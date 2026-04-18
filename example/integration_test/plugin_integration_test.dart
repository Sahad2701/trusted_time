import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:trusted_time/trusted_time.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('TrustedTime initialization test', (WidgetTester tester) async {
    await TrustedTime.initialize();

    expect(TrustedTime.isTrusted, isTrue);

    final now = TrustedTime.now();
    expect(now, isNotNull);

    final unixMs = TrustedTime.nowUnixMs();
    expect(unixMs, greaterThan(0));

    final iso = TrustedTime.nowIso();
    expect(iso, contains('T'));
  });
}
