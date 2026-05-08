import 'time_sample.dart';

/// Contract for implementing custom time-authority providers.
abstract interface class TimeSource {
  /// Prefix for Network Time Protocol (NTP) sources.
  static const String prefixNtp = 'ntp:';

  /// Prefix for Secure Network Time Protocol (NTS) sources.
  static const String prefixNts = 'nts:';

  /// Prefix for HTTPS-based time sources.
  static const String prefixHttps = 'https:';

  /// A unique identifier for this source (e.g., 'ntp:time.google.com').
  String get id;

  /// A group identifier to detect correlated sources (e.g., 'google', 'cloudflare', 'pool.ntp.org').
  String get groupId;

  /// Queries the remote authority and returns a [TimeSample].
  Future<TimeSample> getTime();
}

/// Optional capability for [TimeSource]s that need a one-time setup
/// step (handshakes, key exchange, cache priming) which should
/// complete *outside* the per-query latency budget.
///
/// [SyncEngine] type-checks each active source for this interface and
/// runs [warm] before the timed query phase. Sources that do not need
/// warming should not implement this; they will be queried directly.
///
/// Implementations should be idempotent and tolerate repeated
/// invocation. They must not throw; failures should be handled
/// internally so that [TimeSource.getTime] can still attempt a
/// cold-start query.
abstract interface class Warmable {
  /// Performs the source's one-time setup work.
  Future<void> warm();
}
