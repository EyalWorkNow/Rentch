import 'package:dating_app/core/security/security_config.dart';

// In-memory token-bucket rate limiter.
//
// Why this matters at scale: with 10,000 concurrent users all writing to Appwrite,
// even small bursts of rapid writes (rapid swipes, message spam) will:
//   - Exhaust Appwrite's per-project API rate limits
//   - Create write conflicts on state documents
//   - Cause excessive bandwidth/storage costs
//
// This limiter runs on the CLIENT — it is NOT a replacement for server-side
// rate limiting (which must be set in Appwrite's Functions or API Rules).
// It reduces wasted API calls before they leave the device.

class RateLimiter {
  RateLimiter._();

  static final RateLimiter _instance = RateLimiter._();
  static RateLimiter get instance => _instance;

  final Map<_LimitKey, _TokenBucket> _buckets = {};

  // ── Public API ────────────────────────────────────────────────────────────────

  bool allowStateWrite() => _consume(_LimitKey.stateWrite);
  bool allowSwipe() => _consume(_LimitKey.swipe);
  bool allowMessage() => _consume(_LimitKey.message);
  bool allowPropertyAdd() => _consume(_LimitKey.propertyAdd);
  bool allowImageUpload() => _consume(_LimitKey.imageUpload);

  // How many tokens remain for an operation (for UI feedback)
  int remainingSwipes() => _remaining(_LimitKey.swipe);
  int remainingMessages() => _remaining(_LimitKey.message);

  // Reset all buckets (call on logout)
  void reset() => _buckets.clear();

  // ── Internal ───────────────────────────────────────────────────────────────

  bool _consume(_LimitKey key) {
    final bucket = _buckets.putIfAbsent(key, () => _bucketFor(key));
    return bucket.consume();
  }

  int _remaining(_LimitKey key) {
    final bucket = _buckets[key];
    if (bucket == null) return _bucketFor(key).capacity;
    return bucket.tokens;
  }

  _TokenBucket _bucketFor(_LimitKey key) {
    switch (key) {
      case _LimitKey.stateWrite:
        return _TokenBucket(
          capacity: SecurityConfig.maxStateWritesPerMinute,
          refillPeriod: const Duration(minutes: 1),
        );
      case _LimitKey.swipe:
        return _TokenBucket(
          capacity: SecurityConfig.maxSwipesPerMinute,
          refillPeriod: const Duration(minutes: 1),
        );
      case _LimitKey.message:
        return _TokenBucket(
          capacity: SecurityConfig.maxMessagesPerMinute,
          refillPeriod: const Duration(minutes: 1),
        );
      case _LimitKey.propertyAdd:
        return _TokenBucket(
          capacity: SecurityConfig.maxPropertyAddsPerHour,
          refillPeriod: const Duration(hours: 1),
        );
      case _LimitKey.imageUpload:
        return _TokenBucket(
          capacity: SecurityConfig.maxImageUploadsPerSession,
          refillPeriod: const Duration(hours: 24),
        );
    }
  }
}

enum _LimitKey { stateWrite, swipe, message, propertyAdd, imageUpload }

class _TokenBucket {
  _TokenBucket({
    required this.capacity,
    required this.refillPeriod,
  }) : _tokens = capacity,
       _lastRefill = DateTime.now();

  final int capacity;
  final Duration refillPeriod;
  int _tokens;
  DateTime _lastRefill;

  int get tokens {
    _maybeRefill();
    return _tokens;
  }

  bool consume() {
    _maybeRefill();
    if (_tokens <= 0) return false;
    _tokens--;
    return true;
  }

  void _maybeRefill() {
    final now = DateTime.now();
    if (now.difference(_lastRefill) >= refillPeriod) {
      _tokens = capacity;
      _lastRefill = now;
    }
  }
}

// ── Write debouncer ────────────────────────────────────────────────────────────
//
// The provider calls _persist() on every action (swipe, message, filter change).
// With 10k users, batching writes to Appwrite is critical for performance.
// This debouncer collapses rapid successive writes into one.

class WriteDebouncer {
  WriteDebouncer({this.delay = const Duration(milliseconds: 800)});

  final Duration delay;
  Future<void> Function()? _pending;
  DateTime? _lastScheduled;

  // Schedule a write. If another write arrives within [delay], the earlier one
  // is cancelled and only the latest executes.
  Future<void> schedule(Future<void> Function() write) async {
    _lastScheduled = DateTime.now();
    final scheduled = _lastScheduled;
    _pending = write;

    await Future<void>.delayed(delay);

    // If another call came in while we were waiting, skip this one
    if (_lastScheduled != scheduled) return;

    final fn = _pending;
    _pending = null;
    if (fn != null) await fn();
  }

  // Force-flush any pending write immediately (call on app suspend/logout)
  Future<void> flush() async {
    final fn = _pending;
    _pending = null;
    _lastScheduled = null;
    if (fn != null) await fn();
  }
}
