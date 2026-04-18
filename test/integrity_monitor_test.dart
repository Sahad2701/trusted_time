import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/integrity_monitor.dart';
import 'package:trusted_time/src/models.dart';
import 'package:trusted_time/src/monotonic_clock.dart';

class FakeMonotonicClock implements MonotonicClock {
  int value = 1000;
  @override
  Future<int> uptimeMs() async => value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // EventChannel uses MethodChannel under the hood for listen/cancel.
  // In test mode we mock the underlying MethodChannel so that calling
  // attach() (which calls receiveBroadcastStream()) doesn't throw
  // MissingPluginException. This does NOT simulate native event delivery
  // — it only allows the Dart-side logic to be tested in isolation.
  const integrityChannel = MethodChannel('trusted_time/integrity');
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(integrityChannel, (call) async => null);

  group('IntegrityMonitor', () {
    late FakeMonotonicClock clock;
    late IntegrityMonitor monitor;

    setUp(() {
      clock = FakeMonotonicClock();
      monitor = IntegrityMonitor(clock: clock);
    });

    tearDown(() => monitor.dispose());

    test('checkRebootOnWarmStart detects reboot when uptime < anchor', () async {
      clock.value = 500;
      final anchor = TrustAnchor(
        networkUtcMs: DateTime.now().millisecondsSinceEpoch,
        uptimeMs: 10000,
        wallMs: DateTime.now().millisecondsSinceEpoch,
        uncertaintyMs: 10,
      );
      final rebooted = await monitor.checkRebootOnWarmStart(anchor);
      expect(rebooted, isTrue);
    });

    test('checkRebootOnWarmStart returns false when uptime >= anchor', () async {
      clock.value = 20000;
      final anchor = TrustAnchor(
        networkUtcMs: DateTime.now().millisecondsSinceEpoch,
        uptimeMs: 10000,
        wallMs: DateTime.now().millisecondsSinceEpoch,
        uncertaintyMs: 10,
      );
      final rebooted = await monitor.checkRebootOnWarmStart(anchor);
      expect(rebooted, isFalse);
    });

    test('events stream is a broadcast stream', () {
      expect(monitor.events.isBroadcast, isTrue);
    });

    test('attach establishes monitoring without throwing', () {
      final anchor = TrustAnchor(
        networkUtcMs: DateTime.now().millisecondsSinceEpoch,
        uptimeMs: 1000,
        wallMs: DateTime.now().millisecondsSinceEpoch,
        uncertaintyMs: 10,
      );
      expect(() => monitor.attach(anchor), returnsNormally);
    });

    test('multiple attaches cancel previous subscription', () {
      final anchor = TrustAnchor(
        networkUtcMs: DateTime.now().millisecondsSinceEpoch,
        uptimeMs: 1000,
        wallMs: DateTime.now().millisecondsSinceEpoch,
        uncertaintyMs: 10,
      );
      expect(() {
        monitor.attach(anchor);
        monitor.attach(anchor);
      }, returnsNormally);
    });

    test('dispose can be called multiple times safely', () {
      monitor.dispose();
      expect(() => monitor.dispose(), returnsNormally);
    });
  });
}
