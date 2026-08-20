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
/// The first group is family/health oriented; the second (pharmacies →
/// nightlife) adds lifestyle layers so singles / couples / roommates — who used
/// to see an empty card — get content relevant to how they want to live.
enum NearbyKind {
  schools,
  kindergartens,
  clinics,
  pharmacies,
  supermarkets,
  parks,
  playgrounds,
  dining, // מסעדות ובתי קפה
  gyms, // חדרי כושר
  nightlife, // ברים ופאבים
  synagogues, // בתי כנסת
  culture, // מוזיאונים/תיאטראות/קולנוע/מתנ״סים
  hospitals, // בתי חולים
  transit, // תחנות רכבת ורק״ל
  worship, // מסגדים וכנסיות
  pools, // בריכות ומרכזי ספורט
  dogParks, // גינות כלבים
  vets, // וטרינרים
  bikeShare, // תחנות אופניים
  coworking, // חללי עבודה משותפים
  parking, // חניונים
  rail, // תחנות רכבת כבדה
  airQuality, // תחנות ניטור איכות אוויר
}

/// Maps a nearby category to the ranking DIMENSION it should boost when the
/// seeker explicitly marks it important in the search filter. Returns null for
/// categories that have no scoring dimension today (display-only, e.g. vets /
/// parking). All returned names exist in `kScoringDimensions`.
String? nearbyKindToDimension(NearbyKind k) {
  switch (k) {
    case NearbyKind.schools:
      return 'schools';
    case NearbyKind.kindergartens:
    case NearbyKind.playgrounds:
      return 'school_young';
    case NearbyKind.clinics:
    case NearbyKind.pharmacies:
    case NearbyKind.hospitals:
      return 'health';
    case NearbyKind.supermarkets:
      return 'convenience';
    case NearbyKind.parks:
    case NearbyKind.dogParks:
    case NearbyKind.gyms:
    case NearbyKind.pools:
      return 'park';
    case NearbyKind.synagogues:
    case NearbyKind.worship:
      return 'religious_area';
    case NearbyKind.transit:
    case NearbyKind.bikeShare:
    case NearbyKind.rail:
      return 'transit';
    case NearbyKind.nightlife:
    case NearbyKind.dining:
      return 'nightlife';
    case NearbyKind.culture:
      return 'university';
    case NearbyKind.coworking:
      return 'employment';
    case NearbyKind.airQuality:
      return 'quiet'; // clean-air proximity ≈ environmental-quality preference
    case NearbyKind.vets:
    case NearbyKind.parking:
      return null; // display-only (no ranking dimension yet)
  }
}

/// One relevant section for a given persona: what to show, filtered/ordered.
class NearbySection {
  const NearbySection(this.kind, {this.hmo = '', this.priority = 0});
  final NearbyKind kind;
  final String hmo; // clinics only: restrict to this HMO, '' = all
  final int priority; // higher = more relevant → shown first
}

// fromText runs ~40 pattern matches per call and is invoked per query/card;
// compile each CONSTANT pattern once instead of re-compiling on every call.
final Map<String, RegExp> _reCache = <String, RegExp>{};
RegExp _compile(String p) => _reCache[p] ??= RegExp(p, caseSensitive: false);

// NOTE on word boundaries: Dart's \b is ASCII-only — it treats every Hebrew
// letter as a NON-word char, so `רכב\b` never matches "רכב" at a space or
// end-of-string. Around Hebrew tokens below we therefore use explicit Hebrew+
// ASCII boundaries `(?<![\wא-ת])…(?![\wא-ת])` instead of \b (English tokens keep
// \b, which is correct for ASCII). NOTE on the definite article: `word1 ?word2`
// only allowed a space between words, so "אזור הצעיר"/"בית הספר"/"הרכבת הקלה"
// silently missed — two-word Hebrew phrases now allow an optional `ה?` prefix on
// the second word.
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
    this.pharmacy = false, // explicit "בית מרקחת"
    this.groceries = false, // wants a supermarket nearby
    this.green = false, // wants parks / green
    this.senior = false, // elderly → healthcare relevant
    this.single = false, // young single living alone
    this.couple = false, // living as a couple
    this.roommates = false, // sharing with roommates / friends
    this.active = false, // gym / fitness / sport
    this.nightlife = false, // bars / pubs / going out
    this.dining = false, // restaurants / cafés
    this.observant = false, // wants a synagogue / religious community
    this.culture = false, // museums / theatre / cinema
    this.young = false, // a young/lively AREA vibe (סביבה צעירה) — not a household
    this.transitWanted = false, // wants to be near a train / light-rail stop
    this.muslim = false, // wants a mosque / Arab community
    this.christian = false, // wants a church
    this.student = false, // student / near-campus
    this.wfh = false, // works from home
    this.luxury = false, // premium / high-end
    this.accessible = false, // wheelchair / stroller / mobility need
    this.budget = false, // price-sensitive
    this.pet = false, // pet owner
    this.quiet = false, // wants QUIET — suppresses nightlife
    this.secular = false, // explicitly secular — suppresses synagogues/worship
    this.car = false, // owns/mentions a car → parking relevant
    this.dog = false, // owns a DOG specifically → dog-parks relevant (cats don't)
  });

  final bool family, youngChild, schoolChild, teen, wantsSchools;
  final bool health, pharmacy, groceries, green, senior;
  final bool single, couple, roommates, active, nightlife, dining;
  final bool observant, culture, young, transitWanted, muslim, christian;
  final bool student, wfh, luxury, accessible, budget, pet, quiet, secular;
  final bool car, dog;
  final String hmo;

  /// A lifestyle persona (as opposed to a family/health one).
  bool get lifestyle => single || couple || roommates || student;

  /// Young/urban-lifestyle leaning — drives dining/nightlife/transit/gyms.
  bool get youngLifestyle => single || roommates || student || young;

  bool get anySignal =>
      family ||
      youngChild ||
      schoolChild ||
      teen ||
      wantsSchools ||
      health ||
      hmo.isNotEmpty ||
      pharmacy ||
      groceries ||
      green ||
      senior ||
      lifestyle ||
      active ||
      nightlife ||
      dining ||
      observant ||
      culture ||
      young ||
      transitWanted ||
      muslim ||
      christian ||
      student ||
      wfh ||
      luxury ||
      accessible ||
      budget ||
      pet ||
      car ||
      quiet || // a suppressive intent is still an explicit signal — without this,
      secular; // "דירה שקטה"/"חילוני" fell back to a stale saved persona

  /// Parse a Hebrew/English query or persona string into the signals. Mirrors the
  /// SearchIntent regexes so it stays consistent with the search engine.
  factory NearbyProfile.fromText(String raw) {
    final q = raw.toLowerCase();
    bool has(String pattern) => _compile(pattern).hasMatch(q);

    // ── everyday, colloquial Israeli Hebrew (+ common English) ────────────────
    // Regexes are deliberately loose: abbreviations (בי״ס/קופ״ח/רק״ל), slang
    // (זאטוטים, שוקק, הומה, על הפנים), chains, spelling variants, and spaced/
    // unspaced forms all resolve to the same signal.

    // Explicit "no children" negation → the family dimension is off.
    final noKids = has(
        r'בלי ילד|ללא ילד|לא רוצ\w*\s*ילד|אין ?לנו ?ילד|אין ?לי ?ילד|childless|no kids|without (kids|children)');

    final youngChild = !noKids &&
        has(r'תינוק|תינוקת|פעוט|פעוטה|פעוטות|זאטוט|גיל הרך|גני?\s*ילד|גנון|מעון|פעוטון|'
            r'גן ?חובה|גן ?טרום|טרום ?חובה|צהרון|לגן|בגן|מחפש\w* ?גן|בייבי|toddler|baby|preschool|kindergarten|nursery|daycare');
    final teen = !noKids &&
        has(r'תיכון|מתבגר|בגרות|נוער|בני ?נוער|בן ?נוער|teen|high ?school|adolescent');
    final schoolChild = !noKids &&
        has(r'בית ?ה?ספר|בתי ?ה?ספר|בי[״"׳]?ס|ביה[״"׳]?ס|יסודי|חטיב|תלמיד|כיתה ?[א-ו]|בכיתה|'
            r'elementary|middle ?school|grade ?school|primary school');
    // Broad family/kids signal — many everyday ways to say it.
    final family = !noKids &&
        (youngChild ||
            teen ||
            schoolChild ||
            has(r'משפח|ילד|ילדה|ילדות|ילדים|הקטנים|הקטנטנ|טף|חמד|בהריון|בהיריון|הריון|'
                r'אמא|אבא|הורה|הורים|family|kids?|child(ren)?|parent'));

    // HMO — disambiguate the fund names (Leumit vs "דתי לאומי", Maccabi the club,
    // Meuhedet the political list) and cover casual spellings.
    final religiousNational = has(r'דת[יה]?ת?[ \-]?לאומ|לאומ[יה]?ת?[ \-]?דת');
    final maccabiSport = has(r'כדורגל|כדורסל|אצטדיון|קבוצת|הפועל|יורוליג|אוהד');
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
        has(r'בית ?ה?חולים|בתי ?ה?חולים|קופת ?ה?חולים|קופ[״"׳]?ח|קופ(?![\wא-ת])|מרפא\w*|'
            r'רופא|רופאה|בריאות|בריאותי|רפואה|רפואי|חולה|מחלה|טיפול\w* ?רפואי|'
            r'clinic|hospital|medical|health|doctor|pediatric|checkup');

    // Living arrangement. "חברים" alone is too broad → roommates needs a sharing
    // cue; "זוג" excludes "זוג נעליים/גרביים"; bare "לבד" excluded on negation.
    final roommates = has(
        r'שותפ|רומיז|roomies|flatmate|roommate|share\s?(a|an|the)?\s?(flat|apartment|place)|'
        r'דירת ?שותפים|לגור עם ?חבר|גרים ?ביחד|גרים ?יחד|כמה ?חבר|קומונה');
    final couple = has(
        r'זוג(?!\s*(נעל|גרב|מגפ|כפכף|גורב))|זוגי|זוגיות|בזוגיות|בן ?ה?זוג|בת ?ה?זוג|בני ?ה?זוג|'
        r'נשוי|נשואה|נשואים|החבר ?שלי|החברה ?שלי|אני ?ו(ה)?חבר|שנינו|couple|partner|spouse|'
        r'married|boyfriend|girlfriend|two of us');
    final single = !couple &&
        !roommates &&
        has(r'רווק|רווקה|לגור ?לבד|גר ?לבד|גרה ?לבד|גר ?לבדי|מחפש ?לבד|לבד ?בדירה|פנוי(?![\wא-ת])|פנויה(?![\wא-ת])|'
            r'\bsolo\b|\bsingle\b|living alone|on my own|by myself|young professional');

    final active = has(
        r'חדר\w* ?ה?כושר|כושר|חדכ(?![\wא-ת])|ספורט|ספורטיב|אימון|להתאמן|מתאמן|ריצה|לרוץ|'
        r'יוגה|פילאטיס|קרוספיט|חוג ?ספורט|gym|fitness|workout|crossfit|running|yoga|pilates');
    final quiet = has(
        r'שקט|שקטה|שקטים|רגוע|רגועה|נינוח|פסטורל|שליו|שלווה|בלי ?רעש|ללא ?רעש|רחוק ?מרעש|'
        r'רחוק ?מכביש|לא ?רועש|quiet|calm|peaceful|tranquil|serene');
    final nightlife = !quiet &&
        has(r'חיי ?ה?לילה|בילוי|בילויים|לבלות|לצאת ?בערב|יציאות|לצאת ?בלילה|ברים|(?<![\wא-ת])בר(?![\wא-ת])|פאב|'
            r'מועדון|מסיבו?ת|לרקוד|סצנה|ליינות|nightlife|bars?|pubs?|club(bing|s)?|party|going out');
    final dining = has(
        r'מסעד\w*|בית ?ה?קפה|בתי ?ה?קפה|(?<![\wא-ת])קפה(?![\wא-ת])|בתי ?ה?אוכל|לאכול ?בחוץ|אוכל ?טוב|אוכל ?בא[יי]?זור|'
        r'קולינר|שף|restaurant|cafe|café|dining|foodie|eat ?out|good ?food');
    final pharmacy = has(
        r'בית ?ה?מרקחת|בתי ?ה?מרקחת|מרקחת|תרופות|סופר ?פארם|סופרפארם|ניו ?פארם|be ?drug|'
        r'pharmacy|drugstore|super.?pharm');

    // Explicitly secular → do NOT surface synagogues/mosques/churches.
    final secular = has(r'חילוני|חילונית|חילונים|לא ?דתי|לא ?שומר\w* ?שבת|secular|non.?religious');
    // Observant (Jewish). Guarded by !secular so "חילוני" wins.
    final observant = !secular &&
        (religiousNational ||
            has(r'בית ?ה?כנסת|בתי ?ה?כנסת|מניין|מנין|שומר\w* ?שבת|שומר\w* ?מצוות|כיפה|ציצית|'
                r'דתי|דתייה|דתיה|דתיים|חרד|מסורתי|כשר|כשרות|מקווה|עירוב|ישיבה|אולפנה|'
                r'shul|synagogue|kosher|observant|religious|\bdati\b|haredi|orthodox jew'));
    final culture = has(
        r'תרבות|מוזיאון|מוזאון|תיאטרון|תאטרון|קולנוע|סרטים|אמנות|גלריה|מתנ[״"׳]?ס|מתנס|'
        r'ספרי[יה]|מופע|הצג\w*|קונצרט|culture|museum|theatre|theater|cinema|gallery|arts');
    // Young/lively AREA vibe — daily-life + going-out even without a household type.
    final young = has(
        r'סביבה ?ה?צעיר|א[יי]?זור ?ה?צעיר|שכונה ?ה?צעיר|מקום ?ה?צעיר|קהל ?ה?צעיר|הרבה ?צעירים|צעירים ?בא[יי]?זור|'
        r'תוסס|תוססת|שוקק|הומה ?אדם|אנרגטי|בוהמיינ|בוהמי|היפסטר|טרנדי|היפ(?![\wא-ת])|'
        r'young (area|crowd|neighborhood|vibe)|hipster|trendy|vibrant|lively');
    final transitWanted = has(
        r'תחבורה ?ציבורית|תחבורה(?![\wא-ת])|קרוב ל?ה?רכבת|ליד ?ה?רכבת|רכבת ?ה?קלה|רק[״"׳]?ל|רקל(?![\wא-ת])|'
        r'קו ?אדום|קו ?סגול|מטרו|אוטובוס|תחנת ?ה?רכבת|תחנת ?ה?אוטובוס|בלי ?רכב|בלי ?אוטו|'
        r'אין ?לי ?רכב|אין ?לי ?אוטו|לא ?נוהג|ללא ?רכב|train|\bbus\b|light.?rail|metro|public transport|car.?free');
    final muslim = has(
        r'מסגד|מוסלמ|ערבי(?![\wא-ת])|ערבית|ערבים|מגזר ?ערבי|כפר ?ערבי|יישוב ?ערבי|mosque|muslim|arab');
    final christian = has(r'כנסי[יה]|נוצר[יי]|christian|church');

    final student = has(
        r'סטודנט|סטודנטית|סטודנטים|אוניברסיט|מכללה|מכללת|קמפוס|לומד\w* ?תואר|תואר ?ראשון|'
        r'student|university|college|campus');
    final wfh = has(
        r'עבוד\w* ?מהבית|עובד\w* ?מהבית|מהבית(?![\wא-ת])|מה ?בית|רימוט|פרילנס|עצמאי|חדר ?ה?עבודה|'
        r'\bwfh\b|work ?from ?home|remote ?work|home ?office|freelanc');
    final luxury = has(
        r'יוקר|יוקרתי|מפואר|פאר|פרימיום|איכותי|יקר(?![\wא-ת])|וילה|פנטהאוז|פנטהאוס|דופלקס ?יוקרה|'
        r'luxur|premium|penthouse|high.?end|upscale');
    final accessible = has(
        r'נגיש|נגישות|כיסא ?גלגלים|כסא ?גלגלים|מוגבל|מוגבלות|(?<![\wא-ת])נכה(?![\wא-ת])|נכות|עגלה|'
        r'בלי ?מדרגות|ללא ?מדרגות|צריך ?מעלית|חייב\w* ?מעלית|wheelchair|accessible|step.?free|mobility');
    final budget = has(
        r'זול(?![\wא-ת])|זולה|בזול|תקציב ?נמוך|תקציב ?מוגבל|מוגבל\w* ?בתקציב|חסכ|לא ?יקר|מחיר ?טוב|'
        r'משתלם|במחיר ?שפוי|budget|cheap|affordable|inexpensive|low ?cost');
    final pet = has(
        r'כלב|כלבה|כלבלב|חתול|חתולה|חיית ?מחמד|בעל ?חיים|בע[״"׳]?ח|\bdog\b|\bcat\b|\bpet\b');
    // A DOG specifically → dog-parks are relevant; a cat owner should not see them.
    final dog = has(r'כלב|כלבה|כלבלב|\bdog\b');
    // Owns / mentions a car → parking matters. Suppressed ONLY when the user is
    // explicitly car-free — NOT merely because they also want public transport
    // (wanting a train ≠ owning no car; "ליד הרכבת עם חנייה" needs BOTH).
    final carFree = has(
        r'בלי ?רכב|בלי ?אוטו|אין ?לי ?רכב|אין ?לי ?אוטו|ללא ?רכב|לא ?נוהג|car.?free|without ?a? ?car');
    final car = !carFree &&
        has(r'חני[יה]|מקום ?ה?חני|רכב(?![\wא-ת])|אוטו(?![\wא-ת])|מכונית|נהג\w*|\bcar\b|parking|garage');

    return NearbyProfile(
      family: family,
      youngChild: youngChild,
      schoolChild: schoolChild,
      teen: teen,
      wantsSchools: has(
          r'בית ?ה?ספר|בתי ?ה?ספר|בי[״"׳]?ס|מוסדות ?חינוך|חינוך ?טוב|בתי ?ה?ספר ?ה?טוב|good ?schools?'),
      health: health,
      hmo: hmo,
      pharmacy: pharmacy,
      single: single,
      couple: couple,
      roommates: roommates,
      active: active,
      nightlife: nightlife,
      dining: dining,
      observant: observant,
      culture: culture,
      young: young,
      transitWanted: transitWanted,
      muslim: muslim,
      christian: christian,
      student: student,
      wfh: wfh,
      luxury: luxury,
      accessible: accessible,
      budget: budget,
      pet: pet,
      quiet: quiet,
      secular: secular,
      car: car,
      dog: dog,
      groceries: has(
          r'סופר(?![\wא-ת])|סופרמרקט|סופר ?מרקט|מכולת|פיצוצי|מרכול|קניות|מצרכים|מרכז ?ה?קניות|קניון|'
          r'שופרסל|רמי ?לוי|ויקטורי|יינות ?ביתן|אושר ?עד|טיב ?טעם|מגה(?![\wא-ת])|מחסני ?השוק|יוחננוף|'
          r'חצי ?חינם|קופיקס|am:?pm|ampm|supermarket|grocer|groceries|errands|shopping'),
      green: has(r'פארק|גינה|גינות|שטח ?ה?ירוק|הרבה ?ירוק|ירוק(?![\wא-ת])|טבע|טיילת|park|garden|green|nature'),
      senior: has(
          r'מבוגר|מבוגרת|מבוגרים|קשיש|גמלא|פנסיונ|פנסי|בגיל ?השלישי|סבא|סבתא|'
          r'זוג ?מבוגר|senior|elderly|retire|pensioner'),
    );
  }
}

/// Decide which nearby sections are RELEVANT to [p], ordered most-relevant first.
/// Strict: a section appears only when the persona actually implies a need for
/// it (an empty result → the whole card hides, which is the intended behaviour
/// for a query with no lifestyle signal).
List<NearbySection> relevantNearbySections(NearbyProfile p) {
  final s = <NearbySection>[];
  void add(NearbyKind k, int prio, {String hmo = ''}) =>
      s.add(NearbySection(k, hmo: hmo, priority: prio));

  final youngL = p.youngLifestyle; // single/roommates/student/young-area

  // ── children & education ──────────────────────────────────────────────────
  // A household WITH KIDS is family-first: education/kids sections must lead,
  // ABOVE any couple/lifestyle dining — a couple who mentioned a child is looking
  // for schools & kindergartens, not restaurants (the bug this fixes).
  if (p.youngChild) {
    add(NearbyKind.kindergartens, 95);
  } else if (p.family && !p.schoolChild && !p.teen && !p.wantsSchools) {
    add(NearbyKind.kindergartens, 75);
  }
  if (p.schoolChild || p.teen || p.wantsSchools) {
    add(NearbyKind.schools, (p.teen || p.schoolChild) ? 95 : 85);
  } else if (p.family && !p.youngChild) {
    add(NearbyKind.schools, 78);
  }
  if (p.youngChild) {
    add(NearbyKind.playgrounds, 92);
  } else if (p.family) {
    add(NearbyKind.playgrounds, 70);
  }

  // ── health (clinics / pharmacies / hospitals) ─────────────────────────────
  if (p.health || p.hmo.isNotEmpty || p.senior || p.accessible || p.family) {
    add(NearbyKind.clinics,
        p.hmo.isNotEmpty
            ? 90
            : (p.senior ? 80 : (p.health ? 75 : (p.accessible ? 72 : 58))),
        hmo: p.hmo);
  }
  if (p.pharmacy || p.health || p.senior || p.accessible || p.family) {
    add(NearbyKind.pharmacies,
        p.pharmacy ? 88 : (p.senior ? 78 : (p.health ? 72 : (p.accessible ? 70 : 56))));
  }
  if (p.health || p.senior || p.accessible || p.family) {
    add(NearbyKind.hospitals,
        p.senior ? 74 : (p.health ? 70 : (p.accessible ? 68 : 46)));
  }

  // ── daily life (supermarkets / parks) ─────────────────────────────────────
  if (p.groceries) {
    add(NearbyKind.supermarkets, 85);
  } else if (youngL || p.budget || p.couple || p.family) {
    add(NearbyKind.supermarkets, 52);
  }
  if (p.green) {
    add(NearbyKind.parks, 80);
  } else if (p.family) {
    add(NearbyKind.parks, 55);
  } else if (p.pet) {
    add(NearbyKind.parks, 56);
  } else if (p.couple) {
    add(NearbyKind.parks, 50);
  } else if (p.young || p.wfh) {
    add(NearbyKind.parks, 52);
  }

  // ── going out & lifestyle (dining / gyms / nightlife / culture) ───────────
  if (p.dining) {
    add(NearbyKind.dining, 86);
  } else if (p.lifestyle && !p.family && !p.senior) {
    // Lifestyle dining leads only for a household with NO kids AND NOT elderly — a
    // young couple/single/roommate. A family OR a senior that also reads as a
    // couple gets a minor dining chip BELOW its education / health sections
    // (handled just below), never above them.
    add(NearbyKind.dining, p.couple ? 84 : (p.student ? 74 : 80));
  } else if (p.young) {
    add(NearbyKind.dining, 76);
  } else if (p.luxury) {
    add(NearbyKind.dining, 66);
  } else if (p.wfh) {
    add(NearbyKind.dining, 60); // WFH → cafés to work from
  } else if ((p.family || p.senior) && p.couple) {
    add(NearbyKind.dining, 48); // family/senior couple: a small extra, below the essentials
  }
  if (p.active) {
    add(NearbyKind.gyms, 82);
  } else if ((youngL || p.couple) && !p.family && !p.senior) {
    add(NearbyKind.gyms, 64);
  } else if (p.luxury || p.wfh) {
    add(NearbyKind.gyms, 58);
  }
  // Nightlife/bars — a young household (single/roommates/student/young-area) AND a
  // childless couple want going-out spots nearby; suppressed for a quiet-seeker or
  // a family/senior. (A couple who mentioned kids reads as family and is excluded.)
  if (p.nightlife) {
    add(NearbyKind.nightlife, 83);
  } else if (!p.quiet &&
      !p.family &&
      !p.senior &&
      (p.single || p.roommates || p.student || p.young || p.couple)) {
    add(NearbyKind.nightlife, p.couple ? 62 : 66);
  }
  if (p.culture) {
    add(NearbyKind.culture, 82);
  } else if (p.luxury) {
    add(NearbyKind.culture, 58);
  } else if (p.couple || p.family) {
    add(NearbyKind.culture, 48);
  } else if (p.single || p.student) {
    add(NearbyKind.culture, 46);
  }

  // ── community & faith ─────────────────────────────────────────────────────
  // Synagogues ONLY for an observant seeker — a non-religious family is NOT shown
  // shuls (a hard suppression rule). Mosques/churches only on their signal.
  if (p.observant) add(NearbyKind.synagogues, 90);
  if (p.muslim || p.christian) add(NearbyKind.worship, 90);

  // ── mobility (transit / bike-share / parking) ─────────────────────────────
  if (p.transitWanted) {
    add(NearbyKind.transit, 88);
    add(NearbyKind.rail, 84); // heavy-rail stations — the commuter's anchor
  } else if (youngL || p.couple || p.budget) {
    add(NearbyKind.transit, 62);
    add(NearbyKind.rail, 58);
  }
  // Clean-air signal matters most to families with kids and health-focused
  // seekers — surface the monitoring layer for them.
  if (p.youngChild || p.schoolChild || p.health) {
    add(NearbyKind.airQuality, 45);
  }

  if (p.transitWanted) {
    add(NearbyKind.bikeShare, 68);
  } else if (youngL || p.couple || p.active) {
    add(NearbyKind.bikeShare, 56);
  }
  if (p.car) {
    add(NearbyKind.parking, 82);
  } else if (p.luxury) {
    add(NearbyKind.parking, 50);
  }

  // ── active & pets & work ──────────────────────────────────────────────────
  if (p.active) {
    add(NearbyKind.pools, 78);
  } else if (p.family) {
    add(NearbyKind.pools, 58); // kids' swimming / sports
  } else if (p.young) {
    add(NearbyKind.pools, 46);
  }
  if (p.dog) add(NearbyKind.dogParks, 88); // dog owners only, not cat owners
  if (p.pet) add(NearbyKind.vets, 80); // any pet → a vet is relevant
  if (p.wfh) {
    add(NearbyKind.coworking, 85);
  } else if (p.student) {
    add(NearbyKind.coworking, 60);
  } else if (p.single) {
    add(NearbyKind.coworking, 46);
  }

  // Sort by priority desc; break ties by the enum's declaration order so the
  // output is DETERMINISTIC (Dart's List.sort is not guaranteed stable, which
  // would otherwise let equal-priority sections shuffle between runs).
  s.sort((a, b) {
    final byPrio = b.priority.compareTo(a.priority);
    return byPrio != 0 ? byPrio : a.kind.index.compareTo(b.kind.index);
  });
  return s;
}

/// ALL nearby section kinds, with the persona-relevant ones first (by priority)
/// and the rest appended in a sensible default order. Used on the property
/// detail screen, which is a full reference — every nearby school/kindergarten/
/// clinic/supermarket/park should be browsable — while the chat "why this one"
/// summary uses [relevantNearbySections] (only what matters to the seeker).
List<NearbySection> orderedNearbySections(NearbyProfile p) {
  final relevant = relevantNearbySections(p);
  final have = relevant.map((s) => s.kind).toSet();
  const fallbackOrder = [
    NearbyKind.schools,
    NearbyKind.kindergartens,
    NearbyKind.clinics,
    NearbyKind.pharmacies,
    NearbyKind.supermarkets,
    NearbyKind.parks,
    NearbyKind.playgrounds,
    NearbyKind.hospitals,
    NearbyKind.transit,
    NearbyKind.rail,
    NearbyKind.synagogues,
    NearbyKind.worship,
    NearbyKind.culture,
    NearbyKind.dining,
    NearbyKind.gyms,
    NearbyKind.pools,
    NearbyKind.nightlife,
    NearbyKind.coworking,
    NearbyKind.bikeShare,
    NearbyKind.parking,
    NearbyKind.dogParks,
    NearbyKind.vets,
    NearbyKind.airQuality,
  ];
  // HARD suppressions carry over to the full-reference list too: an explicitly
  // secular seeker is never shown synagogues/mosques/churches even in the
  // browse-all fallback (the relevant-list rule at [relevantNearbySections]
  // would otherwise be silently undone here).
  bool suppressed(NearbyKind k) =>
      p.secular &&
      (k == NearbyKind.synagogues || k == NearbyKind.worship);

  return [
    ...relevant,
    for (final k in fallbackOrder)
      if (!have.contains(k) && !suppressed(k))
        // clinics with no persona HMO → show all funds (hmo: '').
        NearbySection(k, hmo: '', priority: 0),
  ];
}
