import 'core_engine.dart';

/// A production-grade, platform-agnostic formatting API for [TrustedTime].
///
/// This utility provides a wide range of commonly used timestamp formats
/// designed for high reliability across Android, iOS, Web, and Desktop.
///
/// **Design Principles:**
/// * **Stateless**: All methods are pure and depend only on the current trusted time.
/// * **Fail-Safe**: Guaranteed not to throw errors due to missing platform
///   localization libraries (e.g. `dart:ui`).
/// * **Atomic**: Side-effect free and highly efficient.
abstract final class TrustedTimeFormat {
  /// Returns the current trusted time in standardized ISO-8601 format.
  ///
  /// Useful for backend communication and database storage.
  /// Returns a string like: `2026-02-07T15:43:12.345Z`
  static String iso() => TrustedTime.now().toIso8601String();

  /// Returns the current trusted time in RFC 3339 format.
  ///
  /// Similar to ISO-8601 but strictly follows the RFC specification for
  /// internet protocols.
  static String rfc3339() {
    final dt = TrustedTime.now().toUtc();
    return '${_pad(dt.year, 4)}-${_pad(dt.month)}-${_pad(dt.day)}T'
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}Z';
  }

  /// Returns the current trusted time in RFC 1123 format (standard HTTP-date).
  ///
  /// Useful for setting HTTP headers like `Last-Modified` or `Expires`.
  /// Returns a string like: `Sat, 07 Feb 2026 15:43:12 GMT`
  static String rfc1123() {
    final dt = TrustedTime.now().toUtc();
    return '${_weekdays[dt.weekday - 1]}, '
        '${_pad(dt.day)} '
        '${_months[dt.month - 1]} '
        '${dt.year} '
        '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)} GMT';
  }

  /// Returns the current trusted time as a Unix timestamp in seconds.
  static int unixSeconds() => TrustedTime.now().millisecondsSinceEpoch ~/ 1000;

  /// Returns the current trusted time as a Unix timestamp in milliseconds.
  static int unixMilliseconds() => TrustedTime.now().millisecondsSinceEpoch;

  /// Returns a human-centric timestamp formatted for the current local time.
  ///
  /// Returns a string like: `Feb 7, 2026 · 3:43 PM`
  static String humanReadable() {
    final dt = TrustedTime.now();
    return '${_months[dt.month - 1]} ${dt.day}, ${dt.year} · '
        '${_format12Hour(dt)}';
  }

  /// Returns a short date-only format.
  ///
  /// Returns a string like: `2026-02-07`
  static String yyyyMMdd() {
    final dt = TrustedTime.now();
    return '${dt.year}-${_pad(dt.month)}-${_pad(dt.day)}';
  }

  /// Returns a compact date-time format ideal for file logging or audit trails.
  ///
  /// Returns a string like: `20260207_154312`
  static String logCompact() {
    final dt = TrustedTime.now();
    return '${dt.year}${_pad(dt.month)}${_pad(dt.day)}_'
        '${_pad(dt.hour)}${_pad(dt.minute)}${_pad(dt.second)}';
  }

  /// Returns the time in 24-hour clock format.
  ///
  /// Returns a string like: `15:43:12`
  static String hhmmss24() {
    final dt = TrustedTime.now();
    return '${_pad(dt.hour)}:${_pad(dt.minute)}:${_pad(dt.second)}';
  }

  /// Returns the time in 12-hour clock format with AM/PM suffix.
  ///
  /// Returns a string like: `3:43 PM`
  static String hhmm12() => _format12Hour(TrustedTime.now());

  /// Returns a human-friendly relative time string (e.g., "5 minutes ago").
  ///
  /// If provided, [relativeTo] will be used as the anchor point, otherwise it
  /// defaults to the current [TrustedTime.now()].
  static String relativeToNow(DateTime other, {DateTime? relativeTo}) {
    final now = relativeTo ?? TrustedTime.now();
    final diff = other.difference(now);
    final seconds = diff.inSeconds.abs();

    if (seconds < 10) return 'just now';
    if (seconds < 60) return _formatRelative(diff, seconds, 'second');
    if (seconds < 3600) {
      return _formatRelative(diff, seconds ~/ 60, 'minute');
    }
    if (seconds < 86400) {
      return _formatRelative(diff, seconds ~/ 3600, 'hour');
    }
    if (seconds < 172800) {
      return diff.isNegative ? 'yesterday' : 'tomorrow';
    }
    return _formatRelative(diff, seconds ~/ 86400, 'day');
  }

  /// Returns the current trusted time as a UTC [DateTime] object.
  static DateTime utc() => TrustedTime.now().toUtc();

  /// Returns the current trusted time as a local [DateTime] object.
  static DateTime local() => TrustedTime.now().toLocal();

  // Internal Helpers

  static String _formatRelative(Duration diff, int value, String unit) {
    final plural = value == 1 ? unit : '${unit}s';
    return diff.isNegative ? '$value $plural ago' : 'in $value $plural';
  }

  static String _format12Hour(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final suffix = dt.hour < 12 ? 'AM' : 'PM';
    return '$hour:${_pad(dt.minute)} $suffix';
  }

  static String _pad(int value, [int width = 2]) =>
      value.toString().padLeft(width, '0');

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static const List<String> _weekdays = [
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
  ];
}
