// ════════════════════════════════════════════════════════════════════════════
// PART 4 / 4 — RE-RANKING, EXPLAINABILITY & ORCHESTRATION
// ════════════════════════════════════════════════════════════════════════════
//
// The public face of the engine. Ties Parts 1→2→3 together and adds the
// finishing layers that make recommendations feel intelligent:
//
//   • DiversityReranker  — MMR (Maximal Marginal Relevance): avoid showing ten
//                          near-identical listings; balance relevance & variety.
//   • ExplorationPolicy  — a bounded Thompson-sampling bonus that occasionally
//                          surfaces high-upside listings sitting on dimensions
//                          the model is still uncertain about.
//   • Explainer          — SHAP-like attribution over the MAUT contributions,
//                          turned into concrete, data-driven Hebrew highlights.
//   • RecommendationEngine.recommend(...) — the single entry point used by the
//                          assistant, plus a ScoredProperty adapter so the
//                          existing SmartSearch UI can consume it unchanged.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:dating_app/core/finance/commute.dart';
import 'package:dating_app/core/finance/monthly_cost.dart';
import 'package:dating_app/core/finance/rental_yield.dart';
import 'package:dating_app/core/govdata/gov_sources.dart';
import 'package:dating_app/core/matching/match_models.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/preference_model.dart';
import 'package:dating_app/core/search/engine/ranking_engine.dart';
import 'package:dating_app/core/search/engine/scorecard.dart';
import 'package:dating_app/core/search/engine/scorecard_stats.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/profile_tags.dart';
import 'package:dating_app/data/models/rental_models.dart';

// ═════════════════════════════════════════════════════════════════════════════
// Recommendation — public result DTO
// ═════════════════════════════════════════════════════════════════════════════

class Recommendation {
  Recommendation({
    required this.property,
    required this.fitScore,
    required this.fitPct,
    required this.explanation,
    required this.highlights,
    required this.dimensionBreakdown,
    required this.confidence,
    required this.strictMatch,
    required this.trainKm,
    this.scorecard,
  });

  final RentalProperty property;
  final double fitScore; // 0..100
  final int fitPct; // rounded, user-facing
  final String explanation; // one-line Hebrew summary
  final List<String> highlights; // concrete chips
  final Map<String, double> dimensionBreakdown; // dim → contribution
  final double confidence; // 0..1 how sure we are about this ranking
  final bool strictMatch; // all hard constraints met
  final double? trainKm;

  /// Full data-grounded reasoning for this property (engine breakdown + raw
  /// stats + persona reasons + concerns). Built in [RecommendationEngine.recommend].
  final Scorecard? scorecard;
}

// ═════════════════════════════════════════════════════════════════════════════
// DiversityReranker — Maximal Marginal Relevance
// ═════════════════════════════════════════════════════════════════════════════

class DiversityReranker {
  const DiversityReranker._();

  // Compact comparison vector for similarity (the axes a user perceives as
  // "the same kind of apartment").
  static List<double> _vec(PropertyFeatureVector p) => [
        p.centrality,
        p.get('price_percentile'),
        p.get('rooms_percentile'),
        p.amenityRichness,
        p.transitAccess,
        p.valueScore,
      ];

  static double _cosine(List<double> a, List<double> b) {
    double dot = 0, na = 0, nb = 0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      na += a[i] * a[i];
      nb += b[i] * b[i];
    }
    final denom = math.sqrt(na) * math.sqrt(nb);
    return denom < 1e-12 ? 0.0 : (dot / denom).clamp(0.0, 1.0);
  }

  /// Greedy MMR selection: pick [limit] items maximizing
  /// `λ·relevance − (1−λ)·maxSimToAlreadyPicked`.
  static List<RankedCandidate> select(
    List<RankedCandidate> ranked, {
    required int limit,
    double lambda = 0.78,
  }) {
    if (ranked.length <= limit) return ranked;
    final pool = List<RankedCandidate>.from(ranked);
    final selected = <RankedCandidate>[];
    final selectedVecs = <List<double>>[];

    // seed with the top-relevance item
    selected.add(pool.removeAt(0));
    selectedVecs.add(_vec(selected.first.pfv));

    while (selected.length < limit && pool.isNotEmpty) {
      var bestIdx = 0;
      var bestMmr = -1e9;
      for (var i = 0; i < pool.length; i++) {
        final v = _vec(pool[i].pfv);
        double maxSim = 0;
        for (final sv in selectedVecs) {
          final sim = _cosine(v, sv);
          if (sim > maxSim) maxSim = sim;
        }
        final mmr = lambda * pool[i].score - (1 - lambda) * maxSim;
        if (mmr > bestMmr) {
          bestMmr = mmr;
          bestIdx = i;
        }
      }
      final chosen = pool.removeAt(bestIdx);
      selected.add(chosen);
      selectedVecs.add(_vec(chosen.pfv));
    }
    return selected;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// ExplorationPolicy — bounded Thompson-sampling lift
// ═════════════════════════════════════════════════════════════════════════════

class ExplorationPolicy {
  const ExplorationPolicy._();

  /// Add a small, bounded bonus to candidates that score well on dimensions the
  /// model is *uncertain* about — if those weights are truly higher than the
  /// posterior mean, these are hidden gems. epsilon keeps it from dominating.
  static void apply(
    List<RankedCandidate> ranked,
    UserPreferenceModel model, {
    double epsilon = 0.06,
    int? seed,
  }) {
    final rng = math.Random(seed ?? DateTime.now().millisecondsSinceEpoch);
    for (final c in ranked) {
      double bonus = 0;
      double norm = 0;
      for (final dim in kScoringDimensions) {
        final unc = model.uncertainty(dim);
        final sat = model.satisfaction(dim, c.pfv);
        // Thompson draw: sample a plausible weight, reward alignment with it
        final sampled = math.max(0.0, model.weights[dim]!.sample(rng));
        bonus += unc * sat * sampled;
        norm += unc;
      }
      final normalized = norm > 0 ? bonus / norm : 0.0;
      c.score = (c.score + epsilon * normalized).clamp(0.0, 1.0);
    }
    ranked.sort((a, b) => b.score.compareTo(a.score));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Explainer — attribution → concrete Hebrew highlights
// ═════════════════════════════════════════════════════════════════════════════

class Explainer {
  const Explainer._();

  static const Map<String, String> _dimLabel = {
    'location': 'מיקום',
    'neighborhood': 'אזור איכותי',
    'safety': 'בטיחות',
    'budget': 'תקציב',
    'value': 'תמורה למחיר',
    'size': 'גודל',
    'amenities': 'מאפיינים',
    'transit': 'תחבורה',
    'condition': 'מצב הנכס',
    'freshness': 'חדש',
    'popularity': 'ביקוש',
    'trust': 'אמינות',
    'schools': 'מוסדות חינוך',
    'family': 'אזור משפחתי',
    'health': 'נגישות בריאות',
    'coast': 'קרבה לים',
    'yield': 'תשואה להשקעה',
    'university': 'קרבה לאוניברסיטה',
    'young_area': 'אזור צעיר ותוסס',
    'senior_area': 'אזור שקט ומבוגר',
    'luxury': 'רמת יוקרה',
    'view': 'קומה גבוהה / נוף',
    'spaciousness': 'מרווחות',
    'accessibility': 'נגישות',
  };

  /// Public Hebrew label for a scoring dimension key (used by the Scorecard
  /// builder). Falls back to the raw key when unmapped.
  static String dimLabel(String key) => _dimLabel[key] ?? key;

  /// Concrete, data-driven chips for a candidate.
  static List<String> highlights(
    RankedCandidate c,
    UserPreferenceModel model,
  ) {
    final pfv = c.pfv;
    final p = pfv.property;
    final chips = <String>[];

    // value / pricing
    if (pfv.get('hedonic_residual') > 0.2 || pfv.valueScore > 0.72) {
      chips.add('מחיר אטרקטיבי מתחת לשוק');
    } else if (pfv.get('price_per_sqm_percentile') < 0.35 &&
        (p.pricePerSquareMeter ?? 0) > 0) {
      chips.add('₪${p.pricePerSquareMeter}/מ״ר — נמוך לאזור');
    }

    // transit — real gov-data signals
    final railKm = pfv.get('rail_km', 99);
    if (railKm < 1.2) {
      chips.add('צמוד לרכבת');
    } else if (railKm < 3.0) {
      chips.add('כ-${railKm.toStringAsFixed(1)} ק״מ מהרכבת');
    } else if (pfv.get('transit_density') > 0.6) {
      chips.add('מחובר היטב לתחבורה');
    }

    // location & neighbourhood quality (CBS socioeconomic cluster)
    if (pfv.centrality > 0.78) chips.add('מיקום מרכזי');
    if (pfv.get('socioeconomic') > 0.78) chips.add('אזור מבוקש');

    // livability (real gov data)
    if (pfv.get('safety') > 0.7) chips.add('אזור בטוח יחסית');
    if (pfv.get('school_access') > 0.6) chips.add('קרוב למוסדות חינוך');
    if (pfv.get('demo_young') > 0.66 && pfv.get('demo_child') < 0.3) {
      chips.add('שכונה צעירה');
    } else if (pfv.get('demo_child') > 0.6) {
      chips.add('שכונה משפחתית');
    }

    // requested amenities that matched
    final matched = <String>[];
    for (final key in model.requestedAmenityKeys) {
      if (propertyHasFeature(p, key)) {
        final label = _amenityLabel(key);
        if (label != null) matched.add(label);
      }
    }
    if (matched.isNotEmpty) {
      chips.add(matched.take(3).join(' · '));
    }

    // condition
    if (pfv.get('condition_score') > 0.82) chips.add('מצב מצוין');

    // freshness
    if (pfv.get('is_new_listing') > 0.5) {
      chips.add('חדש באתר');
    }

    // demand
    if (pfv.get('like_rate_wilson') > 0.4 || pfv.demandPressure > 0.45) {
      chips.add('מבוקש עכשיו');
    }

    // trust
    if (pfv.get('verified') > 0.5) chips.add('✓ מאומת');
    if (pfv.get('has_3d_tour') > 0.5) chips.add('סיור תלת-ממד');

    return chips;
  }

  /// One-line Hebrew explanation from the top MAUT contributors.
  static String explain(RankedCandidate c, UserPreferenceModel model) {
    final entries = c.dimensionContrib.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final strengths = <String>[];
    for (final e in entries) {
      if (strengths.length >= 3) break;
      final sat = model.satisfaction(e.key, c.pfv);
      if (sat < 0.6) continue; // only mention genuine strengths
      final label = _dimLabel[e.key];
      if (label != null) strengths.add(label);
    }

    if (strengths.isEmpty) {
      return c.strictMatch
          ? 'עונה על כל הדרישות שלך'
          : 'התאמה סבירה על פני מספר קריטריונים';
    }
    final lead = c.strictMatch ? 'עונה על הדרישות, ובולט ב' : 'בולט ב';
    return '$lead${strengths.join(', ')}';
  }

  static String? _amenityLabel(String catalogKey) {
    const map = {
      'renovated': 'משופצת',
      'petsAllowed': 'ידידותי לחיות',
      'parking': 'חניה',
      'balcony': 'מרפסת',
      'elevator': 'מעלית',
      'furnished': 'מרוהטת',
      'mamad': 'ממ״ד',
      'garden': 'גינה',
      'airConditioning': 'מזגן',
      'pool': 'בריכה',
      'gym': 'חדר כושר',
      'storage': 'מחסן',
      'sunBalcony': 'מרפסת שמש',
      'bars': 'סורגים',
      'internetIncluded': 'אינטרנט',
      'washingMachine': 'מכונת כביסה',
    };
    return map[catalogKey];
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// RecommendationEngine — the public entry point
// ═════════════════════════════════════════════════════════════════════════════

class RecommendationEngine {
  const RecommendationEngine._();

  /// Full pipeline: feature-engineer → model → rank → explore → diversify →
  /// explain. Never dead-ends: returns the best [limit] of whatever exists.
  static List<Recommendation> recommend({
    required List<RentalProperty> candidates,
    required SearchQuery query,
    TenantProfile? profile,
    int limit = 10,
    double diversityLambda = 0.78,
    bool explore = true,
    int? seed,
    OnlineLogisticLearner? learner,
    double? workLat,
    double? workLon,
  }) {
    if (candidates.isEmpty) return const [];

    // Hard rent/sale gate: an investor's "דירה להשקעה" must never surface
    // rentals (and vice-versa). Enforced here so EVERY caller — incl. the chat's
    // provider.recommendForTenant path — is gated, not just SmartSearch.rank.
    final gated = SmartSearch.applyTransactionFilter(candidates, query);
    if (gated.isEmpty) return const [];
    candidates = gated;

    // City gate (metro-aware): when the user NAMES a city, stay in its METRO —
    // the named city plus the towns within ~18 km (גוש דן, הקריות, השרון …), so a
    // "תל אביב" search also surfaces רמת גן / גבעתיים, but never a flat 100 km away.
    // The soft city penalty still ranks the exact city first; relax to all cities
    // only when the named city has zero stock.
    final city = query.city?.trim();
    if (city != null && city.isNotEmpty) {
      final inCity = candidates
          .where((p) => '${p.city} ${p.neighborhood}'.contains(city))
          .toList();
      if (inCity.isNotEmpty) {
        // The named-city listings define its centre.
        final cLat = inCity.map((p) => p.lat).reduce((a, b) => a + b) /
            inCity.length;
        final cLon = inCity.map((p) => p.lon).reduce((a, b) => a + b) /
            inCity.length;
        candidates = candidates
            .where((p) =>
                '${p.city} ${p.neighborhood}'.contains(city) ||
                _km(p.lat, p.lon, cLat, cLon) <= 18.0)
            .toList();
      }
    }

    // Part 1 — market analysis + feature engineering
    final market = MarketContext.analyze(candidates);
    final pfvs = [
      for (final p in candidates) FeatureEngineer.engineer(p, market),
    ];

    // Part 2 — preference model
    final model = PreferenceModelBuilder.build(
      query: query,
      profile: profile,
      market: market,
      learner: learner,
    );

    // Part 3 — rank
    final ranked = RankingEngine.rank(pfvs, model);
    if (ranked.isEmpty) return const [];

    // Part 4 — exploration + diversity
    if (explore) {
      ExplorationPolicy.apply(ranked, model, seed: seed);
    }
    final selected = DiversityReranker.select(
      ranked,
      limit: limit,
      lambda: diversityLambda,
    );
    // The ranking blend (c.score) selects WHICH listings + diversity; but the
    // user-facing order and the fit% must speak one language, so present the
    // selected set best-match-first by the SAME stated-match that drives fit%.
    final match = <RankedCandidate, double>{
      for (final c in selected) c: _statedMatch(c, model),
    };
    selected.sort((a, b) => match[b]!.compareTo(match[a]!));

    // model confidence: how much intent we captured + behavioral confidence
    final intentCoverage =
        model.statedDimensions.length / kScoringDimensions.length;
    final baseConfidence =
        (0.4 + 0.4 * intentCoverage + 0.2 * model.learner.confidence)
            .clamp(0.0, 1.0);

    return [
      for (final c in selected)
        () {
          final fitPct = (match[c]! * 100).round();
          final explanation = Explainer.explain(c, model);
          final highlights = Explainer.highlights(c, model);
          final confidence =
              (baseConfidence * (0.7 + 0.3 * c.constraintSatisfaction))
                  .clamp(0.0, 1.0);
          final scorecard = _buildScorecard(
            c: c,
            model: model,
            market: market,
            profile: profile,
            fitPct: fitPct,
            confidence: confidence,
            explanation: explanation,
            highlights: highlights,
            workLat: workLat,
            workLon: workLon,
          );
          return Recommendation(
            property: c.property,
            fitScore: match[c]! * 100,
            fitPct: fitPct,
            explanation: explanation,
            highlights: highlights,
            dimensionBreakdown: c.dimensionContrib,
            confidence: confidence,
            strictMatch: c.strictMatch,
            trainKm: IsraelGeoIndex.nearestStationKm(
                c.property.lat, c.property.lon),
            scorecard: scorecard,
          );
        }(),
    ];
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Scorecard assembly — stop discarding the engine's reasoning.
  //
  // Turns the candidate's already-computed MAUT breakdown + the preference
  // model's weights + the raw market statistics + the tenant persona into the
  // frozen [Scorecard] contract the transparency UI / LLM explainer consume.
  // ───────────────────────────────────────────────────────────────────────────

  /// A dimension counts as a genuine strength above this contribution share.
  static const double _kStrongScore = 0.5; // axis reads as a strength at/above this satisfaction

  static Scorecard _buildScorecard({
    required RankedCandidate c,
    required UserPreferenceModel model,
    required MarketContext market,
    required TenantProfile? profile,
    required int fitPct,
    required double confidence,
    required String explanation,
    required List<String> highlights,
    double? workLat,
    double? workLon,
  }) {
    final stats = ScorecardStats.statLabels(c.property, market);
    final weightSum = model.weightSum;

    final dimensions = <ScorecardDimension>[];
    // Iterate the canonical dimension list so keys align with ScorecardStats /
    // the preference model exactly.
    for (final key in kScoringDimensions) {
      // coast/yield are added below as rich, stat-carrying dimensions (with the
      // real km / yield%); skip them here to avoid a bare duplicate.
      if (key == kCoastDimensionKey || key == kYieldDimensionKey) continue;
      // BAR = how well THIS apartment scores on the axis — its MAUT satisfaction
      // u∈[0,1] — NOT the weighted contribution. The contribution is w·u/Σw, which
      // is tiny by construction, so showing it made a 68% match read as
      // "everything ≤13%". Weight is carried separately as importance.
      final score = model.satisfaction(key, c.pfv).clamp(0.0, 1.0);
      final weightPct =
          weightSum > 0 ? (model.weight(key) / weightSum).clamp(0.0, 1.0) : 0.0;
      // Keep the card focused: axes that matter to the user OR carry a gov stat.
      final matters = model.statedDimensions.contains(key) || weightPct >= 0.05;
      if (!matters && !stats.containsKey(key)) continue;
      final stat = stats[key];
      dimensions.add(ScorecardDimension(
        key: key,
        label: Explainer.dimLabel(key),
        weightPct: weightPct,
        contributionPct: score, // the apartment's strength on this axis (0..1)
        stat: stat,
        // Provenance only when there's a real figure to attribute.
        source: stat != null ? GovSources.labelFor(key) : null,
        // A concern only when the apartment genuinely scores low on the axis —
        // not when the axis merely has low weight.
        positive: score >= _kStrongScore,
      ));
    }

    // Optional commute-to-work axis (Tenant Feature #3). Mirrors the train-
    // distance dimension: shown only when the tenant supplied a work location AND
    // the property has usable coordinates. Off by default → fully back-compat.
    final commuteDim = _commuteDimension(c.property, workLat, workLon);
    if (commuteDim != null) dimensions.add(commuteDim);

    // True monthly cost (rent + arnona + vaad) — a listing can fit on rent yet
    // blow the budget once municipal tax + maintenance are added.
    final costDim = _totalCostDimension(c.property);
    if (costDim != null) dimensions.add(costDim);

    // Investor lens: gross rental yield, shown only for for-sale listings.
    final yieldDim = _yieldDimension(c.property, model, weightSum);
    if (yieldDim != null) dimensions.add(yieldDim);

    // Beach proximity — a real deciding factor in coastal Israel.
    final coastDim = _coastDimension(c.property, model, weightSum);
    if (coastDim != null) dimensions.add(coastDim);

    // Most-relevant axes first (what matters to the user); strongest as tiebreak.
    dimensions.sort((a, b) {
      final w = b.weightPct.compareTo(a.weightPct);
      return w != 0 ? w : b.contributionPct.compareTo(a.contributionPct);
    });

    final personaReasons = _personaReasons(c.property, profile);
    final concerns = _concerns(c, model, dimensions);

    return Scorecard(
      fitPct: fitPct,
      tier: MatchTierX.fromScore(fitPct).label,
      confidence: confidence,
      explanation: explanation,
      highlights: highlights,
      dimensions: dimensions,
      personaReasons: personaReasons,
      concerns: concerns,
    );
  }

  /// Stable engine key for the optional commute-to-work axis.
  static const String kCommuteDimensionKey = 'commute';

  /// Build the optional "מרחק מהעבודה" scorecard dimension from a coarse,
  /// honest [Commute] estimate. Returns null when work coords are absent/invalid
  /// or the property has no usable coordinates — so behaviour is unchanged when
  /// the tenant has no stored work location.
  static ScorecardDimension? _commuteDimension(
    RentalProperty property,
    double? workLat,
    double? workLon,
  ) {
    if (workLat == null || workLon == null) return null;
    final est = Commute.estimate(
      propLat: property.lat,
      propLon: property.lon,
      workLat: workLat,
      workLon: workLon,
    );
    if (est == null) return null;

    // Closer = better. Map drive minutes to a 0..1 satisfaction: ≤10 min ≈ 1,
    // ≥60 min ≈ 0. Linear, deterministic, purely for ordering/positivity.
    final score =
        (1.0 - (est.approxDriveMinutes - 10) / 50.0).clamp(0.0, 1.0).toDouble();
    return ScorecardDimension(
      key: kCommuteDimensionKey,
      label: 'מרחק מהעבודה',
      // Importance is owned by the preference model; this axis is informational,
      // so it carries no model weight (it never re-ranks, only explains).
      weightPct: 0.0,
      contributionPct: score,
      stat: est.plainHebrewLabel,
      positive: score >= _kStrongScore,
    );
  }

  /// Stable engine key for the informational "total monthly cost" axis.
  static const String kTotalCostDimensionKey = 'total_cost';

  /// Informational "עלות חודשית כוללת" axis from a coarse [MonthlyCost] estimate.
  /// Weight 0 → it explains, never re-ranks (promote to a preference weight later
  /// if we want total cost to actually reorder results). Null when size is unknown.
  static ScorecardDimension? _totalCostDimension(RentalProperty property) {
    if (property.transactionType == PropertyTransactionType.sale) return null;
    final est = MonthlyCost.estimate(
      rent: property.price,
      sizeM2: property.sizeM2,
      city: property.city,
    );
    if (est == null) return null;
    // Smaller add-on over rent = better. ≤0% ≈ 1, ≥30% ≈ 0.
    final addOnRatio = (est.total - est.rent) / est.rent;
    final score = (1.0 - addOnRatio / 0.30).clamp(0.0, 1.0).toDouble();
    return ScorecardDimension(
      key: kTotalCostDimensionKey,
      label: 'עלות חודשית כוללת',
      weightPct: 0.0,
      contributionPct: score,
      stat: est.plainHebrewLabel,
      positive: score >= _kStrongScore,
    );
  }

  /// Stable engine key for the informational "rental yield" axis (sale listings).
  static const String kYieldDimensionKey = 'yield';

  /// Informational "תשואה להשקעה" axis for FOR-SALE listings, from a coarse
  /// [RentalYield] estimate. Weight 0 → explains, never re-ranks (owner-occupier
  /// ordering by default; weight it for the investor cohort later). Null for
  /// rentals / unusable size.
  static ScorecardDimension? _yieldDimension(
      RentalProperty property, UserPreferenceModel model, double weightSum) {
    if (property.transactionType != PropertyTransactionType.sale) return null;
    final est = RentalYield.estimate(
      salePrice: property.price,
      sizeM2: property.sizeM2,
      city: property.city,
    );
    if (est == null) return null;
    // 2% ≈ 0, 5% ≈ 1.
    final score = ((est.grossYieldPct - 2.0) / 3.0).clamp(0.0, 1.0).toDouble();
    final weightPct = weightSum > 0
        ? (model.weight(kYieldDimensionKey) / weightSum).clamp(0.0, 1.0)
        : 0.0;
    return ScorecardDimension(
      key: kYieldDimensionKey,
      label: 'תשואה להשקעה',
      weightPct: weightPct,
      contributionPct: score,
      stat: est.plainHebrewLabel,
      positive: score >= _kStrongScore,
    );
  }

  /// Stable engine key for the informational "beach proximity" axis.
  static const String kCoastDimensionKey = 'coast';

  /// Informational "קרבה לים" axis from the real coastline geo-index. Shown only
  /// when the property is within ~8 km of the sea; weight 0 (explains, doesn't
  /// re-rank). Null inland.
  static ScorecardDimension? _coastDimension(
      RentalProperty property, UserPreferenceModel model, double weightSum) {
    final km = IsraelGeoIndex.coastKm(property.lat, property.lon);
    if (km == null || km > 8) return null;
    final score = IsraelGeoIndex.proximityKernel(km, scaleKm: 3.0);
    final kmLabel = km < 10 ? km.toStringAsFixed(1) : km.round().toString();
    final weightPct = weightSum > 0
        ? (model.weight(kCoastDimensionKey) / weightSum).clamp(0.0, 1.0)
        : 0.0;
    return ScorecardDimension(
      key: kCoastDimensionKey,
      label: 'קרבה לים',
      weightPct: weightPct,
      contributionPct: score,
      stat: 'כ-$kmLabel ק״מ מהחוף',
      positive: score >= _kStrongScore,
    );
  }

  // matchKey → property feature catalogue key (only the keys that correspond to
  // a concrete property amenity can be satisfied by the listing itself).
  static const Map<String, String> _personaKeyToFeature = {
    'pets_allowed': 'petsAllowed',
    'parking': 'parking',
    'furnished': 'furnished',
    'elevator': 'elevator',
    'balcony': 'balcony',
    'shelter': 'mamad',
    'ac': 'airConditioning',
  };

  // Hebrew persona reason per matchKey (reads as "fits …").
  static const Map<String, String> _personaKeyLabel = {
    'pets_allowed': 'מתאים לבעלי חיות מחמד',
    'parking': 'כולל חניה כפי שביקשת',
    'furnished': 'מגיע מרוהט כפי שביקשת',
    'elevator': 'יש מעלית כפי שביקשת',
    'balcony': 'יש מרפסת כפי שביקשת',
    'shelter': 'כולל ממ״ד / מקלט',
    'ac': 'יש מיזוג אוויר',
  };

  /// Persona-specific reasons: the tenant's stated tags whose required feature
  /// the property actually has. Empty when no profile is supplied.
  static List<String> _personaReasons(
    RentalProperty property,
    TenantProfile? profile,
  ) {
    if (profile == null) return const [];
    final tags = [...profile.importantDetails, ...profile.dealBreakers];
    if (tags.isEmpty) return const [];
    final keys =
        ProfileTagCatalog.matchKeysFor(tags, isLandlord: false);
    final dealKeys =
        ProfileTagCatalog.matchKeysFor(profile.dealBreakers, isLandlord: false);
    final reasons = <String>[];
    for (final key in keys) {
      final featureKey = _personaKeyToFeature[key];
      if (featureKey == null) continue; // non-physical preference, can't verify
      if (!propertyHasFeature(property, featureKey)) continue;
      final base = _personaKeyLabel[key] ?? 'מתאים להעדפה שלך';
      reasons.add(
          dealKeys.contains(key) ? '$base — דרישת חובה שלך' : base);
    }
    return reasons;
  }

  /// Honest downsides: low/negative dimensions that carry weight, plus a
  /// budget-over note when the listing exceeds the stated max budget.
  // Great-circle km between two coordinates (metro-gate radius check).
  static double _km(double la1, double lo1, double la2, double lo2) {
    if (la1.abs() < 0.1 || la2.abs() < 0.1) return double.infinity; // bad coords
    const r = 6371.0088;
    final dLa = (la2 - la1) * math.pi / 180.0;
    final dLo = (lo2 - lo1) * math.pi / 180.0;
    final a = math.sin(dLa / 2) * math.sin(dLa / 2) +
        math.cos(la1 * math.pi / 180.0) *
            math.cos(la2 * math.pi / 180.0) *
            math.sin(dLo / 2) *
            math.sin(dLo / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  /// Display "match %": how well the listing satisfies WHAT THE USER ASKED FOR
  /// (the stated dimensions), lightly blended with overall quality. The raw
  /// ranking score (c.score) includes trust/popularity/freshness the user never
  /// asked about, so it under-reads a perfect city+budget+size match as ~57%.
  static double _statedMatch(RankedCandidate c, UserPreferenceModel model) {
    final stated = model.statedDimensions;
    if (stated.isEmpty) return c.score;
    double wsum = 0, acc = 0;
    for (final dim in stated) {
      final w = model.weight(dim);
      if (w <= 0) continue;
      wsum += w;
      acc += w * model.satisfaction(dim, c.pfv);
    }
    if (wsum <= 0) return c.score;
    // Mostly the stated-criteria fit, with a little overall quality so it isn't
    // a single axis. Both are 0..1.
    return (0.8 * (acc / wsum) + 0.2 * c.score).clamp(0.0, 1.0);
  }

  static List<String> _concerns(
    RankedCandidate c,
    UserPreferenceModel model,
    List<ScorecardDimension> dimensions,
  ) {
    final concerns = <String>[];

    // Budget concerns ONLY when the user actually stated a budget — otherwise
    // maxBudget is a synthetic median default and "over budget" is a phantom.
    final price = c.property.price;
    final maxBudget = model.maxBudget;
    final budgetStated = model.statedDimensions.contains('budget');
    if (budgetStated && maxBudget > 0) {
      if (price > maxBudget) {
        final over = ((price - maxBudget) / maxBudget * 100).round();
        concerns.add(over <= 10
            ? 'מעט מעל התקציב שלך'
            : 'מעל התקציב שלך בכ-$over%');
      } else if (c.property.transactionType != PropertyTransactionType.sale) {
        // Rent fits, but arnona + vaad push the true cost over — flag ONLY when
        // it overshoots by a meaningful margin (>3%), not by a few shekels.
        final cost = MonthlyCost.estimate(
            rent: price, sizeM2: c.property.sizeM2, city: c.property.city);
        if (cost != null && cost.total > maxBudget * 1.03) {
          concerns.add('שכ״ד בתקציב, אך העלות הכוללת '
              '(${cost.plainHebrewLabel}) חורגת מהתקציב');
        }
      }
    }

    // Only GENUINELY weak spots on axes the user cares about — not axes that are
    // merely mediocre. Capped at 2 so a card isn't a wall of caveats.
    for (final d in dimensions) {
      if (concerns.length >= 2) break;
      if (d.key == 'budget') continue; // covered above
      if (d.contributionPct >= 0.35) continue; // genuinely weak only
      final weighty =
          model.statedDimensions.contains(d.key) || d.weightPct >= 0.12;
      if (!weighty) continue;
      concerns.add('${d.label} פחות חזק כאן');
    }
    return concerns;
  }

  /// Adapter: run the pipeline and return results as the legacy [ScoredProperty]
  /// list the existing SmartSearch UI already renders — so the new engine drops
  /// in without UI changes.
  static List<ScoredProperty> recommendAsScored({
    required List<RentalProperty> candidates,
    required SearchQuery query,
    TenantProfile? profile,
    int limit = 10,
    int? seed,
    OnlineLogisticLearner? learner,
  }) {
    final recs = recommend(
      candidates: candidates,
      query: query,
      profile: profile,
      limit: limit,
      seed: seed,
      learner: learner,
    );
    return [
      for (final r in recs)
        ScoredProperty(
          r.property,
          r.fitScore / 100.0,
          [
            '${r.fitPct}% התאמה',
            ...r.highlights,
          ],
          r.trainKm,
          r.strictMatch,
          r.scorecard,
        ),
    ];
  }
}
