import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/exceptions.dart';
import 'package:trusted_time/src/models.dart';
import 'package:trusted_time/src/domain/marzullo_engine.dart';
import 'package:trusted_time/src/domain/time_sample.dart';
import 'package:trusted_time/src/domain/time_source.dart';

void main() {
  group('TrustedTimeSyncException', () {
    test('toString includes message', () {
      const e = TrustedTimeSyncException('test message');
      expect(e.toString(), contains('test message'));
    });

    test('is catchable as Exception', () {
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
      const a = TrustedTimeConfig(refreshInterval: Duration(hours: 6));
      const b = TrustedTimeConfig(refreshInterval: Duration(hours: 12));
      expect(a, isNot(equals(b)));
    });

    test('configs with different additionalSources are NOT equal', () {
      final sourceA = _FakeSource('a');
      final sourceB = _FakeSource('b');
      final a = TrustedTimeConfig(additionalSources: [sourceA]);
      final b = TrustedTimeConfig(additionalSources: [sourceB]);
      expect(a, isNot(equals(b)));
    });

    test('configs with same additionalSources instance are equal', () {
      final source = _FakeSource('x');
      final a = TrustedTimeConfig(additionalSources: [source]);
      final b = TrustedTimeConfig(additionalSources: [source]);
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('MarzulloEngine tie-breaking', () {
    test('touching intervals at exact same point resolve correctly', () {
      const engine = MarzulloEngine(minimumQuorum: 2);
      final t = DateTime.utc(2024, 1, 1, 12);
      final tMs = t.millisecondsSinceEpoch;

      final result = engine.resolve([
        TimeSample(sourceId: 'a', utc: t, uncertaintyMs: 10),
        TimeSample(
          sourceId: 'b',
          utc: DateTime.fromMillisecondsSinceEpoch(tMs + 20, isUtc: true),
          uncertaintyMs: 10,
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
        TimeSample(sourceId: 'a', utc: t, uncertaintyMs: 5),
        TimeSample(
          sourceId: 'b',
          utc: DateTime.fromMillisecondsSinceEpoch(tMs + 1000, isUtc: true),
          uncertaintyMs: 5,
        ),
      ]);

      expect(result, isNull);
    });
  });

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
        networkUtcMs: 100,
        uptimeMs: 200,
        wallMs: 300,
        uncertaintyMs: 10,
      );
      final b = TrustAnchor(
        networkUtcMs: 100,
        uptimeMs: 200,
        wallMs: 300,
        uncertaintyMs: 10,
      );
      final c = TrustAnchor(
        networkUtcMs: 999,
        uptimeMs: 200,
        wallMs: 300,
        uncertaintyMs: 10,
      );
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });

    test('copyWith returns new instance with updated uncertainty', () {
      final anchor = TrustAnchor(
        networkUtcMs: 100,
        uptimeMs: 200,
        wallMs: 300,
        uncertaintyMs: 10,
      );
      final copy = anchor.copyWith(uncertaintyMs: 50);
      expect(copy.uncertaintyMs, 50);
      expect(copy.networkUtcMs, anchor.networkUtcMs);
    });
  });
}

class _FakeSource implements TimeSource {
  _FakeSource(this._id);
  final String _id;

  @override
  String get id => _id;

  @override
  Future<TimeSample> getTime() async => TimeSample(
        utc: DateTime.now().toUtc(),
        uncertaintyMs: 10,
        sourceId: _id,
      );
}
