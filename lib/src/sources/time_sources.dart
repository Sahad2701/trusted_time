import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:ntp/ntp.dart';
import '../models.dart';

/// Fetches UTC time using the UDP-based Network Time Protocol.
///
/// NTP provides sub-millisecond precision through hardware-level timestamps
/// at the server. Each [NtpSource] wraps a single NTP server hostname and
/// converts the measured offset into an absolute UTC [DateTime].
///
/// ```dart
/// final source = NtpSource('time.google.com');
/// final utc = await source.queryUtc();
/// ```
final class NtpSource implements TrustedTimeSource {
  /// Creates an NTP source targeting the given [host].
  ///
  /// Common examples: `'time.google.com'`, `'pool.ntp.org'`.
  const NtpSource(this._host);

  final String _host;

  @override
  String get id => 'ntp:$_host';

  @override
  Future<DateTime> queryUtc() async {
    final offset = await NTP.getNtpOffset(
      lookUpAddress: _host,
      timeout: const Duration(seconds: 3),
    );
    return DateTime.now().toUtc().add(Duration(milliseconds: offset));
  }
}

/// Fetches UTC time from an HTTPS endpoint's `Date` response header.
///
/// This source provides a universal fallback for environments where UDP
/// (NTP) traffic is blocked by firewalls. The server's `Date` header is
/// corrected for one-way network latency using the measured round-trip time.
///
/// An optional [SecurityContext] can be provided for enterprise certificate
/// pinning scenarios.
///
/// ```dart
/// final source = HttpsSource('https://www.google.com');
/// final utc = await source.queryUtc();
/// ```
final class HttpsSource implements TrustedTimeSource {
  /// Creates an HTTPS time source for the given [url].
  ///
  /// Pass a [securityContext] to enable custom certificate pinning for
  /// enterprise deployments.
  HttpsSource(this._url, {SecurityContext? securityContext})
    : _client = securityContext != null
          ? IOClient(HttpClient(context: securityContext))
          : http.Client();

  final String _url;
  final http.Client _client;

  @override
  String get id => 'https:$_url';

  @override
  Future<DateTime> queryUtc() async {
    final sw = Stopwatch()..start();
    final response = await _client
        .head(Uri.parse(_url))
        .timeout(const Duration(seconds: 3));
    sw.stop();

    final dateHeader = response.headers['date'];
    if (dateHeader == null) {
      throw Exception('Server did not provide a Date header.');
    }

    final serverTime = _HttpDate.parse(dateHeader);
    // Correct for estimated one-way latency (half the round-trip).
    return serverTime
        .add(Duration(milliseconds: sw.elapsedMilliseconds ~/ 2))
        .toUtc();
  }

  /// Closes the underlying HTTP client and releases its socket.
  ///
  /// After calling this method, the source must not be used again.
  void dispose() => _client.close();
}

/// Internal parser for RFC 7231 / RFC 1123 HTTP date headers.
///
/// Handles the standard format: `Thu, 01 Jan 2024 12:00:00 GMT`.
final class _HttpDate {
  static const _months = {
    'Jan': 1,
    'Feb': 2,
    'Mar': 3,
    'Apr': 4,
    'May': 5,
    'Jun': 6,
    'Jul': 7,
    'Aug': 8,
    'Sep': 9,
    'Oct': 10,
    'Nov': 11,
    'Dec': 12,
  };

  static const _weekdays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'};

  /// Parses an HTTP-date string into a UTC [DateTime].
  static DateTime parse(String header) {
    final parts = header
        .split(RegExp(r'[\s,]+'))
        .where((p) => p.isNotEmpty && !_weekdays.contains(p))
        .toList();
    final timeParts = parts[3].split(':');
    return DateTime.utc(
      int.parse(parts[2]),
      _months[parts[1]] ?? 1,
      int.parse(parts[0]),
      int.parse(timeParts[0]),
      int.parse(timeParts[1]),
      int.parse(timeParts[2]),
    );
  }
}
