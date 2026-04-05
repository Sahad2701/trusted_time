import 'package:flutter/foundation.dart';

/// Best-effort estimated time for offline scenarios.
///
/// When the device has lost its trust anchor (e.g., after a reboot with no
/// network connectivity), [TrustedTime.nowEstimated] returns a
/// [TrustedTimeEstimate] that extrapolates from the last known anchor using
/// the device's wall clock and an estimated oscillator drift factor.
///
/// **This estimate is NOT tamper-proof** — it relies on the (manipulatable)
/// system wall clock. Use the [confidence] value to determine if the
/// estimate is suitable for your use case.
@immutable
final class TrustedTimeEstimate {
  /// Creates an estimate with the given parameters.
  const TrustedTimeEstimate({
    required this.estimatedTime,
    required this.confidence,
    required this.estimatedError,
  });

  /// The extrapolated UTC time based on the last known trust anchor and
  /// elapsed wall-clock time.
  final DateTime estimatedTime;

  /// Confidence score in the range `[0.0, 1.0]`.
  ///
  /// Decays linearly from 1.0 to 0.0 over 72 hours (4320 minutes) of
  /// elapsed time since the last valid anchor. A value of 0.5 means
  /// approximately 36 hours have passed.
  final double confidence;

  /// The calculated absolute error margin.
  ///
  /// Computed as: `elapsedTime × oscillatorDriftFactor`. Larger values
  /// indicate less certainty about the estimated time's accuracy.
  final Duration estimatedError;

  /// Returns `true` if the estimate is stable enough for typical UX display.
  ///
  /// The threshold is [confidence] ≥ 0.5 (approximately ≤ 36 hours offline).
  bool get isReasonable => confidence >= 0.5;

  @override
  String toString() =>
      'TrustedTimeEstimate(time: $estimatedTime, '
      'confidence: ${confidence.toStringAsFixed(3)}, '
      'error: ±${estimatedError.inSeconds}s)';
}
