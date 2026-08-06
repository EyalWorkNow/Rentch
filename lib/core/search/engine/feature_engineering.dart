// ════════════════════════════════════════════════════════════════════════════
// PART 1 / 4 — FEATURE ENGINEERING LAYER
// ════════════════════════════════════════════════════════════════════════════
//
// Turns raw `RentalProperty` records into rich, normalized, market-aware feature
// vectors that the downstream preference model (Part 2) and ranking engine
// (Part 3) consume.
//
// Three sub-systems:
//   • IsraelGeoIndex   — geospatial reference data (transit, CBDs, coast, unis)
//                        + Haversine distance + accessibility kernels.
//   • MarketContext    — population statistics over the candidate set used to
//                        normalize every feature relative to the live market,
//                        including a Hedonic Price Model (OLS) for value scoring.
//   • FeatureEngineer  — produces a ~35-dimension PropertyFeatureVector per
//                        property.
//
// Design notes:
//   - Everything is pure & deterministic given the candidate set (testable).
//   - Fixes the legacy `feat_*` key bug: query amenity keys are mapped to the
//     real catalogue keys via `canonicalFeatureKey()` before `isEnabled()`.
//   - No external deps beyond dart:math and the rental models.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;
import 'package:dating_app/core/govdata/geo_intelligence.dart';
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/finance/price_realism.dart';
import 'package:dating_app/core/govdata/market_intelligence.dart';
import 'package:dating_app/data/models/rental_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Canonical feature-key mapping
//
// The conversational parser (smart_search.dart) emits amenity keys prefixed
// with `feat_` (e.g. feat_pets), but the property catalogue stores bare keys
// (e.g. petsAllowed). The legacy matcher called isEnabled('feat_pets') which
// ALWAYS returned false. This map bridges the two namespaces so amenity demand
// is actually honoured.
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, String> _featAliasToCatalogKey = {
  'feat_renovated': 'renovated',
  'feat_pets': 'petsAllowed',
  'feat_parking': 'parking',
  'feat_balcony': 'balcony',
  'feat_elevator': 'elevator',
  'feat_furnished': 'furnished',
  'feat_mamad': 'mamad',
  'feat_garden': 'garden',
  'feat_air': 'airConditioning',
  'feat_pool': 'pool',
  'feat_gym': 'gym',
  'feat_storage': 'storage',
  'feat_sun': 'sunBalcony',
  'feat_safe': 'bars',
  'feat_internet': 'internetIncluded',
  'feat_laundry': 'washingMachine',
};

/// Resolve a (possibly `feat_`-prefixed) amenity key to the real catalogue key.
String canonicalFeatureKey(String key) =>
    _featAliasToCatalogKey[key] ?? key;

/// True if [property] actually has the amenity denoted by [key], accepting both
/// `feat_*` query keys and bare catalogue keys.
bool propertyHasFeature(RentalProperty property, String key) =>
    property.featureFlags.isEnabled(canonicalFeatureKey(key));

// Amenity buckets used for richness / luxury / essential sub-scores.
const List<String> _essentialAmenityKeys = [
  'mamad',
  'parking',
  'elevator',
  'airConditioning',
  'bars',
];
const List<String> _luxuryAmenityKeys = [
  'pool',
  'gym',
  'security',
  'sunBalcony',
  'garden',
  'sharedRoof',
];
const List<String> _comfortAmenityKeys = [
  'renovated',
  'furnished',
  'balcony',
  'storage',
  'equippedKitchen',
  'washingMachine',
  'centralHeating',
  'internetIncluded',
];

// All keys we consider for richness, with an a-priori rarity prior (used as a
// fallback IDF when the live market is too small to estimate frequency).
const Map<String, double> _amenityRarityPrior = {
  'pool': 0.95,
  'gym': 0.9,
  'security': 0.85,
  'garden': 0.7,
  'sharedRoof': 0.75,
  'sunBalcony': 0.55,
  'storage': 0.5,
  'mamad': 0.45,
  'elevator': 0.4,
  'parking': 0.35,
  'furnished': 0.4,
  'renovated': 0.45,
  'balcony': 0.3,
  'airConditioning': 0.2,
  'bars': 0.25,
  'centralHeating': 0.6,
  'equippedKitchen': 0.4,
  'washingMachine': 0.45,
  'internetIncluded': 0.55,
  'petsAllowed': 0.5,
};

// ═════════════════════════════════════════════════════════════════════════════
// IsraelGeoIndex — geospatial reference & distance kernels
// ═════════════════════════════════════════════════════════════════════════════

class _GeoPlace {
  const _GeoPlace(this.name, this.lat, this.lon, [this.weight = 1.0]);
  final String name;
  final double lat;
  final double lon;
  final double weight;
}

class _School {
  const _School(this.name, this.type, this.lat, this.lon, [this.sector = '']);
  final String name;
  final String type; // גן / יסודי / חטיבת ביניים / תיכון / מכללה / אוניברסיטה
  final String sector; // ממלכתי / ממלכתי דתי / חרדי / '' (schools only)
  final double lat;
  final double lon;
}

class _Clinic {
  const _Clinic(this.name, this.hmo, this.lat, this.lon);
  final String name;
  final String hmo; // כללית / מכבי / לאומית / מאוחדת / '' (general clinic)
  final double lat;
  final double lon;
}

/// A generic bundled point (pharmacy / playground / gym / dining / nightlife).
/// [type] carries an optional Hebrew subtype (מסעדה / בית קפה / בר / פאב); name
/// may be empty for layers that are mostly unnamed in OSM (playgrounds).
class _Poi {
  const _Poi(this.name, this.lat, this.lon, [this.type = '']);
  final String name;
  final double lat;
  final double lon;
  final String type;
}

/// A named nearby place (school / kindergarten / park) with its distance from the
/// apartment — for the "nearby places" lists on the property detail screen.
class NearbyPlace {
  const NearbyPlace({
    required this.name,
    required this.km,
    required this.lat,
    required this.lon,
    this.kind = '',
    this.stage = '',
    this.sector = '',
  });
  final String name;
  final double km;
  final double lat;
  final double lon;
  final String kind; // school|kindergarten|clinic|supermarket|park|pharmacy|playground|gym|dining|nightlife
  final String stage; // schools: גן/יסודי/… · clinics: קופת חולים/מרפאה · dining/nightlife: מסעדה/בר/…
  final String sector; // schools: ממלכתי/דתי/חרדי · clinics: HMO (כללית/מכבי/…)
}

class IsraelGeoIndex {
  const IsraelGeoIndex._();

  static const double earthRadiusKm = 6371.0088;

  /// Haversine great-circle distance in km.
  static double haversineKm(double la1, double lo1, double la2, double lo2) {
    final dLa = _rad(la2 - la1);
    final dLo = _rad(lo2 - lo1);
    final a = math.sin(dLa / 2) * math.sin(dLa / 2) +
        math.cos(_rad(la1)) *
            math.cos(_rad(la2)) *
            math.sin(dLo / 2) *
            math.sin(dLo / 2);
    return earthRadiusKm * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double d) => d * math.pi / 180.0;

  static bool _hasCoords(double lat, double lon) =>
      lat.abs() > 0.01 && lon.abs() > 0.01;

  // Spatial grid over a point list — turns an O(n) radius scan (n up to ~15k for
  // schools) into O(nearby cells). Built once per layer at load. This is THE fix
  // for the app-wide jank: the nearby cards + the ranking's FeatureEngineer both
  // hammered these lookups on the UI thread.
  static const double _gridCell = 0.02; // ~2.2 km of latitude per cell
  static int _gridKey(double lat, double lon) {
    final cx = (lat / _gridCell).floor() + 100000;
    final cy = (lon / _gridCell).floor() + 100000;
    return cx * 1000000 + cy;
  }

  static Map<int, List<int>> _buildGrid(
      int n, double Function(int) latOf, double Function(int) lonOf) {
    final cells = <int, List<int>>{};
    for (var i = 0; i < n; i++) {
      (cells[_gridKey(latOf(i), lonOf(i))] ??= <int>[]).add(i);
    }
    return cells;
  }

  // Visit candidate indices whose grid cell overlaps the [km] radius box.
  static void _gridNear(Map<int, List<int>> cells, double lat, double lon,
      double km, void Function(int) visit) {
    final r = (km / 111.0 / _gridCell).ceil() + 1;
    final cx = (lat / _gridCell).floor();
    final cy = (lon / _gridCell).floor();
    for (var dx = -r; dx <= r; dx++) {
      for (var dy = -r; dy <= r; dy++) {
        final l = cells[(cx + dx + 100000) * 1000000 + (cy + dy + 100000)];
        if (l != null) {
          for (final i in l) {
            visit(i);
          }
        }
      }
    }
  }

  // Count points within [km] using the grid (falls back to a full scan). latOf/
  // lonOf read the parallel point coords by index. For the per-candidate density
  // scores that the ranker calls thousands of times.
  static int _countWithin(Map<int, List<int>> grid, int n, double lat, double lon,
      double km, double Function(int) latOf, double Function(int) lonOf) {
    var count = 0;
    if (grid.isNotEmpty) {
      _gridNear(grid, lat, lon, km, (i) {
        if (haversineKm(lat, lon, latOf(i), lonOf(i)) <= km) count++;
      });
    } else {
      for (var i = 0; i < n; i++) {
        if (haversineKm(lat, lon, latOf(i), lonOf(i)) <= km) count++;
      }
    }
    return count;
  }

  static int _poiCountWithin(String key, double lat, double lon, double km) {
    final list = _poiLayers[key];
    if (list == null || list.isEmpty) return 0;
    return _countWithin(_poiGrids[key] ?? const {}, list.length, lat, lon, km,
        (i) => list[i].lat, (i) => list[i].lon);
  }

  /// Nearest Israel Railways station (km), or null if coords are missing.
  static double? nearestStationKm(double lat, double lon) =>
      _nearest(lat, lon, _stations);

  /// Nearest central business district (km).
  static double? nearestCbdKm(double lat, double lon) =>
      _nearest(lat, lon, _cbds);

  /// Nearest university / major college (km) — proxy for student demand.
  static double? nearestUniversityKm(double lat, double lon) =>
      _nearest(lat, lon, _universities);

  /// Distance to the Mediterranean coastline (km), approximated by nearest
  /// coastal reference point.
  static double? coastKm(double lat, double lon) =>
      _nearest(lat, lon, _coast);

  // Public parks / gardens (bundled from OSM `leisure=park`, 1400+ named). Loaded
  // once at startup so park_access scoring + the "קרוב לפארק" auto-tag can use
  // real, verified coordinates.
  static List<_GeoPlace> _parks = const <_GeoPlace>[];
  static Map<int, List<int>> _parksGrid = const {};
  static bool _parksLoaded = false;

  static Future<void> loadParks() async {
    if (_parksLoaded) return;
    _parksLoaded = true;
    try {
      final raw =
          await rootBundle.loadString('assets/data/govdata/parks.json');
      final list = (jsonDecode(raw) as List).cast<dynamic>();
      _parks = [
        for (final p in list)
          if (p is Map)
            _GeoPlace((p['n'] ?? '').toString(),
                (p['lat'] as num).toDouble(), (p['lon'] as num).toDouble()),
      ];
      _parksGrid =
          _buildGrid(_parks.length, (i) => _parks[i].lat, (i) => _parks[i].lon);
    } catch (_) {
      _parks = const <_GeoPlace>[];
    }
  }

  /// Distance (km) to the nearest public park/garden, or null if unknown/unloaded.
  static double? parkKm(double lat, double lon) =>
      _parks.isEmpty ? null : _nearest(lat, lon, _parks, _parksGrid);

  // Named education institutions with a TYPE (גן / יסודי / חטיבה / תיכון / מכללה /
  // אוניברסיטה), bundled from OSM. Enables "250m from יסודי X" instead of a coarse
  // density score, plus filtering by school type.
  static List<_School> _schools = const <_School>[];
  static Map<int, List<int>> _schoolsGrid = const {};
  static bool _schoolsLoaded = false;

  static Future<void> loadSchools() async {
    if (_schoolsLoaded) return;
    _schoolsLoaded = true;
    try {
      final raw =
          await rootBundle.loadString('assets/data/govdata/schools.json');
      final list = (jsonDecode(raw) as List);
      _schools = [
        for (final s in list)
          if (s is Map)
            _School((s['n'] ?? '').toString(), (s['t'] ?? '').toString(),
                (s['lat'] as num).toDouble(), (s['lon'] as num).toDouble(),
                (s['s'] ?? '').toString()),
      ];
      _schoolsGrid = _buildGrid(
          _schools.length, (i) => _schools[i].lat, (i) => _schools[i].lon);
    } catch (_) {
      _schools = const <_School>[];
    }
  }

  /// The nearest school (optionally restricted to a [type]) → (name, type, km),
  /// or null. [type] is one of גן/יסודי/חטיבה/תיכון/מכללה/אוניברסיטה.
  static ({String name, String type, double km})? nearestSchool(
      double lat, double lon,
      {String? type}) {
    if (_schools.isEmpty || !_hasCoords(lat, lon)) return null;
    _School? best;
    double? bestD;
    void consider(_School s) {
      if (type != null && !_typeMatches(s.type, type)) return;
      final d = haversineKm(lat, lon, s.lat, s.lon);
      if (bestD == null || d < bestD!) {
        bestD = d;
        best = s;
      }
    }

    // Grid-scan a generous radius first (nearest school is almost always <15 km);
    // fall back to a full scan only if that box is empty.
    if (_schoolsGrid.isNotEmpty) {
      _gridNear(_schoolsGrid, lat, lon, 15, (i) => consider(_schools[i]));
    }
    if (best == null) {
      for (final s in _schools) {
        consider(s);
      }
    }
    if (best == null) return null;
    return (name: best!.name, type: best!.type, km: bestD!);
  }

  /// Distance (km) to the nearest school of any type, or null.
  static double? nearestSchoolKm(double lat, double lon) =>
      nearestSchool(lat, lon)?.km;

  // ── nearby LISTS (all places within a radius, sorted nearest-first) ─────────
  // The property detail screen shows real lists (name + type + distance), not
  // just the single nearest. Default radius 2 km; capped so the UI stays tidy.
  static const Set<String> _schoolStages = {
    'יסודי', 'חטיבת ביניים', 'תיכון', 'בית ספר', 'על יסודי', 'חטיבה',
  };

  static List<NearbyPlace> _schoolsWhere(
      double lat, double lon, double km, int cap, bool Function(_School) keep) {
    if (_schools.isEmpty || !_hasCoords(lat, lon)) return const [];
    final out = <NearbyPlace>[];
    final seen = <String>{};
    void consider(_School s) {
      if (!keep(s)) return;
      final d = haversineKm(lat, lon, s.lat, s.lon);
      if (d > km) return;
      if (!seen.add('${s.name}_${s.lat}_${s.lon}')) return; // exact dup only
      out.add(NearbyPlace(
          name: s.name, km: d, lat: s.lat, lon: s.lon,
          kind: s.type == 'גן' ? 'kindergarten' : 'school',
          stage: s.type, sector: s.sector));
    }

    if (_schoolsGrid.isNotEmpty) {
      _gridNear(_schoolsGrid, lat, lon, km, (i) => consider(_schools[i]));
    } else {
      for (final s in _schools) {
        consider(s);
      }
    }
    out.sort((a, b) => a.km.compareTo(b.km));
    return out.length > cap ? out.sublist(0, cap) : out;
  }

  /// Kindergartens (גן) within [km] km, sorted nearest-first.
  static List<NearbyPlace> kindergartensWithin(double lat, double lon,
          {double km = 2, int cap = 12}) =>
      _schoolsWhere(lat, lon, km, cap, (s) => s.type == 'גן');

  /// Schools (יסודי / חטיבת ביניים / תיכון …) within [km] km, sorted nearest-first.
  static List<NearbyPlace> schoolsWithin(double lat, double lon,
          {double km = 2, int cap = 12}) =>
      _schoolsWhere(lat, lon, km, cap, (s) => _schoolStages.contains(s.type));

  /// Public parks/gardens within [km] km, sorted nearest-first.
  static List<NearbyPlace> parksWithin(double lat, double lon,
      {double km = 2, int cap = 12}) {
    if (_parks.isEmpty || !_hasCoords(lat, lon)) return const [];
    final out = <NearbyPlace>[];
    final seen = <String>{};
    void consider(_GeoPlace p) {
      final d = haversineKm(lat, lon, p.lat, p.lon);
      if (d > km) return;
      if (p.name.isEmpty || !seen.add('${p.name}_${p.lat}_${p.lon}')) return;
      out.add(NearbyPlace(name: p.name, km: d, lat: p.lat, lon: p.lon, kind: 'park'));
    }

    if (_parksGrid.isNotEmpty) {
      _gridNear(_parksGrid, lat, lon, km, (i) => consider(_parks[i]));
    } else {
      for (final p in _parks) {
        consider(p);
      }
    }
    out.sort((a, b) => a.km.compareTo(b.km));
    return out.length > cap ? out.sublist(0, cap) : out;
  }

  // ── health clinics / קופות חולים (tagged with HMO) ──────────────────────────
  static List<_Clinic> _clinics = const <_Clinic>[];
  static Map<int, List<int>> _clinicsGrid = const {};
  static bool _clinicsLoaded = false;

  static Future<void> loadClinics() async {
    if (_clinicsLoaded) return;
    _clinicsLoaded = true;
    try {
      final raw =
          await rootBundle.loadString('assets/data/govdata/clinics.json');
      _clinics = [
        for (final c in (jsonDecode(raw) as List))
          if (c is Map)
            _Clinic((c['n'] ?? '').toString(), (c['h'] ?? '').toString(),
                (c['lat'] as num).toDouble(), (c['lon'] as num).toDouble()),
      ];
      _clinicsGrid = _buildGrid(
          _clinics.length, (i) => _clinics[i].lat, (i) => _clinics[i].lon);
    } catch (_) {
      _clinics = const <_Clinic>[];
    }
  }

  /// Health clinics within [km] km (default 5 — clinics matter a bit farther),
  /// optionally restricted to one [hmo] (כללית / מכבי / לאומית / מאוחדת).
  static List<NearbyPlace> clinicsWithin(double lat, double lon,
      {double km = 5, String? hmo, int cap = 12}) {
    if (_clinics.isEmpty || !_hasCoords(lat, lon)) return const [];
    final out = <NearbyPlace>[];
    final seen = <String>{};
    void consider(_Clinic c) {
      if (hmo != null && hmo.isNotEmpty && c.hmo != hmo) return;
      final d = haversineKm(lat, lon, c.lat, c.lon);
      if (d > km) return;
      if (!seen.add('${c.name}_${c.lat}_${c.lon}')) return;
      out.add(NearbyPlace(
          name: c.name, km: d, lat: c.lat, lon: c.lon, kind: 'clinic',
          stage: c.hmo.isEmpty ? 'מרפאה' : 'קופת חולים', sector: c.hmo));
    }

    if (_clinicsGrid.isNotEmpty) {
      _gridNear(_clinicsGrid, lat, lon, km, (i) => consider(_clinics[i]));
    } else {
      for (final c in _clinics) {
        consider(c);
      }
    }
    out.sort((a, b) => a.km.compareTo(b.km));
    return out.length > cap ? out.sublist(0, cap) : out;
  }

  // ── supermarkets ────────────────────────────────────────────────────────────
  static List<_GeoPlace> _supermarkets = const <_GeoPlace>[];
  static Map<int, List<int>> _supermarketsGrid = const {};
  static bool _supermarketsLoaded = false;

  static Future<void> loadSupermarkets() async {
    if (_supermarketsLoaded) return;
    _supermarketsLoaded = true;
    try {
      final raw =
          await rootBundle.loadString('assets/data/govdata/supermarkets.json');
      _supermarkets = [
        for (final s in (jsonDecode(raw) as List))
          if (s is Map)
            _GeoPlace((s['n'] ?? '').toString(), (s['lat'] as num).toDouble(),
                (s['lon'] as num).toDouble()),
      ];
      _supermarketsGrid = _buildGrid(_supermarkets.length,
          (i) => _supermarkets[i].lat, (i) => _supermarkets[i].lon);
    } catch (_) {
      _supermarkets = const <_GeoPlace>[];
    }
  }

  /// Supermarkets within [km] km, sorted nearest-first.
  static List<NearbyPlace> supermarketsWithin(double lat, double lon,
      {double km = 2, int cap = 12}) {
    if (_supermarkets.isEmpty || !_hasCoords(lat, lon)) return const [];
    final out = <NearbyPlace>[];
    final seen = <String>{};
    void consider(_GeoPlace s) {
      final d = haversineKm(lat, lon, s.lat, s.lon);
      if (d > km) return;
      if (s.name.isEmpty || !seen.add('${s.name}_${s.lat}_${s.lon}')) return;
      out.add(NearbyPlace(
          name: s.name, km: d, lat: s.lat, lon: s.lon, kind: 'supermarket'));
    }

    if (_supermarketsGrid.isNotEmpty) {
      _gridNear(_supermarketsGrid, lat, lon, km, (i) => consider(_supermarkets[i]));
    } else {
      for (final s in _supermarkets) {
        consider(s);
      }
    }
    out.sort((a, b) => a.km.compareTo(b.km));
    return out.length > cap ? out.sublist(0, cap) : out;
  }

  /// 0..1 errands access from the REAL supermarket point layer — count within
  /// [km] km, log-compressed ([cap] within-radius ⇒ 1.0). Replaces the 16-cell
  /// Tel-Aviv retail SEED grid with 4.5k national points. 0 when none nearby or
  /// the layer isn't loaded.
  // ponytail: O(candidates × supermarkets) linear scan; add a grid index if a
  // single search ever ranks thousands of candidates.
  static double supermarketAccess(double lat, double lon,
      {double km = 1.5, int cap = 8}) {
    if (_supermarkets.isEmpty || !_hasCoords(lat, lon)) return 0.0;
    final n = _countWithin(_supermarketsGrid, _supermarkets.length, lat, lon, km,
        (i) => _supermarkets[i].lat, (i) => _supermarkets[i].lon);
    return n == 0 ? 0.0 : (math.log(1 + n) / math.log(1 + cap)).clamp(0.0, 1.0);
  }

  /// 0..1 health access from the REAL clinic point layer (HMO + general) — count
  /// within [km] km (clinics matter a bit farther than groceries), log-compressed.
  /// Replaces the 160-city health table with 599 national HMO-tagged points.
  static double clinicAccess(double lat, double lon,
      {double km = 3, int cap = 6}) {
    if (_clinics.isEmpty || !_hasCoords(lat, lon)) return 0.0;
    final n = _countWithin(_clinicsGrid, _clinics.length, lat, lon, km,
        (i) => _clinics[i].lat, (i) => _clinics[i].lon);
    return n == 0 ? 0.0 : (math.log(1 + n) / math.log(1 + cap)).clamp(0.0, 1.0);
  }

  // ── lifestyle POI layers (pharmacies/playgrounds/gyms/dining/nightlife) ─────
  // One generic mechanism instead of five copy-pasted loaders. Each layer is a
  // bundled `[{n?,lat,lon,t?}]` JSON; `_poiLayers[key]` is null until loaded.
  static final Map<String, List<_Poi>> _poiLayers = {};
  static final Map<String, Map<int, List<int>>> _poiGrids = {};

  static Future<void> _loadPoi(String key, String file) async {
    if (_poiLayers.containsKey(key)) return;
    _poiLayers[key] = const <_Poi>[]; // mark loading (idempotent)
    try {
      final raw = await rootBundle.loadString('assets/data/govdata/$file');
      final list = [
        for (final e in (jsonDecode(raw) as List))
          if (e is Map)
            _Poi((e['n'] ?? '').toString(), (e['lat'] as num).toDouble(),
                (e['lon'] as num).toDouble(), (e['t'] ?? '').toString()),
      ];
      _poiLayers[key] = list;
      _poiGrids[key] =
          _buildGrid(list.length, (i) => list[i].lat, (i) => list[i].lon);
    } catch (_) {
      _poiLayers[key] = const <_Poi>[];
    }
  }

  /// Load every lifestyle layer used by the personalised nearby card.
  static Future<void> loadLifestylePois() => Future.wait([
        _loadPoi('pharmacies', 'pharmacies.json'),
        _loadPoi('playgrounds', 'playgrounds.json'),
        _loadPoi('gyms', 'gyms.json'),
        _loadPoi('dining', 'dining.json'),
        _loadPoi('nightlife', 'nightlife_venues.json'),
        _loadPoi('synagogues', 'synagogues.json'),
        _loadPoi('culture', 'culture.json'),
        _loadPoi('hospitals', 'hospitals.json'),
        _loadPoi('transit_stops', 'transit_stops.json'),
        _loadPoi('worship', 'worship.json'),
        _loadPoi('pools', 'pools.json'),
        _loadPoi('dog_parks', 'dog_parks.json'),
        _loadPoi('vets', 'vets.json'),
        _loadPoi('bike_share', 'bike_share.json'),
        _loadPoi('coworking', 'coworking.json'),
        _loadPoi('parking', 'parking.json'),
      ]);

  /// Generic within-radius query over a loaded [_poiLayers] key. [kind] tags the
  /// result; [genericName] labels unnamed points (playgrounds).
  static List<NearbyPlace> _poiWithin(String key, double lat, double lon,
      {required double km,
      required String kind,
      int cap = 12,
      String genericName = ''}) {
    final list = _poiLayers[key];
    if (list == null || list.isEmpty || !_hasCoords(lat, lon)) return const [];
    final out = <NearbyPlace>[];
    final seen = <String>{};
    void consider(_Poi p) {
      final d = haversineKm(lat, lon, p.lat, p.lon);
      if (d > km) return;
      final name = p.name.isEmpty ? genericName : p.name;
      if (name.isEmpty || !seen.add('$name|${p.lat}|${p.lon}')) return;
      out.add(NearbyPlace(
          name: name, km: d, lat: p.lat, lon: p.lon, kind: kind, stage: p.type));
    }

    final grid = _poiGrids[key];
    if (grid != null) {
      _gridNear(grid, lat, lon, km, (i) => consider(list[i]));
    } else {
      for (final p in list) {
        consider(p);
      }
    }
    out.sort((a, b) => a.km.compareTo(b.km));
    return out.length > cap ? out.sublist(0, cap) : out;
  }

  static List<NearbyPlace> pharmaciesWithin(double lat, double lon,
          {double km = 2, int cap = 12}) =>
      _poiWithin('pharmacies', lat, lon, km: km, kind: 'pharmacy', cap: cap);

  static List<NearbyPlace> playgroundsWithin(double lat, double lon,
          {double km = 1.5, int cap = 12}) =>
      _poiWithin('playgrounds', lat, lon,
          km: km, kind: 'playground', cap: cap, genericName: 'גן שעשועים');

  static List<NearbyPlace> gymsWithin(double lat, double lon,
          {double km = 3, int cap = 12}) =>
      _poiWithin('gyms', lat, lon, km: km, kind: 'gym', cap: cap);

  static List<NearbyPlace> diningWithin(double lat, double lon,
          {double km = 1.5, int cap = 12}) =>
      _poiWithin('dining', lat, lon, km: km, kind: 'dining', cap: cap);

  static List<NearbyPlace> nightlifeVenuesWithin(double lat, double lon,
          {double km = 2, int cap = 12}) =>
      _poiWithin('nightlife', lat, lon, km: km, kind: 'nightlife', cap: cap);

  static List<NearbyPlace> synagoguesWithin(double lat, double lon,
          {double km = 1.5, int cap = 12}) =>
      _poiWithin('synagogues', lat, lon,
          km: km, kind: 'synagogue', cap: cap, genericName: 'בית כנסת');

  /// Loads ONLY the synagogue layer (lightweight, ~576 pts) for the religious_area
  /// scoring signal — call at startup so the ranker has it without pulling every
  /// lifestyle layer. Idempotent (shares the _poiLayers cache with the card).
  static Future<void> loadSynagogues() => _loadPoi('synagogues', 'synagogues.json');

  /// 0..1 religiosity proxy from REAL synagogue DENSITY — count within [km] km,
  /// log-compressed ([cap] within radius ⇒ 1.0). A dense cluster of synagogues is
  /// a strong, NATIONAL signal of an observant community, unlike the hardcoded
  /// neighbourhood list (which only knows a handful of areas). 0 when unloaded.
  static double synagogueDensity(double lat, double lon,
      {double km = 1.0, int cap = 10}) {
    if (!_hasCoords(lat, lon)) return 0.0;
    final n = _poiCountWithin('synagogues', lat, lon, km);
    return n == 0 ? 0.0 : (math.log(1 + n) / math.log(1 + cap)).clamp(0.0, 1.0);
  }

  static List<NearbyPlace> cultureWithin(double lat, double lon,
          {double km = 3, int cap = 12}) =>
      _poiWithin('culture', lat, lon, km: km, kind: 'culture', cap: cap);

  static List<NearbyPlace> hospitalsWithin(double lat, double lon,
          {double km = 5, int cap = 12}) =>
      _poiWithin('hospitals', lat, lon, km: km, kind: 'hospital', cap: cap);

  static List<NearbyPlace> transitStopsWithin(double lat, double lon,
          {double km = 1.5, int cap = 12}) =>
      _poiWithin('transit_stops', lat, lon,
          km: km, kind: 'transit', cap: cap, genericName: 'תחנת רכבת');

  static List<NearbyPlace> worshipWithin(double lat, double lon,
          {double km = 2, int cap = 12}) =>
      _poiWithin('worship', lat, lon,
          km: km, kind: 'worship', cap: cap, genericName: 'בית תפילה');

  static List<NearbyPlace> poolsWithin(double lat, double lon,
          {double km = 3, int cap = 12}) =>
      _poiWithin('pools', lat, lon, km: km, kind: 'pool', cap: cap);

  static List<NearbyPlace> dogParksWithin(double lat, double lon,
          {double km = 2, int cap = 12}) =>
      _poiWithin('dog_parks', lat, lon,
          km: km, kind: 'dogpark', cap: cap, genericName: 'גינת כלבים');

  static List<NearbyPlace> vetsWithin(double lat, double lon,
          {double km = 3, int cap = 12}) =>
      _poiWithin('vets', lat, lon, km: km, kind: 'vet', cap: cap);

  static List<NearbyPlace> bikeShareWithin(double lat, double lon,
          {double km = 1.5, int cap = 12}) =>
      _poiWithin('bike_share', lat, lon,
          km: km, kind: 'bike', cap: cap, genericName: 'תחנת אופניים');

  static List<NearbyPlace> coworkingWithin(double lat, double lon,
          {double km = 3, int cap = 12}) =>
      _poiWithin('coworking', lat, lon, km: km, kind: 'coworking', cap: cap);

  static List<NearbyPlace> parkingWithin(double lat, double lon,
          {double km = 1.5, int cap = 12}) =>
      _poiWithin('parking', lat, lon, km: km, kind: 'parking', cap: cap);

  // Nightlife venues (OSM bars/pubs/clubs weighted 1.0, cafés 0.4). A LIVELY area
  // isn't the nearest bar — it's the DENSITY of them around you.
  static List<List<double>> _nightlife = const <List<double>>[]; // [lat,lon,w]
  static Map<int, List<int>> _nightlifeGrid = const {};
  static bool _nightlifeLoaded = false;

  static Future<void> loadNightlife() async {
    if (_nightlifeLoaded) return;
    _nightlifeLoaded = true;
    try {
      final raw =
          await rootBundle.loadString('assets/data/govdata/nightlife.json');
      final list = (jsonDecode(raw) as List);
      _nightlife = [
        for (final v in list)
          if (v is List && v.length >= 3)
            [
              (v[0] as num).toDouble(),
              (v[1] as num).toDouble(),
              (v[2] as num).toDouble()
            ],
      ];
      _nightlifeGrid = _buildGrid(
          _nightlife.length, (i) => _nightlife[i][0], (i) => _nightlife[i][1]);
    } catch (_) {
      _nightlife = const <List<double>>[];
    }
  }

  /// 0..1 nightlife/vibrancy — weighted density of bars/pubs/clubs/cafés within a
  /// ~1km walk (closer venues count more). High = a lively, going-out area.
  static double nightlifeDensity(double lat, double lon) {
    if (_nightlife.isEmpty || !_hasCoords(lat, lon)) return 0.0;
    double sum = 0;
    void consider(int i) {
      final v = _nightlife[i];
      final d = haversineKm(lat, lon, v[0], v[1]);
      if (d <= 1.0) sum += v[2] * (1.0 - d); // linear walk-decay
    }

    if (_nightlifeGrid.isNotEmpty) {
      _gridNear(_nightlifeGrid, lat, lon, 1.0, consider);
    } else {
      for (var i = 0; i < _nightlife.length; i++) {
        consider(i);
      }
    }
    return (sum / 9.0).clamp(0.0, 1.0); // ~9 weighted venues in 1km → very lively
  }

  // Most OSM schools are the generic 'בית ספר' — in Israel that's the default
  // ELEMENTARY school (חטיבה/תיכון are named explicitly), so treat generic as
  // elementary when the caller asks for יסודי.
  static bool _typeMatches(String actual, String wanted) {
    if (wanted == 'יסודי') return actual == 'יסודי' || actual == 'בית ספר';
    return actual == wanted;
  }

  /// Best walk-proximity (0..1) to ANY of the given school [types] — e.g. young
  /// kids care about a nearby גן/יסודי, teens about a תיכון.
  static double schoolTypeProximity(
      double lat, double lon, List<String> types) {
    double? best;
    for (final t in types) {
      final km = nearestSchool(lat, lon, type: t)?.km;
      if (km != null && (best == null || km < best)) best = km;
    }
    return proximityKernel(best, scaleKm: 1.0);
  }

  // Well-established religious localities (charedi + dati-leumi) and neighbourhoods
  // — a curated, VERIFIED proxy (these ARE observant communities), since CBS
  // religiosity shares aren't in the bundled data. 1.0 = strongly religious.
  static const _religiousLocalities = <String, double>{
    'בני ברק': 1.0, 'ביתר עילית': 1.0, 'מודיעין עילית': 1.0, 'אלעד': 1.0,
    'עמנואל': 1.0, 'רכסים': 0.9, 'קרית ספר': 1.0, 'ירושלים': 0.6,
    'בית שמש': 0.8, 'אשדוד': 0.5, 'צפת': 0.7, 'טבריה': 0.55, 'נתיבות': 0.7,
    'אופקים': 0.6, 'רחובות': 0.4,
    // dati-leumi
    'אפרת': 0.85, 'קרני שומרון': 0.8, 'אלקנה': 0.85, 'בית אל': 0.9, 'עפרה': 0.9,
    'קדומים': 0.85, 'שילה': 0.85, 'אלון שבות': 0.9, 'נווה דניאל': 0.85,
    'כרמי צור': 0.85, 'מעלה אדומים': 0.6, 'גבעת שמואל': 0.6, 'קרית ארבע': 0.9,
    'אורנית': 0.55, 'טלמון': 0.9, 'שבי שומרון': 0.85, 'עתניאל': 0.9,
  };
  static const _religiousNeighbourhoods = {
    'מאה שערים', 'גאולה', 'הר נוף', 'רמות', 'סנהדריה', 'רמת שלמה',
    'בית וגן', 'קרית משה', 'רמת בית שמש', 'רובע ז'
  };

  /// 0..1 — how religiously-observant the property's community is (verified list).
  /// A confirmed religious NEIGHBOURHOOD is the most specific signal and takes
  /// precedence — otherwise a מאה-שערים flat was dragged down to Jerusalem's
  /// city-average (0.6), identical to a secular Jerusalem flat, so the dimension
  /// couldn't tell them apart. City-level is the fallback when the neighbourhood
  /// is unknown, but a known religious neighbourhood always wins.
  static double religiousAreaScore(String city, String neighborhood) {
    final c = city.trim();
    final n = neighborhood.trim();
    for (final rn in _religiousNeighbourhoods) {
      if (n.contains(rn) || c.contains(rn)) return 0.95;
    }
    return _religiousLocalities[c] ?? 0.0;
  }

  /// The nearest park's NAME (for the "קרוב ל<park>" reason), or null.
  static String? nearestParkName(double lat, double lon) {
    if (_parks.isEmpty || !_hasCoords(lat, lon)) return null;
    _GeoPlace? best;
    double? bestD;
    for (final p in _parks) {
      final d = haversineKm(lat, lon, p.lat, p.lon);
      if (bestD == null || d < bestD) {
        bestD = d;
        best = p;
      }
    }
    return best?.name;
  }

  static double? _nearest(double lat, double lon, List<_GeoPlace> places,
      [Map<int, List<int>>? grid]) {
    if (!_hasCoords(lat, lon)) return null;
    double? best;
    void consider(_GeoPlace p) {
      final d = haversineKm(lat, lon, p.lat, p.lon);
      if (best == null || d < best!) best = d;
    }

    // Nearest is almost always <20 km; grid-scan that box, full-scan only if empty.
    if (grid != null && grid.isNotEmpty) {
      _gridNear(grid, lat, lon, 20, (i) => consider(places[i]));
      if (best != null) return best;
    }
    for (final p in places) {
      consider(p);
    }
    return best;
  }

  /// Exponential-decay accessibility kernel: 1.0 at the POI, ~0.37 at [scaleKm],
  /// approaching 0 far away. Smooth and bounded, unlike hard distance buckets.
  static double proximityKernel(double? distanceKm, {double scaleKm = 1.5}) {
    if (distanceKm == null) return 0.0;
    return math.exp(-distanceKm / scaleKm);
  }

  // ── reference data ────────────────────────────────────────────────────────
  static const List<_GeoPlace> _stations = [
    _GeoPlace('ת"א סבידור מרכז', 32.0833, 34.7991),
    _GeoPlace('ת"א השלום', 32.0734, 34.7920),
    _GeoPlace('ת"א ההגנה', 32.0540, 34.7940),
    _GeoPlace('ת"א אוניברסיטה', 32.1140, 34.8040),
    _GeoPlace('הרצליה', 32.1660, 34.8340),
    _GeoPlace('נתניה', 32.3180, 34.8570),
    _GeoPlace('רעננה מערב', 32.1820, 34.8510),
    _GeoPlace('כפר סבא נורדאו', 32.1670, 34.9160),
    _GeoPlace('פ"ת קריית אריה', 32.1030, 34.8570),
    _GeoPlace('בני ברק', 32.0930, 34.8340),
    _GeoPlace('ראשל"צ הראשונים', 31.9620, 34.8060),
    _GeoPlace('רחובות', 31.9170, 34.7970),
    _GeoPlace('לוד', 31.9480, 34.8720),
    _GeoPlace('רמלה', 31.9280, 34.8640),
    _GeoPlace('מודיעין מרכז', 31.9010, 35.0070),
    _GeoPlace('בית שמש', 31.7470, 34.9880),
    _GeoPlace('ירושלים יצחק נבון', 31.7870, 35.2030),
    _GeoPlace('אשדוד עד הלום', 31.7700, 34.6610),
    _GeoPlace('אשקלון', 31.6520, 34.5780),
    _GeoPlace('באר שבע מרכז', 31.2430, 34.7980),
    _GeoPlace('חיפה חוף הכרמל', 32.7940, 34.9570),
    _GeoPlace('חיפה בת גלים', 32.8310, 34.9890),
    _GeoPlace('חיפה מרכז השמונה', 32.8210, 35.0000),
  ];

  // Employment / commercial cores.
  static const List<_GeoPlace> _cbds = [
    _GeoPlace('ת"א - הקריה/רוטשילד', 32.0700, 34.7800, 1.0),
    _GeoPlace('רמת גן - הבורסה', 32.0840, 34.8060, 0.9),
    _GeoPlace('הרצליה פיתוח', 32.1620, 34.8060, 0.8),
    _GeoPlace('ירושלים - מרכז', 31.7800, 35.2170, 0.85),
    _GeoPlace('חיפה - מרכז', 32.8190, 34.9980, 0.8),
    _GeoPlace('באר שבע - מרכז', 31.2520, 34.7910, 0.6),
  ];

  // Israeli higher-education institutions — the universities AND the colleges
  // (michlalot) students actually live near. Broadened so proximity resolves in
  // every academic city, not only the 7 research universities.
  static const List<_GeoPlace> _universities = [
    // research universities
    _GeoPlace('אוניברסיטת ת"א', 32.1133, 34.8044),
    _GeoPlace('הטכניון', 32.7767, 35.0233),
    _GeoPlace('האונ׳ העברית גבעת רם', 31.7770, 35.1970),
    _GeoPlace('האונ׳ העברית הר הצופים', 31.7940, 35.2440),
    _GeoPlace('בן גוריון', 31.2620, 34.8010),
    _GeoPlace('בר אילן', 32.0690, 34.8430),
    _GeoPlace('אונ׳ חיפה', 32.7610, 35.0200),
    _GeoPlace('אונ׳ אריאל', 32.1030, 35.2070),
    _GeoPlace('הפתוחה רעננה', 32.1810, 34.8710),
    // Rehovot science campus (Weizmann + Faculty of Agriculture)
    _GeoPlace('מכון ויצמן רחובות', 31.9070, 34.8100),
    _GeoPlace('הפקולטה לחקלאות רחובות', 31.9050, 34.8060),
    _GeoPlace('מכללת פרס רחובות', 31.8940, 34.8080),
    // colleges — Gush Dan / Sharon
    _GeoPlace('רייכמן הרצליה', 32.1740, 34.8390),
    _GeoPlace('אפקה ת"א', 32.1130, 34.8180),
    _GeoPlace('לוינסקי ת"א', 32.0940, 34.7830),
    _GeoPlace('שנקר ר"ג', 32.0640, 34.8280),
    _GeoPlace('אונו קרית אונו', 32.0560, 34.8560),
    _GeoPlace('HIT חולון', 32.0150, 34.7740),
    _GeoPlace('המכללה למינהל ראשל"צ', 31.9670, 34.7930),
    _GeoPlace('רופין עמק חפר', 32.3400, 34.9170),
    _GeoPlace('המכללה האקדמית נתניה', 32.3050, 34.8650),
    // Jerusalem colleges
    _GeoPlace('בצלאל ירושלים', 31.7900, 35.2020),
    _GeoPlace('הדסה ירושלים', 31.7810, 35.2210),
    // South
    _GeoPlace('סמי שמעון ב"ש', 31.2510, 34.7920),
    _GeoPlace('ספיר שדרות', 31.5560, 34.5850),
    _GeoPlace('אחוה', 31.7500, 34.7000),
    _GeoPlace('בן גוריון אילת', 29.5560, 34.9510),
    // North
    _GeoPlace('בראודה כרמיאל', 32.9130, 35.3020),
    _GeoPlace('תל חי', 33.2340, 35.5760),
    _GeoPlace('כנרת', 32.7080, 35.5760),
    _GeoPlace('עמק יזרעאל', 32.6470, 35.2960),
  ];

  // Coastline reference points (Mediterranean), ~10-15km apart from Rosh
  // Hanikra to the Gaza border, so `coastKm` approximates distance to the
  // nearest shoreline point rather than to the nearest of a handful of city
  // beaches (which badly overestimated distance for everywhere in between,
  // e.g. Hadera/Caesarea/Ashkelon).
  static const List<_GeoPlace> _coast = [
    _GeoPlace('ראש הנקרה', 33.0900, 35.1060),
    _GeoPlace('נהריה חוף', 33.0060, 35.0940),
    _GeoPlace('עכו חוף', 32.9280, 35.0700),
    _GeoPlace('חיפה חוף', 32.8200, 34.9700),
    _GeoPlace('עתלית', 32.6860, 34.9410),
    _GeoPlace('קיסריה חוף', 32.5000, 34.8950),
    _GeoPlace('חדרה חוף', 32.4280, 34.8730),
    _GeoPlace('נתניה חוף', 32.3300, 34.8500),
    _GeoPlace('הרצליה חוף', 32.1640, 34.7920),
    _GeoPlace('ת"א חוף', 32.0800, 34.7660),
    _GeoPlace('בת ים חוף', 32.0150, 34.7350),
    _GeoPlace('ראשל"צ חוף', 31.9650, 34.7000),
    _GeoPlace('אשדוד חוף', 31.7900, 34.6300),
    _GeoPlace('אשקלון חוף', 31.6600, 34.5600),
    _GeoPlace('זיקים חוף', 31.5600, 34.5000),
  ];
}

// ═════════════════════════════════════════════════════════════════════════════
// HedonicPriceModel — OLS regression of log(price) on property attributes
//
// Estimates the "fair" market price of a property from its attributes, so we can
// score VALUE as the residual: a property priced below its hedonic prediction is
// a good deal. Solved in closed form via the normal equations with ridge
// regularization for numerical stability on small/collinear samples.
// ═════════════════════════════════════════════════════════════════════════════

class HedonicPriceModel {
  HedonicPriceModel._(this._beta, this._featureMeans, this._ok, this.rmse);

  final List<double> _beta; // coefficients incl. intercept at index 0
  final List<double> _featureMeans;
  final bool _ok;
  final double rmse; // residual std-dev in log space (model confidence)

  bool get isFitted => _ok;

  // Design row for a property: [1, rooms, sizeM2, amenityCount, centrality,
  // floorNum, isVerified]. Kept small & robust.
  static List<double> _designRow(
    RentalProperty p,
    double centrality,
  ) {
    final amenityCount = p.featureFlags.values.values.where((v) => v).length;
    final floor = (p.floorNumber ?? 0).toDouble();
    return [
      1.0,
      p.rooms,
      p.sizeM2.toDouble(),
      amenityCount.toDouble(),
      centrality,
      floor,
      p.isVerifiedListing ? 1.0 : 0.0,
    ];
  }

  /// Fit on the candidate set. Properties with non-positive price are skipped.
  static HedonicPriceModel fit(
    List<RentalProperty> properties,
    double Function(RentalProperty) centralityOf,
  ) {
    final rows = <List<double>>[];
    final targets = <double>[];
    for (final p in properties) {
      if (p.price <= 0 || p.rooms <= 0 || p.sizeM2 <= 0) continue;
      rows.add(_designRow(p, centralityOf(p)));
      targets.add(math.log(p.price.toDouble()));
    }
    final n = rows.length;
    final k = 7; // feature count incl intercept
    if (n < k + 3) {
      return HedonicPriceModel._(List.filled(k, 0), List.filled(k, 0), false, 0);
    }

    // Standardize feature columns (except intercept) for conditioning.
    final means = List<double>.filled(k, 0);
    final stds = List<double>.filled(k, 1);
    for (var j = 1; j < k; j++) {
      double s = 0;
      for (var i = 0; i < n; i++) {
        s += rows[i][j];
      }
      means[j] = s / n;
      double v = 0;
      for (var i = 0; i < n; i++) {
        final d = rows[i][j] - means[j];
        v += d * d;
      }
      stds[j] = math.sqrt(v / n);
      if (stds[j] < 1e-9) stds[j] = 1.0;
    }

    // Build standardized X.
    final x = List.generate(
      n,
      (i) => List.generate(
        k,
        (j) => j == 0 ? 1.0 : (rows[i][j] - means[j]) / stds[j],
      ),
    );

    // Normal equations: (XᵀX + λI) β = Xᵀy  (ridge λ for stability).
    const lambda = 1e-3;
    final xtx = List.generate(k, (_) => List<double>.filled(k, 0));
    final xty = List<double>.filled(k, 0);
    for (var a = 0; a < k; a++) {
      for (var b = 0; b < k; b++) {
        double s = 0;
        for (var i = 0; i < n; i++) {
          s += x[i][a] * x[i][b];
        }
        xtx[a][b] = s + (a == b && a != 0 ? lambda : 0);
      }
      double sy = 0;
      for (var i = 0; i < n; i++) {
        sy += x[i][a] * targets[i];
      }
      xty[a] = sy;
    }

    final betaStd = _solveLinearSystem(xtx, xty);
    if (betaStd == null) {
      return HedonicPriceModel._(List.filled(k, 0), means, false, 0);
    }

    // Compute RMSE in log space.
    double sse = 0;
    for (var i = 0; i < n; i++) {
      double pred = 0;
      for (var j = 0; j < k; j++) {
        pred += betaStd[j] * x[i][j];
      }
      final e = targets[i] - pred;
      sse += e * e;
    }
    final rmse = math.sqrt(sse / n);

    // Keep standardized betas + means/stds folded into prediction via _predictStd.
    // Store means as stds-aware by packing stds into _featureMeans alternately is
    // messy; instead store both via closure-free fields: we keep means and bake
    // stds into beta? Simpler: store standardized beta and the means/stds.
    final packed = List<double>.from(betaStd);
    // We stash stds in featureMeans by storing means; prediction recomputes using
    // the same standardization, so we also need stds. Store interleaved:
    final meansAndStds = List<double>.filled(k * 2, 0);
    for (var j = 0; j < k; j++) {
      meansAndStds[j] = means[j];
      meansAndStds[k + j] = stds[j];
    }
    return HedonicPriceModel._(packed, meansAndStds, true, rmse);
  }

  /// Predicted fair price (₪) for a property given its centrality.
  double predictPrice(RentalProperty p, double centrality) {
    if (!_ok) return p.price.toDouble();
    final k = _beta.length;
    final row = _designRow(p, centrality);
    double logp = 0;
    for (var j = 0; j < k; j++) {
      final std = _featureMeans[k + j] == 0 ? 1.0 : _featureMeans[k + j];
      final xj = j == 0 ? 1.0 : (row[j] - _featureMeans[j]) / std;
      logp += _beta[j] * xj;
    }
    return math.exp(logp);
  }

  /// Value residual in [-1, 1]: positive = priced BELOW prediction (good deal),
  /// negative = overpriced. Scaled by model RMSE so it's comparable across fits.
  double valueResidual(RentalProperty p, double centrality) {
    if (!_ok || p.price <= 0) return 0.0;
    final fair = predictPrice(p, centrality);
    if (fair <= 0) return 0.0;
    final logDiff = math.log(fair) - math.log(p.price.toDouble());
    final scale = rmse < 1e-6 ? 0.25 : rmse * 2.0;
    return (logDiff / scale).clamp(-1.0, 1.0);
  }

  // Gaussian elimination with partial pivoting. Returns null if singular.
  static List<double>? _solveLinearSystem(
      List<List<double>> a, List<double> b) {
    final n = b.length;
    final m = List.generate(n, (i) => List<double>.from(a[i])..add(b[i]));
    for (var col = 0; col < n; col++) {
      var pivot = col;
      for (var r = col + 1; r < n; r++) {
        if (m[r][col].abs() > m[pivot][col].abs()) pivot = r;
      }
      if (m[pivot][col].abs() < 1e-12) return null;
      final tmp = m[col];
      m[col] = m[pivot];
      m[pivot] = tmp;
      for (var r = 0; r < n; r++) {
        if (r == col) continue;
        final f = m[r][col] / m[col][col];
        for (var c = col; c <= n; c++) {
          m[r][c] -= f * m[col][c];
        }
      }
    }
    return List.generate(n, (i) => m[i][n] / m[i][i]);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// MarketContext — population statistics over the candidate set
// ═════════════════════════════════════════════════════════════════════════════

class _Dist {
  _Dist(this.sorted)
      : mean = sorted.isEmpty
            ? 0
            : sorted.reduce((a, b) => a + b) / sorted.length,
        std = _stdOf(sorted);
  final List<double> sorted; // ascending
  final double mean;
  final double std;

  static double _stdOf(List<double> xs) {
    if (xs.length < 2) return 0;
    final m = xs.reduce((a, b) => a + b) / xs.length;
    double v = 0;
    for (final x in xs) {
      v += (x - m) * (x - m);
    }
    return math.sqrt(v / xs.length);
  }

  double get median => percentile(0.5);

  /// Value at a [q]∈[0,1] quantile (linear interpolation).
  double percentile(double q) {
    if (sorted.isEmpty) return 0;
    if (sorted.length == 1) return sorted.first;
    final pos = (q.clamp(0.0, 1.0)) * (sorted.length - 1);
    final lo = pos.floor();
    final hi = pos.ceil();
    if (lo == hi) return sorted[lo];
    final frac = pos - lo;
    return sorted[lo] * (1 - frac) + sorted[hi] * frac;
  }

  /// Empirical CDF: fraction of the population ≤ [x] (∈[0,1]).
  double cdf(double x) {
    if (sorted.isEmpty) return 0.5;
    // binary search for first index > x
    var lo = 0, hi = sorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (sorted[mid] <= x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo / sorted.length;
  }

  /// Standard (z) score of [x].
  double z(double x) => std < 1e-9 ? 0.0 : (x - mean) / std;
}

class MarketContext {
  MarketContext._({
    required this.size,
    required _Dist price,
    required _Dist pricePerSqm,
    required _Dist rooms,
    required _Dist sizeM2,
    required this.cityMedianPrice,
    required this.amenityFrequency,
    required this.hedonic,
  })  : _price = price,
        _pricePerSqm = pricePerSqm,
        _rooms = rooms,
        _sizeM2 = sizeM2;

  final int size;
  final _Dist _price;
  final _Dist _pricePerSqm;
  final _Dist _rooms;
  final _Dist _sizeM2;

  /// Median rent per city (for affordability-vs-local-market).
  final Map<String, double> cityMedianPrice;

  /// Fraction of the market that has each amenity (live IDF source).
  final Map<String, double> amenityFrequency;

  /// Fitted hedonic price model (may be unfitted on tiny markets).
  final HedonicPriceModel hedonic;

  double get medianPrice => _price.median;
  double get medianPricePerSqm => _pricePerSqm.median;
  double get minRooms => _rooms.sorted.isEmpty ? 1 : _rooms.sorted.first;
  double get maxRooms => _rooms.sorted.isEmpty ? 6 : _rooms.sorted.last;

  double pricePercentile(int price) => _price.cdf(price.toDouble());
  double pricePerSqmPercentile(double v) => _pricePerSqm.cdf(v);
  double roomsPercentile(double r) => _rooms.cdf(r);
  double sizePercentile(int s) => _sizeM2.cdf(s.toDouble());
  double priceZ(int price) => _price.z(price.toDouble());

  /// Inverse-document-frequency weight of an amenity (rarer ⇒ higher).
  double amenityIdf(String catalogKey) {
    final freq = amenityFrequency[catalogKey];
    if (freq == null || size < 8) {
      return _amenityRarityPrior[catalogKey] ?? 0.4;
    }
    // smoothed IDF normalized to ~[0,1]
    final idf = math.log((1 + size) / (1 + freq * size)) / math.log(1 + size);
    return idf.clamp(0.05, 1.0);
  }

  /// Analyze a candidate set into a reusable context.
  static MarketContext analyze(List<RentalProperty> properties) {
    final prices = <double>[];
    final ppsqm = <double>[];
    final rooms = <double>[];
    final sizes = <double>[];
    final byCity = <String, List<double>>{};
    final amenityCounts = <String, int>{};
    var withAmenityData = 0;

    for (final p in properties) {
      if (p.price > 0) {
        prices.add(p.price.toDouble());
        byCity.putIfAbsent(p.city, () => []).add(p.price.toDouble());
      }
      final pps = p.pricePerSquareMeter;
      if (pps != null && pps > 0) ppsqm.add(pps.toDouble());
      if (p.rooms > 0) rooms.add(p.rooms);
      if (p.sizeM2 > 0) sizes.add(p.sizeM2.toDouble());

      final flags = p.featureFlags.values;
      if (flags.isNotEmpty) withAmenityData++;
      for (final entry in flags.entries) {
        if (entry.value) {
          amenityCounts[entry.key] = (amenityCounts[entry.key] ?? 0) + 1;
        }
      }
    }

    prices.sort();
    ppsqm.sort();
    rooms.sort();
    sizes.sort();

    final cityMedian = <String, double>{};
    byCity.forEach((city, list) {
      list.sort();
      cityMedian[city] = _Dist(list).median;
    });

    final freq = <String, double>{};
    if (withAmenityData > 0) {
      amenityCounts.forEach((k, c) {
        freq[k] = c / withAmenityData;
      });
    }

    // Temporary context for centrality (hedonic needs it). Centrality only needs
    // geo, so compute via a lightweight closure that doesn't depend on hedonic.
    double centralityOf(RentalProperty p) =>
        _centralityScore(p.lat, p.lon, p.city);

    final hedonic = HedonicPriceModel.fit(properties, centralityOf);

    return MarketContext._(
      size: properties.length,
      price: _Dist(prices),
      pricePerSqm: _Dist(ppsqm),
      rooms: _Dist(rooms),
      sizeM2: _Dist(sizes),
      cityMedianPrice: cityMedian,
      amenityFrequency: freq,
      hedonic: hedonic,
    );
  }
}

/// Centrality in [0,1]. Delegates to the gov-data composite (socioeconomic +
/// transit density + city prior); GeoIntelligence falls back to the city prior
/// when GovData isn't loaded.
double _centralityScore(double lat, double lon, String city) =>
    GeoIntelligence.centrality(lat, lon, city);

// ═════════════════════════════════════════════════════════════════════════════
// PropertyFeatureVector — the engineered representation
// ═════════════════════════════════════════════════════════════════════════════

class PropertyFeatureVector {
  PropertyFeatureVector(this.property, this.f);

  final RentalProperty property;

  /// Named features. All are finite; most are normalized to [0,1] or [-1,1].
  final Map<String, double> f;

  double get(String key, [double fallback = 0.0]) => f[key] ?? fallback;

  // Convenience typed accessors used heavily downstream.
  double get centrality => get('centrality');
  double get valueScore => get('value_score');
  double get transitAccess => get('transit_access');
  double get amenityRichness => get('amenity_richness');
  double get freshness => get('freshness');
  double get popularity => get('popularity');
  double get trust => get('trust');
  double get sizeNorm => get('size_norm');
  double get demandPressure => get('demand_pressure');

  @override
  String toString() =>
      'PFV(${property.id} centrality:${centrality.toStringAsFixed(2)} '
      'value:${valueScore.toStringAsFixed(2)} '
      'rich:${amenityRichness.toStringAsFixed(2)})';
}

// ═════════════════════════════════════════════════════════════════════════════
// FeatureEngineer — produces the PropertyFeatureVector
// ═════════════════════════════════════════════════════════════════════════════

class FeatureEngineer {
  const FeatureEngineer._();

  /// Map a free-text condition to an ordinal quality score in [0,1].
  static double conditionScore(String condition) {
    final c = condition.trim();
    const ranks = {
      'חדש מקבלן': 1.0,
      'חדש': 0.95,
      'משופץ': 0.85,
      'משופצת': 0.85,
      'ממש טוב': 0.8,
      'שמור': 0.72,
      'טוב': 0.6,
      'במצב טוב': 0.6,
      'סביר': 0.45,
      'דורש שיפוץ': 0.25,
      'דורש חידוש': 0.25,
    };
    for (final entry in ranks.entries) {
      if (c.contains(entry.key)) return entry.value;
    }
    return 0.55; // unknown ⇒ neutral-ish
  }

  /// Wilson score lower bound for a Bernoulli rate (like/view), at z=1.96 (95%).
  /// Prevents 1/1 listings from looking better than 480/500.
  static double wilsonLowerBound(int positives, int trials, {double z = 1.96}) {
    if (trials <= 0) return 0.0;
    final n = trials.toDouble();
    final phat = positives / n;
    final z2 = z * z;
    final denom = 1 + z2 / n;
    final centre = phat + z2 / (2 * n);
    final margin =
        z * math.sqrt((phat * (1 - phat) + z2 / (4 * n)) / n);
    return ((centre - margin) / denom).clamp(0.0, 1.0);
  }

  /// Build the full feature vector for one property against the market.
  static PropertyFeatureVector engineer(
    RentalProperty p,
    MarketContext mkt,
  ) {
    final f = <String, double>{};

    // ── geospatial (real gov-data: 33,937 transit stops + rail + SES) ─────────
    final transit = GeoIntelligence.transit(p.lat, p.lon);
    final uniKm = IsraelGeoIndex.nearestUniversityKm(p.lat, p.lon);
    final coastKm = IsraelGeoIndex.coastKm(p.lat, p.lon);

    f['centrality'] = _centralityScore(p.lat, p.lon, p.city);
    f['transit_access'] = transit.combined;
    f['transit_density'] = transit.densityScore;
    f['rail_access'] = transit.railAccess;
    f['rail_km'] = transit.railKm ?? 99.0;
    f['transit_km'] = transit.railKm ?? 99.0; // back-compat alias
    f['socioeconomic'] = GeoIntelligence.socioeconomicScore(p.city);
    f['university_access'] =
        IsraelGeoIndex.proximityKernel(uniKm, scaleKm: 3.0);
    f['coast_access'] = IsraelGeoIndex.proximityKernel(coastKm, scaleKm: 3.0);
    // Public-park proximity — hyper-local (a park matters within a short walk), so
    // a tight 0.7km kernel: ~1.0 next to a park, ~0.37 at 700m, ~0 past ~2km.
    f['park_access'] = IsraelGeoIndex.proximityKernel(
        IsraelGeoIndex.parkKm(p.lat, p.lon),
        scaleKm: 0.7);
    // Religiosity of the community: the curated locality/neighbourhood list (known
    // religious areas) OR real synagogue density around the flat — whichever is
    // stronger. The density term extends the signal NATIONALLY to observant
    // pockets the hardcoded list doesn't name, while known areas keep their score.
    f['religious_area'] = math.max(
      IsraelGeoIndex.religiousAreaScore(p.city, p.neighborhood),
      IsraelGeoIndex.synagogueDensity(p.lat, p.lon),
    );

    // ── price / value econometrics ───────────────────────────────────────────
    f['price'] = p.price.toDouble();
    f['price_percentile'] = mkt.pricePercentile(p.price);
    f['price_z'] = mkt.priceZ(p.price);
    final pps = (p.pricePerSquareMeter ?? 0).toDouble();
    f['price_per_sqm'] = pps;
    f['price_per_sqm_percentile'] =
        pps > 0 ? mkt.pricePerSqmPercentile(pps) : 0.5;
    f['price_per_room'] = p.rooms > 0 ? p.price / p.rooms : p.price.toDouble();

    // live OLS hedonic residual (unbiased, high-variance on small samples)
    final liveResidual = mkt.hedonic.isFitted
        ? mkt.hedonic.valueResidual(p, f['centrality']!)
        : _fallbackValueResidual(p, mkt);
    // gov ₪/m²-anchored residual (biased, stable) via empirical-Bayes shrinkage
    final liveFair = mkt.hedonic.isFitted
        ? mkt.hedonic.predictPrice(p, f['centrality']!)
        : null;
    final govResidual = MarketIntelligence.govValueResidual(
      price: p.price,
      liveFair: liveFair,
      city: p.city,
      sizeM2: p.sizeM2,
      marketSize: mkt.size,
    );
    final hasAnchor = MarketIntelligence.hasAnchor(p.city, p.sizeM2);
    // blend: when a real gov anchor exists, average the two; else pure live
    final residual = hasAnchor ? (0.5 * liveResidual + 0.5 * govResidual) : liveResidual;
    f['hedonic_residual'] = residual; // [-1,1] positive = underpriced
    f['gov_value_residual'] = govResidual;
    // value_score: map residual + ppsqm-percentile into [0,1] (higher = better deal)
    final ppsValue = pps > 0 ? (1.0 - mkt.pricePerSqmPercentile(pps)) : 0.5;
    f['value_score'] = (0.6 * ((residual + 1) / 2) + 0.4 * ppsValue)
        .clamp(0.0, 1.0);
    // ANTI-BAIT: an absurdly-cheap price (a typo, or lead-bait like "₪1,300 for a
    // 430m² TLV house") would otherwise look like an incredible deal and TOP the
    // results. Cap value + the underpricing residual by the price-trust so a fake
    // can't win on a bogus discount.
    final priceTrust = PriceRealism.priceTrust(p);
    f['price_trust'] = priceTrust;
    if (priceTrust < 1.0) {
      f['value_score'] = (f['value_score']! * priceTrust).clamp(0.0, 1.0);
      if (residual > 0) f['hedonic_residual'] = residual * priceTrust;
    }

    // affordability: prefer the gov per-locality norm; fall back to the live
    // candidate-set city median.
    if (hasAnchor) {
      f['affordability_local'] =
          MarketIntelligence.affordabilityVsLocal(p.price, p.city, p.sizeM2);
    } else {
      final cityMed = mkt.cityMedianPrice[p.city];
      f['affordability_local'] = (cityMed != null && cityMed > 0 && p.price > 0)
          ? (1.0 - ((p.price / cityMed) - 1).clamp(-1.0, 1.0))
          : 0.5;
    }

    // ── size / space ─────────────────────────────────────────────────────────
    f['rooms'] = p.rooms;
    f['rooms_percentile'] = mkt.roomsPercentile(p.rooms);
    f['size_m2'] = p.sizeM2.toDouble();
    f['size_percentile'] = mkt.sizePercentile(p.sizeM2);
    f['size_per_room'] = p.rooms > 0 ? p.sizeM2 / p.rooms : p.sizeM2.toDouble();
    // size_norm: -1 (tiny) .. +1 (spacious) relative to market room distribution
    f['size_norm'] = (mkt.roomsPercentile(p.rooms) * 2 - 1);
    f['floor_num'] = (p.floorNumber ?? 0).toDouble();

    // ── amenities ────────────────────────────────────────────────────────────
    final flags = p.featureFlags;
    int countIn(List<String> keys) =>
        keys.where((k) => flags.isEnabled(k)).length;
    final essential = countIn(_essentialAmenityKeys);
    final luxury = countIn(_luxuryAmenityKeys);
    final comfort = countIn(_comfortAmenityKeys);
    final totalEnabled = flags.values.values.where((v) => v).length;

    f['amenity_count'] = totalEnabled.toDouble();
    f['amenity_richness'] = (totalEnabled / 12.0).clamp(0.0, 1.0);
    f['essential_amenities'] =
        (essential / _essentialAmenityKeys.length).clamp(0.0, 1.0);
    f['luxury_amenities'] =
        (luxury / _luxuryAmenityKeys.length).clamp(0.0, 1.0);
    f['comfort_amenities'] =
        (comfort / _comfortAmenityKeys.length).clamp(0.0, 1.0);

    // rarity-weighted amenity score (live IDF): rare amenities count for more
    double weighted = 0;
    double maxWeighted = 0;
    for (final entry in _amenityRarityPrior.entries) {
      final idf = mkt.amenityIdf(entry.key);
      maxWeighted += idf;
      if (flags.isEnabled(entry.key)) weighted += idf;
    }
    f['weighted_amenity_score'] =
        maxWeighted > 0 ? (weighted / maxWeighted).clamp(0.0, 1.0) : 0.0;

    // ── condition ────────────────────────────────────────────────────────────
    f['condition_score'] = conditionScore(p.condition);

    // ── temporal ─────────────────────────────────────────────────────────────
    final ageDays = p.createdAt == null
        ? 30.0
        : DateTime.now().difference(p.createdAt!).inDays.toDouble().clamp(0.0, 3650.0);
    f['age_days'] = ageDays;
    // smooth exponential freshness: ~1 fresh, ~0.5 at ~21 days, →0 old
    f['freshness'] = math.exp(-ageDays / 30.0);
    f['is_new_listing'] = p.isNewListing ? 1.0 : 0.0;

    // ── behavioral / market demand ───────────────────────────────────────────
    final s = p.marketSignals;
    final views = s.views;
    final engagement =
        s.views + s.likes * 3 + s.saves * 4 + s.contactRequests * 6;
    f['engagement_raw'] = engagement.toDouble();
    // log-compressed popularity normalized to a "trending" ceiling
    f['popularity'] = engagement > 0
        ? (math.log(1 + engagement) / math.log(1 + 250)).clamp(0.0, 1.0)
        : 0.0;
    // quality of demand (confidence-bounded), not just volume
    f['like_rate_wilson'] = wilsonLowerBound(s.likes, views);
    f['save_rate'] = views > 0 ? (s.saves / views).clamp(0.0, 1.0) : 0.0;
    f['conversion_rate'] =
        views > 0 ? (s.contactRequests / views).clamp(0.0, 1.0) : 0.0;
    // skip pressure: many skips relative to views ⇒ market disinterest
    final totalReactions = s.likes + s.skips;
    f['skip_ratio'] =
        totalReactions > 0 ? (s.skips / totalReactions).clamp(0.0, 1.0) : 0.5;
    // detail dwell time (seconds) compressed
    f['detail_dwell'] =
        (s.avgDetailStaySeconds / 120.0).clamp(0.0, 1.0);
    // live demand pressure (people looking now / liked today)
    f['demand_pressure'] =
        ((s.liveViewers * 2 + s.likesToday) / 10.0).clamp(0.0, 1.0);

    // ── trust / media ────────────────────────────────────────────────────────
    final imageCount = p.imageUrls.length;
    final videoCount = p.videoUrls.length;
    f['media_richness'] =
        ((imageCount + videoCount * 2) / 8.0).clamp(0.0, 1.0);
    f['has_3d_tour'] = p.hasReadyVirtualTour || p.hasModel3d ? 1.0 : 0.0;
    f['verified'] = p.isVerifiedListing ? 1.0 : 0.0;
    f['trust'] = (0.5 * (p.isVerifiedListing ? 1.0 : 0.0) +
            0.3 * ((imageCount + videoCount * 2) / 8.0).clamp(0.0, 1.0) +
            0.2 * (p.hasReadyVirtualTour || p.hasModel3d ? 1.0 : 0.0))
        .clamp(0.0, 1.0);

    // ── livability (real gov data: crime, schools, demographics, health, air) ──
    final gov = GovData.instance;
    // Safety = 1 − percentile(per-capita reported crime). That per-capita rate
    // uses a RESIDENTIAL denominator, but offences accrue from a much larger
    // daytime/commuter/tourist population — so a dense, affluent CENTRE reads far
    // more "dangerous" than residents experience (Tel Aviv ≈ 0.01). Correct the
    // bias HERE (not just in the GBM penalty) so BOTH the score AND the scorecard
    // caveat use the corrected value: pull an inflated-low safety toward neutral in
    // proportion to hubness (centrality ∨ SES). A genuinely distressed area — low
    // centrality AND low SES — gets ~no relief, so its low safety stays honest.
    final rawSafety = gov.safetyScore(p.city) ?? 0.5;
    if (rawSafety < 0.5) {
      final hubness = math.max(f['centrality'] ?? 0.5, f['socioeconomic'] ?? 0.5);
      final relief = ((hubness - 0.5).clamp(0.0, 0.5) / 0.5) * 0.8; // 0..0.8
      f['safety'] = (rawSafety + (0.5 - rawSafety) * relief).clamp(0.0, 1.0);
    } else {
      f['safety'] = rawSafety;
    }
    // Schools: BLEND the area density (many schools around) with the exact
    // distance to the nearest named school (a school within a short walk counts
    // even if the wider density is moderate).
    final schoolDensity = gov.schoolDensityScore(p.lat, p.lon);
    final schoolProximity = IsraelGeoIndex.proximityKernel(
        IsraelGeoIndex.nearestSchoolKm(p.lat, p.lon),
        scaleKm: 0.9);
    f['school_density'] = schoolDensity;
    f['school_proximity'] = schoolProximity;
    f['school_access'] = math.max(schoolDensity, schoolProximity);
    // Age-targeted school proximity: young kids → גן/יסודי; teens → חטיבה/תיכון.
    f['school_young_prox'] =
        IsraelGeoIndex.schoolTypeProximity(p.lat, p.lon, ['גן', 'יסודי']);
    f['school_teen_prox'] =
        IsraelGeoIndex.schoolTypeProximity(p.lat, p.lon, ['תיכון', 'חטיבה']);
    // Nightlife/vibrancy — real bar/pub/café density (a "young, lively area").
    f['nightlife'] = IsraelGeoIndex.nightlifeDensity(p.lat, p.lon);
    // Health access — REAL national clinic points (point-level, HMO-tagged) as the
    // primary signal, falling back to the city-level gov table where no clinic is
    // mapped nearby. max() keeps whichever is the stronger evidence.
    f['health_access'] = math.max(
        IsraelGeoIndex.clinicAccess(p.lat, p.lon), gov.healthAccessScore(p.city));
    // Errands access — REAL national supermarket points (4.5k) as the primary
    // signal, OR-ed with the gov retail grid (which also counts malls where it has
    // coverage). Replaces the Tel-Aviv-only 16-cell retail seed.
    f['retail_access'] = math.max(IsraelGeoIndex.supermarketAccess(p.lat, p.lon),
        gov.retailAccessScore(p.lat, p.lon));
    // Quietness (physical): 1 = far from a major road/rail, 0 = right on one.
    // "unknown" (no noise dataset) stays neutral 0.5 — absence ≠ silence.
    final noise = gov.roadNoiseScore(p.lat, p.lon);
    f['low_noise'] = noise == null ? 0.5 : (1.0 - noise);
    // Investor upside — proximity to a PLANNED metro/light-rail station or an
    // urban-renewal project. 0 = no known upside nearby (a bonus, never a penalty).
    f['future_value'] = gov.futureValueScore(p.lat, p.lon);
    // Employment access — job-place density nearby (a short-commute proxy when the
    // seeker hasn't named a workplace). 0 when the dataset isn't bundled.
    f['employment_access'] = gov.employmentAccessScore(p.lat, p.lon);
    final demo = gov.demographics(p.city);
    f['demo_young'] = demo?['youngShare'] ?? 0.5; // working-age share (20-64)
    f['demo_child'] = demo?['childShare'] ?? 0.5; // 0-19 share (family areas)
    f['demo_senior'] = demo?['seniorShare'] ?? 0.5;
    // MICRO-NEIGHBOURHOOD precision: if the flat falls inside a CBS statistical
    // area (~3,000 residents), its OWN block's socioeconomic cluster + age split
    // OVERRIDE the whole-city average — so neighbourhood/young_area/senior_area/
    // family are scored at street granularity, not "all of Tel Aviv". Degrades to
    // the city figures when the point isn't in any known polygon.
    final sa = gov.statAreaAt(p.lat, p.lon);
    if (sa != null) {
      if (sa.ses >= 1 && sa.ses <= 10) {
        f['socioeconomic'] = (sa.ses - 1) / 9.0;
      }
      f['demo_young'] = sa.youngShare;
      f['demo_child'] = sa.childShare;
      f['demo_senior'] = sa.seniorShare;
    }
    final airKm = gov.nearestAirStationKm(p.lat, p.lon);
    f['air_station_km'] = airKm ?? 99.0; // coarse environmental-monitoring proxy

    // sanitize: replace any NaN/Inf with neutral 0
    for (final key in f.keys.toList()) {
      final v = f[key]!;
      if (v.isNaN || v.isInfinite) f[key] = 0.0;
    }

    return PropertyFeatureVector(p, f);
  }

  // When the hedonic model can't fit (tiny market), approximate value from
  // price-per-sqm percentile vs the market.
  static double _fallbackValueResidual(RentalProperty p, MarketContext mkt) {
    final pps = p.pricePerSquareMeter;
    if (pps == null || pps <= 0) return 0.0;
    // below-median ppsqm ⇒ positive residual (good value)
    return ((0.5 - mkt.pricePerSqmPercentile(pps.toDouble())) * 2)
        .clamp(-1.0, 1.0);
  }
}
