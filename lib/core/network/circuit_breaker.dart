import 'dart:async';

import 'package:flutter/foundation.dart';

// Circuit-breaker — prevents cascade failures when Appwrite is degraded.
//
// Why this matters at 1M clients:
//   If Appwrite goes down for 30 s, every device keeps retrying at full rate.
//   The breaker trips after [failureThreshold] consecutive failures, then
//   fast-fails all calls until [timeout] has elapsed — giving the server space
//   to recover instead of being crushed by the combined retry storm.
//
// State machine:
//   closed  ──(failures ≥ threshold)──▶  open
//   open    ──(timeout elapsed)────────▶  half-open
//   half-open ──(success ≥ succThreshold)▶ closed
//   half-open ──(any failure)────────────▶ open
//
// Usage:
//   final _breaker = CircuitBreaker(name: 'appwrite-properties');
//   final result = await _breaker.call(() => tables.listRows(...));

enum CircuitState { closed, open, halfOpen }

class CircuitBreaker {
  CircuitBreaker({
    this.name = 'default',
    this.failureThreshold = 5,
    this.successThreshold = 2,
    this.timeout = const Duration(seconds: 30),
  });

  final String name;
  final int failureThreshold;
  final int successThreshold;
  final Duration timeout;

  CircuitState _state = CircuitState.closed;
  int _failures = 0;
  int _probeSuccesses = 0;
  DateTime? _openedAt;

  CircuitState get state => _state;
  bool get isOpen => _state == CircuitState.open;

  Future<T> call<T>(Future<T> Function() action) async {
    _maybeTransitionToHalfOpen();

    if (_state == CircuitState.open) {
      throw CircuitOpenException(name);
    }

    try {
      final result = await action();
      _recordSuccess();
      return result;
    } catch (e) {
      if (e is CircuitOpenException) rethrow;
      _recordFailure();
      rethrow;
    }
  }

  void _maybeTransitionToHalfOpen() {
    if (_state != CircuitState.open) return;
    final opened = _openedAt;
    if (opened != null && DateTime.now().difference(opened) >= timeout) {
      _state = CircuitState.halfOpen;
      _probeSuccesses = 0;
      _log('→ half-open (probe)');
    }
  }

  void _recordSuccess() {
    _failures = 0;
    if (_state == CircuitState.halfOpen) {
      _probeSuccesses++;
      if (_probeSuccesses >= successThreshold) {
        _state = CircuitState.closed;
        _log('→ closed (recovered)');
      }
    }
  }

  void _recordFailure() {
    _failures++;
    if (_state == CircuitState.halfOpen) {
      _state = CircuitState.open;
      _openedAt = DateTime.now();
      _log('→ open (probe failed)');
    } else if (_state == CircuitState.closed &&
        _failures >= failureThreshold) {
      _state = CircuitState.open;
      _openedAt = DateTime.now();
      _log('→ open (threshold reached: $_failures failures)');
    }
  }

  void reset() {
    _state = CircuitState.closed;
    _failures = 0;
    _probeSuccesses = 0;
    _openedAt = null;
  }

  void _log(String msg) {
    if (kDebugMode) debugPrint('CircuitBreaker[$name]: $msg');
  }
}

class CircuitOpenException implements Exception {
  CircuitOpenException(this.circuit);
  final String circuit;
  @override
  String toString() => 'CircuitOpenException: circuit "$circuit" is open';
}
