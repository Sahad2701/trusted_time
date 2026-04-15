import 'package:http/http.dart' as http;
import '../models.dart';

export 'ntp_source_stub.dart' if (dart.library.io) 'ntp_source_io.dart';

/// Fetches UTC time from an HTTPS endpoint's `Date` response header.
///
/// Provides a universal fallback for environments where UDP (NTP) traffic
/// is blocked. The server's `Date` header is corrected for one-way network
/// latency using the measured round-trip time.
///
/// Pass a pre-configured [http.Client] for enterprise certificate pinning:
/// ```dart
/// final client = IOClient(HttpClient(context: mySecurityContext));
/// final source = HttpsSource('https://internal.example.com', client: client);
/// ```
final class HttpsSource implements TrustedTimeSource {
  HttpsSource(this._url, {http.Client? client})
    : _client = client ?? http.Client();

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
    return serverTime
        .add(Duration(milliseconds: sw.elapsedMilliseconds ~/ 2))
        .toUtc();
  }

  void dispose() => _client.close();
}

/// Internal parser for RFC 7231 / RFC 1123 HTTP date headers.
final class _HttpDate {
  static const _months = {
    'Jan': 1, 'Feb': 2, 'Mar': 3, 'Apr': 4, 'May': 5, 'Jun': 6,
    'Jul': 7, 'Aug': 8, 'Sep': 9, 'Oct': 10, 'Nov': 11, 'Dec': 12,
  };

  static const _weekdays = {'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'};

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
