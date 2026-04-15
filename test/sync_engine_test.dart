import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/exceptions.dart';
import 'package:trusted_time/src/models.dart';
import 'package:trusted_time/src/marzullo.dart';

void main() {
  // ── Finding 8 / 12: SyncEngine throws TrustedTimeSyncException ──

  group('TrustedTimeSyncException', () {
    test('TrustedTimeSyncException toString includes message', () {
      const e = TrustedTimeSyncException('test message');
      expect(e.toString(), contains('test message'));
    });

    test('TrustedTimeSyncException is catchable as Exception', () {
      expect(
        () => throw const TrustedTimeSyncException('quorum failed'),
        throwsA(isA<TrustedTimeSyncException>()),
      );
    });

    test('TrustedTimeNotReadyException has descriptive message', () {
      const e = TrustedTimeNotReadyException();
      expect(e.toString(), contains('initialize'));
    });
  });

  // ── Finding 8: TrustedTimeConfig equality includes server lists ──

  group('TrustedTimeConfig equality', () {
    test('configs with same servers are equal', () {
      const a = TrustedTimeConfig(ntpServers: ['time.google.com']);
      const b = TrustedTimeConfig(ntpServers: ['time.google.com']);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('configs with different ntpServers are NOT equal', () {
      const a = TrustedTimeConfig(ntpServers: ['time.google.com']);
      const b = TrustedTimeConfig(ntpServers: ['pool.ntp.org']);
      expect(a, isNot(equals(b)));
    });

    test('configs with different httpsSources are NOT equal', () {
      const a = TrustedTimeConfig(
        httpsSources: ['https://www.google.com'],
      );
      const b = TrustedTimeConfig(
        httpsSources: ['https://www.cloudflare.com'],
      );
      expect(a, isNot(equals(b)));
    });

    test('configs with different refreshInterval are NOT equal', () {
      const a = TrustedTimeConfig(
        refreshInterval: Duration(hours: 6),
      );
      const b = TrustedTimeConfig(
        refreshInterval: Duration(hours: 12),
      );
      expect(a, isNot(equals(b)));
    });
  });

  // ── Finding 5: Marzullo tie-breaking ──

  group('MarzulloEngine tie-breaking', () {
    test('touching intervals at exact same point resolve correctly', () {
      const engine = MarzulloEngine(minimumQuorum: 2);
      final t = DateTime.utc(2024, 1, 1, 12);
      final tMs = t.millisecondsSinceEpoch;

      // Source A: [tMs - 10, tMs + 10] (uncertainty = 10)
      // Source B: [tMs + 10, tMs + 30] (center tMs+20, uncertainty = 10)
      // They touch at exactly tMs + 10
      final result = engine.resolve([
        SourceSample(sourceId: 'a', utc: t, roundTripMs: 20),
        SourceSample(
          sourceId: 'b',
          utc: DateTime.fromMillisecondsSinceEpoch(tMs + 20, isUtc: true),
          roundTripMs: 20,
        ),
      ]);

      expect(result, isNotNull);
      expect(result!.participantCount, 2);
    });

    test('non-overlapping intervals return null', () {
      const engine = MarzulloEngine(minimumQuorum: 2);
      final t = DateTime.utc(2024, 1, 1, 12);
      final tMs = t.millisecondsSinceEpoch;

      final result = engine.resolve([
        SourceSample(sourceId: 'a', utc: t, roundTripMs: 10),
        SourceSample(
          sourceId: 'b',
          utc: DateTime.fromMillisecondsSinceEpoch(tMs + 1000, isUtc: true),
          roundTripMs: 10,
        ),
      ]);

      expect(result, isNull);
    });
  });

  // ── TrustAnchor serialization round-trip ──

  group('TrustAnchor', () {
    test('toJson / fromJson round-trip preserves all fields', () {
      final anchor = TrustAnchor(
        networkUtcMs: 1718452800000,
        uptimeMs: 5000,
        wallMs: 1718452800100,
        uncertaintyMs: 15,
      );
      final json = anchor.toJson();
      final restored = TrustAnchor.fromJson(json);
      expect(restored, equals(anchor));
    });

    test('equality and hashCode', () {
      final a = TrustAnchor(
        networkUtcMs: 100, uptimeMs: 200, wallMs: 300, uncertaintyMs: 10,
      );
      final b = TrustAnchor(
        networkUtcMs: 100, uptimeMs: 200, wallMs: 300, uncertaintyMs: 10,
      );
      final c = TrustAnchor(
        networkUtcMs: 999, uptimeMs: 200, wallMs: 300, uncertaintyMs: 10,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });
}
