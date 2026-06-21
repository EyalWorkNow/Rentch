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

import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/preference_model.dart';
import 'package:dating_app/core/search/engine/ranking_engine.dart';
import 'package:dating_app/core/search/smart_search.dart';
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
    'budget': 'תקציב',
    'value': 'תמורה למחיר',
    'size': 'גודל',
    'amenities': 'מאפיינים',
    'transit': 'תחבורה',
    'condition': 'מצב הנכס',
    'freshness': 'חדש',
    'popularity': 'ביקוש',
    'trust': 'אמינות',
  };

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

    // transit
    if (pfv.transitAccess > 0.5) {
      final km = pfv.get('transit_km');
      if (km < 30) {
        final mins = (km / 0.075).round().clamp(1, 60); // ~walking proxy
        chips.add('כ-$mins דק׳ מהרכבת');
      }
    }

    // location
    if (pfv.centrality > 0.78) chips.add('מיקום מרכזי');

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
  }) {
    if (candidates.isEmpty) return const [];

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

    // model confidence: how much intent we captured + behavioral confidence
    final intentCoverage =
        model.statedDimensions.length / kScoringDimensions.length;
    final baseConfidence =
        (0.4 + 0.4 * intentCoverage + 0.2 * model.learner.confidence)
            .clamp(0.0, 1.0);

    return [
      for (final c in selected)
        Recommendation(
          property: c.property,
          fitScore: c.score * 100,
          fitPct: (c.score * 100).round(),
          explanation: Explainer.explain(c, model),
          highlights: Explainer.highlights(c, model),
          dimensionBreakdown: c.dimensionContrib,
          confidence: (baseConfidence * (0.7 + 0.3 * c.constraintSatisfaction))
              .clamp(0.0, 1.0),
          strictMatch: c.strictMatch,
          trainKm: IsraelGeoIndex.nearestStationKm(
              c.property.lat, c.property.lon),
        ),
    ];
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
        ),
    ];
  }
}
