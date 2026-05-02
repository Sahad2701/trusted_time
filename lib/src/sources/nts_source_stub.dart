import '../domain/time_sample.dart';
import '../domain/time_source.dart';

/// NTS time source stub — actual implementation in `nts_source.dart`.
final class NtsSource implements TimeSource {
  NtsSource(this._host, {int port = 4460});

  final String _host;

  @override
  String get id => 'nts:$_host';

  @override
  String get groupId => _host;

  @override
  Future<TimeSample> getTime() => throw UnimplementedError('NTS requires dart:io');
}
