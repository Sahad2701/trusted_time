import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'src/platform/platform_stub.dart'
    if (dart.library.io) 'src/platform/platform_io.dart'
    if (dart.library.html) 'src/platform/platform_web.dart'
    if (dart.library.js_interop) 'src/platform/platform_web.dart';

/// The common interface for all platform-specific implementations of TrustedTime.
///
/// This layer abstracts the native hardware-level calls (like monotonic uptime)
/// required to maintain a secure time anchor across different operating systems.
abstract class TrustedTimePlatform extends PlatformInterface {
  /// Constructs a [TrustedTimePlatform].
  TrustedTimePlatform() : super(token: _token);

  static final Object _token = Object();

  static TrustedTimePlatform _instance = getPlatformInstance();

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
