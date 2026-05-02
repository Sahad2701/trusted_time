import 'domain/time_source.dart';
import 'domain/time_interval.dart';

/// Qualitative grades of consensus integrity.
enum ConfidenceLevel {
  /// The quorum was achieved, but the participant depth or provider 
  /// diversity is below optimal thresholds.
  low,

  /// A reliable quorum with standard provider diversity was achieved.
  medium,

  /// An elite-tier quorum with high participant depth, wide provider 
  /// diversity, and temporal stability.
  high,
}

/// Machine-readable telemetry for a single synchronization cycle.
///
/// Use this for enterprise observability to monitor source performance 
/// and consensus convergence behavior.
@immutable
final class SyncMetrics {
  const SyncMetrics({
    required this.latencyMs,
    required this.uncertaintyMs,
    required this.participantCount,
    required this.groupCount,
    required this.confidence,
    required this.confidenceBreakdown,
  });

  /// The round-trip time for the slowest source participating in the consensus.
  final int latencyMs;

  /// The resolved precision of the consensus (half the interval width).
  final int uncertaintyMs;

  /// The number of unique time authorities that contributed to the consensus.
  final int participantCount;

  /// The number of distinct administrative groups involved.
  final int groupCount;

  /// The qualitative grade assigned by the engine.
  final ConfidenceLevel confidence;

  /// A breakdown of the probabilistic factors (depth, diversity, stability) 
  /// contributing to the final score.
  final Map<String, double> confidenceBreakdown;

  Map<String, dynamic> toJson() => {
        'latencyMs': latencyMs,
        'uncertaintyMs': uncertaintyMs,
        'participantCount': participantCount,
        'groupCount': groupCount,
        'confidence': confidence.name,
        'breakdown': confidenceBreakdown,
      };
}

/// Represents a cryptographically-aware point-in-time "Anchor" pinned 
/// to the hardware monotonic clock.
///
/// A [TrustAnchor] is the immutable foundation of the virtual clock. It 
/// captures the immutable relationship between the network's UTC truth 
/// and the device's hardware oscillator at the exact moment of consensus.
///
/// Since the hardware oscillator (uptime) is immune to user manipulation, 
/// the anchor allows for sub-microsecond, offline-safe time retrieval 
/// that is resilient to system clock tampering.
@immutable
final class TrustAnchor {
  const TrustAnchor({
    required this.networkUtcMs,
    required this.uptimeMs,
    required this.wallMs,
    required this.uncertaintyMs,
    this.authLevel = NtsAuthLevel.none,
    this.confidence = ConfidenceLevel.low,
    this.syncTime,
  }) : syncTime = syncTime ?? DateTime.now();

  /// The cryptographic security level achieved during synchronization.
  final NtsAuthLevel authLevel;

  /// The qualitative grade of the original consensus.
  final ConfidenceLevel confidence;

  /// The wall-clock timestamp when this anchor was established.
  final DateTime syncTime;

  /// Probabilistic "Freshness" score (0.0 to 1.0).
  ///
  /// This score models the increasing uncertainty of the anchor as it ages. 
  /// It uses an exponential decay model based on the anchor's original 
  /// qualitative confidence level:
  /// * **High Confidence**: 6-hour half-life.
  /// * **Standard/Low**: 2-hour half-life.
  ///
  /// As the score approaches 0.1 (the absolute floor), applications should 
  /// consider the anchor "stale" and trigger a resync.
  ///
  /// **Safe Range**: This calculation uses double-precision arithmetic and 
  /// [Duration.inMinutes] (returning a 64-bit int). It is numerically stable 
  /// for anchor ages exceeding 4,000 years.
  double get confidenceScore {
    final age = DateTime.now().difference(syncTime);
    
    // Freshness Decay (Half-life model)
    final halfLifeHours = confidence == ConfidenceLevel.high ? 6.0 : 2.0;
    final decay = age.inMinutes.toDouble() / (halfLifeHours * 60.0);
    final freshness = 1.0 / (1.0 + decay);

    // Base Trust Floor
    final baseTrust = switch (confidence) {
      ConfidenceLevel.high => 0.8,
      ConfidenceLevel.medium => 0.5,
      ConfidenceLevel.low => 0.3,
    };

    return max(0.1, freshness * baseTrust);
  }

  /// The network-verified UTC time in milliseconds since epoch.
  final int networkUtcMs;

  /// The hardware monotonic uptime in milliseconds at the moment of sync.
  final int uptimeMs;

  /// The system wall-clock time in milliseconds at the moment of sync.
  /// Used primarily for drift detection and anomaly monitoring.
  final int wallMs;

  /// The precision of the original measurement (±ms).
  final int uncertaintyMs;

  /// Returns the [networkUtcMs] as a UTC [DateTime].
  DateTime get networkUtc =>
      DateTime.fromMillisecondsSinceEpoch(networkUtcMs, isUtc: true);

  TrustAnchor copyWith({
    int? uncertaintyMs,
    NtsAuthLevel? authLevel,
    ConfidenceLevel? confidence,
  }) =>
      TrustAnchor(
        networkUtcMs: networkUtcMs,
        uptimeMs: uptimeMs,
        wallMs: wallMs,
        uncertaintyMs: uncertaintyMs ?? this.uncertaintyMs,
        authLevel: authLevel ?? this.authLevel,
        confidence: confidence ?? this.confidence,
        syncTime: syncTime,
      );

  Map<String, dynamic> toJson() => {
        'networkUtcMs': networkUtcMs,
        'uptimeMs': uptimeMs,
        'wallMs': wallMs,
        'uncertaintyMs': uncertaintyMs,
        'authLevel': authLevel.index,
        'confidence': confidence.index,
        'syncTime': syncTime.millisecondsSinceEpoch,
      };

  factory TrustAnchor.fromJson(Map<String, dynamic> j) => TrustAnchor(
        networkUtcMs: j['networkUtcMs'] as int,
        uptimeMs: j['uptimeMs'] as int,
        wallMs: j['wallMs'] as int,
        uncertaintyMs: j['uncertaintyMs'] as int,
        authLevel: NtsAuthLevel.values[j['authLevel'] as int? ?? 0],
        confidence: ConfidenceLevel.values[j['confidence'] as int? ?? 0],
        syncTime: DateTime.fromMillisecondsSinceEpoch(
          j['syncTime'] as int? ?? DateTime.now().millisecondsSinceEpoch
        ),
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
  String toString() => 'TrustAnchor(±${uncertaintyMs}ms, confidence: ${confidence.name})';
}

/// Enterprise-grade configuration for the TrustedTime integrity subsystem.
///
/// Use this to tune the engine's sensitivity, source population, 
/// and self-healing behaviors.
@immutable
final class TrustedTimeConfig {
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
    this.ntsServers = const [],
    this.ntsPort = 4460,
    this.minQuorumRatio = 0.6,
    this.maxAllowedUncertaintyMs = 10000,
    this.minGroupCount = 2,
    this.earlyExit = true,
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

  /// Additional custom [TimeSource] implementations to include
  /// in the consensus pool alongside the built-in NTP and HTTPS sources.
  final List<TimeSource> additionalSources;

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

  /// NTS-KE (Network Time Security Key Exchange) server hostnames for
  /// RFC 8915 authenticated time.
  ///
  /// When non-empty, the engine establishes a TLS 1.3 session with each
  /// server, negotiates AEAD keys, then uses those keys to authenticate
  /// NTPv4 packets. Authenticated samples feed into the same Marzullo
  /// consensus engine as plain NTP and HTTPS sources.
  ///
  /// Defaults to `[]` (NTS disabled). When empty, no TLS connections are
  /// made and the `cryptography` package tree-shakes to zero overhead.
  ///
  /// Known compatible servers: `time.cloudflare.com` (port 4460).
  ///
  /// **Android note:** if your `network-security-config` restricts cleartext
  /// traffic, add an `<domain-config>` entry for each NTS server to allow
  /// TLS on port [ntsPort].
  final List<String> ntsServers;

  /// The TCP port used for the NTS-KE TLS handshake.
  final int ntsPort;

  /// The minimum percentage of responding sources that must agree (default 60%).
  final double minQuorumRatio;

  /// Samples with uncertainty exceeding this are excluded from consensus.
  final int maxAllowedUncertaintyMs;

  /// Minimum number of unique source groups (e.g. providers) required for consensus.
  final int minGroupCount;

  /// Whether to stop querying once a stable quorum is reached.
  final bool earlyExit;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TrustedTimeConfig &&
          refreshInterval == other.refreshInterval &&
          listEquals(ntpServers, other.ntpServers) &&
          listEquals(httpsSources, other.httpsSources) &&
          maxLatency == other.maxLatency &&
          minimumQuorum == other.minimumQuorum &&
          persistState == other.persistState &&
          oscillatorDriftFactor == other.oscillatorDriftFactor &&
          backgroundSyncInterval == other.backgroundSyncInterval &&
          listEquals(additionalSources, other.additionalSources) &&
          listEquals(ntsServers, other.ntsServers) &&
          ntsPort == other.ntsPort;

  @override
  int get hashCode => Object.hash(
        refreshInterval,
        Object.hashAll(ntpServers),
        Object.hashAll(httpsSources),
        maxLatency,
        minimumQuorum,
        persistState,
        oscillatorDriftFactor,
        backgroundSyncInterval,
        Object.hashAll(additionalSources),
        Object.hashAll(ntsServers),
        ntsPort,
        minQuorumRatio,
        maxAllowedUncertaintyMs,
        minGroupCount,
        earlyExit,
      );
}
