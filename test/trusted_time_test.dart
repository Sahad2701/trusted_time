import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/trusted_time_platform_interface.dart';
import 'package:trusted_time/src/platform/trusted_time_method_channel.dart';
import 'package:trusted_time/src/platform/trusted_time_desktop.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:io';

class MockTrustedTimePlatform
    with MockPlatformInterfaceMixin
    implements TrustedTimePlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');

  @override
  Future<int?> getUptimeMs() => Future.value(1000);

  @override
  void setClockTamperCallback(void Function() callback) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final initialPlatform = TrustedTimePlatform.instance;

  test('Default instance is appropriate for platform', () {
    if (Platform.isAndroid || Platform.isIOS) {
      expect(initialPlatform, isInstanceOf<MethodChannelTrustedTime>());
    } else {
      expect(initialPlatform, isInstanceOf<TrustedTimeDesktop>());
    }
  });

  test('getPlatformVersion', () async {
    final fakePlatform = MockTrustedTimePlatform();
    TrustedTimePlatform.instance = fakePlatform;

    expect(await TrustedTimePlatform.instance.getPlatformVersion(), '42');
  });
}
