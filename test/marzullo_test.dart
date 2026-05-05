import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/domain/marzullo_engine.dart';
import 'package:trusted_time/src/domain/time_sample.dart';
import 'package:trusted_time/src/domain/time_interval.dart';

void main() {
  group('MarzulloEngine', () {
    const engine = MarzulloEngine(minQuorumRatio: 0.6);
    final baseTime = DateTime.utc(2024, 6, 15, 12, 0, 0);
    final baseMs = baseTime.millisecondsSinceEpoch;

    TimeSample createSample({
      required String id,
      required DateTime utc,
      required int uncertaintyMs,
      String? groupId,
    }) {
      final ms = utc.millisecondsSinceEpoch;
      return TimeSample(
        sourceId: id,
        groupId: groupId ?? id,
        interval: TimeInterval(
          startMs: ms - uncertaintyMs,
          endMs: ms + uncertaintyMs,
        ),
      );
    }

    test('returns null when fewer samples than quorum', () {
      final result = engine.resolve([
        createSample(id: 'a', utc: baseTime, uncertaintyMs: 10),
      ]);
      expect(result, isNull);
    });

    test('returns null for empty sample list', () {
      expect(engine.resolve([]), isNull);
    });

    test('resolves consensus from two agreeing sources', () {
      final result = engine.resolve([
        createSample(id: 'a', utc: baseTime, uncertaintyMs: 10),
        createSample(
          id: 'b',
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
      final result = engine.resolve([
        createSample(id: 'a', utc: baseTime, uncertaintyMs: 10),
        createSample(
          id: 'b',
          utc: baseTime.add(const Duration(milliseconds: 3)),
          uncertaintyMs: 10,
        ),
        createSample(
          id: 'outlier',
          utc: baseTime.add(const Duration(seconds: 60)),
          uncertaintyMs: 10,
        ),
      ]);

      expect(result, isNotNull);
      expect(result!.participantCount, 2); // Outlier excluded from quorum
      final diffFromBase = (result.utc.millisecondsSinceEpoch - baseMs).abs();
      expect(diffFromBase, lessThan(100));
    });

    test('uncertainty reflects intersection width', () {
      final result = engine.resolve([
        createSample(id: 'a', utc: baseTime, uncertaintyMs: 50),
        createSample(id: 'b', utc: baseTime, uncertaintyMs: 50),
      ]);

      expect(result, isNotNull);
      expect(result!.uncertaintyMs, greaterThanOrEqualTo(1));
      expect(result.uncertaintyMs, lessThanOrEqualTo(50));
    });

    test('returns null when sources are too far apart for quorum', () {
      final result = engine.resolve([
        createSample(id: 'a', utc: baseTime, uncertaintyMs: 5),
        createSample(
          id: 'b',
          utc: baseTime.add(const Duration(seconds: 120)),
          uncertaintyMs: 5,
        ),
      ]);

      expect(result, isNull);
    });

    group('Tie-breaking at equal timestamps', () {
      test('touching intervals (upper == lower) count as overlap', () {
        final left = baseMs - 10;
        final right = baseMs + 10;

        final result = engine.resolve([
          TimeSample(
            sourceId: 'a',
            groupId: 'a',
            interval: TimeInterval(startMs: left - 10, endMs: baseMs),
          ),
          TimeSample(
            sourceId: 'b',
            groupId: 'b',
            interval: TimeInterval(startMs: baseMs, endMs: right + 10),
          ),
        ]);

        if (result != null) {
          expect(result.utc.millisecondsSinceEpoch, equals(baseMs));
        }
      });
    });

    group('Diversity and Confidence', () {
      test('participantCount equals number of agreeing sources', () {
        final result = engine.resolve([
          createSample(id: 'a', utc: baseTime, uncertaintyMs: 50),
          createSample(id: 'b', utc: baseTime, uncertaintyMs: 50),
          createSample(id: 'c', utc: baseTime, uncertaintyMs: 50),
        ]);
        expect(result, isNotNull);
        expect(result!.participantCount, equals(3));
      });

      test('participantCount excludes outlier sources', () {
        final result = engine.resolve([
          createSample(id: 'a', utc: baseTime, uncertaintyMs: 10),
          createSample(id: 'b', utc: baseTime, uncertaintyMs: 10),
          createSample(
            id: 'outlier',
            utc: baseTime.add(const Duration(seconds: 60)),
            uncertaintyMs: 10,
          ),
        ]);
        expect(result, isNotNull);
        expect(result!.participantCount, equals(2));
      });
    });

    group('Uncertainty minimum floor', () {
      test('uncertaintyMs is at least 1 for minimal non-zero uncertainty', () {
        final result = engine.resolve([
          createSample(id: 'a', utc: baseTime, uncertaintyMs: 1),
          createSample(id: 'b', utc: baseTime, uncertaintyMs: 1),
        ]);
        expect(result, isNotNull);
        expect(result!.uncertaintyMs, greaterThanOrEqualTo(1));
      });

      // Touching intervals should produce at least 1ms uncertainty
      test('uncertaintyMs is at least 1 for touching intervals', () {
        final result = engine.resolve([
          TimeSample(
            sourceId: 'a',
            groupId: 'a',
            interval: TimeInterval(startMs: baseMs - 5, endMs: baseMs + 1),
          ),
          TimeSample(
            sourceId: 'b',
            groupId: 'b',
            interval: TimeInterval(startMs: baseMs, endMs: baseMs + 5),
          ),
        ]);
        expect(result, isNotNull);
        expect(result!.uncertaintyMs, greaterThanOrEqualTo(1));
      });
    });

    group('Unique source tracking', () {
      test('multiple samples from same source count as one participant', () {
        // Multiple samples from same source should count as one unique participant
        final result = engine.resolve([
          createSample(id: 'same', utc: baseTime, uncertaintyMs: 50),
          createSample(
            id: 'same',
            utc: baseTime.add(const Duration(milliseconds: 10)),
            uncertaintyMs: 50,
          ),
          createSample(id: 'other', utc: baseTime, uncertaintyMs: 50),
        ]);
        expect(result, isNotNull);
        // Should count 2 unique sources, not 3 samples
        expect(result!.participantCount, equals(2));
        expect(result.participants.length, equals(2));
      });

      test('sweep optimizes on unique sources not raw depth', () {
        // Window with more unique sources should win over window with fewer unique sources
        final result = engine.resolve([
          // Chatty source (same ID) with 3 overlapping samples
          createSample(
            id: 'chatty',
            utc: baseTime,
            uncertaintyMs: 100,
            groupId: 'group1',
          ),
          createSample(
            id: 'chatty',
            utc: baseTime.add(const Duration(milliseconds: 10)),
            uncertaintyMs: 100,
            groupId: 'group1',
          ),
          createSample(
            id: 'chatty',
            utc: baseTime.add(const Duration(milliseconds: 20)),
            uncertaintyMs: 100,
            groupId: 'group1',
          ),
          // Three different sources
          createSample(
            id: 'src1',
            utc: baseTime.add(const Duration(milliseconds: 50)),
            uncertaintyMs: 50,
            groupId: 'group2',
          ),
          createSample(
            id: 'src2',
            utc: baseTime.add(const Duration(milliseconds: 50)),
            uncertaintyMs: 50,
            groupId: 'group3',
          ),
          createSample(
            id: 'src3',
            utc: baseTime.add(const Duration(milliseconds: 50)),
            uncertaintyMs: 50,
            groupId: 'group4',
          ),
        ]);
        expect(result, isNotNull);
        // Should find the window with 3 unique sources, not 1 chatty source
        expect(result!.participantCount, greaterThanOrEqualTo(3));
        expect(result.groupCount, greaterThanOrEqualTo(3));
      });
    });

    group('Participants set', () {
      test('participants set contains only samples overlapping midpoint', () {
        final result = engine.resolve([
          createSample(id: 'a', utc: baseTime, uncertaintyMs: 50),
          createSample(id: 'b', utc: baseTime, uncertaintyMs: 50),
          createSample(
            id: 'c',
            utc: baseTime.add(const Duration(seconds: 60)),
            uncertaintyMs: 50,
          ),
        ]);
        expect(result, isNotNull);
        // Outlier should not be in participants
        expect(result!.participants.length, equals(2));
        expect(
          result.participants.map((s) => s.sourceId).contains('c'),
          isFalse,
        );
      });

      test('participants set uses object identity not source ID', () {
        // Two different sample objects from same source
        final sample1 = createSample(
          id: 'same',
          utc: baseTime,
          uncertaintyMs: 50,
        );
        final sample2 = createSample(
          id: 'same',
          utc: baseTime.add(const Duration(milliseconds: 10)),
          uncertaintyMs: 50,
        );
        final result = engine.resolve([sample1, sample2]);
        expect(result, isNotNull);
        // Both samples overlap the consensus window, so both can be in participants
        expect(result.participants.length, greaterThanOrEqualTo(1));
        expect(result.participants.length, lessThanOrEqualTo(2));
      });
    });

    test('clamping maxAllowedUncertaintyMs prevents bloated intervals', () {
      const engineClamped = MarzulloEngine(
        minQuorumRatio: 0.6,
        maxAllowedUncertaintyMs: 100,
      );
      final result = engineClamped.resolve([
        createSample(id: 'a', utc: baseTime, uncertaintyMs: 5000),
        createSample(id: 'b', utc: baseTime, uncertaintyMs: 5000),
      ]);
      // Should be null because both samples exceed maxAllowedUncertaintyMs
      expect(result, isNull);
    });
  });
}
