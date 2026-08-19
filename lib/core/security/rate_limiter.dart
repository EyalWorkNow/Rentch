import 'dart:async';

import 'package:dating_app/core/network/circuit_breaker.dart';
import 'package:dating_app/core/security/security_config.dart';

// In-memory token-bucket rate limiter.
//
// Why this matters at scale: with 1M concurrent users all writing to Appwrite,
// even small bursts of rapid writes (rapid swipes, message spam) will:
//   - Exhaust Appwrite's per-project API rate limits
//   - Create write conflicts on state documents
//   - Cause excessive bandwidth/storage costs
//
// This limiter runs on the CLIENT — it is NOT a replacement for server-side
// rate limiting (which must be set in Appwrite's Functions or API Rules).
// It reduces wasted API calls before they leave the device.
//
// Circuit breakers (CircuitBreaker instances on each service) are the
// complementary server-side guard: they trip when Appwrite is degraded and
// fast-fail calls device-side until the backend recovers.

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

  // Shared circuit breakers — referenced here so logout resets them all.
  static final appwriteProperties = CircuitBreaker(name: 'appwrite-properties');
  static final appwriteUsers = CircuitBreaker(name: 'appwrite-users');
  static final appwriteMessages = CircuitBreaker(name: 'appwrite-messages');

  // Reset all buckets and breakers (call on logout)
  void reset() {
    _buckets.clear();
    appwriteProperties.reset();
    appwriteUsers.reset();
    appwriteMessages.reset();
  }

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
  Timer? _timer;

  // Schedule a write. If another write arrives within [delay], the earlier one
  // is cancelled and only the latest executes. Timer-based (not Future.delayed)
  // so cancel() can actually stop it — widget tests fail on pending timers left
  // after dispose, and a long delay window made that visible.
  Future<void> schedule(Future<void> Function() write) async {
    _pending = write;
    _timer?.cancel();
    _timer = Timer(delay, () {
      final fn = _pending;
      _pending = null;
      if (fn != null) unawaited(fn());
    });
  }

  // Drop any pending write without executing it (call on dispose).
  void cancel() {
    _timer?.cancel();
    _timer = null;
    _pending = null;
  }

  // Force-flush any pending write immediately (call on app suspend/logout)
  Future<void> flush() async {
    _timer?.cancel();
    _timer = null;
    final fn = _pending;
    _pending = null;
    if (fn != null) await fn();
  }
}
