import 'dart:async';
import '../trusted_time.dart';

/// The global test override for [TrustedTime] (internal use only).
TrustedTimeMock? testOverride;

/// Sets the global test override for [TrustedTime] (internal use only).
void setTestOverride(TrustedTimeMock? mock) => testOverride = mock;

/// High-fidelity test double for deterministic temporal testing.
///
/// Provides a fully controllable virtual clock that simulates all aspects
/// of the TrustedTime API — including trust state, time advancement,
/// integrity events, and offline estimation.
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
  /// Creates a new mock with an initial UTC timestamp.
  TrustedTimeMock({required DateTime initial})
      : _now = initial.toUtc(),
        _trusted = true;

  DateTime _now;
  bool _trusted;
  NtsAuthLevel _authLevel = NtsAuthLevel.none;
  DateTime? _rebootTime;
  final _controller = StreamController<IntegrityEvent>.broadcast();

  /// The current time of the mock.
  DateTime get now => _now;

  /// Whether the mock is currently in a trusted state.
  bool get isTrusted => _trusted;

  /// The current NTS authentication level of the mock.
  NtsAuthLevel get authLevel => _authLevel;

  /// The current time as Unix milliseconds since epoch.
  int get nowUnixMs => _now.millisecondsSinceEpoch;

  /// The current time in ISO-8601 format.
  String get nowIso => _now.toIso8601String();

  /// Emits integrity events simulated by this mock.
  Stream<IntegrityEvent> get onIntegrityLost => _controller.stream;

  /// Advances the mock time by the given duration.
  void advanceTime(Duration delta) => _now = _now.add(delta);

  /// Sets the mock time to the specified UTC [DateTime].
  void setNow(DateTime time) => _now = time.toUtc();

  /// Sets the mock to a trusted or untrusted state.
  void setTrusted(bool trusted) => _trusted = trusted;

  /// Sets the NTS authentication level for this mock.
  void setAuthLevel(NtsAuthLevel level) => _authLevel = level;

  /// Restores the mock to a trusted state and clears reboot history.
  void restoreTrust() {
    _trusted = true;
    _rebootTime = null;
  }

  /// Simulates a device reboot, invalidating trust and emitting an event.
  void simulateReboot() {
    _trusted = false;
    _rebootTime = _now;
    _emit(
      IntegrityEvent(reason: TamperReason.deviceRebooted, detectedAt: _now),
    );
  }

  /// Simulates temporal tampering, emitting an integrity event with the given [reason] and optional [drift].
  void simulateTampering(TamperReason reason, {Duration? drift}) {
    _trusted = false;
    _emit(IntegrityEvent(reason: reason, detectedAt: _now, drift: drift));
  }

  /// Returns an estimated time based on the current mock state.
  TrustedTimeEstimate? nowEstimated() {
    if (_trusted) {
      return TrustedTimeEstimate(
        estimatedTime: _now,
        confidence: 1.0,
        estimatedError: Duration.zero,
      );
    }
    if (_rebootTime == null) return null;
    final wallElapsed = _now.difference(_rebootTime!).abs();
    final confidence = (1.0 - wallElapsed.inMinutes / 4320.0).clamp(0.0, 1.0);
    final errorMs = (wallElapsed.inMilliseconds * 0.00005).round();
    return TrustedTimeEstimate(
      estimatedTime: _now,
      confidence: confidence,
      estimatedError: Duration(milliseconds: errorMs),
    );
  }

  void _emit(IntegrityEvent event) {
    if (!_controller.isClosed) _controller.add(event);
  }

  /// Closes the stream controller and cleans up resources.
  void dispose() => _controller.close();
}
