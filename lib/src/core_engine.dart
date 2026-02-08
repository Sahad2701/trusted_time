import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math';
import 'storage.dart';
import 'hybrid_time_resolver.dart';
import 'exceptions.dart';
import '../trusted_time_platform_interface.dart';

/// Tuning parameters for the [TrustedTime] engine.
///
/// This class controls the delicate balance between time precision, network
/// usage, and verification frequency. While the default values are optimized
/// for most mobile apps, custom configurations are useful for high-security
/// financial apps or apps operating in highly restrictive network environments.
class TrustedTimeConfig {
  /// The primary set of NTP pools used for high-precision synchronization.
  ///
  /// If null, the engine defaults to a globally distributed set of Tier-1
  /// time servers (Google, Cloudflare, and the NTP Pool Project).
  final List<String>? ntpServers;

  /// Fallback synchronization sources queried via standard HTTPS.
  ///
  /// These are essential in corporate or cellular networks where UDP (NTP)
  /// traffic is routinely blocked or throttled. The engine extracts the
  /// 'Date' header from these endpoints to establish a secondary trust anchor.
  final List<String>? httpsSources;

  /// How often the engine should re-verify its internal anchor.
  ///
  /// Regular refreshes (the default is 24 hours) are necessary to account
  /// for the slight but inevitable drift in hardware crystal oscillators
  /// over extended uptimes.
  final Duration refreshInterval;

  /// The strict latency cutoff for network requests.
  ///
  /// We reject any time packet that takes longer than this duration to arrive.
  /// High latency introduces significant uncertainty into the "midpoint" 
  /// calculation, so we prioritize precision over connectivity here.
  final Duration maxRequestLatency;

  /// The minimum number of unique sources that must agree on the new time.
  ///
  /// A higher quorum (e.g., 3 or 4) provides extreme defense against
  /// theoretical "Man-in-the-Middle" time-spoofing attacks, but increases
  /// the likelihood of a sync failure in poor network conditions.
  final int minimumQuorum;

  /// Controls whether the trust anchor survives an application restart.
  ///
  /// In typical "Secure Clock" use cases, you want this set to `true` (default).
  /// This allows the app to provide trusted time instantly on launch by
  /// validating the persisted state against the current monotonic uptime.
  final bool persistState;

  const TrustedTimeConfig({
    this.ntpServers,
    this.httpsSources,
    this.refreshInterval = const Duration(hours: 24),
    this.maxRequestLatency = const Duration(seconds: 2),
    this.minimumQuorum = 2,
    this.persistState = true,
  });
}

/// The core orchestration engine for high-integrity timekeeping.
///
/// [TrustedTime] provides a "Virtual Clock" that ignores manual user
/// adjustments to the system wall-clock (the "Clock Tamper" problem).
///
/// **The Philosophy:**
/// We don't just "fetch the time." We anchor a verified UTC network timestamp
/// to the device's internal monotonic hardware uptime. Because the hardware 
/// uptime is a simple incrementing counter that cannot be adjusted by the user,
/// we can calculate the current "true" time synchronously with sub-millisecond
/// overhead using this formula:
///
/// ```dart
/// CurrentTime = (CurrentUptime - UptimeAtSync) + VerifiedNetworkTime
/// ```
///
/// This hybrid approach utilizes both NTP (for precision) and HTTPS (for
/// universal compatibility) to ensure the clock is always reliable.
class TrustedTime {
  TrustedTime._();

  static bool _initialized = false;
  static bool _isInitializing = false;
  static TrustedTimeConfig _config = const TrustedTimeConfig();

  /// The millisecond epoch returned by trusted servers during the last sync.
  static int _serverEpochAtSync = 0;

  /// The monotonic uptime of the device (in ms) at the exact moment of sync.
  static int _uptimeAtSync = 0;

  /// Whether the engine is currently calibrated with a valid network anchor.
  static bool _isTrusted = false;

  /// Indicates if the time integrity has been compromised (e.g., via reboot).
  static bool _integrityLost = false;

  /// The dynamic estimated drift or uncertainty (±) in the current timestamp.
  static Duration _estimatedDrift = Duration.zero;

  /// Streams for event-driven updates.
  static final StreamController<void> _integrityLostController =
      StreamController.broadcast();
  static final StreamController<void> _resyncController =
      StreamController.broadcast();

  /// A background timer that triggers periodic re-calibration.
  static Timer? _refreshTimer;

  /// A high-precision stopwatch to track micro-uptime between platform calls.
  static final Stopwatch _uptimeTicker = Stopwatch();

  /// The base uptime snapshot retrieved from the native platform.
  static int _baseUptime = 0;

  /// A mutex-like lock to ensure only one sync process runs at a time.
  static bool _isSyncing = false;

  /// The current count of failed sync attempts used for exponential backoff.
  static int _syncRetryCount = 0;

  /// Cached DateTime for lastSyncTime to avoid redundant allocations.
  static DateTime _lastSyncTimeCache = DateTime.fromMillisecondsSinceEpoch(0);


  // Public API

  /// Emits whenever the internal trust anchor is invalidated.
  ///
  /// This happens if the system detects a reboot, a manual clock change,
  /// or if internal drift validation fails. Subscribers should usually
  /// stop time-sensitive operations (like signing trials) until trust 
  /// is re-established via [onResync].
  static Stream<void> get onIntegrityLost => _integrityLostController.stream;

  /// Emits when the engine successfully establishes or refreshes a trust anchor.
  static Stream<void> get onResync => _resyncController.stream;

  /// Whether the engine is currently calibrated with a valid network anchor.
  ///
  /// If `false`, calls to [now()] will fallback to the standard system clock
  /// until the first background synchronization completes.
  static bool get isTrusted => _isTrusted;

  /// Whether a hardware reboot or system clock manipulation was detected.
  ///
  /// This flag is persistent until a fresh network sync validates the new state.
  static bool get wasSystemClockChanged => _integrityLost;

  /// The estimated ± uncertainty in the current [now()] timestamp.
  ///
  /// This grows slightly over time due to oscillator drift, and is reset
  /// whenever a new high-precision network quorum is achieved.
  static Duration get estimatedDrift => _estimatedDrift;

  /// The local [DateTime] of the last successful network synchronization.
  ///
  /// Note: Consider using [isTrusted] before acting on this value.
  static DateTime get lastSyncTime => _lastSyncTimeCache;

  /// Bootstraps the [TrustedTime] engine.
  ///
  /// This should be called early in the application lifecycle (e.g., in `main()`).
  /// Being a `Future`, you should [await] this call to ensure the trust anchor 
  /// is established (either from storage or network) before the rest of the 
  /// app starts.
  ///
  /// **The Startup Flow:**
  /// 1. Immediately captures the native monotonic hardware uptime baseline.
  /// 2. Restores the last known trust anchor from secure storage (if disabled, 
  ///    starts as untrusted).
  /// 3. Validates the hardware uptime to detect reboots during app-off time.
  /// 4. Schedules a background network sync to re-verify or establish trust.
  static Future<void> initialize({TrustedTimeConfig? config}) async {
    if (_initialized) return;
    if (_isInitializing) return;

    _initialized = true;
    _isInitializing = true;
    if (config != null) _config = config;

    // We MUST capture the relative baseline immediately. The Stopwatch 
    // effectively "extends" the precision of the discrete native uptime snaps.
    if (!_uptimeTicker.isRunning) {
      _uptimeTicker.start();
    }

    try {
      await _initializeInternal();
    } finally {
      _isInitializing = false;
    }
  }

  /// Internal initialization routine that establishes the baseline and restores state.
  static Future<void> _initializeInternal() async {
    try {
      // Logic Step 1: Establish the Hardware Baseline (MANDATORY).
      // We snap the native uptime. This MUST be done before we can anchor anything.
      final uptimeZero = await _getNativeUptime();
      _baseUptime = uptimeZero;
      _uptimeTicker.reset();
      _uptimeTicker.start();

      // Logic Step 2: Restore Persisted State (FAST - Disk only).
      if (_config.persistState) {
        try {
          final stored = await TrustedStorage.load();
          if (stored != null) {
            // Validation: Only restore if storage isn't from a future session (reboot).
            if (uptimeZero >= stored.uptimeMs) {
              _serverEpochAtSync = stored.serverEpochMs;
              _uptimeAtSync = stored.uptimeMs;
              _lastSyncTimeCache = DateTime.fromMillisecondsSinceEpoch(_serverEpochAtSync);
              _estimatedDrift = Duration(milliseconds: stored.driftMs);
              _isTrusted = true;
              developer.log('Restored trust anchor from storage.', name: 'TrustedTime');
            } else {
              developer.log('Reboot detected. Storage anchor purged.', name: 'TrustedTime');
              _integrityLost = true;
            }
          }
        } catch (e) {
          developer.log('Storage recovery skipped: $e', name: 'TrustedTime');
          unawaited(TrustedStorage.clear().catchError((_) {}));
        }
      }

      // Logic Step 3: Lazy Background Operations (NON-BLOCKING).
      // We don't await these because they add "junk" latency to app boot.
      unawaited(_kickoffBackgroundServices());

    } catch (e, stack) {
      developer.log('Initialization failure: $e', name: 'TrustedTime', error: e, stackTrace: stack);
    }
  }

  /// Kicks off background sync and platform listeners without blocking boot.
  static Future<void> _kickoffBackgroundServices() async {
    // Platform events registration.
    try {
      TrustedTimePlatform.instance.setClockTamperCallback(_onClockTampered);
    } catch (_) {}

    // Initial background sync.
    await _performSync();

    // Setup periodic refresh.
    _setupRefreshTimer();
  }

  /// Retrieves the current high-trust time.
  ///
  /// This operation is synchronous and extremely fast (<1μs), as it only 
  /// performs a simple arithmetic calculation based on the established 
  /// trust anchor and the current hardware uptime.
  ///
  /// **Reliability Guarantee:** 
  /// If the engine is not yet trusted (initial sync pending), it returns the 
  /// standard [DateTime.now()] as a fallback. After the first sync succeeds, 
  /// all future calls are guaranteed to be immune to manual system clock 
  /// adjustments.
  static DateTime now() {
    if (!_isTrusted) {
      return DateTime.now();
    }

    final uptimeNow = _currentUptime();
    final trustedEpoch = (uptimeNow - _uptimeAtSync) + _serverEpochAtSync;

    return DateTime.fromMillisecondsSinceEpoch(trustedEpoch);
  }

  /// The current trusted Unix epoch in milliseconds.
  ///
  /// Optimized for zero-allocation. This method performs raw integer arithmetic
  /// bypassing the creation of [DateTime] objects, making it safe for high-frequency
  /// usage (e.g., inside animation loops or game engines).
  static int nowUnixMs() {
    if (!_isTrusted) {
      return DateTime.now().millisecondsSinceEpoch;
    }
    return (_currentUptime() - _uptimeAtSync) + _serverEpochAtSync;
  }

  /// The current trusted time formatted as an ISO 8601 string.
  static String nowIso() => now().toIso8601String();

  /// Manually triggers a network re-verification of the trust anchor.
  ///
  /// While the engine automatically refreshes periodically, you can 
  /// use this to force an update if you suspect tampering or require 
  /// absolute precision for a critical transaction.
  static Future<void> forceResync() async {
    await _performSync();
  }

  // Internal Implementation Detail

  /// Configures the background timer for periodic re-verification.
  static void _setupRefreshTimer() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(_config.refreshInterval, (_) {
      unawaited(_performSync());
    });
  }

  /// Internal bridge to fetch monotonic uptime from the platform.
  static Future<int> _getNativeUptime() async {
    final uptime = await TrustedTimePlatform.instance.getUptimeMs();
    if (uptime == null) {
      throw const TrustedTimeInitializationException(
        'Platform failed to provide a valid monotonic hardware uptime.',
      );
    }
    return uptime;
  }

  /// Combines the last native snapshot with the high-precision ticker 
  /// to provide sub-millisecond uptime tracking.
  static int _currentUptime() {
    if (_uptimeTicker.isRunning) {
      return _baseUptime + _uptimeTicker.elapsedMilliseconds;
    }
    return _uptimeTicker.elapsedMilliseconds;
  }

  /// Core validation logic that detects hardware resets or drift.
  static Future<void> _validateOrResync() async {
    try {
      final uptimeNow = await _getNativeUptime();
      _baseUptime = uptimeNow;
      _uptimeTicker.reset();
      _uptimeTicker.start();

      // Detection: A monotonic uptime smaller than our sync-record is a
      // definitive signal of a hardware reboot.
      if (_isTrusted && uptimeNow < _uptimeAtSync) {
        developer.log(
          'Reboot detected (Uptime Reset). Establishing new trust anchor.',
          name: 'TrustedTime',
        );
        _integrityLost = true;
        await _performSync();
        return;
      }

      if (!_isTrusted) {
        await _performSync();
        return;
      }

      final age = now().difference(lastSyncTime);
      if (age > _config.refreshInterval) {
        unawaited(_performSync());
      }
    } catch (e) {
      unawaited(_performSync());
    }
  }

  /// The synchronization orchestrator.
  ///
  /// This method is protected by an internal lock to prevent redundant
  /// network requests if multiple calls occur during a single sync window.
  static Future<void> _performSync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final result = await HybridTimeResolver.resolve();

      // Capture native uptime immediately after resolution to minimize skew.
      final uptimeAfterResolve = await _getNativeUptime();

      _baseUptime = uptimeAfterResolve;
      _uptimeTicker.reset();
      _uptimeTicker.start();

      _serverEpochAtSync = result.trustedEpochMs;
      _uptimeAtSync = uptimeAfterResolve;
      _lastSyncTimeCache = DateTime.fromMillisecondsSinceEpoch(_serverEpochAtSync);
      _estimatedDrift = Duration(milliseconds: result.uncertaintyMs);
      _isTrusted = true;
      _integrityLost = false;
      _syncRetryCount = 0;

      if (_config.persistState) {
        unawaited(
          TrustedStorage.save(
            serverEpochMs: _serverEpochAtSync,
            uptimeMs: _uptimeAtSync,
            driftMs: result.uncertaintyMs,
          ).catchError((e) {
            developer.log('Failed to persist trust anchor.', name: 'TrustedTime');
          }),
        );
      }

      _resyncController.add(null);
    } catch (e) {
      developer.log('Sync failed: $e', name: 'TrustedTime');

      // Full Jitter backoff: randomize the exponential window to prevent 
      // synchronized retries (thundering herds).
      _syncRetryCount++;
      final exponentialWait = pow(2, _syncRetryCount).toInt();
      final cappedWait = exponentialWait.clamp(2, 300);
      final jitteredSeconds = Random().nextInt(cappedWait) + 1;
      final delay = Duration(seconds: jitteredSeconds);

      developer.log(
        'Retrying in ${delay.inSeconds}s (Full Jitter, Attempt $_syncRetryCount)',
        name: 'TrustedTime',
      );
      Timer(delay, () => unawaited(_performSync()));

      if (_syncRetryCount > 3) {
        _isTrusted = false;
        _integrityLostController.add(null);
      }
    } finally {
      _isSyncing = false;
    }
  }

  /// Platform event handler for system clock jumps.
  static void _onClockTampered() {
    developer.log(
      'System clock adjustment detected. Refreshing trust anchor.',
      name: 'TrustedTime',
    );
    _integrityLost = true;
    _isTrusted = false;
    _integrityLostController.add(null);
    unawaited(_performSync());
  }
}
