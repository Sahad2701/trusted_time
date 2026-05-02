import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'models.dart';
import 'anchor_store.dart';
import 'exceptions.dart';
import 'integrity_event.dart';
import 'integrity_monitor.dart';
import 'monotonic_clock.dart';
import 'sync_engine.dart';
import 'sources/nts_source.dart';
import 'infra/sync_observer.dart';
import 'infra/consensus_cache.dart';
import 'trusted_time_estimate.dart';
import 'trusted_time_mock.dart';

/// Internal engine managing state, synchronization, and hardware anchoring.
final class TrustedTimeImpl {
  TrustedTimeImpl._({
    required TrustedTimeConfig config,
    required AnchorStore store,
    required MonotonicClock clock,
  })  : _config = config,
        _store = store,
        _cache = ConsensusCache(),
        _syncEngine = SyncEngine(
          config: config,
          clock: clock,
          cache: ConsensusCache(),
          observer: _ProxySyncObserver(() => _instance?._observers ?? {}),
        ),
        _monitor = IntegrityMonitor(clock: clock);

  static TrustedTimeImpl? _instance;

  static TrustedTimeImpl get instance {
    assert(_instance != null, 'Call TrustedTime.initialize() first.');
    return _instance!;
  }

  static Future<TrustedTimeImpl> init(TrustedTimeConfig config) async {
    _instance?.dispose();
    final impl = TrustedTimeImpl._(
      config: config,
      store: AnchorStore(),
      clock: PlatformMonotonicClock(),
    );
    await impl._bootstrap();
    _instance = impl;
    _bgChannel.setMethodCallHandler(impl._handleBackgroundMethodCall);
    return impl;
  }

  final TrustedTimeConfig _config;
  final AnchorStore _store;
  final SyncEngine _syncEngine;
  final IntegrityMonitor _monitor;
  final ConsensusCache _cache;
  final _observers = <SyncObserver>{};

  TrustAnchor? _anchor;
  bool _trusted = false;
  Timer? _refreshTimer;
  Timer? _retryTimer;
  Timer? _desktopBgTimer;
  StreamSubscription<IntegrityEvent>? _integritySub;
  Completer<void>? _syncInProgress;
  int? _offlineLastUtcMs;
  int? _offlineLastWallMs;

  Stream<IntegrityEvent> get onIntegrityLost => _monitor.events;
  bool get isTrusted => _trusted;

  /// The currently active trust anchor.
  TrustAnchor? get anchor => _anchor;

  /// Whether the current trust anchor is cryptographically secure.
  bool get isSecure => _anchor?.authLevel == NtsAuthLevel.fullyAuthenticated;

  /// The specific authentication level of the current time estimate.
  NtsAuthLevel get authLevel => _anchor?.authLevel ?? NtsAuthLevel.none;

  /// Registers an observer for synchronization events.
  void registerObserver(SyncObserver observer) => _observers.add(observer);

  /// Unregisters a synchronization observer.
  void unregisterObserver(SyncObserver observer) => _observers.remove(observer);

  /// Returns the current trusted UTC time. Synchronous — no I/O.
  DateTime now() {
    if (!_trusted || _anchor == null) {
      throw const TrustedTimeNotReadyException();
    }
    return DateTime.fromMillisecondsSinceEpoch(
      _anchor!.networkUtcMs + SyncClock.elapsedSinceAnchorMs(),
      isUtc: true,
    );
  }

  int nowUnixMs() => now().millisecondsSinceEpoch;
  String nowIso() => now().toIso8601String();

  TrustedTimeEstimate? nowEstimated() {
    int? baseUtcMs;
    int? baseWallMs;

    if (_anchor != null) {
      baseUtcMs = _anchor!.networkUtcMs;
      baseWallMs = _anchor!.wallMs;
    } else if (_offlineLastUtcMs != null && _offlineLastWallMs != null) {
      baseUtcMs = _offlineLastUtcMs;
      baseWallMs = _offlineLastWallMs;
    } else {
      return null;
    }

    final currentTime = testOverride != null ? testOverride!.now : DateTime.now();
    final wallElapsed = Duration(
      milliseconds: currentTime.millisecondsSinceEpoch - baseWallMs!,
    );
    final confidence = (1.0 - wallElapsed.inMinutes.abs() / 4320.0).clamp(0.0, 1.0);
    final errorMs = (wallElapsed.inMilliseconds.abs() * _config.oscillatorDriftFactor).round();

    return TrustedTimeEstimate(
      estimatedTime: DateTime.fromMillisecondsSinceEpoch(
        baseUtcMs! + wallElapsed.inMilliseconds,
        isUtc: true,
      ),
      confidence: confidence,
      estimatedError: Duration(milliseconds: errorMs),
    );
  }

  Future<void> forceResync() async {
    _trusted = false;
    await _performSync();
  }

  Future<void> enableBackgroundSync(Duration interval) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      if (kDebugMode && interval.inHours < 1) {
        debugPrint('[TrustedTime] Background sync interval below 1h; clamped.');
      }
      await _invokeBackgroundSync(interval);
    } else {
      _desktopBgTimer?.cancel();
      _desktopBgTimer = Timer.periodic(interval, (_) => _performSync());
    }
  }

  Future<void> _bootstrap() async {
    _listenForIntegrityEvents();

    if (_config.persistState) {
      final lastKnown = await _store.loadLastKnown();
      if (lastKnown != null) {
        _offlineLastUtcMs = lastKnown.trustedUtcMs;
        _offlineLastWallMs = lastKnown.wallMs;
      }
    }

    final persisted = _config.persistState ? await _store.load() : null;
    if (persisted != null) {
      final rebooted = await _monitor.checkRebootOnWarmStart(persisted);
      if (!rebooted) {
        _applyAnchor(persisted);
        _trusted = true;
        _scheduleRefresh();
        if (_config.backgroundSyncInterval != null) {
          await enableBackgroundSync(_config.backgroundSyncInterval!);
        }
        return;
      }
    }

    await _performSync();
    if (_config.backgroundSyncInterval != null) {
      await enableBackgroundSync(_config.backgroundSyncInterval!);
    }
  }

  /// Whether the host platform supports cryptographically secure time (NTS).
  bool get supportsSecureTime => _config.ntsServers.isNotEmpty;

  void _listenForIntegrityEvents() {
    _integritySub?.cancel();
    _integritySub = _monitor.events.listen((event) {
      if (event.reason == TamperReason.systemClockJumped ||
          event.reason == TamperReason.deviceRebooted) {
        _trusted = false;
        _cache.clear(); // #28: Immediate cache invalidation on anomaly
        _performSync(); // #28: Immediate feedback loop re-sync
      }
    });
  }

  Future<void> _performSync() async {
    if (_syncInProgress != null) return _syncInProgress!.future;
    final completer = Completer<void>();
    _syncInProgress = completer;
    _retryTimer?.cancel();
    try {
      final anchor = await _syncEngine.sync();
      _applyAnchor(anchor);
      if (_config.persistState) await _store.save(anchor);
      _trusted = true;
      _offlineLastUtcMs = anchor.networkUtcMs;
      _offlineLastWallMs = anchor.wallMs;
      _scheduleRefresh();
    } catch (e) {
      if (kDebugMode) debugPrint('[TrustedTime] Sync failed: $e');
      _trusted = false;
      _scheduleRetry();
    } finally {
      _syncInProgress = null;
      completer.complete();
    }
  }

  void _applyAnchor(TrustAnchor anchor) {
    _anchor = anchor;
    SyncClock.update(anchor.uptimeMs, anchor.wallMs);
    _monitor.attach(anchor);
  }

  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_config.refreshInterval, _performSync);
  }

  void _scheduleRetry() {
    _retryTimer?.cancel();
    final delay = _syncEngine.getNextRetryDelay();
    if (delay > Duration.zero) {
      _retryTimer = Timer(delay, _performSync);
    }
  }

  static const _bgChannel = MethodChannel('trusted_time/background');

  Future<void> _invokeBackgroundSync(Duration interval) async {
    try {
      await _bgChannel.invokeMethod<void>('enableBackgroundSync', {
        'intervalHours': interval.inHours.clamp(1, 168),
      });
    } catch (e) {
      if (kDebugMode) debugPrint('[TrustedTime] Background sync failed: $e');
    }
  }

  Future<void> _handleBackgroundMethodCall(MethodCall call) async {
    if (call.method == 'onBackgroundSync') await _performSync();
  }

  void dispose() {
    _refreshTimer?.cancel();
    _retryTimer?.cancel();
    _desktopBgTimer?.cancel();
    _integritySub?.cancel();
    _syncEngine.dispose();
    _monitor.dispose();
    SyncClock.reset();
  }
}

class _ProxySyncObserver implements SyncObserver {
  _ProxySyncObserver(this._getObservers);
  final Set<SyncObserver> Function() _getObservers;

  @override
  void onSyncStarted() {
    for (final o in _getObservers()) o.onSyncStarted();
  }

  @override
  void onSampleReceived(TimeSample sample) {
    for (final o in _getObservers()) o.onSampleReceived(sample);
  }

  @override
  void onSourceFailed(String sourceId, Object error) {
    for (final o in _getObservers()) o.onSourceFailed(sourceId, error);
  }

  @override
  void onConsensusReached(ConsensusResult result) {
    for (final o in _getObservers()) o.onConsensusReached(result);
  }

  @override
  void onSyncFailed(Object error) {
    for (final o in _getObservers()) o.onSyncFailed(error);
  }
}
