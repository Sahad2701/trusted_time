import 'package:flutter/foundation.dart';

/// Exhaustive reasons why the trusted time baseline was compromised.
///
/// Each variant represents a distinct class of temporal integrity violation
/// that the `IntegrityMonitor` can detect, either through native OS signals
/// or through the engine's own consistency checks.
enum TamperReason {
  /// The OS reports a significant change in the system wall clock.
  ///
  /// Triggered by `ACTION_TIME_CHANGED` on Android or equivalent iOS
  /// notifications.
  systemClockJumped,

  /// The device timezone was changed via OS settings.
  ///
  /// While this doesn't necessarily indicate tampering, it may affect
  /// local time calculations and is worth monitoring.
  timezoneChanged,

  /// A hardware reboot was detected via monotonic uptime reset.
  ///
  /// After a reboot the monotonic clock restarts from zero, invalidating
  /// the current trust anchor.
  deviceRebooted,

  /// A resync was manually triggered via [TrustedTime.forceResync].
  ///
  /// The engine does not emit this reason internally — it is reserved
  /// for consumer-side auditing. Applications may emit it via
  /// [TrustedTimeMock.simulateTampering] to test forced-resync paths.
  forcedNtpSync,

  /// The root cause could not be determined from available platform
  /// signals.
  unknown,
}

/// Encapsulates a single violation of the temporal baseline with forensic
/// metadata.
///
/// [IntegrityEvent]s are emitted on the [TrustedTime.onIntegrityLost] stream
/// whenever the engine detects a compromise of its trust anchor — whether
/// from a clock jump, timezone change, device reboot, or unknown cause.
///
/// ```dart
/// TrustedTime.onIntegrityLost.listen((event) {
///   log('Integrity lost: ${event.reason}, drift: ${event.drift}');
/// });
/// ```
@immutable
final class IntegrityEvent {
  /// Creates an integrity event with the given [reason] and detection
  /// timestamp.
  const IntegrityEvent({
    required this.reason,
    required this.detectedAt,
    this.drift,
  });

  /// The root cause identified by the integrity monitor.
  final TamperReason reason;

  /// UTC timestamp of when the violation was detected.
  final DateTime detectedAt;

  /// The measured magnitude of the clock discrepancy, if available.
  ///
  /// For [TamperReason.systemClockJumped], this represents the size of
  /// the jump. For [TamperReason.timezoneChanged], the offset difference.
  final Duration? drift;

  @override
  String toString() =>
      'IntegrityEvent(reason: $reason, drift: $drift, at: $detectedAt)';
}
