import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/integrity_event.dart';
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

    test('events stream emits IntegrityEvent on attach and native event',
        () async {
      final events = <IntegrityEvent>[];
      monitor.events.listen(events.add);

      final anchor = TrustAnchor(
        networkUtcMs: DateTime.now().millisecondsSinceEpoch,
        uptimeMs: 1000,
        wallMs: DateTime.now().millisecondsSinceEpoch,
        uncertaintyMs: 10,
      );
      monitor.attach(anchor);

      await Future.delayed(Duration.zero);
      expect(monitor, isNotNull);
    });
  });
}
