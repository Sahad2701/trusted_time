import 'dart:async';
import 'ntp_time_resolver.dart';
import 'network_resolver.dart';

/// A high-level orchestrator that manages synchronization across different transports.
///
/// The `HybridTimeResolver` implements a fallback strategy to maximize reliability
/// in diverse network environments (corporate firewalls, restricted cellular data, etc).
///
/// **Strategy Order:**
/// 1. **NTP Quorum**: The preferred method. It is the fastest and provides the
///    strongest mathematical guarantees for precision.
/// 2. **HTTPS/REST Quorum**: A universal fallback that uses standard HTTP traffic
///    (ports 80/443), which is rarely blocked by firewalls.
abstract final class HybridTimeResolver {
  /// Orchestrates the synchronization process using the best available transport.
  ///
  /// This method will first attempt a high-precision NTP resolution. If that
  /// fails or times out, it will automatically fall back to the HTTPS-based
  /// resolver to ensure a trust anchor is established.
  static Future<NetworkTimeResult> resolve() async {
    try {
      // Priority 1: High-precision NTP sync.
      final ntp = await NtpTimeResolver.resolve();
      if (ntp != null) {
        return NetworkTimeResult(
          networkTimeMs: ntp.networkTimeMs,
          uncertaintyMs: ntp.uncertaintyMs,
          sourceCount: ntp.sourceCount,
        );
      }
    } catch (_) {
      // Graceful fallback: NTP might be blocked in this environment.
    }

    // Priority 2: Universal HTTPS fallback.
    return NetworkTimeResolver.resolve();
  }
}
