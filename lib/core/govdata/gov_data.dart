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
    }
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

  // ── geo helpers ──────────────────────────────────────────────────────────────
  static bool _validCoord(double lat, double lon) =>
      lat.abs() > 0.1 && lon.abs() > 0.1;

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
    _grid.clear();
    _railLatLon.clear();
    _railName.clear();
    _market.clear();
    _maxCellDensity = 1;
    version = 0;
  }
}
