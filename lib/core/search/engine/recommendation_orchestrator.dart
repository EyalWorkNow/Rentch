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
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/finance/rental_yield.dart';
import 'package:dating_app/core/govdata/gov_sources.dart';
import 'package:dating_app/core/matching/match_models.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/govdata/gov_data.dart';
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
    'park': 'קרבה לפארק',
    'religious_area': 'קהילה דתית',
    'school_young': 'גנים ויסודי בקרבת מקום',
    'school_teen': 'חטיבה ותיכון בקרבת מקום',
    'nightlife': 'חיי לילה ובילוי',
    'yield': 'תשואה להשקעה',
    'university': 'קרבה לאוניברסיטה',
    'young_area': 'אזור צעיר ותוסס',
    'senior_area': 'אזור שקט ומבוגר',
    'luxury': 'רמת יוקרה',
    'view': 'קומה גבוהה / נוף',
    'spaciousness': 'מרווחות',
    'accessibility': 'נגישות',
    'convenience': 'קרבה לסופר וקניות',
    'low_noise': 'שקט מרעש',
    'future_value': 'פוטנציאל השבחה',
    'employment': 'קרבה לתעסוקה',
    'low_floor': 'קומה נמוכה',
  };

  /// Public Hebrew label for a scoring dimension key (used by the Scorecard
  /// builder). Falls back to the raw key when unmapped.
  static String dimLabel(String key) => _dimLabel[key] ?? key;

  static String _dist(double km) =>
      km < 1.0 ? '${(km * 1000).round()} מ׳' : '${km.toStringAsFixed(1)} ק"מ';

  /// "פארק <name>" unless the name already carries its own descriptor.
  static String _parkLabel(String? name) {
    final n = (name ?? '').trim();
    if (n.isEmpty) return 'פארק';
    return RegExp(r'^(גן|פארק|שדרות|יער|חורש|כיכר)').hasMatch(n) ? n : 'פארק $n';
  }

  /// Prefix the school type so "<name>" reads clearly ("בית ספר X", "גן X").
  static String _schoolLabel(String name, String type) {
    final n = name.trim();
    if (type == 'גן') return n.startsWith('גן') ? n : 'גן $n';
    if (type == 'אוניברסיטה' || type == 'מכללה') return n;
    if (type == 'תיכון') return RegExp(r'תיכון').hasMatch(n) ? n : 'תיכון $n';
    if (type == 'חטיבה') return RegExp(r'חטיב').hasMatch(n) ? n : 'חטיבת $n';
    return RegExp('בית.?ספר|בי"?ס|יסודי').hasMatch(n) ? n : 'בית ספר $n';
  }

  /// Concrete, data-driven chips for a candidate. [intents] gates the lifestyle
  /// geo chips to what THIS seeker actually asked for — a nightlife-seeker never
  /// gets school/family chips, and vice-versa (relevant + brief).
  static List<String> highlights(
    RankedCandidate c,
    UserPreferenceModel model,
    Set<String> intents,
  ) {
    final pfv = c.pfv;
    final p = pfv.property;
    final chips = <String>[];

    // ── VOICED-INTENT tags FIRST ─────────────────────────────────────────────
    // Every lifestyle intent the seeker actually voiced gets a visible chip when
    // this flat satisfies it — so the card leads with what THEY asked for
    // (safety/quiet/errands/work/health/green/upside), not generic price/transit.
    // Placed first so the compact "why" (first 2 chips) shows their real asks.
    if (intents.contains(SearchIntent.safety)) {
      final sf = pfv.get('safety', 0.5);
      if (sf > 0.66) {
        chips.add('🛡️ שכונה בטוחה');
      } else if (sf > 0.45) {
        chips.add('🛡️ רמת בטיחות סבירה');
      }
    }
    if (intents.contains(SearchIntent.quiet) && pfv.get('low_noise', 0.5) > 0.66) {
      chips.add('🤫 שקט — רחוק מצירי תנועה');
    }
    if (intents.contains(SearchIntent.convenience) &&
        pfv.get('retail_access', 0.0) > 0.4) {
      chips.add('🛒 קרוב לסופר ולקניות');
    }
    if (intents.contains(SearchIntent.employment) &&
        pfv.get('employment_access', 0.0) > 0.4) {
      chips.add('💼 קרוב לאזור תעסוקה');
    }
    if (intents.contains(SearchIntent.health) &&
        pfv.get('health_access', 0.5) > 0.5) {
      chips.add('🏥 קרוב לשירותי בריאות');
    }
    if (intents.contains(SearchIntent.religiousArea) &&
        pfv.get('religious_area', 0.0) > 0.4) {
      chips.add('🕍 קהילה דתית באזור');
    }
    if (intents.contains(SearchIntent.lowFloor) && (p.floorNumber ?? 99) <= 2) {
      chips.add('🏠 קומה נמוכה');
    }
    if (intents.contains(SearchIntent.green)) {
      final parkKm = IsraelGeoIndex.parkKm(p.lat, p.lon);
      if (parkKm != null && parkKm <= 0.8) chips.add('🌳 ${_dist(parkKm)} מפארק');
    }
    if (intents.contains(SearchIntent.youngPop) && pfv.get('demo_young', 0.5) > 0.55) {
      chips.add('🎈 אזור צעיר');
    }
    if ((intents.contains(SearchIntent.growth) ||
            intents.contains(SearchIntent.investment)) &&
        pfv.get('future_value', 0.0) > 0.5) {
      chips.add('📈 פוטנציאל השבחה — ליד תשתית מתוכננת');
    }
    if (intents.contains(SearchIntent.investment) &&
        p.transactionType == PropertyTransactionType.sale) {
      final est = RentalYield.estimate(
          salePrice: p.price, sizeM2: p.sizeM2, city: p.city);
      if (est != null && est.grossYieldPct > 0) {
        chips.add('📊 תשואה ~${est.grossYieldPct.toStringAsFixed(1)}%');
      }
    }

    // value / pricing
    if (pfv.get('hedonic_residual') > 0.2 || pfv.valueScore > 0.72) {
      chips.add('מחיר אטרקטיבי מתחת לשוק');
    } else if (pfv.get('price_per_sqm_percentile') < 0.35 &&
        (p.pricePerSquareMeter ?? 0) > 0) {
      chips.add('₪${p.pricePerSquareMeter}/מ״ר — נמוך לאזור');
    }

    // transit — real gov-data signals. Name the actual nearest station when close.
    final railKm = pfv.get('rail_km', 99);
    if (railKm < 3.0) {
      final st = GovData.instance
          .nearestRailStation(pfv.property.lat, pfv.property.lon);
      if (st != null && st.name.trim().isNotEmpty) {
        chips.add('🚉 ${_dist(railKm)} מתחנת ${st.name}');
      } else {
        chips.add(railKm < 1.2 ? 'צמוד לרכבת' : 'כ-${_dist(railKm)} מהרכבת');
      }
    } else if (pfv.get('transit_density') > 0.6) {
      chips.add('מחובר היטב לתחבורה');
    }

    // location & neighbourhood quality (CBS socioeconomic cluster)
    if (pfv.centrality > 0.78) chips.add('מיקום מרכזי');
    if (pfv.get('socioeconomic') > 0.78) chips.add('אזור מבוקש');

    // livability (real gov data)
    if (pfv.get('safety') > 0.7) chips.add('אזור בטוח יחסית');
    // Schools — only for a family / kids-focused search.
    final wantsSchools = intents.contains(SearchIntent.goodSchools) ||
        intents.contains(SearchIntent.youngChildren) ||
        intents.contains(SearchIntent.teens);
    if (wantsSchools && pfv.get('school_access') > 0.6) {
      // Pick the school TYPE that matches the family's stage — "משפחה" means an
      // actual SCHOOL, not just a nearby kindergarten. Teens→תיכון, toddler→גן,
      // otherwise a real (elementary) school.
      final targetType = intents.contains(SearchIntent.teens)
          ? 'תיכון'
          : intents.contains(SearchIntent.youngChildren)
              ? 'גן'
              : 'יסודי';
      final near = IsraelGeoIndex.nearestSchool(p.lat, p.lon, type: targetType) ??
          IsraelGeoIndex.nearestSchool(p.lat, p.lon);
      if (near != null && near.km <= 1.5) {
        chips.add('🏫 ${_dist(near.km)} מ${_schoolLabel(near.name, near.type)}');
      } else {
        chips.add('קרוב למוסדות חינוך');
      }
    }
    // Parks — families + quiet-seekers value them; not a nightlife-seeker.
    if (wantsSchools || intents.contains(SearchIntent.quiet)) {
      final parkKm = IsraelGeoIndex.parkKm(pfv.property.lat, pfv.property.lon);
      if (parkKm != null && parkKm <= 0.7) {
        final name =
            IsraelGeoIndex.nearestParkName(pfv.property.lat, pfv.property.lon);
        chips.add('🌳 ${_dist(parkKm)} מ${_parkLabel(name)}');
      }
    }
    // Health — nearest clinic (named with its HMO), for a health-focused seeker.
    if (intents.contains(SearchIntent.health)) {
      final cl = IsraelGeoIndex.clinicsWithin(p.lat, p.lon, km: 5, cap: 1);
      if (cl.isNotEmpty) {
        final c0 = cl.first;
        chips.add(
            '🏥 ${_dist(c0.km)} מ${c0.sector.isEmpty ? 'מרפאה' : 'קופ״ח ${c0.sector}'}');
      }
    }
    // Kindergarten — for a young-children search (a real גן nearby).
    if (intents.contains(SearchIntent.youngChildren)) {
      final kg = IsraelGeoIndex.kindergartensWithin(p.lat, p.lon, km: 2, cap: 1);
      if (kg.isNotEmpty) chips.add('🧸 ${_dist(kg.first.km)} מגן ילדים');
    }
    // Errands — nearest supermarket, for a convenience/groceries-focused seeker.
    if (intents.contains(SearchIntent.convenience)) {
      final su = IsraelGeoIndex.supermarketsWithin(p.lat, p.lon, km: 2, cap: 1);
      if (su.isNotEmpty) chips.add('🛒 ${_dist(su.first.km)} מ${su.first.name}');
    }

    // Sea — only a beach-seeker.
    if (intents.contains(SearchIntent.nearSea)) {
      final seaKm = IsraelGeoIndex.coastKm(pfv.property.lat, pfv.property.lon);
      if (seaKm != null && seaKm <= 1.2) chips.add('🏖️ ${_dist(seaKm)} מהחוף');
    }
    // University — only a student / near-campus search.
    if (intents.contains(SearchIntent.student) ||
        intents.contains(SearchIntent.nearUniversity)) {
      final uni = IsraelGeoIndex.nearestSchool(
          pfv.property.lat, pfv.property.lon,
          type: 'אוניברסיטה');
      if (uni != null && uni.km <= 1.5) {
        chips.add('🎓 ${_dist(uni.km)} מ${uni.name}');
      } else if (pfv.get('university_access', 0.0) > 0.5) {
        // Campus proximity without a named institution in the index — still tell
        // the student the intent was honoured.
        chips.add('🎓 קרוב לקמפוס');
      }
    }
    // Nightlife — only a nightlife / vibrant-area search.
    if (intents.contains(SearchIntent.nightlife)) {
      final nl = pfv.get('nightlife', 0.0);
      if (nl > 0.6) {
        chips.add('🍸 אזור תוסס — חיי לילה');
      } else if (nl > 0.35) {
        chips.add('🍸 קרוב לברים ובתי קפה');
      }
    }
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

// Process-wide cache of the catalogue-constant market baseline (see recommend()).
// A single slot is enough: queries within a session share one catalogue, so the
// key stays stable and hits every time until the catalogue changes.
class _BaselineCache {
  _BaselineCache._();
  static int? key;
  static MarketContext? rent;
  static MarketContext? sale;
}

// PERF: FeatureEngineer.engineer() does ~25 geo/gov lookups per property and is
// catalogue-stable (its output depends only on the property + the market
// baseline, NOT the query — the query is applied later in scoring/gating). A
// single user action re-runs the whole pipeline 7-12× (cohort fallbacks +
// what-if counting), and each swipe re-ranks, so without memoization every
// candidate is re-engineered from scratch each time. Cache the feature vector
// per property, generation-keyed by the market baseline's OBJECT identity: the
// cached baseline is a stable object for a given catalogue, so it holds across
// the repeat runs and auto-clears when the catalogue (baseline) is replaced.
class _PfvMemo {
  _PfvMemo._();
  static int marketId = 0;
  // Keyed by the property OBJECT identity (not id): the same objects are reused
  // across a search's repeat runs (cache hit), while a different object — an
  // edited listing, or a distinct test fixture that reuses an id — never yields
  // a stale vector. Cleared whenever the market baseline object changes.
  static final Map<int, PropertyFeatureVector> byObj =
      <int, PropertyFeatureVector>{};
}

PropertyFeatureVector _engineerCached(RentalProperty p, MarketContext market) {
  final mid = identityHashCode(market);
  if (_PfvMemo.marketId != mid) {
    _PfvMemo.marketId = mid;
    _PfvMemo.byObj.clear();
  }
  final oid = identityHashCode(p);
  final hit = _PfvMemo.byObj[oid];
  if (hit != null) return hit;
  final v = FeatureEngineer.engineer(p, market); // the REAL engineer, not self
  _PfvMemo.byObj[oid] = v;
  return v;
}

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
    Map<String, Map<String, double>>? learnerFeatureSink,
  }) {
    if (candidates.isEmpty) return const [];

    // PERSISTENT market baseline: fit the price / percentile / hedonic statistics
    // over the FULL, UNFILTERED catalogue — segmented by transaction type (rent ≈
    // ₪5k, sale ≈ ₪2M; mixing them would wreck the price distribution). Feature
    // engineering below reads THIS, not per-query stats, so a listing's
    // value_score / price_percentile / hedonic-residual are stable: they no longer
    // drift with whoever happens to co-occur in a filtered result set. Same
    // catalogue in ⇒ same baseline out, every query. (A tiny catalogue — <8 of a
    // type, e.g. a unit test — has no meaningful distribution, so it falls back to
    // per-query analyze() below.)
    // PERF: the baseline is catalogue-constant ("same catalogue in ⇒ same baseline
    // out"), so analyzing ~1,500 listings' percentiles on EVERY query/swipe is
    // wasted main-thread work. Cache it, keyed by the candidate list's identity +
    // length + endpoints — a robust, O(1) key that misses (recomputes) whenever the
    // catalogue is replaced, appended to, or a different subset is passed.
    final baselineKey = Object.hash(
      identityHashCode(candidates),
      candidates.length,
      candidates.isEmpty ? 0 : candidates.first.id,
      candidates.isEmpty ? 0 : candidates.last.id,
    );
    final MarketContext? rentBaseline;
    final MarketContext? saleBaseline;
    if (_BaselineCache.key == baselineKey) {
      rentBaseline = _BaselineCache.rent;
      saleBaseline = _BaselineCache.sale;
    } else {
      final rentAll = <RentalProperty>[];
      final saleAll = <RentalProperty>[];
      for (final p in candidates) {
        (p.transactionType == PropertyTransactionType.sale ? saleAll : rentAll)
            .add(p);
      }
      rentBaseline = rentAll.length >= 8 ? MarketContext.analyze(rentAll) : null;
      saleBaseline = saleAll.length >= 8 ? MarketContext.analyze(saleAll) : null;
      _BaselineCache.key = baselineKey;
      _BaselineCache.rent = rentBaseline;
      _BaselineCache.sale = saleBaseline;
    }

    // Hard rent/sale gate: an investor's "דירה להשקעה" must never surface
    // rentals (and vice-versa). Enforced here so EVERY caller — incl. the chat's
    // provider.recommendForTenant path — is gated, not just SmartSearch.rank.
    final gated = SmartSearch.applyTransactionFilter(candidates, query);
    if (gated.isEmpty) return const [];
    // Marketplace default: an UNSPECIFIED search is a RENT search — a family
    // looking to rent must never see million-shekel sales mixed in. Buying is a
    // deliberate choice ("למכירה"/"להשקעה"). Relax to all only if there's no rent.
    if (query.transactionType == TransactionTypeFilter.any) {
      final rentOnly = gated
          .where((p) => p.transactionType == PropertyTransactionType.rent)
          .toList();
      candidates = rentOnly.isNotEmpty ? rentOnly : gated;
    } else {
      candidates = gated;
    }

    // City gate — the named city is an IDENTITY, not a suggestion. Three cases:
    //  • ample exact stock (≥3) → show ONLY the named city (a "תל אביב" search must
    //    never surface פתח תקווה).
    //  • sparse exact stock (1-2) → widen ONLY to the tightly-CONTIGUOUS metro
    //    (≤5 km: רמת גן / גבעתיים from ת"א), never a distinct city farther out —
    //    "עין עירון" must NOT pull אור עקיבא (~7 km away, its own city).
    //  • ZERO exact stock → return the (empty) named-city set. We do NOT silently
    //    substitute a different city; the flow says "nothing in <city>". A tiny
    //    moshav with no listings must never be answered with a neighbouring town.
    // property id → km from the searched city, for listings in a DIFFERENT but
    // adjacent (≤4km) town. Kept later only if they score >70%, and flagged with
    // the reason. Lets "דירה בעיר X" surface a great match hugging X's border.
    final nearbyKm = <String, double>{};
    final city = query.city?.trim();
    // "אזור X" (SearchIntent.cityArea) EXPLICITLY asks for X + its adjacent
    // settlements, so the gate widens to the neighbouring towns (≤8km) and shows
    // them as full results — not the >70%-only bonus that a bare "בעיר X" gets.
    final areaMode = query.intents.contains(SearchIntent.cityArea);
    if (city != null && city.isNotEmpty) {
      final inCity = candidates
          .where((p) => _cityMatches(p, city))
          .toList();
      // Area center for "אזור X": prefer the CBS locality's REAL coordinate — it
      // exists for every city in Israel (assets/govdata/localities.json), so the
      // circle works even when X has zero own stock or its listings lack coords.
      // Falls back to the mean of in-city listings if the locality is unknown.
      double? aLat, aLon;
      if (areaMode) {
        final gov = GovData.instance.localityByName(city);
        if (gov != null && gov.lat.abs() > 0.1 && gov.lon.abs() > 0.1) {
          aLat = gov.lat;
          aLon = gov.lon;
        } else if (inCity.isNotEmpty) {
          aLat = inCity.map((p) => p.lat).reduce((a, b) => a + b) / inCity.length;
          aLon = inCity.map((p) => p.lon).reduce((a, b) => a + b) / inCity.length;
        }
      }
      if (areaMode && aLat != null && aLon != null) {
        final cLat = aLat, cLon = aLon;
        candidates = candidates
            .where((p) =>
                _cityMatches(p, city) ||
                _km(p.lat, p.lon, cLat, cLon) <= 8.0)
            .toList();
      } else if (inCity.length >= 3) {
        final cLat =
            inCity.map((p) => p.lat).reduce((a, b) => a + b) / inCity.length;
        final cLon =
            inCity.map((p) => p.lon).reduce((a, b) => a + b) / inCity.length;
        final nearby = candidates
            .where((p) =>
                !_cityMatches(p, city) &&
                _km(p.lat, p.lon, cLat, cLon) <= 4.0)
            .toList();
        for (final p in nearby) {
          nearbyKm[p.id] = _km(p.lat, p.lon, cLat, cLon);
        }
        candidates = [...inCity, ...nearby];
      } else if (inCity.isNotEmpty) {
        final cLat = inCity.map((p) => p.lat).reduce((a, b) => a + b) /
            inCity.length;
        final cLon = inCity.map((p) => p.lon).reduce((a, b) => a + b) /
            inCity.length;
        candidates = candidates
            .where((p) =>
                _cityMatches(p, city) || _km(p.lat, p.lon, cLat, cLon) <= 5.0)
            .toList();
      } else {
        candidates = inCity; // empty → honest "no listings in <city>", never a leak
      }
    }
    // Named city with zero stock → return nothing (the flow says "none in <city>")
    // rather than crashing or leaking a neighbouring town.
    if (candidates.isEmpty) return const [];

    // Required-feature gate: HARD deal-breakers (mamad חובה / must allow pets /
    // furnished) EXCLUDE listings that lack them — a "must have a mamad" search
    // must never surface a flat without one. Relax only if nothing qualifies.
    if (query.requiredFeatures.isNotEmpty) {
      final req = query.requiredFeatures;
      // First pass: listings satisfying ALL must-haves.
      var pool = candidates
          .where((p) => req.every((k) => propertyHasFeature(p, k)))
          .toList();
      if (pool.isEmpty) {
        // Nothing satisfies ALL. Drop only the UNSATISFIABLE keys — those NO
        // listing carries (usually an UNRECORDED feature like a pet policy, not
        // one that's banned) — and gate on the rest. This fixes the old
        // fall-through where a single impossible key (e.g. an `accessible` flag no
        // listing has) voided a perfectly-satisfiable one (elevator) and leaked
        // walk-ups to a wheelchair searcher. If NO key is satisfiable, keep the
        // full pool rather than hide everything (absence ≠ excluded).
        final satisfiable = req
            .where((k) => candidates.any((p) => propertyHasFeature(p, k)))
            .toSet();
        pool = satisfiable.isEmpty
            ? candidates
            : candidates
                .where((p) => satisfiable.every((k) => propertyHasFeature(p, k)))
                .toList();
        if (pool.isEmpty) pool = candidates;
      }
      candidates = pool;
    }

    // Near-sea gate: excludes the clearly-inland (so "קרוב לים" never returns
    // ירושלים), but stays forgiving — "לא רחוק מהים" in a coastal city still
    // means a few km inland is fine. SearchIntent.notFarFromSeaKm (4km,
    // exclusive) is the single definition of "not far"; the coast dimension
    // below orders the survivors by exact distance (beachfront first). Relax
    // entirely if nothing qualifies.
    if (query.intents.contains(SearchIntent.nearSea)) {
      final nearSea = candidates.where((p) {
        final km = IsraelGeoIndex.coastKm(p.lat, p.lon);
        return km != null && km < SearchIntent.notFarFromSeaKm;
      }).toList();
      if (nearSea.isNotEmpty) candidates = nearSea;
    }

    // Backfill pool captured HERE — after the IDENTITY gates (city, must-have
    // features, near-sea) but before the SOFT ones (budget, rooms). So topping the
    // list up to ~10 relaxes only budget/rooms (a "slightly over budget" or
    // "one room fewer" near-match), NEVER the identity: a "קרוב לים" search is
    // never backfilled with an inland flat, nor a "must-have mamad" with one lacking it.
    final backfillPool = List.of(candidates);

    // Budget gate: a stated max budget is a HARD ceiling — "עד 5000" must never
    // surface a ₪5500 flat while anything ≤ ₪5000 exists. Only when NOTHING fits
    // do we relax to the cheapest available cluster (each carries an explicit
    // "over budget" concern so the compromise is visible, not silent).
    final maxP = query.maxPrice;
    if (maxP != null && maxP > 0) {
      final within = candidates.where((p) => p.price <= maxP).toList();
      if (within.isNotEmpty) {
        candidates = within;
      } else {
        final sorted = [...candidates]..sort((a, b) => a.price.compareTo(b.price));
        final cheapest = sorted.first.price;
        candidates = sorted.where((p) => p.price <= cheapest * 1.35).toList();
      }
    }

    // Min-rooms gate: a stated minimum ("4+ rooms") should not surface a 3-room
    // (½-room tolerance). Relax if nothing meets it.
    final minR = query.minRooms;
    if (minR != null && minR > 0) {
      final enough = candidates.where((p) => p.rooms >= minR - 0.5).toList();
      if (enough.isNotEmpty) candidates = enough;
    }

    // Part 1 — market analysis + feature engineering. Use the PERSISTENT,
    // catalogue-wide baseline (segmented rent/sale) so value/percentile/hedonic
    // don't drift with this query's filtered set; fall back to per-query stats only
    // when the catalogue was too small to fit a baseline (tests / tiny markets).
    final isSale = candidates.isNotEmpty &&
        candidates.every(
            (p) => p.transactionType == PropertyTransactionType.sale);
    final market = (isSale ? saleBaseline : rentBaseline) ??
        MarketContext.analyze(candidates);

    // PERF CAP: per-candidate feature engineering + ranking is O(n) on the UI
    // isolate — ~1s over a 10k catalogue, a visible freeze that grows as the
    // background loader accumulates pages. City/budget-gated queries already shrink
    // far below this cap; only a BROAD (no-city) feed stays huge, and there any
    // representative subset ranks fine — the user swipes a few dozen. Keep the most
    // relevant slice by a CHEAP price heuristic (no gov lookups): within-budget /
    // cheapest / mainstream-priced, matching what the ranker would favour anyway.
    // ponytail: 1200 cap (~200ms); raise if broad-feed recall ever matters more.
    const kMaxRankCandidates = 1200;
    if (candidates.length > kMaxRankCandidates) {
      final maxP = query.maxPrice;
      final med = market.medianPrice > 0 ? market.medianPrice : 5000.0;
      int cost(RentalProperty p) {
        if (maxP != null && maxP > 0) {
          // in-budget first (priciest-within-budget ≈ best), over-budget last.
          return p.price <= maxP ? (maxP - p.price) : (p.price - maxP) + 100000000;
        }
        if (query.cheapPreference) return p.price;
        return (p.price - med).abs().round();
      }
      candidates = ([...candidates]..sort((a, b) => cost(a).compareTo(cost(b))))
          .sublist(0, kMaxRankCandidates);
    }
    final pfvs = [
      for (final p in candidates) _engineerCached(p, market),
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

    // IN-CITY FIRST (part 1/2): when the user named a specific city (not "אזור X"),
    // penalise adjacent-town candidates in the RANKING SCORE — BEFORE selection —
    // so an in-city flat is never dropped from the top-N by a stronger neighbour.
    // "דירה בתל אביב" must keep its Tel-Aviv options even when רמת גן scores higher.
    final areaSearch = query.intents.contains(SearchIntent.cityArea);
    final namedCity = query.city?.trim() ?? '';
    final cityGated = !areaSearch && namedCity.isNotEmpty;
    if (cityGated) {
      for (final c in ranked) {
        if (!_cityMatches(c.property, namedCity)) c.score *= 0.7;
      }
      ranked.sort((a, b) => b.score.compareTo(a.score));
    }

    // A REGION word without a city ("מרכז" / "השרון") = a broad AREA, not "central
    // within any city". Otherwise a central-Beer-Sheva flat outranks Tel Aviv for
    // "משהו במרכז". So when no city is named, softly down-weight listings outside
    // the referenced region (never a hard drop). Only when no city — a named city
    // keeps its own centre meaning.
    if (namedCity.isEmpty) {
      Set<String>? region;
      if (RegExp(r'השרון|בשרון|שרון(?![\wא-ת])').hasMatch(query.rawText)) {
        region = _sharonRegion;
      } else if (query.intents.contains(SearchIntent.central)) {
        region = _centralRegion;
      }
      if (region != null) {
        var touched = false;
        for (final c in ranked) {
          if (!_inRegion(c.property.city, region)) {
            c.score *= 0.6;
            touched = true;
          }
        }
        if (touched) ranked.sort((a, b) => b.score.compareTo(a.score));
      }
    }

    // NAMED NEIGHBOURHOOD ("דירה בפלורנטין") — an IDENTITY, like the city. Naming a
    // neighbourhood sharpens weights but doesn't, on its own, pull the flats
    // actually IN that neighbourhood to the top (centrality is coord-based and
    // similar for adjacent areas). So down-weight out-of-neighbourhood listings the
    // same way we do out-of-city ones — a "פלורנטין" search must surface Florentin
    // first. Soft (×0.6), never a hard drop.
    final namedHood = query.neighborhood?.trim() ?? '';
    if (namedHood.isNotEmpty) {
      final anyInHood =
          ranked.any((c) => _hoodMatches(c.property, namedHood));
      if (anyInHood) {
        for (final c in ranked) {
          if (!_hoodMatches(c.property, namedHood)) c.score *= 0.6;
        }
        ranked.sort((a, b) => b.score.compareTo(a.score));
      }
    }

    // Sub-city DIRECTION ("דרום תל אביב") + EXCLUDED areas ("לא רמת גן") — a SOFT
    // preference: matching listings are boosted / excluded ones sink, but nothing
    // is hard-dropped (never dead-ends). Purely coordinate + neighbourhood-name.
    if (query.areaDir != null || query.excludeAreas.isNotEmpty) {
      final regionCity = namedCity.isNotEmpty ? namedCity : (query.city ?? '');
      var touched = false;
      for (final c in ranked) {
        final mult = _locationRegionMultiplier(c.property, query, regionCity);
        if (mult != 1.0) {
          c.score *= mult;
          touched = true;
        }
      }
      if (touched) ranked.sort((a, b) => b.score.compareTo(a.score));
    }

    // COMMUTE re-rank: when the tenant supplied a work location, proximity to it is
    // a genuine, stated priority ("קרוב לעבודה") — so it must actually REORDER, not
    // just annotate the card (the commute scorecard axis carries weight 0). A
    // Gaussian-ish proximity boost (up to +30% for a flat at the workplace, ~0 by
    // 25 km) nudges nearer flats up without overriding budget/rooms/features.
    if (workLat != null && workLon != null &&
        workLat.abs() > 0.1 && workLon.abs() > 0.1) {
      for (final c in ranked) {
        final km = _km(c.property.lat, c.property.lon, workLat, workLon);
        if (!km.isFinite) continue;
        final prox = math.exp(-km / 8.0); // 1 at 0 km, ~0.29 at 10 km
        c.score *= 1.0 + 0.30 * prox;
      }
      ranked.sort((a, b) => b.score.compareTo(a.score));
    }

    // CHEAPEST re-rank: an explicit "הכי זול" is a request for the lowest PRICE,
    // not the best price-per-m² value (which the `value` dimension already scores).
    // Nudge by absolute cheapness (lowest price-percentile) so the actually-cheapest
    // in-scope flat surfaces, without letting it override a hard budget/rooms fit.
    if (query.cheapPreference) {
      for (final c in ranked) {
        final pctile = c.pfv.get('price_percentile', 0.5); // 0 = cheapest
        c.score *= 1.0 + 0.18 * (1.0 - pctile.clamp(0.0, 1.0));
      }
      ranked.sort((a, b) => b.score.compareTo(a.score));
    }

    // NO-BUDGET OUTLIER GUARD: when the user gave no price ceiling AND isn't after
    // luxury/investment, an absurd top-of-market flat (a ₪20k penthouse in a ₪5k
    // market) must not become the default #1 just because it satisfies the stated
    // dims (accessible / quiet …). Softly sink only the extreme top price-percentile
    // so a sensible flat wins (#30 senior-pension → ₪20k penthouse).
    final noBudgetOutlierGuard = maxP == null &&
        market.medianPrice > 0 &&
        !query.intents.contains(SearchIntent.luxury) &&
        !query.intents.contains(SearchIntent.investment);
    // Sink only a GENUINE outlier — priced above 2× the market median (a ₪20k flat
    // in a ₪5k market), scaling to a 0.55 cut at ~3.3× median. A merely above-median
    // flat (a ₪6k central flat vs ₪2.6k periphery) is left untouched, so this can't
    // fight the region/central preference.
    double _outlierPenalty(RankedCandidate c) {
      final ratio = c.property.price / market.medianPrice;
      if (ratio <= 2.0) return 1.0;
      return 1.0 - (0.55 * ((ratio - 2.0) / 1.3)).clamp(0.0, 0.55);
    }
    if (noBudgetOutlierGuard) {
      for (final c in ranked) {
        c.score *= _outlierPenalty(c);
      }
      ranked.sort((a, b) => b.score.compareTo(a.score));
    }

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
    // The DISPLAY order + fit% is driven by _statedMatch, so the same soft
    // preferences that re-ranked c.score (which only drives SELECTION) must ALSO
    // shape match[c] — else a named-neighbourhood / commute / cheapest search
    // selects the right flat but still orders it by generic stated-match. Apply
    // them here so the visible order and % reflect what the user actually asked.
    if (namedHood.isNotEmpty) {
      final anyIn = selected.any((c) => _hoodMatches(c.property, namedHood));
      if (anyIn) {
        for (final c in selected) {
          if (!_hoodMatches(c.property, namedHood)) match[c] = match[c]! * 0.6;
        }
      }
    }
    // Region ("מרכז"/"השרון") without a city — down-weight the DISPLAY of out-of-
    // region listings too, so a cheap peripheral flat doesn't top a region search.
    if (namedCity.isEmpty) {
      Set<String>? region;
      if (RegExp(r'השרון|בשרון|שרון(?![\wא-ת])').hasMatch(query.rawText)) {
        region = _sharonRegion;
      } else if (query.intents.contains(SearchIntent.central)) {
        region = _centralRegion;
      }
      if (region != null && selected.any((c) => _inRegion(c.property.city, region!))) {
        for (final c in selected) {
          if (!_inRegion(c.property.city, region)) match[c] = match[c]! * 0.55;
        }
      }
    }
    if (workLat != null && workLon != null &&
        workLat.abs() > 0.1 && workLon.abs() > 0.1) {
      for (final c in selected) {
        final km = _km(c.property.lat, c.property.lon, workLat, workLon);
        if (km.isFinite) {
          match[c] =
              (match[c]! * (1.0 + 0.30 * math.exp(-km / 8.0))).clamp(0.0, 1.0);
        }
      }
    }
    if (query.cheapPreference) {
      for (final c in selected) {
        final pctile = c.pfv.get('price_percentile', 0.5).clamp(0.0, 1.0);
        match[c] = (match[c]! * (1.0 + 0.18 * (1.0 - pctile))).clamp(0.0, 1.0);
      }
    }
    // Mirror the no-budget outlier guard on the DISPLAY scale (see selection above).
    if (noBudgetOutlierGuard) {
      for (final c in selected) {
        match[c] = (match[c]! * _outlierPenalty(c)).clamp(0.0, 1.0);
      }
    }
    // IN-CITY FIRST: cap each out-of-city flat's DISPLAYED match to just below the
    // weakest in-city one — so every in-city flat sorts first AND the fit% stays
    // monotonic. This runs LAST (after the cheap/commute boosts) so a cheaper
    // adjacent-town flat can never re-inflate past a named-city one in the display
    // order (#5 רמת גן → בני ברק). Pairs with the pre-selection score penalty.
    if (cityGated) {
      final inCity = [
        for (final c in selected)
          if (_cityMatches(c.property, namedCity)) match[c]!
      ];
      if (inCity.isNotEmpty) {
        final minIn = inCity.reduce(math.min);
        for (final c in selected) {
          if (!_cityMatches(c.property, namedCity)) {
            match[c] = math.min(match[c]!, minIn * 0.98);
          }
        }
      }
    }
    selected.sort((a, b) => match[b]!.compareTo(match[a]!));

    // Adjacent-town results are a BONUS, not the search: keep one only if it's a
    // genuinely strong fit, so a weak out-of-city listing never dilutes the
    // named-city results. Threshold is on the HONEST (un-inflated) scale — 0.63
    // here equals the old inflated 0.70, preserving the same real selectivity.
    // Run this BEFORE the backfill so pruning a weak neighbour frees a slot that
    // the backfill then re-fills from legitimate in-scope stock — the list stays
    // topped up to `want` rather than silently shrinking below it.
    if (nearbyKm.isNotEmpty) {
      selected.removeWhere((c) =>
          nearbyKm.containsKey(c.property.id) && (match[c] ?? 0) <= 0.63);
    }

    // Backfill: the softer gates can leave only a handful of exact matches, but a
    // user wants ~10 options. Top up from the in-city pool (relaxing budget /
    // features / rooms / sea, NOT city or rent/sale) with the closest near-matches,
    // ranked and appended STRICTLY BELOW the exact matches.
    final want = limit < 10 ? limit : 10;
    if (selected.length < want) {
      final have = selected.map((c) => c.property.id).toSet();
      // Backfill relaxes SOFT filters (features / rooms / sea) to reach ~10 options
      // — but NEVER the budget: a stated max is a hard ceiling, so a ₪5500 flat must
      // not pad a "עד 5000" search. (When nothing at all fit the budget, the primary
      // gate already switched to the cheapest cluster with an "over budget" concern.)
      final nearSeaStated = query.intents.contains(SearchIntent.nearSea);
      final extra = backfillPool.where((p) {
        if (have.contains(p.id)) return false;
        // The weak adjacent-town bonus flats were just pruned — don't re-add them.
        if (nearbyKm.containsKey(p.id)) return false;
        if (maxP != null && maxP > 0 && p.price > maxP) return false;
        if (nearSeaStated) {
          final km = IsraelGeoIndex.coastKm(p.lat, p.lon);
          // Same 4km cutoff as the primary near-sea gate — the backfill used
          // 5.0, quietly admitting flats the gate had just excluded.
          if (km == null || km > SearchIntent.notFarFromSeaKm) return false;
        }
        return true;
      }).toList();
      if (extra.isNotEmpty) {
        final extraRanked = RankingEngine.rank(
          [for (final p in extra) _engineerCached(p, market)],
          model,
        );
        final fill = DiversityReranker.select(extraRanked,
            limit: want - selected.length, lambda: diversityLambda);
        for (final c in fill) {
          match[c] = _statedMatch(c, model);
        }
        // These near-matches violate a stated filter, so they're genuinely weaker:
        // scale their fit to sit just BELOW the weakest exact match — preserving
        // both strict-first order AND the fit%-monotonic display invariant.
        final minStrict = selected.isEmpty ? 1.0 : match[selected.last]!;
        final maxFill =
            fill.fold<double>(0, (m, c) => match[c]! > m ? match[c]! : m);
        // Ceiling: below the weakest exact match AND never in "strong match"
        // territory — a near-match that breaks a stated filter is a compromise.
        final ceil = (minStrict * 0.95).clamp(0.0, 0.55);
        final scale = maxFill > 0 ? ceil / maxFill : 0.0;
        for (final c in fill) {
          match[c] = match[c]! * scale;
        }
        fill.sort((a, b) => match[b]!.compareTo(match[a]!));
        selected.addAll(fill); // after the sorted exact matches → strict-first
      }
    }

    // model confidence: how much intent we captured + behavioral confidence
    final intentCoverage =
        model.statedDimensions.length / kScoringDimensions.length;
    final baseConfidence =
        (0.4 + 0.4 * intentCoverage + 0.2 * model.learner.confidence)
            .clamp(0.0, 1.0);

    return [
      for (final c in selected)
        () {
          // Stash the learner feature vector for this SHOWN listing so a later
          // swipe can feed the online learner in O(1) — no recompute (see
          // DatingProvider._pfvCache / registerSwipeFeedback).
          learnerFeatureSink?[c.property.id] = model.learnerFeatures(c.pfv);
          final fitPct = (match[c]! * 100).round();
          final explanation = Explainer.explain(c, model);
          // Flag WHY an out-of-city listing surfaced: it hugs the searched city's
          // border and still scored high — so the user understands the suggestion.
          final nearKm = nearbyKm[c.property.id];
          final highlights = <String>[
            if (nearKm != null)
              '📍 בעיר שכנה — ${nearKm.toStringAsFixed(nearKm < 10 ? 1 : 0)} ק"מ מ${city ?? ''}, אבל התאמה גבוהה',
            ...Explainer.highlights(c, model, query.intents),
          ];
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

    // Most-relevant axes first: the dimensions the user ACTUALLY stated (their
    // budget, city, and every intent they voiced — safety/schools/quiet/…) lead,
    // ahead of always-on generic axes (value/condition/popularity/trust) the user
    // never asked about. So every apartment card shows what's relevant to THIS
    // search first, not a generic breakdown. Weight, then strength, break ties.
    final stated = model.statedDimensions;
    dimensions.sort((a, b) {
      final aS = stated.contains(a.key) ? 1 : 0;
      final bS = stated.contains(b.key) ? 1 : 0;
      if (aS != bS) return bS - aS;
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
      // The tenant SAVED a work address — that's a stated priority, and both
      // ranking surfaces now genuinely reorder by it (the ×1.30 boost in
      // recommend() and the bounded boost in relevance()). Displaying 0%
      // importance next to a re-ranking factor was dishonest; show the real
      // effective share the commute boost carries.
      weightPct: 0.12,
      contributionPct: score,
      stat: est.plainHebrewLabel,
      source: GovSources.labelFor(kCommuteDimensionKey),
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
      source: GovSources.labelFor(kTotalCostDimensionKey),
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
      source: GovSources.labelFor(kYieldDimensionKey),
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
    // NaN slips past `km > 8` (NaN comparisons are false) and then km.round()
    // throws — guard non-finite (a listing with Infinity/NaN coords).
    if (km == null || !km.isFinite || km > 8) return null;
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
      source: GovSources.labelFor(kCoastDimensionKey),
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
  // Normalise a city string for comparison: trim, unify hyphen/maqaf → space,
  // collapse whitespace. "תל אביב-יפו" and "תל אביב יפו" become comparable.
  static String _normCity(String s) => s
      .trim()
      .replaceAll(RegExp(r'[\-־]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');

  // Does a listing belong to the NAMED city? Matches the listing's own city (or a
  // moshav/neighbourhood recorded in [neighborhood]) against the query — full-name
  // containment only, so "עין עירון" matches "עין עירון" but NOT "אור עקיבא" or a
  // different "עין …". Distance is handled separately by the metro widening.
  static bool _cityMatches(RentalProperty p, String city) {
    final q = _normCity(city);
    if (q.isEmpty) return false;
    final pc = _normCity(p.city);
    if (_cityNameMatch(pc, q)) return true;
    final nb = _normCity(p.neighborhood);
    // Neighborhood/moshav recorded on the listing: exact or whole-word prefix.
    return nb.isNotEmpty && _cityNameMatch(nb, q);
  }

  /// Whole-word prefix match on normalized names: exact, or one is a leading
  /// whole word of the other ("תל אביב" ⊂ "תל אביב יפו"). Rejects mid/suffix
  /// containment across a word boundary so "יבנה" ≠ "גן יבנה".
  static bool _cityNameMatch(String a, String b) {
    if (a == b) return true;
    final shorter = a.length <= b.length ? a : b;
    final longer = a.length <= b.length ? b : a;
    return longer.startsWith('$shorter ');
  }

  // The central region (גוש דן + inner ring) — what "מרכז" means when no specific
  // city is named. A soft preference, never a hard gate.
  static const Set<String> _centralRegion = {
    'תל אביב', 'תל אביב יפו', 'רמת גן', 'גבעתיים', 'בני ברק', 'הרצליה',
    'רמת השרון', 'גבעת שמואל', 'קרית אונו', 'פתח תקווה', 'ראשון לציון', 'חולון',
    'בת ים', 'אור יהודה', 'יהוד', 'כפר סבא', 'רעננה', 'הוד השרון', 'נס ציונה',
    'רחובות', 'לוד', 'רמלה', 'אזור', 'גני תקווה',
  };

  // The Sharon region — what "השרון" means when no specific city is named.
  static const Set<String> _sharonRegion = {
    'הרצליה', 'רמת השרון', 'הוד השרון', 'רעננה', 'כפר סבא', 'כפר יונה',
    'נתניה', 'אבן יהודה', 'צור יגאל', 'קדימה צורן', 'תל מונד', 'רמת גן',
  };

  static bool _inRegion(String city, Set<String> region) {
    final c = _normCity(city);
    for (final r in region) {
      if (c == r || c.contains(r) || r.contains(c)) return true;
    }
    return false;
  }

  // Does a listing sit in the NAMED neighbourhood? Matches the recorded
  // neighbourhood (either-way containment, hyphen/space-normalised).
  static bool _hoodMatches(RentalProperty p, String hood) {
    final q = _normCity(hood);
    if (q.isEmpty) return false;
    final nb = _normCity(p.neighborhood);
    return nb.isNotEmpty && (nb == q || nb.contains(q) || q.contains(nb));
  }

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

  // Sub-city direction → known neighbourhood clusters (name-based). Tel Aviv is
  // the dense case; other cities fall back to the coordinate half-plane below.
  static const _dirClusters = <String, Map<String, List<String>>>{
    'תל אביב': {
      'דרום': ['פלורנטין', 'שפירא', 'נווה שאנן', 'קרית שלום', 'יד אליהו',
        'התקווה', 'נווה צדק', 'כרם התימנים', 'מונטיפיורי', 'ביצרון'],
      'צפון': ['רמת אביב', 'הצפון הישן', 'הצפון החדש', 'בבלי', 'אפקה',
        'תל ברוך', 'רמת החייל', 'נווה אביבים', 'כוכב הצפון'],
      'מרכז': ['לב העיר', 'רוטשילד', 'הכרם', 'מרכז העיר', 'גן העיר'],
      'מזרח': ['רמת החייל', 'יד אליהו', 'ביצרון', 'נחלת יצחק', 'רמת ישראל'],
      'מערב': ['נווה צדק', 'כרם התימנים', 'גן הכובשים'],
    },
  };

  /// Is [p] in the [dir] region of [city]? true=in · false=out · null=can't tell.
  static bool? _inDirection(RentalProperty p, String city, String dir) {
    final clusters = _dirClusters[_normCity(city)] ?? _dirClusters[city.trim()];
    if (clusters != null && p.neighborhood.trim().isNotEmpty) {
      final names = clusters[dir];
      if (names != null && names.any((n) => p.neighborhood.contains(n))) {
        return true;
      }
    }
    final gov = GovData.instance.localityByName(city);
    if (gov != null && gov.lat.abs() > 0.1 && p.lat.abs() > 0.1) {
      switch (dir) {
        case 'דרום':
          return p.lat < gov.lat - 0.004; // ~400m buffer around the centroid
        case 'צפון':
          return p.lat > gov.lat + 0.004;
        case 'מזרח':
          return p.lon > gov.lon + 0.004;
        case 'מערב':
          return p.lon < gov.lon - 0.004;
        case 'מרכז':
          return _km(p.lat, p.lon, gov.lat, gov.lon) <= 2.5;
      }
    }
    return null;
  }

  /// Soft location multiplier for direction + excluded areas (never 0).
  static double _locationRegionMultiplier(
      RentalProperty p, SearchQuery q, String city) {
    double m = 1.0;
    if (q.excludeAreas.isNotEmpty) {
      final hay = _normCity('${p.city} ${p.neighborhood}');
      for (final area in q.excludeAreas) {
        final a = _normCity(area);
        if (a.isNotEmpty && hay.contains(a)) {
          m *= 0.35; // an explicitly-avoided place sinks hard (but never vanishes)
          break;
        }
      }
    }
    final dir = q.areaDir;
    if (dir != null && city.isNotEmpty) {
      final inR = _inDirection(p, city, dir);
      if (inR != null) {
        if (q.areaDirExclude) {
          if (inR) m *= 0.35; // "לא בדרום" → sink flats in that direction
        } else if (!inR) {
          m *= 0.55; // "דרום" → prefer that direction, downweight the rest
        }
      }
    }
    return m;
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
    // HONEST fit: the weighted satisfaction of the user's STATED criteria (mostly),
    // plus a small overall-quality term so it isn't a single axis and ties break by
    // quality. Both are 0..1. NO cosmetic inflation — the % means exactly what it
    // says: "this listing satisfies ~X% of what you asked for". A listing that
    // fully meets the criteria and also scores well still reaches ~90%+ ("perfect");
    // a partial match now reads at its true level instead of being padded upward.
    return (0.85 * (acc / wsum) + 0.15 * c.score).clamp(0.0, 1.0);
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
        final base = over <= 10
            ? 'מעט מעל התקציב שלך'
            : 'מעל התקציב שלך בכ-$over%';
        // Phase 4 — trade-off narration: a real agent doesn't just flag "over
        // budget", they say what you GET for it. Tie the concern to the single
        // strongest offsetting quality so the compromise is explicit, not scary.
        ScorecardDimension? strength;
        for (final d in dimensions) {
          if (d.key == 'budget' || d.key == 'total_cost') continue;
          if (d.contributionPct < 0.6) continue;
          if (strength == null || d.contributionPct > strength.contributionPct) {
            strength = d;
          }
        }
        concerns.add(strength != null
            ? '$base — אבל ${strength.label} מצוין, ששווה את זה'
            : base);
      } else if (price <= maxBudget * 0.95 &&
          c.property.transactionType != PropertyTransactionType.sale) {
        // Budget BLIND-SPOT only: the rent LOOKS comfortably affordable (≤95% of
        // budget) yet arnona + vaad quietly push the true cost over by a real
        // margin (>5%). If the rent is already near budget the tenant knows
        // they're stretching, so we stay quiet — no concern on every card.
        final cost = MonthlyCost.estimate(
            rent: price, sizeM2: c.property.sizeM2, city: c.property.city);
        if (cost != null && cost.total > maxBudget * 1.05) {
          concerns.add('נראית זולה, אבל העלות הכוללת '
              '(${cost.plainHebrewLabel}) חורגת מהתקציב');
        }
      }
    }

    // Only GENUINELY weak spots on axes the user cares about — not axes that are
    // merely mediocre. Capped at 2 so a card isn't a wall of caveats.
    for (final d in dimensions) {
      if (concerns.length >= 2) break;
      if (d.key == 'budget') continue; // covered above
      // Skip axes that are NOT quality defects: demographic context (a low score
      // just means "not that kind of area"), and ASPIRATIONAL/inferred axes whose
      // low value is often the OPPOSITE of what the seeker wants — e.g. flagging
      // "view weak" to someone who asked for a LOW floor, or "nightlife weak" to a
      // family. These bleed in via soft inference weights and read as nonsense.
      // Demographic context + ASPIRATIONAL axes whose low value isn't a defect and
      // is often the OPPOSITE of the ask (e.g. "view weak" to a low-floor seeker,
      // whose garden request inferred a view weight). Genuinely-stated axes like
      // nightlife/park/coast still caveat honestly (they resolve in production).
      const notADefect = {
        'senior_area', 'young_area', 'family', 'view', 'luxury', 'low_floor',
      };
      if (notADefect.contains(d.key)) continue;
      if (d.contributionPct >= 0.35) continue; // genuinely weak only
      // Only caveat what the user ACTUALLY asked about (stated) — an inferred
      // weight must never generate a scary caveat the user never raised.
      if (!model.statedDimensions.contains(d.key)) continue;
      concerns.add('${d.label} פחות חזק כאן');
    }
    return concerns;
  }

  /// PURE per-property relevance in [0,1] — the ranker's blended, calibrated score
  /// (MAUT + GBM + learner, Platt-calibrated, × soft-constraint) WITHOUT the
  /// orchestrator's city/budget gates, diversity rerank, backfill or 10-slate
  /// logic. For callers that do their OWN filtering and just need one stable,
  /// comparable relevance per listing (e.g. the swipe deck). [marketSource] fits
  /// the value/hedonic baseline — pass the FULL catalogue for a stable,
  /// non-batch-relative baseline; defaults to [candidates].
  static Map<String, double> relevance({
    required List<RentalProperty> candidates,
    required SearchQuery query,
    TenantProfile? profile,
    List<RentalProperty>? marketSource,
    // The per-user FTRL model. Without it every deck rank built a COLD learner
    // (confidence 0 → learner component weight 0), so months of swipe training
    // never influenced the surface that generated the training data.
    OnlineLogisticLearner? learner,
  }) {
    if (candidates.isEmpty) return const {};
    // Baseline over the transaction-consistent slice of the market source (never
    // judge a rental's value against sale prices), mirroring recommend().
    final isSale = candidates
        .every((p) => p.transactionType == PropertyTransactionType.sale);
    final src = marketSource ?? candidates;
    final seg = [
      for (final p in src)
        if ((p.transactionType == PropertyTransactionType.sale) == isSale) p,
    ];
    final market =
        MarketContext.analyzeCached(seg.length >= 8 ? seg : candidates);
    final model = PreferenceModelBuilder.build(
        query: query, profile: profile, market: market, learner: learner);
    final ranked = RankingEngine.rank(
      [for (final p in candidates) _engineerCached(p, market)],
      model,
    );
    // Return the honest fit% (_statedMatch), NOT the raw blended score: it reads
    // as "how well this satisfies what you asked for" on a percentage-like band,
    // which is what a caller wants to display AND what keeps a caller's own ±
    // deltas (calibrated against that band) meaningful.
    final out = {for (final c in ranked) c.property.id: _statedMatch(c, model)};
    // COMMUTE on the DECK: the tenant's saved work location used to reorder
    // only the chat surface — the main feed ignored it entirely. A bounded
    // additive proximity boost (≤ +0.12 for a flat AT the workplace, ~0 by
    // ~18 km) keeps the 0..1 fit band intact while genuinely reordering.
    final workLat = profile?.workLat, workLon = profile?.workLon;
    if (workLat != null && workLon != null &&
        workLat.abs() > 0.1 && workLon.abs() > 0.1) {
      for (final c in ranked) {
        final km = _km(c.property.lat, c.property.lon, workLat, workLon);
        if (!km.isFinite) continue;
        final prox = math.exp(-km / 6.0);
        final id = c.property.id;
        out[id] = ((out[id] ?? 0) + 0.12 * prox).clamp(0.0, 1.0);
      }
    }
    return out;
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
