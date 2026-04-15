import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/marzullo.dart';

void main() {
  group('MarzulloEngine', () {
    const engine = MarzulloEngine(minimumQuorum: 2);
    final baseTime = DateTime.utc(2024, 6, 15, 12, 0, 0);
    final baseMs = baseTime.millisecondsSinceEpoch;

    test('returns null when fewer samples than quorum', () {
      final result = engine.resolve([
        SourceSample(sourceId: 'a', utc: baseTime, roundTripMs: 20),
      ]);
      expect(result, isNull);
    });

    test('returns null for empty sample list', () {
      expect(engine.resolve([]), isNull);
    });

    test('resolves consensus from two agreeing sources', () {
      final result = engine.resolve([
        SourceSample(sourceId: 'a', utc: baseTime, roundTripMs: 20),
        SourceSample(
          sourceId: 'b',
          utc: baseTime.add(const Duration(milliseconds: 5)),
          roundTripMs: 30,
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
        SourceSample(sourceId: 'a', utc: baseTime, roundTripMs: 20),
        SourceSample(
          sourceId: 'b',
          utc: baseTime.add(const Duration(milliseconds: 3)),
          roundTripMs: 20,
        ),
        SourceSample(
          sourceId: 'outlier',
          utc: baseTime.add(const Duration(seconds: 60)),
          roundTripMs: 20,
        ),
      ]);

      expect(result, isNotNull);
      final diffFromBase =
          (result!.utc.millisecondsSinceEpoch - baseMs).abs();
      expect(diffFromBase, lessThan(100));
    });

    test('uncertainty reflects intersection width', () {
      final result = engine.resolve([
        SourceSample(sourceId: 'a', utc: baseTime, roundTripMs: 100),
        SourceSample(sourceId: 'b', utc: baseTime, roundTripMs: 100),
      ]);

      expect(result, isNotNull);
      expect(result!.uncertaintyMs, greaterThanOrEqualTo(0));
      expect(result.uncertaintyMs, lessThanOrEqualTo(100));
    });

    test('returns null when sources are too far apart for quorum', () {
      final result = engine.resolve([
        SourceSample(sourceId: 'a', utc: baseTime, roundTripMs: 10),
        SourceSample(
          sourceId: 'b',
          utc: baseTime.add(const Duration(seconds: 120)),
          roundTripMs: 10,
        ),
      ]);

      expect(result, isNull);
    });
  });
}
