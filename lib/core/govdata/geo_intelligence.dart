// ════════════════════════════════════════════════════════════════════════════
// PART C / 5 — GEOSPATIAL INTELLIGENCE
// ════════════════════════════════════════════════════════════════════════════
//
// Turns the real gov-data geo layer (33,937 transit stops → density grid + 244
// rail stations + locality centroids + CBS socioeconomic clusters) into the
// geographic signals the feature engineer consumes. Every function degrades
// gracefully to the built-in IsraelGeoIndex heuristics when GovData isn't loaded
// (e.g. asset missing, or a unit test that didn't init it).
//
// Math:
//   • Transit accessibility = blend of (a) stop *density* around the point
//     (log-scaled count in a ~6 km² window) and (b) a Gaussian proximity kernel
//     to the nearest rail station — density captures "well-served", rail captures
//     "fast inter-city access". Multi-modal, not a single nearest-stop hack.
//   • Centrality = convex combination of socioeconomic cluster, transit density,
//     and CBD proximity, with a city prior as the floor.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:dating_app/core/govdata/gov_data.dart';

// City desirability prior — the floor for centrality when richer signals are
// missing. Kept here (not in the data layer) because it's a modelling choice.
const Map<String, double> _cityCentralityPrior = {
  'תל אביב': 0.97,
  'תל אביב-יפו': 0.97,
  'רמת גן': 0.9,
  'גבעתיים': 0.9,
  'הרצליה': 0.86,
  'רמת השרון': 0.9,
  'גבעת שמואל': 0.8,
  'קריית אונו': 0.82,
  'בני ברק': 0.7,
  'ירושלים': 0.8,
  'חיפה': 0.74,
  'ראשון לציון': 0.7,
  'פתח תקווה': 0.68,
  'רעננה': 0.78,
  'כפר סבא': 0.7,
  'נתניה': 0.62,
  'באר שבע': 0.5,
  'אשדוד': 0.55,
  'אשקלון': 0.5,
};

class TransitAccess {
  const TransitAccess({
    required this.densityScore,
    required this.railKm,
    required this.railAccess,
    required this.combined,
  });

  final double densityScore; // 0..1 stop density around the point
  final double? railKm; // km to nearest rail/light-rail station
  final double railAccess; // 0..1 Gaussian proximity to rail
  final double combined; // 0..1 blended accessibility
}

class GeoIntelligence {
  const GeoIntelligence._();

  static GovData get _gov => GovData.instance;

  static bool _validCoord(double lat, double lon) =>
      lat.abs() > 0.1 && lon.abs() > 0.1;

  // ── transit ──────────────────────────────────────────────────────────────────
  /// Multi-modal transit accessibility for a point.
  static TransitAccess transit(double lat, double lon) {
    if (_gov.loaded && _validCoord(lat, lon)) {
      final density = _gov.transitDensityScore(lat, lon);
      final railKm = _gov.nearestRailKm(lat, lon);
      final railAccess = _gaussianKernel(railKm, scaleKm: 1.2);
      // density dominates "served-ness"; rail adds inter-city reach
      final combined = (0.6 * density + 0.4 * railAccess).clamp(0.0, 1.0);
      return TransitAccess(
        densityScore: density,
        railKm: railKm,
        railAccess: railAccess,
        combined: combined,
      );
    }
    // fallback: rail kernel only (no density grid)
    final railKm = _IsraelFallback.nearestStationKm(lat, lon);
    final railAccess = _expKernel(railKm, scaleKm: 1.5);
    return TransitAccess(
      densityScore: railAccess * 0.6,
      railKm: railKm,
      railAccess: railAccess,
      combined: railAccess,
    );
  }

  // ── socioeconomic ────────────────────────────────────────────────────────────
  /// CBS socioeconomic cluster mapped to [0,1] (cluster 1→0.0 … 10→1.0), or a
  /// neutral 0.5 when unknown.
  static double socioeconomicScore(String city) {
    final ses = _gov.loaded ? _gov.socioeconomic(city) : 0;
    if (ses < 1 || ses > 10) return 0.5;
    return (ses - 1) / 9.0;
  }

  /// Raw cluster 1..10 (0 = unknown) — exposed for explanations.
  static int socioeconomicCluster(String city) =>
      _gov.loaded ? _gov.socioeconomic(city) : 0;

  // ── centrality ───────────────────────────────────────────────────────────────
  /// Composite centrality/desirability in [0,1].
  static double centrality(double lat, double lon, String city) {
    final prior = _cityPrior(city);

    if (_gov.loaded) {
      final ses = _gov.socioeconomic(city);
      final sesScore = (ses >= 1 && ses <= 10) ? (ses - 1) / 9.0 : null;
      final density = _validCoord(lat, lon)
          ? _gov.transitDensityScore(lat, lon)
          : null;

      // weighted blend of whatever signals we actually have
      double num = 0, den = 0;
      void add(double? v, double w) {
        if (v != null) {
          num += v * w;
          den += w;
        }
      }

      add(sesScore, 0.45);
      add(density, 0.35);
      add(prior, 0.30); // prior always present (floor)

      final blended = den > 0 ? num / den : prior;
      // never let it fall below half the city prior (stability)
      return math.max(blended, prior * 0.5).clamp(0.0, 1.0);
    }

    return prior;
  }

  static double _cityPrior(String city) {
    final key = normalizeLocalityName(city);
    final direct = _cityCentralityPrior[key];
    if (direct != null) return direct;
    final base = key.split('-').first.trim();
    return _cityCentralityPrior[base] ?? 0.45;
  }

  // ── kernels ──────────────────────────────────────────────────────────────────
  /// Gaussian proximity: 1 at 0 km, ~0.6 at scaleKm, smooth tail.
  static double _gaussianKernel(double? km, {double scaleKm = 1.2}) {
    if (km == null) return 0.0;
    return math.exp(-(km * km) / (2 * scaleKm * scaleKm));
  }

  /// Exponential proximity: 1 at 0 km, ~0.37 at scaleKm.
  static double _expKernel(double? km, {double scaleKm = 1.5}) {
    if (km == null) return 0.0;
    return math.exp(-km / scaleKm);
  }
}

// Minimal built-in rail fallback (subset of Israel Railways) for when the gov
// asset isn't available. Mirrors the historical hard-coded list.
class _IsraelFallback {
  static const List<List<double>> _stations = [
    [32.0833, 34.7991], [32.0734, 34.7920], [32.0540, 34.7940],
    [32.1140, 34.8040], [32.1660, 34.8340], [32.3180, 34.8570],
    [31.9620, 34.8060], [31.9170, 34.7970], [31.9010, 35.0070],
    [31.7870, 35.2030], [31.7700, 34.6610], [31.2430, 34.7980],
    [32.7940, 34.9570], [32.8310, 34.9890],
  ];

  static double? nearestStationKm(double lat, double lon) {
    if (lat.abs() < 0.1 || lon.abs() < 0.1) return null;
    double best = double.infinity;
    for (final s in _stations) {
      final d = _haversineKm(lat, lon, s[0], s[1]);
      if (d < best) best = d;
    }
    return best.isFinite ? best : null;
  }

  static double _haversineKm(double la1, double lo1, double la2, double lo2) {
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
}
