import 'package:flutter/services.dart';

/// Contract for providing a hardware-pinned monotonic ticker.
///
/// Monotonic clocks only move forward and are immune to system clock
/// manipulation. They reset to zero on device reboot.
abstract interface class MonotonicClock {
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
///
/// **Design note**: [SyncClock] uses Dart's [Stopwatch] for elapsed-time
/// tracking, while [PlatformMonotonicClock] uses native kernel timers
/// (`SystemClock.elapsedRealtime`, `ProcessInfo.systemUptime`, etc.).
/// Both are monotonic clocks but from different sources. The [Stopwatch]
/// does not count time spent in deep sleep on some platforms, but this
/// is acceptable because the anchor is refreshed periodically and after
/// reboots. The key guarantee is that [Stopwatch] cannot be manipulated
/// by changing the system clock.
final class SyncClock {
  SyncClock._();

  static int _cachedUptimeMs = 0;
  static int _cachedWallMs = 0;
  static final Stopwatch _stopwatch = Stopwatch();

  static void update(int uptimeMs, int wallMs) {
    _cachedUptimeMs = uptimeMs;
    _cachedWallMs = wallMs;
    _stopwatch.reset();
    _stopwatch.start();
  }

  static int elapsedSinceAnchorMs() => _stopwatch.elapsedMilliseconds;

  static int get lastUptimeMs => _cachedUptimeMs;
  static int get lastWallMs => _cachedWallMs;

  /// #14: Clears all static state and stops the stopwatch.
  /// Called from [TrustedTimeImpl.dispose] to prevent stale state
  /// leaking across test cases or re-initialization cycles.
  static void reset() {
    _cachedUptimeMs = 0;
    _cachedWallMs = 0;
    _stopwatch.stop();
    _stopwatch.reset();
  }
}
