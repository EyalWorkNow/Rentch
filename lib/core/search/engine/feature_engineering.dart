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

import 'dart:math' as math;

import 'package:dating_app/core/govdata/geo_intelligence.dart';
import 'package:dating_app/core/govdata/gov_data.dart';
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

  static double? _nearest(double lat, double lon, List<_GeoPlace> places) {
    if (!_hasCoords(lat, lon)) return null;
    double? best;
    for (final p in places) {
      final d = haversineKm(lat, lon, p.lat, p.lon);
      if (best == null || d < best) best = d;
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

  static const List<_GeoPlace> _universities = [
    _GeoPlace('אוניברסיטת ת"א', 32.1133, 34.8044),
    _GeoPlace('הטכניון', 32.7767, 35.0233),
    _GeoPlace('האונ׳ העברית גבעת רם', 31.7770, 35.1970),
    _GeoPlace('בן גוריון', 31.2620, 34.8010),
    _GeoPlace('בר אילן', 32.0690, 34.8430),
    _GeoPlace('אונ׳ חיפה', 32.7610, 35.0200),
    _GeoPlace('רייכמן הרצליה', 32.1740, 34.8390),
  ];

  // Coarse coastline reference points (Mediterranean).
  static const List<_GeoPlace> _coast = [
    _GeoPlace('ת"א חוף', 32.0800, 34.7660),
    _GeoPlace('הרצליה חוף', 32.1640, 34.7920),
    _GeoPlace('נתניה חוף', 32.3300, 34.8500),
    _GeoPlace('חיפה חוף', 32.8200, 34.9700),
    _GeoPlace('אשדוד חוף', 31.7900, 34.6300),
    _GeoPlace('בת ים חוף', 32.0150, 34.7350),
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
    f['safety'] = gov.safetyScore(p.city) ?? 0.5; // 1 = safest (per-capita crime)
    f['school_access'] = gov.schoolDensityScore(p.lat, p.lon);
    f['health_access'] = gov.healthAccessScore(p.city);
    final demo = gov.demographics(p.city);
    f['demo_young'] = demo?['youngShare'] ?? 0.5; // working-age share (20-64)
    f['demo_child'] = demo?['childShare'] ?? 0.5; // 0-19 share (family areas)
    f['demo_senior'] = demo?['seniorShare'] ?? 0.5;
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
