import 'dart:async';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;
import '../../trusted_time_platform_interface.dart';

/// A web-specific implementation of the TrustedTime platform.
///
/// On the web, we leverage [web.window.performance.now] to provide a
/// high-resolution monotonic timer that is immune to system clock adjustments.
class TrustedTimeWeb extends TrustedTimePlatform {
  /// Registers this class as the default instance of [TrustedTimePlatform].
  static void registerWith(Registrar registrar) {
    TrustedTimePlatform.instance = TrustedTimeWeb();
  }

  @override
  Future<String?> getPlatformVersion() async => web.window.navigator.userAgent;

  @override
  Future<int?> getUptimeMs() async {
    // performance.now() returns milliseconds with sub-millisecond precision.
    // We floor it to return an integer for consistency with native platforms.
    return web.window.performance.now().floor();
  }

  @override
  void setClockTamperCallback(void Function() callback) {
    // The web browser does not provide a standard event for system clock
    // manipulation. We rely on the core engine's periodic resync to detect shifts.
  }
}
