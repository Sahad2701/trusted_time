import 'package:flutter/foundation.dart';
import 'time_interval.dart';

import '../sources/nts_source.dart';

/// Represents a single time measurement from a remote authority.
/// Combines the mathematical [interval] with telemetry [sourceId] and [groupId].
@immutable
final class TimeSample {
  const TimeSample({
    required this.interval,
    required this.sourceId,
    required this.groupId,
    this.authLevel = NtsAuthLevel.none,
  });

  /// The mathematical time interval.
  final TimeInterval interval;

  /// Unique identifier of the source (e.g., 'ntp:time.google.com').
  final String sourceId;

  /// Group identifier to detect correlated sources (e.g., ASN, provider, or region).
  final String groupId;

  /// The authentication level achieved for this specific sample.
  final NtsAuthLevel authLevel;

  /// Helper to get the UTC time (midpoint of the interval).
  DateTime get utc => DateTime.fromMillisecondsSinceEpoch(interval.midpoint, isUtc: true);

  /// Helper to get the uncertainty in milliseconds.
  int get uncertaintyMs => interval.width ~/ 2;

  @override
  String toString() =>
      'TimeSample(interval: $interval, from: $sourceId, group: $groupId)';
}
