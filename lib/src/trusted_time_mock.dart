import 'dart:async';
import 'integrity_event.dart';
import 'trusted_time_estimate.dart';

/// High-fidelity test double for deterministic temporal testing.
///
/// Provides a fully controllable virtual clock that simulates all aspects
/// of the TrustedTime API — including trust state, time advancement,
/// integrity events, and offline estimation.
///
/// Use with [TrustedTime.overrideForTesting] to inject into the global
/// API during widget or unit tests:
///
/// ```dart
/// final mock = TrustedTimeMock(initial: DateTime.utc(2024, 1, 1));
/// TrustedTime.overrideForTesting(mock);
///
/// expect(TrustedTime.now(), DateTime.utc(2024, 1, 1));
///
/// mock.advanceTime(const Duration(hours: 1));
/// expect(TrustedTime.now(), DateTime.utc(2024, 1, 1, 1));
///
/// TrustedTime.resetOverride();
/// mock.dispose();
/// ```
final class TrustedTimeMock {
  /// Creates a mock starting at the given [initial] UTC time.
  ///
  /// The mock begins in a trusted state.
  TrustedTimeMock({required DateTime initial})
    : _now = initial.toUtc(),
      _trusted = true;

  DateTime _now;
  bool _trusted;
  DateTime? _rebootTime;
  final _controller = StreamController<IntegrityEvent>.broadcast();

  /// The current simulated UTC time.
  DateTime get now => _now;

  /// Whether the mock is currently in a trusted state.
  bool get isTrusted => _trusted;

  /// The current simulated Unix timestamp in milliseconds.
  int get nowUnixMs => _now.millisecondsSinceEpoch;

  /// The current simulated time as an ISO-8601 string.
  String get nowIso => _now.toIso8601String();

  /// Stream of simulated integrity violation events.
  Stream<IntegrityEvent> get onIntegrityLost => _controller.stream;

  /// Advances the virtual clock by [delta].
  ///
  /// Does not affect the trust state — use [simulateReboot] or
  /// [simulateTampering] to trigger trust loss.
  void advanceTime(Duration delta) => _now = _now.add(delta);

  /// Sets the virtual clock to a specific [time] (converted to UTC).
  void setNow(DateTime time) => _now = time.toUtc();

  /// Restores the mock to a trusted state.
  ///
  /// Useful after calling [simulateReboot] or [simulateTampering] to
  /// test recovery paths.
  void restoreTrust() => _trusted = true;

  /// Simulates a device reboot: clears trust and emits a
  /// [TamperReason.deviceRebooted] event.
  void simulateReboot() {
    _trusted = false;
    _rebootTime = _now;
    _emit(
      IntegrityEvent(reason: TamperReason.deviceRebooted, detectedAt: _now),
    );
  }

  /// Simulates an arbitrary clock manipulation event.
  ///
  /// Sets the mock to untrusted and emits an [IntegrityEvent] with the
  /// given [reason] and optional [drift] magnitude.
  void simulateTampering(TamperReason reason, {Duration? drift}) {
    _trusted = false;
    _emit(IntegrityEvent(reason: reason, detectedAt: _now, drift: drift));
  }

  /// Returns a simulated offline estimate for testing estimation paths.
  ///
  /// Returns `null` if the mock is still trusted or no reboot has been
  /// simulated (i.e., there's no "offline since" reference point).
  TrustedTimeEstimate? nowEstimated() {
    if (_trusted || _rebootTime == null) return null;
    final wallElapsed = _now.difference(_rebootTime!).abs();
    final confidence = (1.0 - wallElapsed.inMinutes / 4320.0).clamp(0.0, 1.0);
    final errorMs = (wallElapsed.inMilliseconds * 0.00005).round();
    return TrustedTimeEstimate(
      estimatedTime: _now,
      confidence: confidence,
      estimatedError: Duration(milliseconds: errorMs),
    );
  }

  /// Broadcasts a simulated event to all listeners.
  void _emit(IntegrityEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  /// Releases resources. Call this in `tearDown` after testing.
  void dispose() => _controller.close();
}
