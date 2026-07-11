// ════════════════════════════════════════════════════════════════════════════
// PART B / 5 — REFERENCE DATA LAYER
// ════════════════════════════════════════════════════════════════════════════
//
// Loads the compact assets compiled by scripts/govdata/ingest.mjs from real
// data.gov.il datasets (33,937 transit stops → locality centroids + density grid
// + rail index, the localities registry, CBS socioeconomic clusters, and ₪/m²
// market priors) and exposes fast, synchronous lookups to the recommendation
// engine.
//
// Production posture:
//   • One async init() (reads bundled JSON), then everything is sync.
//   • Fully degradable: if assets are missing/corrupt, `loaded` stays false and
//     every accessor returns null/empty so the engine falls back to heuristics.
//   • Asset reading is injectable (AssetReader) so it's testable without the
//     Flutter asset binding.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/services.dart' show rootBundle;

/// Reads the raw string contents of a bundled asset path.
typedef AssetReader = Future<String> Function(String path);

const String _assetDir = 'assets/data/govdata';

// ── name normalization (mirrors ingest.mjs normName) ─────────────────────────
String normalizeLocalityName(String s) {
  var out = s.replaceAll(RegExp('["\'״׳]'), '');
  out = out.replaceAll(RegExp(r'\s*-\s*'), '-');
  out = out.replaceAll(RegExp(r'\s+'), ' ').trim();
  return out;
}

// ═════════════════════════════════════════════════════════════════════════════
// Models
// ═════════════════════════════════════════════════════════════════════════════

class LocalityRecord {
  const LocalityRecord({
    required this.code,
    required this.name,
    required this.nameEn,
    required this.district,
    required this.lat,
    required this.lon,
    required this.stops,
    required this.rail,
    required this.bus,
    required this.ses,
  });

  final int code;
  final String name;
  final String nameEn;
  final String district;
  final double lat;
  final double lon;
  final int stops; // total public-transport stops in the locality
  final int rail; // rail/light-rail stops
  final int bus; // bus stops
  final int ses; // CBS socioeconomic cluster 1..10 (0 = unknown)

  bool get hasSocioeconomic => ses >= 1 && ses <= 10;

  factory LocalityRecord.fromJson(Map<String, dynamic> j) => LocalityRecord(
        code: (j['code'] as num?)?.toInt() ?? 0,
        name: j['name'] as String? ?? '',
        nameEn: j['nameEn'] as String? ?? '',
        district: j['district'] as String? ?? '',
        lat: (j['lat'] as num?)?.toDouble() ?? 0,
        lon: (j['lon'] as num?)?.toDouble() ?? 0,
        stops: (j['stops'] as num?)?.toInt() ?? 0,
        rail: (j['rail'] as num?)?.toInt() ?? 0,
        bus: (j['bus'] as num?)?.toInt() ?? 0,
        ses: (j['ses'] as num?)?.toInt() ?? 0,
      );
}

class MarketPrior {
  const MarketPrior(this.rentPerSqm, this.salePerSqm);
  final double rentPerSqm;
  final double salePerSqm;
}

/// A CBS statistical area (אזור סטטיסטי, ~3,000 residents) — far finer than a
/// whole city. Carries its own socioeconomic cluster + age split and a boundary
/// polygon ([[lat,lon],…]) so a flat is scored by the block it sits in, not the
/// city average (huge for heterogeneous cities like TA / Jerusalem / Haifa).
class StatArea {
  const StatArea({
    required this.ses,
    required this.youngShare,
    required this.childShare,
    required this.seniorShare,
    required this.poly,
    this.city = '',
    this.id = 0,
  });
  final int ses; // 1..10 (0 = unknown)
  final double youngShare;
  final double childShare;
  final double seniorShare;
  final List<List<double>> poly; // [[lat,lon], …]
  final String city; // settlement name (for city ranking)
  final int id; // YISHUV*10000 + stat-area

  /// Approximate centroid (mean of the ring vertices) — [lat, lon]. Enough for
  /// profiling the area and placing it on a map.
  List<double> get centroid {
    if (poly.isEmpty) return const [0, 0];
    var la = 0.0, lo = 0.0;
    for (final p in poly) {
      la += p[0];
      lo += p[1];
    }
    return [la / poly.length, lo / poly.length];
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// GovData — the singleton reference store
// ═════════════════════════════════════════════════════════════════════════════

class GovData {
  GovData._();
  static final GovData instance = GovData._();

  bool _loaded = false;
  bool get loaded => _loaded;

  int version = 0;

  // localities
  final List<LocalityRecord> _localities = [];
  final Map<int, LocalityRecord> _byCode = {};
  final Map<String, LocalityRecord> _byName = {};

  // transit density grid
  double _gridCell = 0.02;
  final Map<String, List<int>> _grid = {}; // key → [count, railCount]
  int _maxCellDensity = 1;

  // rail stations [lat, lon, name]
  final List<List<double>> _railLatLon = [];
  final List<String> _railName = [];

  // market priors by normalized locality name
  final Map<String, MarketPrior> _market = {};

  // loose index (spaces/hyphens/quotes stripped) for robust cross-dataset name
  // joins — e.g. police "תל אביב יפו" ↔ registry "תל אביב - יפו".
  final Map<String, LocalityRecord> _byLoose = {};

  // crime (safety): code → [total, violent, property]; + loose-name fallback
  final Map<int, List<int>> _crime = {};
  final Map<String, List<int>> _crimeLoose = {};
  // derived crime-rate distribution (offences per 1,000 residents)
  final Map<int, double> _crimeRate = {};
  List<double> _rateSorted = const [];

  // demographics: code → {pop, youngShare, childShare, seniorShare}
  final Map<int, Map<String, double>> _demo = {};
  final Map<String, Map<String, double>> _demoLoose = {};

  // schools density grid: key → [schoolCount, kindergartenCount]
  double _schoolCell = 0.02;
  final Map<String, List<int>> _schoolGrid = {};
  int _maxSchoolCell = 1;

  // health facilities (clinic counts): code → count; + loose fallback
  final Map<int, int> _health = {};
  final Map<String, int> _healthLoose = {};
  int _maxHealth = 1;

  // air-quality monitoring stations [lat, lon]
  final List<List<double>> _airLatLon = [];

  // retail/errands density grid: key → [supermarkets, malls] (OSM / data.gov.il)
  double _retailCell = 0.02;
  final Map<String, List<int>> _retailGrid = {};
  int _maxRetailCell = 1;

  // noise proxy: presence of a MAJOR road / rail line per FINE cell (~500m), so a
  // flat hugging the Ayalon or a train line reads as loud. Presence, not count —
  // one motorway is enough. key → segment count. (OSM highways + railways.)
  double _noiseCell = 0.005;
  final Map<String, int> _noiseGrid = {};

  // statistical areas (CBS): polygons + per-block SES/age, bucketed into a 0.02°
  // index by bounding box so a point-in-polygon lookup only tests nearby areas.
  double _statCell = 0.02;
  final List<StatArea> _statAreas = [];
  final Map<String, List<int>> _statIndex = {}; // cell → candidate area indices

  // future infrastructure (investor upside): PLANNED metro/light-rail stations
  // (נת״ע) + urban-renewal projects (פינוי-בינוי / תמ״א). Point lists → proximity.
  final List<List<double>> _futureStations = []; // [lat, lon]
  final List<List<double>> _renewalPoints = []; // [lat, lon]

  // employment density grid: key → job-place count (OSM offices + commercial /
  // industrial). A flat in/near a dense cell = a short commute to many jobs.
  double _jobCell = 0.02;
  final Map<String, int> _jobGrid = {};
  int _maxJobCell = 1;

  List<LocalityRecord> get localities => List.unmodifiable(_localities);

  // ── init ────────────────────────────────────────────────────────────────────
  Future<bool> init({AssetReader? reader}) async {
    if (_loaded) return true;
    final read = reader ?? _rootBundleReader;
    try {
      await _loadLocalities(read);
      await _loadGrid(read);
      await _loadRail(read);
      await _loadMarket(read);
      await _loadMeta(read);
      // New gov datasets — each optional & independently guarded so a missing
      // or malformed one degrades only its own signal, never the whole layer.
      await _loadOptional(() => _loadCrime(read));
      await _loadOptional(() => _loadDemographics(read));
      await _loadOptional(() => _loadSchools(read));
      await _loadOptional(() => _loadHealth(read));
      await _loadOptional(() => _loadAirQuality(read));
      await _loadOptional(() => _loadRetail(read));
      await _loadOptional(() => _loadNoise(read));
      await _loadOptional(() => _loadStatAreas(read));
      await _loadOptional(() => _loadAreaValue(read));
      await _loadOptional(() => _loadFutureInfra(read));
      await _loadOptional(() => _loadEmployment(read));
      _deriveCrimeRates();
      _loaded = _localities.isNotEmpty;
      return _loaded;
    } catch (_) {
      _loaded = false;
      return false;
    }
  }

  static Future<String> _rootBundleReader(String path) =>
      rootBundle.loadString(path);

  Future<void> _loadLocalities(AssetReader read) async {
    final raw = await read('$_assetDir/localities.json');
    final list = jsonDecode(raw) as List<dynamic>;
    for (final item in list) {
      final rec = LocalityRecord.fromJson(item as Map<String, dynamic>);
      _localities.add(rec);
      _byCode[rec.code] = rec;
      // index by the full normalized name AND its base (before a hyphen), so
      // "תל אביב" resolves the "תל אביב-יפו" record. Keep the entry with the
      // most stops on collision (the "real"/largest locality).
      for (final key in _nameKeys(rec.name)) {
        final existing = _byName[key];
        if (existing == null || rec.stops > existing.stops) {
          _byName[key] = rec;
        }
      }
      final lk = _looseKey(rec.name);
      final le = _byLoose[lk];
      if (le == null || rec.stops > le.stops) _byLoose[lk] = rec;
    }
  }

  // Strips spaces/hyphens/quotes for tolerant cross-dataset name joins.
  static String _looseKey(String s) =>
      normalizeLocalityName(s).replaceAll('-', '').replaceAll(' ', '');

  // Resolve any locality name (from any dataset) to its registry code.
  int? _resolveCode(String name) {
    for (final key in _nameKeys(name)) {
      final r = _byName[key];
      if (r != null) return r.code;
    }
    return _byLoose[_looseKey(name)]?.code;
  }

  static Future<void> _loadOptional(Future<void> Function() load) async {
    try {
      await load();
    } catch (_) {
      // optional dataset — ignore and continue
    }
  }

  Future<void> _loadCrime(AssetReader read) async {
    final obj = jsonDecode(await read('$_assetDir/crime.json'))
        as Map<String, dynamic>;
    for (final e in obj.entries) {
      final m = e.value as Map<String, dynamic>;
      final v = [
        (m['total'] as num?)?.toInt() ?? 0,
        (m['violent'] as num?)?.toInt() ?? 0,
        (m['property'] as num?)?.toInt() ?? 0,
      ];
      final code = _resolveCode(e.key);
      if (code != null) {
        _crime[code] = v;
      } else {
        _crimeLoose[_looseKey(e.key)] = v;
      }
    }
  }

  Future<void> _loadDemographics(AssetReader read) async {
    final obj = jsonDecode(await read('$_assetDir/demographics.json'))
        as Map<String, dynamic>;
    for (final e in obj.entries) {
      final m = e.value as Map<String, dynamic>;
      final d = <String, double>{
        'pop': (m['pop'] as num?)?.toDouble() ?? 0,
        'youngShare': (m['youngShare'] as num?)?.toDouble() ?? 0,
        'childShare': (m['childShare'] as num?)?.toDouble() ?? 0,
        'seniorShare': (m['seniorShare'] as num?)?.toDouble() ?? 0,
      };
      final code = _resolveCode(e.key);
      if (code != null) {
        _demo[code] = d;
      } else {
        _demoLoose[_looseKey(e.key)] = d;
      }
    }
  }

  Future<void> _loadSchools(AssetReader read) async {
    final obj = jsonDecode(await read('$_assetDir/schools_grid.json'))
        as Map<String, dynamic>;
    _schoolCell = (obj['cell'] as num?)?.toDouble() ?? 0.02;
    final cells = obj['cells'] as Map<String, dynamic>;
    for (final e in cells.entries) {
      final v =
          (e.value as List<dynamic>).map((x) => (x as num).toInt()).toList();
      _schoolGrid[e.key] = v;
      final total = v.fold<int>(0, (a, b) => a + b);
      if (total > _maxSchoolCell) _maxSchoolCell = total;
    }
  }

  Future<void> _loadHealth(AssetReader read) async {
    final obj = jsonDecode(await read('$_assetDir/health.json'))
        as Map<String, dynamic>;
    for (final e in obj.entries) {
      final count = (e.value as num?)?.toInt() ?? 0;
      if (count > _maxHealth) _maxHealth = count;
      final code = _resolveCode(e.key);
      if (code != null) {
        _health[code] = (_health[code] ?? 0) + count;
      } else {
        _healthLoose[_looseKey(e.key)] = count;
      }
    }
  }

  Future<void> _loadAirQuality(AssetReader read) async {
    final list = jsonDecode(await read('$_assetDir/air_quality_stations.json'))
        as List<dynamic>;
    for (final item in list) {
      final t = item as List<dynamic>;
      _airLatLon.add([(t[0] as num).toDouble(), (t[1] as num).toDouble()]);
    }
  }

  // Build the offences-per-1,000-residents distribution from crime ⨝ demographics.
  void _deriveCrimeRates() {
    for (final e in _crime.entries) {
      final demo = _demo[e.key];
      final pop = demo?['pop'] ?? 0;
      if (pop > 500) {
        _crimeRate[e.key] = e.value[0] / (pop / 1000.0);
      }
    }
    final rates = _crimeRate.values.toList()..sort();
    _rateSorted = rates;
  }

  Future<void> _loadGrid(AssetReader read) async {
    final raw = await read('$_assetDir/transit_grid.json');
    final obj = jsonDecode(raw) as Map<String, dynamic>;
    _gridCell = (obj['cell'] as num?)?.toDouble() ?? 0.02;
    final cells = obj['cells'] as Map<String, dynamic>;
    for (final entry in cells.entries) {
      final v = (entry.value as List<dynamic>)
          .map((e) => (e as num).toInt())
          .toList();
      _grid[entry.key] = v;
      if (v.isNotEmpty && v[0] > _maxCellDensity) _maxCellDensity = v[0];
    }
  }

  Future<void> _loadRail(AssetReader read) async {
    final raw = await read('$_assetDir/rail_stations.json');
    final list = jsonDecode(raw) as List<dynamic>;
    for (final item in list) {
      final t = item as List<dynamic>;
      _railLatLon.add([(t[0] as num).toDouble(), (t[1] as num).toDouble()]);
      _railName.add(t.length > 2 ? (t[2]?.toString() ?? '') : '');
    }
  }

  Future<void> _loadMarket(AssetReader read) async {
    final raw = await read('$_assetDir/market_seed.json');
    final obj = jsonDecode(raw) as Map<String, dynamic>;
    for (final entry in obj.entries) {
      final m = entry.value as Map<String, dynamic>;
      final prior = MarketPrior(
        (m['rentPerSqm'] as num?)?.toDouble() ?? 0,
        (m['salePerSqm'] as num?)?.toDouble() ?? 0,
      );
      for (final key in _nameKeys(entry.key)) {
        _market.putIfAbsent(key, () => prior);
      }
    }
  }

  Future<void> _loadMeta(AssetReader read) async {
    try {
      final raw = await read('$_assetDir/meta.json');
      final obj = jsonDecode(raw) as Map<String, dynamic>;
      version = (obj['version'] as num?)?.toInt() ?? 0;
    } catch (_) {
      version = 0;
    }
  }

  // ── lookups (all sync, null/empty-safe before init) ──────────────────────────

  // Full normalized name + base-before-hyphen (e.g. "תל אביב-יפו" → "תל אביב").
  static List<String> _nameKeys(String name) {
    final full = normalizeLocalityName(name);
    final base = full.split('-').first.trim();
    return base.isNotEmpty && base != full ? [full, base] : [full];
  }

  LocalityRecord? localityByName(String name) {
    if (!_loaded) return null;
    for (final key in _nameKeys(name)) {
      final hit = _byName[key];
      if (hit != null) return hit;
    }
    return null;
  }

  LocalityRecord? localityByCode(int code) => _byCode[code];

  /// The LONGEST known locality name (CBS list — every city, moshav, kibbutz,
  /// village) that appears in [text]. Returns the record so callers get coords +
  /// district too. This is how a free-text search recognises tiny places like
  /// "עין עירון" that no hand-maintained list would contain. Longest-match wins so
  /// "קרית ביאליק" beats "קרית", and a ≥3-char floor avoids spurious hits.
  LocalityRecord? findLocalityInText(String text) {
    if (!_loaded || text.trim().isEmpty) return null;
    final t = normalizeLocalityName(text);
    LocalityRecord? best;
    var bestLen = 0;
    for (final rec in _byCode.values) {
      final n = rec.name;
      // Locality names that ARE extremely common Hebrew words ("אזור"=area,
      // "חמד"=lovely) hallucinate a city out of ordinary phrasing ("אזור שקט").
      // Skip them in free-text matching — they're rare as an actual search target.
      if (_ambiguousLocalityNames.contains(n)) continue;
      // Match the full CBS name OR, for a MERGED municipality ("בנימינה-גבעת עדה",
      // "מעלות-תרשיחא", "פרדס חנה-כרכור"), ANY settlement people actually say
      // ("בנימינה", "כרכור", "מכבים"). Longest match wins so specificity is kept.
      for (final v in {
        n,
        if (n.contains('-'))
          ...n.split('-').map((s) => s.trim()).where((s) => s.length >= 4),
      }) {
        if (v.length >= 3 && v.length > bestLen && _containsWord(t, v)) {
          best = rec;
          bestLen = v.length;
        }
      }
    }
    return best;
  }

  static const _ambiguousLocalityNames = {'אזור', 'חמד', 'גן', 'אור', 'נס'};
  static const _hebrewPrefixes = {'ב', 'ל', 'מ', 'ה', 'ו', 'ש', 'כ'};

  static bool _isHebrewLetter(int c) => c >= 0x05D0 && c <= 0x05EA;

  /// True only if [word] appears as a WHOLE word in [text] — not glued inside a
  /// larger Hebrew word. A single inseparable prefix (ב/ל/מ/ה/ו/ש/כ) is allowed,
  /// so "בכרכור"/"להרצליה" still match, but "נחמד" does NOT match "חמד".
  static bool _containsWord(String text, String word) {
    var i = text.indexOf(word);
    while (i >= 0) {
      final afterIdx = i + word.length;
      final after = afterIdx < text.length ? text.codeUnitAt(afterIdx) : 0;
      final afterOk = !_isHebrewLetter(after);
      bool beforeOk;
      if (i == 0) {
        beforeOk = true;
      } else if (!_isHebrewLetter(text.codeUnitAt(i - 1))) {
        beforeOk = true;
      } else if (_hebrewPrefixes.contains(text[i - 1]) &&
          (i == 1 || !_isHebrewLetter(text.codeUnitAt(i - 2)))) {
        beforeOk = true; // a single attached prefix: "בכרכור", "לתל אביב"
      } else {
        beforeOk = false; // glued mid-word: "נחמד" ≠ "חמד"
      }
      if (beforeOk && afterOk) return true;
      i = text.indexOf(word, i + 1);
    }
    return false;
  }

  /// CBS socioeconomic cluster (1..10) for a city, or 0 if unknown.
  int socioeconomic(String city) => localityByName(city)?.ses ?? 0;

  /// Per-m² monthly-rent prior for a city, or null if we have no anchor.
  double? rentPerSqm(String city) {
    if (!_loaded) return null;
    for (final key in _nameKeys(city)) {
      final p = _market[key];
      if (p != null && p.rentPerSqm > 0) return p.rentPerSqm;
    }
    return null;
  }

  double? salePerSqm(String city) {
    if (!_loaded) return null;
    for (final key in _nameKeys(city)) {
      final p = _market[key];
      if (p != null && p.salePerSqm > 0) return p.salePerSqm;
    }
    return null;
  }

  // ── new gov-data signals ─────────────────────────────────────────────────────

  /// [total, violent, property] recorded offences for a city, or null.
  List<int>? crimeCounts(String city) {
    if (!_loaded) return null;
    final code = _resolveCode(city);
    if (code != null && _crime[code] != null) return _crime[code];
    return _crimeLoose[_looseKey(city)];
  }

  /// Safety score in [0,1] (1 = safest) from offences-per-1,000-residents vs the
  /// national distribution. Null when crime or population data is unavailable.
  double? safetyScore(String city) {
    if (!_loaded || _rateSorted.isEmpty) return null;
    final code = _resolveCode(city);
    if (code == null) return null;
    final rate = _crimeRate[code];
    if (rate == null) return null;
    // safer = lower crime rate ⇒ 1 − percentile(rate)
    return (1.0 - _cdf(_rateSorted, rate)).clamp(0.0, 1.0);
  }

  /// Demographics {pop, youngShare, childShare, seniorShare} for a city, or null.
  Map<String, double>? demographics(String city) {
    if (!_loaded) return null;
    final code = _resolveCode(city);
    if (code != null && _demo[code] != null) return _demo[code];
    return _demoLoose[_looseKey(city)];
  }

  /// Education-institution density in [0,1] around a point (log-scaled count of
  /// schools+kindergartens in a ~6 km² window vs the densest cell).
  double schoolDensityScore(double lat, double lon) {
    if (!_loaded || _schoolGrid.isEmpty || !_validCoord(lat, lon)) return 0.0;
    final cx = (lat / _schoolCell).round();
    final cy = (lon / _schoolCell).round();
    var total = 0;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final cell = _schoolGrid['${cx + dx}_${cy + dy}'];
        if (cell != null) {
          total += cell.fold<int>(0, (a, b) => a + b);
        }
      }
    }
    if (total <= 0) return 0.0;
    return (math.log(1 + total) / math.log(1 + _maxSchoolCell * 3))
        .clamp(0.0, 1.0);
  }

  Future<void> _loadRetail(AssetReader read) async {
    final obj = jsonDecode(await read('$_assetDir/poi_retail.json'))
        as Map<String, dynamic>;
    _retailCell = (obj['cell'] as num?)?.toDouble() ?? 0.02;
    final cells = obj['cells'] as Map<String, dynamic>;
    for (final e in cells.entries) {
      final v =
          (e.value as List<dynamic>).map((x) => (x as num).toInt()).toList();
      _retailGrid[e.key] = v;
      final total = v.fold<int>(0, (a, b) => a + b);
      if (total > _maxRetailCell) _maxRetailCell = total;
    }
  }

  /// Errands/retail access in [0,1] around a point — supermarkets + shopping
  /// centres within a ~6 km² window, log-scaled vs the densest cell. A mall is
  /// weighted x2 (it covers far more errands than a single grocery). 0 when the
  /// dataset is missing (the layer degrades to neutral).
  double retailAccessScore(double lat, double lon) {
    if (!_loaded || _retailGrid.isEmpty || !_validCoord(lat, lon)) return 0.0;
    final cx = (lat / _retailCell).round();
    final cy = (lon / _retailCell).round();
    var weighted = 0;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final cell = _retailGrid['${cx + dx}_${cy + dy}'];
        if (cell != null) {
          final markets = cell.isNotEmpty ? cell[0] : 0;
          final malls = cell.length > 1 ? cell[1] : 0;
          weighted += markets + malls * 2;
        }
      }
    }
    if (weighted <= 0) return 0.0;
    return (math.log(1 + weighted) / math.log(1 + _maxRetailCell * 3))
        .clamp(0.0, 1.0);
  }

  Future<void> _loadNoise(AssetReader read) async {
    final obj = jsonDecode(await read('$_assetDir/noise_roads.json'))
        as Map<String, dynamic>;
    _noiseCell = (obj['cell'] as num?)?.toDouble() ?? 0.005;
    final cells = obj['cells'] as Map<String, dynamic>;
    for (final e in cells.entries) {
      _noiseGrid[e.key] = (e.value as num).toInt();
    }
  }

  /// Road/rail NOISE proxy in [0,1] (1 = loud, right on a major road/rail; 0 =
  /// no major road within ~1.5km). Presence-based: the property's own ~500m cell
  /// counts full, the surrounding ring half. Returns null when the dataset is
  /// missing (caller treats "unknown" as neutral, not silent-quiet).
  double? roadNoiseScore(double lat, double lon) {
    if (!_loaded || _noiseGrid.isEmpty || !_validCoord(lat, lon)) return null;
    final cx = (lat / _noiseCell).round();
    final cy = (lon / _noiseCell).round();
    if ((_noiseGrid['${cx}_$cy'] ?? 0) > 0) return 1.0;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        if (dx == 0 && dy == 0) continue;
        if ((_noiseGrid['${cx + dx}_${cy + dy}'] ?? 0) > 0) return 0.5;
      }
    }
    return 0.0;
  }

  Future<void> _loadStatAreas(AssetReader read) async {
    final obj = jsonDecode(await read('$_assetDir/stat_areas.json'))
        as Map<String, dynamic>;
    _statCell = (obj['cell'] as num?)?.toDouble() ?? 0.02;
    final areas = obj['areas'] as List<dynamic>;
    for (final a in areas) {
      final m = a as Map<String, dynamic>;
      final poly = (m['poly'] as List<dynamic>)
          .map((p) => (p as List<dynamic>)
              .map((n) => (n as num).toDouble())
              .toList())
          .toList();
      if (poly.length < 3) continue;
      final idx = _statAreas.length;
      _statAreas.add(StatArea(
        ses: (m['ses'] as num?)?.toInt() ?? 0,
        youngShare: (m['young'] as num?)?.toDouble() ?? 0.5,
        childShare: (m['child'] as num?)?.toDouble() ?? 0.5,
        seniorShare: (m['senior'] as num?)?.toDouble() ?? 0.5,
        city: (m['city'] as String?)?.trim() ?? '',
        id: (m['id'] as num?)?.toInt() ?? 0,
        poly: poly,
      ));
      // Stamp every 0.02° cell the polygon's bounding box covers → this area.
      var minLat = poly.first[0], maxLat = poly.first[0];
      var minLon = poly.first[1], maxLon = poly.first[1];
      for (final pt in poly) {
        minLat = math.min(minLat, pt[0]);
        maxLat = math.max(maxLat, pt[0]);
        minLon = math.min(minLon, pt[1]);
        maxLon = math.max(maxLon, pt[1]);
      }
      for (var cx = (minLat / _statCell).floor();
          cx <= (maxLat / _statCell).ceil();
          cx++) {
        for (var cy = (minLon / _statCell).floor();
            cy <= (maxLon / _statCell).ceil();
            cy++) {
          (_statIndex['${cx}_$cy'] ??= []).add(idx);
        }
      }
    }
  }

  /// The CBS statistical area containing [lat],[lon], or null (point in no known
  /// polygon / dataset absent). Only tests the few areas whose bbox touches the
  /// point's 0.02° cell, so it's O(1)-ish rather than scanning all ~3,000 areas.
  StatArea? statAreaAt(double lat, double lon) {
    if (!_loaded || _statAreas.isEmpty || !_validCoord(lat, lon)) return null;
    final cx = (lat / _statCell).round();
    final cy = (lon / _statCell).round();
    final cand = _statIndex['${cx}_$cy'];
    if (cand == null) return null;
    for (final i in cand) {
      if (_pointInPoly(lat, lon, _statAreas[i].poly)) return _statAreas[i];
    }
    return null;
  }

  /// All statistical areas in [city] (normalized name match — handles the
  /// "תל אביב -יפו" / "תל אביב יפו" / "תל אביב" spellings). Empty when unloaded or
  /// the city has no areas. Used by Area Intelligence to rank a city's blocks.
  List<StatArea> statAreasInCity(String city) {
    if (!_loaded || _statAreas.isEmpty) return const [];
    final q = _normStatCity(city);
    if (q.isEmpty) return const [];
    return [
      for (final a in _statAreas)
        if (_statCityMatches(a.city, q)) a
    ];
  }

  static String _normStatCity(String s) => s
      .trim()
      .replaceAll(RegExp(r'[\-־]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'\sיפו$'), '')
      .trim();

  static bool _statCityMatches(String areaCity, String normQuery) {
    final a = _normStatCity(areaCity);
    if (a.isEmpty) return false;
    return a == normQuery || a.contains(normQuery) || normQuery.contains(a);
  }

  // ── CBS estimated apartment value per statistical area (₪/m², 2013) ──────────
  final Map<int, int> _areaValue = {}; // YISHUV_STA → ₪/m²
  List<int> _areaValueSorted = const []; // ascending, for percentiles

  Future<void> _loadAreaValue(AssetReader read) async {
    final obj = jsonDecode(await read('$_assetDir/stat_area_value.json'))
        as Map<String, dynamic>;
    obj.forEach((k, v) {
      final id = int.tryParse(k);
      final val = (v as num?)?.toInt();
      if (id != null && val != null && val > 0) _areaValue[id] = val;
    });
    _areaValueSorted = _areaValue.values.toList()..sort();
  }

  /// Estimated ₪/m² for the block [id] (2013 CBS), or null when unknown.
  int? areaValuePerSqm(int id) => _areaValue[id];

  /// Relative price positioning of block [id]: fraction of valued blocks whose
  /// ₪/m² is ≤ this one (0 = cheapest nationally … 1 = priciest). Null if unknown.
  /// The 2013 vintage is stale in ABSOLUTE terms but relative rank is fairly stable.
  double? areaValuePercentile(int id) {
    final v = _areaValue[id];
    if (v == null || _areaValueSorted.isEmpty) return null;
    var lo = 0, hi = _areaValueSorted.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (_areaValueSorted[mid] <= v) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo / _areaValueSorted.length;
  }

  Future<void> _loadFutureInfra(AssetReader read) async {
    final obj = jsonDecode(await read('$_assetDir/future_infra.json'))
        as Map<String, dynamic>;
    for (final s in (obj['stations'] as List<dynamic>? ?? const [])) {
      final p = s as List<dynamic>;
      _futureStations.add([(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
    }
    for (final r in (obj['renewal'] as List<dynamic>? ?? const [])) {
      final p = r as List<dynamic>;
      _renewalPoints.add([(p[0] as num).toDouble(), (p[1] as num).toDouble()]);
    }
  }

  /// Investor upside in [0,1] — proximity to a PLANNED metro/light-rail station
  /// (strong value driver) or an urban-renewal project. 0 when nothing planned is
  /// nearby (or the dataset is absent) — a bonus, so no data = no bonus, never a
  /// penalty. Weighted only on the investment/growth intent.
  double futureValueScore(double lat, double lon) {
    if (!_loaded || !_validCoord(lat, lon)) return 0.0;
    double nearest(List<List<double>> pts) {
      var best = double.infinity;
      for (final p in pts) {
        final d = _haversineKm(lat, lon, p[0], p[1]);
        if (d < best) best = d;
      }
      return best;
    }

    // exp falloff: a future station lifts value out to ~1.5km; renewal is tighter.
    double kernel(double km, double scale) =>
        km.isFinite ? math.exp(-km / scale) : 0.0;
    final station = kernel(nearest(_futureStations), 1.5);
    final renewal = kernel(nearest(_renewalPoints), 0.7);
    return math.max(station, 0.85 * renewal).clamp(0.0, 1.0);
  }

  Future<void> _loadEmployment(AssetReader read) async {
    final obj = jsonDecode(await read('$_assetDir/employment.json'))
        as Map<String, dynamic>;
    _jobCell = (obj['cell'] as num?)?.toDouble() ?? 0.02;
    final cells = obj['cells'] as Map<String, dynamic>;
    for (final e in cells.entries) {
      final v = (e.value as num).toInt();
      _jobGrid[e.key] = v;
      if (v > _maxJobCell) _maxJobCell = v;
    }
  }

  /// Employment access in [0,1] — job-place density (offices + commercial /
  /// industrial) in a ~6 km² window, log-scaled vs the densest cell. A proxy for
  /// "short commute to work" when the seeker hasn't named their workplace. 0 when
  /// the dataset is absent. Weighted on a "near work / employment" intent.
  double employmentAccessScore(double lat, double lon) {
    if (!_loaded || _jobGrid.isEmpty || !_validCoord(lat, lon)) return 0.0;
    final cx = (lat / _jobCell).round();
    final cy = (lon / _jobCell).round();
    var total = 0;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        total += _jobGrid['${cx + dx}_${cy + dy}'] ?? 0;
      }
    }
    if (total <= 0) return 0.0;
    return (math.log(1 + total) / math.log(1 + _maxJobCell * 3)).clamp(0.0, 1.0);
  }

  // Ray-casting point-in-polygon on [lat,lon] rings.
  static bool _pointInPoly(double lat, double lon, List<List<double>> poly) {
    var inside = false;
    for (var i = 0, j = poly.length - 1; i < poly.length; j = i++) {
      final yi = poly[i][0], xi = poly[i][1];
      final yj = poly[j][0], xj = poly[j][1];
      final intersect = ((yi > lat) != (yj > lat)) &&
          (lon < (xj - xi) * (lat - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) + xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  /// Health-facility availability for a city in [0,1] (log-scaled count), or 0.
  double healthAccessScore(String city) {
    if (!_loaded) return 0.0;
    final code = _resolveCode(city);
    final count =
        (code != null ? _health[code] : null) ?? _healthLoose[_looseKey(city)];
    if (count == null || count <= 0) return 0.0;
    return (math.log(1 + count) / math.log(1 + _maxHealth)).clamp(0.0, 1.0);
  }

  /// Distance (km) to the nearest air-quality monitoring station, or null.
  double? nearestAirStationKm(double lat, double lon) {
    if (!_loaded || _airLatLon.isEmpty || !_validCoord(lat, lon)) return null;
    double best = double.infinity;
    for (final s in _airLatLon) {
      final d = _haversineKm(lat, lon, s[0], s[1]);
      if (d < best) best = d;
    }
    return best.isFinite ? best : null;
  }

  // Empirical CDF over a sorted list (fraction ≤ x).
  static double _cdf(List<double> sorted, double x) {
    if (sorted.isEmpty) return 0.5;
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

  /// Nearest locality centroid to a coordinate (linear; used only as a fallback
  /// when a property has no usable city string).
  LocalityRecord? nearestLocality(double lat, double lon) {
    if (!_loaded || !_validCoord(lat, lon)) return null;
    LocalityRecord? best;
    double bestD = double.infinity;
    for (final r in _localities) {
      final d = _haversineKm(lat, lon, r.lat, r.lon);
      if (d < bestD) {
        bestD = d;
        best = r;
      }
    }
    return best;
  }

  /// Number of public-transport stops within the query cell and its 8 neighbours
  /// (≈ a 6 km² window) — a real measure of how transit-served a point is.
  int transitStopsAround(double lat, double lon) {
    if (!_loaded || !_validCoord(lat, lon)) return 0;
    final cx = (lat / _gridCell).round();
    final cy = (lon / _gridCell).round();
    var total = 0;
    for (var dx = -1; dx <= 1; dx++) {
      for (var dy = -1; dy <= 1; dy++) {
        final cell = _grid['${cx + dx}_${cy + dy}'];
        if (cell != null && cell.isNotEmpty) total += cell[0];
      }
    }
    return total;
  }

  /// Transit-density accessibility in [0,1] (log-scaled vs the densest cell).
  double transitDensityScore(double lat, double lon) {
    final n = transitStopsAround(lat, lon);
    if (n <= 0) return 0.0;
    return (math.log(1 + n) / math.log(1 + _maxCellDensity * 3))
        .clamp(0.0, 1.0);
  }

  /// Distance (km) to the nearest rail / light-rail station, or null.
  double? nearestRailKm(double lat, double lon) {
    if (!_loaded || _railLatLon.isEmpty || !_validCoord(lat, lon)) return null;
    double best = double.infinity;
    for (final s in _railLatLon) {
      final d = _haversineKm(lat, lon, s[0], s[1]);
      if (d < best) best = d;
    }
    return best.isFinite ? best : null;
  }

  /// Nearest rail / light-rail station → (name, km), or null.
  ({String name, double km})? nearestRailStation(double lat, double lon) {
    if (!_loaded || _railLatLon.isEmpty || !_validCoord(lat, lon)) return null;
    double best = double.infinity;
    var bestI = -1;
    for (var i = 0; i < _railLatLon.length; i++) {
      final s = _railLatLon[i];
      final d = _haversineKm(lat, lon, s[0], s[1]);
      if (d < best) {
        best = d;
        bestI = i;
      }
    }
    if (bestI < 0 || !best.isFinite) return null;
    return (name: _railName[bestI], km: best);
  }

  // ── geo helpers ──────────────────────────────────────────────────────────────
  static bool _validCoord(double lat, double lon) =>
      lat.isFinite && lon.isFinite && lat.abs() > 0.1 && lon.abs() > 0.1;

  static double _haversineKm(double la1, double lo1, double la2, double lo2) {
    const r = 6371.0088;
    final dLa = _rad(la2 - la1);
    final dLo = _rad(lo2 - lo1);
    final a = math.sin(dLa / 2) * math.sin(dLa / 2) +
        math.cos(_rad(la1)) *
            math.cos(_rad(la2)) *
            math.sin(dLo / 2) *
            math.sin(dLo / 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  static double _rad(double d) => d * math.pi / 180.0;

  // ── test/util hook ───────────────────────────────────────────────────────────
  /// Reset for tests.
  void resetForTest() {
    _loaded = false;
    _localities.clear();
    _byCode.clear();
    _byName.clear();
    _byLoose.clear();
    _grid.clear();
    _railLatLon.clear();
    _railName.clear();
    _market.clear();
    _crime.clear();
    _crimeLoose.clear();
    _crimeRate.clear();
    _rateSorted = const [];
    _demo.clear();
    _demoLoose.clear();
    _schoolGrid.clear();
    _health.clear();
    _healthLoose.clear();
    _airLatLon.clear();
    _retailGrid.clear();
    _noiseGrid.clear();
    _statAreas.clear();
    _statIndex.clear();
    _areaValue.clear();
    _areaValueSorted = const [];
    _futureStations.clear();
    _renewalPoints.clear();
    _jobGrid.clear();
    _maxJobCell = 1;
    _maxCellDensity = 1;
    _maxSchoolCell = 1;
    _maxHealth = 1;
    _maxRetailCell = 1;
    version = 0;
  }
}
