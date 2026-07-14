import 'dart:math' as math;

import 'package:dating_app/core/config/app_config.dart';
import 'package:dating_app/core/network/circuit_breaker.dart';
import 'package:dating_app/core/search/advanced_matcher.dart';
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
    this.maxRooms,
    this.amenityKeys = const {},
    this.vibe,
    this.queryText,
    this.cohortSignals = const {},
  });

  final String? city;
  final int? minPrice;
  final int? maxPrice;
  final double? minRooms;
  final double? maxRooms;
  // PropertyFeatureSet keys, e.g. {'feat_parking','feat_balcony'}.
  final Set<String> amenityKeys;
  // Soft preference (chip or NL): 'שקט'/'תוסס'/'משפחתי'/'סטודנטיאלי'.
  // Not a hard filter — feeds the vibe_fit ranking term.
  final String? vibe;
  // Raw NL query text, when available. Enables the semantic kNN candidate
  // source; when null, retrieval is the city query alone (unchanged behavior).
  final String? queryText;
  // Persona/cohort signals (household/religiousStream/isOleh/carFree/wfh/…) sent
  // verbatim to the backend `resolveCohort` so the 14-cohort taxonomy + community_fit
  // actually engage. Produced by SmartSearch.cohortSignals(). Empty → old behavior.
  final Map<String, String> cohortSignals;
}

/// Maps a requested vibe to a target neighborhood-vibrancy in [-1,1] (same scale
/// as AdvancedMatcher.neighborhoodVibrancy). Returns null for empty/unknown vibe
/// so the scorer stays neutral. Substring match tolerates chips and NL phrasing.
// ponytail: reuses the existing hardcoded vibrancy map — no embeddings yet.
// Upgrade path (doc part ג'): replace with cosine(userEmbedding, listingEmbedding).
double? vibeTargetVibrancy(String? vibe) {
  final v = vibe?.trim();
  if (v == null || v.isEmpty) return null;
  if (v.contains('שקט')) return -0.8; // quiet
  if (v.contains('תוסס')) return 0.9; // vibrant
  if (v.contains('משפח')) return -0.3; // family → residential-leaning
  if (v.contains('סטודנט')) return 0.5; // student → central, lively
  return null;
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
    // Route the cohort signal to the backend personalization engine: the current
    // vibe overrides the stored profile, so the main-feed scorer (attachRankSignals
    // → resolveCohort) ranks with the full 14-cohort taxonomy + community_fit and
    // returns a per-listing `rankScore` we order by below.
    final cohortParams = <String, String>{
      ...c.cohortSignals,
      if (c.vibe != null && c.vibe!.trim().isNotEmpty) 'vibe': c.vibe!.trim(),
    };

    try {
      // Kick off the semantic kNN candidate source in parallel with the city
      // query (fail-soft — returns [] on any problem, incl. when the backend
      // has embeddings disabled), then merge the two candidate sets.
      final knnFuture = _knnCandidates(c);
      final result = await _breaker.call(
        () => RetryPolicy.transient.execute(
          () => tables.listRows(
            databaseId: appwriteDatabaseId,
            tableId: _tableId,
            queries: queries,
            params: cohortParams,
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

      final merged = _mergeCandidates(parsed, await knnFuture);
      return _filterAndRank(merged, c);
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

  /// The text used for semantic kNN: caller-provided raw NL if present,
  /// otherwise a query synthesized from the active chips/criteria. Returns null
  /// when there's nothing meaningful to search on (so kNN simply doesn't fire).
  static String? effectiveQueryText(PropertySearchCriteria c) {
    final raw = c.queryText?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    final bits = <String>[
      if (c.vibe != null && c.vibe!.trim().isNotEmpty) c.vibe!.trim(),
      if (c.minRooms != null) '${_roomsLabel(c.minRooms!)} חדרים',
      if (c.city != null && c.city!.trim().isNotEmpty) 'ב${c.city!.trim()}',
      if (c.maxPrice != null) 'עד ${c.maxPrice} ש״ח',
    ];
    if (bits.isEmpty) return null;
    return 'דירה ${bits.join(' ')}';
  }

  static String _roomsLabel(double r) =>
      r % 1 == 0 ? r.toStringAsFixed(0) : r.toStringAsFixed(1);

  /// Semantic kNN candidate source. Calls the backend /search/knn with the raw
  /// query text; the backend embeds it and queries S3 Vectors. Fully fail-soft:
  /// returns [] when there's no query text, the API is unconfigured, or the
  /// backend has embeddings disabled (it replies {results: []}).
  Future<List<_Candidate>> _knnCandidates(PropertySearchCriteria c) async {
    final text = effectiveQueryText(c);
    if (text == null || text.isEmpty) return const [];
    if (!AwsApiClient.instance.isConfigured) return const [];
    try {
      final res = await AwsApiClient.instance.post('/search/knn', {
        'text': text,
        if (c.city != null && c.city!.trim().isNotEmpty) 'city': c.city!.trim(),
        'topK': 50,
      });
      final list = res['results'];
      if (list is! List) return const [];
      final out = <_Candidate>[];
      for (final row in list) {
        if (row is! Map) continue;
        final map = Map<String, dynamic>.from(row);
        final p = _safeParse(map);
        if (p != null) out.add(_Candidate(p, map)); // raw carries `semanticSim`
      }
      return out;
    } catch (_) {
      return const []; // city query still stands
    }
  }

  /// Union of the city-query and kNN candidates, deduped by id. For listings in
  /// both, keep the city-query candidate (its raw has the server rank signals)
  /// but graft on the kNN `semanticSim` so the scorer sees it.
  List<_Candidate> _mergeCandidates(List<_Candidate> base, List<_Candidate> knn) {
    final byId = <String, _Candidate>{for (final c in base) c.property.id: c};
    for (final c in knn) {
      final existing = byId[c.property.id];
      if (existing == null) {
        byId[c.property.id] = c;
      } else {
        final sim = c.raw['semanticSim'];
        // Rebuild with a merged raw (don't mutate — the backend map may be
        // unmodifiable): keep the server rank signals, add semanticSim.
        if (sim != null) {
          byId[c.property.id] = _Candidate(
            existing.property,
            {...existing.raw, 'semanticSim': sim},
          );
        }
      }
    }
    return byId.values.toList();
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
      if (c.maxRooms != null && p.rooms > c.maxRooms!) return false;
      for (final key in c.amenityKeys) {
        if (!p.featureFlags.isEnabled(key)) return false;
      }
      return true;
    }).toList();

    final maxPop = _maxPopularity(matched);
    // Client-side cohort (from vibe) drives the transparent client scorer, kept
    // as the training-log features + the ranking FALLBACK.
    final cohort = cohortFromVibe(c.vibe);
    final weights = weightsFor(cohort);
    final fvOf = <String, Map<String, double>>{};
    final clientScoreOf = <String, double>{};
    for (final cand in matched) {
      final fv = _features(cand, c, maxPop, cohort);
      fvOf[cand.property.id] = fv;
      clientScoreOf[cand.property.id] = _scoreFromFeatures(fv, weights);
    }

    // ROUTE THROUGH THE BACKEND ENGINE: prefer the per-listing `rankScore` the
    // main-feed scorer attached (full 14-cohort taxonomy + point-level
    // community_fit, from the vibe we passed + the user's profile). Fall back to
    // the client score for any candidate the backend didn't rank (e.g. kNN-only).
    double sortKey(_Candidate cand) =>
        _numField(cand.raw, const ['rankScore']) ?? clientScoreOf[cand.property.id]!;
    matched.sort((a, b) => sortKey(b).compareTo(sortKey(a)));

    final ranked = [for (final cand in matched) cand.property];
    final scored = [
      for (final cand in matched)
        _Scored(cand.property, fvOf[cand.property.id]!, clientScoreOf[cand.property.id]!),
    ];
    // Fire-and-forget per-impression feature log (the phase-2 LightGBM training
    // set), now in the backend-ranked order. Fail-soft — never blocks the UI.
    _logImpressions(scored, c, weights, cohort);
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
  // ponytail: score is only a sort key, so this extra term needn't renormalise
  // the others — when no vibe is requested vibe_fit is a constant 0.5 and the
  // sort order is unchanged; it only differentiates once a vibe is set.
  static const _wVibeFit = 0.10;
  // Semantic similarity from the embedding kNN (step 3). Neutral 0.5 for
  // candidates without an embedding signal (e.g. city-query-only hits, or when
  // the backend has embeddings off) → constant offset, no sort effect until a
  // real semanticSim is present.
  static const _wSemanticSim = 0.20;
  // Personalized neighborhood-quality fit: matches the listing's public-data
  // area sub-scores (safety/walkability/schools/transit/green) to the cohort's
  // priorities. Neutral 0.5 when the listing has no enriched neighborhood score.
  static const _wNeighborhoodFit = 0.15;

  // Global default weight-set. Per-cohort variants override a few of these.
  static const Map<String, double> _baseWeights = {
    'tag_overlap': _wTagOverlap,
    'price_fit': _wPriceFit,
    'distance_decay': _wDistanceDecay,
    'recency': _wRecency,
    'popularity_prior': _wPopularity,
    'explore': _wExplore,
    'vibe_fit': _wVibeFit,
    'semantic_sim': _wSemanticSim,
    'neighborhood_fit': _wNeighborhoodFit,
  };

  // Per-cohort neighborhood-quality weights over the public-data sub-scores
  // {safety, walkability, schools, transit, green} (from neighborhood.mjs —
  // data.gov.il schools, OSM POIs/transit/green). THIS is where public area
  // data becomes personal: families weight schools+safety, students weight
  // transit+walkability. Unknown cohort → generic quality-of-life (matches the
  // composite weights in neighborhood.mjs).
  static const Map<String, double> _baseNeighborhoodWeights = {
    'safety': 0.30, 'walkability': 0.25, 'schools': 0.20, 'transit': 0.15, 'green': 0.10,
  };
  static const Map<String, Map<String, double>> _cohortNeighborhoodWeights = {
    'family':  {'safety': 0.30, 'walkability': 0.10, 'schools': 0.35, 'transit': 0.05, 'green': 0.20},
    'student': {'safety': 0.10, 'walkability': 0.35, 'schools': 0.00, 'transit': 0.45, 'green': 0.10},
  };

  /// Neighborhood-dimension weights for a cohort (defaults to generic QoL).
  static Map<String, double> neighborhoodWeightsFor(String? cohort) =>
      (cohort != null ? _cohortNeighborhoodWeights[cohort] : null) ??
      _baseNeighborhoodWeights;

  /// neighborhood_fit: weighted average of the listing's public-data sub-scores
  /// (0..100 → [0,1]) under the cohort's neighborhood weights, renormalized over
  /// whichever dimensions are actually present. Neutral 0.5 when there's no
  /// enriched neighborhood score at all.
  static double neighborhoodFit(Map<String, dynamic> raw, String? cohort) {
    final ns = raw['neighborhoodScore'];
    final sub = ns is Map ? ns['sub'] : null;
    if (sub is! Map) return 0.5;
    final weights = neighborhoodWeightsFor(cohort);
    double wsum = 0;
    double acc = 0;
    weights.forEach((k, w) {
      final v = sub[k];
      final d = v is num ? v.toDouble() : (v is String ? double.tryParse(v) : null);
      if (d != null && d > 0) {
        acc += w * (d / 100.0).clamp(0.0, 1.0);
        wsum += w;
      }
    });
    if (wsum == 0) return 0.5;
    return (acc / wsum).clamp(0.0, 1.0);
  }

  // Per-cohort weight overrides (מהיר tier: dynamic weights without ML). Cohort
  // is inferred from the requested vibe — the only cohort signal available at
  // search time. Directional starting points, not tuned.
  // ponytail: heuristic weights; upgrade path is LightGBM lambdarank on the log.
  static const Map<String, Map<String, double>> _cohortWeights = {
    // Students: budget-driven, amenities matter less.
    'student': {'tag_overlap': 0.20, 'price_fit': 0.35},
    // Families: amenities/space matter, less exploration of cold inventory.
    'family': {'tag_overlap': 0.38, 'price_fit': 0.20, 'explore': 0.05},
  };

  /// Cohort from the requested vibe chip. Null → global weights.
  static String? cohortFromVibe(String? vibe) {
    final v = vibe?.trim();
    if (v == null || v.isEmpty) return null;
    if (v.contains('סטודנט')) return 'student';
    if (v.contains('משפח')) return 'family';
    return null;
  }

  /// Effective weights for a cohort: base with the cohort's overrides applied.
  static Map<String, double> weightsFor(String? cohort) {
    final overrides = cohort == null ? null : _cohortWeights[cohort];
    if (overrides == null) return _baseWeights;
    return {..._baseWeights, ...overrides};
  }

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
    String? cohort,
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

    // vibe_fit: closeness of the listing's neighborhood vibrancy to the vibe the
    // user asked for. Neutral 0.5 when no (or unknown) vibe was requested.
    final target = vibeTargetVibrancy(crit.vibe);
    double vibeFit = 0.5;
    if (target != null) {
      final propVibrancy =
          AdvancedMatcher.neighborhoodVibrancy(p.neighborhood, p.city);
      vibeFit = 1.0 - ((propVibrancy - target).abs() / 2.0);
    }

    // semantic_sim: the embedding kNN similarity the backend grafted onto this
    // candidate's raw map (top-level `semanticSim`). Neutral 0.5 when absent.
    final sem = _serverSignal(c.raw, const ['semanticSim', 'semantic_sim']);
    final semanticSim = (sem ?? 0.5).clamp(0.0, 1.0).toDouble();

    // neighborhood_fit: public-data area sub-scores matched to the cohort's
    // neighborhood priorities (families→schools/safety, students→transit).
    final neighborhoodFitVal = neighborhoodFit(c.raw, cohort);

    return {
      'tag_overlap': tagOverlap.clamp(0.0, 1.0).toDouble(),
      'price_fit': priceFit.clamp(0.0, 1.0).toDouble(),
      'distance_decay': distanceDecay.clamp(0.0, 1.0).toDouble(),
      'recency': recency.clamp(0.0, 1.0).toDouble(),
      'popularity_prior': popularity.clamp(0.0, 1.0).toDouble(),
      'explore': explore.toDouble(),
      'vibe_fit': vibeFit.clamp(0.0, 1.0).toDouble(),
      'semantic_sim': semanticSim,
      'neighborhood_fit': neighborhoodFitVal,
    };
  }

  double _scoreFromFeatures(Map<String, double> f, Map<String, double> w) {
    var sum = 0.0;
    for (final entry in f.entries) {
      sum += (w[entry.key] ?? 0.0) * entry.value;
    }
    return sum;
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
  void _logImpressions(
    List<_Scored> scored,
    PropertySearchCriteria c,
    Map<String, double> weights,
    String? cohort,
  ) {
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
          'maxRooms': c.maxRooms,
          'amenities': c.amenityKeys.toList(),
          'vibe': c.vibe,
        },
        // The actual weight-set used for this search (cohort-dependent), so the
        // training log reflects what really ranked the results.
        'weights': weights,
        'cohort': cohort,
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
