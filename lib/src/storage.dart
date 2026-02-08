import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'exceptions.dart';

/// A snapshot of the internal trust anchor state used for persistence.
class StoredState {
  /// The millisecond epoch verified by network sources at the time of sync.
  final int serverEpochMs;

  /// The device uptime (in ms) at the exact moment the network time was captured.
  final int uptimeMs;

  /// The calculated uncertainty or drift at the time of sync.
  final int driftMs;

  StoredState(this.serverEpochMs, this.uptimeMs, this.driftMs);
}

/// An internal utility for persisting and retrieving synchronization state.
///
/// This class leverages `FlutterSecureStorage` to ensure that even if the
/// app is closed or the device reboots, we can potentially restore a previous
/// trust anchor if it is still valid.
abstract final class TrustedStorage {
  static const _storage = FlutterSecureStorage();

  static const _kEpoch = 'epoch';
  static const _kUptime = 'uptime';
  static const _kDrift = 'drift';

  /// Saves the current trust anchor state to secure storage.
  static Future<void> save({
    required int serverEpochMs,
    required int uptimeMs,
    required int driftMs,
  }) async {
    try {
      await _storage.write(key: _kEpoch, value: '$serverEpochMs');
      await _storage.write(key: _kUptime, value: '$uptimeMs');
      await _storage.write(key: _kDrift, value: '$driftMs');
    } catch (e, stackTrace) {
      throw TrustedTimeStorageException(
        'Critical failure while writing to secure storage.',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Loads the persisted trust anchor state, if available.
  ///
  /// This method performs validation to ensure the data is not corrupted
  /// before returning a [StoredState].
  static Future<StoredState?> load() async {
    try {
      final e = await _storage.read(key: _kEpoch);
      final u = await _storage.read(key: _kUptime);
      final d = await _storage.read(key: _kDrift);

      if (e == null || u == null || d == null) return null;

      final epoch = int.tryParse(e);
      final uptime = int.tryParse(u);
      final drift = int.tryParse(d);

      if (epoch == null || uptime == null || drift == null) {
        throw TrustedTimeStorageException(
          'Storage mismatch: non-numeric values found in secure storage.',
        );
      }

      // Sanity check: epoch should be reasonable (after year 2000).
      if (epoch < 946684800000) {
        throw TrustedTimeStorageException(
          'Storage data rejected: invalid historical epoch timestamp.',
        );
      }

      return StoredState(epoch, uptime, drift);
    } on TrustedTimeStorageException {
      rethrow;
    } catch (e, stackTrace) {
      throw TrustedTimeStorageException(
        'A system error occurred while reading from secure storage.',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }

  /// Clears all persisted trust anchor state from the device.
  static Future<void> clear() async {
    try {
      await _storage.deleteAll();
    } catch (e, stackTrace) {
      throw TrustedTimeStorageException(
        'Failed to purge synchronization state from the device.',
        originalError: e,
        stackTrace: stackTrace,
      );
    }
  }
}
