// ═════════════════════════════════════════════════════════════════════════════
// ScorecardStats — raw, sourced statistics behind each Scorecard dimension.
//
// FROZEN SIGNATURE (do not change the public method shape — A2 imports it):
//   ScorecardStats.statLabels(property, market) -> { dimKey: "ready Hebrew label" }
//
// Returns, per scoring dimension key (the EXACT keys in `kScoringDimensions`),
// a ready-to-display Hebrew string carrying the ACTUAL number — e.g.
//   'value'        : "₪82/מ״ר · 14% מתחת לחציון האזור (₪96)"
//   'transit'      : "כ-1.4 ק״מ מהרכבת"
//   'safety'       : "אחוזון בטיחות 78 (גבוה = בטוח יותר)"
//   'neighborhood' : "אשכול חברתי-כלכלי 8/10"
//   'size'         : "92 מ״ר · אחוזון 64 באזור"
// so the transparency UI and the LLM explainer reason over real figures.
//
// CONTRACT RULES (honesty layer):
//   • Only return a label when the underlying datum truly exists; OMIT the key
//     otherwise (never fabricate a number). Missing key == "no figure available",
//     and the UI/LLM must degrade gracefully.
//   • Every number traces to a real source: gov ₪/m² medians (GovData.rentPerSqm),
//     MarketContext percentiles / city medians, the hedonic / gov-anchored
//     fair-rent residual (MarketIntelligence), GovData crime safety percentile,
//     GovData socioeconomic cluster, and rail distance (GovData / IsraelGeoIndex).
// ═════════════════════════════════════════════════════════════════════════════

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/govdata/market_intelligence.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/data/models/rental_models.dart';

class ScorecardStats {
  const ScorecardStats._();

  /// dimKey -> ready Hebrew label with the real figure. Omit keys with no datum.
  static Map<String, String> statLabels(
    RentalProperty property,
    MarketContext market,
  ) {
    final out = <String, String>{};
    final gov = GovData.instance;

    _addValue(out, property, market, gov);
    _addTransit(out, property, gov);
    _addSafety(out, property, gov);
    _addNeighborhood(out, property, gov);
    _addSize(out, property, market);
    _addSchools(out, property, gov);
    _addFamily(out, property, gov);
    _addHealth(out, property, gov);

    return out;
  }

  // ── value: ₪/m² of the unit vs the locality's gov ₪/m² median, plus the
  //    gov-anchored fair-rent residual when a real anchor exists. ────────────────
  static void _addValue(
    Map<String, String> out,
    RentalProperty p,
    MarketContext market,
    GovData gov,
  ) {
    final parts = <String>[];

    final pps = p.pricePerSquareMeter; // ₪/m² of THIS unit (real, derived)
    final govMedian = gov.loaded ? gov.rentPerSqm(p.city) : null; // gov ₪/m²

    if (pps != null && pps > 0) {
      parts.add('₪$pps/מ״ר');
      // Compare to the gov per-locality ₪/m² median when we have that anchor.
      if (govMedian != null && govMedian > 0) {
        final pct = ((pps - govMedian) / govMedian * 100).round();
        final med = govMedian.round();
        if (pct.abs() >= 1) {
          final dir = pct < 0 ? 'מתחת' : 'מעל';
          parts.add('${pct.abs()}% $dir לחציון האזור (₪$med)');
        } else {
          parts.add('כחציון האזור (₪$med)');
        }
      }
    }

    // Gov-anchored fair-rent residual: only when a genuine locality anchor exists.
    if (MarketIntelligence.hasAnchor(p.city, p.sizeM2) && p.price > 0) {
      final fair = MarketIntelligence.blendedFairRent(
        liveFair: null, // pure gov anchor for the transparency label (stable)
        city: p.city,
        sizeM2: p.sizeM2,
        marketSize: market.size,
      );
      if (fair != null && fair > 0) {
        final residualPct =
            ((fair - p.price) / p.price * 100).round(); // + ⇒ underpriced
        final fairRounded = fair.round();
        if (residualPct.abs() >= 1) {
          final dir = residualPct > 0 ? 'מתחת' : 'מעל';
          parts.add('הוגן: ₪$fairRounded · ${residualPct.abs()}% $dir');
        } else {
          parts.add('הוגן: ₪$fairRounded · במחיר ההוגן');
        }
      }
    }

    if (parts.isNotEmpty) out['value'] = parts.join(' · ');
  }

  // ── transit: real distance to nearest rail station (gov rail index first,
  //    then the IsraelGeoIndex station fallback). Omit if no coords / no match. ──
  static void _addTransit(
    Map<String, String> out,
    RentalProperty p,
    GovData gov,
  ) {
    double? railKm = gov.loaded ? gov.nearestRailKm(p.lat, p.lon) : null;
    railKm ??= IsraelGeoIndex.nearestStationKm(p.lat, p.lon);
    if (railKm == null || !railKm.isFinite) return;

    final label = railKm < 10
        ? railKm.toStringAsFixed(1)
        : railKm.round().toString();
    out['transit'] = 'כ-$label ק״מ מהרכבת';
  }

  // ── safety: gov crime safety percentile (1 = safest). Express as a 0–100
  //    percentile, higher = safer. Omit when crime/pop data is missing. ──────────
  static void _addSafety(
    Map<String, String> out,
    RentalProperty p,
    GovData gov,
  ) {
    if (!gov.loaded) return;
    final safety = gov.safetyScore(p.city); // [0,1], 1 = safest, null if no data
    if (safety == null) return;
    // `safety` is 1 − percentile(crime-rate): a high-density city such as
    // Tel Aviv has high reported crime per capita and so lands near the bottom
    // of this distribution. The OLD label rendered that as "safety 1", which
    // reads as "totally unsafe" and is misleading for a desirable city. Report
    // the honest underlying figure instead — the reported-crime percentile —
    // and frame it neutrally so a dense, in-demand locality isn't alarmed.
    final crimePercentile = ((1.0 - safety) * 100).round(); // 100 = most crime
    out['safety'] =
        'פשיעה מדווחת לנפש: אחוזון $crimePercentile (נמוך = פחות פשיעה)';
  }

  // ── neighborhood: CBS socioeconomic cluster 1–10 for the locality. ───────────
  static void _addNeighborhood(
    Map<String, String> out,
    RentalProperty p,
    GovData gov,
  ) {
    if (!gov.loaded) return;
    final cluster = gov.socioeconomic(p.city); // 1..10, 0 = unknown
    if (cluster < 1 || cluster > 10) return;
    out['neighborhood'] = 'אשכול חברתי-כלכלי $cluster/10';
  }

  // ── size: real m² + the property's size percentile within the live market. ───
  static void _addSize(
    Map<String, String> out,
    RentalProperty p,
    MarketContext market,
  ) {
    if (p.sizeM2 <= 0) return;
    final parts = <String>['${p.sizeM2} מ״ר'];
    // Size percentile is only meaningful with a non-trivial market sample.
    if (market.size >= 5) {
      final pct = (market.sizePercentile(p.sizeM2) * 100).round();
      parts.add('אחוזון $pct באזור');
    }
    out['size'] = parts.join(' · ');
  }

  // ── schools: CBS education-institution density around the property's coords,
  //    [0,1] (log-scaled count of schools+kindergartens). Omit when no coords /
  //    no schools indexed near the point (score 0). ─────────────────────────────
  static void _addSchools(
    Map<String, String> out,
    RentalProperty p,
    GovData gov,
  ) {
    if (!gov.loaded) return;
    final density = gov.schoolDensityScore(p.lat, p.lon); // [0,1], 0 = none/no data
    if (density <= 0) return;
    final pct = (density * 100).round();
    final qualifier = density >= 0.66
        ? 'גבוהה'
        : density >= 0.33
            ? 'בינונית'
            : 'נמוכה';
    out['schools'] = 'צפיפות מוסדות חינוך $qualifier (אחוזון $pct)';
  }

  // ── family: CBS share of children (0-19) in the locality → family-friendliness.
  //    Append a "young area" note when the working-age share is high. Omit when
  //    demographics are unavailable. ────────────────────────────────────────────
  static void _addFamily(
    Map<String, String> out,
    RentalProperty p,
    GovData gov,
  ) {
    if (!gov.loaded) return;
    final demo = gov.demographics(p.city);
    if (demo == null) return;
    final childShare = demo['childShare'];
    if (childShare == null || childShare <= 0) return;
    final childPct = (childShare * 100).round();
    var label = 'אזור משפחתי — $childPct% ילדים';
    final youngShare = demo['youngShare'] ?? 0.0;
    if (youngShare >= 0.6) label = '$label · אזור צעיר';
    out['family'] = label;
  }

  // ── health: CBS health-facility availability for the locality, [0,1]
  //    (log-scaled clinic/facility count). Omit when none indexed (score 0). ─────
  static void _addHealth(
    Map<String, String> out,
    RentalProperty p,
    GovData gov,
  ) {
    if (!gov.loaded) return;
    final access = gov.healthAccessScore(p.city); // [0,1], 0 = none/no data
    if (access <= 0) return;
    final qualifier = access >= 0.66
        ? 'גבוהה'
        : access >= 0.33
            ? 'טובה'
            : 'בסיסית';
    final pct = (access * 100).round();
    out['health'] = 'נגישות שירותי בריאות $qualifier (אחוזון $pct)';
  }
}
