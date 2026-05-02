import 'package:flutter/foundation.dart';
import 'domain/time_source.dart';
import 'exceptions.dart';
import 'sources/nts_source.dart';

/// Qualitative grades of consensus integrity.
///
/// These levels represent the engine's confidence in the accuracy of the current 
/// [TrustAnchor] based on population depth, provider diversity, and variance.
enum ConfidenceLevel {
  /// The engine has not yet reached a stable quorum, or the current state 
  /// has been explicitly invalidated (e.g., after an integrity violation).
  none,

  /// A consensus has been achieved, but the population depth or provider 
  /// diversity is minimal (e.g., only two sources from the same network group).
  low,

  /// A stable quorum has been reached with adequate provider diversity 
  /// (multiple administrative groups/protocols).
  medium,

  /// A high-integrity quorum has been reached with broad diversity across 
  /// protocols (NTP, HTTPS, NTS) and extremely low population variance.
  high,
}

@immutable
/// Configuration parameters for the [TrustedTime] engine.
///
/// This class defines the behavioral policy of the engine, including quorum 
/// requirements, security thresholds, and background synchronization intervals.
final class TrustedTimeConfig {
  /// Creates a new configuration instance with sensible production defaults.
  const TrustedTimeConfig({
    this.ntpServers = const ['pool.ntp.org', 'time.google.com'],
    this.httpsSources = const ['https://www.google.com', 'https://www.cloudflare.com'],
    this.ntsServers = const ['time.cloudflare.com'],
    this.ntsPort = 4460,
    this.additionalSources = const [],
    this.minQuorumRatio = 0.6,
    this.minimumQuorum = 2,
    this.minGroupCount = 2,
    this.maxLatency = const Duration(seconds: 4),
    this.refreshInterval = const Duration(minutes: 30),
    this.maxAllowedUncertaintyMs = 5000,
    this.persistState = true,
    this.earlyExit = true,
    this.oscillatorDriftFactor = 0.00005,
    this.backgroundSyncInterval,
  });

  /// The list of authoritative NTP server hostnames used for synchronization.
  final List<String> ntpServers;

  /// The list of HTTP/HTTPS endpoints used to extract UTC time from the `Date` header.
  final List<String> httpsSources;

  /// The list of Network Time Security (NTS) servers used for cryptographically 
  /// authenticated synchronization.
  final List<String> ntsServers;

  /// The TCP port used for the NTS Key Exchange (NTS-KE) handshake. 
  /// Defaults to 4460 as per RFC 8915.
  final int ntsPort;

  /// Custom [TimeSource] implementations provided by the application developer.
  final List<TimeSource> additionalSources;

  /// The minimum fraction of responding sources (0.0 to 1.0) that must overlap 
  /// for a consensus to be considered valid.
  final double minQuorumRatio;

  /// The absolute minimum number of agreeing sources required to establish trust.
  final int minimumQuorum;

  /// The minimum number of distinct administrative groups (e.g., different ASNs 
  /// or protocols) required to reach higher confidence levels.
  final int minGroupCount;

  /// The maximum amount of time the engine will wait for a response from any 
  /// single source before it is discarded.
  final Duration maxLatency;

  /// The frequency at which the engine enters a proactive synchronization cycle 
  /// while the app is in the foreground.
  final Duration refreshInterval;

  /// The hard threshold for precision. If a consensus result has an uncertainty 
  /// (width/2) exceeding this value, it is discarded.
  final int maxAllowedUncertaintyMs;

  /// Whether to persist the last verified [TrustAnchor] to secure storage. 
  /// Allows for faster "warm-start" trust establishment on app restart.
  final bool persistState;

  /// If true, the engine will stop querying sources as soon as a stable quorum 
  /// is reached, conserving network and battery resources.
  final bool earlyExit;

  /// The assumed drift rate of the device oscillator in seconds per second. 
  /// Used for offline confidence degradation (0.00005 ≈ 50ppm).
  final double oscillatorDriftFactor;

  /// The interval at which the engine should perform a background synchronization. 
  /// If null, background synchronization is disabled.
  final Duration? backgroundSyncInterval;
}

@immutable
/// A hardware-anchored snapshot representing a verified network consensus.
///
/// This model acts as the "source of truth" for the engine. It links the 
/// network-verified UTC time to the device's hardware monotonic clock at a 
/// specific moment in time.
final class TrustAnchor {
  /// Internal constructor for creating a new trust anchor.
  const TrustAnchor({
    required this.networkUtcMs,
    required this.uptimeMs,
    required this.wallMs,
    required this.uncertaintyMs,
    this.authLevel = NtsAuthLevel.none,
    this.confidence = ConfidenceLevel.low,
  });

  /// Deserializes a [TrustAnchor] from a JSON map with rigorous bounds checking.
  factory TrustAnchor.fromJson(Map<String, dynamic> json) {
    try {
      final authIdx = json['authLevel'] as int? ?? 0;
      final confIdx = json['confidence'] as int? ?? 0;
      
      // CRITICAL-6: Prevent RangeError or malformed state during deserialization.
      final authLevel = (authIdx >= 0 && authIdx < NtsAuthLevel.values.length)
          ? NtsAuthLevel.values[authIdx]
          : NtsAuthLevel.none;
          
      final confidence = (confIdx >= 0 && confIdx < ConfidenceLevel.values.length)
          ? ConfidenceLevel.values[confIdx]
          : ConfidenceLevel.none;

      return TrustAnchor(
        networkUtcMs: json['networkUtcMs'] as int,
        uptimeMs: json['uptimeMs'] as int,
        wallMs: json['wallMs'] as int,
        uncertaintyMs: json['uncertaintyMs'] as int,
        authLevel: authLevel,
        confidence: confidence,
      );
    } catch (e) {
      throw TrustedTimePersistenceException('Malformed TrustAnchor JSON: $e');
    }
  }

  /// The UTC timestamp established by the network consensus (milliseconds).
  final int networkUtcMs;

  /// The device's monotonic uptime at the moment the consensus was reached.
  final int uptimeMs;

  /// The device's system wall-clock time at the moment the consensus was reached.
  final int wallMs;

  /// The calculated precision of the consensus (half-width of the intersection).
  final int uncertaintyMs;

  /// The common authentication level achieved by the quorum participants.
  final NtsAuthLevel authLevel;

  /// The qualitative grade of this anchor (none, low, medium, or high).
  final ConfidenceLevel confidence;

  /// Alias for [networkUtcMs].
  int get trustedUtcMs => networkUtcMs;

  /// A normalized score (0.0 to 1.0) representing the reliability of this anchor.
  double get confidenceScore {
    switch (confidence) {
      case ConfidenceLevel.none: return 0.0;
      case ConfidenceLevel.low: return 0.3;
      case ConfidenceLevel.medium: return 0.7;
      case ConfidenceLevel.high: return 1.0;
    }
  }

  /// Serializes the anchor for secure local storage.
  Map<String, dynamic> toJson() => {
        'networkUtcMs': networkUtcMs,
        'uptimeMs': uptimeMs,
        'wallMs': wallMs,
        'uncertaintyMs': uncertaintyMs,
        'authLevel': authLevel.index,
        'confidence': confidence.index,
      };
}

@immutable
/// Diagnostic metrics captured during a synchronization cycle.
final class SyncMetrics {
  /// Internal constructor for synchronization metrics.
  const SyncMetrics({
    required this.latencyMs,
    required this.uncertaintyMs,
    required this.participantCount,
    required this.groupCount,
    required this.confidence,
    required this.confidenceBreakdown,
  });

  /// The total time taken for the network synchronization cycle.
  final int latencyMs;

  /// The precision achieved by the resolved consensus.
  final int uncertaintyMs;

  /// The number of time authorities that participated in the consensus.
  final int participantCount;

  /// The number of administrative groups represented in the quorum.
  final int groupCount;

  /// The qualitative grade of the synchronization result.
  final ConfidenceLevel confidence;

  /// A granular breakdown of confidence factors (e.g., depth, diversity, stability).
  final Map<String, double> confidenceBreakdown;
}