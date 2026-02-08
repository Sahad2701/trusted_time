/// Base exception for all errors produced by the TrustedTime library.
///
/// Catch this type to handle any failure related to time synchronization,
/// initial state validation, or secure persistence.
class TrustedTimeException implements Exception {
  /// A descriptive message explaining the failure.
  final String message;

  /// The underlying error (e.g., a [SocketException] or [PlatformException])
  /// that triggered this failure, if available.
  final dynamic originalError;

  /// The stack trace associated with the [originalError].
  final StackTrace? stackTrace;

  const TrustedTimeException(
    this.message, {
    this.originalError,
    this.stackTrace,
  });

  @override
  String toString() {
    if (originalError != null) {
      return 'TrustedTimeException: $message\nCaused by: $originalError';
    }
    return 'TrustedTimeException: $message';
  }
}

/// Thrown when the engine cannot establish its initial communication bridge.
///
/// This typically indicates a missing platform manifest entry (on Android)
/// or a failure to retrieve the initial monotonic uptime from the hardware.
class TrustedTimeInitializationException extends TrustedTimeException {
  const TrustedTimeInitializationException(
    super.message, {
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() {
    if (originalError != null) {
      return 'TrustedTimeInitializationException: $message\nCaused by: $originalError';
    }
    return 'TrustedTimeInitializationException: $message';
  }
}

/// Thrown when the engine fails to achieve a network consensus.
///
/// This occurs if all configured NTP and HTTPS sources are unreachable
/// or if the responses are too inconsistent to establish a quorum.
class TrustedTimeSyncException extends TrustedTimeException {
  const TrustedTimeSyncException(
    super.message, {
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() {
    if (originalError != null) {
      return 'TrustedTimeSyncException: $message\nCaused by: $originalError';
    }
    return 'TrustedTimeSyncException: $message';
  }
}

/// Thrown when reading or writing to the device's secure storage fails.
class TrustedTimeStorageException extends TrustedTimeException {
  const TrustedTimeStorageException(
    super.message, {
    super.originalError,
    super.stackTrace,
  });

  @override
  String toString() {
    if (originalError != null) {
      return 'TrustedTimeStorageException: $message\nCaused by: $originalError';
    }
    return 'TrustedTimeStorageException: $message';
  }
}
