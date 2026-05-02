import 'package:ntp/ntp.dart';
import '../domain/time_sample.dart';
import '../domain/time_source.dart';
import '../domain/time_interval.dart';

/// NTP time source — IO-only (uses UDP sockets via `dart:io`).
final class NtpSource implements TimeSource {
  const NtpSource(this._host);

  final String _host;

  @override
  String get id => '${TimeSource.prefixNtp}$_host';

  @override
  String get groupId => _host.split('.').reversed.skip(1).take(2).toList().reversed.join('.') 
      .replaceFirst('pool.ntp.org', 'ntp-pool'); // Basic group heuristic

  @override
  Future<TimeSample> getTime() async {
    final sw = Stopwatch()..start();
    final offset = await NTP.getNtpOffset(
      lookUpAddress: _host,
      timeout: const Duration(seconds: 10),
    );
    sw.stop();
    
    final utc = DateTime.now().toUtc().add(Duration(milliseconds: offset));
    final u = sw.elapsedMilliseconds ~/ 2;
    
    return TimeSample(
      interval: TimeInterval(
        startMs: utc.millisecondsSinceEpoch - u,
        endMs: utc.millisecondsSinceEpoch + u,
      ),
      sourceId: id,
      groupId: groupId,
    );
  }
}
