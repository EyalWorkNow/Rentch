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
    this.maxFitScore,
    this.numChildrenMax,
    this.hasPets,
    this.hasCar,
    this.household = const <String>{},
    this.occupation = const <String>{},
    this.incomeMin,
    this.wfh,
    this.verifiedOnly = false,
    this.ageMin,
    this.ageMax,
    this.lifeStage = const <String>{},
    this.roomsMin,
    this.recentOnly = false,
    this.minIncomeToRentRatio,
    this.oleh,
    this.maxCommuteKm,
    this.smoker,
    this.hasGuarantor,
    this.minLeaseMonths,
    this.incomeProofReady,
    this.religiousLifestyle = const <String>{},
    this.shabbatObservant,
    this.keepsKosher,
    this.petTypes = const <String>{},
    this.hostsGuests,
    this.playsInstrument,
  });

  /// Candidate's declared budget floor / ceiling (₪ per month). null = inactive.
  final double? budgetMin;
  final double? budgetMax;

  /// Availability bucket the liked property must fall within. null = inactive.
  /// One of [moveInWindowTokens]. Matched against days-until-available.
  final String? moveInWindow;

  /// Honest fit-score window in [0, 100]. null = inactive (open on that end),
  /// so the landlord can pick a RANGE (e.g. 30–70) for flexibility.
  final double? minFitScore;
  final double? maxFitScore;

  /// Household size / attribute constraints (future-proof; unpopulated today).
  final int? numChildrenMax;
  final bool? hasPets;
  final bool? hasCar;
  final Set<String> household;
  final Set<String> occupation;
  final double? incomeMin;
  final bool? wfh;
  final bool verifiedOnly;

  /// Candidate age window (years). null on an end = open there.
  final int? ageMin;
  final int? ageMax;

  /// Life-stage keys the candidate must fall into (student / young-professional
  /// / family / senior). Empty = inactive.
  final Set<String> lifeStage;

  /// Minimum desired rooms the candidate declared. null = inactive.
  final double? roomsMin;

  /// When true, keep only candidates whose like is recent (≤ 7 days old).
  /// Unknown like-age passes.
  final bool recentOnly;

  /// Minimum income-to-rent ratio (e.g. 2.5 ⇒ income ≥ 2.5× the liked
  /// property's rent). null = inactive. Computed per candidate from the liker's
  /// income and the liked property's price.
  final double? minIncomeToRentRatio;

  /// When true, keep only candidates who are new immigrants (עולה חדש); when
  /// false, only non-oleh. null = inactive. Unknown liker value passes.
  final bool? oleh;

  /// Maximum distance (km) between the candidate's work location and the liked
  /// property. null = inactive. Unknown commute (no work location) passes.
  final double? maxCommuteKm;

  /// Candidate smoking status constraint. null = inactive. Unknown passes.
  final bool? smoker;

  /// When true, keep only candidates who have a guarantor (ערב). null = inactive.
  final bool? hasGuarantor;

  /// Minimum desired lease length in months (e.g. 12 ⇒ ≥ 12 months). null =
  /// inactive. Unknown lease length passes.
  final int? minLeaseMonths;

  /// When true, keep only candidates whose income proof is ready. null =
  /// inactive. Unknown passes.
  final bool? incomeProofReady;

  // ── Lifestyle / religious deal-breakers (Israeli market) ────────────────────
  /// Acceptable tenant lifestyles: chiloni / masorti / dati / charedi. Empty =
  /// inactive. A candidate whose lifestyle isn't in the set is excluded (unknown
  /// passes). Set-membership, like [household]/[lifeStage].
  final Set<String> religiousLifestyle;

  /// Require Shomer-Shabbat (true) or specifically NOT (false). null = inactive.
  final bool? shabbatObservant;

  /// Require a kosher-keeping tenant (true) or specifically not (false). null =
  /// inactive. The key shared-apartment compatibility signal.
  final bool? keepsKosher;

  /// Acceptable pet types: none / cat / dog_small / dog_large / other. Empty =
  /// inactive. Lets a landlord allow a cat but exclude a large dog, instead of a
  /// blunt yes/no. Unknown pet detail passes.
  final Set<String> petTypes;

  /// Constrain frequent hosting/gatherings (false ⇒ only quiet tenants). null =
  /// inactive. Unknown passes.
  final bool? hostsGuests;

  /// Constrain instrument-playing (false ⇒ exclude players). null = inactive.
  /// Unknown passes.
  final bool? playsInstrument;

  /// A like at or under this age (days) counts as "recent" for [recentOnly].
  static const int recentLikeMaxDays = 7;

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

  /// Canonical life-stage tokens (locked to the eligibility gate's allowlist —
  /// note the hyphen in 'young-professional') and their Hebrew labels (RTL UI).
  static const Map<String, String> lifeStageLabels = <String, String>{
    'student': 'סטודנט/ית',
    'young-professional': 'צעיר/ה מקצועי/ת',
    'family': 'משפחה',
    'senior': 'גיל הזהב',
  };

  static String lifeStageLabel(String token) => lifeStageLabels[token] ?? token;

  bool get isEmpty => activeCount == 0;
  bool get isNotEmpty => !isEmpty;

  /// Number of active constraints — drives the badge on the "מסננים" button.
  int get activeCount {
    var n = 0;
    if (budgetMin != null) n++;
    if (budgetMax != null) n++;
    if (moveInWindow != null) n++;
    if (minFitScore != null || maxFitScore != null) n++;
    if (numChildrenMax != null) n++;
    if (hasPets != null) n++;
    if (hasCar != null) n++;
    if (household.isNotEmpty) n++;
    if (occupation.isNotEmpty) n++;
    if (incomeMin != null) n++;
    if (wfh != null) n++;
    if (verifiedOnly) n++;
    if (ageMin != null || ageMax != null) n++;
    if (lifeStage.isNotEmpty) n++;
    if (roomsMin != null) n++;
    if (recentOnly) n++;
    if (minIncomeToRentRatio != null) n++;
    if (oleh != null) n++;
    if (maxCommuteKm != null) n++;
    if (smoker != null) n++;
    if (hasGuarantor != null) n++;
    if (minLeaseMonths != null) n++;
    if (incomeProofReady != null) n++;
    if (religiousLifestyle.isNotEmpty) n++;
    if (shabbatObservant != null) n++;
    if (keepsKosher != null) n++;
    if (petTypes.isNotEmpty) n++;
    if (hostsGuests != null) n++;
    if (playsInstrument != null) n++;
    return n;
  }

  /// Pure test: does [c] satisfy every active constraint? Unknown (null)
  /// attributes always pass — we never exclude on a signal we can't measure.
  bool matches(CandidateAttributes c) {
    if (minFitScore != null && c.fitScore < minFitScore!) return false;
    if (maxFitScore != null && c.fitScore > maxFitScore!) return false;

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

    if (c.age != null) {
      if (ageMin != null && c.age! < ageMin!) return false;
      if (ageMax != null && c.age! > ageMax!) return false;
    }

    if (lifeStage.isNotEmpty &&
        c.lifeStage != null &&
        !lifeStage.contains(c.lifeStage)) {
      return false;
    }

    if (roomsMin != null && c.rooms != null && c.rooms! < roomsMin!) {
      return false;
    }

    if (recentOnly &&
        c.likedInDays != null &&
        c.likedInDays! > recentLikeMaxDays) {
      return false;
    }

    // Affordability: income-to-rent ratio floor.
    if (minIncomeToRentRatio != null &&
        c.incomeToRentRatio != null &&
        c.incomeToRentRatio! < minIncomeToRentRatio!) {
      return false;
    }

    if (oleh != null && c.isOleh != null && c.isOleh != oleh) return false;

    if (maxCommuteKm != null &&
        c.commuteKm != null &&
        c.commuteKm! > maxCommuteKm!) {
      return false;
    }

    if (smoker != null && c.smoker != null && c.smoker != smoker) return false;

    if (hasGuarantor != null &&
        c.hasGuarantor != null &&
        c.hasGuarantor != hasGuarantor) {
      return false;
    }

    if (minLeaseMonths != null &&
        c.leaseMonths != null &&
        c.leaseMonths! < minLeaseMonths!) {
      return false;
    }

    if (incomeProofReady != null &&
        c.incomeProofReady != null &&
        c.incomeProofReady != incomeProofReady) {
      return false;
    }

    if (religiousLifestyle.isNotEmpty &&
        c.religiousLifestyle != null &&
        !religiousLifestyle.contains(c.religiousLifestyle)) {
      return false;
    }
    if (shabbatObservant != null &&
        c.shabbatObservant != null &&
        c.shabbatObservant != shabbatObservant) {
      return false;
    }
    if (keepsKosher != null &&
        c.keepsKosher != null &&
        c.keepsKosher != keepsKosher) {
      return false;
    }
    if (petTypes.isNotEmpty && c.petType != null && !petTypes.contains(c.petType)) {
      return false;
    }
    if (hostsGuests != null &&
        c.hostsGuests != null &&
        c.hostsGuests != hostsGuests) {
      return false;
    }
    if (playsInstrument != null &&
        c.playsInstrument != null &&
        c.playsInstrument != playsInstrument) {
      return false;
    }

    return true;
  }

  CandidateFilters copyWith({
    double? budgetMin,
    double? budgetMax,
    String? moveInWindow,
    double? minFitScore,
    double? maxFitScore,
    int? numChildrenMax,
    bool? hasPets,
    bool? hasCar,
    Set<String>? household,
    Set<String>? occupation,
    double? incomeMin,
    bool? wfh,
    bool? verifiedOnly,
    int? ageMin,
    int? ageMax,
    Set<String>? lifeStage,
    double? roomsMin,
    bool? recentOnly,
    double? minIncomeToRentRatio,
    bool? oleh,
    double? maxCommuteKm,
    bool? smoker,
    bool? hasGuarantor,
    int? minLeaseMonths,
    bool? incomeProofReady,
    Set<String>? religiousLifestyle,
    bool? shabbatObservant,
    bool? keepsKosher,
    Set<String>? petTypes,
    bool? hostsGuests,
    bool? playsInstrument,
    // Explicit clears — copyWith can't null-out a field via the params above.
    bool clearBudgetMin = false,
    bool clearBudgetMax = false,
    bool clearMoveInWindow = false,
    bool clearMinFitScore = false,
    bool clearMaxFitScore = false,
    bool clearNumChildrenMax = false,
    bool clearHasPets = false,
    bool clearHasCar = false,
    bool clearIncomeMin = false,
    bool clearWfh = false,
    bool clearAgeMin = false,
    bool clearAgeMax = false,
    bool clearRoomsMin = false,
    bool clearMinIncomeToRentRatio = false,
    bool clearOleh = false,
    bool clearMaxCommuteKm = false,
    bool clearSmoker = false,
    bool clearHasGuarantor = false,
    bool clearMinLeaseMonths = false,
    bool clearIncomeProofReady = false,
    bool clearShabbatObservant = false,
    bool clearKeepsKosher = false,
    bool clearHostsGuests = false,
    bool clearPlaysInstrument = false,
  }) {
    return CandidateFilters(
      budgetMin: clearBudgetMin ? null : (budgetMin ?? this.budgetMin),
      budgetMax: clearBudgetMax ? null : (budgetMax ?? this.budgetMax),
      moveInWindow:
          clearMoveInWindow ? null : (moveInWindow ?? this.moveInWindow),
      minFitScore: clearMinFitScore ? null : (minFitScore ?? this.minFitScore),
      maxFitScore: clearMaxFitScore ? null : (maxFitScore ?? this.maxFitScore),
      numChildrenMax:
          clearNumChildrenMax ? null : (numChildrenMax ?? this.numChildrenMax),
      hasPets: clearHasPets ? null : (hasPets ?? this.hasPets),
      hasCar: clearHasCar ? null : (hasCar ?? this.hasCar),
      household: household ?? this.household,
      occupation: occupation ?? this.occupation,
      incomeMin: clearIncomeMin ? null : (incomeMin ?? this.incomeMin),
      wfh: clearWfh ? null : (wfh ?? this.wfh),
      verifiedOnly: verifiedOnly ?? this.verifiedOnly,
      ageMin: clearAgeMin ? null : (ageMin ?? this.ageMin),
      ageMax: clearAgeMax ? null : (ageMax ?? this.ageMax),
      lifeStage: lifeStage ?? this.lifeStage,
      roomsMin: clearRoomsMin ? null : (roomsMin ?? this.roomsMin),
      recentOnly: recentOnly ?? this.recentOnly,
      minIncomeToRentRatio: clearMinIncomeToRentRatio
          ? null
          : (minIncomeToRentRatio ?? this.minIncomeToRentRatio),
      oleh: clearOleh ? null : (oleh ?? this.oleh),
      maxCommuteKm:
          clearMaxCommuteKm ? null : (maxCommuteKm ?? this.maxCommuteKm),
      smoker: clearSmoker ? null : (smoker ?? this.smoker),
      hasGuarantor:
          clearHasGuarantor ? null : (hasGuarantor ?? this.hasGuarantor),
      minLeaseMonths:
          clearMinLeaseMonths ? null : (minLeaseMonths ?? this.minLeaseMonths),
      incomeProofReady: clearIncomeProofReady
          ? null
          : (incomeProofReady ?? this.incomeProofReady),
      religiousLifestyle: religiousLifestyle ?? this.religiousLifestyle,
      shabbatObservant: clearShabbatObservant
          ? null
          : (shabbatObservant ?? this.shabbatObservant),
      keepsKosher: clearKeepsKosher ? null : (keepsKosher ?? this.keepsKosher),
      petTypes: petTypes ?? this.petTypes,
      hostsGuests:
          clearHostsGuests ? null : (hostsGuests ?? this.hostsGuests),
      playsInstrument: clearPlaysInstrument
          ? null
          : (playsInstrument ?? this.playsInstrument),
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

    // Lifestyle / religious deal-breakers.
    const shabbatTenant = CandidateAttributes(
      fitScore: 80,
      shabbatObservant: true,
      keepsKosher: true,
      religiousLifestyle: 'dati',
      petType: 'dog_large',
    );
    // A landlord requiring Shomer-Shabbat keeps an observant tenant, drops a non.
    assert(const CandidateFilters(shabbatObservant: true).matches(shabbatTenant));
    assert(!const CandidateFilters(shabbatObservant: false)
        .matches(shabbatTenant));
    // Lifestyle set-membership.
    assert(const CandidateFilters(religiousLifestyle: {'dati', 'masorti'})
        .matches(shabbatTenant));
    assert(!const CandidateFilters(religiousLifestyle: {'chiloni'})
        .matches(shabbatTenant));
    // Pet-type: allow cats + small dogs excludes a large dog.
    assert(!const CandidateFilters(petTypes: {'none', 'cat', 'dog_small'})
        .matches(shabbatTenant));
    // Unknown lifestyle never excludes.
    assert(const CandidateFilters(shabbatObservant: true).matches(attrs));
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
    this.age,
    this.lifeStage,
    this.rooms,
    this.likedInDays,
    this.incomeToRentRatio,
    this.isOleh,
    this.commuteKm,
    this.smoker,
    this.hasGuarantor,
    this.leaseMonths,
    this.incomeProofReady,
    this.religiousLifestyle,
    this.shabbatObservant,
    this.keepsKosher,
    this.petType,
    this.hostsGuests,
    this.playsInstrument,
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

  /// Candidate age in years, if the like snapshot carried one.
  final int? age;

  /// Candidate life-stage key (student / young-professional / family / senior).
  final String? lifeStage;

  /// Candidate's declared desired rooms, if known.
  final double? rooms;

  /// How many days ago the like was created (0 = today). Drives [recentOnly].
  final int? likedInDays;

  /// Candidate income ÷ the liked property's rent, if both are known.
  final double? incomeToRentRatio;

  /// Whether the candidate is a new immigrant (עולה חדש), if known.
  final bool? isOleh;

  /// Distance (km) from the candidate's work location to the liked property,
  /// if a work location is on file.
  final double? commuteKm;

  /// Candidate smoking status, if known.
  final bool? smoker;

  /// Whether the candidate has a guarantor (ערב), if known.
  final bool? hasGuarantor;

  /// Candidate's desired lease length in months, if known.
  final int? leaseMonths;

  /// Whether the candidate's income proof is ready, if known.
  final bool? incomeProofReady;

  // ── Lifestyle / religious signals (Israeli-market deal-breakers) ────────────
  /// Candidate lifestyle: chiloni / masorti / dati / charedi, if known.
  final String? religiousLifestyle;

  /// Whether the candidate keeps Shabbat, if known.
  final bool? shabbatObservant;

  /// Whether the candidate keeps kosher, if known.
  final bool? keepsKosher;

  /// Candidate pet detail: none / cat / dog_small / dog_large / other, if known.
  final String? petType;

  /// Whether the candidate hosts frequently, if known.
  final bool? hostsGuests;

  /// Whether the candidate plays an instrument at home, if known.
  final bool? playsInstrument;
}
