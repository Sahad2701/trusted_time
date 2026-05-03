import 'package:flutter/foundation.dart';

/// ## Absolute Top Tier: High-Fidelity Temporal Estimation
///
/// [TrustedTimeEstimate] provides a best-effort extrapolated time for scenarios
/// where the device is offline or has lost its primary trust anchor.
///
/// While the core [TrustedTime] engine requires a network-verified quorum for
/// "Absolute Truth," this class allows applications to maintain operational
/// continuity by projecting time based on the last known verified state.
///
/// **Security Note**: This estimate is NOT tamper-proof. It relies on the
/// device oscillator and wall clock, which can be manipulated by a determined
/// adversary. Always check the [confidence] score before using this for
/// security-critical logic.
@immutable
final class TrustedTimeEstimate {
  /// Creates a magnificent temporal estimate.
  const TrustedTimeEstimate({
    required this.estimatedTime,
    required this.confidence,
    required this.estimatedError,
  });

  /// The extrapolated UTC time based on the last known trust anchor.
  ///
  /// This value is calculated by applying the elapsed hardware-anchored time
  /// since the last verified sync to the baseline network timestamp.
  final DateTime estimatedTime;

  /// Qualitative confidence score in the range `[0.0, 1.0]`.
  ///
  /// This value decays linearly as time passes without a successful network
  /// synchronization.
  /// - **1.0**: Absolute trust (fresh anchor).
  /// - **0.5**: Moderate trust (approx. 36 hours since last sync).
  /// - **0.0**: Zero trust (stale or invalidated state).
  final double confidence;

  /// The calculated absolute error margin (uncertainty).
  ///
  /// This represents the potential drift accumulated since the last verified
  /// synchronization, based on the [TrustedTimeConfig.oscillatorDriftFactor].
  final Duration estimatedError;

  /// Returns `true` if the estimate is considered reasonable for standard UX display.
  ///
  /// The default threshold is [confidence] >= 0.5. Applications with high-precision
  /// requirements should manually verify [estimatedError] instead.
  bool get isReasonable => confidence >= 0.5;

  @override
  String toString() => 'TrustedTimeEstimate(time: $estimatedTime, '
      'confidence: ${confidence.toStringAsFixed(3)}, '
      'error: ±${estimatedError.inSeconds}s)';
}
