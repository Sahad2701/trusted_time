import 'package:flutter/foundation.dart';

/// Represents a verified point-in-time anchor pinned to hardware uptime.
///
/// A [TrustAnchor] captures the precise relationship between network-verified
/// UTC time and the device's monotonic uptime clock at the moment of
/// synchronization. This relationship is the foundation for all subsequent
/// tamper-proof time calculations:
///
/// ```
/// trustedNow = networkUtcMs + (currentUptime - uptimeMs)
/// ```
///
/// Because monotonic uptime cannot be manipulated by the user, the anchor
/// remains valid until the device reboots (which resets the uptime counter).
@immutable
final class TrustAnchor {
  /// Creates a new trust anchor from a successful network synchronization.
  ///
  /// All values are in milliseconds since their respective epochs:
  /// - [networkUtcMs]: Unix epoch (1970-01-01T00:00:00Z)
  /// - [uptimeMs]: Device boot time
  /// - [wallMs]: Unix epoch (device's local wall clock at sync time)
  const TrustAnchor({
    required this.networkUtcMs,
    required this.uptimeMs,
    required this.wallMs,
    required this.uncertaintyMs,
  });

  /// The verified UTC time from network consensus, in milliseconds since
  /// the Unix epoch.
  final int networkUtcMs;

  /// The device's monotonic uptime at the moment of synchronization, in
  /// milliseconds since boot.
  ///
  /// This value is immune to system clock manipulation and only resets on
  /// device reboot.
  final int uptimeMs;

  /// The device's wall-clock time at the moment of synchronization, in
  /// milliseconds since the Unix epoch.
  ///
  /// Used for elapsed-time calculations and offline estimation. Unlike
  /// [uptimeMs], this value can be manipulated by the user.
  final int wallMs;

  /// The estimated uncertainty of the network time measurement, in
  /// milliseconds.
  ///
  /// Derived from the Marzullo intersection width — smaller values indicate
  /// higher confidence in the anchor's accuracy.
  final int uncertaintyMs;

  /// Returns the [networkUtcMs] as a UTC [DateTime].
  DateTime get networkUtc =>
      DateTime.fromMillisecondsSinceEpoch(networkUtcMs, isUtc: true);

  /// Creates a copy of this anchor with an updated [uncertaintyMs].
  TrustAnchor copyWith({int? uncertaintyMs}) => TrustAnchor(
    networkUtcMs: networkUtcMs,
    uptimeMs: uptimeMs,
    wallMs: wallMs,
    uncertaintyMs: uncertaintyMs ?? this.uncertaintyMs,
  );

  /// Serializes this anchor to a JSON-compatible map for secure storage.
  Map<String, dynamic> toJson() => {
    'networkUtcMs': networkUtcMs,
    'uptimeMs': uptimeMs,
    'wallMs': wallMs,
    'uncertaintyMs': uncertaintyMs,
  };

  /// Deserializes a [TrustAnchor] from a JSON map.
  ///
  /// Throws if any required key is missing or has an incorrect type.
  factory TrustAnchor.fromJson(Map<String, dynamic> j) => TrustAnchor(
    networkUtcMs: j['networkUtcMs'] as int,
    uptimeMs: j['uptimeMs'] as int,
    wallMs: j['wallMs'] as int,
    uncertaintyMs: j['uncertaintyMs'] as int,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrustAnchor &&
          networkUtcMs == other.networkUtcMs &&
          uptimeMs == other.uptimeMs &&
          wallMs == other.wallMs &&
          uncertaintyMs == other.uncertaintyMs;

  @override
  int get hashCode =>
      Object.hash(networkUtcMs, uptimeMs, wallMs, uncertaintyMs);

  @override
  String toString() =>
      'TrustAnchor(utc: $networkUtcMs, uptime: $uptimeMs, '
      'wall: $wallMs, uncertainty: ±${uncertaintyMs}ms)';
}

/// Contract for implementing custom time-authority providers.
///
/// Implement this interface to add enterprise or custom time sources
/// (e.g., a company-internal NTP server or a proprietary time API)
/// to the TrustedTime consensus pool.
///
/// ```dart
/// class MyTimeSource implements TrustedTimeSource {
///   @override
///   String get id => 'my-company-ntp';
///
///   @override
///   Future<DateTime> queryUtc() async {
///     // Query your time authority and return UTC.
///   }
/// }
/// ```
abstract interface class TrustedTimeSource {
  /// A unique identifier for this source, used in debug logging and
  /// consensus weighting (e.g., `'ntp:time.google.com'`).
  String get id;

  /// Queries the remote time authority and returns the current UTC time.
  ///
  /// Implementations should throw on failure rather than returning stale
  /// or estimated values — the sync engine handles failures gracefully.
  Future<DateTime> queryUtc();
}

/// Immutable configuration for the TrustedTime engine.
///
/// All parameters have sensible defaults for most applications. Pass a
/// custom [TrustedTimeConfig] to [TrustedTime.initialize] to tune behavior
/// for specific requirements.
///
/// ```dart
/// await TrustedTime.initialize(
///   config: TrustedTimeConfig(
///     refreshInterval: Duration(hours: 6),
///     minimumQuorum: 3,
///   ),
/// );
/// ```
@immutable
final class TrustedTimeConfig {
  /// Creates a new configuration with the given parameters.
  ///
  /// All parameters are optional and fall back to production-safe defaults.
  const TrustedTimeConfig({
    this.refreshInterval = const Duration(hours: 12),
    this.ntpServers = const [
      'time.google.com',
      'time.cloudflare.com',
      'pool.ntp.org',
    ],
    this.httpsSources = const [
      'https://www.google.com',
      'https://www.cloudflare.com',
    ],
    this.maxLatency = const Duration(seconds: 3),
    this.minimumQuorum = 2,
    this.persistState = true,
    this.additionalSources = const [],
    this.oscillatorDriftFactor = 0.00005,
    this.backgroundSyncInterval,
  });

  /// How often the engine re-validates its anchor against network sources.
  ///
  /// Defaults to 12 hours. Shorter intervals increase accuracy but use
  /// more network bandwidth.
  final Duration refreshInterval;

  /// NTP server hostnames to query via UDP.
  ///
  /// At least [minimumQuorum] servers should be listed for reliable
  /// consensus. Defaults to Google, Cloudflare, and pool.ntp.org.
  final List<String> ntpServers;

  /// HTTPS URLs whose `Date` headers are used as a fallback time source.
  ///
  /// This provides a universal fallback for environments where UDP (NTP)
  /// traffic is blocked (e.g., corporate firewalls).
  final List<String> httpsSources;

  /// Maximum acceptable round-trip latency for a single source query.
  ///
  /// Responses exceeding this threshold are discarded as too noisy.
  /// Defaults to 3 seconds.
  final Duration maxLatency;

  /// Minimum number of agreeing sources required to establish consensus.
  ///
  /// Must be ≥ 2 for meaningful tamper resistance. The engine will throw
  /// [TrustedTimeSyncException] if fewer sources agree.
  final int minimumQuorum;

  /// Whether to persist the trust anchor in secure storage.
  ///
  /// When `true`, the anchor survives app restarts without requiring
  /// a fresh network sync (unless a device reboot is detected).
  final bool persistState;

  /// Additional custom [TrustedTimeSource] implementations to include
  /// in the consensus pool alongside the built-in NTP and HTTPS sources.
  final List<TrustedTimeSource> additionalSources;

  /// Estimated local oscillator drift rate in ms/ms.
  ///
  /// Used to calculate error bounds for offline time estimation.
  /// The default value of `0.00005` (50 ppm) is conservative for
  /// typical mobile device quartz oscillators.
  final double oscillatorDriftFactor;

  /// Optional interval for automatic background synchronization.
  ///
  /// When set, the engine registers OS-level background tasks
  /// (WorkManager on Android, BGTaskScheduler on iOS) to refresh the
  /// anchor periodically even when the app is not in the foreground.
  final Duration? backgroundSyncInterval;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrustedTimeConfig &&
          refreshInterval == other.refreshInterval &&
          maxLatency == other.maxLatency &&
          minimumQuorum == other.minimumQuorum &&
          persistState == other.persistState &&
          oscillatorDriftFactor == other.oscillatorDriftFactor &&
          backgroundSyncInterval == other.backgroundSyncInterval;

  @override
  int get hashCode => Object.hash(
    refreshInterval,
    maxLatency,
    minimumQuorum,
    persistState,
    oscillatorDriftFactor,
    backgroundSyncInterval,
  );
}
