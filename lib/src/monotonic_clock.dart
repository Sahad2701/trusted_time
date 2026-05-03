import 'package:flutter/services.dart';

/// Contract for providing a hardware-pinned monotonic ticker.
///
/// Monotonic clocks only move forward and are immune to system clock
/// manipulation. They reset to zero on device reboot.
abstract interface class MonotonicClock {
  /// Documented.
  Future<int> uptimeMs();
}

/// Production implementation using native OS kernel timers via
/// platform channels.
final class PlatformMonotonicClock implements MonotonicClock {
  static const _channel = MethodChannel('trusted_time/monotonic');

  @override
  Future<int> uptimeMs() async {
    final result = await _channel.invokeMethod<int>('getUptimeMs');
    if (result == null) {
      throw StateError('OS kernel returned null uptime baseline.');
    }
    return result;
  }
}

/// In-memory cache enabling sub-microsecond synchronous access to trusted time.
///
/// Uses Dart's [Stopwatch] (backed by the OS monotonic clock) so that
/// elapsed-time measurement is immune to system clock manipulation.
final class SyncClock {
  /// Documented.
  SyncClock();

  int _cachedUptimeMs = 0;
  int _cachedWallMs = 0;
  final Stopwatch _stopwatch = Stopwatch();

  /// Updates the clock with a new trust anchor.
  void update(int uptimeMs, int wallMs) {
    _cachedUptimeMs = uptimeMs;
    _cachedWallMs = wallMs;
    _stopwatch.reset();
    _stopwatch.start();
  }

  /// Returns the elapsed time since the anchor was last updated.
  int elapsedSinceAnchorMs() => _stopwatch.elapsedMilliseconds;

  /// The hardware uptime recorded in the last anchor.
  int get lastUptimeMs => _cachedUptimeMs;

  /// The system wall-clock recorded in the last anchor.
  int get lastWallMs => _cachedWallMs;

  /// Stops the internal stopwatch and clears the cache.
  void dispose() {
    _cachedUptimeMs = 0;
    _cachedWallMs = 0;
    _stopwatch.stop();
    _stopwatch.reset();
  }
}
