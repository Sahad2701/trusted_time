import '../domain/time_sample.dart';
import '../domain/marzullo_engine.dart';

/// Observer for synchronization events.
/// Use this for telemetry and monitoring.
abstract interface class SyncObserver {
  /// Called when a synchronization cycle starts.
  void onSyncStarted();

  /// Called when a sample is received from a source.
  void onSampleReceived(TimeSample sample);

  /// Called when a source query fails.
  void onSourceFailed(String sourceId, Object error);

  /// Called when a consensus is reached.
  void onConsensusReached(ConsensusResult result);

  /// Called when a synchronization cycle fails.
  void onSyncFailed(Object error);
}
