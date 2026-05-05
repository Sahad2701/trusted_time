/// Authentication levels for NTS queries.
enum NtsAuthLevel {
  /// No authentication performed (Plain NTP/HTTPS).
  none,

  /// **DEPRECATED**: Previously used for non-conforming pure-Dart NTS.
  /// The current implementation uses `package:nts` with full RFC 8915 compliance.
  @Deprecated(
    'Use verified instead. This level is no longer supported with the migration to package:nts.',
  )
  advisory,

  /// Full RFC 8915 cryptographic authentication via `package:nts`.
  ///
  /// Uses Rust-based TLS 1.3 with proper RFC 5705 keying material exporters
  /// and AES-SIV-CMAC-256 AEAD. Provides cryptographic authenticity guarantees
  /// against on-path attackers.
  verified,
}
