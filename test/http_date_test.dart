import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:trusted_time/src/sources/time_sources.dart';

void main() {
  group('HttpsSource / HttpDate Validation (HIGH-7)', () {
    test('throws FormatException for invalid day range', () async {
      final client = MockClient((request) async {
        return http.Response('', 200, headers: {'date': 'Wed, 99 Jan 2024 12:00:00 GMT'});
      });
      final source = HttpsSource('https://test.com', client: client);

      expect(() => source.getTime(), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for invalid hour range', () async {
      final client = MockClient((request) async {
        return http.Response('', 200, headers: {'date': 'Wed, 01 Jan 2024 25:00:00 GMT'});
      });
      final source = HttpsSource('https://test.com', client: client);

      expect(() => source.getTime(), throwsA(isA<FormatException>()));
    });

    test('throws FormatException for invalid month name', () async {
      final client = MockClient((request) async {
        return http.Response('', 200, headers: {'date': 'Wed, 01 Bad 2024 12:00:00 GMT'});
      });
      final source = HttpsSource('https://test.com', client: client);

      expect(() => source.getTime(), throwsA(isA<FormatException>()));
    });

    test('successfully parses valid RFC 1123 date', () async {
      final client = MockClient((request) async {
        return http.Response('', 200, headers: {'date': 'Wed, 01 May 2024 10:00:00 GMT'});
      });
      final source = HttpsSource('https://test.com', client: client);

      final sample = await source.getTime();
      // 10:00:00 UTC = 1714557600000 ms
      expect(sample.interval.midpoint, closeTo(1714557600000, 5000));
    });
  });
}
