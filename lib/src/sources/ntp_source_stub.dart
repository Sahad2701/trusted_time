import '../models.dart';

/// Web/stub NTP source — NTP (UDP) is unavailable on this platform.
///
/// The [SyncEngine._querySafe] catch clause handles the thrown error
/// gracefully, so the engine will simply rely on HTTPS sources on web.
final class NtpSource implements TrustedTimeSource {
  const NtpSource(this._host);

  final String _host;

  @override
  String get id => 'ntp:$_host';

  @override
  Future<DateTime> queryUtc() async {
    throw UnsupportedError('NTP (UDP) is not available on this platform.');
  }
}
