import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/trusted_time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Mock secure storage MethodChannel.
  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(storageChannel, (call) async {
    if (call.method == 'read') return null;
    return null;
  });

  // Mock monotonic uptime channel.
  const monotonicChannel = MethodChannel('trusted_time/monotonic');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(monotonicChannel, (call) async {
    if (call.method == 'getUptimeMs') return 1000;
    return null;
  });

  // Mock background task channel.
  const backgroundChannel = MethodChannel('trusted_time/background');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(backgroundChannel, (call) async {
    return null;
  });

  // Mock integrity events channel.
  const integrityChannel = MethodChannel(
    'trusted_time/integrity',
  ); // Note: EventChannel uses same underlying messenger.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(integrityChannel, (call) async {
    return null;
  });

  group('TrustedTime V2 Senior Rewrite Test Suite', () {
    late DateTime baseTime;
    late TrustedTimeMock mock;

    setUp(() {
      baseTime = DateTime.utc(2024, 1, 1, 12, 0, 0);
      mock = TrustedTimeMock(initial: baseTime);
      TrustedTime.overrideForTesting(mock);
    });

    tearDown(() {
      TrustedTime.resetOverride();
      mock.dispose();
    });

    test('Synchronous now() returns exactly the mocked UTC time', () {
      expect(TrustedTime.now(), baseTime);
      expect(TrustedTime.nowUnixMs(), 1704110400000);
      expect(TrustedTime.isTrusted, isTrue);
    });

    test('advanceTime() shifts now() without changing hardware baseline', () {
      mock.advanceTime(const Duration(seconds: 45));
      expect(TrustedTime.now(), baseTime.add(const Duration(seconds: 45)));
    });

    test(
      'Tamper Forensics: onIntegrityLost captures reason and drift',
      () async {
        final drift = const Duration(minutes: 5);
        final events = <IntegrityEvent>[];
        final sub = TrustedTime.onIntegrityLost.listen(events.add);

        mock.simulateTampering(TamperReason.systemClockJumped, drift: drift);

        await Future.delayed(Duration.zero); // Flush stream microtasks.
        expect(events.length, 1);
        expect(events.first.reason, TamperReason.systemClockJumped);
        expect(events.first.drift, drift);
        expect(TrustedTime.isTrusted, isFalse);

        await sub.cancel();
      },
    );

    test('Offline Best-Effort: nowEstimated() decays confidence over 72h', () {
      mock.simulateReboot(); // Lose trust to enable estimation paths.

      final estimate = TrustedTime.nowEstimated();
      expect(estimate, isNotNull);
      expect(
        estimate!.confidence,
        1.0,
      ); // No time elapsed yet since "mocked" reboot.
      expect(estimate.isReasonable, isTrue);

      // Advance virtual clock by 36 hours (half of 72h).
      mock.advanceTime(const Duration(hours: 36));
      final estimate36h = TrustedTime.nowEstimated()!;
      expect(estimate36h.confidence, closeTo(0.5, 0.01));
      expect(estimate36h.isReasonable, isTrue);

      // Advance past 72h.
      mock.advanceTime(const Duration(hours: 40));
      final estimate76h = TrustedTime.nowEstimated()!;
      expect(estimate76h.confidence, 0.0);
      expect(estimate76h.isReasonable, isFalse);
    });

    test(
      'Timezone-Proof: trustedLocalTimeIn() returns correct offsets',
      () async {
        // Initialize timezone database must happen during TrustedTime.initialize()
        // or manually for hermetic tests.
        await TrustedTime.initialize();

        // "America/New_York" on Jan 1st is UTC-5.
        final nycTime = TrustedTime.trustedLocalTimeIn('America/New_York');
        expect(nycTime.hour, 7); // 12:00 UTC - 5h = 07:00.
        expect(nycTime.minute, 0);

        // "Asia/Tokyo" on Jan 1st is UTC+9.
        final tokyoTime = TrustedTime.trustedLocalTimeIn('Asia/Tokyo');
        expect(tokyoTime.hour, 21); // 12:00 UTC + 9h = 21:00.
      },
    );

    test('Exception: trustedLocalTimeIn() throws for unknown identifiers', () {
      expect(
        () => TrustedTime.trustedLocalTimeIn('Mars/Elon_City'),
        throwsA(isA<UnknownTimezoneException>()),
      );
    });

    test('Mock Restore: restoreTrust() resumes high-integrity baseline', () {
      mock.simulateReboot();
      expect(TrustedTime.isTrusted, isFalse);
      mock.restoreTrust();
      expect(TrustedTime.isTrusted, isTrue);
    });
  });
}
