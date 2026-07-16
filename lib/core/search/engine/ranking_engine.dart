// ════════════════════════════════════════════════════════════════════════════
// PART 3 / 4 — SCORING & RANKING ENGINE
// ════════════════════════════════════════════════════════════════════════════
//
// Combines THREE genuinely-orthogonal scorers into one calibrated relevance per
// property, with full per-dimension attribution for explainability (Part 4):
//
//   1. MautScorer            — weighted multi-attribute utility  U = Σ w·u / Σ w
//                              (the single canonical PERSONALISED linear signal)
//   2. GradientBoostedScorer — additive ensemble of decision stumps capturing
//                              nonlinear interactions (value×trust×freshness …)
//   3. the online learner    — behavioural signal, trusted as feedback accrues
//
// (TOPSIS and Cosine were removed — they re-measured MAUT's construct and only
//  inflated confidence; MAUT inherits their combined weight, so personalisation
//  strength is unchanged. See CalibratedEnsemble.combine.)
//
// The CalibratedEnsemble blends them (weighted by each scorer's reliability for
// the current query), applies Platt-style sigmoid calibration, and gates the
// result by the soft constraint satisfaction from Part 2 — so over-budget /
// wrong-city listings sink but never vanish (never dead-ends).
// ════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/preference_model.dart';
import 'package:dating_app/data/models/rental_models.dart';

// ═════════════════════════════════════════════════════════════════════════════
// RankedCandidate — a scored property with full breakdown
// ═════════════════════════════════════════════════════════════════════════════

class RankedCandidate {
  RankedCandidate({
    required this.pfv,
    required this.score,
    required this.components,
    required this.dimensionContrib,
    required this.constraintSatisfaction,
    required this.strictMatch,
  });

  final PropertyFeatureVector pfv;

  /// Final calibrated relevance in [0,1].
  double score;

  /// Per-scorer breakdown: maut / gbm / learner / gbdt (gbdt only once the
  /// on-device learned tree model has trained).
  final Map<String, double> components;

  /// Weighted contribution of each scoring dimension to the MAUT score
  /// (already normalized to sum≈MAUT). Drives SHAP-like explanations.
  final Map<String, double> dimensionContrib;

  final double constraintSatisfaction; // 0..1 from HardConstraints
  final bool strictMatch;

  RentalProperty get property => pfv.property;
}

// ═════════════════════════════════════════════════════════════════════════════
// 1. MAUT — Multi-Attribute Utility aggregation
// ═════════════════════════════════════════════════════════════════════════════

class MautScorer {
  const MautScorer._();

  /// Returns (utility, perDimensionContribution). Contribution_d = w_d·u_d/Σw.
  static (double, Map<String, double>) score(
    PropertyFeatureVector pfv,
    UserPreferenceModel model,
  ) {
    double weighted = 0;
    double wsum = 0;
    final contrib = <String, double>{};
    for (final dim in kScoringDimensions) {
      final w = model.weight(dim);
      final u = model.satisfaction(dim, pfv);
      weighted += w * u;
      wsum += w;
      contrib[dim] = w * u; // un-normalized; normalize after
    }
    final utility = wsum > 0 ? weighted / wsum : 0.5;
    if (wsum > 0) {
      contrib.updateAll((_, v) => v / wsum);
    }
    return (utility, contrib);
  }
}

// NOTE: TopsisScorer and CosineScorer were removed. Both measured the same
// weighted-satisfaction construct as MAUT (Cosine = MAUT normalised by ‖s‖;
// TOPSIS = a batch-relative echo that also drifted with the candidate pool), so
// blending them triple-counted one signal and manufactured false confidence.
// MAUT now carries their combined weight — see CalibratedEnsemble.combine.

// ═════════════════════════════════════════════════════════════════════════════
// 4. Gradient-Boosted stump ensemble — nonlinear interaction capture
//
// An additive model Σ leaf_k(features) → logit → sigmoid. The stumps encode
// domain knowledge as interaction terms a flat weighted-sum can't express
// (e.g. "underpriced AND verified AND fresh" deserves a super-linear boost;
// "high skip-ratio" deserves a penalty regardless of other strengths).
// Structured exactly like a trained GBM so it can later be swapped for one
// learned offline from real click logs.
// ═════════════════════════════════════════════════════════════════════════════

class _Stump {
  const _Stump(this.feature, this.threshold, this.whenAbove, this.whenBelow);
  final String feature;
  final double threshold;
  final double whenAbove; // leaf value (logit contribution) if feature ≥ thr
  final double whenBelow;
}

class GradientBoostedScorer {
  const GradientBoostedScorer._();

  // Hand-tuned ensemble. Leaf values are logit contributions; their sum passes
  // through a sigmoid. Positive ⇒ boost, negative ⇒ penalty.
  static const List<_Stump> _stumps = [
    // value: strong underpricing is a major positive signal
    _Stump('value_score', 0.7, 0.9, 0.0),
    _Stump('hedonic_residual', 0.25, 0.7, 0.0),
    _Stump('price_per_sqm_percentile', 0.4, 0.0, 0.45), // cheap per-sqm ⇒ +
    // trust & verification
    _Stump('trust', 0.6, 0.5, -0.1),
    _Stump('verified', 0.5, 0.35, 0.0),
    _Stump('media_richness', 0.5, 0.25, -0.1),
    // demand quality (confidence-bounded, not raw volume)
    _Stump('like_rate_wilson', 0.35, 0.6, 0.0),
    _Stump('conversion_rate', 0.08, 0.5, 0.0),
    _Stump('demand_pressure', 0.4, 0.4, 0.0),
    _Stump('skip_ratio', 0.65, -0.6, 0.0), // crowd is skipping ⇒ penalty
    // freshness & novelty
    _Stump('freshness', 0.6, 0.4, 0.0),
    _Stump('is_new_listing', 0.5, 0.3, 0.0),
    // location & access
    _Stump('centrality', 0.75, 0.4, 0.0),
    _Stump('transit_access', 0.5, 0.35, 0.0),
    _Stump('transit_density', 0.55, 0.3, 0.0), // real gov stop-density
    _Stump('socioeconomic', 0.66, 0.3, 0.0), // CBS cluster quality
    _Stump('rail_access', 0.5, 0.25, 0.0), // near rail/light-rail
    // amenities richness
    _Stump('weighted_amenity_score', 0.6, 0.45, 0.0),
    _Stump('condition_score', 0.8, 0.3, 0.0),
    // livability (real gov data)
    _Stump('safety', 0.6, 0.4, -0.15), // safer area boosts; unsafe penalizes
    // NOTE: the strong high-crime penalty was moved out of the static stump list
    // into _safetyPenalty() below, because a flat -0.45 cliff on `safety` alone
    // is a disproportionate, opaque sledgehammer. See _safetyPenalty for the
    // residential-denominator caveat and the SES/centrality gating.
    _Stump('school_access', 0.55, 0.25, 0.0), // education density
    _Stump('health_access', 0.5, 0.18, 0.0), // health facilities nearby
  ];

  // Interaction multipliers: AND-style boosts that pure stumps miss.
  static double _interactions(PropertyFeatureVector pfv) {
    double logit = 0;
    final value = pfv.valueScore;
    final trust = pfv.trust;
    final fresh = pfv.freshness;
    final demand = pfv.get('like_rate_wilson');

    // a verified, underpriced, fresh listing is a standout
    if (value > 0.65 && trust > 0.6 && fresh > 0.5) logit += 0.8;
    // great value the crowd already validates
    if (value > 0.6 && demand > 0.4) logit += 0.5;
    // central + near transit (commuter sweet-spot)
    if (pfv.centrality > 0.7 && pfv.transitAccess > 0.5) logit += 0.4;
    // overpriced AND being skipped is doubly bad
    if (pfv.get('hedonic_residual') < -0.3 && pfv.get('skip_ratio') > 0.6) {
      logit -= 0.7;
    }
    // family sweet-spot: safe + lots of schools + child-heavy demographics
    if (pfv.get('safety') > 0.6 &&
        pfv.get('school_access') > 0.5 &&
        pfv.get('demo_child') > 0.55) {
      logit += 0.5;
    }
    return logit;
  }

  // Gentle, gated penalty for high-crime areas.
  //
  // The `safety` signal = 1 − percentile(per-capita reported-crime rate) from
  // gov crime data. That per-capita rate uses a RESIDENTIAL-population
  // denominator, but offences accrue from a much larger daytime/commuter/
  // nightlife population. For flagship, high-density commercial cities
  // (e.g. Tel Aviv → safety ≈ 0.01) this systematically OVERSTATES residential
  // danger. The previous flat -0.45 cliff on `safety` alone silently buried
  // such listings on a single contested metric — bad for a tenant assistant.
  //
  // So we keep safety as a real signal but soften it three ways:
  //   1. Reduced magnitude: cap at -0.25 (was -0.45).
  //   2. Gradual ramp: scale with how far below the 0.3 threshold we are,
  //      instead of a hard cliff at the boundary.
  //   3. SES/centrality gating: a high-socioeconomic, high-centrality center
  //      (commercial/nightlife hub) gets the penalty attenuated, because its
  //      crime rate is inflated by the residential denominator. A genuinely
  //      distressed area (low SES AND low centrality) still gets the full,
  //      meaningful penalty.
  static double _safetyPenalty(PropertyFeatureVector pfv) {
    const threshold = 0.3;
    final safety = pfv.get('safety');
    if (safety >= threshold) return 0.0;

    // 0 at the threshold, 1 at safety == 0 → gradual ramp, no cliff.
    final severity = (threshold - safety) / threshold;
    const maxPenalty = 0.25; // softened from 0.45

    // Centrality + SES both default to a neutral 0.5 when absent.
    final ses = pfv.get('socioeconomic', 0.5);
    final centrality = pfv.get('centrality', 0.5);
    // High SES and/or high centrality ⇒ likely a commercial hub whose crime
    // rate is denominator-inflated ⇒ attenuate. Distressed areas (both low)
    // keep the full penalty (attenuation → 0).
    final hubness = math.max(ses, centrality); // 0 distressed … 1 prime center
    final attenuation = (hubness - 0.5).clamp(0.0, 0.5) / 0.5; // 0…1
    final gate = 1.0 - 0.7 * attenuation; // up to 70% relief for prime centers

    return -maxPenalty * severity * gate;
  }

  static double score(PropertyFeatureVector pfv) {
    double logit = -0.6; // base rate slightly below 0.5
    for (final s in _stumps) {
      final x = pfv.get(s.feature);
      logit += x >= s.threshold ? s.whenAbove : s.whenBelow;
    }
    logit += _interactions(pfv);
    logit += _safetyPenalty(pfv);
    return 1.0 / (1.0 + math.exp(-logit.clamp(-30.0, 30.0)));
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// CalibratedEnsemble — blend + calibrate
// ═════════════════════════════════════════════════════════════════════════════

class CalibratedEnsemble {
  const CalibratedEnsemble._();

  // Platt scaling parameters (spread the blended raw score across [0,1]).
  static const double _plattA = 4.2;
  static const double _plattB = -2.1;

  /// Combine component scores into a calibrated relevance, given the model's
  /// confidence (drives how much the learned/behavioral components are trusted).
  static double combine(
    Map<String, double> components,
    UserPreferenceModel model,
  ) {
    // base reliability weights per scorer.
    //
    // MAUT, TOPSIS and Cosine all measure the SAME construct — the alignment of a
    // listing's per-dimension satisfactions with the user's weights (Cosine is
    // essentially MAUT normalised by ‖s‖; TOPSIS is a batch-relative echo that
    // also drifts as the candidate pool changes). Blending all three just counted
    // one signal three times and manufactured false confidence. We keep MAUT as
    // the single canonical weighted-utility scorer and give it their COMBINED
    // weight (0.72) — so personalisation strength is unchanged — leaving three
    // genuinely orthogonal signals: MAUT (personalised linear utility), GBM
    // (query-independent nonlinear interactions) and the online learner (behaviour).
    final learnerConf = model.learner.confidence;
    // COLD START → WARM TRANSITION for the nonlinear-tree signal:
    //   • Before the on-device GBDT has trained, `gbdt` is absent and the static
    //     hand-tuned GBM carries the FULL 0.28 tree weight → behaviour is EXACTLY
    //     as it was historically (static GBM only).
    //   • Once the GBDT is ready, it TAKES OVER the nonlinear role with weight
    //     0.25, and the static GBM is de-weighted to a small 0.03 anchor so the
    //     two tree signals aren't double-counted (~0.28 total tree budget is
    //     preserved, MAUT/learner weights unchanged). The static GBM stays as a
    //     tiny domain-prior floor rather than dropping to zero.
    final gbdtReady = model.learner.gbdtReady;
    final weights = <String, double>{
      'maut': 0.72,
      'gbm': gbdtReady ? 0.03 : 0.28,
      if (gbdtReady) 'gbdt': 0.25,
      // the online learner earns trust only as it accumulates feedback
      'learner': 0.5 * learnerConf,
    };

    double num = 0, den = 0;
    weights.forEach((k, w) {
      final v = components[k];
      if (v != null && w > 0) {
        num += w * v;
        den += w;
      }
    });
    final raw = den > 0 ? num / den : 0.5;

    // Platt-style logistic calibration
    final calibrated =
        1.0 / (1.0 + math.exp(-(_plattA * raw + _plattB)));
    return calibrated.clamp(0.0, 1.0);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// RankingEngine — orchestrates all scorers over the candidate set
// ═════════════════════════════════════════════════════════════════════════════

class RankingEngine {
  const RankingEngine._();

  /// Score & sort all candidates. Returns descending by final relevance.
  static List<RankedCandidate> rank(
    List<PropertyFeatureVector> pfvs,
    UserPreferenceModel model,
  ) {
    if (pfvs.isEmpty) return const [];

    final out = <RankedCandidate>[];
    for (var i = 0; i < pfvs.length; i++) {
      final pfv = pfvs[i];

      final (maut, contrib) = MautScorer.score(pfv, model);
      final gbm = GradientBoostedScorer.score(pfv);
      final learnerFeats = model.learnerFeatures(pfv);
      final learner = model.learner.confidence > 0.05
          ? model.learner.predict(learnerFeats)
          : maut; // cold learner defers to MAUT

      final components = <String, double>{
        'maut': maut,
        'gbm': gbm,
        'learner': learner,
      };
      // Learned on-device GBDT: only present once it has trained on enough real
      // swipes. Reuses the SAME feature vector the FTRL learner consumed.
      if (model.learner.gbdtReady) {
        components['gbdt'] =
            model.learner.gbdtPredict(model.learner.vectorizeFeatures(learnerFeats));
      }

      final blended = CalibratedEnsemble.combine(components, model);
      final constraint = model.constraints.softSatisfaction(pfv.property);
      final strict = model.constraints.strictlySatisfied(pfv.property);

      // gate by soft constraint satisfaction (never zero ⇒ never dead-ends)
      final finalScore = (blended * constraint).clamp(0.0, 1.0);

      out.add(RankedCandidate(
        pfv: pfv,
        score: finalScore,
        components: components,
        dimensionContrib: contrib,
        constraintSatisfaction: constraint,
        strictMatch: strict,
      ));
    }

    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }
}
