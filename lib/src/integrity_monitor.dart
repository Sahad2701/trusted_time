import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'integrity_event.dart';
import 'models.dart';
import 'monotonic_clock.dart';

/// Monitors platform-level temporal signals and detects integrity violations.
final class IntegrityMonitor {
  IntegrityMonitor({required MonotonicClock clock}) : _clock = clock;

  final MonotonicClock _clock;
  final _controller = StreamController<IntegrityEvent>.broadcast();
  static const _channel = EventChannel('trusted_time/integrity');

  StreamSubscription<dynamic>? _nativeSub;
  TrustAnchor? _anchor;
  Duration? _lastTimezoneOffset;

  Stream<IntegrityEvent> get events => _controller.stream;

  void attach(TrustAnchor anchor) {
    _anchor = anchor;
    _lastTimezoneOffset = DateTime.now().timeZoneOffset;
    _nativeSub?.cancel();
    _nativeSub = _channel.receiveBroadcastStream().listen(_onNativeEvent);
  }

  /// #2: Full try/catch around the entire handler body so a malformed
  /// native payload never crashes the engine.
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
                    milliseconds: (now.timeZoneOffset - prev).inMilliseconds.abs(),
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
      debugPrint('[TrustedTime] Integrity event handling error: $e\n$st');
    }
  }

  Future<bool> checkRebootOnWarmStart(TrustAnchor previousAnchor) async {
    final currentUptime = await _clock.uptimeMs();
    return currentUptime < previousAnchor.uptimeMs;
  }

  void _emit(IntegrityEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  void dispose() {
    _nativeSub?.cancel();
    _controller.close();
  }
}
