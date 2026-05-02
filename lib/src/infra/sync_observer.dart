import '../domain/time_sample.dart';
import '../domain/marzullo_engine.dart';
import '../models.dart';

/// ## Absolute Top Tier: Telemetry and Observability
///
/// [SyncObserver] provides a high-fidelity interface for monitoring the
/// internal synchronization lifecycle of the engine.
///
/// Implement this interface to capture diagnostic metrics, audit security
/// events, or provide real-time feedback to the end-user during
/// synchronization cycles.
abstract interface class SyncObserver {
  /// Called when a synchronization cycle is initiated by the engine.
  void onSyncStarted();

  /// Called when a raw [TimeSample] is successfully retrieved from a
  /// remote time authority.
  void onSampleReceived(TimeSample sample);

  /// Called when a specific source query fails (e.g., timeout or network error).
  void onSourceFailed(String sourceId, Object error);

  /// Called when the [MarzulloEngine] successfully resolves a new consensus
  /// from the available samples.
  void onConsensusReached(ConsensusResult result);

  /// Called when the entire synchronization cycle fails (e.g., quorum not met).
  void onSyncFailed(Object error);

  /// Called when comprehensive [SyncMetrics] are generated for a completed cycle.
  void onMetricsReported(SyncMetrics metrics);
}
