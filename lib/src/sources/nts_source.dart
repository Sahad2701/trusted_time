import 'package:flutter/foundation.dart';
import 'package:nts/nts.dart' as nts;

import '../domain/time_sample.dart';
import '../domain/time_source.dart';
import '../domain/time_interval.dart';
import '../exceptions.dart';
import '../models.dart';
import 'nts_auth_level.dart';

/// RFC 8915-compliant NTS (Network Time Security) time source.
///
/// Uses [package:nts](https://pub.dev/packages/nts) which provides a
/// Rust-based implementation via `flutter_rust_bridge` with proper
/// TLS 1.3 keying material exporter support (RFC 5705).
///
/// This implementation is **fully conformant** with RFC 8915:
/// - Proper AEAD key derivation via TLS exporter
/// - AES-SIV-CMAC-256 authenticated encryption
/// - Secure NTPv4 extension field handling
///
/// **Platform support:** Android, iOS, macOS, Windows, Linux.
/// Not available on Web (NTS requires TLS 1.3 with exporters).
///
/// **Zero overhead when unused:** When [TrustedTimeConfig.ntsServers] is
/// empty (the default), no NTS connections are made.
final class NtsSource implements TimeSource {
  /// Creates an NTS source for the given NTS-KE server.
  ///
  /// [maxLatency] is forwarded as `ntsQuery`'s `timeoutMs`. [SyncEngine]
  /// passes [TrustedTimeConfig.maxLatency] so the inner per-query budget
  /// matches the outer `.timeout(_config.maxLatency)` wrapper. Without
  /// this, an inner timeout longer than the outer would always be
  /// pre-empted by Dart's `TimeoutException`, swallowing the
  /// phase-tagged `NtsError.timeout(TimeoutPhase)` payload that drives
  /// the [TransientSourceError] cooldown-bypass path. The default of 5 s
  /// preserves the prior hardcoded behaviour for direct callers.
  NtsSource(
    this._host, {
    int port = 4460,
    Duration maxLatency = const Duration(seconds: 5),
  }) : _port = port,
       _timeoutMs = maxLatency.inMilliseconds;

  final String _host;
  final int _port;
  final int _timeoutMs;

  @override
  String get id => '${TimeSource.prefixNts}$_host';

  @override
  String get groupId => _host;

  /// Whether this source is cryptographically secure.
  /// Returns `true` — this implementation uses proper RFC 8915 AEAD
  /// authentication via TLS keying material exporters.
  bool get isSecure => true;

  @override
  Future<TimeSample> getTime() async {
    final nts.NtsTimeSample result;
    try {
      result = await nts.ntsQuery(
        spec: nts.NtsServerSpec(host: _host, port: _port),
        timeoutMs: _timeoutMs,
      );
    } on nts.NtsError_Timeout catch (e) {
      // Dns(Saturation) means the bounded DNS resolver pool was at
      // capacity for this call. The host itself is healthy; SyncEngine
      // should retry on the next cycle without applying exponential
      // cooldown. Other timeout phases (Connect, Tls, KeRecordIo, Ntp,
      // DnsTimeout) propagate as-is and follow the standard cooldown
      // path.
      if (e.field0 == nts.TimeoutPhase.dnsSaturation) {
        throw TransientSourceError(e);
      }
      rethrow;
    }

    if (kDebugMode) {
      final p = result.phaseTimings;
      debugPrint(
        '[TrustedTime] nts:$_host '
        'rtt=${(result.roundTripMicros / 1000).toStringAsFixed(1)}ms '
        'dns=${(p.dnsMicros / 1000).toStringAsFixed(1)}ms '
        'connect=${(p.connectMicros / 1000).toStringAsFixed(1)}ms '
        'tls=${(p.tlsHandshakeMicros / 1000).toStringAsFixed(1)}ms '
        'ke=${(p.keRecordIoMicros / 1000).toStringAsFixed(1)}ms',
      );
    }

    // Calculate uncertainty from network RTT (convert microseconds to milliseconds)
    final uncertaintyMs = result.roundTripMicros ~/ 2000;
    final timestampMs = result.utcUnixMicros ~/ 1000;

    return TimeSample(
      interval: TimeInterval(
        startMs: timestampMs - uncertaintyMs,
        endMs: timestampMs + uncertaintyMs,
      ),
      sourceId: id,
      groupId: groupId,
      // Full RFC 8915 compliance = cryptographic security
      authLevel: NtsAuthLevel.verified,
    );
  }
}
