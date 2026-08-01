// Area Intelligence (supply side): profile a LOCATION with every gov-data layer
// and score how well it serves a target tenant/buyer persona — the inverse of the
// tenant search engine, reusing the SAME FeatureEngineer + preference model.
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/insights/target_personas.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/preference_model.dart';
import 'package:dating_app/data/models/rental_models.dart';

/// One scored reason ("why this area fits") — a layer + how strong it is.
class AreaReason {
  const AreaReason(this.label, this.strength);
  final String label; // Hebrew
  final double strength; // 0..1
}

/// Investment lens for an area — honest about what's current vs stale.
class InvestmentLens {
  const InvestmentLens({
    required this.rentability,
    required this.appreciation,
    required this.investmentScore,
    this.relativePriceTier,
    this.valuePerSqm2013,
    this.roughYieldPct,
  });

  final double rentability; // 0..1 — how easy to rent out (CURRENT gov signals)
  final double appreciation; // 0..1 — planned-infra upside (CURRENT)
  final int investmentScore; // 0..100 combined heuristic
  final double? relativePriceTier; // 0..1 CBS 2013 rank (relative, not absolute)
  final int? valuePerSqm2013; // ₪/m² (2013 — stale absolute)
  final double? roughYieldPct; // labelled rough estimate (rent ÷ inflated 2013 value)
}

/// The full gov-data profile of a point, ready for the card UI.
class AreaProfile {
  const AreaProfile({
    required this.lat,
    required this.lon,
    required this.city,
    required this.sesCluster,
    required this.socioeconomic,
    required this.safety,
    required this.centrality,
    required this.transit,
    required this.railKm,
    required this.schools,
    required this.youngShare,
    required this.childShare,
    required this.seniorShare,
    required this.nightlife,
    required this.employment,
    required this.futureValue,
    required this.health,
    required this.coastKm,
    required this.parkAccess,
    required this.pfv,
    required this.investment,
    this.demographicsAvailable = false,
  });

  final double lat, lon;
  final String city;
  final int sesCluster; // 1..10 (0 = unknown block)
  final double socioeconomic, safety, centrality, transit; // 0..1
  final double? railKm, coastKm;
  final double schools, youngShare, childShare, seniorShare;
  final double nightlife, employment, futureValue, health, parkAccess;
  final PropertyFeatureVector pfv;
  final InvestmentLens investment;

  /// True only when a REAL CBS statistical area backs the demographic shares.
  /// When false, [youngShare]/[childShare]/[seniorShare] are neutral 0.5
  /// placeholders (dataset not loaded) and must NOT be shown as precise %.
  final bool demographicsAvailable;
}

class PersonaFit {
  const PersonaFit(this.persona, this.pct, this.reasons);
  final TargetPersona persona;
  final int pct; // 0..100
  final List<AreaReason> reasons; // top contributing layers
}

/// One statistical area ranked for a persona (list + map row).
class RankedArea {
  const RankedArea(this.area, this.profile, this.fit);
  final StatArea area;
  final AreaProfile profile;
  final PersonaFit fit;
  List<double> get centroid => area.centroid; // [lat, lon]
  List<List<double>> get poly => area.poly;
}

class AreaIntelligence {
  const AreaIntelligence._();

  // The dimensions that describe a PLACE (not a specific flat). Area fit is scored
  // over these only — budget/rooms/amenities/condition are property-level.
  static const List<String> _placeDims = [
    'location', 'neighborhood', 'safety', 'transit', 'schools', 'family',
    'health', 'coast', 'park', 'religious_area', 'nightlife', 'young_area',
    'senior_area', 'employment', 'convenience', 'low_noise', 'future_value',
    'university',
  ];

  static const Map<String, String> _label = {
    'location': 'מרכזיות', 'neighborhood': 'איכות אזור (סוציו-אקונומי)',
    'safety': 'בטיחות', 'transit': 'תחבורה ציבורית', 'schools': 'מוסדות חינוך',
    'family': 'אופי משפחתי', 'health': 'שירותי בריאות', 'coast': 'קרבה לים',
    'park': 'פארקים וירוק', 'religious_area': 'קהילה דתית',
    'nightlife': 'חיי לילה ובילוי', 'young_area': 'אוכלוסייה צעירה',
    'senior_area': 'אזור שקט/מבוגר', 'employment': 'קרבה לתעסוקה',
    'convenience': 'סופר וקניות', 'low_noise': 'שקט מרעש',
    'future_value': 'פוטנציאל השבחה', 'university': 'קרבה לאוניברסיטה',
  };

  // A tiny fixed market so FeatureEngineer can run — the PLACE layers come from
  // GovData/GeoIntelligence, not the market, so its contents don't affect them.
  static MarketContext? _market;
  static MarketContext _dummyMarket() => _market ??= MarketContext.analyze([
        for (var i = 0; i < 10; i++)
          RentalProperty(
              id: 'seed$i', price: 5000 + i * 300, rooms: 3, sizeM2: 70,
              floor: '2', totalFloors: '6', city: 'תל אביב', neighborhood: '',
              street: 'x', streetNumber: 1, lat: 32.07, lon: 34.78,
              propertyType: 'דירה', entryDate: '', condition: 'טוב',
              ownerName: 'x', agencyListing: false, features: const [],
              media: const [
                PropertyMedia(url: 'u', type: PropertyMediaType.image)
              ]),
      ]);

  static RentalProperty _syntheticAt(double lat, double lon, String city) =>
      RentalProperty(
          id: 'area', price: 6000, rooms: 3, sizeM2: 70, floor: '2',
          totalFloors: '6', city: city, neighborhood: '', street: '',
          streetNumber: 0, lat: lat, lon: lon, propertyType: 'דירה',
          entryDate: '', condition: 'טוב', ownerName: '', agencyListing: false,
          features: const [],
          media: const [PropertyMedia(url: 'u', type: PropertyMediaType.image)]);

  /// Full gov-data profile of a point.
  static AreaProfile profileAt(double lat, double lon, {String city = ''}) {
    final pfv = FeatureEngineer.engineer(_syntheticAt(lat, lon, city), _dummyMarket());
    final sa = GovData.instance.loaded
        ? GovData.instance.statAreaAt(lat, lon)
        : null;
    double g(String k, [double d = 0.0]) => pfv.get(k, d);
    final gov = GovData.instance;
    // ── investment lens ────────────────────────────────────────────────────
    // Rentability = how easy to let (CURRENT gov signals). Appreciation = planned
    // infra. Price = CBS 2013 relative rank only. A rough yield uses current city
    // rent ÷ the 2013 value inflated by the national 2013→now index (~2.1×) — a
    // labelled ESTIMATE, never presented as precise.
    final rentability = (0.35 * g('transit_access') +
            0.30 * g('centrality', 0.5) +
            0.20 * g('employment_access') +
            0.15 * g('demo_young', 0.5))
        .clamp(0.0, 1.0);
    final appreciation = g('future_value');
    final priceTier = sa != null ? gov.areaValuePercentile(sa.id) : null;
    final value2013 = sa != null ? gov.areaValuePerSqm(sa.id) : null;
    final rentSqm = city.isNotEmpty ? gov.rentPerSqm(city) : null;
    final roughYield = (value2013 != null && rentSqm != null && rentSqm > 0)
        ? (rentSqm * 12) / (value2013 * 2.1) * 100
        : null;
    // Combined score: rentability + upside reward, cheaper areas score higher
    // (better yield headroom). Falls back gracefully when price is unknown.
    final invScore = priceTier != null
        ? (50 * rentability + 30 * appreciation + 20 * (1 - priceTier))
        : (65 * rentability + 35 * appreciation);
    final investment = InvestmentLens(
      rentability: rentability,
      appreciation: appreciation,
      investmentScore: invScore.round().clamp(0, 100),
      relativePriceTier: priceTier,
      valuePerSqm2013: value2013,
      roughYieldPct: roughYield,
    );
    final railKm = g('rail_km', 99);
    final coastKm = g('coast_access', -1) > 0
        ? null // engineered as a kernel; expose the km separately if needed
        : null;
    return AreaProfile(
      lat: lat, lon: lon, city: city,
      sesCluster: sa?.ses ?? 0,
      socioeconomic: g('socioeconomic', 0.5),
      safety: g('safety', 0.5),
      centrality: g('centrality', 0.5),
      transit: g('transit_access'),
      railKm: railKm < 90 ? railKm : null,
      schools: g('school_access'),
      youngShare: g('demo_young', 0.5),
      childShare: g('demo_child', 0.5),
      seniorShare: g('demo_senior', 0.5),
      // Real demographics require a matched CBS statistical area.
      demographicsAvailable: sa != null,
      nightlife: g('nightlife'),
      employment: g('employment_access'),
      futureValue: g('future_value'),
      health: g('health_access'),
      coastKm: coastKm,
      parkAccess: g('park_access'),
      pfv: pfv,
      investment: investment,
    );
  }

  /// How well [pfv] (a place) serves [persona]: a 0..100 fit + the top reasons.
  static PersonaFit fit(PropertyFeatureVector pfv, TargetPersona persona) {
    final model = PreferenceModelBuilder.build(
        query: persona.query, market: _dummyMarket());
    double wsum = 0, acc = 0;
    final contrib = <String, double>{};
    for (final dim in _placeDims) {
      final w = model.weight(dim);
      if (w <= 0.001) continue;
      final sat = model.satisfaction(dim, pfv);
      wsum += w;
      acc += w * sat;
      contrib[dim] = w * sat;
    }
    final pct = wsum > 0 ? (acc / wsum * 100).round() : 50;
    final reasons = (contrib.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .take(3)
        .where((e) => model.satisfaction(e.key, pfv) >= 0.5)
        .map((e) => AreaReason(
            _label[e.key] ?? e.key, model.satisfaction(e.key, pfv)))
        .toList();
    return PersonaFit(persona, pct.clamp(0, 100), reasons);
  }

  /// All personas ranked by how well this point serves them (best first).
  static List<PersonaFit> suitablePersonas(PropertyFeatureVector pfv) {
    final out = [for (final p in TargetPersona.all) fit(pfv, p)];
    out.sort((a, b) => b.pct.compareTo(a.pct));
    return out;
  }

  static final Map<String, List<RankedArea>> _cityCache = {};

  /// Rank every statistical block in [city] for [persona], best-first. Profiles
  /// each block's centroid and scores persona-fit — the "where should I buy for
  /// this crowd" view. Cached per (city, persona); returns [] when gov data isn't
  /// loaded or the city has no known blocks.
  static List<RankedArea> rankCityAreas(String city, TargetPersona persona,
      {int? limit}) {
    final key = '${_normKey(city)}|${persona.key}';
    var ranked = _cityCache[key];
    if (ranked == null) {
      final areas = GovData.instance.statAreasInCity(city);
      final out = <RankedArea>[];
      for (final a in areas) {
        final c = a.centroid;
        if (c[0].abs() < 0.1 || c[1].abs() < 0.1) continue;
        final profile = profileAt(c[0], c[1], city: a.city);
        out.add(RankedArea(a, profile, fit(profile.pfv, persona)));
      }
      out.sort((x, y) => y.fit.pct.compareTo(x.fit.pct));
      ranked = _cityCache[key] = out;
    }
    return limit != null && ranked.length > limit
        ? ranked.sublist(0, limit)
        : ranked;
  }

  static String _normKey(String s) =>
      s.trim().replaceAll(RegExp(r'[\-־\s]+'), ' ');
}
