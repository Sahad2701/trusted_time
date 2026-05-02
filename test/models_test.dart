import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/models.dart';
import 'package:trusted_time/src/sources/nts_source.dart';

void main() {
  group('TrustAnchor Deserialization Safety (CRITICAL-6)', () {
    test('handles invalid NtsAuthLevel index gracefully', () {
      final json = {
        'networkUtcMs': 1000000,
        'uptimeMs': 50000,
        'wallMs': 1000000,
        'uncertaintyMs': 10,
        'authLevel': 999, // Out of bounds
        'confidence': 1,
        'syncTime': 1000000,
      };

      final anchor = TrustAnchor.fromJson(json);
      expect(anchor.authLevel, NtsAuthLevel.none);
    });

    test('handles invalid ConfidenceLevel index gracefully', () {
      final json = {
        'networkUtcMs': 1000000,
        'uptimeMs': 50000,
        'wallMs': 1000000,
        'uncertaintyMs': 10,
        'authLevel': 1,
        'confidence': -1, // Out of bounds
        'syncTime': 1000000,
      };

      final anchor = TrustAnchor.fromJson(json);
      expect(anchor.confidence, ConfidenceLevel.low);
    });

    test('handles missing optional fields with safe defaults', () {
      final json = {
        'networkUtcMs': 1000000,
        'uptimeMs': 50000,
        'wallMs': 1000000,
        'uncertaintyMs': 10,
      };

      final anchor = TrustAnchor.fromJson(json);
      expect(anchor.authLevel, NtsAuthLevel.none);
      expect(anchor.confidence, ConfidenceLevel.low);
    });
  });
}
