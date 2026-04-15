import 'dart:async';
import 'package:flutter/foundation.dart';
import 'exceptions.dart';
import 'models.dart';
import 'marzullo.dart';
import 'monotonic_clock.dart';
import 'sources/time_sources.dart';

/// Orchestrates parallel queries across multiple time authorities to establish
/// a quorum-based trust anchor.
///
/// The [SyncEngine] builds a list of [TrustedTimeSource] instances from the
/// [TrustedTimeConfig] and queries them concurrently. Valid responses are
/// fed into the [MarzulloEngine] to compute a consensus UTC time with bounded
/// uncertainty.
final class SyncEngine {
  /// Creates a sync engine with the given [config] and [clock].
  SyncEngine({required TrustedTimeConfig config, required MonotonicClock clock})
    : _config = config,
      _clock = clock,
      _engine = MarzulloEngine(minimumQuorum: config.minimumQuorum);

  final TrustedTimeConfig _config;
  final MonotonicClock _clock;
  final MarzulloEngine _engine;

  /// Lazily built list of time authorities from config servers and custom
  /// sources.
  late final List<TrustedTimeSource> _sources = [
    for (final host in _config.ntpServers) NtpSource(host),
    for (final url in _config.httpsSources) HttpsSource(url),
    ..._config.additionalSources,
  ];

  /// Executes concurrent sampling and returns a hardware-pinned trust anchor.
  ///
  /// Queries all configured time sources in parallel, filters by maximum
  /// latency, and uses Marzullo's algorithm to find the consensus interval.
  ///
  /// Throws [TrustedTimeSyncException] if no sources respond or if quorum
  /// cannot be reached.
  Future<TrustAnchor> sync() async {
    final samples = await _queryConcurrently();
    if (samples.isEmpty) {
      throw const TrustedTimeSyncException(
        'Every configured time source failed to respond.',
      );
    }

    final result = _engine.resolve(samples);
    if (result == null) {
      throw TrustedTimeSyncException(
        'Quorum not reached: got ${samples.length} samples, '
        'need ${_config.minimumQuorum} for intersection.',
      );
    }

    final uptimeMs = await _clock.uptimeMs();
    final wallMs = DateTime.now().millisecondsSinceEpoch;

    return TrustAnchor(
      networkUtcMs: result.utc.millisecondsSinceEpoch,
      uptimeMs: uptimeMs,
      wallMs: wallMs,
      uncertaintyMs: result.uncertaintyMs,
    );
  }

  /// Releases resources held by time sources (e.g., open HTTP clients).
  void dispose() {
    for (final source in _sources) {
      if (source is HttpsSource) source.dispose();
    }
  }

  /// Queries all sources concurrently and filters by max latency.
  Future<List<SourceSample>> _queryConcurrently() async {
    final results = await Future.wait(_sources.map(_querySafe));
    return results
        .whereType<SourceSample>()
        .where((s) => s.roundTripMs <= _config.maxLatency.inMilliseconds)
        .toList();
  }

  /// Wraps a source query in a try-catch with timeout enforcement.
  ///
  /// Returns `null` on failure to allow graceful degradation.
  Future<SourceSample?> _querySafe(TrustedTimeSource source) async {
    try {
      final sw = Stopwatch()..start();
      final utc = await source.queryUtc().timeout(_config.maxLatency);
      sw.stop();
      return SourceSample(
        sourceId: source.id,
        utc: utc,
        roundTripMs: sw.elapsedMilliseconds,
      );
    } catch (e) {
      debugPrint('[TrustedTime] Source ${source.id} failed: $e');
      return null;
    }
  }
}
