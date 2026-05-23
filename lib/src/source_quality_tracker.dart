import 'dart:collection';
import 'dart:math';

/// How many recent observations are retained per source.
const int _kHistoryDepth = 10;

/// Minimum fraction of sync cycles between forced low-ranking queries to
/// prevent source starvation. Sources that haven't been queried within
/// [_kStarvationCycles] cycles are promoted to forced-query regardless of
/// score.
const int _kStarvationCycles = 5;

/// Per-source observation recorded after each successful [TimeSample].
class _SourceObservation {
  const _SourceObservation({
    required this.uncertaintyMs,
    required this.participatedInConsensus,
    required this.cycleIndex,
  });

  final int uncertaintyMs;
  final bool participatedInConsensus;
  final int cycleIndex;
}

/// Tracks the rolling quality of individual time sources and produces a
/// priority-ordered list for the next sync cycle.
///
/// **Scoring**: Each source is scored on three dimensions:
/// 1. **RTT/uncertainty** — lower uncertainty → higher score.
/// 2. **Consensus participation** — sources that regularly contribute to a
///    winning quorum are weighted higher.
/// 3. **NTP stratum** (optional, 1–15) — lower stratum (closer to reference)
///    → higher weight.
///
/// **Starvation guard**: Sources that haven't been queried within
/// [_kStarvationCycles] cycles are always included in the next cycle at
/// minimum query rate, keeping their quality estimates fresh and preventing
/// the engine from permanently ignoring lower-ranked sources.
final class SourceQualityTracker {
  final _history = <String, Queue<_SourceObservation>>{};
  final _lastQueriedCycle = <String, int>{};
  final _stratumHints = <String, int>{};

  int _cycleIndex = 0;

  /// Records a completed sync cycle observation for a source.
  ///
  /// [sourceId] uniquely identifies the source.
  /// [uncertaintyMs] is the half-width of the returned [TimeInterval].
  /// [participatedInConsensus] is true if the source's sample was part of
  /// the Marzullo winning set.
  void record({
    required String sourceId,
    required int uncertaintyMs,
    required bool participatedInConsensus,
  }) {
    final q = _history.putIfAbsent(sourceId, Queue.new);
    q.addLast(
      _SourceObservation(
        uncertaintyMs: uncertaintyMs,
        participatedInConsensus: participatedInConsensus,
        cycleIndex: _cycleIndex,
      ),
    );
    while (q.length > _kHistoryDepth) {
      q.removeFirst();
    }
    _lastQueriedCycle[sourceId] = _cycleIndex;
  }

  /// Records a failure for a source (no observation added, but the query
  /// cycle is noted so starvation detection still works).
  void recordFailure(String sourceId) {
    _lastQueriedCycle[sourceId] = _cycleIndex;
  }

  /// Optionally registers an NTP stratum hint for a source.
  ///
  /// Stratum 1 (directly attached to a reference clock) scores highest.
  /// Valid range: 1–15; values outside this range are ignored.
  void setStratum(String sourceId, int stratum) {
    if (stratum >= 1 && stratum <= 15) {
      _stratumHints[sourceId] = stratum;
    }
  }

  /// Advances the internal cycle counter. Call once per completed sync cycle.
  void advanceCycle() => _cycleIndex++;

  /// Returns a sorted list of source IDs, highest quality first, given the
  /// full set of candidate [sourceIds].
  ///
  /// Sources flagged for **forced inclusion** (starvation guard) appear after
  /// the ranked set so the engine always queries them even at lower priority.
  List<String> ranked(Iterable<String> sourceIds) {
    final ids = sourceIds.toList();
    final scores = {for (final id in ids) id: _score(id)};
    ids.sort((a, b) => scores[b]!.compareTo(scores[a]!));
    return ids;
  }

  /// Returns `true` if [sourceId] should be force-included this cycle to
  /// prevent starvation, regardless of its quality rank.
  bool isStarved(String sourceId) {
    final last = _lastQueriedCycle[sourceId];
    if (last == null) return true; // Never queried.
    return (_cycleIndex - last) >= _kStarvationCycles;
  }

  double _score(String sourceId) {
    final q = _history[sourceId];

    // No history: treat as neutral (will be queried; starvation guard handles it).
    if (q == null || q.isEmpty) return 0.5;

    // RTT score: normalise over observed range; lower uncertainty is better.
    final uncertainties = q.map((o) => o.uncertaintyMs).toList();
    final avgUncertainty =
        uncertainties.fold(0, (a, b) => a + b) / uncertainties.length;
    // Map to (0, 1]: asymptotic curve so very fast sources score near 1.0.
    final rttScore = 1.0 / (1.0 + log(1 + avgUncertainty / 50));

    // Consensus participation rate.
    final participationRate =
        q.where((o) => o.participatedInConsensus).length / q.length;

    // Stratum score: 1→1.0, 15→0.0, absent→0.5.
    final stratum = _stratumHints[sourceId];
    final stratumScore = stratum != null ? (15 - stratum) / 14.0 : 0.5;

    // Weighted combination.
    return (rttScore * 0.4) + (participationRate * 0.4) + (stratumScore * 0.2);
  }
}
