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
import 'trusted_time_estimate.dart';
import 'trusted_time_mock.dart';

/// Internal engine managing state, synchronization, and hardware anchoring.
///
/// This is the private implementation behind the [TrustedTime] public API.
/// It manages the lifecycle of the trust anchor, periodic refresh timers,
/// integrity monitoring, and offline estimation.
///
/// Access via [TrustedTimeImpl.instance] after calling [TrustedTimeImpl.init].
final class TrustedTimeImpl {
  TrustedTimeImpl._({
    required TrustedTimeConfig config,
    required AnchorStore store,
    required MonotonicClock clock,
  }) : _config = config,
       _store = store,
       _syncEngine = SyncEngine(config: config, clock: clock),
       _monitor = IntegrityMonitor(clock: clock);

  static TrustedTimeImpl? _instance;

  /// Returns the active singleton instance.
  ///
  /// Asserts that [init] has been called first.
  static TrustedTimeImpl get instance {
    assert(_instance != null, 'Call TrustedTime.initialize() first.');
    return _instance!;
  }

  /// Initializes the singleton with the given [config].
  ///
  /// Disposes any previous instance before creating a new one. Runs the
  /// cold-start bootstrap sequence (load persisted anchor, detect reboot,
  /// perform initial sync if needed).
  static Future<TrustedTimeImpl> init(TrustedTimeConfig config) async {
    _instance?.dispose();
    final impl = TrustedTimeImpl._(
      config: config,
      store: AnchorStore(),
      clock: PlatformMonotonicClock(),
    );
    await impl._bootstrap();
    _instance = impl;
    return impl;
  }

  final TrustedTimeConfig _config;
  final AnchorStore _store;
  final SyncEngine _syncEngine;
  final IntegrityMonitor _monitor;

  TrustAnchor? _anchor;
  bool _trusted = false;
  Timer? _refreshTimer;
  int? _offlineLastUtcMs;
  int? _offlineLastWallMs;

  /// Stream of integrity violation events (clock jumps, reboots, etc.).
  Stream<IntegrityEvent> get onIntegrityLost => _monitor.events;

  /// Whether the engine currently holds a valid trust anchor.
  bool get isTrusted => _trusted;

  /// Returns the current trusted UTC time.
  ///
  /// Synchronous, <1µs — no I/O. Uses the cached wall-clock delta from the
  /// last successful sync to compute the current time.
  ///
  /// Throws [TrustedTimeNotReadyException] if no anchor is active.
  DateTime now() {
    if (!_trusted || _anchor == null) {
      throw const TrustedTimeNotReadyException();
    }
    return DateTime.fromMillisecondsSinceEpoch(
      _anchor!.networkUtcMs + SyncClock.elapsedSinceAnchorMs(),
      isUtc: true,
    );
  }

  /// Returns the current trusted Unix timestamp in milliseconds.
  int nowUnixMs() => now().millisecondsSinceEpoch;

  /// Returns the current trusted time as an ISO-8601 string.
  String nowIso() => now().toIso8601String();

  /// Estimates UTC when offline. **NOT tamper-proof.**
  ///
  /// Returns `null` if no anchor or last-known values are available.
  /// Confidence decays linearly to 0 over 72 hours.
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

    final currentTime = testOverride != null
        ? testOverride!.now
        : DateTime.now();
    final wallElapsed = Duration(
      milliseconds: currentTime.millisecondsSinceEpoch - baseWallMs!,
    );

    // Confidence decays linearly to 0 over 72 hours (4320 minutes).
    final confidence = (1.0 - wallElapsed.inMinutes.abs() / 4320.0).clamp(
      0.0,
      1.0,
    );
    // Absolute error = elapsed time × estimated oscillator skew.
    final errorMs =
        (wallElapsed.inMilliseconds.abs() * _config.oscillatorDriftFactor)
            .round();

    return TrustedTimeEstimate(
      estimatedTime: DateTime.fromMillisecondsSinceEpoch(
        baseUtcMs! + wallElapsed.inMilliseconds,
        isUtc: true,
      ),
      confidence: confidence,
      estimatedError: Duration(milliseconds: errorMs),
    );
  }

  /// Triggers an immediate network re-sync.
  ///
  /// Temporarily marks the engine as untrusted until the sync completes
  /// and a new anchor is established.
  Future<void> forceResync() async {
    _trusted = false;
    await _performSync();
  }

  /// Registers OS-level background tasks for periodic anchor refreshing.
  ///
  /// On mobile, uses WorkManager (Android) or BGTaskScheduler (iOS).
  /// On desktop, falls back to a Dart [Timer.periodic].
  /// On web, background syncing is not supported (browsers suspend tabs).
  Future<void> enableBackgroundSync(Duration interval) async {
    if (kIsWeb) return;
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      await _invokeBackgroundSync(interval);
    } else {
      Timer.periodic(interval, (_) => _performSync());
    }
  }

  // ── Private lifecycle methods ──────────────────────────────────────

  /// Cold-start bootstrap: loads persisted state and detects reboots.
  Future<void> _bootstrap() async {
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
        return;
      }
    }

    await _performSync();
    if (_config.backgroundSyncInterval != null) {
      await enableBackgroundSync(_config.backgroundSyncInterval!);
    }
  }

  /// Performs a full network sync and establishes a new anchor.
  Future<void> _performSync() async {
    try {
      final anchor = await _syncEngine.sync();
      _applyAnchor(anchor);
      if (_config.persistState) await _store.save(anchor);
      _trusted = true;
      _offlineLastUtcMs = anchor.networkUtcMs;
      _offlineLastWallMs = anchor.wallMs;
      _scheduleRefresh();
    } catch (e) {
      debugPrint('[TrustedTime] Sync failed: $e');
      _trusted = false;
    }
  }

  /// Pins a fresh anchor and updates all dependent subsystems.
  void _applyAnchor(TrustAnchor anchor) {
    _anchor = anchor;
    SyncClock.update(anchor.uptimeMs, anchor.wallMs);
    _monitor.attach(anchor);
  }

  /// Schedules the next periodic refresh.
  void _scheduleRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(_config.refreshInterval, _performSync);
  }

  static const _bgChannel = MethodChannel('trusted_time/background');

  /// Invokes native background sync registration.
  Future<void> _invokeBackgroundSync(Duration interval) async {
    try {
      await _bgChannel.invokeMethod<void>('enableBackgroundSync', {
        'intervalHours': interval.inHours.clamp(1, 168),
      });
    } catch (e) {
      debugPrint('[TrustedTime] Background sync registration failed: $e');
    }
  }

  /// Releases all resources: timers, monitoring streams, and HTTP clients.
  void dispose() {
    _refreshTimer?.cancel();
    _syncEngine.dispose();
    _monitor.dispose();
  }
}

// ── Test Override Management ─────────────────────────────────────────

TrustedTimeMock? _testOverride;

/// Configures the global test mock override.
///
/// Only available in debug/test builds (guarded by [assert]).
void setTestOverride(TrustedTimeMock? mock) {
  assert(() {
    _testOverride = mock;
    return true;
  }(), 'overrideForTesting is only available in debug/test builds.');
}

/// Returns the active test mock, if configured.
TrustedTimeMock? get testOverride => _testOverride;
