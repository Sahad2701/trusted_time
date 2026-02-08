import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'trusted_time_platform_interface.dart';

/// The default [MethodChannel]-based implementation for mobile platforms.
///
/// This class handles the standard asynchronous bridge between Dart and the
/// native Kotlin (Android) or Swift (iOS) implementations.
class MethodChannelTrustedTime extends TrustedTimePlatform {
  /// The underlying [MethodChannel] used for native communication.
  @visibleForTesting
  final methodChannel = const MethodChannel('trusted_time');

  VoidCallback? _clockTamperCallback;

  MethodChannelTrustedTime() {
    // Register the inbound call handler for platform broadcasts.
    methodChannel.setMethodCallHandler(_handleMethodCall);
  }

  /// Internal dispatcher for events coming from the native side.
  Future<void> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onClockTampered':
        _clockTamperCallback?.call();
        break;
      default:
        // Ignore unrecognized methods
        break;
    }
  }

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }

  @override
  Future<int?> getUptimeMs() async {
    final uptime = await methodChannel.invokeMethod<int>('getUptimeMs');
    return uptime;
  }

  @override
  void setClockTamperCallback(void Function() callback) {
    _clockTamperCallback = callback;
  }
}
