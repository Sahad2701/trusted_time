import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/storage.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StoredState', () {
    test('correctly initializes', () {
      final state = StoredState(1000, 2000, 50);
      expect(state.serverEpochMs, 1000);
      expect(state.uptimeMs, 2000);
      expect(state.driftMs, 50);
    });
  });

  group('Parsing Logic', () {
    // We can't easily test static methods that use FlutterSecureStorage directly,
    // but we've verified the StoredState data container used by the engine.
  });
}
