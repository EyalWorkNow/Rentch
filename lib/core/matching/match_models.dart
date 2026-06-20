/// Domain models for the two-sided rental matching engine.
///
/// The engine turns raw signals from both sides of a potential rental — the
/// tenant's preferences and the landlord's offer/requirements — into a single,
/// explainable [MatchOutcome]: a 0–100 score, a human tier, the concrete
/// reasons behind it, and any hard "deal-breaker" conflicts that should sink or
/// hide the match.
library;

/// Coarse, user-facing quality band for a match.
enum MatchTier { perfect, excellent, good, fair, weak }

extension MatchTierX on MatchTier {
  /// Hebrew label shown on cards / detail.
  String get label => switch (this) {
        MatchTier.perfect => 'התאמה מושלמת',
        MatchTier.excellent => 'התאמה מעולה',
        MatchTier.good => 'התאמה טובה',
        MatchTier.fair => 'התאמה חלקית',
        MatchTier.weak => 'התאמה נמוכה',
      };

  /// Lowest score (inclusive) that still qualifies for this tier.
  static MatchTier fromScore(int score) {
    if (score >= 90) return MatchTier.perfect;
    if (score >= 75) return MatchTier.excellent;
    if (score >= 55) return MatchTier.good;
    if (score >= 35) return MatchTier.fair;
    return MatchTier.weak;
  }
}

/// The category a [MatchReason] belongs to (drives its icon/colour in the UI).
enum MatchReasonKind {
  budget,
  location,
  rooms,
  size,
  timing,
  amenity,
  lifestyle,
  quality,
  mutualInterest,
  dealBreaker,
}

/// One explainable signal behind a match — positive ("fits your budget") or a
/// concern ("above your budget"). Kept tiny and value-typed so the engine stays
/// pure and easily testable.
class MatchReason {
  const MatchReason({
    required this.kind,
    required this.label,
    this.positive = true,
    this.weight = 1.0,
  });

  final MatchReasonKind kind;
  final String label;
  final bool positive;

  /// Relative importance, used only to order reasons for display.
  final double weight;

  @override
  String toString() => '${positive ? '✓' : '✗'} $label';
}

/// The full result of evaluating a tenant ⇄ property pairing.
class MatchOutcome {
  const MatchOutcome({
    required this.score,
    required this.tier,
    required this.propertyFitScore,
    required this.tenantFitScore,
    required this.reasons,
    required this.dealBreakerConflicts,
    required this.excluded,
  });

  /// Final mutual score, 0–100.
  final int score;
  final MatchTier tier;

  /// How well the property fits what the tenant wants (tenant → property).
  final int propertyFitScore;

  /// How well the tenant fits the landlord's stated requirements
  /// (landlord → tenant). 0–100; -1 when the landlord profile is unknown.
  final int tenantFitScore;

  /// Ordered, de-duplicated reasons (positives first) for display.
  final List<MatchReason> reasons;

  /// Unmet non-negotiables from either side, as human strings.
  final List<String> dealBreakerConflicts;

  /// True when a hard gate (an unmet deal-breaker) means the pairing should be
  /// suppressed / pushed to the bottom rather than merely scored low.
  final bool excluded;

  bool get hasTwoSidedSignal => tenantFitScore >= 0;

  List<MatchReason> get positives =>
      reasons.where((r) => r.positive).toList();
  List<MatchReason> get concerns =>
      reasons.where((r) => !r.positive).toList();

  /// The single strongest positive reason, for a compact badge.
  MatchReason? get headlineReason {
    final pos = positives;
    if (pos.isEmpty) return null;
    pos.sort((a, b) => b.weight.compareTo(a.weight));
    return pos.first;
  }
}
