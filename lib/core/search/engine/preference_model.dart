// ════════════════════════════════════════════════════════════════════════════
// PART 2 / 4 — PREFERENCE MODELING & USER INTENT
// ════════════════════════════════════════════════════════════════════════════
//
// Converts the user's stated intent (SearchQuery), stored profile (TenantProfile)
// and the live MarketContext into a quantitative, uncertainty-aware preference
// model the ranking engine (Part 3) can evaluate against any property.
//
// Components:
//   • AttributeUtility       — single-attribute satisfaction functions u(x)∈[0,1]
//                              (Gaussian / Sigmoid / Budget / Range / Linear).
//   • BayesianWeight         — a Normal(μ,σ²) belief over each dimension's
//                              importance; stated preferences sharpen it.
//   • HardConstraints        — city / budget / rooms / must-haves / deal-breakers,
//                              expressed as SOFT, relaxable penalties (never a
//                              hard zero ⇒ the assistant never dead-ends).
//   • OnlineLogisticLearner  — FTRL-Proximal logistic regression that learns from
//                              like/skip feedback over time.
//   • UserPreferenceModel    — the assembled object, with satisfaction() per
//                              dimension and posterior weights + uncertainty.
//   • PreferenceModelBuilder — constructs the model from query+profile+market.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:dating_app/core/finance/monthly_cost.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/finance/rental_yield.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/gbdt.dart';
import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:dating_app/core/search/scenario_layers.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/profile_tags.dart';
import 'package:dating_app/data/models/rental_models.dart';

// Canonical scoring dimensions. Parts 2/3/4 iterate this exact list so weights,
// utilities and attributions stay aligned.
const List<String> kScoringDimensions = [
  'location',
  'neighborhood', // CBS socioeconomic quality of the locality (gov data)
  'safety', // per-capita crime safety (police data)
  'budget',
  'value',
  'size',
  'amenities',
  'transit',
  'condition',
  'freshness',
  'popularity',
  'trust',
  'schools', // CBS education-institution density around the property (gov data)
  'family', // CBS share of children 0-19 — family-friendliness of the locality
  'health', // CBS health-facility availability for the locality (gov data)
  'coast', // proximity to the sea — weighted only on beach intent
  'park', // proximity to a public park/garden — weighted for families/kids
  'religious_area', // observant community — weighted only on a religious intent
  'school_young', // proximity to גן/יסודי — weighted for young kids
  'school_teen', // proximity to חטיבה/תיכון — weighted for teens
  'nightlife', // real bar/pub/café density — weighted on a nightlife/vibrant intent
  'yield', // gross rental yield (sale listings) — weighted only on investment intent
  'university', // proximity to a university/college — weighted on student intent
  'young_area', // CBS share of young adults — weighted on young/nightlife intent
  'senior_area', // CBS share of seniors — weighted on quiet/retiree intent
  'luxury', // luxury-amenity tier — weighted on premium intent
  'view', // floor height (view) — weighted on view/high-floor intent
  'spaciousness', // m² per room — weighted on "מרווח" / roommate / WFH intent
  'accessibility', // elevator or low floor — weighted on elderly/stroller/wheelchair
  'convenience', // supermarkets + shopping centres nearby — weighted on errands intent
  'low_noise', // distance from a major road/rail (physical quiet) — on a quiet intent
  'future_value', // proximity to planned metro/light-rail + urban renewal — investor upside
  'employment', // job-place density nearby (short-commute proxy) — on a near-work intent
  'low_floor', // a low floor itself (not just an elevator) — on a "קומה נמוכה" intent
];

// The EXACT feature ordering the on-device GBDT consumes: the same 'bias' + all
// scoring dimensions the FTRL learnerFeatures() map emits, flattened to a dense
// vector in this fixed order so every training row and every prediction align.
const List<String> kGbdtFeatureOrder = ['bias', ...kScoringDimensions];

// ═════════════════════════════════════════════════════════════════════════════
// AttributeUtility — single-attribute satisfaction functions
// ═════════════════════════════════════════════════════════════════════════════

abstract class AttributeUtility {
  const AttributeUtility();

  /// Satisfaction in [0,1] for an input value [x] (units depend on the dim).
  double utility(double x);
}

/// Peaks at [center], falls off with a Gaussian of width [tolerance].
class GaussianPreferenceUtility extends AttributeUtility {
  const GaussianPreferenceUtility(this.center, this.tolerance);
  final double center;
  final double tolerance;

  @override
  double utility(double x) {
    final t = tolerance < 1e-6 ? 1e-6 : tolerance;
    final d = x - center;
    return math.exp(-(d * d) / (2 * t * t));
  }
}

/// Logistic satisfaction around a [threshold]. ascending=true ⇒ more is better.
class SigmoidThresholdUtility extends AttributeUtility {
  const SigmoidThresholdUtility(
    this.threshold,
    this.steepness, {
    this.ascending = true,
  });
  final double threshold;
  final double steepness;
  final bool ascending;

  @override
  double utility(double x) {
    final s = 1.0 / (1.0 + math.exp(-steepness * (x - threshold)));
    return ascending ? s : 1.0 - s;
  }
}

/// 1.0 at or under [maxBudget]; decays above it at a rate set by [elasticity]
/// (0 = rigid, 1 = very flexible). Optionally rewards being well under budget.
class BudgetUtility extends AttributeUtility {
  const BudgetUtility(this.maxBudget, this.elasticity, {this.minBudget = 0});
  final double maxBudget;
  final double elasticity;
  final double minBudget;

  @override
  double utility(double price) {
    if (maxBudget <= 0) return 0.5;
    if (price <= 0) return 0.5;
    // below a stated floor ⇒ mild penalty (often signals a mismatch/too-cheap)
    if (minBudget > 0 && price < minBudget) {
      final under = (minBudget - price) / minBudget;
      return (1.0 - 0.4 * under.clamp(0.0, 1.0)).clamp(0.0, 1.0);
    }
    final r = price / maxBudget;
    if (r <= 1.0) return 1.0;
    final over = r - 1.0;
    final tolerance = 0.04 + elasticity * 0.26; // 4%..30% over budget tolerated
    return math.exp(-over / tolerance).clamp(0.0, 1.0);
  }
}

/// 1.0 inside [lo,hi]; linear decay outside, reaching 0 after the slack.
class RangeUtility extends AttributeUtility {
  const RangeUtility(
    this.lo,
    this.hi, {
    this.slackBelow = 1.0,
    this.slackAbove = 2.0,
  });
  final double lo;
  final double hi;
  final double slackBelow;
  final double slackAbove;

  @override
  double utility(double x) {
    if (x >= lo && x <= hi) return 1.0;
    if (x < lo) {
      final d = lo - x;
      return (1.0 - d / (slackBelow < 1e-6 ? 1e-6 : slackBelow)).clamp(0.0, 1.0);
    }
    final d = x - hi;
    return (1.0 - d / (slackAbove < 1e-6 ? 1e-6 : slackAbove)).clamp(0.0, 1.0);
  }
}

/// Identity (ascending) or 1-x (descending) for inputs already in [0,1].
class LinearUtility extends AttributeUtility {
  const LinearUtility({this.ascending = true});
  final bool ascending;

  @override
  double utility(double x) {
    final c = x.clamp(0.0, 1.0);
    return ascending ? c : 1.0 - c;
  }
}

/// Always returns a constant — used for dimensions the user is neutral about.
class ConstantUtility extends AttributeUtility {
  const ConstantUtility(this.value);
  final double value;
  @override
  double utility(double x) => value;
}

// ═════════════════════════════════════════════════════════════════════════════
// BayesianWeight — Normal belief over a dimension's importance
//
// Prior μ₀,σ₀². Each stated preference is an observation that pulls μ toward an
// evidence value and shrinks σ (conjugate Normal-Normal update with known
// observation precision). The posterior mean is the working weight; the
// posterior std drives exploration (Thompson sampling) in Part 4.
// ═════════════════════════════════════════════════════════════════════════════

class BayesianWeight {
  BayesianWeight(this.mean, this.variance);

  double mean;
  double variance;

  double get std => math.sqrt(variance < 0 ? 0 : variance);

  /// Conjugate update toward [evidenceMean] with observation [precision]
  /// (= 1/σ_obs²). Higher precision ⇒ stronger, more certain pull.
  void observe(double evidenceMean, double precision) {
    final priorPrecision = variance < 1e-9 ? 1e9 : 1.0 / variance;
    final postPrecision = priorPrecision + precision;
    mean = (mean * priorPrecision + evidenceMean * precision) / postPrecision;
    variance = 1.0 / postPrecision;
  }

  /// Draw a sample from N(μ,σ²) using Box–Muller, with [rng].
  double sample(math.Random rng) {
    final u1 = math.max(1e-12, rng.nextDouble());
    final u2 = rng.nextDouble();
    final g = math.sqrt(-2 * math.log(u1)) * math.cos(2 * math.pi * u2);
    return mean + std * g;
  }

  BayesianWeight clone() => BayesianWeight(mean, variance);
}

// ═════════════════════════════════════════════════════════════════════════════
// HardConstraints — soft, relaxable gating
// ═════════════════════════════════════════════════════════════════════════════

class HardConstraints {
  HardConstraints({
    this.city,
    this.minPrice,
    this.maxPrice,
    this.minRooms,
    this.maxRooms,
    Set<String>? requiredFeatures,
    Set<String>? dealBreakers,
    this.propertyType,
  })  : requiredFeatures = requiredFeatures ?? const {},
        dealBreakers = dealBreakers ?? const {};

  final String? city;
  final int? minPrice;
  final int? maxPrice;
  final double? minRooms;
  final double? maxRooms;
  final Set<String> requiredFeatures; // canonical catalogue keys
  final Set<String> dealBreakers; // canonical catalogue keys (must be absent)
  final String? propertyType;

  /// A multiplicative satisfaction in (0,1]: 1.0 = all constraints met. Each
  /// violation multiplies by a penalty <1 (severe for hard misses, mild for
  /// soft ones) but never reaches 0 — so a near-miss still surfaces rather than
  /// dead-ending the search.
  double softSatisfaction(RentalProperty p) {
    double m = 1.0;

    if (city != null && city!.trim().isNotEmpty) {
      final hay = '${p.city} ${p.neighborhood}';
      if (!hay.contains(city!.trim())) m *= 0.45; // wrong city: heavy but soft
    }

    if (maxPrice != null && p.price > maxPrice!) {
      final over = (p.price - maxPrice!) / maxPrice!;
      m *= math.exp(-over * 2.2).clamp(0.15, 1.0);
    }
    if (minPrice != null && p.price > 0 && p.price < minPrice!) {
      m *= 0.85;
    }

    if (minRooms != null && p.rooms < minRooms!) {
      final d = minRooms! - p.rooms;
      m *= (1.0 - 0.3 * d).clamp(0.3, 1.0);
    }
    if (maxRooms != null && p.rooms > maxRooms!) {
      final d = p.rooms - maxRooms!;
      m *= (1.0 - 0.18 * d).clamp(0.45, 1.0);
    }

    if (propertyType != null && propertyType!.trim().isNotEmpty) {
      final pt = propertyType!.trim();
      if (!(p.propertyType.contains(pt) || pt.contains(p.propertyType))) {
        m *= 0.7;
      }
    }

    for (final key in requiredFeatures) {
      if (!propertyHasFeature(p, key)) m *= 0.55; // missing must-have
    }
    for (final key in dealBreakers) {
      if (propertyHasFeature(p, key)) m *= 0.3; // has a deal-breaker
    }

    return m.clamp(0.05, 1.0);
  }

  /// True if every hard constraint is strictly satisfied (used for the "exact"
  /// flag and for funnel telemetry — NOT for filtering).
  bool strictlySatisfied(RentalProperty p) {
    if (city != null &&
        city!.trim().isNotEmpty &&
        !'${p.city} ${p.neighborhood}'.contains(city!.trim())) {
      return false;
    }
    if (maxPrice != null && p.price > maxPrice!) return false;
    if (minPrice != null && p.price > 0 && p.price < minPrice!) return false;
    if (minRooms != null && p.rooms < minRooms!) return false;
    if (maxRooms != null && p.rooms > maxRooms!) return false;
    for (final key in requiredFeatures) {
      if (!propertyHasFeature(p, key)) return false;
    }
    for (final key in dealBreakers) {
      if (propertyHasFeature(p, key)) return false;
    }
    return true;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// OnlineLogisticLearner — FTRL-Proximal logistic regression
//
// Learns P(like | features) online from streaming feedback. Sparse, regularized,
// and cheap — ideal for on-device personalization that improves as the user
// swipes. Reference: McMahan et al., "Ad Click Prediction: a View from the
// Trenches" (KDD 2013).
// ═════════════════════════════════════════════════════════════════════════════

class OnlineLogisticLearner {
  OnlineLogisticLearner({
    this.alpha = 0.1, // learning-rate scale
    this.beta = 1.0, // learning-rate smoothing
    this.l1 = 0.0, // L1 regularization (sparsity)
    this.l2 = 0.05, // L2 regularization (shrinkage)
  });

  final double alpha;
  final double beta;
  final double l1;
  final double l2;

  final Map<String, double> _z = {}; // accumulated gradient (with lazy reg)
  final Map<String, double> _n = {}; // accumulated squared gradient
  int updates = 0;

  // ── On-device GBDT (learned NONLINEAR ranker) ──────────────────────────────
  // Every FTRL update() ALSO appends (features,label) to a bounded ring-buffer.
  // Once ~120 labelled swipes accrue (and every ~40 after) we (re)train a small
  // gradient-boosted regression-tree model that captures nonlinear interactions
  // the linear FTRL can't. The buffer is capped so memory + train cost stay flat;
  // the buffer itself is NOT persisted (it re-accumulates from swipes) but the
  // trained model IS (see toJson/fromJson) so predictions survive a restart.
  static const int _gbdtBufferCap = 1500;
  static const int _gbdtMinToTrain = 120;
  static const int _gbdtTrainEvery = 40;
  final List<List<double>> _gbBufX = [];
  final List<double> _gbBufY = [];
  int _gbSinceTrain = 0;
  GbdtModel? _gbdt;

  /// Current per-feature weight (lazily materialized from z,n).
  double _weight(String k) {
    final z = _z[k] ?? 0.0;
    if (z.abs() <= l1) return 0.0;
    final n = _n[k] ?? 0.0;
    final sign = z < 0 ? -1.0 : 1.0;
    return -(z - sign * l1) / ((beta + math.sqrt(n)) / alpha + l2);
  }

  /// Probability the user likes a property with these features.
  double predict(Map<String, double> x) {
    double wtx = 0.0;
    for (final entry in x.entries) {
      wtx += _weight(entry.key) * entry.value;
    }
    return 1.0 / (1.0 + math.exp(-wtx.clamp(-30.0, 30.0)));
  }

  /// One FTRL update toward label [y]∈{0,1} (like=1, skip=0).
  void update(Map<String, double> x, double y) {
    final p = predict(x);
    final g = p - y; // gradient of logloss wrt wtx
    for (final entry in x.entries) {
      final k = entry.key;
      final xi = entry.value;
      final gi = g * xi;
      final nPrev = _n[k] ?? 0.0;
      final sigma =
          (math.sqrt(nPrev + gi * gi) - math.sqrt(nPrev)) / alpha;
      _z[k] = (_z[k] ?? 0.0) + gi - sigma * _weight(k);
      _n[k] = nPrev + gi * gi;
    }
    updates++;
    // Same feedback also trains the on-device GBDT (buffer + periodic refit).
    _bufferAndMaybeTrainGbdt(x, y);
  }

  /// Confidence in the learner's own predictions, growing with #updates.
  double get confidence => 1.0 - math.exp(-updates / 25.0);

  // ── GBDT plumbing ──────────────────────────────────────────────────────────

  /// Flatten a learnerFeatures() map into the dense GBDT vector (fixed order).
  List<double> vectorizeFeatures(Map<String, double> x) =>
      [for (final k in kGbdtFeatureOrder) x[k] ?? 0.0];

  /// True once the on-device GBDT has trained on enough labelled swipes.
  bool get gbdtReady => _gbdt?.isTrained ?? false;

  /// GBDT relevance in [0,1] for a dense vector (see [vectorizeFeatures]).
  /// Returns a neutral 0.5 before the model is ready.
  double gbdtPredict(List<double> feats) => _gbdt?.predict(feats) ?? 0.5;

  void _bufferAndMaybeTrainGbdt(Map<String, double> x, double y) {
    _gbBufX.add(vectorizeFeatures(x));
    _gbBufY.add(y.clamp(0.0, 1.0));
    if (_gbBufX.length > _gbdtBufferCap) {
      _gbBufX.removeAt(0); // drop oldest ⇒ a rolling window of recent behaviour
      _gbBufY.removeAt(0);
    }
    _gbSinceTrain++;
    if (_gbBufX.length >= _gbdtMinToTrain &&
        (_gbdt == null || _gbSinceTrain >= _gbdtTrainEvery)) {
      final m = GbdtModel()..train(_gbBufX, _gbBufY);
      if (m.isTrained) _gbdt = m;
      _gbSinceTrain = 0;
    }
  }

  Map<String, double> snapshotWeights(Iterable<String> keys) =>
      {for (final k in keys) k: _weight(k)};

  /// Serialize the LEARNED state (z, n, updates) for cross-session persistence.
  /// Hyper-params (alpha/beta/l1/l2) are fixed config and are NOT stored. The
  /// trained GBDT is folded in here too (when present) so the existing
  /// _learner.toJson() persistence hook carries it with zero caller changes; the
  /// raw training buffer is intentionally omitted (it re-accumulates on swipes).
  Map<String, dynamic> toJson() => {
        'z': _z,
        'n': _n,
        'u': updates,
        if (_gbdt != null) 'gbdt': _gbdt!.toJson(),
      };

  /// Restore a learner from [toJson]. Unknown/absent fields degrade to an empty
  /// (cold) learner, so a corrupt or version-changed blob can never throw.
  factory OnlineLogisticLearner.fromJson(Map<String, dynamic> j) {
    final l = OnlineLogisticLearner();
    void load(Map<String, double> into, dynamic raw) {
      if (raw is Map) {
        raw.forEach((k, v) {
          final d = v is num ? v.toDouble() : double.tryParse('$v');
          if (d != null && d.isFinite) into['$k'] = d;
        });
      }
    }
    load(l._z, j['z']);
    load(l._n, j['n']);
    final u = j['u'];
    l.updates = u is int ? u : (u is num ? u.toInt() : 0);
    final g = j['gbdt'];
    if (g is Map) {
      l._gbdt = GbdtModel.fromJson(Map<String, dynamic>.from(g));
    }
    return l;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// UserPreferenceModel — the assembled, queryable model
// ═════════════════════════════════════════════════════════════════════════════

class UserPreferenceModel {
  UserPreferenceModel({
    required this.weights,
    required this.utilities,
    required this.constraints,
    required this.requestedAmenityKeys,
    required this.learner,
    required this.maxBudget,
    required this.desiredRooms,
    required this.statedDimensions,
  });

  final Map<String, BayesianWeight> weights;
  final Map<String, AttributeUtility> utilities;
  final HardConstraints constraints;
  final Set<String> requestedAmenityKeys; // canonical catalogue keys
  final OnlineLogisticLearner learner;
  final double maxBudget;
  final double? desiredRooms;

  /// Dimensions the user explicitly addressed (drives confidence + explanations).
  final Set<String> statedDimensions;

  /// Working (posterior-mean) weight for a dimension.
  double weight(String dim) => weights[dim]?.mean ?? 0.0;

  /// Posterior uncertainty for a dimension (for exploration).
  double uncertainty(String dim) => weights[dim]?.std ?? 0.0;

  /// Sum of weights (for normalization).
  double get weightSum =>
      kScoringDimensions.fold(0.0, (s, d) => s + weight(d));

  /// The raw value fed into dimension [dim]'s utility for property [pfv].
  double dimensionValue(String dim, PropertyFeatureVector pfv) {
    switch (dim) {
      case 'location':
        return pfv.centrality;
      case 'neighborhood':
        return pfv.get('socioeconomic', 0.5);
      case 'safety':
        return pfv.get('safety', 0.5);
      case 'budget':
        // Sale listings: the price is a purchase price, not a monthly cost.
        if (pfv.property.transactionType == PropertyTransactionType.sale) {
          return pfv.property.price.toDouble();
        }
        // Judge the TRUE monthly cost (rent + arnona + vaad), not just rent, so
        // two listings at the same rent but different size/city rank by what the
        // tenant actually pays. Falls back to rent when size is unknown.
        return MonthlyCost.estimate(
              rent: pfv.property.price,
              sizeM2: pfv.property.sizeM2,
              city: pfv.property.city,
            )?.total.toDouble() ??
            pfv.property.price.toDouble();
      case 'value':
        return pfv.valueScore;
      case 'size':
        return pfv.get('rooms');
      case 'amenities':
        return _amenitySatisfaction(pfv); // already a [0,1] satisfaction
      case 'transit':
        return pfv.transitAccess;
      case 'condition':
        return pfv.get('condition_score');
      case 'freshness':
        return pfv.freshness;
      case 'popularity':
        return 0.6 * pfv.popularity + 0.4 * pfv.get('like_rate_wilson');
      case 'trust':
        return pfv.trust;
      // ── gov-data livability dimensions (flat keys from FeatureEngineer) ──────
      case 'schools':
        return pfv.get('school_access', 0.5).clamp(0.0, 1.0);
      case 'family':
        return pfv.get('demo_child', 0.5).clamp(0.0, 1.0);
      case 'health':
        return pfv.get('health_access', 0.5).clamp(0.0, 1.0);
      case 'convenience':
        return pfv.get('retail_access', 0.0).clamp(0.0, 1.0);
      case 'low_noise':
        return pfv.get('low_noise', 0.5).clamp(0.0, 1.0);
      case 'future_value':
        return pfv.get('future_value', 0.0).clamp(0.0, 1.0);
      case 'employment':
        return pfv.get('employment_access', 0.0).clamp(0.0, 1.0);
      case 'coast':
        return pfv.get('coast_access', 0.0).clamp(0.0, 1.0);
      case 'park':
        return pfv.get('park_access', 0.0).clamp(0.0, 1.0);
      case 'religious_area':
        return pfv.get('religious_area', 0.0).clamp(0.0, 1.0);
      case 'school_young':
        return pfv.get('school_young_prox', 0.0).clamp(0.0, 1.0);
      case 'school_teen':
        return pfv.get('school_teen_prox', 0.0).clamp(0.0, 1.0);
      case 'nightlife':
        return pfv.get('nightlife', 0.0).clamp(0.0, 1.0);
      case 'yield':
        // Sale listings only; rentals stay neutral (weight is 0 there anyway).
        final est = RentalYield.estimate(
          salePrice: pfv.property.price,
          sizeM2: pfv.property.sizeM2,
          city: pfv.property.city,
        );
        if (est == null) return 0.5;
        return ((est.grossYieldPct - 2.0) / 3.0).clamp(0.0, 1.0);
      case 'university':
        return pfv.get('university_access', 0.0).clamp(0.0, 1.0);
      case 'young_area':
        return pfv.get('demo_young', 0.5).clamp(0.0, 1.0);
      case 'senior_area':
        return pfv.get('demo_senior', 0.5).clamp(0.0, 1.0);
      case 'luxury':
        // "Premium" = upscale + comfort amenities, priced above the local market.
        // luxury_amenities is count/6 and comfort is count/8 (both harsh), so
        // recover the raw counts: ~4 nice features already reads as premium.
        final luxCount = pfv.get('luxury_amenities', 0.0) * 6;
        final comfortCount = pfv.get('comfort_amenities', 0.0) * 8;
        final amen = ((luxCount + comfortCount) / 4).clamp(0.0, 1.0);
        final pricey = pfv.get('price_per_sqm_percentile', 0.5);
        return (0.55 * amen + 0.45 * pricey).clamp(0.0, 1.0);
      case 'view':
        // Higher floor ⇒ better view; ~12th floor saturates to 1.
        return (pfv.get('floor_num', 0.0) / 12.0).clamp(0.0, 1.0);
      case 'spaciousness':
        // m² per room, on a scale where ~12 reads as cramped and ~30 as very
        // roomy — so a genuinely small flat scores low (and gets flagged) when
        // "מרווחת" was asked, while a moderate one stays mid.
        return ((pfv.get('size_per_room', 20.0) - 12.0) / 18.0).clamp(0.0, 1.0);
      case 'low_floor':
        // A LOW floor itself (independent of an elevator) — floor 0→1, ~8th→0.
        return (1.0 - pfv.get('floor_num', 0.0) / 8.0).clamp(0.0, 1.0);
      case 'accessibility':
        // Step-free access: an elevator makes any floor accessible; otherwise a
        // ground/low floor is fine, a walk-up higher up is near-unusable.
        if (propertyHasFeature(pfv.property, 'elevator')) return 1.0;
        final floor = pfv.get('floor_num', 0.0);
        if (floor <= 0) return 0.9; // ground floor, step-free
        if (floor <= 1) return 0.7;
        if (floor <= 2) return 0.35;
        return 0.05; // 3rd+ walk-up
      default:
        return 0.5;
    }
  }

  /// Satisfaction ∈[0,1] of property [pfv] on dimension [dim].
  double satisfaction(String dim, PropertyFeatureVector pfv) {
    final u = utilities[dim] ?? const ConstantUtility(0.5);
    // 'amenities' value is already a satisfaction; pass through the utility too
    // so the elasticity/strength still shapes it.
    return u.utility(dimensionValue(dim, pfv)).clamp(0.0, 1.0);
  }

  // Coverage of the user's requested amenities, blended with rarity-weighted
  // richness when nothing specific was asked for.
  double _amenitySatisfaction(PropertyFeatureVector pfv) {
    if (requestedAmenityKeys.isEmpty) {
      return pfv.get('weighted_amenity_score', 0.4);
    }
    var present = 0;
    for (final key in requestedAmenityKeys) {
      if (propertyHasFeature(pfv.property, key)) present++;
    }
    final coverage = present / requestedAmenityKeys.length;
    // reward full coverage strongly, partial coverage proportionally, plus a
    // small bonus for extra richness beyond what was asked.
    return (0.85 * coverage + 0.15 * pfv.get('weighted_amenity_score'))
        .clamp(0.0, 1.0);
  }

  /// Feature map for the online learner (compact, dimension-aligned).
  Map<String, double> learnerFeatures(PropertyFeatureVector pfv) {
    final m = <String, double>{'bias': 1.0};
    for (final dim in kScoringDimensions) {
      m[dim] = satisfaction(dim, pfv);
    }
    return m;
  }

  /// Apply a like/skip observation, updating the online learner AND nudging the
  /// Bayesian weights of the dimensions the property scored extreme on.
  void registerFeedback(PropertyFeatureVector pfv, bool liked) {
    final feats = learnerFeatures(pfv);
    learner.update(feats, liked ? 1.0 : 0.0);

    // Credit assignment: if the user liked a property that scored high on a
    // dimension, that dimension probably matters (raise its weight belief).
    for (final dim in kScoringDimensions) {
      final sat = satisfaction(dim, pfv);
      if (sat > 0.7 || sat < 0.3) {
        final evidence = liked ? sat : (1.0 - sat);
        // weak precision so behavior accumulates gradually
        weights[dim]?.observe(evidence, 0.4);
      }
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PreferenceModelBuilder — assemble the model from intent + profile + market
// ═════════════════════════════════════════════════════════════════════════════

class PreferenceModelBuilder {
  const PreferenceModelBuilder._();

  // Prior importance of each dimension before any user signal.
  static const Map<String, double> _priorMean = {
    'location': 0.55,
    'neighborhood': 0.35,
    'safety': 0.5,
    'budget': 0.85,
    'value': 0.6,
    'size': 0.6,
    'amenities': 0.4,
    'transit': 0.35,
    'condition': 0.4,
    'freshness': 0.3,
    'popularity': 0.3,
    'trust': 0.45,
    // gov-data livability: non-zero so they always contribute a little, then
    // persona-boosted below when the tenant signals a family / young household.
    'schools': 0.3,
    'family': 0.3,
    'health': 0.3,
    // Off by default — they only matter once the user's intent turns them on
    // (beach / investment / student / young / quiet / luxury / view), so they
    // don't skew ordinary searches.
    'coast': 0.0,
    'park': 0.0,
    'religious_area': 0.0,
    'school_young': 0.0,
    'school_teen': 0.0,
    'nightlife': 0.0,
    'yield': 0.0,
    'university': 0.0,
    'young_area': 0.0,
    'senior_area': 0.0,
    'luxury': 0.0,
    'view': 0.0,
    'spaciousness': 0.0,
    'accessibility': 0.0,
    'convenience': 0.0, // off until an errands/shopping intent turns it on
    'low_noise': 0.0, // off until a quiet intent turns it on
    'future_value': 0.0, // off until an investment/growth intent turns it on
    'employment': 0.0, // off until a near-work intent turns it on
    'low_floor': 0.0, // off until a "קומה נמוכה" intent turns it on
  };
  static const double _priorVariance = 0.09; // σ≈0.3 — fairly uncertain prior

  /// Maps the assistant's friendly factor names → internal scoring dimensions.
  /// The model may also address a dimension by its own name. This is the shared
  /// vocabulary the assistant is instructed to use when it assigns importances.
  static const Map<String, String> factorToDimension = {
    'budget': 'budget', 'price': 'budget', 'affordability': 'budget',
    'location': 'location', 'central': 'location', 'centrality': 'location',
    'neighborhood': 'neighborhood', 'area_quality': 'neighborhood',
    'quality_area': 'neighborhood',
    'safety': 'safety',
    'value': 'value',
    'size': 'size', 'rooms': 'size',
    'amenities': 'amenities', 'features': 'amenities',
    'transit': 'transit', 'public_transport': 'transit',
    'condition': 'condition',
    'schools': 'schools', 'good_schools': 'schools',
    'family': 'family', 'family_area': 'family',
    'health': 'health',
    'near_sea': 'coast', 'sea': 'coast', 'beach': 'coast', 'coast': 'coast',
    'yield': 'yield', 'investment': 'yield',
    'university': 'university', 'campus': 'university',
    'nightlife': 'young_area', 'young_area': 'young_area', 'vibrant': 'young_area',
    'quiet': 'senior_area', 'senior_area': 'senior_area', 'calm': 'senior_area',
    'luxury': 'luxury', 'premium': 'luxury',
    'view': 'view',
    'spacious': 'spaciousness', 'spaciousness': 'spaciousness',
    'accessible': 'accessibility', 'accessibility': 'accessibility',
  };

  /// The importance the assistant assigned to [dim] (0 if it didn't mention it) —
  /// the max over any factor name that maps to this dimension, or the dimension
  /// name used directly.
  static double llmWeightForDim(String dim, Map<String, double> llm) {
    double best = (llm[dim] ?? 0.0).toDouble();
    for (final e in factorToDimension.entries) {
      if (e.value == dim) {
        final v = llm[e.key];
        if (v != null && v > best) best = v;
      }
    }
    return best.clamp(0.0, 1.0);
  }

  static UserPreferenceModel build({
    required SearchQuery query,
    TenantProfile? profile,
    required MarketContext market,
    OnlineLogisticLearner? learner,
  }) {
    final stated = <String>{};

    // ── resolve targets ───────────────────────────────────────────────────────
    final maxBudget = (query.maxPrice ??
            profile?.budgetMax ??
            (market.medianPrice > 0 ? (market.medianPrice * 1.1).round() : 8000))
        .toDouble();
    final minBudget = query.minPrice;
    final cheap = query.cheapPreference;

    final desiredRoomsLo = query.minRooms ?? profile?.desiredRooms;
    final desiredRoomsHi = query.maxRooms ??
        (profile?.desiredRooms != null ? profile!.desiredRooms + 1 : null);

    // requested amenities → canonical keys
    final requested = <String>{
      for (final a in query.amenities) canonicalFeatureKey(a),
    };

    // A curated profile's dealBreakers are NON-NEGOTIABLE preferences — the model
    // (see TenantProfile doc) treats a MISSING counterpart as a heavy penalty, so
    // they are REQUIRED features, not "must be absent". Their free-text Hebrew
    // labels ('נגישות'/'מעלית'/'ממ"ד') are mapped through the amenity lexicon —
    // without this the profile silently never touched ranking. importantDetails
    // feature mentions fold in as softer (non-negotiable-only for dealBreakers).
    for (final label in (profile?.dealBreakers ?? const [])) {
      for (final k in SmartSearch.amenityKeysIn(label)) {
        requested.add(canonicalFeatureKey(k));
      }
    }

    // No genuine "must NOT have X" source exists today (the profile field is
    // must-HAVE), so the must-be-absent set stays empty.
    const dealBreakers = <String>{};

    // ── weights: prior, then sharpen with stated evidence ────────────────────
    final weights = <String, BayesianWeight>{
      for (final dim in kScoringDimensions)
        dim: BayesianWeight(_priorMean[dim] ?? 0.4, _priorVariance),
    };

    void sharpen(String dim, double toward, double precision) {
      weights[dim]?.observe(toward, precision);
      stated.add(dim);
    }

    // budget always matters; a stated budget makes it near-certain
    if (query.maxPrice != null || profile?.budgetMax != null) {
      sharpen('budget', 0.95, 6.0);
      sharpen('value', cheap ? 0.9 : 0.7, 3.0);
    }
    if (cheap) {
      sharpen('value', 0.95, 6.0);
      sharpen('budget', 0.95, 4.0);
    }
    if (query.city != null && query.city!.trim().isNotEmpty) {
      sharpen('location', 0.9, 5.0);
      sharpen('neighborhood', 0.6, 1.5); // naming a place ⇒ character matters
    }
    if (query.neighborhood != null && query.neighborhood!.trim().isNotEmpty) {
      sharpen('location', 0.95, 6.0);
      sharpen('neighborhood', 0.7, 2.0);
    }
    if (desiredRoomsLo != null || desiredRoomsHi != null) {
      sharpen('size', 0.85, 4.0);
    }
    if (requested.isNotEmpty) {
      sharpen('amenities', (0.6 + 0.1 * requested.length).clamp(0.6, 0.97), 5.0);
    }
    if (query.nearTrain) {
      // Explicitly asking to be near transit is a top-tier criterion, not a nudge.
      sharpen('transit', 0.95, 12.0);
    }
    // ── intent-driven weights — CONSUME the structured SearchIntent contract ──
    // The model never re-parses free text; SmartSearch / the voice assistant have
    // already distilled the conversation into `query.intents`. An explicitly-
    // requested lifestyle factor is a top-tier weight (≈value/size), not a nudge.
    final intents = query.intents;
    if (intents.contains(SearchIntent.nearSea)) sharpen('coast', 0.97, 18.0);
    if (intents.contains(SearchIntent.investment)) {
      sharpen('yield', 0.95, 12.0);
      sharpen('future_value', 0.85, 7.0); // an investor cares about upside/appreciation
    }
    if (intents.contains(SearchIntent.growth)) {
      sharpen('future_value', 0.95, 12.0); // explicitly asked for upside/appreciation
    }
    if (intents.contains(SearchIntent.nearUniversity)) {
      sharpen('university', 0.95, 12.0);
      sharpen('young_area', 0.85, 6.0);
    }
    if (intents.contains(SearchIntent.nightlife)) {
      // REAL bar/pub/café density is the strongest signal; young demographics +
      // centrality reinforce it.
      sharpen('nightlife', 0.95, 14.0);
      sharpen('young_area', 0.92, 8.0);
      sharpen('location', 0.7, 3.0); // vibrant areas are central
    }
    if (intents.contains(SearchIntent.quiet)) {
      sharpen('senior_area', 0.95, 10.0); // demographic (calm, older) proxy
      sharpen('low_noise', 0.95, 12.0); // physical — far from a major road/rail
    }
    if (intents.contains(SearchIntent.luxury)) {
      // "יוקרה" is the DOMINANT ask — weight it hard so a plain cheap flat can't
      // tie a pool/gym penthouse on fit%. Space + a high floor (view) are part of
      // the premium picture, so nudge those too.
      sharpen('luxury', 0.95, 15.0);
      sharpen('spaciousness', 0.75, 5.0);
      sharpen('view', 0.7, 4.0);
      // A luxury seeker isn't optimizing ₪/m² — don't let the value dimension
      // dock the expensive-but-premium penthouse they actually asked for.
      weights['value'] = BayesianWeight(0.08, 0.02);
    }
    if (intents.contains(SearchIntent.view)) sharpen('view', 0.9, 9.0);
    if (intents.contains(SearchIntent.lowFloor)) sharpen('low_floor', 0.95, 12.0);
    if (intents.contains(SearchIntent.spacious)) {
      sharpen('spaciousness', 0.9, 10.0);
    }
    // A downsizer wants SMALL — so size matters, but the ideal is FEW rooms (the
    // size utility below caps the sweet-spot at ≤3 rooms for a compact search, so
    // a big 4-5 room flat decays instead of winning).
    if (intents.contains(SearchIntent.compact)) {
      sharpen('size', 0.85, 7.0);
    }
    // A persona's LIVELY-lifestyle boosts (nightlife / young-area) are wrong when
    // the SAME query asks for calm — an elderly religious couple ("זוג דתי מבוגר
    // ... שקט") is still a couple, but must NOT be pushed toward bars. Gate the
    // lively signals on the absence of a quiet/religious/senior cue.
    final wantsCalm = intents.contains(SearchIntent.quiet) ||
        intents.contains(SearchIntent.religiousArea);
    if (intents.contains(SearchIntent.roommates)) {
      // Bedrooms are near-mandatory: 3 roommates can't share a studio, so room
      // count must DOMINATE — a lively 1-room must never outrank a big flat here.
      sharpen('size', 0.95, 14.0);
      sharpen('spaciousness', 0.85, 6.0);
      sharpen('transit', 0.72, 4.0); // often car-free
      if (!wantsCalm) {
        sharpen('young_area', 0.72, 2.5); // shared flats skew young (secondary)
        sharpen('nightlife', 0.66, 2.0); // + social / going-out (secondary)
      }
    }
    // A young single living alone → central, well-connected, and (unless they
    // asked for calm) lively/young. Uses the real bar/café-density ('nightlife'),
    // CBS young-adult share and transit-grid dims, so the persona genuinely
    // reorders results — not just the nearby-places card.
    if (intents.contains(SearchIntent.single)) {
      sharpen('location', 0.82, 6.0);
      sharpen('transit', 0.75, 5.0);
      if (!wantsCalm) {
        sharpen('young_area', 0.85, 7.0);
        sharpen('nightlife', 0.78, 6.0); // bars / cafés / restaurants nearby
      }
    }
    // A couple → central-ish, a quality area, and dining/cafés. But these are
    // SOFT inferences and must never fight an explicit ask: a religious/quiet
    // couple's neighbourhood is driven by 'religious_area'/'quiet', so when the
    // query signals calm we leave the couple signal inert rather than push
    // generic centrality/SES/nightlife that would bury a מאה-שערים flat.
    if (intents.contains(SearchIntent.couple) && !wantsCalm) {
      sharpen('location', 0.70, 4.0);
      sharpen('neighborhood', 0.62, 3.0);
      sharpen('nightlife', 0.62, 3.0);
    }
    if (intents.contains(SearchIntent.wfh)) {
      sharpen('spaciousness', 0.85, 7.0);
      sharpen('condition', 0.7, 2.5);
    }
    if (intents.contains(SearchIntent.accessible)) {
      sharpen('accessibility', 0.97, 20.0);
    }
    if (intents.contains(SearchIntent.central)) sharpen('location', 0.9, 8.0);
    if (intents.contains(SearchIntent.goodSchools)) {
      sharpen('schools', 0.9, 8.0);
      // Families with kids value a park within a short walk.
      sharpen('park', 0.82, 6.0);
    }
    // Age-targeted school type: young kids → a גן/יסודי nearby; teens → a תיכון.
    if (intents.contains(SearchIntent.youngChildren)) {
      sharpen('school_young', 0.9, 9.0);
    }
    if (intents.contains(SearchIntent.teens)) {
      sharpen('school_teen', 0.9, 9.0);
    }
    if (intents.contains(SearchIntent.qualityArea)) {
      sharpen('neighborhood', 0.9, 8.0);
    }
    // A religious/observant community is a strong, defining ask — weight it high.
    if (intents.contains(SearchIntent.religiousArea)) {
      sharpen('religious_area', 0.95, 14.0);
      // A religious neighbourhood (e.g. מאה שערים) is typically LOW-SES and
      // family-heavy (many children, few seniors). Now that real block-level CBS
      // data flows in, the affluence proxy (neighborhood/SES) and the older-crowd
      // proxy (senior_area, which `quiet` sharpens) would fight the very area the
      // observant seeker asked for — burying it. Neutralise both so the explicit
      // religious choice wins; physical quiet (low_noise) still carries the "שקט".
      weights['neighborhood'] = BayesianWeight(0.1, 0.02);
      weights['senior_area'] = BayesianWeight(0.0, 0.02);
    }
    // Map-data-backed neighbourhood intents → their GovData dimensions.
    if (intents.contains(SearchIntent.safety)) sharpen('safety', 0.95, 12.0);
    if (intents.contains(SearchIntent.transit)) sharpen('transit', 0.95, 12.0);
    if (intents.contains(SearchIntent.green)) sharpen('park', 0.9, 10.0);
    if (intents.contains(SearchIntent.health)) sharpen('health', 0.9, 9.0);
    if (intents.contains(SearchIntent.convenience)) {
      sharpen('convenience', 0.92, 10.0);
    }
    if (intents.contains(SearchIntent.employment)) {
      sharpen('employment', 0.92, 10.0);
      sharpen('transit', 0.7, 3.0); // commuters also value getting there
    }
    if (intents.contains(SearchIntent.youngPop)) {
      sharpen('young_area', 0.93, 10.0);
    }
    // EXPLICIT nearby-category picks from the search filter — the seeker directly
    // chose these categories as important, so weight their dimensions high (on
    // top of any persona/intent signal). Empty by default → zero behaviour change.
    for (final dim in query.preferredNearbyDims) {
      sharpen(dim, 0.95, 14.0);
    }
    // Pet owner (requested pet-friendly) → a ground/low floor is easier with a
    // dog, so give accessibility a mild boost on top of the amenity match.
    if (requested.contains('petsAllowed')) {
      sharpen('accessibility', 0.7, 3.0);
    }

    // ════════════════════════════════════════════════════════════════════════
    // READING BETWEEN THE LINES — 40 soft inference nudges.
    //
    // What an expert agent infers from what the seeker DIDN'T say. Each is a
    // SMALL push (~0.2–0.35× the strength of an explicit ask, which already
    // sharpened above) toward a need the request implies. An explicit criterion
    // always dominates; these only break ties and gently reorder.
    // ════════════════════════════════════════════════════════════════════════
    const s = 2.6; // base soft strength (explicit asks use 8–20)
    final infTxt = query.rawText;
    final rooms = query.minRooms ?? query.maxRooms;
    final buying = query.transactionType == TransactionTypeFilter.sale;
    final renting = !buying;
    final budget = query.maxPrice ?? 0;
    final amen = query.amenities;

    // ── A. Budget tells (the price reveals the life behind it) ──────────────
    if (renting && budget > 0 && budget <= 3000) {
      sharpen('transit', 0.80, s); // (1) low budget → likely no car → transit
      sharpen('young_area', 0.72, s * 0.6); // (2) young/first-job profile
      sharpen('value', 0.78, s * 0.8); // (5) price-sensitive → value
    } else if (renting && budget > 3000 && budget <= 4500) {
      sharpen('value', 0.75, s * 0.7);
      sharpen('transit', 0.72, s * 0.5);
    }
    if (budget > 0 && budget >= (renting ? 14000 : 4000000)) {
      sharpen('luxury', 0.80, s); // (4) top of market → luxury + area + view
      sharpen('neighborhood', 0.78, s * 0.8);
      sharpen('view', 0.72, s * 0.6);
    }
    if (renting && budget > 0 && budget <= 3500) {
      sharpen('value', 0.76, s * 0.6); // (7) low budget → arnona-sensitive value
    }

    // ── B. Room-count tells (household shape) ───────────────────────────────
    if (rooms != null && rooms <= 1.5) {
      sharpen('location', 0.76, s); // (8) studio/1BR → single → central
      sharpen('transit', 0.72, s * 0.7);
      sharpen('young_area', 0.72, s * 0.6);
    } else if (rooms != null && rooms == 2) {
      sharpen('location', 0.72, s * 0.7); // (9) couple/professional → central
    } else if (rooms != null && rooms >= 4) {
      sharpen('schools', 0.78, s); // (10-12) family size → schools/area/safety
      sharpen('neighborhood', 0.75, s * 0.7);
      sharpen('safety', 0.72, s * 0.6);
      sharpen('accessibility', 0.62, s * 0.5); // strollers → low floor/elevator
    }

    // ── C. Transaction tells (horizon) ──────────────────────────────────────
    if (buying) {
      sharpen('schools', 0.72, s * 0.6); // (13) long-term → schools + area
      sharpen('neighborhood', 0.74, s * 0.6);
    } else {
      sharpen('condition', 0.68, s * 0.4); // (14) renting → move-in-ready
    }

    // ── D. One request implies another ──────────────────────────────────────
    if (amen.contains('feat_elevator')) {
      sharpen('accessibility', 0.68, s * 0.5); // (17) elevator → strollers/elderly
    }
    if (amen.contains('feat_mamad')) {
      sharpen('safety', 0.72, s * 0.6); // (19) safety-conscious → newer/safe area
      sharpen('condition', 0.66, s * 0.4);
    }
    if (amen.contains('feat_renovated')) {
      sharpen('condition', 0.76, s * 0.7); // (21) wants move-in-ready
    }
    if (amen.contains('feat_balcony') || amen.contains('feat_garden')) {
      sharpen('view', 0.68, s * 0.5); // (18) outdoor lifestyle
      sharpen('neighborhood', 0.66, s * 0.4);
    }
    if (query.nearTrain) {
      sharpen('young_area', 0.64, s * 0.4); // (26) transit-oriented → urban
    }

    // ── E. Phrasing tells (how they describe themselves) ────────────────────
    if (RegExp(r'דירה ראשונה|בית ראשון|first (home|apartment)').hasMatch(infTxt)) {
      sharpen('value', 0.75, s * 0.7); // (36) first-timer → value + transit + ready
      sharpen('transit', 0.70, s * 0.5);
      sharpen('condition', 0.68, s * 0.4);
    }
    if (RegExp(r'עבודה מהבית|עובד[ת]? מהבית|רימוט|remote|wfh').hasMatch(infTxt)) {
      sharpen('spaciousness', 0.74, s * 0.6); // (27) WFH → room for an office
      sharpen('condition', 0.66, s * 0.4);
    }
    if (RegExp(r'להשקע|השקעה|תשוא|invest|yield').hasMatch(infTxt)) {
      sharpen('yield', 0.78, s); // (37) investor → yield + rental demand
      sharpen('university', 0.66, s * 0.5);
    }
    if (RegExp(r'להקטין|מקטינ|קטנה יותר|downsiz|empty.?nest').hasMatch(infTxt)) {
      sharpen('accessibility', 0.72, s * 0.6); // (40b) downsizer → low-maintenance
      sharpen('location', 0.72, s * 0.6);
    }
    if (RegExp(r'לשדרג|יותר גדול|גדולה יותר|upgrad|move.?up').hasMatch(infTxt)) {
      sharpen('spaciousness', 0.74, s * 0.6); // (40a) move-up → space + area
      sharpen('neighborhood', 0.72, s * 0.6);
    }

    // ════════════════════════════════════════════════════════════════════════
    // F. LIFE-SITUATION & LIFESTYLE TELLS — same GOAL, many PHRASINGS (41-67).
    //
    // What an expert infers from HOW someone describes their life, robust to
    // wording (formal Hebrew + slang + English). Each is a soft push toward the
    // implied need. Lifestyle pushes (young/nightlife) are gated on `lively`
    // (= !wantsCalm) so a quiet/religious ask is never overridden.
    // ════════════════════════════════════════════════════════════════════════
    bool m(String re) => RegExp(re, caseSensitive: false).hasMatch(infTxt);
    final lively = !wantsCalm;

    // (41) Single / lives alone → young, connected, central (the canonical case).
    if (m(r'רווק|רווקה|גר\w* לבד|גרה לבד|לבד(?![\wא-ת])|בחור צעיר|בחורה צעיר|single|on my own|by myself|just me')) {
      sharpen('young_area', 0.80, s * (lively ? 1.0 : 0.4));
      sharpen('transit', 0.80, s);
      sharpen('location', 0.78, s * 0.8);
      if (lively) sharpen('nightlife', 0.72, s * 0.6);
    }
    // (42) New couple moving in together → central quality area + a bit of space.
    if (m(r'עוברים לגור|לגור (ביחד|יחד)|זוג טרי|מתחילים לגור|moving in together')) {
      sharpen('location', 0.74, s * 0.7);
      sharpen('neighborhood', 0.70, s * 0.6);
      sharpen('spaciousness', 0.68, s * 0.5);
    }
    // (43) Newlyweds → quality area, room to grow.
    if (m(r'נשוי\w* טרי|התחתנ|חתונה|newlywed|just married')) {
      sharpen('neighborhood', 0.72, s * 0.6);
      sharpen('spaciousness', 0.70, s * 0.5);
      sharpen('schools', 0.62, s * 0.35);
    }
    // (44) Expecting a baby → family area, safe, stroller-friendly, a bit bigger.
    if (m(r'בהריון|הריון|מצפים ל?תינוק|בדרך תינוק|expecting|pregnant|baby on the way')) {
      sharpen('safety', 0.80, s * 0.8);
      sharpen('schools', 0.70, s * 0.6);
      sharpen('accessibility', 0.70, s * 0.6); // stroller → elevator / low floor
      sharpen('spaciousness', 0.66, s * 0.4);
      sharpen('health', 0.66, s * 0.4);
    }
    // (45) Divorced / fresh start → value, move-in-ready, connected.
    if (m(r'גרוש|גרושה|פרידה|נפרדתי|אחרי גירושין|divorced|separated|breakup')) {
      sharpen('value', 0.74, s * 0.7);
      sharpen('condition', 0.70, s * 0.5);
      sharpen('transit', 0.68, s * 0.4);
    }
    // (46) Relocating for a new job → near work + easy commute + move-in-ready.
    if (m(r'עבר\w* בשביל עבוד|מעבר לעבוד|התחלתי עבוד|עבודה חדשה|relocat|new job|starting a job')) {
      sharpen('employment', 0.76, s * 0.7);
      sharpen('transit', 0.74, s * 0.6);
      sharpen('condition', 0.66, s * 0.4);
    }
    // (47) High-tech / young professional → central, lively, connected.
    if (m(r'הייטק|היי.טק|מתכנת|סטארטאפ|יזם|young professional|high.?tech|\btech\b|startup')) {
      sharpen('location', 0.76, s * 0.7);
      sharpen('transit', 0.70, s * 0.5);
      if (lively) {
        sharpen('young_area', 0.74, s * 0.6);
        sharpen('nightlife', 0.66, s * 0.4);
      }
    }
    // (48) Retiree / pensioner → accessible, quiet, health nearby, low floor.
    if (m(r'פנסיונר|גמלא|פרישה|בגיל השליש|קשיש|retire|pensioner')) {
      sharpen('accessibility', 0.82, s * 0.9);
      sharpen('health', 0.76, s * 0.7);
      sharpen('low_noise', 0.72, s * 0.6);
      sharpen('low_floor', 0.70, s * 0.5);
      sharpen('senior_area', 0.70, s * 0.5);
    }
    // (49) Health / mobility need → accessible + health, low floor.
    if (m(r'בעי\w* רפואי|מוגבלות|ניידות|נכה(?![\wא-ת])|כיסא גלגלים|health condition|mobility|wheelchair|disab')) {
      sharpen('accessibility', 0.88, s);
      sharpen('health', 0.78, s * 0.7);
      sharpen('low_floor', 0.72, s * 0.6);
    }
    // (50) Beach lover → coast + coastal centrality.
    if (m(r'אוהב\w* ים|קרוב לים|גלישה|לגלוש|חוף(?![\wא-ת])|beach|surf|by the sea|seaside')) {
      sharpen('coast', 0.82, s * 0.9);
      sharpen('location', 0.66, s * 0.4);
    }
    // (51) Nature / outdoors → parks + quiet.
    if (m(r'טבע|ירוק(?![\wא-ת])|טיול|hiking|nature|outdoors|greenery')) {
      sharpen('park', 0.76, s * 0.7);
      sharpen('low_noise', 0.66, s * 0.4);
    }
    // (52) Car-free → transit + walkable convenience.
    if (m(r'בלי רכב|אין לי (רכב|אוטו)|לא נוהג|ללא רכב|car.?free|no car|don.?t drive')) {
      sharpen('transit', 0.84, s);
      sharpen('location', 0.70, s * 0.5);
      sharpen('convenience', 0.70, s * 0.5);
    }
    // (53) Foodie / café culture → café & dining density, central.
    if (m(r'קולינר|מסעד|בתי ?ה?קפה|שף(?![\wא-ת])|אוכל טוב|foodie|caf[eé]|restaurant|dining')) {
      if (lively) sharpen('nightlife', 0.72, s * 0.6); // bar/café-density dim
      sharpen('location', 0.66, s * 0.4);
    }
    // (54) Fitness / active → parks (running) + young area (gyms cluster).
    if (m(r'ספורט|כושר|ריצה|לרוץ|אופניים|gym|fitness|running|workout')) {
      sharpen('park', 0.68, s * 0.5);
      if (lively) sharpen('young_area', 0.64, s * 0.35);
    }
    // (55) Frequent traveler → connected + central.
    if (m(r'טס הרבה|נוסע לחו.?ל|שדה תעופה|נתב.?ג|travel a lot|frequent flyer|airport')) {
      sharpen('transit', 0.72, s * 0.5);
      sharpen('location', 0.66, s * 0.4);
    }
    // (56) After the army / first job → value + transit + young.
    if (m(r'אחרי הצבא|אחרי צבא|עבודה ראשונה|שחרור מהצבא|after army|first job|fresh out of')) {
      sharpen('value', 0.76, s * 0.7);
      sharpen('transit', 0.72, s * 0.5);
      if (lively) sharpen('young_area', 0.70, s * 0.5);
    }
    // (57) Growing family / need more room → space + schools + quality area.
    if (m(r'משפחה גדל|צריכ\w* יותר מקום|נהיה צפוף|growing family|need more (room|space)|outgrown')) {
      sharpen('spaciousness', 0.76, s * 0.7);
      sharpen('schools', 0.70, s * 0.5);
      sharpen('neighborhood', 0.68, s * 0.4);
    }
    // (58) Commuter to a job hub → transit + employment + upside.
    if (m(r'נוסע ל?(תל אביב|מרכז|עבודה)|עובד ב?מרכז|commut')) {
      sharpen('transit', 0.76, s * 0.6);
      sharpen('employment', 0.68, s * 0.4);
      sharpen('future_value', 0.62, s * 0.3);
    }
    // (59) Quiet / calm phrasing → physical quiet + calmer demographic.
    if (m(r'שקט|רגוע|שלווה|בלי רעש|peace|quiet|calm|serene')) {
      sharpen('low_noise', 0.80, s * 0.8);
      sharpen('senior_area', 0.62, s * 0.3);
    }
    // (60) Luxury lifestyle phrasing → premium + view + prime area.
    if (m(r'יוקר|מפואר|פרימיום|וילה|פנטהאו|luxur|premium|upscale|high.?end')) {
      sharpen('luxury', 0.80, s * 0.7);
      sharpen('view', 0.70, s * 0.5);
      sharpen('neighborhood', 0.70, s * 0.5);
    }
    // (61) Budget-conscious phrasing → value + transit + convenience.
    if (m(r'חסכ|תקציב מוגבל|לא יקר|במחיר טוב|משתלם|זול|budget|affordab|cheap|save money')) {
      sharpen('value', 0.80, s * 0.8);
      sharpen('transit', 0.66, s * 0.4);
      sharpen('convenience', 0.62, s * 0.3);
    }
    // (62) Student phrasings (broad) → campus + value + young + transit.
    if (m(r'סטודנט|לומד\w* תואר|אקדמ|מכללה|קמפוס|student|university|college|campus')) {
      sharpen('university', 0.74, s * 0.6);
      sharpen('value', 0.70, s * 0.5);
      sharpen('transit', 0.68, s * 0.4);
      if (lively) sharpen('young_area', 0.68, s * 0.4);
    }
    // (63) Religious / observant phrasing (mild — heavy handling is intent-driven).
    if (m(r'דתי(?![\wא-ת])|שומר\w* שבת|כשר(?![\wא-ת])|בית ?ה?כנסת|מסורתי|observant|kosher|religious')) {
      sharpen('religious_area', 0.72, s * 0.5);
    }
    // (64) Works from home (broad) → space for an office + quiet.
    if (m(r'מהבית|פרילנס|עצמאי|חדר ?ה?עבודה|home office|freelanc|self.?employed')) {
      sharpen('spaciousness', 0.72, s * 0.5);
      sharpen('low_noise', 0.66, s * 0.4);
    }
    // (65) View / high floor phrasing → view.
    if (m(r'נוף(?![\wא-ת])|קומה גבוה|high floor|\bview\b|skyline')) {
      sharpen('view', 0.78, s * 0.6);
    }
    // (66) Garden / outdoor-space lover → green + nicer area.
    if (m(r'גינה|מרפסת גדולה|צמח|שמש|garden|big balcony|plants')) {
      sharpen('park', 0.60, s * 0.3);
      sharpen('neighborhood', 0.60, s * 0.3);
    }
    // (67) Errands / convenience-first → supermarkets & shops nearby + walkable.
    if (m(r'קרוב לסופר|קניות|מכולת|נוחות|errands|groceries|convenien')) {
      sharpen('convenience', 0.78, s * 0.7);
      sharpen('location', 0.62, s * 0.3);
    }

    if (profile != null && profile.importantDetails.isNotEmpty) {
      // a tenant who curated details cares about condition & trust
      sharpen('condition', 0.7, 2.0);
      sharpen('trust', 0.6, 1.5);
    }

    // persona-aware sharpening from the free text: families weight safety &
    // neighbourhood; everyone gets a mild safety prior bump (universally valued).
    final raw = query.rawText;
    // persona match-keys from the curated profile tags (e.g. 'family','students').
    final personaKeys = profile != null
        ? ProfileTagCatalog.matchKeysFor(profile.importantDetails,
            isLandlord: false)
        : const <String>{};
    final familyTag = personaKeys.contains('family');
    final studentTag =
        personaKeys.contains('students') || personaKeys.contains('roommates');
    final familyPersona =
        familyTag || RegExp(r'משפח|ילד|ילדים|בית ספר').hasMatch(raw);
    if (familyPersona) {
      sharpen('safety', 0.9, 4.0);
      sharpen('neighborhood', 0.7, 2.0);
      sharpen('park', 0.8, 3.5); // a nearby park matters for a household with kids
    } else {
      sharpen('safety', 0.6, 1.0); // soft default — safety still counts
    }

    // ── persona-weighted gov livability dimensions ───────────────────────────
    // A family (or family free-text) makes schools + a family-friendly area
    // strongly relevant; students/roommates care a little about a young area but
    // not about schools. Otherwise these stay at their mild non-zero prior so
    // they still contribute without dominating.
    if (familyPersona) {
      sharpen('schools', 0.9, 5.0);
      sharpen('family', 0.85, 4.0);
      sharpen('health', 0.6, 1.5); // families value clinic access too
    } else if (studentTag) {
      sharpen('family', 0.55, 2.0); // young/family-mix area, mild
    }

    // A CHILDLESS single / couple / roommate is NOT looking for child (or elderly)
    // infrastructure — being a couple doesn't mean they want schools & gardens.
    // The schools/family/health dims otherwise sit at the same 0.30 baseline as a
    // family's and quietly push them toward family neighbourhoods over their REAL
    // needs (central/lively/transit/nightlife). Down-weight those dims here (a
    // direct override, NOT marked "stated") so the seeker's own lifestyle leads.
    // A calm/quiet couple still keeps health (they may value it) via wantsCalm.
    final childless = !familyPersona &&
        (intents.contains(SearchIntent.single) ||
            intents.contains(SearchIntent.couple) ||
            intents.contains(SearchIntent.roommates));
    if (childless) {
      // Only the child-specific dims — health stays (a childless couple, and
      // especially a retired one, may still value clinics nearby).
      weights['schools'] = BayesianWeight(0.08, 0.02);
      weights['family'] = BayesianWeight(0.10, 0.02);
    }

    // ── LLM-DRIVEN WEIGHTS (the assistant is the brain) ───────────────────────
    // When the assistant supplied importances, they REPLACE all heuristic weights:
    // the language model understood the human and decided what matters and how
    // much. A factor it didn't mention drops to 0 (not considered). The algorithm
    // then does only the math the model asked for. Budget/location keep a small
    // floor so price/place are never entirely ignored.
    if (query.weights.isNotEmpty) {
      stated.clear();
      for (final dim in kScoringDimensions) {
        final llmImp = llmWeightForDim(dim, query.weights); // what the model set
        var imp = llmImp;
        if (dim == 'budget') imp = math.max(imp, 0.35);
        if (dim == 'location') imp = math.max(imp, 0.20);
        weights[dim] = BayesianWeight(imp, 0.02); // confident: the model decided
        // Only "stated" when the model ACTUALLY weighted it — the budget/location
        // FLOOR must not mark budget as stated (else a no-budget search shows a
        // phantom "over budget" concern against the default median budget).
        if (llmImp > 0) stated.add(dim);
      }
    }

    // ── utilities per dimension ──────────────────────────────────────────────
    final elasticity = cheap ? 0.1 : (query.maxPrice != null ? 0.35 : 0.55);

    final roomsLo = desiredRoomsLo ?? (market.minRooms);
    final roomsHi = desiredRoomsHi ?? (desiredRoomsLo != null
        ? desiredRoomsLo + 1.0
        : market.maxRooms);

    final utilities = <String, AttributeUtility>{
      // central is better, but vague-location users shouldn't be punished hard
      'location': query.city != null
          ? const SigmoidThresholdUtility(0.45, 6.0)
          : const LinearUtility(),
      // socioeconomic quality: gentle reward for mid+ clusters; cheap-seekers
      // shouldn't be penalized for affordable areas, so keep it soft.
      'neighborhood': cheap
          ? const ConstantUtility(0.55)
          : const SigmoidThresholdUtility(0.4, 4.0),
      // safety: higher is always better, with a gentle floor so a single
      // low-safety area isn't fatal.
      'safety': const SigmoidThresholdUtility(0.35, 4.5),
      // KNOWN LIMITATION: the budget VALUE is the true monthly cost (rent +
      // arnona + vaad) while this ceiling is the stated RENT ceiling, so a rental
      // whose rent sits exactly at budget reads slightly "over". A flat overhead
      // inflation was tried but shifts ranking goldens broadly; a correct fix
      // needs a size-aware per-listing ceiling + golden re-baselining. Left as-is
      // (soft down-weight only; the hard budget gate correctly uses rent).
      'budget': BudgetUtility(maxBudget, elasticity,
          minBudget: (minBudget ?? 0).toDouble()),
      'value': const LinearUtility(),
      // Compact (downsizer): ideal 2-3 rooms, a 4+ flat decays — so "קטנה" no
      // longer surfaces the biggest flat. Roommates want the OPPOSITE: more rooms
      // is better, so a 5-room flat isn't penalised for exceeding the market
      // "typical" range. Otherwise the usual range around the stated desire.
      'size': intents.contains(SearchIntent.compact)
          ? RangeUtility(math.min(roomsLo, 2.0), 3.0,
              slackBelow: 1.0, slackAbove: 1.0)
          // Roommates want BEDROOMS: more rooms is strictly better, and a too-small
          // flat is nearly unusable (3 roommates can't share a studio). A steep
          // sigmoid centred at 3 → 1-room≈0.02, 3-room≈0.5, 4-5 rooms high, so a
          // cheap central studio can no longer top a big flat here.
          : (intents.contains(SearchIntent.roommates) && desiredRoomsLo == null)
              ? const SigmoidThresholdUtility(3.0, 2.0)
              // Open-ended "לפחות N חדרים" (min set, no max): N-or-more all
              // satisfy — a 7-room must not score 0 against "at least 4". Only
              // decays BELOW the floor.
              : (query.minRooms != null && query.maxRooms == null)
                  ? RangeUtility(roomsLo, 99.0, slackBelow: 1.0)
                  : RangeUtility(roomsLo, roomsHi,
                      slackBelow: 1.0, slackAbove: 2.0),
      'amenities': const LinearUtility(), // input already a satisfaction
      'transit': query.nearTrain
          ? const SigmoidThresholdUtility(0.3, 7.0)
          : const LinearUtility(),
      'condition': const SigmoidThresholdUtility(0.4, 5.0),
      'freshness': const LinearUtility(),
      'popularity': const LinearUtility(),
      'trust': const LinearUtility(),
      // gov-data livability inputs are already [0,1] scores — higher is better.
      'schools': const LinearUtility(),
      'family': const LinearUtility(),
      'health': const LinearUtility(),
      // These 5 gov/geo dims were MISSING here and silently fell back to a
      // ConstantUtility(0.5) in satisfaction() — i.e. their real feature values
      // were IGNORED in ranking. So a religious neighbourhood, a nearby park, an
      // age-matched school, and bar/café density never actually moved the score
      // (only their chips did). They are [0,1] scores where higher is better.
      'park': const LinearUtility(),
      'religious_area': const LinearUtility(),
      'school_young': const LinearUtility(),
      'school_teen': const LinearUtility(),
      'nightlife': const LinearUtility(),
      'coast': const LinearUtility(), // coast_access is already a [0,1] proximity
      'yield': const LinearUtility(), // yield score already normalised to [0,1]
      'university': const LinearUtility(),
      'young_area': const LinearUtility(),
      'senior_area': const LinearUtility(),
      'luxury': const LinearUtility(),
      'view': const LinearUtility(),
      'spaciousness': const LinearUtility(),
      'accessibility': const LinearUtility(),
      'convenience': const LinearUtility(),
      'low_noise': const LinearUtility(),
      'future_value': const LinearUtility(),
      'employment': const LinearUtility(),
      'low_floor': const LinearUtility(),
    };

    // ── curated persona→layer spec: a GENTLE prior nudge ─────────────────────
    // The 504-scenario spec (ScenarioLayers) says which layers a persona cares
    // about; fold its layer weights into the matching dimension priors at LOW
    // precision (0.8 vs a ~11 prior precision ⇒ a ~0.05 nudge) so stated and
    // learned evidence still dominate. Best-effort: an unloaded asset or an
    // unmatched persona is a no-op. NOT marked `stated` — these are priors, not
    // user-stated facts, so they don't claim attribution in explanations.
    try {
      final np = NearbyProfile.fromText(query.rawText);
      final purpose =
          query.transactionType == TransactionTypeFilter.sale ? 'buy' : 'rent';
      ScenarioLayers.instance
          .dimensionBoostsFor(np, purpose: purpose)
          ?.forEach((dim, target) => weights[dim]?.observe(target, 0.8));
    } catch (_) {}

    final constraints = HardConstraints(
      city: query.city,
      minPrice: query.minPrice,
      maxPrice: query.maxPrice,
      minRooms: query.minRooms,
      maxRooms: query.maxRooms,
      requiredFeatures: requested,
      dealBreakers: dealBreakers,
      propertyType: query.propertyType,
    );

    return UserPreferenceModel(
      weights: weights,
      utilities: utilities,
      constraints: constraints,
      requestedAmenityKeys: requested,
      learner: learner ?? OnlineLogisticLearner(),
      maxBudget: maxBudget,
      desiredRooms: desiredRoomsLo,
      statedDimensions: stated,
    );
  }
}
