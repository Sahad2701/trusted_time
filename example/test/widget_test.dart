import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:trusted_time_example/main.dart';
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

  testWidgets('Example app renders TrustedTime V2 Features title',
      (WidgetTester tester) async {
    final mock = TrustedTimeMock(initial: DateTime.utc(2024, 1, 1, 12));
    TrustedTime.overrideForTesting(mock);

    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('TrustedTime V2 Features'), findsOneWidget);
    expect(find.text('Section 1 — Live Clock'), findsOneWidget);

    TrustedTime.resetOverride();
    mock.dispose();
  });
}
