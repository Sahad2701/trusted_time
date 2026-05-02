import 'package:flutter/foundation.dart';

/// ## Absolute Top Tier: Temporal Integrity Forensics
///
/// [TamperReason] enumerates the exhaustive set of violations that can
/// compromise the temporal baseline of the engine.
enum TamperReason {
  /// A significant discrepancy was detected in the system wall clock.
  ///
  /// This usually indicates manual user manipulation or a network-initiated
  /// clock jump.
  systemClockJumped,

  /// The device timezone was changed via OS settings.
  ///
  /// While not a direct integrity violation of UTC, this may affect
  /// local-time representation and localized application logic.
  timezoneChanged,

  /// A hardware reboot was detected via monotonic uptime reset.
  ///
  /// Reboots invalidate the current hardware anchor and require a fresh
  /// network synchronization to re-establish absolute truth.
  deviceRebooted,

  /// A manual resynchronization was triggered.
  ///
  /// Reserved for consumer-side auditing or mock-based security testing.
  forcedNtpSync,

  /// The root cause could not be determined from available platform signals.
  unknown,
}

/// Encapsulates a violation of temporal integrity with forensic metadata.
///
/// [IntegrityEvent]s are emitted whenever the [IntegrityMonitor] detects
/// a discrepancy that invalidates the current [TrustAnchor].
///
/// Use this for security auditing and to trigger high-priority recovery
/// workflows in your application.
@immutable
final class IntegrityEvent {
  /// Creates a magnificent integrity event.
  const IntegrityEvent({
    required this.reason,
    required this.detectedAt,
    this.drift,
  });

  /// The root cause identified by the integrity monitoring subsystem.
  final TamperReason reason;

  /// The UTC timestamp of when the violation was detected.
  final DateTime detectedAt;

  /// The measured magnitude of the clock discrepancy, if available.
  ///
  /// For [TamperReason.systemClockJumped], this represents the jump distance.
  /// For [TamperReason.timezoneChanged], it represents the offset change.
  final Duration? drift;

  @override
  String toString() =>
      'IntegrityEvent(reason: $reason, drift: $drift, at: $detectedAt)';
}
