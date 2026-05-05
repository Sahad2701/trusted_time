import 'package:nts/nts.dart' as nts;

import '../domain/time_sample.dart';
import '../domain/time_source.dart';
import '../domain/time_interval.dart';
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
  NtsSource(this._host, {int port = 4460}) : _port = port;

  final String _host;
  final int _port;

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
    // Use package:nts for full RFC 8915 compliant NTS query
    final result = await nts.ntsQuery(
      spec: nts.NtsServerSpec(host: _host, port: _port),
      timeoutMs: 5000,
    );

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
