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

import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/smart_search.dart';
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
];

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
  }

  /// Confidence in the learner's own predictions, growing with #updates.
  double get confidence => 1.0 - math.exp(-updates / 25.0);

  Map<String, double> snapshotWeights(Iterable<String> keys) =>
      {for (final k in keys) k: _weight(k)};
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
        return pfv.property.price.toDouble();
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
  };
  static const double _priorVariance = 0.09; // σ≈0.3 — fairly uncertain prior

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

    // deal-breakers from profile (best-effort canonicalization)
    final dealBreakers = <String>{
      for (final d in (profile?.dealBreakers ?? const []))
        canonicalFeatureKey(d),
    };

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
      sharpen('transit', 0.95, 6.0);
    }
    if (profile != null && profile.importantDetails.isNotEmpty) {
      // a tenant who curated details cares about condition & trust
      sharpen('condition', 0.7, 2.0);
      sharpen('trust', 0.6, 1.5);
    }

    // persona-aware sharpening from the free text: families weight safety &
    // neighbourhood; everyone gets a mild safety prior bump (universally valued).
    final raw = query.rawText;
    final familyPersona = RegExp(r'משפח|ילד|ילדים|בית ספר').hasMatch(raw);
    if (familyPersona) {
      sharpen('safety', 0.9, 4.0);
      sharpen('neighborhood', 0.7, 2.0);
    } else {
      sharpen('safety', 0.6, 1.0); // soft default — safety still counts
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
      'budget': BudgetUtility(maxBudget, elasticity,
          minBudget: (minBudget ?? 0).toDouble()),
      'value': const LinearUtility(),
      'size': RangeUtility(roomsLo, roomsHi, slackBelow: 1.0, slackAbove: 2.0),
      'amenities': const LinearUtility(), // input already a satisfaction
      'transit': query.nearTrain
          ? const SigmoidThresholdUtility(0.3, 7.0)
          : const LinearUtility(),
      'condition': const SigmoidThresholdUtility(0.4, 5.0),
      'freshness': const LinearUtility(),
      'popularity': const LinearUtility(),
      'trust': const LinearUtility(),
    };

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
