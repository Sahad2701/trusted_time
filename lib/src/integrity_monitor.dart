import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'integrity_event.dart';
import 'models.dart';
import 'monotonic_clock.dart';

/// A high-integrity monitoring agent that detects temporal tampering and 
/// OS-level clock jumps.
///
/// The [IntegrityMonitor] implements a dual-layer defense strategy:
/// 1. **Native Signals**: Listens for platform-native events (e.g., 
///    `ACTION_TIME_CHANGED` on Android, `WM_TIMECHANGE` on Windows).
/// 2. **Monotonic Drift Detection**: A Dart-side secondary check that compares 
///    the delta of the hardware monotonic clock vs. the system wall clock.
///
/// This dual-layer approach ensures that even if native OS hooks are 
/// bypassed or suppressed, manual wall-clock manipulation is eventually 
/// detected via monotonic divergence.
final class IntegrityMonitor {
  IntegrityMonitor({required MonotonicClock clock}) : _clock = clock;

  final MonotonicClock _clock;
  final _controller = StreamController<IntegrityEvent>.broadcast();
  
  /// The underlying platform channel for native clock-change notifications.
  static const _channel = EventChannel('trusted_time/integrity');

  StreamSubscription<dynamic>? _nativeSub;
  TrustAnchor? _anchor;
  Duration? _lastTimezoneOffset;
  Timer? _driftCheckTimer;

  /// Reactive stream of detected integrity violations and timezone changes.
  Stream<IntegrityEvent> get events => _controller.stream;

  /// Attaches the monitor to an active trust anchor and begins surveillance.
  void attach(TrustAnchor anchor) {
    _anchor = anchor;
    _lastTimezoneOffset = DateTime.now().timeZoneOffset;
    _nativeSub?.cancel();
    _nativeSub = _channel.receiveBroadcastStream().listen(_onNativeEvent);
    
    _startDriftCheck();
  }

  /// The dynamic interval for Monotonic-to-Wall drift checks.
  Duration _driftCheckInterval = const Duration(minutes: 5);

  /// Initializes or restarts the adaptive drift check loop.
  void _startDriftCheck() {
    _driftCheckTimer?.cancel();
    _driftCheckTimer = Timer(_driftCheckInterval, _runAdaptiveDriftCheck);
  }

  /// Executes an adaptive drift check and recalculates the next check interval.
  ///
  /// To optimize for both battery and integrity:
  /// * Upon anomaly detection, the check frequency accelerates to **30 seconds**.
  /// * As stability is maintained, the interval gradually relaxes back to 
  ///   the **5-minute** baseline.
  Future<void> _runAdaptiveDriftCheck() async {
    final hasAnomaly = await _checkDrift();
    
    if (hasAnomaly) {
      _driftCheckInterval = const Duration(seconds: 30);
    } else {
      _driftCheckInterval = Duration(
        seconds: min(_driftCheckInterval.inSeconds + 30, 300),
      );
    }
    
    _startDriftCheck();
  }

  /// Compares local monotonic uptime delta against wall-clock delta to 
  /// detect tampering.
  ///
  /// In a healthy system, `ΔUptime` and `ΔWall` should be nearly identical. 
  /// A divergence of >5 seconds is considered a high-integrity violation.
  Future<bool> _checkDrift() async {
    final anchor = _anchor;
    if (anchor == null) return false;

    final uptimeMs = await _clock.uptimeMs();
    final wallMs = DateTime.now().millisecondsSinceEpoch;
    
    final elapsedUptime = uptimeMs - anchor.uptimeMs;
    final elapsedWall = wallMs - anchor.wallMs;
    
    final divergence = (elapsedUptime - elapsedWall).abs();
    if (divergence > 5000) { 
      _emit(IntegrityEvent(
        reason: TamperReason.systemClockJumped,
        detectedAt: DateTime.now().toUtc(),
        drift: Duration(milliseconds: divergence),
      ));
      return true;
    }
    return false;
  }

  /// Internal handler for raw platform events.
  void _onNativeEvent(dynamic raw) {
    try {
      if (_anchor == null) return;
      if (raw is! Map) return;
      final map = raw;
      final type = map['type'] as String? ?? 'unknown';
      final driftMs = map['driftMs'] as int?;

      switch (type) {
        case 'clockJumped':
          _emit(IntegrityEvent(
            reason: TamperReason.systemClockJumped,
            detectedAt: DateTime.now().toUtc(),
            drift: driftMs != null ? Duration(milliseconds: driftMs) : null,
          ));
        case 'reboot':
          _emit(IntegrityEvent(
            reason: TamperReason.deviceRebooted,
            detectedAt: DateTime.now().toUtc(),
          ));
        case 'timezoneChanged':
          final now = DateTime.now();
          final prev = _lastTimezoneOffset;
          _lastTimezoneOffset = now.timeZoneOffset;
          _emit(IntegrityEvent(
            reason: TamperReason.timezoneChanged,
            detectedAt: now.toUtc(),
            drift: prev != null
                ? Duration(
                    milliseconds:
                        (now.timeZoneOffset - prev).inMilliseconds.abs(),
                  )
                : null,
          ));
        default:
          _emit(IntegrityEvent(
            reason: TamperReason.unknown,
            detectedAt: DateTime.now().toUtc(),
          ));
      }
    } catch (e, st) {
      debugPrint('[TrustedTime] Critical failure in native event dispatcher: $e\n$st');
    }
  }

  /// Verification check for reboots during warm-start (cache restoration).
  ///
  /// A reboot is confirmed if the current hardware uptime is less than the 
  /// uptime recorded when the cached anchor was established.
  Future<bool> checkRebootOnWarmStart(TrustAnchor previousAnchor) async {
    final currentUptime = await _clock.uptimeMs();
    return currentUptime < previousAnchor.uptimeMs;
  }

  void _emit(IntegrityEvent event) {
    try {
      if (!_controller.isClosed) _controller.add(event);
    } catch (_) {
      // Stream may have closed between check and add in rare race conditions.
    }
  }

  /// Releases platform channel listeners and stops surveillance.
  void dispose() {
    _driftCheckTimer?.cancel();
    _nativeSub?.cancel();
    _controller.close();
  }
}
