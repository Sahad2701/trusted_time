import 'dart:async';
import 'network_resolver.dart';

/// A stub resolver for platforms that do not support raw UDP/NTP sockets (e.g., Web).
abstract final class NtpTimeResolver {
  /// Resolves trusted time using an NTP quorum strategy (Unsupported on this platform).
  static Future<NetworkTimeResult?> resolve() async {
    // NTP requires raw UDP sockets, which are not available in the browser.
    // We return null to fallback to HTTPS-based resolution.
    return null;
  }
}
