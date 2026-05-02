import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/trusted_time.dart';

void main() {
  group('Security Policy Enforcement (CRITICAL-4, 5)', () {
    test('getTime(requireSecure: true) fails when authLevel is advisory',
        () async {
      final mock = TrustedTimeMock(initial: DateTime.now());
      mock.setTrusted(true);
      mock.setAuthLevel(NtsAuthLevel.advisory);

      TrustedTime.overrideForTesting(mock);

      expect(() => TrustedTime.getTime(requireSecure: true),
          throwsA(isA<TrustedTimeSecurityException>()));

      TrustedTime.resetOverride();
    });

    test('isSecure returns false for advisory authLevel', () {
      final mock = TrustedTimeMock(initial: DateTime.now());
      mock.setAuthLevel(NtsAuthLevel.advisory);
      TrustedTime.overrideForTesting(mock);

      expect(TrustedTime.isSecure, isFalse);

      TrustedTime.resetOverride();
    });
  });
}
