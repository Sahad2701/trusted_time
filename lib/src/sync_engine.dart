import 'dart:async';
import 'dart:math';
import 'domain/marzullo_engine.dart';
import 'domain/time_sample.dart';
import 'domain/time_source.dart';
import 'domain/time_interval.dart';
import 'exceptions.dart';
import 'models.dart';
import 'monotonic_clock.dart';
import 'source_quality_tracker.dart';
import 'sources/time_sources.dart';
import 'infra/sync_observer.dart';
import 'infra/consensus_cache.dart';

/// ## Absolute Top Tier: Distributed Lifecycle Orchestration
///
/// The [SyncEngine] is the heart of the time integrity subsystem. It implements
/// a self-healing operational state machine designed for adversarial robustness.
///
/// Key Refinements:
/// 1. **Racing Parallelism**: Minimizes cold-start latency through concurrent
///    multi-source querying.
/// 2. **Adaptive Stability Escalation**: Dynamically adjusts quorum requirements
///    based on population variance.
/// 3. **Mathematical Outlier Filtering**: Uses median-based guards to neutralize
///    malicious or jittery time authorities.
final class SyncEngine {
  /// Documented.
  SyncEngine({
    required TrustedTimeConfig config,
    required MonotonicClock clock,
    SyncObserver? observer,
    ConsensusCache? cache,
  }) : _config = config,
       _clock = clock,
       _observer = observer,
       _cache = cache,
       _engine = MarzulloEngine(
         minQuorumRatio: config.minQuorumRatio,
         maxAllowedUncertaintyMs: config.maxAllowedUncertaintyMs,
         minGroupCount: config.minGroupCount,
       );

  final TrustedTimeConfig _config;
  final MonotonicClock _clock;
  final SyncObserver? _observer;
  final ConsensusCache? _cache;
  final MarzulloEngine _engine;

  /// Lazily-initialized list of authoritative time sources.
  late final List<TimeSource> _sources = [
    for (final host in _config.ntpServers) NtpSource(host),
    for (final url in _config.httpsSources) HttpsSource(url),
    for (final host in _config.ntsServers)
      NtsSource(
        host,
        port: _config.ntsPort,
        onStratumObserved: (s) =>
            _qualityTracker.setStratum('${TimeSource.prefixNts}$host', s),
      ),
    ..._config.additionalSources,
  ];

  /// Tracks consecutive failures for each source to implement exponential cooldown.
  final _sourceHealth = <String, int>{};

  /// Precise timestamps until which a source is considered "blacklisted."
  final _blacklistUntil = <String, DateTime>{};

  final _qualityTracker = SourceQualityTracker();

  int _syncAttempts = 0;

  /// Executes a full synchronization cycle across all healthy sources.
  ///
  /// This method is the primary driver of trust establishment. It races sources,
  /// performs adaptive outlier filtering, and requires stability across
  /// multiple samples before finalizing an anchor.
  Future<TrustAnchor> sync() async {
    _observer?.onSyncStarted();
    final swSync = Stopwatch()..start();

    final samples = <TimeSample>[];
    final completer = Completer<TrustAnchor>();
    var streamClosed = false;
    StreamSubscription<TimeSample?>? streamSub;
    final sampleController = StreamController<TimeSample?>();

    try {
      final now = DateTime.now();

      // Quality-ranked source ordering with starvation guard.
      // Sources that haven't been queried within _kStarvationCycles are always
      // included so their quality estimates remain fresh.
      final healthySources = _sources.where((s) {
        final until = _blacklistUntil[s.id];
        return until == null || now.isAfter(until);
      }).toList();

      final rankedIds = _qualityTracker.ranked(healthySources.map((s) => s.id));
      final activeSources = [
        // High-quality sources first, in ranked order.
        for (final id in rankedIds)
          healthySources.firstWhere((s) => s.id == id),
        // Starvation-forced sources not already in the ranked set.
        for (final s in healthySources)
          if (_qualityTracker.isStarved(s.id) && !rankedIds.contains(s.id)) s,
      ];

      var pendingQueries = activeSources.length;
      if (pendingQueries == 0) {
        throw TrustedTimeSyncException(
          'All available time sources are currently in exponential cooldown due to persistent failures.',
        );
      }

      TimeInterval? lastStabilityInterval;
      var stableCount = 0;
      var rejectedInvalid = 0;

      // 1. Process samples sequentially via a stream to preserve determinism
      // and prevent race conditions during list mutation. This ensures that
      // outlier filtering and consensus resolution always happen on a consistent
      // snapshot of the sample population.
      streamSub = sampleController.stream.listen((sample) {
        if (completer.isCompleted) return;

        if (sample != null) {
          // Filter samples with negative uncertainty early, before both Marzullo
          // and the anchor reduce. Negative uncertainty indicates clock errors.
          if (sample.uncertaintyMs < 0) {
            rejectedInvalid++;
            _observer?.onSourceFailed(
              sample.sourceId,
              'Sample rejected: negative uncertainty (RTT)',
            );
            pendingQueries--;
            if (pendingQueries == 0 && !completer.isCompleted) {
              _finalizeSync(
                samples,
                rejectedInvalid,
                activeSources.length,
                completer,
              );
            }
            return;
          }

          samples.add(sample);
          _observer?.onSampleReceived(sample);

          // Adaptive Outlier Filtering: Uses a median-based guard to identify
          // and exclude sources that deviate significantly from the population.
          if (samples.length >= 3) {
            final uncertainties = samples.map((s) => s.uncertaintyMs).toList()
              ..sort();
            final medianU = uncertainties[uncertainties.length ~/ 2];

            // Heuristic: If a sample's uncertainty is > 3x the median, it is
            // likely malicious or experiencing extreme network jitter.
            if (sample.uncertaintyMs > max(medianU * 3, 500)) {
              samples.remove(sample);
              _observer?.onSourceFailed(
                sample.sourceId,
                'Adaptive exclusion: statistical outlier detected',
              );
            }
          }

          final result = _engine.resolve(samples);
          if (result != null) {
            // Stability Check: Escalates quorum requirements if high variance
            // is detected, ensuring we don't anchor to a jittery consensus.
            final varianceDetected = samples.any(
              (s) =>
                  (s.interval.midpoint - result.utc.millisecondsSinceEpoch)
                      .abs() >
                  500,
            );
            final requiredStability = varianceDetected ? 3 : 2;

            if (lastStabilityInterval == result.interval) {
              stableCount++;
            } else {
              stableCount = 1;
            }
            lastStabilityInterval = result.interval;

            if (stableCount >= requiredStability) {
              // Early Exit: If configured, we return as soon as a stable quorum
              // is reached to minimize power and network consumption.
              if (_config.earlyExit || samples.length == activeSources.length) {
                swSync.stop();
                unawaited(
                  _completeSync(result, swSync.elapsedMilliseconds, completer),
                );
              }
            }
          }
        }

        pendingQueries--;
        if (pendingQueries == 0 && !completer.isCompleted) {
          _finalizeSync(
            samples,
            rejectedInvalid,
            activeSources.length,
            completer,
            elapsedMs: swSync.elapsedMilliseconds,
          );
        }
      });

      // 2. Launch racing queries
      for (final source in activeSources) {
        unawaited(
          _querySafe(source)
              .then((s) {
                if (!streamClosed && !sampleController.isClosed) {
                  sampleController.add(s);
                }
              })
              .catchError((Object e) {
                _observer?.onSourceFailed(source.id, e);
                if (!streamClosed && !sampleController.isClosed) {
                  sampleController.add(
                    null,
                  ); // Ensure pendingQueries still decrements
                }
              }),
        );
      }

      final anchor = await completer.future.timeout(
        _config.maxLatency + const Duration(seconds: 1),
        onTimeout: () {
          if (!completer.isCompleted &&
              samples.length >= _config.minimumQuorum) {
            final result = _engine.resolve(samples);
            if (result != null) {
              return _createAnchor(result);
            }
          }
          throw TrustedTimeSyncException(
            'Synchronization timed out before reaching a stable quorum.',
          );
        },
      );

      _syncAttempts = 0;
      _cache?.update(anchor);
      _qualityTracker.advanceCycle();
      return anchor;
    } catch (e) {
      _observer?.onSyncFailed(e);
      _syncAttempts++;
      if (!completer.isCompleted) completer.completeError(e);
      rethrow;
    } finally {
      streamClosed = true;
      // Cancel subscription first to prevent hanging when controller closes
      await streamSub?.cancel();
      await sampleController.close();
    }
  }

  Future<void> _completeSync(
    ConsensusResult result,
    int latencyMs,
    Completer<TrustAnchor> completer,
  ) async {
    if (completer.isCompleted) return;

    try {
      final anchor = await _createAnchor(result);
      _observer?.onConsensusReached(result);

      // Record quality observations for all participant samples.
      final participantIds = result.participants.map((s) => s.sourceId).toSet();
      for (final sample in result.participants) {
        _qualityTracker.record(
          sourceId: sample.sourceId,
          uncertaintyMs: sample.uncertaintyMs,
          participatedInConsensus: participantIds.contains(sample.sourceId),
        );
      }

      _observer?.onMetricsReported(
        SyncMetrics(
          latencyMs: latencyMs,
          uncertaintyMs: result.uncertaintyMs,
          participantCount: result.participantCount,
          groupCount: result.groupCount,
          confidence: result.confidence,
          confidenceBreakdown: {
            'depth': result.participantCount / _sources.length,
            'diversity': result.groupCount / 2.0,
            'stability': 1.0,
          },
        ),
      );

      if (!completer.isCompleted) completer.complete(anchor);
    } catch (e) {
      if (!completer.isCompleted) completer.completeError(e);
    }
  }

  Future<TrustAnchor> _createAnchor(ConsensusResult result) async {
    // Anchor selection validates that consensus has participant samples.
    // This prevents outliers from corrupting the monotonic clock reference.
    final participantSamples = result.participants;
    if (participantSamples.isEmpty) {
      throw TrustedTimeSyncException(
        'Consensus result has no participant samples',
      );
    }

    final uptimeMs = await _clock.uptimeMs();
    final wallMs = DateTime.now().millisecondsSinceEpoch;

    return TrustAnchor(
      networkUtcMs: result.utc.millisecondsSinceEpoch,
      uptimeMs: uptimeMs,
      wallMs: wallMs,
      uncertaintyMs: result.uncertaintyMs,
      authLevel: result.authLevel,
      confidence: result.confidence,
    );
  }

  /// Finalizes synchronization when all queries complete.
  void _finalizeSync(
    List<TimeSample> samples,
    int rejectedInvalid,
    int totalSources,
    Completer<TrustAnchor> completer, {
    int? elapsedMs,
  }) {
    if (completer.isCompleted) return;

    // All sources responded but we haven't reached stability.
    // Try one final resolve with all samples before failing.
    final finalResult = _engine.resolve(samples);
    if (finalResult != null && samples.length >= _config.minimumQuorum) {
      unawaited(_completeSync(finalResult, elapsedMs ?? 0, completer));
    } else {
      // Improved quorum-failure messaging with accurate counts
      final eligibleCount = samples.length;
      final sampleWord = eligibleCount == 1 ? 'sample' : 'samples';
      final rejectedWord = rejectedInvalid == 1 ? 'source was' : 'sources were';

      completer.completeError(
        TrustedTimeSyncException(
          'Failed to reach quorum: got $eligibleCount eligible $sampleWord '
          '($rejectedInvalid $rejectedWord rejected as invalid) from $totalSources total sources.',
        ),
      );
    }
  }

  /// Wraps a source query with timeout and health-tracking logic.
  Future<TimeSample?> _querySafe(TimeSource source) async {
    try {
      final sample = await source.getTime().timeout(_config.maxLatency);
      _sourceHealth[source.id] = 0; // Reset failure count on success
      _blacklistUntil.remove(source.id);
      return sample;
    } catch (e) {
      _observer?.onSourceFailed(source.id, e);
      _qualityTracker.recordFailure(source.id);

      final score = (_sourceHealth[source.id] ?? 0) + 1;
      _sourceHealth[source.id] = score;
      final cooldownMin = pow(2, min(score, 6)).toInt();
      _blacklistUntil[source.id] = DateTime.now().add(
        Duration(minutes: cooldownMin),
      );

      return null;
    }
  }

  /// Calculates the next retry delay for the entire engine.
  Duration getNextRetryDelay() {
    if (_syncAttempts == 0) return Duration.zero;
    final exponent = min(_syncAttempts, 8);
    final seconds = pow(2, exponent).toInt();
    return Duration(seconds: seconds);
  }

  /// Releases network and platform resources.
  void dispose() {
    for (final source in _sources) {
      if (source is HttpsSource) source.dispose();
    }
  }
}
