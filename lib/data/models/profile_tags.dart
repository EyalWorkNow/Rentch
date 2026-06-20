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

class ProfileTag {
  const ProfileTag(
    this.label, {
    this.matchKey,
    this.canBeDealBreaker = false,
  });

  /// The exact Hebrew string persisted in `TenantProfile.importantDetails`.
  final String label;

  /// Links a tenant tag to its compatible landlord tag (and vice-versa). Null
  /// for purely descriptive tags that don't participate in matching.
  final String? matchKey;

  /// Whether this preference is eligible to be flagged as a deal-breaker.
  final bool canBeDealBreaker;
}

class ProfileTagCategory {
  const ProfileTagCategory(this.title, this.tags);
  final String title;
  final List<ProfileTag> tags;
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
