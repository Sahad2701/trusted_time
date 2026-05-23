/// Authentication levels for NTS queries.
///
/// **Migration note (v2.0.3 → v2.1.0)**: `NtsAuthLevel.advisory` has been
/// removed. It was deprecated in v2.0.3 when the implementation migrated to
/// `package:nts` (RFC 8915-compliant Rust backend). Any exhaustive `switch`
/// or `if` branch that handled `.advisory` must be deleted; the case is no
/// longer reachable. Code that previously treated `.advisory` as a weak-auth
/// signal should instead rely on [NtsAuthLevel.none] for unauthenticated
/// sources and [NtsAuthLevel.verified] for cryptographically authenticated
/// ones.
enum NtsAuthLevel {
  /// No authentication performed (plain NTP or HTTPS `Date` header).
  none,

  /// Full RFC 8915 cryptographic authentication via `package:nts`.
  ///
  /// Uses a Rust-based TLS 1.3 client with proper RFC 5705 keying material
  /// exporters and AES-SIV-CMAC-256 AEAD. Provides cryptographic authenticity
  /// guarantees against on-path attackers.
  verified,
}
