/// Catalog of selectable profile tags for both renters ("tenant") and property
/// owners ("landlord"), grouped into searchable categories.
///
/// A tag may carry a [matchKey]. When a tenant tag and a landlord tag share the
/// same [matchKey] they are considered *compatible* — the matching algorithm
/// rewards the pair. Tags flagged [canBeDealBreaker] can additionally be marked
/// by the user as non-negotiable: if the other side lacks the compatible
/// counterpart the match is heavily penalized instead of merely missing a bonus.
///
/// Keeping this list in one place lets the profile editor, the filter sheet and
/// [DatingProvider]'s scoring all stay in sync.
library;

import 'package:dating_app/l10n/app_localizations.dart';

class ProfileTag {
  const ProfileTag(
    this.label, {
    this.matchKey,
    this.canBeDealBreaker = false,
  });

  /// The exact Hebrew string persisted in `TenantProfile.importantDetails`.
  /// This is the canonical value used for storage, comparison and matching
  /// throughout the app (`tagFor`, `matchKeysFor`, deal-breaker lists) — it
  /// must never change.
  final String label;

  /// Links a tenant tag to its compatible landlord tag (and vice-versa). Null
  /// for purely descriptive tags that don't participate in matching.
  final String? matchKey;

  /// Whether this preference is eligible to be flagged as a deal-breaker.
  final bool canBeDealBreaker;

  /// The text to actually render to the user, translated into the active
  /// locale. [label] itself stays fixed (it's the persisted/compared value) —
  /// only the on-screen text changes per-locale.
  String displayLabel(AppLocalizations l10n) => _tagDisplayLabel(label, l10n);
}

class ProfileTagCategory {
  const ProfileTagCategory(this.title, this.tags);
  final String title;
  final List<ProfileTag> tags;

  /// The category heading, translated into the active locale.
  String displayTitle(AppLocalizations l10n) =>
      _categoryDisplayTitle(title, l10n);
}

/// Localized display text for a tag catalog entry, keyed by the (stable,
/// Hebrew) [ProfileTag.label]. Falls back to the raw label for anything not
/// in the catalog (e.g. free-text tags added via voice-fill).
String _tagDisplayLabel(String label, AppLocalizations l10n) {
  switch (label) {
    // ── Tenant: status & household ──────────────────────────────────────
    case 'יחיד/ה':
      return l10n.profileTagsSingle;
    case 'זוג':
      return l10n.profileTagsCouple;
    case 'משפחה עם ילדים':
      return l10n.profileTagsFamilyWithKids;
    case 'מחפש/ת שותפים':
      return l10n.profileTagsSeekingRoommates;
    case 'סטודנט/ית':
      return l10n.profileTagsStudent;
    case 'אנשי מקצוע עובדים':
      return l10n.profileTagsWorkingProfessionals;
    case 'עובד/ת מהבית':
      return l10n.profileTagsWorksFromHome;

    // ── Tenant: lifestyle ────────────────────────────────────────────────
    case 'לא מעשן/ת':
      return l10n.profileTagsNonSmoker;
    case 'יש לי חיות מחמד':
      return l10n.profileTagsHasPets;
    case 'ללא חיות מחמד':
      return l10n.profileTagsNoPets;
    case 'שקט/ה ומסודר/ת':
      return l10n.profileTagsQuietTidy;
    case 'צמחוני/ת':
      return l10n.profileTagsVegetarian;
    case 'אורח חיים דתי':
      return l10n.profileTagsReligiousLifestyle;
    case 'שומר/ת שבת':
      return l10n.profileTagsShabbatObservant;

    // ── Tenant: apartment requirements ──────────────────────────────────
    case 'חייב/ת חניה':
      return l10n.profileTagsMustHaveParking;
    case 'מרוהטת':
      return l10n.profileTagsFurnished;
    case 'מעלית':
      return l10n.profileTagsElevator;
    case 'מרפסת':
      return l10n.profileTagsBalcony;
    case 'ממ"ד / מקלט':
      return l10n.profileTagsShelter;
    case 'מיזוג אוויר':
      return l10n.profileTagsAc;
    case 'נגישות לנכים':
      return l10n.profileTagsAccessibleForDisabled;
    case 'מתאים לחיות מחמד':
      return l10n.profileTagsPetFriendly;
    case 'ממ"ד פרטי':
      return l10n.profileTagsPrivateShelter;

    // ── Tenant: contract & payment ──────────────────────────────────────
    case 'אישור הכנסה מוכן':
      return l10n.profileTagsIncomeProofReady;
    case 'יש לי ערבים':
      return l10n.profileTagsHasGuarantors;
    case 'שכירות ארוכת טווח':
      return l10n.profileTagsLongTermRental;
    case 'שכירות לטווח קצר':
      return l10n.profileTagsShortTermRental;
    case 'כניסה מיידית':
      return l10n.profileTagsImmediateMoveIn;
    case 'גמיש/ה במועד הכניסה':
      return l10n.profileTagsFlexibleMoveInDate;
    case 'תשלום מראש אפשרי':
      return l10n.profileTagsAdvancePaymentPossible;
    case 'שוכר/ת ותיק/ה עם המלצות':
      return l10n.profileTagsExperiencedTenantWithReferences;

    // ── Landlord: about my property ─────────────────────────────────────
    case 'הדירה מרוהטת':
      return l10n.profileTagsApartmentFurnished;
    case 'יש חניה':
      return l10n.profileTagsHasParking;
    case 'יש מעלית':
      return l10n.profileTagsHasElevator;
    case 'יש מרפסת':
      return l10n.profileTagsHasBalcony;
    case 'דירה נגישה':
      return l10n.profileTagsAccessibleApartment;
    case 'נכס משופץ':
      return l10n.profileTagsRenovatedProperty;

    // ── Landlord: suitable for ──────────────────────────────────────────
    case 'מאפשר בעלי חיים':
      return l10n.profileTagsAllowsPets;
    case 'מתאים לזוגות':
      return l10n.profileTagsSuitableForCouples;
    case 'מתאים למשפחות':
      return l10n.profileTagsSuitableForFamilies;
    case 'מתאים לשותפים':
      return l10n.profileTagsSuitableForRoommates;
    case 'מתאים לסטודנטים':
      return l10n.profileTagsSuitableForStudents;
    case 'מעדיף שוכרים לא מעשנים':
      return l10n.profileTagsPrefersNonSmokingTenants;
    case 'מחפש שוכרים שקטים':
      return l10n.profileTagsSeeksQuietTenants;

    // ── Landlord: contract & requirements ───────────────────────────────
    case 'חוזה מסודר':
      return l10n.profileTagsProperContract;
    case 'חוזה ארוך טווח':
      return l10n.profileTagsLongTermContract;
    case 'מאפשר טווח קצר':
      return l10n.profileTagsAllowsShortTerm;
    case 'דורש אישור הכנסה':
      return l10n.profileTagsRequiresIncomeProof;
    case 'דורש ערבים':
      return l10n.profileTagsRequiresGuarantors;
    case 'גמישות במחיר':
      return l10n.profileTagsPriceFlexibility;
    case 'ללא תיווך':
      return l10n.profileTagsNoBroker;

    // ── Landlord: service ────────────────────────────────────────────────
    case 'תגובה מהירה':
      return l10n.profileTagsQuickResponse;
    case 'ניסיון בניהול נכסים':
      return l10n.profileTagsPropertyManagementExperience;
    case 'זמין לסיורים גם בערב':
      return l10n.profileTagsAvailableForEveningTours;
    case 'יחס אישי לשוכרים':
      return l10n.profileTagsPersonalizedTenantService;

    default:
      return label;
  }
}

/// Localized display text for a tag category heading, keyed by the (stable,
/// Hebrew) [ProfileTagCategory.title].
String _categoryDisplayTitle(String title, AppLocalizations l10n) {
  switch (title) {
    case 'סטטוס ומשק בית':
      return l10n.profileTagsCategoryHouseholdStatus;
    case 'אורח חיים':
      return l10n.profileTagsCategoryLifestyle;
    case 'דרישות מהדירה':
      return l10n.profileTagsCategoryApartmentRequirements;
    case 'חוזה ותשלום':
      return l10n.profileTagsCategoryContractPayment;
    case 'על הנכס שלי':
      return l10n.profileTagsCategoryAboutMyProperty;
    case 'מתאים ל':
      return l10n.profileTagsCategorySuitableFor;
    case 'חוזה ודרישות':
      return l10n.profileTagsCategoryContractRequirements;
    case 'שירות':
      return l10n.profileTagsCategoryService;
    default:
      return title;
  }
}

class ProfileTagCatalog {
  const ProfileTagCatalog._();

  // ── Tenant (renter) tags ────────────────────────────────────────────────
  static const List<ProfileTagCategory> tenant = [
    ProfileTagCategory('סטטוס ומשק בית', [
      ProfileTag('יחיד/ה'),
      ProfileTag('זוג', matchKey: 'couples'),
      ProfileTag('משפחה עם ילדים', matchKey: 'family'),
      ProfileTag('מחפש/ת שותפים', matchKey: 'roommates'),
      ProfileTag('סטודנט/ית', matchKey: 'students'),
      ProfileTag('אנשי מקצוע עובדים'),
      ProfileTag('עובד/ת מהבית'),
    ]),
    ProfileTagCategory('אורח חיים', [
      ProfileTag('לא מעשן/ת', matchKey: 'no_smoking', canBeDealBreaker: true),
      ProfileTag('יש לי חיות מחמד', matchKey: 'pets', canBeDealBreaker: true),
      ProfileTag('ללא חיות מחמד'),
      ProfileTag('שקט/ה ומסודר/ת', matchKey: 'quiet'),
      ProfileTag('צמחוני/ת'),
      ProfileTag('אורח חיים דתי'),
      ProfileTag('שומר/ת שבת'),
    ]),
    ProfileTagCategory('דרישות מהדירה', [
      ProfileTag('חייב/ת חניה', matchKey: 'parking', canBeDealBreaker: true),
      ProfileTag('מרוהטת', matchKey: 'furnished', canBeDealBreaker: true),
      ProfileTag('מעלית', matchKey: 'elevator', canBeDealBreaker: true),
      ProfileTag('מרפסת', matchKey: 'balcony'),
      ProfileTag('ממ"ד / מקלט', matchKey: 'shelter'),
      ProfileTag('מיזוג אוויר', matchKey: 'ac'),
      ProfileTag('נגישות לנכים', matchKey: 'accessible', canBeDealBreaker: true),
      ProfileTag('מתאים לחיות מחמד', matchKey: 'pets_allowed', canBeDealBreaker: true),
      ProfileTag('ממ"ד פרטי'),
    ]),
    ProfileTagCategory('חוזה ותשלום', [
      ProfileTag('אישור הכנסה מוכן', matchKey: 'income_proof'),
      ProfileTag('יש לי ערבים', matchKey: 'guarantors'),
      ProfileTag('שכירות ארוכת טווח', matchKey: 'long_term'),
      ProfileTag('שכירות לטווח קצר', matchKey: 'short_term', canBeDealBreaker: true),
      ProfileTag('כניסה מיידית', matchKey: 'immediate'),
      ProfileTag('גמיש/ה במועד הכניסה'),
      ProfileTag('תשלום מראש אפשרי'),
      ProfileTag('שוכר/ת ותיק/ה עם המלצות'),
    ]),
  ];

  // ── Landlord (owner) tags ───────────────────────────────────────────────
  static const List<ProfileTagCategory> landlord = [
    ProfileTagCategory('על הנכס שלי', [
      ProfileTag('הדירה מרוהטת', matchKey: 'furnished'),
      ProfileTag('יש חניה', matchKey: 'parking'),
      ProfileTag('יש מעלית', matchKey: 'elevator'),
      ProfileTag('יש מרפסת', matchKey: 'balcony'),
      ProfileTag('ממ"ד / מקלט', matchKey: 'shelter'),
      ProfileTag('מיזוג אוויר', matchKey: 'ac'),
      ProfileTag('דירה נגישה', matchKey: 'accessible'),
      ProfileTag('נכס משופץ'),
    ]),
    ProfileTagCategory('מתאים ל', [
      ProfileTag('מאפשר בעלי חיים', matchKey: 'pets_allowed'),
      ProfileTag('מתאים לזוגות', matchKey: 'couples'),
      ProfileTag('מתאים למשפחות', matchKey: 'family'),
      ProfileTag('מתאים לשותפים', matchKey: 'roommates'),
      ProfileTag('מתאים לסטודנטים', matchKey: 'students'),
      ProfileTag('מעדיף שוכרים לא מעשנים', matchKey: 'no_smoking', canBeDealBreaker: true),
      ProfileTag('מחפש שוכרים שקטים', matchKey: 'quiet'),
    ]),
    ProfileTagCategory('חוזה ודרישות', [
      ProfileTag('חוזה מסודר'),
      ProfileTag('חוזה ארוך טווח', matchKey: 'long_term'),
      ProfileTag('מאפשר טווח קצר', matchKey: 'short_term'),
      ProfileTag('כניסה מיידית', matchKey: 'immediate'),
      ProfileTag('דורש אישור הכנסה', matchKey: 'income_proof', canBeDealBreaker: true),
      ProfileTag('דורש ערבים', matchKey: 'guarantors', canBeDealBreaker: true),
      ProfileTag('גמישות במחיר'),
      ProfileTag('ללא תיווך'),
    ]),
    ProfileTagCategory('שירות', [
      ProfileTag('תגובה מהירה'),
      ProfileTag('ניסיון בניהול נכסים'),
      ProfileTag('זמין לסיורים גם בערב'),
      ProfileTag('יחס אישי לשוכרים'),
    ]),
  ];

  static List<ProfileTagCategory> forRole({required bool isLandlord}) =>
      isLandlord ? landlord : tenant;

  /// Flat list of every tag label for a role.
  static List<String> labelsForRole({required bool isLandlord}) => [
        for (final category in forRole(isLandlord: isLandlord))
          for (final tag in category.tags) tag.label,
      ];

  /// Lookup a tag definition by its label within a role.
  static ProfileTag? tagFor(String label, {required bool isLandlord}) {
    for (final category in forRole(isLandlord: isLandlord)) {
      for (final tag in category.tags) {
        if (tag.label == label) return tag;
      }
    }
    return null;
  }

  /// The set of [matchKey]s represented by a list of selected tag labels.
  static Set<String> matchKeysFor(
    List<String> labels, {
    required bool isLandlord,
  }) {
    final keys = <String>{};
    for (final label in labels) {
      final tag = tagFor(label, isLandlord: isLandlord);
      if (tag?.matchKey != null) keys.add(tag!.matchKey!);
    }
    return keys;
  }
}
