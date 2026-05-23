import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/source_quality_tracker.dart';

void main() {
  group('SourceQualityTracker', () {
    late SourceQualityTracker tracker;

    setUp(() => tracker = SourceQualityTracker());

    test('ranked returns all provided source IDs', () {
      final ids = ['a', 'b', 'c'];
      final result = tracker.ranked(ids);
      expect(result, unorderedEquals(ids));
    });

    test('higher consensus participation ranks higher', () {
      // 'good' participates in consensus every cycle; 'bad' never does.
      for (var i = 0; i < 8; i++) {
        tracker.record(
          sourceId: 'good',
          uncertaintyMs: 100,
          participatedInConsensus: true,
        );
        tracker.record(
          sourceId: 'bad',
          uncertaintyMs: 100,
          participatedInConsensus: false,
        );
        tracker.advanceCycle();
      }

      final ranked = tracker.ranked(['good', 'bad']);
      expect(ranked.first, equals('good'));
    });

    test('lower uncertainty ranks higher when participation is equal', () {
      for (var i = 0; i < 8; i++) {
        tracker.record(
          sourceId: 'fast',
          uncertaintyMs: 20,
          participatedInConsensus: true,
        );
        tracker.record(
          sourceId: 'slow',
          uncertaintyMs: 500,
          participatedInConsensus: true,
        );
        tracker.advanceCycle();
      }

      final ranked = tracker.ranked(['fast', 'slow']);
      expect(ranked.first, equals('fast'));
    });

    test('lower NTP stratum ranks higher', () {
      for (var i = 0; i < 8; i++) {
        tracker.record(
          sourceId: 'tier1',
          uncertaintyMs: 100,
          participatedInConsensus: true,
        );
        tracker.record(
          sourceId: 'tier3',
          uncertaintyMs: 100,
          participatedInConsensus: true,
        );
        tracker.advanceCycle();
      }
      tracker.setStratum('tier1', 1);
      tracker.setStratum('tier3', 3);

      final ranked = tracker.ranked(['tier1', 'tier3']);
      expect(ranked.first, equals('tier1'));
    });

    group('Starvation guard', () {
      test('newly seen source is considered starved', () {
        expect(tracker.isStarved('never_queried'), isTrue);
      });

      test('recently queried source is not starved', () {
        tracker.record(
          sourceId: 'fresh',
          uncertaintyMs: 50,
          participatedInConsensus: true,
        );
        expect(tracker.isStarved('fresh'), isFalse);
      });

      test(
        'source becomes starved after _kStarvationCycles without a query',
        () {
          tracker.record(
            sourceId: 'stale',
            uncertaintyMs: 50,
            participatedInConsensus: true,
          );
          // Advance 5 cycles without recording the source again.
          for (var i = 0; i < 5; i++) {
            tracker.advanceCycle();
          }
          expect(tracker.isStarved('stale'), isTrue);
        },
      );

      test('failure resets starvation clock', () {
        tracker.record(
          sourceId: 'src',
          uncertaintyMs: 50,
          participatedInConsensus: false,
        );
        for (var i = 0; i < 3; i++) {
          tracker.advanceCycle();
        }
        tracker.recordFailure('src');
        expect(tracker.isStarved('src'), isFalse);
      });
    });

    test('ranked does not duplicate starvation-forced sources', () {
      // All sources are known (not starved). ranked() should return each
      // source exactly once.
      const ids = ['a', 'b', 'c'];
      for (final id in ids) {
        tracker.record(
          sourceId: id,
          uncertaintyMs: 50,
          participatedInConsensus: true,
        );
      }
      tracker.advanceCycle();

      final ranked = tracker.ranked(ids);
      expect(ranked.length, equals(ids.length));
      expect(ranked.toSet().length, equals(ids.length));
    });

    test('invalid stratum values are ignored', () {
      tracker.setStratum('a', 0); // Too low
      tracker.setStratum('b', 16); // Too high
      // Should not throw and should score neutrally.
      expect(() => tracker.ranked(['a', 'b']), returnsNormally);
    });
  });
}
