import 'package:flutter/foundation.dart';

/// Individual time point captured from a specific remote authority.
///
/// A [SourceSample] represents one successful response from a
/// [TrustedTimeSource], including the measured round-trip latency which
/// determines the uncertainty bounds for Marzullo's algorithm.
@immutable
final class SourceSample {
  /// Creates a sample with the given [sourceId], measured [utc] time,
  /// and [roundTripMs] latency.
  const SourceSample({
    required this.sourceId,
    required this.utc,
    required this.roundTripMs,
  });

  /// Identifier of the source that produced this sample (e.g.,
  /// `'ntp:time.google.com'`).
  final String sourceId;

  /// The UTC time reported by the source, corrected for one-way latency.
  final DateTime utc;

  /// The total round-trip time of the query, in milliseconds.
  final int roundTripMs;

  /// The estimated uncertainty: half the round-trip latency (best case).
  int get uncertaintyMs => roundTripMs ~/ 2;
}

/// The result of a successful multi-source consensus resolution.
///
/// Contains the best-estimate UTC time derived from the intersection of
/// all agreeing source intervals, along with the residual uncertainty and
/// the number of sources that participated in the consensus.
@immutable
final class ConsensusResult {
  /// Creates a consensus result.
  const ConsensusResult({
    required this.utc,
    required this.uncertaintyMs,
    required this.participantCount,
  });

  /// The best-estimate UTC time (midpoint of the Marzullo intersection).
  final DateTime utc;

  /// Half-width of the intersection interval, in milliseconds.
  ///
  /// Smaller values indicate higher precision.
  final int uncertaintyMs;

  /// Number of sources whose intervals overlapped in the consensus.
  final int participantCount;
}

/// Resolves a single source-of-truth from overlapping confidence intervals
/// using [Marzullo's Algorithm](https://en.wikipedia.org/wiki/Marzullo%27s_algorithm).
///
/// Each source provides a time estimate with uncertainty bounds (derived from
/// round-trip latency). The algorithm finds the narrowest interval where at
/// least [minimumQuorum] sources agree, yielding the best consensus time.
final class MarzulloEngine {
  /// Creates an engine requiring [minimumQuorum] overlapping intervals.
  const MarzulloEngine({required this.minimumQuorum});

  /// The minimum number of agreeing sources required for a valid consensus.
  final int minimumQuorum;

  /// Runs Marzullo's algorithm on the given [samples].
  ///
  /// Returns the [ConsensusResult] if at least [minimumQuorum] intervals
  /// overlap, or `null` if consensus cannot be reached.
  ConsensusResult? resolve(List<SourceSample> samples) {
    if (samples.length < minimumQuorum) return null;

    // Convert each sample's center ± uncertainty into an interval pair.
    final endpoints = <_Endpoint>[];
    for (final s in samples) {
      final center = s.utc.millisecondsSinceEpoch;
      final u = s.uncertaintyMs;
      endpoints
        ..add(_Endpoint(center - u, _EndpointType.lower, s.sourceId))
        ..add(_Endpoint(center + u, _EndpointType.upper, s.sourceId));
    }

    // Sort all boundaries chronologically for linear scanning.
    endpoints.sort((a, b) => a.timeMs.compareTo(b.timeMs));

    var best = 0;
    int? bestStart;
    int? bestEnd;
    var overlap = 0;

    for (final ep in endpoints) {
      if (ep.type == _EndpointType.lower) {
        overlap++;
        if (overlap > best) {
          best = overlap;
          bestStart = ep.timeMs;
        }
      } else {
        if (overlap == best && bestStart != null) {
          bestEnd = ep.timeMs;
        }
        overlap--;
      }
    }

    if (best < minimumQuorum || bestStart == null || bestEnd == null) {
      return null;
    }

    // Midpoint of the intersection gives the best UTC estimate.
    final midMs = (bestStart + bestEnd) ~/ 2;
    // Uncertainty is half the width of the final intersection.
    final uncertaintyMs = (bestEnd - bestStart) ~/ 2;

    return ConsensusResult(
      utc: DateTime.fromMillisecondsSinceEpoch(midMs, isUtc: true),
      uncertaintyMs: uncertaintyMs,
      participantCount: best,
    );
  }
}

/// Whether an endpoint marks the start or end of a confidence interval.
enum _EndpointType { lower, upper }

/// A single boundary point in the Marzullo linear scan.
final class _Endpoint {
  const _Endpoint(this.timeMs, this.type, this.sourceId);

  final int timeMs;
  final _EndpointType type;
  final String sourceId;
}
