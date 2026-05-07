import 'package:flutter/foundation.dart';
import 'package:trusted_time/trusted_time.dart';

/// The kind of telemetry event captured from a [SyncObserver] callback.
enum TelemetryKind {
  syncStarted,
  sample,
  sourceFailed,
  consensus,
  metrics,
  syncFailed,
}

/// A single observable event in the synchronization lifecycle, stamped
/// with elapsed time since the recorder was constructed.
@immutable
class TelemetryEvent {
  const TelemetryEvent({
    required this.elapsedMs,
    required this.kind,
    required this.detail,
  });
  final int elapsedMs;
  final TelemetryKind kind;
  final String detail;
}

/// A [SyncObserver] that records every callback into a bounded ring of
/// [TelemetryEvent]s and notifies listeners so the UI can render the
/// per-source pipeline behaviour.
///
/// `onSourceFailed` events surface the engine's `'warm: <error>'`
/// prefix when a [Warmable] source's warm phase throws, letting the UI
/// distinguish warming-phase failures from query-phase failures without
/// any extra plumbing.
class TelemetryRecorder extends ChangeNotifier implements SyncObserver {
  TelemetryRecorder() : _start = Stopwatch()..start();

  static const int _maxEvents = 50;

  final Stopwatch _start;
  final List<TelemetryEvent> _events = [];

  /// Snapshot of recorded events, oldest first.
  List<TelemetryEvent> get events => List.unmodifiable(_events);

  void _add(TelemetryKind kind, String detail) {
    _events.add(
      TelemetryEvent(
        elapsedMs: _start.elapsedMilliseconds,
        kind: kind,
        detail: detail,
      ),
    );
    if (_events.length > _maxEvents) {
      _events.removeRange(0, _events.length - _maxEvents);
    }
    notifyListeners();
  }

  /// Removes all recorded events and resets the elapsed-time origin.
  void reset() {
    _events.clear();
    _start
      ..reset()
      ..start();
    notifyListeners();
  }

  @override
  void onSyncStarted() => _add(TelemetryKind.syncStarted, 'cycle started');

  @override
  void onSampleReceived(TimeSample sample) {
    _add(
      TelemetryKind.sample,
      '${sample.sourceId} '
      'window=${sample.interval.endMs - sample.interval.startMs}ms '
      'auth=${sample.authLevel.name}',
    );
  }

  @override
  void onSourceFailed(String sourceId, Object error) {
    _add(TelemetryKind.sourceFailed, '$sourceId: $error');
  }

  @override
  void onConsensusReached(ConsensusResult result) {
    _add(
      TelemetryKind.consensus,
      'utc=${result.utc.toIso8601String()} '
      '±${result.uncertaintyMs}ms '
      'participants=${result.participantCount} '
      'groups=${result.groupCount}',
    );
  }

  @override
  void onMetricsReported(SyncMetrics metrics) {
    _add(
      TelemetryKind.metrics,
      'latency=${metrics.latencyMs}ms '
      'uncertainty=${metrics.uncertaintyMs}ms '
      'confidence=${metrics.confidence.name}',
    );
  }

  @override
  void onSyncFailed(Object error) {
    _add(TelemetryKind.syncFailed, error.toString());
  }
}
