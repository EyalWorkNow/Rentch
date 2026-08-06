/// SEARCH INTENT — the single, shared contract for lifestyle/spatial intent.
///
/// Historically each intent ("קרוב לים", "מרכזי", "שקט"…) was detected by a regex
/// buried inside the preference model, and the voice assistant couldn't speak the
/// same language. This centralises it: text → a set of canonical intent keys.
/// BOTH the typed search (SmartSearch) and the voice assistant fill
/// `SearchQuery.intents` from here, and the ranking engine + gates CONSUME the
/// keys — never re-parsing free text. Add an intent once, everyone gets it.
class SearchIntent {
  const SearchIntent._();

  // Canonical intent keys.
  static const nearSea = 'near_sea';
  static const nightlife = 'nightlife';
  static const quiet = 'quiet';
  static const central = 'central';
  static const spacious = 'spacious';
  static const compact = 'compact'; // wants a SMALL flat (downsizer / low-maintenance)
  static const accessible = 'accessible';
  static const luxury = 'luxury';
  static const view = 'view';
  static const student = 'student';
  static const nearUniversity = 'near_university';
  static const investment = 'investment';
  static const roommates = 'roommates';
  /// Household shape — a young person living ALONE, or a couple. These sharpen
  /// lifestyle ranking dimensions (centrality, young/lively area, transit) so the
  /// persona actually reorders results, not just the nearby-places card.
  static const single = 'single';
  static const couple = 'couple';
  static const wfh = 'wfh';
  static const goodSchools = 'good_schools';
  static const qualityArea = 'quality_area';

  // Map-data-backed neighbourhood intents (each sharpens a GovData dimension:
  // safety→police crime, transit→transit grid+rail, green→park, health→health
  // facilities, youngPop→CBS young-adult share).
  static const safety = 'safety';
  static const transit = 'transit';
  static const green = 'green';
  static const health = 'health';
  static const youngPop = 'young_pop';
  static const convenience = 'convenience';
  static const growth = 'growth';
  static const employment = 'employment';
  static const lowFloor = 'low_floor';

  /// The seeker wants a religiously-observant community (חרדי / דתי-לאומי) or a
  /// place near a synagogue → prefer known religious localities/neighbourhoods.
  static const religiousArea = 'religious_area';

  /// Age of the kids → which school type matters: young → גן/יסודי, teens → תיכון.
  static const youngChildren = 'young_children';
  static const teens = 'teens';

  /// "אזור X" (as opposed to the city X itself) — the user wants X PLUS its
  /// adjacent settlements, so the city gate widens to the neighbouring towns.
  static const cityArea = 'city_area';

  /// "לא רחוק מהים" ("not far from the sea") means strictly under this — 4km
  /// is NOT "not far". The single definition; the near-sea gate in
  /// RecommendationOrchestrator consumes this rather than a local constant.
  static const double notFarFromSeaKm = 4.0;

  static final Map<String, RegExp> _patterns = {
    // NB: "לים" must be a WORD ("קרוב לים"), not a suffix — otherwise "גלגלים"
    // (as in "כיסא גלגלים"/wheelchair) false-matches and sea-gates the search.
    nearSea: RegExp(r'הים|(?<=\s)לים|חוף|ליד המים|beach|seaside|seafront', caseSensitive: false),
    nightlife: RegExp(
        r'נייטלייף|חיי ?ה?לילה|בילוי|לבלות|מקום לבלות|(?<![\wא-ת])בר(?![\wא-ת])|ברים|פאב|פאבים|מועדון|'
        r'מסעד|בית ?ה?קפה|בתי ?ה?קפה|תוסס|תוססת|בוהמיינ|בוהמי|היפסטר|אמנותי|סצנה|'
        r'אזור ?ה?צעיר|שכונה ?ה?צעיר|מקום ?ה?צעיר|צעיר ותוסס|'
        r'nightlife|bars|pubs|clubs|hipster|trendy|bohemian',
        caseSensitive: false),
    quiet: RegExp(
        r'שקט|שקטה|רגוע|רגועה|שלוו|שליו|פסטורל|מבוגר|גמלא|פנסי|קשיש|'
        r'בלי רעש|ללא רעש|רחוק מרעש|נטול רעש|רחוק מכביש|רחוק מהרעש|'
        r'retire|quiet|calm|peaceful|tranquil',
        caseSensitive: false),
    central: RegExp(
        r'מרכזי|מרכזית|מרכז ?ה?עיר|לב ?ה?עיר|במרכז|סנטר|אזור ?ה?עסקים|מרכז ?ה?עסקים|'
        r'מגדלי משרדים|central|downtown|business district',
        caseSensitive: false),
    spacious: RegExp(r'מרווח|מרווחת|מרווחים|מרווחות|חדרים גדולים|גדולה מאוד|spacious',
        caseSensitive: false),
    // Small on purpose — a downsizer / low-maintenance seeker. Guarded phrases so
    // a bare "קטן" (or "לא קטנה") doesn't false-fire.
    compact: RegExp(
        r'דירה קטנה|קטנטנה|קומפקט|להקטין|מקטינ|קן ריק|downsiz|empty.?nest|compact',
        caseSensitive: false),
    accessible: RegExp(
        r'נגיש|נגישות|כיסא גלגלים|כסא גלגלים|מוגבלות|נכה|עגלה|wheelchair|accessible|step.?free',
        caseSensitive: false),
    luxury: RegExp(r'יוקר|מפואר|פרימיום|luxur|penthouse|פנטהאוז', caseSensitive: false),
    view: RegExp(r'נוף|קומה גבוה|פנטהאוז|view|penthouse', caseSensitive: false),
    lowFloor: RegExp(
        r'קומה נמוכה|קומת קרקע|קומה ראשונה|קומה שנייה|קומה שניה|בלי מדרגות|'
        r'ללא מדרגות|קרוב לכניסה|low floor|ground floor',
        caseSensitive: false),
    student: RegExp(r'סטודנט|סטודנטית|קמפוס|מכלל|student|campus', caseSensitive: false),
    nearUniversity:
        RegExp(r'אוניברסיט|קמפוס|מכלל|university|campus', caseSensitive: false),
    investment: RegExp(r'השקע|תשוא|invest|yield|rental income', caseSensitive: false),
    roommates: RegExp(r'שותפ|שותפות|roommate|flatmate', caseSensitive: false),
    // Detect the "living ALONE" INTENT via explicit phrasings, NOT a bare "לבד"
    // (which false-matches "לא לבד" / "פחד להיות לבד" — the _negator only covers
    // בלי/ללא/לא-ליד, not a bare לא). Stricter than NearbyProfile on purpose: this
    // one moves the ranking, so a false positive has a real cost.
    single: RegExp(
        r'רווק|רווקה|לגור לבד|גר לבד|גרה לבד|גר לבדי|מחפש לבד|לבד בדירה|'
        r'\bsolo\b|\bsingle\b|living alone|on my own|by myself|young professional',
        caseSensitive: false),
    couple: RegExp(
        // Guard bare "זוג" against "זוג נעליים/גרביים/מגפיים…" (a PAIR of X),
        // matching the guard in NearbyProfile.fromText.
        r'זוג(?!\s*(נעל|גרב|מגפ|כפכף|גורב))|זוגי|בן ?ה?זוג|בת ?ה?זוג|בני ?ה?זוג|בזוגיות|נשואים טריים|'
        r'couple|partner|spouse|two of us|newlywed',
        caseSensitive: false),
    wfh: RegExp(
        r'עבודה מהבית|עובד מהבית|עובדת מהבית|חדר ?ה?עבודה|מהבית|רימוט|remote|wfh|work from home',
        caseSensitive: false),
    goodSchools: RegExp(r'בתי ?ה?ספר|בית ?ה?ספר|חינוך|מוסדות ?ה?חינוך|schools?',
        caseSensitive: false),
    qualityArea: RegExp(
        r'שכונה ?ה?טובה|אזור ?ה?טוב|אזור ?ה?איכותי|אזור ?ה?יוקרתי|שכונה ?ה?יוקרתית|שכונה ?ה?שקטה|'
        r'מטופח|מטופחת|אזור ?ה?מבוקש|שכונה ?ה?מבוקש|מבוקשת|נחשב|נחשבת|שכונה ?בעלייה|'
        r'בעלייה|אזור ?ה?מתפתח|מתפתח|מתפתחת|מתחדש|מתחדשת|שכונה ?ה?נקייה|אזור ?ה?נקי|'
        r'good area|nice area|prime|up.and.coming|sought.after',
        caseSensitive: false),
    safety: RegExp(
        r'בטוח|בטוחה|בטיחות|לא מסוכן|לא מסוכנת|בלי פשיעה|ללא פשיעה|פשיעה נמוכה|'
        r'ללא אלימות|בלי אלימות|safe|low.crime|secure',
        caseSensitive: false),
    transit: RegExp(
        r'תחבורה ציבורית|קרוב לתחבורה|נגיש לתחבורה|קרוב ל?ה?רכבת|ליד ?ה?רכבת|תחנת ?ה?רכבת|'
        r'רכבת ?ה?קלה|קו אדום|קו סגול|מטרו|קרוב ל?ה?אוטובוס|ליד ?ה?אוטובוס|תחנת ?ה?אוטובוס|'
        r'קרוב ל?ה?תחנה|public transport|near.*train|metro|light.rail|\bbus\b|transit|'
        r'near transit|well.connected',
        caseSensitive: false),
    employment: RegExp(
        r'קרוב לעבודה|ליד ?ה?עבודה|קרוב למקום ?ה?עבודה|אזור ?ה?תעסוקה|אזור ?ה?תעשייה|'
        r'הייטק|היי[- ]?טק|פארק ?ה?הייטק|קרוב ל?ה?משרדים|ליד ?ה?משרדים|מרכז ?ה?עסקים|'
        r'אזור ?ה?עסקים|קרוב לאזור ?ה?תעשייה|near work|close to work|tech park|'
        r'business district|job hub|employment',
        caseSensitive: false),
    green: RegExp(
        r'אזור ?ה?ירוק|הרבה ירוק|הרבה גינות|גינות|גינה ?ה?ציבורית|פארק|קרוב לפארק|'
        r'גן ?ה?ציבורי|גנים ציבוריים|שטח ?ה?פתוח|אזור ?ה?פתוח|טבע|ריאות ירוקות|אוויר נקי|'
        r'green|park|garden',
        caseSensitive: false),
    health: RegExp(
        r'בית ?ה?חולים|קופת ?ה?חולים|מרפאה|קרוב לרפואה|שירותי בריאות|קרוב לבריאות|'
        r'clinic|hospital|medical',
        caseSensitive: false),
    youngPop: RegExp(
        r'אזור ?ה?צעיר|סביבה ?ה?צעיר|שכונה ?ה?צעיר|מקום ?ה?צעיר|אוכלוס\S* צעיר|'
        r'אזור של צעירים|קהל ?ה?צעיר|הרבה צעירים|young (area|crowd|people|vibe)',
        caseSensitive: false),
    convenience: RegExp(
        r'ליד ?ה?סופר|קרוב ל?ה?סופר|סופרמרקט|ליד ?ה?מכולת|מרכז ?ה?קניות|מרכזי ?ה?קניות|קניון|'
        r'קרוב לקניות|ליד מרכז ?ה?מסחרי|מרכז ?ה?מסחרי|קרוב לחנויות|ליד ?ה?חנויות|'
        r'supermarket|grocer|shopping|\bmall\b|errands',
        caseSensitive: false),
    growth: RegExp(
        r'פוטנציאל|פוטנציאל השבחה|השבחה|פינוי בינוי|פינוי[- ]?בינוי|תמ[״"]?א|'
        r'התחדשות עירונית|אזור ?ה?מתפתח|בעלייה|לפני עלייה|קרוב למטרו|מטרו עתידי|'
        r'קו מטרו|רכבת ?ה?קלה עתידית|רק[״"]?ל עתיד|ערך עתידי|appreciation|upside|'
        r'up.and.coming|future (metro|value)|urban renewal',
        caseSensitive: false),
    religiousArea: RegExp(
        r'דתי|דתיה|דתיים|חרדי|חרדית|חרדים|שומר שבת|שומרי שבת|בית ?ה?כנסת|בתי ?ה?כנסת|'
        r'קהילה ?ה?דתית|אזור ?ה?דתי|שכונה ?ה?דתית|מסורתי|מסורתית|כשר|מקווה|עירוב|ישיבה|אולפנה|תלמוד תורה|'
        r'religious|synagogue|kosher|haredi|observant',
        caseSensitive: false),
  };

  static final RegExp _negator =
      RegExp(r'(בלי|ללא|לא ליד|לא רוצה|לא צריך|לא מעוניין|without|no)\s*$');

  /// True if the intent keyword at [matchStart] is preceded (within ~14 chars) by
  /// a negation like "בלי" / "לא" — so we don't add the opposite intent.
  static bool _isNegated(String text, int matchStart) {
    final from = matchStart - 14 < 0 ? 0 : matchStart - 14;
    return _negator.hasMatch(text.substring(from, matchStart));
  }

  /// The set of intents present in [text]. Elderly/retiree phrasing implies both
  /// quiet and accessibility; a student implies being near a campus.
  static Set<String> fromText(String text) {
    if (text.trim().isEmpty) return <String>{};
    // Normalize the common "איזור" (with yud) → "אזור" spelling ONCE so every
    // pattern below stays simple. All matching/negation runs on this normalized
    // string, so match offsets stay internally consistent.
    text = text.replaceAll('איזור', 'אזור');
    final out = <String>{};
    for (final e in _patterns.entries) {
      final m = e.value.firstMatch(text);
      // Honour NEGATION: "בלי קומה גבוהה" / "לא ליד הים" must NOT add the intent
      // (previously it flipped meaning and added view / near_sea).
      if (m != null && !_isNegated(text, m.start)) out.add(e.key);
    }
    // ── Phase 2: life-stage inference ──────────────────────────────────────
    // A real agent reads a SINGLE cue about who the seeker is and fills in the
    // whole bundle of priorities that life-stage implies — even when the seeker
    // didn't spell each one out.
    //
    // Empty-nesters DOWNSIZING ("הילדים עזבו") — text mentions "ילדים" but they
    // want the OPPOSITE of a family flat. Treat like a quiet/accessible downsizer,
    // never schools/space.
    final emptyNest = RegExp(r'הילדים עזבו|הילדים גדלו|אחרי שהילדים|קן ריק|'
            r'נשארנו לבד|הבית התרוקן|דירה קטנה יותר|empty nest')
        .hasMatch(text);
    // Family / kids / a baby on the way → schools, a quiet & good area, and space.
    if (!emptyNest &&
        RegExp(r'משפח|ילד|תינוק|בהריון|הריון|פעוט|בייבי|family|kids|child|baby')
            .hasMatch(text)) {
      out..add(goodSchools)..add(quiet)..add(spacious)..add(qualityArea);
    }
    if (emptyNest) {
      out..add(quiet)..add(accessible);
    }
    // Age of the kids picks the relevant school type (only for a real family).
    if (!emptyNest) {
      if (RegExp(r'תינוק|פעוט|רך נולד|בהריון|הריון|גן ?ה?ילדים|ילד ?ה?קטן|'
              r'ילדים ?ה?קטנים|בייבי|baby|toddler')
          .hasMatch(text)) {
        out.add(youngChildren);
      }
      if (RegExp(r'מתבגר|מתבגרת|מתבגרים|נוער|גיל העשרה|בני ?ה?נוער|תיכון|teen')
          .hasMatch(text)) {
        out.add(teens);
      }
    }
    // Retiree / elderly → step-free access + a quiet area. Includes a stated
    // numeric age of 65+ ("אני בן 74") — the person, not a building (a building's
    // age reads as "בניין בן N שנה", which this doesn't match).
    final elderlyAge = RegExp(r'(?:בן|בת|גיל)\s*(6[5-9]|[7-9]\d|1\d\d)\b')
        .hasMatch(text) &&
        !RegExp(r'בניין|בית|מבנה|נכס').hasMatch(text);
    if (elderlyAge ||
        RegExp(r'מבוגר|גמלא|פנסי|קשיש|בגיל השלישי|retire|senior|elderly')
            .hasMatch(text)) {
      out..add(accessible)..add(quiet);
    }
    // Wanting the ABSENCE of noise = wanting QUIET (a negation that ADDS an intent
    // rather than cancelling one — "לא באזור רועש" / "בלי רעש" / "רחוק מכביש").
    // Only the explicit AVOID-noise phrasings add quiet — NOT a bare "רועש",
    // which may be dismissive ("לא משנה אם קצת רועש" = doesn't mind noise).
    if (RegExp(r'בלי רעש|ללא רעש|לא רוצה רעש|לא רועש|לא באזור רועש|לא בסביבה רועש|'
            r'רחוק מרעש|רחוק מכביש|נטול רעש|no noise|away from.*(road|highway)')
        .hasMatch(text)) {
      out.add(quiet);
    }
    // Avoiding a HIGH floor = wanting a LOW one ("לא קומה גבוהה" / "בלי קומה גבוהה").
    if (RegExp(r'(?:לא|בלי|ללא)\s*קומה גבוה').hasMatch(text)) {
      out
        ..add(lowFloor)
        ..remove(view); // the negated "קומה גבוהה" must not also add view
    }
    // Young couple → they lean central/lively.
    if (RegExp(r'זוג צעיר|זוג|בני זוג|נשואים טריים|couple|newlywed')
        .hasMatch(text)) {
      out.add(central);
    }
    // Olim / anglo (English-speaking) seekers — a distinct Israeli factor: they
    // cluster in established, community-oriented areas with good (often English-
    // friendly) schools. Without a dedicated anglo-area feed we map to the closest
    // proxies the model already scores: a quality area + schools.
    if (RegExp(
            r'עולה חדש|עולים חדשים|עולה חדשה|עלייה לארץ|עליתי לארץ|'
            r'דובר אנגלית|דוברת אנגלית|דוברי אנגלית|אנגלו[- ]?סקסי|'
            r'\banglo\b|\bolim\b|\boleh\b|new immigrant|english.speaking',
            caseSensitive: false)
        .hasMatch(text)) {
      out..add(qualityArea)..add(goodSchools);
    }
    // Student → near a campus (kept from before).
    if (out.contains(student)) out.add(nearUniversity);
    return out;
  }
}
