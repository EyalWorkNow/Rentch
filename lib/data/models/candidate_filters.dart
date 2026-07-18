/// Filters the landlord applies to their candidates deck (מועמדים).
///
/// Design notes (important — read before extending):
/// The candidates deck is a `List<RentalProperty>` (each entry is an owned
/// property a tenant liked). On-device, the ONLY genuinely per-candidate data
/// that varies and is reliably populated today is:
///   * the honest fit score (`DatingProvider.leadFitScore`), and
///   * the liked property's own fields (price, availability date).
/// The richer tenant attributes (children / pets / car / income / occupation /
/// household / wfh / verification) are NOT available per liker on-device: the
/// deck card renders the current user's own [TenantProfile] as a stand-in, and
/// the cross-user `PropertyLike` row carries no such fields (its optional
/// budget/move-in snapshots are never written by the client today).
///
/// So this model deliberately declares the FULL field set (mirroring the
/// `SearchFilters` shape and keeping the matcher future-proof), while
/// [CandidateAttributes] carries whatever real data the caller could source.
/// The matcher's rule is uniform and honest: **an unknown (null) attribute is
/// never excluded** — we do not hide a candidate on a signal we cannot measure.
/// The UI only surfaces controls whose data is actually populated, so no filter
/// silently does nothing.
class CandidateFilters {
  const CandidateFilters({
    this.budgetMin,
    this.budgetMax,
    this.moveInWindow,
    this.minFitScore,
    this.numChildrenMax,
    this.hasPets,
    this.hasCar,
    this.household = const <String>{},
    this.occupation = const <String>{},
    this.incomeMin,
    this.wfh,
    this.verifiedOnly = false,
  });

  /// Candidate's declared budget floor / ceiling (₪ per month). null = inactive.
  final double? budgetMin;
  final double? budgetMax;

  /// Availability bucket the liked property must fall within. null = inactive.
  /// One of [moveInWindowTokens]. Matched against days-until-available.
  final String? moveInWindow;

  /// Minimum honest fit score in [0, 100]. null = inactive.
  final double? minFitScore;

  /// Household size / attribute constraints (future-proof; unpopulated today).
  final int? numChildrenMax;
  final bool? hasPets;
  final bool? hasCar;
  final Set<String> household;
  final Set<String> occupation;
  final double? incomeMin;
  final bool? wfh;
  final bool verifiedOnly;

  /// Canonical move-in / availability buckets and their inclusive day ceilings.
  static const Map<String, int> moveInWindowMaxDays = <String, int>{
    'immediate': 0,
    'month': 30,
    '1-3': 90,
    '3-6': 180,
  };

  static const List<String> moveInWindowTokens = <String>[
    'immediate',
    'month',
    '1-3',
    '3-6',
  ];

  /// Hebrew label for a move-in bucket token (RTL UI).
  static String moveInWindowLabel(String token) {
    switch (token) {
      case 'immediate':
        return 'פנוי מיידית';
      case 'month':
        return 'תוך חודש';
      case '1-3':
        return '1-3 חודשים';
      case '3-6':
        return '3-6 חודשים';
      default:
        return token;
    }
  }

  bool get isEmpty => activeCount == 0;
  bool get isNotEmpty => !isEmpty;

  /// Number of active constraints — drives the badge on the "מסננים" button.
  int get activeCount {
    var n = 0;
    if (budgetMin != null) n++;
    if (budgetMax != null) n++;
    if (moveInWindow != null) n++;
    if (minFitScore != null) n++;
    if (numChildrenMax != null) n++;
    if (hasPets != null) n++;
    if (hasCar != null) n++;
    if (household.isNotEmpty) n++;
    if (occupation.isNotEmpty) n++;
    if (incomeMin != null) n++;
    if (wfh != null) n++;
    if (verifiedOnly) n++;
    return n;
  }

  /// Pure test: does [c] satisfy every active constraint? Unknown (null)
  /// attributes always pass — we never exclude on a signal we can't measure.
  bool matches(CandidateAttributes c) {
    if (minFitScore != null && c.fitScore < minFitScore!) return false;

    if (c.budget != null) {
      if (budgetMin != null && c.budget! < budgetMin!) return false;
      if (budgetMax != null && c.budget! > budgetMax!) return false;
    }

    if (moveInWindow != null && c.availableInDays != null) {
      final maxDays = moveInWindowMaxDays[moveInWindow!];
      if (maxDays != null && c.availableInDays! > maxDays) return false;
    }

    if (numChildrenMax != null &&
        c.numChildren != null &&
        c.numChildren! > numChildrenMax!) {
      return false;
    }
    if (hasPets != null && c.hasPets != null && c.hasPets != hasPets) {
      return false;
    }
    if (hasCar != null && c.hasCar != null && c.hasCar != hasCar) return false;
    if (wfh != null && c.wfh != null && c.wfh != wfh) return false;

    if (household.isNotEmpty &&
        c.household != null &&
        !household.contains(c.household)) {
      return false;
    }
    if (occupation.isNotEmpty &&
        c.occupation != null &&
        !occupation.contains(c.occupation)) {
      return false;
    }
    if (incomeMin != null && c.income != null && c.income! < incomeMin!) {
      return false;
    }
    if (verifiedOnly && c.verified != null && c.verified != true) return false;

    return true;
  }

  CandidateFilters copyWith({
    double? budgetMin,
    double? budgetMax,
    String? moveInWindow,
    double? minFitScore,
    int? numChildrenMax,
    bool? hasPets,
    bool? hasCar,
    Set<String>? household,
    Set<String>? occupation,
    double? incomeMin,
    bool? wfh,
    bool? verifiedOnly,
    // Explicit clears — copyWith can't null-out a field via the params above.
    bool clearBudgetMin = false,
    bool clearBudgetMax = false,
    bool clearMoveInWindow = false,
    bool clearMinFitScore = false,
    bool clearNumChildrenMax = false,
    bool clearHasPets = false,
    bool clearHasCar = false,
    bool clearIncomeMin = false,
    bool clearWfh = false,
  }) {
    return CandidateFilters(
      budgetMin: clearBudgetMin ? null : (budgetMin ?? this.budgetMin),
      budgetMax: clearBudgetMax ? null : (budgetMax ?? this.budgetMax),
      moveInWindow:
          clearMoveInWindow ? null : (moveInWindow ?? this.moveInWindow),
      minFitScore: clearMinFitScore ? null : (minFitScore ?? this.minFitScore),
      numChildrenMax:
          clearNumChildrenMax ? null : (numChildrenMax ?? this.numChildrenMax),
      hasPets: clearHasPets ? null : (hasPets ?? this.hasPets),
      hasCar: clearHasCar ? null : (hasCar ?? this.hasCar),
      household: household ?? this.household,
      occupation: occupation ?? this.occupation,
      incomeMin: clearIncomeMin ? null : (incomeMin ?? this.incomeMin),
      wfh: clearWfh ? null : (wfh ?? this.wfh),
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
    );
  }

  static const CandidateFilters empty = CandidateFilters();

  /// Tiny assert-based self-check. Kept in-source so the invariants are visible
  /// next to the model; mirrored (and expanded) in
  /// test/candidate_filters_test.dart.
  static void demo() {
    const attrs = CandidateAttributes(fitScore: 82, availableInDays: 0);
    assert(CandidateFilters.empty.isEmpty);
    assert(CandidateFilters.empty.matches(attrs));
    assert(const CandidateFilters(minFitScore: 70).matches(attrs));
    assert(!const CandidateFilters(minFitScore: 90).matches(attrs));
    assert(const CandidateFilters(moveInWindow: 'immediate').matches(attrs));
    // Unknown attribute (budget) never excludes.
    assert(const CandidateFilters(budgetMin: 5000).matches(attrs));
    assert(const CandidateFilters(minFitScore: 70).activeCount == 1);
  }
}

/// The real, per-candidate attributes a caller could source on-device. Every
/// field except [fitScore] is nullable: null means "unknown / not available",
/// which [CandidateFilters.matches] treats as a pass.
class CandidateAttributes {
  const CandidateAttributes({
    required this.fitScore,
    this.budget,
    this.availableInDays,
    this.numChildren,
    this.hasPets,
    this.hasCar,
    this.wfh,
    this.household,
    this.occupation,
    this.income,
    this.verified,
  });

  /// Honest fit score in [0, 100] (always known — computed from real signals).
  final double fitScore;

  /// Candidate's declared budget (₪/mo), if a like snapshot carried one.
  final double? budget;

  /// Days until the liked property is available (0 = now), if it has an entry
  /// date. Drives the move-in / availability filter.
  final int? availableInDays;

  final int? numChildren;
  final bool? hasPets;
  final bool? hasCar;
  final bool? wfh;
  final String? household;
  final String? occupation;
  final double? income;
  final bool? verified;
}
