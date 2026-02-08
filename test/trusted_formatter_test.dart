import 'package:flutter_test/flutter_test.dart';
import 'package:trusted_time/src/formatter.dart';

void main() {
  group('TrustedTimeFormat', () {
    test('iso() returns valid ISO-8601 string', () {
      final iso = TrustedTimeFormat.iso();
      // Match ISO: YYYY-MM-DDTHH:MM:SS.sss... (variable precision)
      expect(iso, matches(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z?$'));
    });

    test('unixSeconds() returns reasonable value', () {
      final unix = TrustedTimeFormat.unixSeconds();
      // Greater than Jan 2024
      expect(unix, greaterThan(1704067200));
    });

    test('rfc1123() returns valid HTTP-date format', () {
      final rfc = TrustedTimeFormat.rfc1123();
      // Example: Sat, 07 Feb 2026 15:43:12 GMT
      expect(rfc, matches(r'^[A-Z][a-z]{2}, \d{2} [A-Z][a-z]{2} \d{4} \d{2}:\d{2}:\d{2} GMT$'));
    });

    test('relativeToNow() returns correct strings with reference time', () {
      final baseNow = DateTime(2026, 2, 7, 10, 0, 0);
      
      expect(
        TrustedTimeFormat.relativeToNow(baseNow, relativeTo: baseNow), 
        equals('just now')
      );

      final future = baseNow.add(const Duration(minutes: 5));
      expect(
        TrustedTimeFormat.relativeToNow(future, relativeTo: baseNow), 
        equals('in 5 minutes')
      );

      final past = baseNow.subtract(const Duration(hours: 2));
      expect(
        TrustedTimeFormat.relativeToNow(past, relativeTo: baseNow), 
        equals('2 hours ago')
      );

      final yesterday = baseNow.subtract(const Duration(days: 1));
      expect(
        TrustedTimeFormat.relativeToNow(yesterday, relativeTo: baseNow), 
        equals('yesterday')
      );
    });

    test('yyyyMMdd() returns correct format', () {
      final date = TrustedTimeFormat.yyyyMMdd();
      expect(date, matches(r'^\d{4}-\d{2}-\d{2}$'));
    });
  });
}
