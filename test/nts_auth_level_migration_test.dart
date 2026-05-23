import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/sources/nts_auth_level.dart';
import 'package:trusted_time/src/models.dart';

void main() {
  group('NtsAuthLevel post-advisory removal', () {
    test('enum has exactly two variants: none and verified', () {
      expect(NtsAuthLevel.values, hasLength(2));
      expect(
        NtsAuthLevel.values,
        containsAll([NtsAuthLevel.none, NtsAuthLevel.verified]),
      );
    });

    test('none is at index 0, verified at index 1', () {
      expect(NtsAuthLevel.none.index, equals(0));
      expect(NtsAuthLevel.verified.index, equals(1));
    });
  });

  group('TrustAnchor.fromJson v2.0.x → v2.1.0 migration', () {
    TrustAnchor makeAnchor(int authIdx) => TrustAnchor.fromJson({
      'networkUtcMs': 1_700_000_000_000,
      'uptimeMs': 12345,
      'wallMs': 1_700_000_000_000,
      'uncertaintyMs': 50,
      'authLevel': authIdx,
      'confidence': 0,
    });

    test('old index 0 (none) decodes as none', () {
      expect(makeAnchor(0).authLevel, equals(NtsAuthLevel.none));
    });

    test('old index 1 (advisory) decodes as none to degrade safely', () {
      // advisory was index 1 in v2.0.x. Should downgrade to none, not
      // misidentify as verified.
      expect(makeAnchor(1).authLevel, equals(NtsAuthLevel.none));
    });

    test('old index 2 (verified) decodes as verified', () {
      expect(makeAnchor(2).authLevel, equals(NtsAuthLevel.verified));
    });

    test('out-of-range index falls back to none', () {
      expect(makeAnchor(99).authLevel, equals(NtsAuthLevel.none));
    });
  });
}
