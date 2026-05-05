import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/integrity_event.dart';
import 'package:trusted_time/src/trusted_time_estimate.dart';

void main() {
  group('IntegrityEvent', () {
    test('toString includes reason and drift', () {
      final event = IntegrityEvent(
        reason: TamperReason.systemClockJumped,
        detectedAt: DateTime.utc(2024, 1, 1),
        drift: const Duration(minutes: 5),
      );
      final str = event.toString();
      expect(str, contains('systemClockJumped'));
      expect(str, contains('0:05:00'));
    });

    test('drift can be null', () {
      final event = IntegrityEvent(
        reason: TamperReason.deviceRebooted,
        detectedAt: DateTime.utc(2024, 1, 1),
      );
      expect(event.drift, isNull);
      expect(event.reason, TamperReason.deviceRebooted);
    });

    test('all TamperReason variants exist', () {
      expect(
        TamperReason.values,
        containsAll([
          TamperReason.systemClockJumped,
          TamperReason.timezoneChanged,
          TamperReason.deviceRebooted,
          TamperReason.forcedNtpSync,
          TamperReason.unknown,
        ]),
      );
    });
  });

  group('TrustedTimeEstimate', () {
    test('isReasonable returns true when confidence >= 0.5', () {
      final estimate = TrustedTimeEstimate(
        estimatedTime: DateTime.utc(2024, 1, 1),
        confidence: 0.5,
        estimatedError: const Duration(seconds: 10),
      );
      expect(estimate.isReasonable, isTrue);
    });

    test('isReasonable returns false when confidence < 0.5', () {
      final estimate = TrustedTimeEstimate(
        estimatedTime: DateTime.utc(2024, 1, 1),
        confidence: 0.49,
        estimatedError: const Duration(seconds: 10),
      );
      expect(estimate.isReasonable, isFalse);
    });

    test('toString includes confidence and error', () {
      final estimate = TrustedTimeEstimate(
        estimatedTime: DateTime.utc(2024, 1, 1),
        confidence: 0.75,
        estimatedError: const Duration(seconds: 30),
      );
      final str = estimate.toString();
      expect(str, contains('0.750'));
      expect(str, contains('30'));
    });
  });
}
