// This is a basic Flutter integration test.
//
// Since integration tests run in a full Flutter application, they can interact
// with the host side of a plugin implementation, unlike Dart unit tests.
//
// For more information about Flutter integration tests, please see
// https://flutter.dev/to/integration-testing

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:trusted_time/trusted_time.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TrustedTime initialization test', (WidgetTester tester) async {
    // Initialize is now non-blocking (void return)
    TrustedTime.initialize();

    // Verify that TrustedTime can provide time
    final now = TrustedTime.now();
    expect(now, isNotNull);

    // Verify Unix timestamp methods work
    final unixMs = TrustedTime.nowUnixMs();
    expect(unixMs, greaterThan(0));
  });
}
