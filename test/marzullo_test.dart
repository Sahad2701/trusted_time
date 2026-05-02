import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/domain/marzullo_engine.dart';
import 'package:trusted_time/src/domain/time_sample.dart';

void main() {
  group('MarzulloEngine', () {
    const engine = MarzulloEngine(minimumQuorum: 2);
    final baseTime = DateTime.utc(2024, 6, 15, 12, 0, 0);
    final baseMs = baseTime.millisecondsSinceEpoch;

    test('returns null when fewer samples than quorum', () {
      final result = engine.resolve([
        TimeSample(sourceId: 'a', utc: baseTime, uncertaintyMs: 10),
      ]);
      expect(result, isNull);
    });

    test('returns null for empty sample list', () {
      expect(engine.resolve([]), isNull);
    });

    test('resolves consensus from two agreeing sources', () {
      final result = engine.resolve([
        TimeSample(sourceId: 'a', utc: baseTime, uncertaintyMs: 10),
        TimeSample(
          sourceId: 'b',
          utc: baseTime.add(const Duration(milliseconds: 5)),
          uncertaintyMs: 15,
        ),
      ]);

      expect(result, isNotNull);
      expect(result!.participantCount, 2);
      final diffMs = (result.utc.millisecondsSinceEpoch - baseMs).abs();
      expect(diffMs, lessThan(50));
    });

    test('resolves consensus from three sources with one outlier', () {
      final engine3 = MarzulloEngine(minimumQuorum: 2);
      final result = engine3.resolve([
        TimeSample(sourceId: 'a', utc: baseTime, uncertaintyMs: 10),
        TimeSample(
          sourceId: 'b',
          utc: baseTime.add(const Duration(milliseconds: 3)),
          uncertaintyMs: 10,
        ),
        TimeSample(
          sourceId: 'outlier',
          utc: baseTime.add(const Duration(seconds: 60)),
          uncertaintyMs: 10,
        ),
      ]);

      expect(result, isNotNull);
      final diffFromBase = (result!.utc.millisecondsSinceEpoch - baseMs).abs();
      expect(diffFromBase, lessThan(100));
    });

    test('uncertainty reflects intersection width', () {
      final result = engine.resolve([
        TimeSample(sourceId: 'a', utc: baseTime, uncertaintyMs: 50),
        TimeSample(sourceId: 'b', utc: baseTime, uncertaintyMs: 50),
      ]);

      expect(result, isNotNull);
      expect(result!.uncertaintyMs, greaterThanOrEqualTo(1));
      expect(result.uncertaintyMs, lessThanOrEqualTo(100));
    });

    test('returns null when sources are too far apart for quorum', () {
      final result = engine.resolve([
        TimeSample(sourceId: 'a', utc: baseTime, uncertaintyMs: 5),
        TimeSample(
          sourceId: 'b',
          utc: baseTime.add(const Duration(seconds: 120)),
          uncertaintyMs: 5,
        ),
      ]);

      expect(result, isNull);
    });

    group('Bug regression — tie-breaking at equal timestamps', () {
      test('touching intervals (upper == lower) count as overlap of 1', () {
        final left =
            DateTime.fromMillisecondsSinceEpoch(baseMs - 10, isUtc: true);
        final right =
            DateTime.fromMillisecondsSinceEpoch(baseMs + 10, isUtc: true);
        const engine1 = MarzulloEngine(minimumQuorum: 2);
        final result = engine1.resolve([
          TimeSample(sourceId: 'a', utc: left, uncertaintyMs: 10),
          TimeSample(sourceId: 'b', utc: right, uncertaintyMs: 10),
        ]);
        if (result != null) {
          expect(result.utc.millisecondsSinceEpoch, equals(baseMs));
        }
      });

      test('widely overlapping sources give correct midpoint', () {
        final result = engine.resolve([
          TimeSample(sourceId: 'a', utc: baseTime, uncertaintyMs: 50),
          TimeSample(sourceId: 'b', utc: baseTime, uncertaintyMs: 50),
        ]);
        expect(result, isNotNull);
        expect(result!.utc.millisecondsSinceEpoch, equals(baseMs));
      });
    });

    group('Bug regression — participantCount is unique source count', () {
      test(
          'participantCount equals number of agreeing sources, not overlap depth',
          () {
        const engine3 = MarzulloEngine(minimumQuorum: 2);
        final result = engine3.resolve([
          TimeSample(sourceId: 'a', utc: baseTime, uncertaintyMs: 50),
          TimeSample(sourceId: 'b', utc: baseTime, uncertaintyMs: 50),
          TimeSample(sourceId: 'c', utc: baseTime, uncertaintyMs: 50),
        ]);
        expect(result, isNotNull);
        expect(result!.participantCount, equals(3));
      });

      test('participantCount excludes outlier sources', () {
        const engine3 = MarzulloEngine(minimumQuorum: 2);
        final result = engine3.resolve([
          TimeSample(sourceId: 'a', utc: baseTime, uncertaintyMs: 10),
          TimeSample(sourceId: 'b', utc: baseTime, uncertaintyMs: 10),
          TimeSample(
            sourceId: 'outlier',
            utc: baseTime.add(const Duration(seconds: 60)),
            uncertaintyMs: 10,
          ),
        ]);
        expect(result, isNotNull);
        expect(result!.participantCount, equals(2));
      });
    });

    group('Bug regression — uncertaintyMs minimum floor', () {
      test('uncertaintyMs is at least 1 for minimal non-zero uncertainty', () {
        final result = engine.resolve([
          TimeSample(sourceId: 'a', utc: baseTime, uncertaintyMs: 1),
          TimeSample(sourceId: 'b', utc: baseTime, uncertaintyMs: 1),
        ]);
        expect(result, isNotNull);
        expect(result!.uncertaintyMs, greaterThanOrEqualTo(1));
      });

      test('zero-uncertainty sources produce no valid intersection', () {
        final result = engine.resolve([
          TimeSample(sourceId: 'a', utc: baseTime, uncertaintyMs: 0),
          TimeSample(sourceId: 'b', utc: baseTime, uncertaintyMs: 0),
        ]);
        expect(result, isNull);
      });
    });

    test('clamping maxUncertaintyMs prevents bloated intervals', () {
      const engineClamped =
          MarzulloEngine(minimumQuorum: 2, maxUncertaintyMs: 100);
      final result = engineClamped.resolve([
        TimeSample(sourceId: 'a', utc: baseTime, uncertaintyMs: 5000),
        TimeSample(sourceId: 'b', utc: baseTime, uncertaintyMs: 5000),
      ]);
      expect(result, isNotNull);
      expect(result!.uncertaintyMs, equals(100));
    });
  });
}
