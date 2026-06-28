/// Per-user *derived* behavioral aggregate.
///
/// Where [event_service.dart] emits raw append-only behavioral rows (one per
/// swipe, dwell, media-open, …), [UserSignals] is the small, denormalized
/// summary the *matching algorithm* actually reads — the revealed-preference
/// columns folded out of that event stream.
///
/// The fold is a **pure deterministic reducer** ([UserSignals.update]): given a
/// current aggregate and one raw signal it returns the next aggregate, with no
/// I/O and no clock access (the caller passes `at`). That keeps it trivially
/// unit-testable and lets the same code run client-side (optimistic update) or
/// server-side (authoritative recompute) over the event table.
///
/// All numeric folds *blend* rather than overwrite (running averages / decayed
/// EMAs) so a single outlier event can't whipsaw the algorithm.
library;

import 'dart:convert';
import 'dart:math' as math;

/// A geographic centroid the user has revealed a preference for, with a weight
/// proportional to how many liked listings collapsed into it.
class AreaCentroid {
  const AreaCentroid({
    required this.lat,
    required this.lng,
    this.weight = 1.0,
  });

  final double lat;
  final double lng;

  /// Number of liked points (fractional after blending) backing this centroid.
  final double weight;

  AreaCentroid copyWith({double? lat, double? lng, double? weight}) =>
      AreaCentroid(
        lat: lat ?? this.lat,
        lng: lng ?? this.lng,
        weight: weight ?? this.weight,
      );

  Map<String, dynamic> toJson() => {'lat': lat, 'lng': lng, 'weight': weight};

  factory AreaCentroid.fromJson(Map<String, dynamic> json) => AreaCentroid(
        lat: _toD(json['lat']),
        lng: _toD(json['lng']),
        weight: _toD(json['weight'], fallback: 1.0),
      );
}

class UserSignals {
  const UserSignals({
    this.revealedBudgetTolerance = 1.0,
    this.tagAffinity = const {},
    this.preferredAreas = const [],
    this.avgDwellMs = 0.0,
    this.decisiveness = 0.5,
    this.mediaEngagementScore = 0.0,
    this.activeHours = const [],
    this.sessionCount = 0,
    this.lastActiveAt,
  });

  /// Price ceiling the user actually likes at, relative to their stated budget.
  /// 1.0 = sticks to budget; 1.15 = will like listings up to 15% over budget.
  final double revealedBudgetTolerance;

  /// Affinity per tag/feature key, typically in [-1, 1] (liked raises, skipped
  /// lowers). The algorithm uses this to reweight tag matches per user.
  final Map<String, double> tagAffinity;

  /// Revealed area preferences as weighted centroids (kept deliberately simple:
  /// nearest-centroid merge, no full k-means).
  final List<AreaCentroid> preferredAreas;

  /// Running average dwell time (ms) on cards before acting.
  final double avgDwellMs;

  /// 0..1 — how quickly/cleanly the user decides (high = short dwell, few undos).
  final double decisiveness;

  /// 0..1 — how much the user engages with rich media (360/3D/video/photos).
  final double mediaEngagementScore;

  /// Hours-of-day (0..23) in which the user is active, ordered by first-seen.
  final List<int> activeHours;

  final int sessionCount;
  final DateTime? lastActiveAt;

  // ── Tuning constants ──────────────────────────────────────────────────────
  static const double _dwellAlpha = 0.2; // EMA weight for new dwell samples
  static const double _toleranceAlpha = 0.25; // pull toward a higher tolerance
  static const double _affinityStep = 0.15; // per-event affinity nudge
  static const double _mediaAlpha = 0.2;
  static const double _areaMergeKm = 2.0; // merge liked points within ~2 km

  UserSignals copyWith({
    double? revealedBudgetTolerance,
    Map<String, double>? tagAffinity,
    List<AreaCentroid>? preferredAreas,
    double? avgDwellMs,
    double? decisiveness,
    double? mediaEngagementScore,
    List<int>? activeHours,
    int? sessionCount,
    DateTime? lastActiveAt,
  }) =>
      UserSignals(
        revealedBudgetTolerance:
            revealedBudgetTolerance ?? this.revealedBudgetTolerance,
        tagAffinity: tagAffinity ?? this.tagAffinity,
        preferredAreas: preferredAreas ?? this.preferredAreas,
        avgDwellMs: avgDwellMs ?? this.avgDwellMs,
        decisiveness: decisiveness ?? this.decisiveness,
        mediaEngagementScore: mediaEngagementScore ?? this.mediaEngagementScore,
        activeHours: activeHours ?? this.activeHours,
        sessionCount: sessionCount ?? this.sessionCount,
        lastActiveAt: lastActiveAt ?? this.lastActiveAt,
      );

  // ── JSON round-trip ───────────────────────────────────────────────────────

  Map<String, dynamic> toJson() => {
        'revealedBudgetTolerance': revealedBudgetTolerance,
        'tagAffinity': tagAffinity,
        'preferredAreas': preferredAreas.map((a) => a.toJson()).toList(),
        'avgDwellMs': avgDwellMs,
        'decisiveness': decisiveness,
        'mediaEngagementScore': mediaEngagementScore,
        'activeHours': activeHours,
        'sessionCount': sessionCount,
        'lastActiveAt': lastActiveAt?.toUtc().toIso8601String(),
      };

  factory UserSignals.fromJson(Map<String, dynamic> json) => UserSignals(
        revealedBudgetTolerance:
            _toD(json['revealedBudgetTolerance'], fallback: 1.0),
        tagAffinity: _toDoubleMap(json['tagAffinity']),
        preferredAreas: (json['preferredAreas'] as List?)
                ?.whereType<Map>()
                .map((m) => AreaCentroid.fromJson(Map<String, dynamic>.from(m)))
                .toList() ??
            const [],
        avgDwellMs: _toD(json['avgDwellMs']),
        decisiveness: _toD(json['decisiveness'], fallback: 0.5),
        mediaEngagementScore: _toD(json['mediaEngagementScore']),
        activeHours: (json['activeHours'] as List?)
                ?.map((e) => _toI(e))
                .toList() ??
            const [],
        sessionCount: _toI(json['sessionCount']),
        lastActiveAt: _parseDate(json['lastActiveAt']),
      );

  String encode() => jsonEncode(toJson());

  factory UserSignals.decode(String source) =>
      UserSignals.fromJson(jsonDecode(source) as Map<String, dynamic>);

  // ── Pure deterministic reducer ────────────────────────────────────────────
  //
  // Folds ONE raw behavioral signal into the aggregate and returns the next
  // value. No I/O, no DateTime.now() — the caller supplies [at] (the event's
  // createdAt). [event] mirrors the `metadata` payload emitted by EventService,
  // discriminated by [type] (a UserEventType.name string, e.g. 'swipeOutcome').
  static UserSignals update(
    UserSignals current, {
    required String type,
    Map<String, dynamic> event = const {},
    DateTime? at,
  }) {
    var next = current;

    switch (type) {
      case 'swipeOutcome':
        final dir = (event['direction'] as String?) ?? 'skip';
        final ratio = _toD(event['priceToBudgetRatio'], fallback: 1.0);
        final liked = dir == 'like' || dir == 'superlike';
        if (liked && ratio > next.revealedBudgetTolerance) {
          // Pull tolerance up toward the revealed over-budget ratio (never down
          // on a like — a cheaper like shouldn't shrink known tolerance).
          final blended = next.revealedBudgetTolerance +
              _toleranceAlpha * (ratio - next.revealedBudgetTolerance);
          next = next.copyWith(revealedBudgetTolerance: blended);
        }
        // A skip is a more deliberate act than a like → small decisiveness bump.
        next = next.copyWith(
          decisiveness:
              _blend(next.decisiveness, liked ? 0.5 : 0.7, 0.05).clamp(0.0, 1.0),
        );
        break;

      case 'dealBreakerApplied':
      case 'tagLiked':
      case 'tagSkipped':
        // Generic tag-affinity nudge. `dealBreakerApplied` lowers affinity for
        // the violating tag; an explicit liked/skipped tag moves it accordingly.
        final tag = event['tag'] as String?;
        if (tag != null && tag.isNotEmpty) {
          final lowers = type == 'dealBreakerApplied' || type == 'tagSkipped';
          final cur = next.tagAffinity[tag] ?? 0.0;
          final delta = lowers ? -_affinityStep : _affinityStep;
          final updated = Map<String, double>.from(next.tagAffinity)
            ..[tag] = (cur + delta).clamp(-1.0, 1.0);
          next = next.copyWith(tagAffinity: updated);
        }
        break;

      case 'likedLocation':
        next = next.copyWith(
          preferredAreas: _mergeArea(
            next.preferredAreas,
            _toD(event['lat']),
            _toD(event['lng']),
          ),
        );
        break;

      case 'cardDwell':
        final dwell = _toD(event['dwellMs']);
        final avg = next.avgDwellMs == 0.0
            ? dwell
            : _blend(next.avgDwellMs, dwell, _dwellAlpha);
        next = next.copyWith(avgDwellMs: avg);
        break;

      case 'mediaEngagement':
        // Map this event onto a 0..1 score then EMA-blend it in.
        var s = 0.0;
        if (event['opened360'] == true) s += 0.3;
        if (event['opened3d'] == true) s += 0.3;
        if (event['openedVideo'] == true) s += 0.2;
        final photos = _toI(event['photosViewed']);
        s += math.min(0.2, photos * 0.04); // up to +0.2 for 5+ photos
        next = next.copyWith(
          mediaEngagementScore:
              _blend(next.mediaEngagementScore, s.clamp(0.0, 1.0), _mediaAlpha),
        );
        break;

      case 'priceSensitivity':
        final r = _toD(event['maxOverBudgetRatioLiked'], fallback: 1.0);
        if (r > next.revealedBudgetTolerance) {
          next = next.copyWith(revealedBudgetTolerance: r);
        }
        break;

      case 'undoSwipe':
        // Hesitation → lowers decisiveness.
        next = next.copyWith(
          decisiveness: _blend(next.decisiveness, 0.0, 0.1).clamp(0.0, 1.0),
        );
        break;

      case 'sessionStarted':
      case 'sessionContext':
        next = next.copyWith(sessionCount: next.sessionCount + 1);
        break;
    }

    // Activity bookkeeping applies to every folded signal that carries a time.
    if (at != null) {
      final hour = at.toLocal().hour;
      final hours = next.activeHours.contains(hour)
          ? next.activeHours
          : (List<int>.from(next.activeHours)..add(hour));
      final lastActive =
          (next.lastActiveAt == null || at.isAfter(next.lastActiveAt!))
              ? at
              : next.lastActiveAt;
      next = next.copyWith(activeHours: hours, lastActiveAt: lastActive);
    }

    return next;
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static double _blend(double current, double sample, double alpha) =>
      current + alpha * (sample - current);

  /// Nearest-centroid merge: if a liked point falls within [_areaMergeKm] of an
  /// existing centroid, weight-average them; otherwise append a new centroid.
  static List<AreaCentroid> _mergeArea(
    List<AreaCentroid> areas,
    double lat,
    double lng,
  ) {
    var bestIdx = -1;
    var bestKm = double.infinity;
    for (var i = 0; i < areas.length; i++) {
      final d = _haversineKm(areas[i].lat, areas[i].lng, lat, lng);
      if (d < bestKm) {
        bestKm = d;
        bestIdx = i;
      }
    }
    if (bestIdx >= 0 && bestKm <= _areaMergeKm) {
      final c = areas[bestIdx];
      final w = c.weight + 1.0;
      final merged = c.copyWith(
        lat: (c.lat * c.weight + lat) / w,
        lng: (c.lng * c.weight + lng) / w,
        weight: w,
      );
      return [
        for (var i = 0; i < areas.length; i++)
          if (i == bestIdx) merged else areas[i],
      ];
    }
    return [...areas, AreaCentroid(lat: lat, lng: lng)];
  }

  static double _haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _rad(lat2 - lat1);
    final dLng = _rad(lng2 - lng1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double deg) => deg * math.pi / 180.0;
}

// ── Lenient JSON coercion ─────────────────────────────────────────────────────

double _toD(Object? v, {double fallback = 0.0}) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? fallback;
  return fallback;
}

int _toI(Object? v, {int fallback = 0}) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

Map<String, double> _toDoubleMap(Object? v) {
  if (v is Map) {
    return v.map((k, val) => MapEntry(k.toString(), _toD(val)));
  }
  return {};
}

DateTime? _parseDate(Object? v) {
  if (v is String && v.isNotEmpty) return DateTime.tryParse(v);
  return null;
}
