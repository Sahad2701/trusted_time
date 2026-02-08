import 'package:flutter/foundation.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'dart:io' show Platform;
import 'trusted_time_method_channel.dart';
import 'trusted_time_web.dart';
import 'trusted_time_desktop.dart';

/// The common interface for all platform-specific implementations of TrustedTime.
///
/// This layer abstracts the native hardware-level calls (like monotonic uptime)
/// required to maintain a secure time anchor across different operating systems.
abstract class TrustedTimePlatform extends PlatformInterface {
  /// Constructs a [TrustedTimePlatform].
  TrustedTimePlatform() : super(token: _token);

  static final Object _token = Object();

  static TrustedTimePlatform _instance = _getDefaultInstance();

  static TrustedTimePlatform _getDefaultInstance() {
    if (kIsWeb) {
      return TrustedTimeWeb();
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return MethodChannelTrustedTime();
    }
    // Fallback for Windows, Linux, and macOS
    return TrustedTimeDesktop();
  }

  /// The active platform-specific implementation instance.
  ///
  /// Defaults to [MethodChannelTrustedTime], which covers Android and iOS.
  static TrustedTimePlatform get instance => _instance;

  /// Sets the active platform implementation instance.
  ///
  /// This should be called by the platform-specific registration code
  /// (e.g., in a Windows or Web plugin implementation).
  static set instance(TrustedTimePlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  /// Returns the native platform's version string.
  Future<String?> getPlatformVersion() {
    throw UnimplementedError('getPlatformVersion() has not been implemented.');
  }

  /// Retrieves the monotonic system uptime in milliseconds.
  ///
  /// Unlike standard wall-clock time, monotonic uptime is guaranteed to only
  /// increase and is immune to manual user adjustments. The implementation
  /// must include time spent in deep sleep (e.g., `elapsedRealtime` on Android).
  Future<int?> getUptimeMs() {
    throw UnimplementedError('getUptimeMs() has not been implemented.');
  }

  /// Registers a native listener for system clock manipulation events.
  ///
  /// This callback should be triggered when the OS detects a manual change
  /// to the system time or timezone (e.g., `ACTION_TIME_CHANGED` on Android).
  void setClockTamperCallback(void Function() callback) {
    throw UnimplementedError(
      'setClockTamperCallback() has not been implemented.',
    );
  }
}
