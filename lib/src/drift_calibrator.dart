/// Minimum elapsed time between two anchor observations before the computed
/// rate is considered reliable enough to replace the static fallback.
const Duration _kMinObservationWindow = Duration(minutes: 30);

/// Maximum physically plausible oscillator drift rate (100 ppm = 0.0001 s/s).
/// Samples that imply a higher rate are discarded as corrupted.
const double _kMaxDriftPpm = 100.0;
const double _kMaxDriftFactor = _kMaxDriftPpm / 1e6;

/// Maximum number of calibration observations retained in the sliding window.
const int _kMaxObservations = 20;

/// A calibration point: wall-clock time and the trusted network UTC at the
/// moment an anchor was committed.
class _Observation {
  const _Observation({required this.wallMs, required this.networkUtcMs});

  final int wallMs;
  final int networkUtcMs;
}

/// Tracks per-device oscillator drift by comparing successive trust anchors
/// and computes a running median drift rate.
///
/// The computed rate replaces [TrustedTimeConfig.oscillatorDriftFactor] in
/// [TrustedTimeImpl.nowEstimated] once a sufficiently long observation window
/// has been accumulated and the rate passes a sanity bound check.
///
/// All methods are synchronous (no I/O). Instances are not thread-safe; they
/// must be accessed from the same isolate as [TrustedTimeImpl].
final class DriftCalibrator {
  final _observations = <_Observation>[];

  /// The calibrated drift factor (s/s), or `null` if insufficient data.
  ///
  /// Callers should fall back to the configured static factor when this
  /// returns `null`.
  double? get calibratedFactor => _calibratedFactor;
  double? _calibratedFactor;

  /// Records a new trust anchor observation.
  ///
  /// [wallMs] is `DateTime.now().millisecondsSinceEpoch` at anchor commit
  /// time. [networkUtcMs] is the consensus-derived UTC from the anchor.
  void recordAnchor(int wallMs, int networkUtcMs) {
    _observations.add(_Observation(wallMs: wallMs, networkUtcMs: networkUtcMs));

    // Keep the window bounded.
    while (_observations.length > _kMaxObservations) {
      _observations.removeAt(0);
    }

    _recompute();
  }

  void _recompute() {
    if (_observations.length < 2) return;

    final oldest = _observations.first;
    final newest = _observations.last;

    final elapsedWallMs = newest.wallMs - oldest.wallMs;

    // Require a minimum observation window before trusting the result.
    if (elapsedWallMs < _kMinObservationWindow.inMilliseconds) return;

    // Collect per-segment drift rates across the full observation history.
    final rates = <double>[];
    for (var i = 1; i < _observations.length; i++) {
      final prev = _observations[i - 1];
      final curr = _observations[i];
      final segWallMs = curr.wallMs - prev.wallMs;
      if (segWallMs <= 0) continue;
      final segNetworkMs = curr.networkUtcMs - prev.networkUtcMs;
      // drift = (wall elapsed - network elapsed) / wall elapsed
      final drift = (segWallMs - segNetworkMs).abs() / segWallMs;
      rates.add(drift);
    }

    if (rates.isEmpty) return;

    final median = _median(rates);

    // Sanity-check: reject physically implausible values.
    if (median > _kMaxDriftFactor) {
      // Corrupted sample set — clear and wait for fresh observations.
      _observations.clear();
      _calibratedFactor = null;
      return;
    }

    _calibratedFactor = median;
  }

  /// Clears all observations and the computed factor.
  void reset() {
    _observations.clear();
    _calibratedFactor = null;
  }

  static double _median(List<double> values) {
    final sorted = List<double>.from(values)..sort();
    final mid = sorted.length ~/ 2;
    return sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
}
