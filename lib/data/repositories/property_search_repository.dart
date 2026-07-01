import 'dart:math' as math;

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/circuit_breaker.dart';
import 'package:dating_app/core/network/retry_policy.dart';
import 'package:dating_app/core/services/appwrite_client.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter/foundation.dart';

// Criteria collected by the AI search assistant (3-turn conversation).
class PropertySearchCriteria {
  const PropertySearchCriteria({
    this.city,
    this.minPrice,
    this.maxPrice,
    this.minRooms,
    this.amenityKeys = const {},
    this.vibe,
  });

  final String? city;
  final int? minPrice;
  final int? maxPrice;
  final double? minRooms;
  // PropertyFeatureSet keys, e.g. {'feat_parking','feat_balcony'}.
  final Set<String> amenityKeys;
  // Soft preference, not used as a hard filter for now.
  final String? vibe;
}

// Reads real listings from the AWS-backed properties table and matches them
// against the assistant's criteria.
//
// ponytail: city is filtered server-side (plain string equality — the pattern
// the app already relies on); price/rooms/amenities/active are filtered
// client-side over the capped page. Push these server-side once the AWS query
// layer's numeric/boolean equality semantics are confirmed.
class PropertySearchRepository {
  PropertySearchRepository({String? tableId})
      : _tableId = tableId ?? AppConfig.appwritePropertiesTableId;

  final String _tableId;
  final _breaker = CircuitBreaker(name: 'property-search');

  bool get isConfigured => AppConfig.canUseProperties && _tableId.isNotEmpty;

  Future<List<RentalProperty>> search(
    PropertySearchCriteria c, {
    int limit = 100,
  }) async {
    if (!isConfigured || _breaker.isOpen) return const [];

    final queries = <String>[
      if (c.city != null && c.city!.trim().isNotEmpty)
        Query.equal('city', c.city!.trim()),
      Query.limit(limit),
    ];

    try {
      final result = await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.listRows(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            queries: queries,
          ),
        ),
      );

      // Keep each listing paired with its raw backend map so the ranker can read
      // server-supplied ranking signals (popularity / freshness) defensively.
      final parsed = <_Candidate>[];
      for (final row in result.rows) {
        final p = _safeParse(row.data);
        if (p != null) parsed.add(_Candidate(p, row.data));
      }

      return _filterAndRank(parsed, c);
    } on CircuitOpenException {
      return const [];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('PropertySearchRepository.search error: $e');
      }
      return const [];
    }
  }

  RentalProperty? _safeParse(Map<String, dynamic> data) {
    try {
      return RentalProperty.fromJson(data);
    } catch (_) {
      return null;
    }
  }

  List<RentalProperty> _filterAndRank(
    List<_Candidate> items,
    PropertySearchCriteria c,
  ) {
    final wantCity = c.city?.trim();
    final matched = items.where((cand) {
      final p = cand.property;
      if (!p.isActive) return false;
      // The backend's GSI filters by status, not city, so the city Query is a
      // no-op server-side — enforce it here or we'd return wrong-city listings.
      if (wantCity != null && wantCity.isNotEmpty && !_cityMatches(p.city, wantCity)) {
        return false;
      }
      if (c.minPrice != null && p.price < c.minPrice!) return false;
      if (c.maxPrice != null && p.price > c.maxPrice!) return false;
      if (c.minRooms != null && p.rooms < c.minRooms!) return false;
      for (final key in c.amenityKeys) {
        if (!p.featureFlags.isEnabled(key)) return false;
      }
      return true;
    }).toList();

    // Score once per candidate (the transparent linear scorer), cache the
    // feature vectors, then sort high→low. Caching keeps the sort cheap and
    // lets us log exactly what the ranker saw.
    final scored = <_Scored>[];
    final maxPop = _maxPopularity(matched);
    for (final cand in matched) {
      final fv = _features(cand, c, maxPop);
      scored.add(_Scored(cand.property, fv, _scoreFromFeatures(fv)));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));

    final ranked = [for (final s in scored) s.property];
    // Fire-and-forget per-impression feature log (the phase-2 LightGBM training
    // set). Fail-soft — never blocks or breaks the UI.
    _logImpressions(scored, c);
    return ranked;
  }

  // Space/case-insensitive city match, tolerant of partials ("תל אביב" vs
  // "תל אביב יפו") since user-typed and stored city strings vary.
  bool _cityMatches(String propertyCity, String wanted) {
    final a = propertyCity.trim();
    final b = wanted.trim();
    if (a.isEmpty) return false;
    return a == b || a.contains(b) || b.contains(a);
  }

  // ── Transparent linear ranker ───────────────────────────────────────────────
  // score = Σ wᵢ·featureᵢ over the synthesis features:
  //   tag_overlap · price_fit · distance_decay · recency · popularity_prior · explore
  // Every term is normalised to [0,1] and the weights are explicit + auditable,
  // so any rank is explainable and the cost is one pass over the page.
  static const _wTagOverlap = 0.30;
  static const _wPriceFit = 0.25;
  static const _wDistanceDecay = 0.10;
  static const _wRecency = 0.12;
  static const _wPopularity = 0.15;
  static const _wExplore = 0.08;

  /// Highest popularity_prior in the page — normalises the popularity term so a
  /// single viral listing doesn't swamp the budget/tag signals.
  double _maxPopularity(List<_Candidate> items) {
    var maxP = 0.0;
    for (final c in items) {
      final p = _rawPopularity(c);
      if (p > maxP) maxP = p;
    }
    return maxP;
  }

  /// Raw (un-normalised) popularity from server signals if present, else the
  /// embedded market signals. Read defensively — backend may add a top-level
  /// `popularity` field later.
  /// Reads a ranking signal the backend NESTS under `rankSignals` (with a
  /// top-level fallback) — the router emits {rankSignals:{popularity,freshness,
  /// completeness,priceFit,...}}, so reading top-level only would ignore them.
  double? _serverSignal(Map<String, dynamic> raw, List<String> keys) {
    final rs = raw['rankSignals'];
    if (rs is Map) {
      final v = _numField(Map<String, dynamic>.from(rs), keys);
      if (v != null) return v;
    }
    return _numField(raw, keys);
  }

  double _rawPopularity(_Candidate c) {
    final server = _serverSignal(c.raw, const ['popularity', 'popularityScore']);
    if (server != null) return math.max(0, server);
    final m = c.property.marketSignals;
    // A cheap engagement proxy: weighted likes/saves/contacts over views.
    return (m.likes * 2 + m.saves * 3 + m.contactRequests * 4 + m.views)
        .toDouble();
  }

  /// Builds the normalised [0,1] feature vector for one listing.
  Map<String, double> _features(
    _Candidate c,
    PropertySearchCriteria crit,
    double maxPop,
  ) {
    final p = c.property;

    // tag_overlap: fraction of the requested amenities the listing satisfies
    // (matched listings already satisfy all hard amenities, so this rewards
    // verified + photographed completeness when no amenities were asked for).
    double tagOverlap;
    if (crit.amenityKeys.isEmpty) {
      tagOverlap = (p.isVerifiedListing ? 0.6 : 0.0) +
          (p.imageUrl.isNotEmpty ? 0.4 : 0.0);
    } else {
      final hit =
          crit.amenityKeys.where((k) => p.featureFlags.isEnabled(k)).length;
      tagOverlap = hit / crit.amenityKeys.length;
    }

    // price_fit: 1 at the budget midpoint, decaying linearly to the edges.
    double priceFit = 0.5;
    if (crit.minPrice != null &&
        crit.maxPrice != null &&
        crit.maxPrice! > crit.minPrice!) {
      final mid = (crit.minPrice! + crit.maxPrice!) / 2.0;
      final span = (crit.maxPrice! - crit.minPrice!).toDouble();
      priceFit = 1.0 - ((p.price - mid).abs() / span).clamp(0.0, 1.0);
    }

    // distance_decay: no per-search origin here, so use the server `distanceKm`
    // if present (exponential decay over ~5 km); neutral 0.5 otherwise.
    double distanceDecay = 0.5;
    final dist = _numField(c.raw, const ['distanceKm', 'distance_km']);
    if (dist != null) distanceDecay = math.exp(-dist.abs() / 5.0);

    // recency / freshness: prefer the server `freshness` ([0,1]) when present,
    // else derive from createdAt with a 30-day half-life.
    double recency;
    final freshness = _serverSignal(c.raw, const ['freshness', 'freshnessScore']);
    if (freshness != null) {
      recency = freshness.clamp(0.0, 1.0).toDouble();
    } else if (p.createdAt != null) {
      final ageDays = DateTime.now().difference(p.createdAt!).inHours / 24.0;
      recency = math.exp(-math.max(0, ageDays) / 30.0);
    } else {
      recency = p.isNewListing ? 1.0 : 0.4;
    }

    // popularity_prior: page-normalised engagement.
    final popularity = maxPop > 0 ? (_rawPopularity(c) / maxPop) : 0.0;

    // explore: UCB/ε-greedy bonus for under-impressed listings — the fewer
    // views a listing has had, the bigger the exploration nudge, so cold
    // inventory still surfaces. log-scaled, capped at 1.
    final views = p.marketSignals.views;
    final explore = (1.0 / math.sqrt(1 + views)).clamp(0.0, 1.0);

    return {
      'tag_overlap': tagOverlap.clamp(0.0, 1.0).toDouble(),
      'price_fit': priceFit.clamp(0.0, 1.0).toDouble(),
      'distance_decay': distanceDecay.clamp(0.0, 1.0).toDouble(),
      'recency': recency.clamp(0.0, 1.0).toDouble(),
      'popularity_prior': popularity.clamp(0.0, 1.0).toDouble(),
      'explore': explore.toDouble(),
    };
  }

  double _scoreFromFeatures(Map<String, double> f) {
    return _wTagOverlap * f['tag_overlap']! +
        _wPriceFit * f['price_fit']! +
        _wDistanceDecay * f['distance_decay']! +
        _wRecency * f['recency']! +
        _wPopularity * f['popularity_prior']! +
        _wExplore * f['explore']!;
  }

  /// Reads the first numeric value among [keys] from a raw backend map.
  double? _numField(Map<String, dynamic> raw, List<String> keys) {
    for (final k in keys) {
      final v = raw[k];
      if (v is num) return v.toDouble();
      if (v is String) {
        final parsed = num.tryParse(v);
        if (parsed != null) return parsed.toDouble();
      }
    }
    return null;
  }

  /// Per-impression feature-vector log → `/search/log`. The training set for the
  /// phase-2 LightGBM lambdarank upgrade. Fully fail-soft.
  void _logImpressions(List<_Scored> scored, PropertySearchCriteria c) {
    if (scored.isEmpty) return;
    if (!AwsApiClient.instance.isConfigured) return;
    try {
      final impressions = [
        for (var i = 0; i < scored.length; i++)
          {
            'propertyId': scored[i].property.id,
            'rank': i,
            'score': scored[i].score,
            'features': scored[i].features,
          },
      ];
      final body = <String, dynamic>{
        'criteria': {
          'city': c.city,
          'minPrice': c.minPrice,
          'maxPrice': c.maxPrice,
          'minRooms': c.minRooms,
          'amenities': c.amenityKeys.toList(),
          'vibe': c.vibe,
        },
        'weights': const {
          'tag_overlap': _wTagOverlap,
          'price_fit': _wPriceFit,
          'distance_decay': _wDistanceDecay,
          'recency': _wRecency,
          'popularity_prior': _wPopularity,
          'explore': _wExplore,
        },
        'ts': DateTime.now().toUtc().toIso8601String(),
        'impressions': impressions,
      };
      // Don't await — never block the result list on telemetry.
      AwsApiClient.instance.post('/search/log', body).catchError(
        (_) => <String, dynamic>{},
      );
    } catch (_) {/* fail-soft */}
  }
}

/// A parsed listing paired with its raw backend map (for defensive server-signal
/// reads during ranking).
class _Candidate {
  const _Candidate(this.property, this.raw);
  final RentalProperty property;
  final Map<String, dynamic> raw;
}

/// A scored listing carrying the feature vector that produced its score, so the
/// rank is both explainable and loggable.
class _Scored {
  const _Scored(this.property, this.features, this.score);
  final RentalProperty property;
  final Map<String, double> features;
  final double score;
}
