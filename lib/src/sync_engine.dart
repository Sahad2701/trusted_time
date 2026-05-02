import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'domain/marzullo_engine.dart';
import 'domain/time_sample.dart';
import 'domain/time_source.dart';
import 'domain/time_interval.dart';
import 'exceptions.dart';
import 'models.dart';
import 'monotonic_clock.dart';
import 'sources/time_sources.dart';
import 'infra/sync_observer.dart';
import 'infra/consensus_cache.dart';

/// Orchestrates the distributed synchronization lifecycle across multiple 
/// time authorities.
///
/// The [SyncEngine] is responsible for:
/// 1. **Racing Parallelism**: Querying multiple NTP, HTTPS, and NTS sources 
///    concurrently to minimize latency.
/// 2. **Self-Healing Health**: Managing exponential cooldowns for unreliable 
///    or failing sources.
/// 3. **Adaptive Stability**: Escalating quorum requirements when high variance 
///    is detected in the sampling population.
/// 4. **Early Exit**: Triggering immediate consensus resolution once a 
///    stable quorum is reached, conserving battery and data.
final class SyncEngine {
  SyncEngine({
    required TrustedTimeConfig config,
    required MonotonicClock clock,
    SyncObserver? observer,
    ConsensusCache? cache,
  })  : _config = config,
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
      NtsSource(host, port: _config.ntsPort),
    ..._config.additionalSources,
  ];

  /// Tracks consecutive failures for each source to implement exponential cooldown.
  final _sourceHealth = <String, int>{}; 
  
  /// Precise timestamps until which a source is considered "blacklisted."
  final _blacklistUntil = <String, DateTime>{};
  
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
    final sampleController = StreamController<TimeSample?>();
    
    try {
      final now = DateTime.now();
      final activeSources = _sources.where((s) {
        final until = _blacklistUntil[s.id];
        return until == null || now.isAfter(until);
      }).toList();

      var pendingQueries = activeSources.length;
      if (pendingQueries == 0) {
        throw TrustedTimeSyncException(
          'All available time sources are currently in exponential cooldown due to persistent failures.'
        );
      }

      TimeInterval? lastStabilityInterval;
      var stableCount = 0;

      // 1. Process samples sequentially via a stream to preserve determinism 
      // and prevent race conditions during list mutation.
      final streamSub = sampleController.stream.listen((sample) {
        if (completer.isCompleted) return;

        if (sample != null) {
          samples.add(sample);
          _observer?.onSampleReceived(sample);

          // Adaptive Outlier Filtering
          if (samples.length >= 3) {
            final uncertainties = samples.map((s) => s.uncertaintyMs).toList()..sort();
            final medianU = uncertainties[uncertainties.length ~/ 2];
            if (sample.uncertaintyMs > max(medianU * 3, 500)) {
              samples.remove(sample);
              _observer?.onSourceFailed(sample.sourceId, 'Adaptive exclusion: statistical outlier detected');
            }
          }

          final result = _engine.resolve(samples);
          if (result != null) {
            final varianceDetected = samples.any(
              (s) => (s.interval.midpoint - result.utc.millisecondsSinceEpoch).abs() > 500
            );
            final requiredStability = varianceDetected ? 3 : 2;

            if (lastStabilityInterval == result.interval) {
              stableCount++;
            } else {
              stableCount = 1;
            }
            lastStabilityInterval = result.interval;

            if (stableCount >= requiredStability) {
              if (_config.earlyExit || samples.length == activeSources.length) {
                swSync.stop();
                _completeSync(result, swSync.elapsedMilliseconds, completer);
              }
            }
          }
        }

        pendingQueries--;
        if (pendingQueries == 0 && !completer.isCompleted) {
          completer.completeError(
            TrustedTimeSyncException('Failed to reach quorum after exhausting all healthy sources.')
          );
        }
      });

      // 2. Launch racing queries
      for (final source in activeSources) {
        _querySafe(source).then((s) {
          if (!sampleController.isClosed) sampleController.add(s);
        });
      }

      final anchor = await completer.future.timeout(
        _config.maxLatency + const Duration(seconds: 1),
        onTimeout: () {
          if (!completer.isCompleted && samples.length >= _config.minimumQuorum) {
             final result = _engine.resolve(samples);
             if (result != null) return _createAnchor(result);
          }
          throw TrustedTimeSyncException('Synchronization timed out before reaching a stable quorum.');
        }
      ).whenComplete(() {
        streamSub.cancel();
        sampleController.close();
      });

      _syncAttempts = 0; 
      _cache?.update(anchor);
      return anchor;
    } catch (e) {
      _observer?.onSyncFailed(e);
      _syncAttempts++;
      if (!completer.isCompleted) {
        completer.completeError(e); // Ensure future unblocks on error
      }
      rethrow;
    }
  }

  Future<void> _completeSync(ConsensusResult result, int latencyMs, Completer<TrustAnchor> completer) async {
    if (completer.isCompleted) return;
    
    try {
      final anchor = await _createAnchor(result);
      _observer?.onConsensusReached(result);
      
      _observer?.onMetricsReported(SyncMetrics(
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
      ));

      if (!completer.isCompleted) completer.complete(anchor);
    } catch (e) {
      if (!completer.isCompleted) completer.completeError(e);
    }
  }

  Future<TrustAnchor> _createAnchor(ConsensusResult result) async {
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

  /// Wraps a source query with timeout and health-tracking logic.
  Future<TimeSample?> _querySafe(TimeSource source) async {
    try {
      final sample = await source.getTime().timeout(_config.maxLatency);
      _sourceHealth[source.id] = 0; // Reset failure count on success
      _blacklistUntil.remove(source.id);
      return sample;
    } catch (e) {
      _observer?.onSourceFailed(source.id, e);
      
      final score = (_sourceHealth[source.id] ?? 0) + 1;
      _sourceHealth[source.id] = score;
      final cooldownMin = pow(2, min(score, 6)).toInt();
      _blacklistUntil[source.id] = DateTime.now().add(Duration(minutes: cooldownMin));
      
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
