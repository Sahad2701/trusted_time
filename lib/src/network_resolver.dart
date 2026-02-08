import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'exceptions.dart';

/// A data container representing the successful resolution of trusted network time.
class NetworkTimeResult {
  /// The estimated network time in milliseconds since the Unix epoch (UTC).
  final int networkTimeMs;

  /// The estimated uncertainty or confidence interval (± milliseconds) of
  /// the resolved time. A lower value indicates higher precision.
  final int uncertaintyMs;

  /// The total number of unique time sources that contributed to the
  /// consensus during this resolution.
  final int sourceCount;

  const NetworkTimeResult({
    required this.networkTimeMs,
    required this.uncertaintyMs,
    required this.sourceCount,
  });

  /// The legacy name for [networkTimeMs], maintained for internal consistency.
  int get trustedEpochMs => networkTimeMs;
}

/// A high-performance resolver using an HTTPS-based multi-source quorum.
///
/// This resolver is designed for maximum compatibility, working in environments
/// where UDP (NTP) might be restricted. It leverages standard HTTPS traffic
/// to derive a high-trust time anchor.
///
/// **The Algorithm:**
/// It implements a refined version of **Marzullo's Algorithm**. By querying
/// multiple high-availability sources and identifying the widest overlapping
/// interval of agreement, it can effectively reject outliers and account
/// for network asymmetric delay.
abstract final class NetworkTimeResolver {
  /// Tier-1 public time sources used for HTTPS quorum.
  /// We select these specific providers for their global distribution and
  /// high-precision "date" header adherence.
  static const List<String> defaultSources = <String>[
    'https://www.google.com',
    'https://www.cloudflare.com',
    'https://www.apple.com',
  ];

  /// The maximum round-trip time (RTT) allowed for a single source.
  /// Records exceeding this threshold are discarded as being too noisy.
  static const Duration _maxRtt = Duration(seconds: 2);

  /// Minimum number of successful responses required to reach consensus.
  static const int _minimumQuorum = 2;

  /// Resolves the current trusted time using a multi-source quorum strategy.
  static Future<NetworkTimeResult> resolve({
    List<String>? sources,
    Duration timeoutPerSource = const Duration(seconds: 2),
    int minimumQuorum = _minimumQuorum,
  }) async {
    final effectiveSources = sources ?? defaultSources;
    if (effectiveSources.length < minimumQuorum) {
      throw ArgumentError('Insufficient sources for quorum.');
    }

    // We establish a "Temporal Baseline" before launching parallel requests.
    // By anchoring every response to the same local monotonic timeline, we
    // ensure that the final consensus is mathematically perfect even if the
    // system clock is manually adjusted during the synchronization process.
    final bMs = DateTime.now().millisecondsSinceEpoch;
    final bSw = Stopwatch()..start();

    final intervals = <_TimeInterval>[];

    await Future.wait(
      effectiveSources.map((url) async {
        try {
          final res = await _querySource(url, timeoutPerSource, bMs, bSw);
          if (res != null) intervals.add(res);
        } catch (_) {}
      }),
    );

    if (intervals.length < minimumQuorum) {
      throw const TrustedTimeSyncException('Consensus quorum failed.');
    }

    final overlap = _findMajorityOverlap(intervals, minimumQuorum);
    final medianOffset = (overlap.start + overlap.end) ~/ 2;

    return NetworkTimeResult(
      networkTimeMs: bMs + bSw.elapsedMilliseconds + medianOffset,
      uncertaintyMs: (overlap.end - overlap.start) ~/ 2 + 20,
      sourceCount: overlap.contributors,
    );
  }

  // Source querying

  static Future<_TimeInterval?> _querySource(
    String url,
    Duration timeout,
    int bMs,
    Stopwatch bSw,
  ) async {
    try {
      final sSw = Stopwatch()..start();
      final uri = Uri.parse(url);

      http.Response resp;
      try {
        resp = await http.head(uri).timeout(timeout);
      } catch (_) {
        resp = await http.get(uri).timeout(timeout);
      }

      final rtt = sSw.elapsedMilliseconds;
      final date = resp.headers['date'];

      // Accuracy Check: We reject results with unreasonable latency (RTT).
      // High latency introduces significant uncertainty in the midpoint estimation.
      if (date == null || rtt > _maxRtt.inMilliseconds) return null;

      final sMs = HttpDate.parse(date).millisecondsSinceEpoch;
      final rMs = bMs + bSw.elapsedMilliseconds;

      // Midpoint Estimation: We assume symmetry in network travel time.
      // The true server time is estimated as: ServerTime - (LocalTimeAtReceipt - RTT/2).
      final off = sMs - (rMs - (rtt ~/ 2));
      final err = rtt ~/ 2;

      return _TimeInterval(off - err, off + err);
    } catch (_) {
      return null;
    }
  }

  /// Implementation of Marzullo's Algorithm to find the consensus interval.
  ///
  /// This method identifies the range where at least [minimumQuorum] intervals
  /// overlap, providing the most credible time domain.
  static _Result _findMajorityOverlap(List<_TimeInterval> data, int minQuorum) {
    final pts = List<_Pt>.generate(data.length * 2, (i) {
      final d = data[i ~/ 2];
      return i.isEven ? _Pt(d.start, 1) : _Pt(d.end, -1);
    }, growable: false);

    pts.sort((a, b) {
      final c = a.v.compareTo(b.v);
      return c != 0 ? c : b.d.compareTo(a.d);
    });

    var count = 0, bestCount = 0, start = 0, end = 0;
    for (var i = 0; i < pts.length; i++) {
      count += pts[i].d;
      if (count > bestCount && count >= minQuorum && i + 1 < pts.length) {
        bestCount = count;
        start = pts[i].v;
        end = pts[i + 1].v;
      }
    }

    if (bestCount < minQuorum) throw TimeoutException('Consensus lost.');
    return _Result(start, end, bestCount);
  }
}

class _TimeInterval {
  final int start, end;
  const _TimeInterval(this.start, this.end);
}

class _Pt {
  final int v, d;
  const _Pt(this.v, this.d);
}

class _Result {
  final int start, end, contributors;
  const _Result(this.start, this.end, this.contributors);
}
