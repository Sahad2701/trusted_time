/// Thrown when accessing [TrustedTime.now] before a successful sync has
/// established a trust anchor.
///
/// This typically means [TrustedTime.initialize] has not been awaited, or
/// the initial network sync failed.
final class TrustedTimeNotReadyException implements Exception {
  /// Creates a [TrustedTimeNotReadyException].
  const TrustedTimeNotReadyException();

  @override
  String toString() =>
      'TrustedTime is not yet trusted. '
      'Await initialize() and ensure sync succeeded.';
}

/// Thrown when the sync engine cannot reach the required quorum of agreeing
/// time sources.
///
/// This can happen if the device is completely offline, all configured
/// servers are unreachable, or network latency exceeds the configured
/// [TrustedTimeConfig.maxLatency].
final class TrustedTimeSyncException implements Exception {
  /// Creates a [TrustedTimeSyncException] with a descriptive [message].
  const TrustedTimeSyncException(this.message);

  /// Human-readable description of why consensus failed.
  final String message;

  @override
  String toString() => 'TrustedTimeSyncException: $message';
}

/// Thrown when [TrustedTime.trustedLocalTimeIn] is called with an IANA
/// timezone identifier that does not exist in the embedded database.
///
/// Example invalid identifiers: `'Mars/Elon_City'`, `'UTC+5'`.
final class UnknownTimezoneException implements Exception {
  /// Creates an [UnknownTimezoneException] for the given [identifier].
  const UnknownTimezoneException(this.identifier);

  /// The unrecognized IANA timezone identifier.
  final String identifier;

  @override
  String toString() => 'Unknown timezone: $identifier';
}

/// Thrown when a secure time query is requested but the engine cannot provide
/// cryptographically authenticated time (e.g. NTS failed).
final class TrustedTimeSecurityException implements Exception {
  /// Creates a [TrustedTimeSecurityException] with a descriptive [message].
  const TrustedTimeSecurityException(this.message);

  /// Human-readable description of the security requirement violation.
  final String message;
  @override
  String toString() => 'TrustedTimeSecurityException: $message';
}

/// Thrown when local state restoration or persistence fails.
final class TrustedTimePersistenceException implements Exception {
  /// Creates a [TrustedTimePersistenceException] with a descriptive [message].
  const TrustedTimePersistenceException(this.message);

  /// Human-readable description of the persistence error.
  final String message;
  @override
  String toString() => 'TrustedTimePersistenceException: $message';
}

/// Thrown by a `TimeSource` to signal that the failure was transient and
/// the source should be retried on the next sync cycle without the
/// exponential cooldown that other failures incur.
///
/// Example: an `NtsSource` whose `ntsQuery` returned
/// `NtsError.timeout(TimeoutPhase.dnsSaturation)` because the bounded DNS
/// resolver pool was momentarily full. The host itself is healthy; the
/// next cycle will probably succeed once peers release their resolver
/// slots, so blacklisting the source for minutes would be incorrect.
final class TransientSourceError implements Exception {
  /// Creates a [TransientSourceError] wrapping the underlying [cause].
  const TransientSourceError(this.cause);

  /// The original error that the source classified as transient.
  final Object cause;

  @override
  String toString() => 'TransientSourceError: $cause';
}