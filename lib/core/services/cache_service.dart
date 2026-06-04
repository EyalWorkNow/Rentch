// LRU + TTL cache for hot data (properties, profiles, message pages).
//
// Why: At 1M concurrent users, even a 5-minute device-level cache dramatically
// cuts Appwrite read pressure on browse-heavy flows (users scrolling the same
// property pages).
//
// Memory budget (conservative):
//   300 property summaries × ~2 KB ≈ 600 KB
//   100 message pages     × ~10 KB ≈ 1 MB
//   500 profiles          × ~0.5 KB ≈ 250 KB
//   Total: ≈ 2 MB — negligible on modern devices.
//
// Eviction policy: LRU (least recently used) so hot items stay in memory.

class _Entry<V> {
  _Entry({required this.value, required this.expiresAt});
  final V value;
  final DateTime expiresAt;
  bool get isExpired => DateTime.now().isAfter(expiresAt);
}

class LruCache<K, V> {
  LruCache({required this.maxSize, required this.ttl});

  final int maxSize;
  final Duration ttl;

  // LinkedHashMap insertion order = LRU order; last inserted = most recent.
  final _store = <K, _Entry<V>>{};

  V? get(K key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (entry.isExpired) {
      _store.remove(key);
      return null;
    }
    // Refresh access order
    _store.remove(key);
    _store[key] = entry;
    return entry.value;
  }

  void put(K key, V value) {
    _store.remove(key); // reset position
    if (_store.length >= maxSize) {
      _store.remove(_store.keys.first); // evict LRU
    }
    _store[key] = _Entry(
      value: value,
      expiresAt: DateTime.now().add(ttl),
    );
  }

  void invalidate(K key) => _store.remove(key);

  void invalidateWhere(bool Function(K key) test) =>
      _store.removeWhere((k, _) => test(k));

  void clear() => _store.clear();
  int get size => _store.length;
  bool containsKey(K key) => _store[key]?.isExpired == false;
}

/// Singleton cache registry. Call [AppCache.instance.clear()] on logout.
class AppCache {
  AppCache._();
  static final AppCache instance = AppCache._();

  /// Property list pages, keyed by `"$areaId:$offset"`.
  /// 5-minute TTL covers a typical browse session without serving stale data.
  final propertyPages = LruCache<String, List<Map<String, dynamic>>>(
    maxSize: 60,
    ttl: const Duration(minutes: 5),
  );

  /// Individual property records, keyed by propertyId.
  final propertyDetail = LruCache<String, Map<String, dynamic>>(
    maxSize: 300,
    ttl: const Duration(minutes: 10),
  );

  /// User / tenant profiles, keyed by userId.
  final profiles = LruCache<String, Map<String, dynamic>>(
    maxSize: 500,
    ttl: const Duration(minutes: 15),
  );

  /// First page of messages per conversation, keyed by matchId.
  /// Short TTL because messages arrive in real-time.
  final messagePages = LruCache<String, List<Map<String, dynamic>>>(
    maxSize: 100,
    ttl: const Duration(minutes: 2),
  );

  void clear() {
    propertyPages.clear();
    propertyDetail.clear();
    profiles.clear();
    messagePages.clear();
  }
}
