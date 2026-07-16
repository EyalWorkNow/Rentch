import 'dart:async';
import 'dart:math' as math;

import 'package:dating_app/core/services/event_service.dart';
import 'package:flutter/foundation.dart';

/// On-device, per-session behavioural aggregator.
///
/// Individual events ([EventService.logBackNavigation], `logSearchRefined`,
/// `logLeadFunnelStep`, …) are the raw stream; this service keeps a lightweight
/// ROLLING SUMMARY of them so we can emit one compact `sessionInsights` row that
/// characterises the user for this session — their *type* (decisive vs
/// explorer), *search style* (how much they refine, in which direction), and how
/// far they walked toward the conversion action (leaving details / contacting a
/// landlord). Downstream, the ranker and product analytics read this summary
/// without having to re-aggregate thousands of raw event rows.
///
/// Design contract (mirrors [EventService]):
///   • Fully self-contained — no wiring into other screens. Callers ADOPT it by
///     calling the `note*` methods; nothing here reaches back into the UI.
///   • Best-effort / non-blocking — every method is fail-soft and cheap
///     (in-memory counters + small sets), never throws into a caller.
///   • Feedable from the same behaviours the typed events capture, so a screen
///     can emit the raw event AND note it here in one place.
///   • Flushes on a periodic timer and on session end; `flush()` emits a
///     `sessionInsights` event and then resets the window.
///
/// Emitted summary shape (all keys optional; bounded, well under the 2 KB cap):
/// ```
/// {
///   "screensVisited":        int,     // distinct screen names seen
///   "backCount":             int,     // total back/pop navigations
///   "systemBackCount":       int,     // OS/gesture backs (subset of backCount)
///   "inAppBackCount":        int,     // tapped in-app backs (subset)
///   "dwell": {                        // per-screen dwell distribution (ms)
///     "count": int, "sumMs": int, "minMs": int, "maxMs": int, "avgMs": int
///   },
///   "refine": {                       // search-refinement style
///     "total": int, "broaden": int, "narrow": int, "lateral": int,
///     "net": "broaden"|"narrow"|"balanced"   // dominant direction
///   },
///   "searchAbandonedCount":  int,
///   "hesitationCount":       int,
///   "reversals":             int,     // summed back-and-forth actions
///   "breadth": {                      // exploration breadth
///     "distinctProperties": int, "distinctAreas": int,
///     "priceMin": num, "priceMax": num, "priceRangeSpan": num
///   },
///   "furthestFunnelStep":    string,  // deepest LeadFunnelStep.name reached
///   "furthestFunnelIndex":   int,     // its ordinal (compare across sessions)
///   "reachedContactIntent":  bool,
///   "reachedContactSubmitted": bool,
///   "profile":               string,  // coarse label: "decisive"|"explorer"|"browsing"
///   "windowMs":              int      // wall-clock span this summary covers
/// }
/// ```
class BehaviorInsights {
  BehaviorInsights._();

  /// App-wide singleton — one rolling window shared across the session, matching
  /// the single [AppEvents] instance that carries the (final) sessionId.
  static final BehaviorInsights instance = BehaviorInsights._();

  /// How often the rolling summary is auto-flushed while the app is in use, so a
  /// long session still yields periodic snapshots (not just one at the end).
  static const Duration flushInterval = Duration(minutes: 3);

  Timer? _timer;
  DateTime _windowStart = DateTime.now();

  // ── Counters (reset each window) ───────────────────────────────────────────
  final Set<String> _screens = <String>{};
  int _backCount = 0;
  int _systemBackCount = 0;
  int _inAppBackCount = 0;

  int _dwellCount = 0;
  int _dwellSumMs = 0;
  int _dwellMinMs = 0;
  int _dwellMaxMs = 0;

  int _refineBroaden = 0;
  int _refineNarrow = 0;
  int _refineLateral = 0;

  int _searchAbandoned = 0;
  int _hesitationCount = 0;
  int _reversals = 0;

  final Set<String> _distinctProperties = <String>{};
  final Set<String> _distinctAreas = <String>{};
  double? _priceMin;
  double? _priceMax;

  int _furthestFunnelIndex = -1;

  bool get _hasData =>
      _screens.isNotEmpty ||
      _backCount > 0 ||
      _dwellCount > 0 ||
      _refineTotal > 0 ||
      _searchAbandoned > 0 ||
      _hesitationCount > 0 ||
      _distinctProperties.isNotEmpty ||
      _furthestFunnelIndex >= 0;

  int get _refineTotal => _refineBroaden + _refineNarrow + _refineLateral;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  /// Start the periodic auto-flush. Idempotent — safe to call on every launch.
  void start() {
    _timer ??= Timer.periodic(flushInterval, (_) => flush());
  }

  /// Stop the periodic flush and emit a final summary (call on session end).
  void stop() {
    _timer?.cancel();
    _timer = null;
    flush();
  }

  // ── Feed API (called by adopting screens / the NavigatorObserver) ───────────
  // Each mirrors a raw event so a caller notes-here and logs-there together.

  /// Record time spent on a screen (also counts it as a distinct screen).
  void noteScreenDwell({required String screen, required int dwellMs}) {
    try {
      if (screen.isNotEmpty) _screens.add(screen);
      final ms = math.max(0, dwellMs);
      _dwellCount++;
      _dwellSumMs += ms;
      if (_dwellCount == 1) {
        _dwellMinMs = ms;
        _dwellMaxMs = ms;
      } else {
        _dwellMinMs = math.min(_dwellMinMs, ms);
        _dwellMaxMs = math.max(_dwellMaxMs, ms);
      }
    } catch (_) {/* fail-soft */}
  }

  /// Record a back/pop navigation (feed alongside `logBackNavigation`).
  void noteBackNavigation({
    required String fromScreen,
    required int dwellMs,
    required bool isSystemBack,
  }) {
    try {
      _backCount++;
      if (isSystemBack) {
        _systemBackCount++;
      } else {
        _inAppBackCount++;
      }
      noteScreenDwell(screen: fromScreen, dwellMs: dwellMs);
    } catch (_) {/* fail-soft */}
  }

  /// Record a search refinement direction (feed alongside `logSearchRefined`).
  void noteSearchRefined(RefinementDirection direction) {
    try {
      switch (direction) {
        case RefinementDirection.broaden:
          _refineBroaden++;
        case RefinementDirection.narrow:
          _refineNarrow++;
        case RefinementDirection.lateral:
          _refineLateral++;
      }
    } catch (_) {/* fail-soft */}
  }

  /// Record a search abandoned without engaging a result.
  void noteSearchAbandoned() {
    try {
      _searchAbandoned++;
    } catch (_) {/* fail-soft */}
  }

  /// Record an indecision marker; [reversals] adds to the session's total.
  void noteHesitation({int reversals = 0}) {
    try {
      _hesitationCount++;
      _reversals += math.max(0, reversals);
    } catch (_) {/* fail-soft */}
  }

  /// Record a funnel step toward contact — keeps the furthest reached.
  void noteFunnelStep(LeadFunnelStep step) {
    try {
      if (step.index > _furthestFunnelIndex) _furthestFunnelIndex = step.index;
    } catch (_) {/* fail-soft */}
  }

  /// Record a property the user engaged, widening the exploration-breadth view.
  /// [area] and [price] are optional (area = coarse area label, not PII).
  void notePropertyViewed({
    required String propertyId,
    String? area,
    double? price,
  }) {
    try {
      if (propertyId.isNotEmpty) _distinctProperties.add(propertyId);
      if (area != null && area.isNotEmpty) _distinctAreas.add(area);
      if (price != null && price.isFinite && price > 0) {
        _priceMin = _priceMin == null ? price : math.min(_priceMin!, price);
        _priceMax = _priceMax == null ? price : math.max(_priceMax!, price);
      }
    } catch (_) {/* fail-soft */}
  }

  // ── Flush ────────────────────────────────────────────────────────────────

  /// Emit the current rolling summary as a `sessionInsights` event, then reset
  /// the window. No-op (no emit) when nothing was recorded, so idle periodic
  /// ticks and a redundant session-end flush stay silent.
  void flush() {
    try {
      if (!_hasData) {
        _windowStart = DateTime.now();
        return;
      }
      AppEvents.instance.service.logSessionInsights(_buildSummary());
    } catch (e) {
      if (kDebugMode) debugPrint('BehaviorInsights: flush failed: $e');
    } finally {
      _reset();
    }
  }

  Map<String, dynamic> _buildSummary() {
    final total = _refineTotal;
    final avgDwell = _dwellCount == 0 ? 0 : (_dwellSumMs ~/ _dwellCount);
    final priceMin = _priceMin ?? 0.0;
    final priceMax = _priceMax ?? 0.0;

    return <String, dynamic>{
      'screensVisited': _screens.length,
      'backCount': _backCount,
      'systemBackCount': _systemBackCount,
      'inAppBackCount': _inAppBackCount,
      if (_dwellCount > 0)
        'dwell': {
          'count': _dwellCount,
          'sumMs': _dwellSumMs,
          'minMs': _dwellMinMs,
          'maxMs': _dwellMaxMs,
          'avgMs': avgDwell,
        },
      if (total > 0)
        'refine': {
          'total': total,
          'broaden': _refineBroaden,
          'narrow': _refineNarrow,
          'lateral': _refineLateral,
          'net': _netDirection(),
        },
      'searchAbandonedCount': _searchAbandoned,
      'hesitationCount': _hesitationCount,
      'reversals': _reversals,
      'breadth': {
        'distinctProperties': _distinctProperties.length,
        'distinctAreas': _distinctAreas.length,
        'priceMin': priceMin,
        'priceMax': priceMax,
        'priceRangeSpan': math.max(0.0, priceMax - priceMin),
      },
      if (_furthestFunnelIndex >= 0) ...{
        'furthestFunnelStep':
            LeadFunnelStep.values[_furthestFunnelIndex].name,
        'furthestFunnelIndex': _furthestFunnelIndex,
        'reachedContactIntent':
            _furthestFunnelIndex >= LeadFunnelStep.contactIntent.index,
        'reachedContactSubmitted':
            _furthestFunnelIndex >= LeadFunnelStep.contactSubmitted.index,
      },
      'profile': _profileLabel(),
      'windowMs':
          math.max(0, DateTime.now().difference(_windowStart).inMilliseconds),
    };
  }

  String _netDirection() {
    if (_refineBroaden > _refineNarrow) return 'broaden';
    if (_refineNarrow > _refineBroaden) return 'narrow';
    return 'balanced';
  }

  /// Coarse, explainable user-type label derived from the window's breadth and
  /// refinement volume. Intentionally simple — the raw fields travel too, so a
  /// downstream model can re-derive its own segmentation.
  String _profileLabel() {
    final props = _distinctProperties.length;
    final refines = _refineTotal;
    if (props == 0 && refines == 0) return 'browsing';
    if (props <= 3 && refines <= 2) return 'decisive';
    if (props >= 8 || refines >= 5) return 'explorer';
    return 'considered';
  }

  void _reset() {
    _windowStart = DateTime.now();
    _screens.clear();
    _backCount = 0;
    _systemBackCount = 0;
    _inAppBackCount = 0;
    _dwellCount = 0;
    _dwellSumMs = 0;
    _dwellMinMs = 0;
    _dwellMaxMs = 0;
    _refineBroaden = 0;
    _refineNarrow = 0;
    _refineLateral = 0;
    _searchAbandoned = 0;
    _hesitationCount = 0;
    _reversals = 0;
    _distinctProperties.clear();
    _distinctAreas.clear();
    _priceMin = null;
    _priceMax = null;
    _furthestFunnelIndex = -1;
  }
}
