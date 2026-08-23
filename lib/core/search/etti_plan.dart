import 'package:dating_app/core/search/anchor_resolver.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart' show TransactionTypeFilter;

/// ETTI PLAN — the structured output of the "Etti" intent-extraction engine.
///
/// Etti (the LLM) reads the user's free text, reasons about Israeli housing
/// culture, and emits: `hard_constraints` (absolute deal-breakers), `soft_weights`
/// (factor → 1.0-neutral importance, up to 2.0), and an `inferred_persona`.
/// This class folds that into the engine's [SearchQuery], applying the collision
/// hierarchy:
///   1. hard constraints  → gating filters (city / budget / transaction / features)
///   2. deal-breakers     → a required feature PLUS an aggressive weight
///   3. soft preferences  → continuous weights (never a hard veto)
///
/// A deterministic [SearchQuery] fallback (explicit numbers the model may have
/// missed, or hallucinations to correct) is merged underneath — hard constraints
/// from Etti win, but the fallback fills any gap.
class EttiPlan {
  const EttiPlan({
    required this.hardConstraints,
    required this.softWeights,
    required this.persona,
  });

  final Map<String, dynamic> hardConstraints;
  final Map<String, double> softWeights; // Etti factor name → weight (−1..2)
  final String persona;

  factory EttiPlan.fromJson(Map<String, dynamic> j) {
    final hc = <String, dynamic>{};
    (j['hard_constraints'] as Map?)?.forEach((k, v) => hc['$k'] = v);
    final sw = <String, double>{};
    (j['soft_weights'] as Map?)?.forEach((k, v) {
      final d = v is num ? v.toDouble() : double.tryParse('$v');
      if (d != null) sw['$k'] = d;
    });
    return EttiPlan(
      hardConstraints: hc,
      softWeights: sw,
      persona: j['inferred_persona']?.toString() ?? '',
    );
  }

  bool get isEmpty => hardConstraints.isEmpty && softWeights.isEmpty;

  /// Etti's [−1..2] weight (1.0 neutral) → engine importance [0..1], with a
  /// SUPER-LINEAR curve above the midpoint: a factor the model flagged as "very
  /// important" (raw ≥ ~1.7) becomes decisive rather than averaging out against
  /// value/budget. `size:-1.0` (undesired) → 0 (deprioritised, never a veto).
  static double _importance(double rawWeight) {
    // BELOW neutral is a real signal, not noise: the model's own worked
    // example emits `size:-1.0` ("willing to sacrifice size"). The old clamp
    // dropped every raw < 1.0, so "מוכן לוותר על X" never reached the ranker.
    // raw ∈ [-1, 1) → a small explicit de-prioritisation (0.03..0.12) that
    // REPLACES the default weight instead of leaving it untouched.
    if (rawWeight < 1.0) {
      final t = ((rawWeight + 1.0) / 2.0).clamp(0.0, 1.0); // -1→0, 1→1
      return 0.03 + t * 0.09;
    }
    final base = (rawWeight - 1.0).clamp(0.0, 1.0).toDouble();
    if (base <= 0.5) return base; // neutral..moderate stays linear
    return (0.5 + (base - 0.5) * 1.8).clamp(0.0, 1.0); // strong signals amplified
  }

  // Etti's friendly factor names → the engine's factor keys (understood by
  // PreferenceModelBuilder.factorToDimension). Deal-breaker features handled below.
  static const Map<String, String> _alias = {
    'family_friendly': 'family', 'family': 'family',
    'schools_nearby': 'schools', 'schools': 'schools', 'good_schools': 'schools',
    'accessibility_stroller': 'accessible', 'ground_floor': 'accessible',
    'accessibility': 'accessible', 'accessible': 'accessible',
    'quiet_neighborhood': 'quiet', 'quiet': 'quiet',
    'near_sea': 'near_sea', 'sea': 'near_sea', 'beach': 'near_sea',
    'central_location': 'central', 'central': 'central', 'centrality': 'central',
    'nightlife': 'nightlife', 'vibrant': 'nightlife',
    'security': 'safety', 'safety': 'safety',
    'transit': 'transit', 'public_transport': 'transit',
    'size': 'size', 'value': 'value', 'budget': 'budget', 'price': 'budget',
    'luxury': 'luxury', 'premium': 'luxury', 'view': 'view',
    'yield': 'yield', 'investment': 'yield', 'high_demand_areas': 'transit',
    'university': 'university', 'near_university': 'university',
    'spacious': 'spacious', 'spaciousness': 'spacious',
    'quality_area': 'quality_area', 'neighborhood': 'quality_area',
    'condition': 'condition', 'renovated': 'condition', 'amenities': 'amenities',
  };

  // Factor keys that are ALSO spatial intents → adding them fires the matching
  // gate (near-sea distance, etc.) in the engine.
  static const Set<String> _intentFactors = {
    'near_sea', 'nightlife', 'quiet', 'central', 'spacious', 'accessible',
    'luxury', 'view', 'university', 'investment', 'good_schools', 'quality_area',
  };

  /// Build the engine [SearchQuery]. [fallback] = the deterministic parse
  /// (SmartSearch) whose explicit numbers fill any gaps Etti left.
  SearchQuery toQuery({SearchQuery? fallback}) {
    final fb = fallback ?? SearchQuery();
    String? s(dynamic v) => v?.toString().trim().isNotEmpty == true ? '$v'.trim() : null;
    int? i(dynamic v) => v is num ? v.round() : int.tryParse('${v ?? ''}');
    double? n(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

    // ── 1. hard constraints (gating) ──────────────────────────────────────────
    final city = s(hardConstraints['city']) ?? fb.city;
    final maxPrice = i(hardConstraints['max_price'] ?? hardConstraints['maxPrice']) ??
        fb.maxPrice;
    final minPrice = i(hardConstraints['min_price'] ?? hardConstraints['minPrice']) ??
        fb.minPrice;
    final minRooms = n(hardConstraints['min_rooms'] ??
            hardConstraints['minRooms'] ??
            hardConstraints['rooms']) ??
        fb.minRooms;
    final maxRooms = n(hardConstraints['max_rooms'] ?? hardConstraints['maxRooms']) ??
        fb.maxRooms;
    final tx = switch (s(hardConstraints['transaction_type'])?.toLowerCase()) {
      'sale' => TransactionTypeFilter.sale,
      'rent' => TransactionTypeFilter.rent,
      _ => fb.transactionType,
    };
    // The prompt doesn't enumerate a closed key set, so the model routinely
    // emits keys that ARE representable in SearchQuery but used to be silently
    // dropped — neighborhood and property_type being the costly ones.
    final neighborhood = s(hardConstraints['neighborhood'] ??
            hardConstraints['area'] ??
            hardConstraints['שכונה']) ??
        fb.neighborhood;
    final propertyType = s(hardConstraints['property_type'] ??
            hardConstraints['propertyType'] ??
            hardConstraints['type']) ??
        fb.propertyType;
    // "לא רחוק מ-X" as a structured constraint (the on-device parse already
    // resolves it from rawText — this catches the model's explicit key too).
    final nearPlace = s(hardConstraints['near_place'] ??
        hardConstraints['nearPlace'] ??
        hardConstraints['near']);
    final anchor = (nearPlace != null
            ? AnchorResolver.resolveNamed(nearPlace)
            : null) ??
        fb.anchor;

    // ── 2. deal-breaker features (required amenity + aggressive weight) ────────
    final features = <String>{...fb.amenities};
    final weights = <String, double>{...fb.weights};
    final required = <String>{...fb.requiredFeatures};
    // A hard deal-breaker → a required amenity + aggressive weight, AND (for a
    // CONCRETE feature) a hard exclusion of listings that lack it. 'accessible'
    // is NOT a single feature (floor+elevator logic) → weight only, no hard veto.
    void dealBreaker(String hcKey, String featKey, String weightFactor,
        {String? hardCanonical}) {
      if (hardConstraints[hcKey] == true) {
        features.add(featKey);
        weights[weightFactor] = 1.0;
        if (hardCanonical != null) required.add(hardCanonical);
      }
    }
    dealBreaker('mamad', 'feat_mamad', 'safety', hardCanonical: 'mamad');
    dealBreaker('ממ"ד', 'feat_mamad', 'safety', hardCanonical: 'mamad');
    dealBreaker('parking', 'feat_parking', 'amenities', hardCanonical: 'parking');
    dealBreaker('elevator', 'feat_elevator', 'accessible', hardCanonical: 'elevator');
    // Common hard asks the model emits that used to vanish (canonical keys
    // verified against the feature catalog in rental_models.dart).
    dealBreaker('balcony', 'feat_balcony', 'amenities', hardCanonical: 'balcony');
    dealBreaker('storage', 'feat_storage', 'amenities', hardCanonical: 'storage');
    dealBreaker('air_conditioning', 'feat_ac', 'amenities',
        hardCanonical: 'airConditioning');
    dealBreaker('garden', 'feat_garden', 'amenities', hardCanonical: 'garden');
    // pets is a HARD gate (petsAllowed veto) — weight is nearly cosmetic, but it
    // must NOT be 'accessible' or a pet owner sees a bogus "נגישות פחות חזק" concern.
    dealBreaker('pets', 'feat_pets', 'amenities', hardCanonical: 'petsAllowed');
    dealBreaker('accessible', 'feat_accessible', 'accessible');
    dealBreaker('furnished', 'feat_furnished', 'amenities', hardCanonical: 'furnished');

    // ── 3. soft weights (continuous; 1.0 neutral → 0, 2.0 → 1.0) ──────────────
    final intents = <String>{...fb.intents};
    softWeights.forEach((k, w) {
      final imp = _importance(w);
      if (imp <= 0) return;
      // The model sometimes combines factor names ("safety/security",
      // "accessibility_stroller/ground_floor") — split and map each part.
      for (final part in k.toLowerCase().split('/')) {
        final factor = _alias[part.trim()] ?? part.trim();
        weights[factor] = imp > (weights[factor] ?? 0) ? imp : weights[factor]!;
        if (_intentFactors.contains(factor)) intents.add(factor);
      }
    });
    // Anything present as a required feature is also its intent (gate).
    if (features.contains('feat_accessible') ||
        hardConstraints['accessible'] == true) {
      intents.add(SearchIntent.accessible);
    }

    return SearchQuery(
      city: city,
      neighborhood: neighborhood,
      propertyType: propertyType,
      minPrice: minPrice,
      maxPrice: maxPrice,
      minRooms: minRooms,
      maxRooms: maxRooms,
      transactionType: tx,
      amenities: features,
      requiredFeatures: required,
      weights: weights,
      intents: intents,
      rawText: fb.rawText,
      preferredNearbyDims: fb.preferredNearbyDims,
      anchor: anchor,
    );
  }
}
