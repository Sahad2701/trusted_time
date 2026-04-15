import 'package:ntp/ntp.dart';
import '../models.dart';

/// NTP time source — IO-only (uses UDP sockets via `dart:io`).
final class NtpSource implements TrustedTimeSource {
  const NtpSource(this._host);

  final String _host;

  @override
  String get id => 'ntp:$_host';

  @override
  Future<DateTime> queryUtc() async {
    final offset = await NTP.getNtpOffset(
      lookUpAddress: _host,
      timeout: const Duration(seconds: 10),
    );
    return DateTime.now().toUtc().add(Duration(milliseconds: offset));
  }
}
