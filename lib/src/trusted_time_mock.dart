import 'dart:async';
import 'integrity_event.dart';
import 'trusted_time_estimate.dart';

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
  TrustedTimeMock({required DateTime initial})
      : _now = initial.toUtc(),
        _trusted = true;

  DateTime _now;
  bool _trusted;
  DateTime? _rebootTime;
  final _controller = StreamController<IntegrityEvent>.broadcast();

  DateTime get now => _now;
  bool get isTrusted => _trusted;
  int get nowUnixMs => _now.millisecondsSinceEpoch;
  String get nowIso => _now.toIso8601String();
  Stream<IntegrityEvent> get onIntegrityLost => _controller.stream;

  void advanceTime(Duration delta) => _now = _now.add(delta);
  void setNow(DateTime time) => _now = time.toUtc();
  void restoreTrust() {
    _trusted = true;
    _rebootTime = null;
  }

  void simulateReboot() {
    _trusted = false;
    _rebootTime = _now;
    _emit(
      IntegrityEvent(reason: TamperReason.deviceRebooted, detectedAt: _now),
    );
  }

  void simulateTampering(TamperReason reason, {Duration? drift}) {
    _trusted = false;
    _emit(IntegrityEvent(reason: reason, detectedAt: _now, drift: drift));
  }

  /// Returns an estimated time — aligned with production behavior.
  ///
  /// When trusted, returns a high-confidence estimate (matching production
  /// where an anchor is available). When untrusted after a simulated reboot,
  /// confidence decays over time just like production.
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

  void dispose() => _controller.close();
}
