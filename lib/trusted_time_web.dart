import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

import 'trusted_time_platform_interface.dart';

/// Web implementation of the TrustedTime plugin.
///
/// Registers MethodChannel handlers for `trusted_time/monotonic` and
/// `trusted_time/background` so the Dart engine can function on web.
/// Uses `performance.now()` as the monotonic clock source.
class TrustedTimeWebPlugin extends TrustedTimePlatform {
  TrustedTimeWebPlugin();

  static void registerWith(Registrar registrar) {
    TrustedTimePlatform.instance = TrustedTimeWebPlugin();

    const MethodChannel('trusted_time/monotonic')
        .setMethodCallHandler(_handleMonotonic);

    const MethodChannel('trusted_time/background')
        .setMethodCallHandler(_handleBackground);

    const MethodChannel('trusted_time')
        .setMethodCallHandler(_handleLegacy);
  }

  static Future<dynamic> _handleMonotonic(MethodCall call) async {
    if (call.method == 'getUptimeMs') {
      return web.window.performance.now().floor();
    }
    throw PlatformException(
      code: 'UNIMPLEMENTED',
      message: '${call.method} not implemented on web',
    );
  }

  static Future<dynamic> _handleBackground(MethodCall call) async {
    return null;
  }

  static Future<dynamic> _handleLegacy(MethodCall call) async {
    if (call.method == 'getPlatformVersion') {
      return web.window.navigator.userAgent;
    }
    throw PlatformException(
      code: 'UNIMPLEMENTED',
      message: '${call.method} not implemented on web',
    );
  }

  @override
  Future<String?> getPlatformVersion() async =>
      web.window.navigator.userAgent;

  @override
  Future<int?> getUptimeMs() async =>
      web.window.performance.now().floor();

  @override
  void setClockTamperCallback(void Function() callback) {
    // Browsers don't expose system clock change events.
  }
}
