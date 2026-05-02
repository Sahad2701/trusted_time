import '../domain/time_sample.dart';
import '../domain/time_source.dart';
import '../domain/time_interval.dart';

/// NTP time source stub — actual implementation in `ntp_source_io.dart`.
final class NtpSource implements TimeSource {
  const NtpSource(this._host);

  final String _host;

  @override
  String get id => 'ntp:$_host';

  @override
  String get groupId => _host;

  @override
  Future<TimeSample> getTime() => throw UnimplementedError('NTP requires dart:io');
}
