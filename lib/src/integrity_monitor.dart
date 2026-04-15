import 'dart:async';
import 'package:flutter/services.dart';
import 'integrity_event.dart';
import 'models.dart';
import 'monotonic_clock.dart';

/// Monitors platform-level temporal signals and detects integrity violations.
///
/// The [IntegrityMonitor] listens for native OS events (clock jumps, timezone
/// changes, reboots) via an [EventChannel] and emits [IntegrityEvent]s
/// through its [events] stream. It also provides [checkRebootOnWarmStart]
/// to detect cold-boot resets by comparing current uptime against a
/// persisted anchor.
final class IntegrityMonitor {
  /// Creates a monitor using the given [clock] for uptime comparisons.
  IntegrityMonitor({required MonotonicClock clock}) : _clock = clock;

  final MonotonicClock _clock;
  final _controller = StreamController<IntegrityEvent>.broadcast();
  static const _channel = EventChannel('trusted_time/integrity');

  StreamSubscription<dynamic>? _nativeSub;
  TrustAnchor? _anchor;
  Duration? _lastTimezoneOffset;

  /// Stream of validated integrity violation events.
  ///
  /// Listeners receive events whenever the engine detects a clock jump,
  /// timezone change, device reboot, or other temporal manipulation.
  Stream<IntegrityEvent> get events => _controller.stream;

  /// Attaches a fresh trust anchor and begins monitoring for violations.
  ///
  /// Cancels any previous native subscription before establishing the new
  /// one. Records the current timezone offset for drift detection.
  void attach(TrustAnchor anchor) {
    _anchor = anchor;
    _lastTimezoneOffset = DateTime.now().timeZoneOffset;
    _nativeSub?.cancel();
    _nativeSub = _channel.receiveBroadcastStream().listen(_onNativeEvent);
  }

  /// Handles incoming signals from native platform receivers.
  ///
  /// Expected event map format: `{ 'type': String, 'driftMs': int? }`.
  void _onNativeEvent(dynamic raw) {
    if (_anchor == null) return;
    if (raw is! Map) return;
    final map = raw;
    final type = map['type'] as String? ?? 'unknown';
    final driftMs = map['driftMs'] as int?;

    switch (type) {
      case 'clockJumped':
        _emit(
          IntegrityEvent(
            reason: TamperReason.systemClockJumped,
            detectedAt: DateTime.now().toUtc(),
            drift: driftMs != null ? Duration(milliseconds: driftMs) : null,
          ),
        );
      case 'reboot':
        _emit(
          IntegrityEvent(
            reason: TamperReason.deviceRebooted,
            detectedAt: DateTime.now().toUtc(),
          ),
        );
      case 'timezoneChanged':
        final now = DateTime.now();
        final prev = _lastTimezoneOffset;
        _lastTimezoneOffset = now.timeZoneOffset;
        _emit(
          IntegrityEvent(
            reason: TamperReason.timezoneChanged,
            detectedAt: now.toUtc(),
            drift: prev != null
                ? Duration(
                    milliseconds: (now.timeZoneOffset - prev).inMilliseconds
                        .abs(),
                  )
                : null,
          ),
        );
      default:
        _emit(
          IntegrityEvent(
            reason: TamperReason.unknown,
            detectedAt: DateTime.now().toUtc(),
          ),
        );
    }
  }

  /// Detects a device reboot by comparing current uptime against the
  /// persisted anchor.
  ///
  /// Returns `true` if the current monotonic uptime is less than the
  /// anchor's recorded uptime, indicating the clock was reset (i.e.,
  /// the device rebooted).
  Future<bool> checkRebootOnWarmStart(TrustAnchor previousAnchor) async {
    final currentUptime = await _clock.uptimeMs();
    return currentUptime < previousAnchor.uptimeMs;
  }

  /// Broadcasts an event into the reactive stream, if still open.
  void _emit(IntegrityEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  /// Shuts down all platform listeners and closes the event stream.
  void dispose() {
    _nativeSub?.cancel();
    _controller.close();
  }
}
