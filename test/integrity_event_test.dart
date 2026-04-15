import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/integrity_event.dart';

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
      expect(TamperReason.values, containsAll([
        TamperReason.systemClockJumped,
        TamperReason.timezoneChanged,
        TamperReason.deviceRebooted,
        TamperReason.forcedNtpSync,
        TamperReason.unknown,
      ]));
    });
  });

  group('TrustedTimeEstimate (via mock)', () {
    // Covered in trusted_time_impl_test.dart
  });
}
