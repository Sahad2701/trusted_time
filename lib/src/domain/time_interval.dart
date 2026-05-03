import 'package:flutter/foundation.dart';

/// Represents a CLOSED mathematical interval `[startMs, endMs]` in UNIX epoch milliseconds.
/// Used for Marzullo's consensus algorithm. Both bounds are inclusive.
@immutable
final class TimeInterval {
  /// Documented.
  const TimeInterval({
    required this.startMs,
    required this.endMs,
  }) : assert(startMs <= endMs, 'Interval start must be <= end');

  /// The start of the interval (inclusive).
  final int startMs;

  /// The end of the interval (inclusive).
  final int endMs;

  /// The midpoint of the interval.
  int get midpoint => (startMs + endMs) ~/ 2;

  /// The width of the interval (uncertainty).
  int get width => endMs - startMs;

  @override
  String toString() => '[$startMs, $endMs]';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TimeInterval &&
          runtimeType == other.runtimeType &&
          startMs == other.startMs &&
          endMs == other.endMs;

  @override
  int get hashCode => Object.hash(startMs, endMs);
}
