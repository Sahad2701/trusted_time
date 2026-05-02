/// Authentication levels for NTS queries.
enum NtsAuthLevel {
  /// No authentication performed (Plain NTP/HTTPS).
  none,

  /// **ADVISORY ONLY**: NTS-KE handshake successful, but AEAD verification
  /// is currently simulated/advisory due to Dart SDK limitations (lack of
  /// TLS exporters and native AES-SIV support).
  ///
  /// This level provides protection against accidental drift but NOT against
  /// determined on-path adversaries. Do not use for high-value financial
  /// or security-critical transactions.
  advisory,

  /// Full cryptographic authentication (Reserved for future native/FFI implementation).
  verified,
}
