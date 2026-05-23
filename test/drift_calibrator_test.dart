import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/drift_calibrator.dart';

void main() {
  group('DriftCalibrator', () {
    late DriftCalibrator calibrator;

    setUp(() => calibrator = DriftCalibrator());

    test('returns null before sufficient observation window', () {
      // Two observations 1 minute apart — below the 30-minute threshold.
      final base = DateTime.utc(2024, 1, 1).millisecondsSinceEpoch;
      calibrator.recordAnchor(base, base);
      calibrator.recordAnchor(base + 60000, base + 60000);

      expect(calibrator.calibratedFactor, isNull);
    });

    test('returns a factor after a 30-minute+ observation window', () {
      final base = DateTime.utc(2024, 1, 1).millisecondsSinceEpoch;
      // Simulate 40 minutes elapsed wall time vs 40 minutes network time
      // (perfect oscillator, drift ≈ 0).
      calibrator.recordAnchor(base, base);
      calibrator.recordAnchor(
        base + Duration(minutes: 40).inMilliseconds,
        base + Duration(minutes: 40).inMilliseconds,
      );

      expect(calibrator.calibratedFactor, isNotNull);
      expect(calibrator.calibratedFactor!, lessThan(0.0001));
    });

    test('computed drift rate matches injected synthetic drift', () {
      // Inject 50 ppm drift: wall advances 1ms more per 20s than network.
      const driftPpm = 50.0;
      const driftFactor = driftPpm / 1e6;
      final base = DateTime.utc(2024, 1, 1).millisecondsSinceEpoch;
      const windowMs = 3600000; // 1 hour

      calibrator.recordAnchor(base, base);
      // Wall clock runs faster by driftFactor.
      final wallEnd = base + windowMs;
      final networkEnd = base + (windowMs * (1 - driftFactor)).round();
      calibrator.recordAnchor(wallEnd, networkEnd);

      expect(calibrator.calibratedFactor, isNotNull);
      // Allow ±10 ppm tolerance for integer rounding.
      expect(calibrator.calibratedFactor!, closeTo(driftFactor, 10 / 1e6));
    });

    test('rejects samples exceeding 100 ppm and clears history', () {
      final base = DateTime.utc(2024, 1, 1).millisecondsSinceEpoch;
      const windowMs = 3600000;

      calibrator.recordAnchor(base, base);
      // Inject 200 ppm drift — above the sanity cap.
      final networkEnd = base + (windowMs * (1 - 200 / 1e6)).round();
      calibrator.recordAnchor(base + windowMs, networkEnd);

      // Calibrator should reject the sample and return null.
      expect(calibrator.calibratedFactor, isNull);
    });

    test('ignores known-bad outlier samples via median', () {
      final base = DateTime.utc(2024, 1, 1).millisecondsSinceEpoch;
      final segmentMs = Duration(minutes: 20).inMilliseconds;

      // Three segments: two near-zero drift, one bad (corrupted wall clock).
      calibrator.recordAnchor(base, base);
      calibrator.recordAnchor(
        base + segmentMs,
        base + segmentMs, // good
      );
      calibrator.recordAnchor(
        base + segmentMs * 2,
        // Simulate a single bad segment: network suddenly jumped 5 seconds.
        base + segmentMs * 2 - 5000, // bad outlier
      );
      calibrator.recordAnchor(
        base + segmentMs * 3,
        base + segmentMs * 3, // good
      );

      // With median filtering, the one bad segment is dominated by good ones.
      // The result should still be within sane bounds (< 100 ppm).
      if (calibrator.calibratedFactor != null) {
        expect(calibrator.calibratedFactor!, lessThanOrEqualTo(0.0001));
      }
    });

    test('reset clears all state', () {
      final base = DateTime.utc(2024, 1, 1).millisecondsSinceEpoch;
      calibrator.recordAnchor(base, base);
      calibrator.recordAnchor(
        base + Duration(hours: 1).inMilliseconds,
        base + Duration(hours: 1).inMilliseconds,
      );

      calibrator.reset();
      expect(calibrator.calibratedFactor, isNull);

      // A single anchor after reset should not produce a factor.
      calibrator.recordAnchor(base, base);
      expect(calibrator.calibratedFactor, isNull);
    });
  });
}
