import '../models.dart';

/// Cache for the last successful consensus result.
/// Helps survive short-term network issues and app restarts.
final class ConsensusCache {
  ConsensusCache({this.ttl = const Duration(hours: 24)});

  /// How long a cached anchor remains valid for bootstrap.
  final Duration ttl;

  TrustAnchor? _lastAnchor;
  DateTime? _cachedAt;

  /// Updates the cache with a new anchor.
  void update(TrustAnchor anchor) {
    _lastAnchor = anchor;
    _cachedAt = DateTime.now();
  }

  /// Retrieves the last anchor if it's still within TTL.
  TrustAnchor? get() {
    if (_lastAnchor == null || _cachedAt == null) return null;
    
    final age = DateTime.now().difference(_cachedAt!);
    if (age > ttl) {
      _lastAnchor = null;
      return null;
    }
    
    return _lastAnchor;
  }

  /// Clears the cache.
  void clear() {
    _lastAnchor = null;
    _cachedAt = null;
  }
}
