/// TrustedTime — The absolute source of truth for high-integrity time in Flutter.
///
/// This library provides cryptographically-aware, hardware-anchored UTC timestamps 
/// that remain accurate even in adversarial environments where the system clock 
/// is manipulated or network time is spoofed.
///
/// ## Core Concepts
///
/// * **Monotonic Anchoring**: We anchor network-verified time to the device's 
///   hardware oscillator (monotonic uptime). This creates a virtual clock that 
///   cannot be rolled back or forward by the user.
/// * **Consensus (Marzullo)**: We use multi-source quorum resolution to filter 
///   out noisy or malicious time authorities.
/// * **Security Intent**: Explicit distinction between "Trusted" (consensus-valid) 
///   and "Secure" (NTS-authenticated) time.
///
/// ## Usage Patterns
///
/// ```dart
/// // Standard high-integrity retrieval
/// final now = TrustedTime.now();
///
/// // Security-critical query (e.g. financial ledgering)
/// final secureNow = TrustedTime.getTime(requireSecure: true);
/// ```
library;

import 'dart:async';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'src/exceptions.dart';
import 'src/integrity_event.dart';
import 'src/models.dart';
import 'src/trusted_time_estimate.dart';
import 'src/trusted_time_impl.dart';
import 'src/trusted_time_mock.dart';

export 'src/exceptions.dart';
export 'src/integrity_event.dart';
export 'src/models.dart' show TrustedTimeConfig, TrustAnchor;
export 'src/trusted_time_estimate.dart';
export 'src/trusted_time_mock.dart';
export 'src/infra/sync_observer.dart';
export 'src/sources/nts_source.dart' show NtsAuthLevel;
export 'src/domain/time_sample.dart' show TimeSample;
export 'src/domain/marzullo_engine.dart' show ConsensusResult;
export 'src/domain/time_interval.dart' show TimeInterval;
export 'src/models.dart' show ConfidenceLevel, SyncMetrics;

/// The primary gateway for high-integrity time synchronization and retrieval.
///
/// [TrustedTime] implements a self-healing operational state machine. It handles 
/// initial synchronization, background maintenance, and proactive drift detection.
///
/// For most use cases, [now] is the preferred retrieval method. For high-security 
/// applications, use [getTime] to enforce specific cryptographic or confidence 
/// requirements.
abstract final class TrustedTime {
  TrustedTime._();

  static bool _timezoneInitialized = false;

  /// Bootstraps the time integrity subsystem.
  ///
  /// This must be called at app launch. It performs several critical actions:
  /// 1. Initializes the embedded IANA timezone database.
  /// 2. Restores the last known trust anchor from secure storage.
  /// 3. Launches the initial network synchronization cycle.
  ///
  /// ```dart
  /// void main() async {
  ///   WidgetsFlutterBinding.ensureInitialized();
  ///   await TrustedTime.initialize(); // Essential first step
  ///   runApp(MyApp());
  /// }
  /// ```
  static Future<void> initialize({
    TrustedTimeConfig config = const TrustedTimeConfig(),
  }) async {
    if (!_timezoneInitialized) {
      tz.initializeTimeZones();
      _timezoneInitialized = true;
    }

    // In a testing context, we skip hardware and network orchestration 
    // to keep tests hermetic and reproducible.
    if (_override != null) return;

    await TrustedTimeImpl.init(config);
  }

  /// Synchronously returns the current trusted UTC time.
  ///
  /// This operation is optimized for performance, typically completing in **<1µs**. 
  /// It performs a simple arithmetic projection based on the active hardware anchor 
  /// and does not involve any platform channel or I/O overhead.
  ///
  /// Throws [TrustedTimeNotReadyException] if called before the engine has established 
  /// its initial trust anchor.
  static DateTime now() {
    if (_override != null) return _override!.now;
    return TrustedTimeImpl.instance.now();
  }

  /// Returns the current trusted Unix timestamp (milliseconds since epoch).
  ///
  /// High-performance variant of [now] that avoids the overhead of [DateTime] 
  /// object instantiation. Recommended for high-frequency audit logging or 
  /// real-time security signatures.
  static int nowUnixMs() {
    if (_override != null) return _override!.nowUnixMs;
    return TrustedTimeImpl.instance.nowUnixMs();
  }

  /// Returns the current trusted time in ISO-8601 format.
  ///
  /// Optimized for transmission over network protocols or persistent logging.
  /// Example: `2024-05-02T12:00:00.000Z`
  static String nowIso() {
    if (_override != null) return _override!.nowIso;
    return TrustedTimeImpl.instance.nowIso();
  }

  /// Returns `true` if the engine has successfully established a consensus-based 
  /// trust anchor.
  ///
  /// When this is `false`, [now] will throw. This state occurs during initial 
  /// synchronization or after a critical integrity failure (e.g. a device reboot).
  static bool get isTrusted {
    if (_override != null) return _override!.isTrusted;
    return TrustedTimeImpl.instance.isTrusted;
  }

  /// Returns the qualitative confidence grade of the current trust anchor.
  ///
  /// A [ConfidenceLevel.high] grade indicates a consensus reached with high 
  /// source diversity and depth, whereas [ConfidenceLevel.low] may indicate 
  /// a valid but geographically or provider-limited consensus.
  static ConfidenceLevel get confidence {
    if (_override != null) return ConfidenceLevel.high;
    return TrustedTimeImpl.instance.anchor?.confidence ?? ConfidenceLevel.low;
  }

  /// Returns a probabilistic "freshness" score (0.0 to 1.0).
  ///
  /// This score models the temporal uncertainty of the anchor. It decays 
  /// exponentially as the anchor ages. High-value transactions should check 
  /// this score and potentially trigger a [forceResync] if it falls below 
  /// an application-defined threshold (e.g. 0.5).
  static double get confidenceScore {
    if (_override != null) return 1.0;
    return TrustedTimeImpl.instance.anchor?.confidenceScore ?? 0.0;
  }

  /// Advanced retrieval that enforces specific security and integrity constraints.
  ///
  /// Use this when your application logic requires higher guarantees than 
  /// standard consensus.
  ///
  /// * Set [requireSecure] to `true` to force a fail-fast error if NTS 
  ///   cryptographic authentication is unavailable.
  /// * Set [minConfidence] to enforce a minimum qualitative trust level.
  ///
  /// Throws [TrustedTimeSecurityException] if requirements are not met.
  static DateTime getTime({
    bool requireSecure = false,
    ConfidenceLevel minConfidence = ConfidenceLevel.low,
  }) {
    if (_override != null) return now();
    final impl = TrustedTimeImpl.instance;
    
    if (requireSecure && !impl.isSecure) {
      throw const TrustedTimeSecurityException(
        'NTS-authenticated time is required but unavailable in the current session.'
      );
    }
    
    final currentConfidence = impl.anchor?.confidence ?? ConfidenceLevel.low;
    if (currentConfidence.index < minConfidence.index) {
      throw TrustedTimeSecurityException(
        'Confidence level ${currentConfidence.name} is below required ${minConfidence.name}.'
      );
    }
    
    return now();
  }

  /// Returns `true` if the system is configured to support Network Time 
  /// Security (NTS).
  static bool get supportsSecureTime {
    if (_override != null) return false;
    return TrustedTimeImpl.instance.supportsSecureTime;
  }

  /// Emits events when the engine detects potential temporal tampering.
  ///
  /// The engine proactively monitors for Monotonic-to-Wall drift. If a 
  /// system clock jump or device reboot is detected, this stream will 
  /// emit an event, and the engine will automatically enter a recovery 
  /// cycle (cache invalidation + immediate resync).
  static Stream<IntegrityEvent> get onIntegrityLost {
    if (_override != null) return _override!.onIntegrityLost;
    return TrustedTimeImpl.instance.onIntegrityLost;
  }

  /// Indicates if the current trust anchor is backed by cryptographic 
  /// authentication (NTS/RFC 8915).
  static bool get isSecure {
    if (_override != null) return false;
    return TrustedTimeImpl.instance.isSecure;
  }

  /// Exposes the specific cryptographic authentication level achieved during sync.
  static NtsAuthLevel get authLevel {
    if (_override != null) return NtsAuthLevel.none;
    return TrustedTimeImpl.instance.authLevel;
  }

  /// Hooks into the internal synchronization lifecycle.
  ///
  /// Register a [SyncObserver] to receive machine-readable [SyncMetrics], 
  /// including latency, uncertainty, and consensus participant counts. 
  /// Useful for enterprise-grade telemetry and observability.
  static void registerObserver(SyncObserver observer) {
    if (_override != null) return;
    TrustedTimeImpl.instance.registerObserver(observer);
  }

  /// Detaches a previously registered [SyncObserver].
  static void unregisterObserver(SyncObserver observer) {
    if (_override != null) return;
    TrustedTimeImpl.instance.unregisterObserver(observer);
  }

  /// Best-effort time estimation for offline or unanchored scenarios.
  ///
  /// Returns a [TrustedTimeEstimate] extrapolated from the last known state. 
  /// **WARNING**: This estimate is susceptible to wall-clock manipulation. 
  /// Use only for non-critical UI hints when [isTrusted] is false.
  static TrustedTimeEstimate? nowEstimated() {
    if (_override != null) return _override!.nowEstimated();
    return TrustedTimeImpl.instance.nowEstimated();
  }

  /// Forces an immediate network synchronization cycle.
  ///
  /// This purges the current anchor and forces the engine into an active 
  /// sampling phase. Useful for recovering from an integrity loss or 
  /// manually refreshing an aged anchor.
  static Future<void> forceResync() {
    if (_override != null) return Future.value();
    return TrustedTimeImpl.instance.forceResync();
  }

  /// Schedules OS-level background tasks to keep the trust anchor fresh.
  ///
  /// Leverages platform-native schedulers (WorkManager on Android, 
  /// BGTaskScheduler on iOS/macOS) to perform periodic maintenance 
  /// while the app is backgrounded.
  static Future<void> enableBackgroundSync({
    Duration interval = const Duration(hours: 24),
  }) {
    if (_override != null) return Future.value();
    return TrustedTimeImpl.instance.enableBackgroundSync(interval);
  }

  /// Returns trusted local time in the specified IANA timezone.
  ///
  /// Converts the trusted UTC time to the target timezone using the 
  /// embedded IANA database. This ensures the result is immune to 
  /// device-level timezone manipulation.
  ///
  /// Throws [UnknownTimezoneException] if the [timezoneIdentifier] 
  /// is not found in the database.
  static DateTime trustedLocalTimeIn(String timezoneIdentifier) {
    if (!isTrusted) throw const TrustedTimeNotReadyException();
    tz.Location location;
    try {
      location = tz.getLocation(timezoneIdentifier);
    } catch (_) {
      throw UnknownTimezoneException(timezoneIdentifier);
    }
    return tz.TZDateTime.from(now(), location);
  }

  /// Injects a mock implementation for hermetic unit and widget testing.
  ///
  /// Under an override, all static methods of [TrustedTime] delegate to the 
  /// mock, ensuring tests are deterministic and network-independent.
  static void overrideForTesting(TrustedTimeMock mock) {
    setTestOverride(mock);
  }

  /// Restores standard production behavior by removing any active mock override.
  static void resetOverride() {
    setTestOverride(null);
  }

  static TrustedTimeMock? get _override => testOverride;
}
