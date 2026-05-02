import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/sync_engine.dart';
import 'package:trusted_time/src/models.dart';
import 'package:trusted_time/src/domain/time_source.dart';
import 'package:trusted_time/src/domain/time_sample.dart';
import 'package:trusted_time/src/domain/time_interval.dart';
import 'package:trusted_time/src/monotonic_clock.dart';

class MockMonotonicClock implements MonotonicClock {
  @override
  Future<int> uptimeMs() async => 100000;
}

class RaceConditionSource implements TimeSource {
  RaceConditionSource(this.id, this.delay, this.utcMs, [this.groupId = 'test-group']);
  @override
  final String id;
  final Duration delay;
  final int utcMs;

  @override
  final String groupId;

  @override
  Future<TimeSample> getTime() async {
    await Future.delayed(delay);
    return TimeSample(
      interval: TimeInterval(startMs: utcMs - 10, endMs: utcMs + 10),
      sourceId: id,
      groupId: groupId,
    );
  }
}

void main() {
  group('SyncEngine Concurrency & Race Conditions', () {
    late TrustedTimeConfig config;
    late MockMonotonicClock clock;

    setUp(() {
      clock = MockMonotonicClock();
      config = const TrustedTimeConfig(
        minimumQuorum: 2,
        minGroupCount: 1, // Relax for tests
        ntpServers: [],
        httpsSources: [],
      );
    });

    test('resolves correctly when multiple sources respond in the same microtask', () async {
      final source1 = RaceConditionSource('s1', const Duration(milliseconds: 50), 1000000, 'g1');
      final source2 = RaceConditionSource('s2', const Duration(milliseconds: 50), 1000000, 'g2');
      final source3 = RaceConditionSource('s3', const Duration(milliseconds: 50), 1000000, 'g3');

      final engine = SyncEngine(
        config: config.copyWith(additionalSources: [source1, source2, source3]),
        clock: clock,
      );

      final anchor = await engine.sync();
      expect(anchor.networkUtcMs, inInclusiveRange(999990, 1000020));
    });

    test('handles stream closure during late query completion without StateError', () async {
      final source1 = RaceConditionSource('s1', const Duration(milliseconds: 10), 1000000, 'g1');
      final source2 = RaceConditionSource('s2', const Duration(milliseconds: 20), 1000000, 'g2');
      final source3 = RaceConditionSource('s3', const Duration(milliseconds: 100), 1000000, 'g3');

      final engine = SyncEngine(
        config: config.copyWith(
          minimumQuorum: 2,
          earlyExit: true,
          additionalSources: [source1, source2, source3],
        ),
        clock: clock,
      );

      final anchor = await engine.sync();
      expect(anchor.networkUtcMs, 1000000);

      await Future.delayed(const Duration(milliseconds: 150));
    });

    test('outlier filtering is deterministic across simultaneous arrivals', () async {
      // 4 sources to ensure stableCount >= 2 after filtering 1 outlier
      final s1 = RaceConditionSource('s1', const Duration(milliseconds: 50), 1000000, 'g1');
      final s2 = RaceConditionSource('s2', const Duration(milliseconds: 50), 1000002, 'g2');
      final s3 = RaceConditionSource('s3', const Duration(milliseconds: 50), 1000001, 'g3');
      final s4 = RaceConditionSource('s4', const Duration(milliseconds: 50), 2000000, 'g4');

      final engine = SyncEngine(
        config: config.copyWith(
          minimumQuorum: 2,
          additionalSources: [s1, s2, s3, s4],
        ),
        clock: clock,
      );

      final anchor = await engine.sync();
      expect(anchor.networkUtcMs, closeTo(1000000, 100));
    });
  });
}

extension on TrustedTimeConfig {
  TrustedTimeConfig copyWith({
    List<TimeSource>? additionalSources,
    int? minimumQuorum,
    bool? earlyExit,
    int? minGroupCount,
  }) {
    return TrustedTimeConfig(
      ntpServers: ntpServers,
      httpsSources: httpsSources,
      additionalSources: additionalSources ?? this.additionalSources,
      minimumQuorum: minimumQuorum ?? this.minimumQuorum,
      earlyExit: earlyExit ?? this.earlyExit,
      minGroupCount: minGroupCount ?? this.minGroupCount,
      persistState: persistState,
      refreshInterval: refreshInterval,
      maxLatency: maxLatency,
    );
  }
}
