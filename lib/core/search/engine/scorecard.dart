// ═════════════════════════════════════════════════════════════════════════════
// Scorecard — the FROZEN data contract between the ranking engine, the LLM
// explainer, and the transparency UI.
//
// The recommendation engine already computes per-property reasoning
// (explanation, dimension breakdown, confidence) and the app holds real market
// statistics (gov ₪/m² medians, percentiles, fair-rent residual, transit
// distance, safety percentile). Today recommendAsScored() discards all of it and
// keeps only "NN% התאמה" + a few chips.
//
// A Scorecard carries the FULL, honest, data-grounded reasoning for ONE property
// so that:
//   • the deterministic engine CHOOSES (fills fitPct/tier/dimensions/stats),
//   • the LLM EXPLAINS over the real numbers (fills llmReason — never invents),
//   • the UI SHOWS the breakdown (renders dimensions + stats + reasons).
//
// This file defines ONLY the shape (+ JSON). Population lives in the engine
// (A2/A5), persona reasons in A1/A2, and llmReason in the backend explainer (A3).
// Keep it dependency-free so every layer can import it.
// ═════════════════════════════════════════════════════════════════════════════

/// One weighted dimension of the match (e.g. value-for-money, location, space),
/// with both the model's numbers and the raw statistic behind it.
class ScorecardDimension {
  const ScorecardDimension({
    required this.key,
    required this.label,
    required this.weightPct,
    required this.contributionPct,
    this.stat,
    this.positive = true,
  });

  /// Stable engine key, e.g. 'value', 'location', 'space', 'transit', 'safety'.
  final String key;

  /// Human Hebrew label, e.g. "תמורה למחיר".
  final String label;

  /// How much this dimension counts in the decision, 0..1 (from the preference
  /// model / persona weighting).
  final double weightPct;

  /// This property's score on this dimension, 0..1 (from dimensionBreakdown).
  final double contributionPct;

  /// The raw statistic behind the score, as a ready-to-show Hebrew string —
  /// e.g. "₪82/מ״ר · 14% מתחת לחציון האזור", "כ-1.4 ק״מ מהרכבת", "אחוזון בטיחות 78".
  /// Null when no concrete number is available (degrade gracefully). Filled by A5.
  final String? stat;

  /// Whether this dimension helps (true) or is a concern (false).
  final bool positive;

  Map<String, dynamic> toJson() => {
        'key': key,
        'label': label,
        'weightPct': weightPct,
        'contributionPct': contributionPct,
        if (stat != null) 'stat': stat,
        'positive': positive,
      };

  factory ScorecardDimension.fromJson(Map<String, dynamic> j) =>
      ScorecardDimension(
        key: j['key']?.toString() ?? '',
        label: j['label']?.toString() ?? '',
        weightPct: (j['weightPct'] as num?)?.toDouble() ?? 0,
        contributionPct: (j['contributionPct'] as num?)?.toDouble() ?? 0,
        stat: j['stat']?.toString(),
        positive: j['positive'] as bool? ?? true,
      );
}

/// The full data-grounded reasoning for one recommended property.
class Scorecard {
  const Scorecard({
    required this.fitPct,
    required this.tier,
    required this.confidence,
    required this.explanation,
    this.highlights = const [],
    this.dimensions = const [],
    this.personaReasons = const [],
    this.concerns = const [],
    this.llmReason,
  });

  /// Overall fit 0..100 (the engine's chosen score).
  final int fitPct;

  /// Tier label, e.g. "התאמה מצוינת" (reuse MatchTier thresholds).
  final String tier;

  /// 0..1 — how sure the engine is about this ranking (intent coverage + data
  /// completeness). Surfacing this is part of the honesty requirement.
  final double confidence;

  /// The engine's one-line Hebrew "why".
  final String explanation;

  /// Concrete chips, e.g. "מחיר אטרקטיבי מתחת לשוק".
  final List<String> highlights;

  /// Per-dimension breakdown with raw statistics — the core of the transparency.
  final List<ScorecardDimension> dimensions;

  /// Why this fits the user's PERSONA specifically (tag/deal-breaker matches),
  /// e.g. "מתאים לבעלי חיות מחמד — דרישת חובה שלך". Filled from the persona.
  final List<String> personaReasons;

  /// Honest downsides, e.g. "מעט מעל התקציב שלך", "רחוק מתחבורה ציבורית".
  final List<String> concerns;

  /// The LLM's natural-language, number-grounded reason for THIS property.
  /// Filled by the backend explainer (A3) over the data above; never invented.
  /// Null until the explain step runs.
  final String? llmReason;

  Scorecard withLlmReason(String? reason) => Scorecard(
        fitPct: fitPct,
        tier: tier,
        confidence: confidence,
        explanation: explanation,
        highlights: highlights,
        dimensions: dimensions,
        personaReasons: personaReasons,
        concerns: concerns,
        llmReason: reason,
      );

  Map<String, dynamic> toJson() => {
        'fitPct': fitPct,
        'tier': tier,
        'confidence': confidence,
        'explanation': explanation,
        'highlights': highlights,
        'dimensions': dimensions.map((d) => d.toJson()).toList(),
        'personaReasons': personaReasons,
        'concerns': concerns,
        if (llmReason != null) 'llmReason': llmReason,
      };

  factory Scorecard.fromJson(Map<String, dynamic> j) => Scorecard(
        fitPct: (j['fitPct'] as num?)?.toInt() ?? 0,
        tier: j['tier']?.toString() ?? '',
        confidence: (j['confidence'] as num?)?.toDouble() ?? 0,
        explanation: j['explanation']?.toString() ?? '',
        highlights: (j['highlights'] as List?)?.map((e) => e.toString()).toList() ??
            const [],
        dimensions: (j['dimensions'] as List?)
                ?.whereType<Map>()
                .map((m) =>
                    ScorecardDimension.fromJson(Map<String, dynamic>.from(m)))
                .toList() ??
            const [],
        personaReasons:
            (j['personaReasons'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        concerns:
            (j['concerns'] as List?)?.map((e) => e.toString()).toList() ??
                const [],
        llmReason: j['llmReason']?.toString(),
      );
}
