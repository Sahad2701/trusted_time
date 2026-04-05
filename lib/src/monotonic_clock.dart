import 'package:flutter/services.dart';

/// Contract for providing a hardware-pinned monotonic ticker.
///
/// Monotonic clocks only move forward and are immune to system clock
/// manipulation. They reset to zero on device reboot.
abstract interface class MonotonicClock {
  /// Returns milliseconds since boot (monotonic uptime).
  ///
  /// On mobile, this maps to native kernel timers:
  /// - Android: `SystemClock.elapsedRealtime()`
  /// - iOS: `ProcessInfo.systemUptime`
  ///
  /// On desktop, this falls back to Dart's high-precision [Stopwatch].
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

/// In-memory cache enabling sub-microsecond synchronous access to trusted
/// time.
///
/// [SyncClock] stores the wall-clock and uptime baselines from the most
/// recent synchronization. The [TrustedTimeImpl.now] method uses these
/// cached values to compute the current trusted time without any I/O:
///
/// ```
/// trustedNow = anchor.networkUtcMs + (DateTime.now() - cachedWallMs)
/// ```
///
/// This design ensures `TrustedTime.now()` completes in <1µs.
final class SyncClock {
  SyncClock._();

  static int _cachedUptimeMs = 0;
  static int _cachedWallMs = 0;

  /// Atomically updates the cache from a freshly established anchor.
  static void update(int uptimeMs, int wallMs) {
    _cachedUptimeMs = uptimeMs;
    _cachedWallMs = wallMs;
  }

  /// Returns the elapsed wall-clock milliseconds since the last sync.
  ///
  /// This is the delta added to the anchor's [networkUtcMs] to compute
  /// the current trusted time.
  static int elapsedSinceAnchorMs() =>
      DateTime.now().millisecondsSinceEpoch - _cachedWallMs;

  /// The uptime baseline recorded during the last successful sync.
  ///
  /// Used by [IntegrityMonitor] to detect device reboots.
  static int get lastUptimeMs => _cachedUptimeMs;
}
