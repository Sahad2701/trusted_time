import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/trusted_time.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const storageChannel = MethodChannel(
    'plugins.it_nomads.com/flutter_secure_storage',
  );
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(storageChannel, (call) async => null);

  const monotonicChannel = MethodChannel('trusted_time/monotonic');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(monotonicChannel, (call) async {
    if (call.method == 'getUptimeMs') return 1000;
    return null;
  });

  const backgroundChannel = MethodChannel('trusted_time/background');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(backgroundChannel, (call) async => null);

  const integrityChannel = MethodChannel('trusted_time/integrity');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(integrityChannel, (call) async => null);

  group('TrustedTimeImpl via mock', () {
    late TrustedTimeMock mock;

    setUp(() {
      mock = TrustedTimeMock(initial: DateTime.utc(2024, 6, 15, 12));
      TrustedTime.overrideForTesting(mock);
    });

    tearDown(() {
      TrustedTime.resetOverride();
      mock.dispose();
    });

    test('isTrusted becomes false after clock jump event', () async {
      expect(TrustedTime.isTrusted, isTrue);

      mock.simulateTampering(TamperReason.systemClockJumped);
      await Future.delayed(Duration.zero);

      expect(TrustedTime.isTrusted, isFalse);
    });

    test('isTrusted becomes false after reboot event', () async {
      expect(TrustedTime.isTrusted, isTrue);

      mock.simulateReboot();
      await Future.delayed(Duration.zero);

      expect(TrustedTime.isTrusted, isFalse);
    });

    test('onIntegrityLost stream emits events with correct reason', () async {
      final events = <IntegrityEvent>[];
      final sub = TrustedTime.onIntegrityLost.listen(events.add);

      mock.simulateTampering(
        TamperReason.systemClockJumped,
        drift: const Duration(minutes: 3),
      );
      await Future.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.first.reason, TamperReason.systemClockJumped);
      expect(events.first.drift, const Duration(minutes: 3));

      await sub.cancel();
    });

    test('restoreTrust re-enables isTrusted after reboot', () {
      mock.simulateReboot();
      expect(TrustedTime.isTrusted, isFalse);
      mock.restoreTrust();
      expect(TrustedTime.isTrusted, isTrue);
    });

    test('trustedLocalTimeIn throws TrustedTimeNotReadyException when not trusted',
        () async {
      await TrustedTime.initialize();
      mock = TrustedTimeMock(initial: DateTime.utc(2024, 6, 15, 12));
      TrustedTime.overrideForTesting(mock);
      mock.simulateReboot();
      expect(
        () => TrustedTime.trustedLocalTimeIn('America/New_York'),
        throwsA(isA<TrustedTimeNotReadyException>()),
      );
    });

    test('nowEstimated returns estimate with full confidence when trusted', () {
      final estimate = TrustedTime.nowEstimated();
      expect(estimate, isNotNull);
      expect(estimate!.confidence, 1.0);
      expect(estimate.estimatedError, Duration.zero);
    });

    test('nowEstimated returns decaying estimate after reboot', () {
      mock.simulateReboot();
      final estimate = TrustedTime.nowEstimated();
      expect(estimate, isNotNull);
      expect(estimate!.confidence, 1.0);
    });

    test('nowEstimated returns null when untrusted without reboot data', () {
      mock.simulateTampering(TamperReason.systemClockJumped);
      final estimate = TrustedTime.nowEstimated();
      expect(estimate, isNull);
    });
  });
}
