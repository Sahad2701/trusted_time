import 'dart:math';
import 'package:flutter/foundation.dart';
import 'time_sample.dart';
import 'time_interval.dart';

import '../sources/nts_source.dart';
import '../models.dart';

@immutable
/// The resolved state of a consensus cycle.
///
/// Encapsulates the verified UTC time, the calculated precision (uncertainty), 
/// and the metadata required to judge the integrity of the consensus.
@immutable
final class ConsensusResult {
  const ConsensusResult({
    required this.utc,
    required this.uncertaintyMs,
    required this.participantCount,
    required this.groupCount,
    this.authLevel = NtsAuthLevel.none,
    this.confidence = ConfidenceLevel.low,
    this.interval,
  });

  /// The mid-point of the agreed consensus interval.
  final DateTime utc;

  /// The precision of the consensus, representing half the width of the overlap.
  final int uncertaintyMs;

  /// Number of unique time authorities that contributed to this consensus.
  final int participantCount;

  /// Number of distinct administrative groups (e.g. ASNs) in the consensus.
  final int groupCount;

  /// The highest common authentication level achieved across the consensus group.
  final NtsAuthLevel authLevel;

  /// Qualitative grade of the consensus established by the [MarzulloEngine].
  final ConfidenceLevel confidence;

  /// The raw [TimeInterval] representing the intersection of all quorum samples.
  final TimeInterval? interval;
}

/// A high-integrity implementation of Marzullo's algorithm for time consensus.
///
/// This engine resolves a single "truth" from multiple, potentially noisy or 
/// malicious time authorities. It treats each time sample as an interval 
/// `[T - error, T + error]` and searches for the intersection that contains 
/// the most probable true time.
///
/// ## Key Refinements
///
/// * **Group-Aware Diversity**: Prevents "correlated failures" where a single 
///   provider (e.g. a specific data center or ASN) dominates the consensus.
/// * **Closed-Interval Tie-breaking**: Strictly enforces that endpoint boundaries 
///   are inclusive, ensuring stable overlap detection even with identical timestamps.
/// * **Graduated Trust**: Automatically grades the resulting consensus as 
///   low, medium, or high confidence based on depth and diversity.
final class MarzulloEngine {
  const MarzulloEngine({
    this.minQuorumRatio = 0.6,
    this.maxAllowedUncertaintyMs = 10000,
    this.minGroupCount = 2,
  });

  /// The minimum percentage of responding sources that must participate in 
  /// the consensus for it to be considered valid.
  final double minQuorumRatio;

  /// Hard exclusion threshold. Sources with uncertainty exceeding this 
  /// are discarded to prevent "consensus bloating."
  final int maxAllowedUncertaintyMs;

  /// Minimum number of distinct administrative groups required to achieve 
  /// high-confidence status.
  final int minGroupCount;

  /// Orchestrates the consensus resolution process across a set of samples.
  ///
  /// Returns a [ConsensusResult] if a quorum is achieved that satisfies 
  /// the [minQuorumRatio] and [minGroupCount] constraints. Returns `null` 
  /// if the samples are too divergent or the population is insufficient.
  ConsensusResult? resolve(List<TimeSample> samples) {
    // We filter out "noisy" sources early. Inclusion of high-uncertainty 
    // sources artificially increases the consensus width without adding 
    // valuable information.
    final validSamples = samples.where((s) => s.uncertaintyMs <= maxAllowedUncertaintyMs).toList();

    final totalSources = validSamples.length;
    final requiredQuorum = (totalSources * minQuorumRatio).ceil();
    
    if (totalSources == 0 || requiredQuorum == 0) return null;

    final endpoints = <_Endpoint>[];
    for (final s in validSamples) {
      endpoints
        ..add(_Endpoint(s.interval.startMs, _EndpointType.lower, s))
        ..add(_Endpoint(s.interval.endMs, _EndpointType.upper, s));
    }

    // Sort endpoints to find the densest overlap. 
    // In Marzullo's algorithm, for closed intervals, an 'upper' endpoint 
    // at time T should be processed before a 'lower' endpoint at time T 
    // to correctly count the depth at the point of overlap.
    endpoints.sort((a, b) {
      final cmp = a.timeMs.compareTo(b.timeMs);
      if (cmp != 0) return cmp;
      return a.type == _EndpointType.upper ? -1 : 1;
    });

    var bestOverlap = 0;
    int? bestStart;
    int? bestEnd;
    var currentOverlap = 0;
    
    final activeSamples = <TimeSample>{};
    final bestSamples = <TimeSample>{};

    for (final ep in endpoints) {
      if (ep.type == _EndpointType.lower) {
        currentOverlap++;
        activeSamples.add(ep.sample);
        
        if (currentOverlap > bestOverlap) {
          bestOverlap = currentOverlap;
          bestStart = ep.timeMs;
          bestEnd = null;
          bestSamples
            ..clear()
            ..addAll(activeSamples);
        }
      } else {
        if (currentOverlap == bestOverlap && bestStart != null && bestEnd == null) {
          bestEnd = ep.timeMs;
        }
        activeSamples.remove(ep.sample);
        currentOverlap--;
      }
    }

    // A consensus is only valid if it reaches the required population depth.
    if (bestOverlap < requiredQuorum || bestStart == null || bestEnd == null) {
      return null;
    }

    final uniqueGroups = bestSamples.map((s) => s.groupId).toSet();
    final groupCount = uniqueGroups.length;
    
    // We grade confidence based on both the depth of the quorum and the 
    // diversity of its providers. A high-confidence result requires 
    // exceeding the minimum quorum and meeting diversity requirements.
    var confidence = ConfidenceLevel.low;
    if (groupCount >= minGroupCount) {
      confidence = ConfidenceLevel.medium;
      if (bestOverlap >= requiredQuorum + 1) {
        confidence = ConfidenceLevel.high;
      }
    }

    final midMs = (bestStart + bestEnd) ~/ 2;
    final uncertaintyMs = (bestEnd - bestStart) ~/ 2;

    // The consensus authentication level is determined by the "weakest link."
    // If even one source in the quorum is unauthenticated, the entire 
    // consensus cannot be considered fully authenticated.
    var effectiveAuth = NtsAuthLevel.verified;
    for (final s in bestSamples) {
      if (s.authLevel.index < effectiveAuth.index) {
        effectiveAuth = s.authLevel;
      }
    }

    return ConsensusResult(
      utc: DateTime.fromMillisecondsSinceEpoch(midMs, isUtc: true),
      uncertaintyMs: max(1, uncertaintyMs),
      participantCount: bestSamples.length,
      groupCount: groupCount,
      authLevel: effectiveAuth,
      confidence: confidence,
      interval: TimeInterval(startMs: bestStart, endMs: bestEnd),
    );
  }
}

enum _EndpointType { lower, upper }

final class _Endpoint {
  const _Endpoint(this.timeMs, this.type, this.sample);
  final int timeMs;
  final _EndpointType type;
  final TimeSample sample;
}
