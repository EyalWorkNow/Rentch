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
      if (uni != null && uni.km <= 1.5) chips.add('🎓 ${_dist(uni.km)} מ${uni.name}');
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
      if (areaMode && inCity.isNotEmpty) {
        final cLat =
            inCity.map((p) => p.lat).reduce((a, b) => a + b) / inCity.length;
        final cLon =
            inCity.map((p) => p.lon).reduce((a, b) => a + b) / inCity.length;
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
      final ok = candidates
          .where((p) =>
              query.requiredFeatures.every((k) => propertyHasFeature(p, k)))
          .toList();
      if (ok.isNotEmpty) {
        candidates = ok;
      } else {
        // No listing has ALL must-haves → fall back to the NON-NEGOTIABLE ones
        // (a dog can't live in a no-pets building; a family in a shelter zone
        // needs a mamad). Softer must-haves (parking/furnished/elevator) yield.
        const absolute = {'petsAllowed', 'mamad'};
        final reqAbs = query.requiredFeatures.where(absolute.contains).toSet();
        if (reqAbs.isNotEmpty) {
          final absOk = candidates
              .where((p) => reqAbs.every((k) => propertyHasFeature(p, k)))
              .toList();
          if (absOk.isNotEmpty) candidates = absOk;
        }
      }
    }

    // Near-sea gate: excludes the clearly-inland (so "קרוב לים" never returns
    // ירושלים), but stays forgiving — "לא רחוק מהים" in a coastal city still
    // means a few km inland is fine. So the GATE is a generous 5km while the
    // coast dimension below orders the survivors by exact distance (beachfront
    // first). Relax entirely if nothing qualifies.
    if (query.intents.contains(SearchIntent.nearSea)) {
      const seaGateKm = 5.0;
      final nearSea = candidates.where((p) {
        final km = IsraelGeoIndex.coastKm(p.lat, p.lon);
        return km != null && km <= seaGateKm;
      }).toList();
      if (nearSea.isNotEmpty) candidates = nearSea;
    }

    // Backfill pool captured HERE — after the IDENTITY gates (city, must-have
    // features, near-sea) but before the SOFT ones (budget, rooms). So topping the
    // list up to ~10 relaxes only budget/rooms (a "slightly over budget" or
    // "one room fewer" near-match), NEVER the identity: a "קרוב לים" search is
    // never backfilled with an inland flat, nor a "must-have mamad" with one lacking it.
    final backfillPool = List.of(candidates);

    // Budget gate: when the user states a max budget, don't surface listings far
    // over it (>15%) while in-budget options exist. Relax to the cheapest cluster
    // when NOTHING fits (the "over budget" concern makes the compromise explicit).
    final maxP = query.maxPrice;
    if (maxP != null && maxP > 0) {
      final within = candidates.where((p) => p.price <= maxP * 1.15).toList();
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

    // Backfill: the softer gates can leave only a handful of exact matches, but a
    // user wants ~10 options. Top up from the in-city pool (relaxing budget /
    // features / rooms / sea, NOT city or rent/sale) with the closest near-matches,
    // ranked and appended STRICTLY BELOW the exact matches.
    final want = limit < 10 ? limit : 10;
    if (selected.length < want) {
      final have = selected.map((c) => c.property.id).toSet();
      final extra = backfillPool.where((p) => !have.contains(p.id)).toList();
      if (extra.isNotEmpty) {
        final extraRanked = RankingEngine.rank(
          [for (final p in extra) FeatureEngineer.engineer(p, market)],
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

    // Adjacent-town results are a BONUS, not the search: keep one only if it's a
    // genuinely strong fit (>70%), so a weak out-of-city listing never dilutes the
    // named-city results. (Backfilled fills are already capped ≤0.55 → dropped here.)
    if (nearbyKm.isNotEmpty) {
      selected.removeWhere((c) =>
          nearbyKm.containsKey(c.property.id) && (match[c] ?? 0) <= 0.70);
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
    if (pc == q || pc.contains(q) || q.contains(pc)) return true;
    final nb = _normCity(p.neighborhood);
    return nb.isNotEmpty && (nb == q || nb.contains(q));
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
    // Mostly the stated-criteria fit (weigh it more; the ranking blend carries
    // trust/popularity the user didn't ask about, which shouldn't drag the %).
    final m = (0.85 * (acc / wsum) + 0.15 * c.score).clamp(0.0, 1.0);
    // Display calibration: a genuinely good match (~0.7) should READ as strong
    // (~0.85). Expand the upper half only — weak matches (≤0.5) are untouched, and
    // the transform is monotonic so the display order is preserved.
    return (m <= 0.5 ? m : (0.5 + (m - 0.5) * 1.5)).clamp(0.0, 1.0);
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
