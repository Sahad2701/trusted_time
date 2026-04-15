import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/monotonic_clock.dart';

void main() {
  group('SyncClock', () {
    test('elapsedSinceAnchorMs uses monotonic stopwatch, not wall clock', () {
      SyncClock.update(1000, DateTime.now().millisecondsSinceEpoch);

      final elapsed1 = SyncClock.elapsedSinceAnchorMs();
      expect(elapsed1, greaterThanOrEqualTo(0));
      expect(elapsed1, lessThan(100));
    });

    test('update resets the stopwatch', () async {
      SyncClock.update(1000, DateTime.now().millisecondsSinceEpoch);
      await Future.delayed(const Duration(milliseconds: 50));
      final beforeReset = SyncClock.elapsedSinceAnchorMs();
      expect(beforeReset, greaterThanOrEqualTo(40));

      SyncClock.update(2000, DateTime.now().millisecondsSinceEpoch);
      final afterReset = SyncClock.elapsedSinceAnchorMs();
      expect(afterReset, lessThan(beforeReset));
      expect(afterReset, lessThan(10));
    });

    test('elapsed increases monotonically over time', () async {
      SyncClock.update(500, DateTime.now().millisecondsSinceEpoch);

      final t1 = SyncClock.elapsedSinceAnchorMs();
      await Future.delayed(const Duration(milliseconds: 30));
      final t2 = SyncClock.elapsedSinceAnchorMs();
      await Future.delayed(const Duration(milliseconds: 30));
      final t3 = SyncClock.elapsedSinceAnchorMs();

      expect(t2, greaterThan(t1));
      expect(t3, greaterThan(t2));
    });

    test('lastUptimeMs and lastWallMs reflect last update', () {
      final wallMs = DateTime.now().millisecondsSinceEpoch;
      SyncClock.update(42000, wallMs);

      expect(SyncClock.lastUptimeMs, 42000);
      expect(SyncClock.lastWallMs, wallMs);
    });
  });
}
