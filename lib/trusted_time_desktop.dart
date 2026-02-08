import 'dart:async';
import 'trusted_time_platform_interface.dart';

/// A pure-Dart implementation of the TrustedTime platform for Desktop.
///
/// This serves as a high-fidelity fallback for Windows, Linux, and macOS.
/// It uses the system's high-precision [Stopwatch] to track monotonic time.
class TrustedTimeDesktop extends TrustedTimePlatform {
  final Stopwatch _stopwatch = Stopwatch()..start();

  @override
  Future<String?> getPlatformVersion() async =>
      'Desktop (Dart Full-Fidelity Fallback)';

  @override
  Future<int?> getUptimeMs() async {
    // Stopwatch is monotonic and high-precision across all desktop platforms.
    return _stopwatch.elapsedMilliseconds;
  }

  @override
  void setClockTamperCallback(void Function() callback) {
    // Desktop manual clock changes are best detected via the core engine's
    // periodic resync and network consensus checks.
  }
}
