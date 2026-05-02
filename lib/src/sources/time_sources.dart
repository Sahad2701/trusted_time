import 'package:http/http.dart' as http;
import '../domain/time_sample.dart';
import '../domain/time_source.dart';
import '../domain/time_interval.dart';

export 'ntp_source_stub.dart' if (dart.library.io) 'ntp_source_io.dart';
export 'nts_source_stub.dart' if (dart.library.io) 'nts_source.dart';

/// Fetches UTC time from an HTTPS endpoint's `Date` response header.
final class HttpsSource implements TimeSource {
  HttpsSource(this._url, {http.Client? client})
      : _client = client ?? http.Client();

  final String _url;
  final http.Client _client;

  @override
  String get id => '${TimeSource.prefixHttps}$_url';

  @override
  String get groupId {
    try {
      return Uri.parse(_url).host;
    } catch (_) {
      return _url;
    }
  }

  @override
  Future<TimeSample> getTime() async {
    final uri = Uri.parse(_url);
    final sw = Stopwatch()..start();

    var response = await _client.head(uri).timeout(const Duration(seconds: 3));
    if (response.statusCode == 405 || response.headers['date'] == null) {
      sw.reset();
      sw.start();
      response = await _client.get(uri).timeout(const Duration(seconds: 3));
    }
    sw.stop();

    final dateHeader = response.headers['date'];
    if (dateHeader == null) {
      throw Exception('Server did not provide a Date header.');
    }

    final serverTime = _HttpDate.parse(dateHeader);
    final correctedTime = serverTime
        .add(Duration(milliseconds: sw.elapsedMilliseconds ~/ 2))
        .toUtc();

    final startMs =
        correctedTime.millisecondsSinceEpoch - (sw.elapsedMilliseconds ~/ 2);
    final endMs =
        correctedTime.millisecondsSinceEpoch + (sw.elapsedMilliseconds ~/ 2);

    return TimeSample(
      interval: TimeInterval(startMs: startMs, endMs: endMs),
      sourceId: id,
      groupId: groupId,
    );
  }

  void dispose() => _client.close();
}

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

  static const _weekdays = {
    'Mon',
    'Tue',
    'Wed',
    'Thu',
    'Fri',
    'Sat',
    'Sun',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  };

  static DateTime parse(String header) {
    try {
      final parts = header
          .replaceAll('-', ' ')
          .split(RegExp(r'[\s,]+'))
          .where((p) => p.isNotEmpty && !_weekdays.contains(p))
          .toList();

      if (parts.length < 4) {
        throw FormatException('Unrecognized HTTP-date format: $header');
      }

      final timeParts = parts[3].split(':');
      if (timeParts.length < 3) {
        throw FormatException('Unrecognized time format in HTTP-date: $header');
      }

      final day = int.parse(parts[0]);
      final monthStr = parts[1];
      final month = _months[monthStr];
      if (month == null) throw FormatException('Invalid month: $monthStr');

      var year = int.parse(parts[2]);
      if (year < 100) {
        year += year < 70 ? 2000 : 1900; // RFC 2616 §19.3
      }

      final hour = int.parse(timeParts[0]);
      final min = int.parse(timeParts[1]);
      final sec = int.parse(timeParts[2]);

      if (day < 1 || day > 31) {
        throw const FormatException('Day out of range');
      }
      if (hour < 0 || hour > 23) {
        throw const FormatException('Hour out of range');
      }
      if (min < 0 || min > 59) {
        throw const FormatException('Minute out of range');
      }
      if (sec < 0 || sec > 60) {
        throw const FormatException(
            'Second out of range'); // Allow leap seconds
      }

      return DateTime.utc(year, month, day, hour, min, sec);
    } catch (e) {
      if (e is FormatException) rethrow;
      throw FormatException('Failed to parse HTTP-date: $header ($e)');
    }
  }
}
