import 'dart:async';
import '../trusted_time.dart';

/// Documented.
TrustedTimeMock? testOverride;

/// Documented.
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
  /// Documented.
  TrustedTimeMock({required DateTime initial})
      : _now = initial.toUtc(),
        _trusted = true;

  DateTime _now;
  bool _trusted;
  NtsAuthLevel _authLevel = NtsAuthLevel.none;
  DateTime? _rebootTime;
  final _controller = StreamController<IntegrityEvent>.broadcast();

  /// Documented.
  DateTime get now => _now;

  /// Documented.
  bool get isTrusted => _trusted;

  /// Documented.
  NtsAuthLevel get authLevel => _authLevel;

  /// Documented.
  int get nowUnixMs => _now.millisecondsSinceEpoch;

  /// Documented.
  String get nowIso => _now.toIso8601String();

  /// Documented.
  Stream<IntegrityEvent> get onIntegrityLost => _controller.stream;

  /// Documented.
  void advanceTime(Duration delta) => _now = _now.add(delta);

  /// Documented.
  void setNow(DateTime time) => _now = time.toUtc();

  /// Documented.
  void setTrusted(bool trusted) => _trusted = trusted;

  /// Documented.
  void setAuthLevel(NtsAuthLevel level) => _authLevel = level;

  /// Documented.
  void restoreTrust() {
    _trusted = true;
    _rebootTime = null;
  }

  /// Documented.
  void simulateReboot() {
    _trusted = false;
    _rebootTime = _now;
    _emit(
      IntegrityEvent(reason: TamperReason.deviceRebooted, detectedAt: _now),
    );
  }

  /// Documented.
  void simulateTampering(TamperReason reason, {Duration? drift}) {
    _trusted = false;
    _emit(IntegrityEvent(reason: reason, detectedAt: _now, drift: drift));
  }

  /// Documented.
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

  /// Documented.
  void dispose() => _controller.close();
}
