import 'time_sample.dart';

/// Contract for implementing custom time-authority providers.
abstract interface class TimeSource {
  /// A unique identifier for this source (e.g., 'ntp:time.google.com').
  String get id;

  /// A group identifier to detect correlated sources (e.g., 'google', 'cloudflare', 'pool.ntp.org').
  String get groupId;

  /// Queries the remote authority and returns a [TimeSample].
  Future<TimeSample> getTime();
}
