import 'dart:async';
import 'dart:math' as math;

import 'package:dating_app/core/services/appwrite_client.dart' show AwsApiException;

// Exponential backoff with full jitter.
//
// Formula: random(0, min(cap, base * 2^attempt))
//
// Full jitter is deliberate: with 1M clients, deterministic delays (e.g. "retry
// in 2s, then 4s, then 8s") cause synchronized retry storms — every device hits
// the server at the same moment after a transient outage.  Full jitter spreads
// them evenly over the window, dramatically reducing thundering-herd pressure.
//
// References: https://aws.amazon.com/blogs/architecture/exponential-backoff-and-jitter/

class RetryPolicy {
  const RetryPolicy({
    this.maxAttempts = 4,
    this.base = const Duration(milliseconds: 300),
    this.cap = const Duration(seconds: 30),
    this.retryOn = _isTransient,
  });

  /// Retries only transient Appwrite/network errors.
  static const RetryPolicy transient = RetryPolicy();

  /// Retries anything — use for idempotent reads.
  static const RetryPolicy aggressive = RetryPolicy(maxAttempts: 5);

  /// No retries — use for writes where duplicate execution would be harmful.
  static const RetryPolicy none = RetryPolicy(maxAttempts: 1);

  final int maxAttempts;
  final Duration base;
  final Duration cap;
  final bool Function(Object error) retryOn;

  static final _rng = math.Random.secure();

  static bool _isTransient(Object error) {
    if (error is AwsApiException) {
      final code = error.statusCode ?? 0;
      // 429 = rate limit, 5xx = server errors — all retry-worthy
      return code == 429 || code >= 500;
    }
    return true;
  }

  Duration _delay(int attempt) {
    final capMs = cap.inMilliseconds;
    final baseMs = base.inMilliseconds;
    final ceiling = math.min(capMs.toDouble(), baseMs * math.pow(2, attempt));
    final jitter = (_rng.nextDouble() * ceiling).toInt();
    return Duration(milliseconds: jitter);
  }

  Future<T> execute<T>(Future<T> Function() fn) async {
    Object? lastError;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (e) {
        lastError = e;
        final isLast = attempt == maxAttempts - 1;
        if (isLast || !retryOn(e)) rethrow;
        await Future<void>.delayed(_delay(attempt));
      }
    }
    throw lastError!;
  }
}
