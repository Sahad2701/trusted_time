import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:web/web.dart' as web;

/// Web implementation of the TrustedTime plugin.
///
/// Registers [MethodChannel] handlers for the channels the Dart engine
/// expects. Uses `performance.now()` as the monotonic clock source.
///
/// **Important**: `performance.now()` is session-relative — it resets to
/// zero on every page load. This means trust anchors cannot survive page
/// refreshes; the engine will perform a fresh network sync on each load.
class TrustedTimeWebPlugin {
  static void registerWith(Registrar registrar) {
    const MethodChannel('trusted_time/monotonic')
        .setMethodCallHandler(_handleMonotonic);

    const MethodChannel('trusted_time/background')
        .setMethodCallHandler(_handleBackground);
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
}
