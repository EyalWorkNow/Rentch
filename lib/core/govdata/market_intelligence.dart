// ════════════════════════════════════════════════════════════════════════════
// PART D / 5 — MARKET & SOCIOECONOMIC INTELLIGENCE
// ════════════════════════════════════════════════════════════════════════════
//
// Anchors the engine's value/affordability reasoning to real per-locality ₪/m²
// market priors (from market_seed.json, overlayable by nadlan) and CBS
// socioeconomic clusters.
//
// The core idea is empirical-Bayes shrinkage: a live OLS hedonic model fit on the
// current candidate set is unbiased but high-variance on small samples, while the
// gov per-locality ₪/m² prior is biased-but-stable. We combine the two in log
// space, precision-weighting the live estimate by how much data backs it. The
// result is a robust "fair rent" that doesn't swing wildly when only a handful of
// listings are loaded — exactly what an on-device, session-scoped market needs.
// ════════════════════════════════════════════════════════════════════════════

import 'dart:math' as math;

import 'package:dating_app/core/govdata/gov_data.dart';

class MarketIntelligence {
  const MarketIntelligence._();

  static GovData get _gov => GovData.instance;

  /// Gov per-locality "fair monthly rent" prior for a unit of [sizeM2] in
  /// [city], or null when we have no anchor for that locality.
  static double? govExpectedRent(String city, int sizeM2) {
    if (sizeM2 <= 0) return null;
    final perSqm = _gov.loaded ? _gov.rentPerSqm(city) : null;
    if (perSqm == null || perSqm <= 0) return null;
    return perSqm * sizeM2;
  }

  /// Precision (inverse-variance) weight for the LIVE hedonic estimate, as a
  /// function of the candidate-set size. Small samples ⇒ trust the gov prior;
  /// large samples ⇒ trust the live fit. Saturates so a big session can't make
  /// the live estimate infinitely confident.
  static double liveWeight(int marketSize) {
    if (marketSize <= 4) return 0.15;
    return (marketSize / 45.0).clamp(0.15, 1.6);
  }

  /// Empirical-Bayes blended fair price (₪) in linear space, combining a live
  /// hedonic prediction with the gov prior. Either input may be null.
  ///
  /// [liveFair]   fair price from the live OLS hedonic model (null if unfit).
  /// [marketSize] number of listings the live model saw.
  static double? blendedFairRent({
    required double? liveFair,
    required String city,
    required int sizeM2,
    required int marketSize,
  }) {
    final gov = govExpectedRent(city, sizeM2);
    final hasLive = liveFair != null && liveFair > 0;
    final hasGov = gov != null && gov > 0;

    if (!hasLive && !hasGov) return null;
    if (!hasGov) return liveFair;
    if (!hasLive) return gov;

    // precision-weighted average in log space (geometric shrinkage)
    final wLive = liveWeight(marketSize);
    const wGov = 1.0;
    final logBlend =
        (wLive * math.log(liveFair) + wGov * math.log(gov)) / (wLive + wGov);
    return math.exp(logBlend);
  }

  /// Value residual in [-1,1] from the gov-anchored fair rent: positive ⇒ the
  /// listing is priced BELOW its anchored fair value (a deal). [scale] controls
  /// how many log-units map to the extremes (~0.3 ≈ ±35%).
  static double govValueResidual({
    required int price,
    required double? liveFair,
    required String city,
    required int sizeM2,
    required int marketSize,
    double scale = 0.32,
  }) {
    if (price <= 0) return 0.0;
    final fair = blendedFairRent(
      liveFair: liveFair,
      city: city,
      sizeM2: sizeM2,
      marketSize: marketSize,
    );
    if (fair == null || fair <= 0) return 0.0;
    final logDiff = math.log(fair) - math.log(price.toDouble());
    return (logDiff / scale).clamp(-1.0, 1.0);
  }

  /// Affordability of [price] against the locality's typical rent for its size,
  /// in [0,1] (1 = comfortably below local norm, 0.5 = at norm, →0 above).
  static double affordabilityVsLocal(int price, String city, int sizeM2) {
    final gov = govExpectedRent(city, sizeM2);
    if (gov == null || gov <= 0 || price <= 0) return 0.5;
    final ratio = price / gov;
    // 0.7×norm → ~0.85, norm → 0.5, 1.4×norm → ~0.15
    return (1.0 / (1.0 + math.exp(3.0 * (ratio - 1.0)))).clamp(0.0, 1.0);
  }

  /// CBS socioeconomic score for a city in [0,1] (cluster 1→0 … 10→1), or a
  /// neutral 0.5 when unknown.
  static double socioeconomicScore(String city) {
    final ses = _gov.loaded ? _gov.socioeconomic(city) : 0;
    if (ses < 1 || ses > 10) return 0.5;
    return (ses - 1) / 9.0;
  }

  /// Whether we have a real market anchor for [city] (for confidence/telemetry).
  static bool hasAnchor(String city, int sizeM2) =>
      govExpectedRent(city, sizeM2) != null;
}
