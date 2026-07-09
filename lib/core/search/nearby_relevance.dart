// ═══════════════════════════════════════════════════════════════════════════
// Nearby-places PERSONALISATION.
//
// The property detail screen shows nearby schools / kindergartens / clinics /
// supermarkets / parks — but NOT all of them to everyone. This module decides,
// from the seeker's query/persona, WHICH sections are relevant and in what
// order, so a family sees schools & kindergartens, a health-focused seeker sees
// their HMO's clinics, and a young single sees neither.
//
// Pure Dart (no Flutter) → unit-testable with persona fixtures.
// ═══════════════════════════════════════════════════════════════════════════

/// The nearby section kinds, mapped 1:1 to IsraelGeoIndex.*Within helpers.
enum NearbyKind { schools, kindergartens, clinics, supermarkets, parks }

/// One relevant section for a given persona: what to show, filtered/ordered.
class NearbySection {
  const NearbySection(this.kind, {this.hmo = '', this.priority = 0});
  final NearbyKind kind;
  final String hmo; // clinics only: restrict to this HMO, '' = all
  final int priority; // higher = more relevant → shown first
}

/// Structured persona signals derived from the seeker's free-text query/persona.
class NearbyProfile {
  const NearbyProfile({
    this.family = false,
    this.youngChild = false, // toddler / preschool → kindergarten
    this.schoolChild = false, // elementary / middle
    this.teen = false, // high school
    this.wantsSchools = false, // explicit "בתי ספר" / good schools
    this.health = false, // wants healthcare access
    this.hmo = '', // preferred HMO: כללית/מכבי/לאומית/מאוחדת
    this.groceries = false, // wants a supermarket nearby
    this.green = false, // wants parks / green
    this.senior = false, // elderly → healthcare relevant
  });

  final bool family, youngChild, schoolChild, teen, wantsSchools;
  final bool health, groceries, green, senior;
  final String hmo;

  bool get anySignal =>
      family ||
      youngChild ||
      schoolChild ||
      teen ||
      wantsSchools ||
      health ||
      hmo.isNotEmpty ||
      groceries ||
      green ||
      senior;

  /// Parse a Hebrew/English query or persona string into the signals. Mirrors the
  /// SearchIntent regexes so it stays consistent with the search engine.
  factory NearbyProfile.fromText(String raw) {
    final q = raw.toLowerCase();
    bool has(String pattern) =>
        RegExp(pattern, caseSensitive: false).hasMatch(q);

    // Explicit "no children" negation → the whole family dimension is off, so a
    // young couple "בלי ילדים" isn't shown schools/kindergartens.
    final noKids = has(
        r'בלי ילד|ללא ילד|לא רוצ\w*\s*ילד|childless|no kids|without (kids|children)');

    final youngChild = !noKids &&
        has(r'תינוק|פעוט|גיל הרך|גני?\s*ילדים|גן חובה|גן טרום|טרום חובה|צהרון|לגן|מעון|toddler|baby|preschool|kindergarten|nursery');
    final teen = !noKids && has(r'תיכון|מתבגר|נוער|בני נוער|teen|high ?school');
    final schoolChild = !noKids &&
        has(r'בית ?ספר|בתי ?ספר|יסודי|חטיב|תלמיד|elementary|middle ?school|grade ?school');
    // Broad family/children signal (SearchIntent family detector).
    final family = !noKids &&
        (youngChild ||
            teen ||
            schoolChild ||
            has(r'משפח|ילד|ילדה|ילדים|בהריון|הריון|family|kids?|child(ren)?'));

    // HMO — but each fund name is ambiguous: "לאומית" is also the religious-
    // Zionist stream ("דתית לאומית"), "מכבי" is also the sports club, "מאוחדת"
    // is also a political list. Disambiguate so a persona isn't mis-tagged.
    final religiousNational = has(r'דת[יה]?ת?[ \-]?לאומ|לאומ[יה]?ת?[ \-]?דת');
    final maccabiSport = has(r'כדורגל|כדורסל|אצטדיון|קבוצת|הפועל|יורוליג');
    String hmo = '';
    if (has(r'כללית|clalit')) {
      hmo = 'כללית';
    } else if (has(r'מכבי|maccabi|makabi') && !maccabiSport) {
      hmo = 'מכבי';
    } else if (has(r'לאומית|leumit') && !religiousNational) {
      hmo = 'לאומית';
    } else if (has(r'מאוחדת|meuhedet') && !has(r'רשימה|מפלגה')) {
      hmo = 'מאוחדת';
    }
    final health = hmo.isNotEmpty ||
        has(r'בית ?חולים|קופת ?חולים|קופ״ח|מרפא\w*|רופא|בריאות|רפואה|clinic|hospital|medical|health|doctor|pediatric');

    return NearbyProfile(
      family: family,
      youngChild: youngChild,
      schoolChild: schoolChild,
      teen: teen,
      wantsSchools:
          has(r'בית ?ספר|בתי ?ספר|מוסדות ?חינוך|חינוך טוב|good ?schools?'),
      health: health,
      hmo: hmo,
      groceries: has(
          r'סופר|סופרמרקט|מכולת|קניות|מרכז ?קניות|קניון|'
          // common Israeli grocery chains (a query often names the chain):
          r'שופרסל|רמי לוי|ויקטורי|יינות ביתן|אושר עד|טיב טעם|מגה|מחסני השוק|יוחננוף|חצי חינם|קופיקס|am:?pm|'
          r'supermarket|grocer|groceries|errands|shopping'),
      green: has(r'פארק|גינה|שטח ?ירוק|ירוק|טבע|park|garden|green|nature'),
      senior: has(r'מבוגר|גמלא|קשיש|פנסי|זוג מבוגר|senior|elderly|retire'),
    );
  }
}

/// Decide which nearby sections are RELEVANT to [p], ordered most-relevant first.
/// Strict: a section appears only when the persona actually implies a need for
/// it (an empty result → the whole card hides, which is the intended behaviour
/// for a query with no lifestyle signal).
List<NearbySection> relevantNearbySections(NearbyProfile p) {
  final sections = <NearbySection>[];

  // Kindergartens: a toddler, or a family that hasn't signalled older kids.
  if (p.youngChild) {
    sections.add(const NearbySection(NearbyKind.kindergartens, priority: 95));
  } else if (p.family && !p.schoolChild && !p.teen && !p.wantsSchools) {
    sections.add(const NearbySection(NearbyKind.kindergartens, priority: 60));
  }

  // Schools: school-age/teen/explicit interest, or a generic family (kids grow).
  if (p.schoolChild || p.teen || p.wantsSchools) {
    sections.add(NearbySection(NearbyKind.schools,
        priority: (p.teen || p.schoolChild) ? 95 : 85));
  } else if (p.family && !p.youngChild) {
    sections.add(const NearbySection(NearbyKind.schools, priority: 65));
  }

  // Clinics: a health need, a named HMO, or an elderly seeker. HMO filters it.
  if (p.health || p.hmo.isNotEmpty || p.senior) {
    sections.add(NearbySection(NearbyKind.clinics,
        hmo: p.hmo,
        priority: p.hmo.isNotEmpty ? 90 : (p.senior ? 80 : 75)));
  }

  // Supermarkets: only when errands/groceries are an explicit concern.
  if (p.groceries) {
    sections.add(const NearbySection(NearbyKind.supermarkets, priority: 85));
  }

  // Parks: an explicit green wish, or a family (kids + outdoors).
  if (p.green) {
    sections.add(const NearbySection(NearbyKind.parks, priority: 80));
  } else if (p.family) {
    sections.add(const NearbySection(NearbyKind.parks, priority: 55));
  }

  sections.sort((a, b) => b.priority.compareTo(a.priority));
  return sections;
}
