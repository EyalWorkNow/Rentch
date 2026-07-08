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
  static const accessible = 'accessible';
  static const luxury = 'luxury';
  static const view = 'view';
  static const student = 'student';
  static const nearUniversity = 'near_university';
  static const investment = 'investment';
  static const roommates = 'roommates';
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

  /// The seeker wants a religiously-observant community (חרדי / דתי-לאומי) or a
  /// place near a synagogue → prefer known religious localities/neighbourhoods.
  static const religiousArea = 'religious_area';

  /// Age of the kids → which school type matters: young → גן/יסודי, teens → תיכון.
  static const youngChildren = 'young_children';
  static const teens = 'teens';

  /// "אזור X" (as opposed to the city X itself) — the user wants X PLUS its
  /// adjacent settlements, so the city gate widens to the neighbouring towns.
  static const cityArea = 'city_area';

  // Distance-from-sea thresholds (km) — a shared, explicit definition of "close".
  static const double seaCloseKm = 1.5; // "on the sea" / walkable to the beach
  static const double seaOkKm = 3.0; // still "near the sea"
  // >seaOkKm ⇒ not near the sea.

  static final Map<String, RegExp> _patterns = {
    // NB: "לים" must be a WORD ("קרוב לים"), not a suffix — otherwise "גלגלים"
    // (as in "כיסא גלגלים"/wheelchair) false-matches and sea-gates the search.
    nearSea: RegExp(r'הים|(?<=\s)לים|חוף|ליד המים|beach|seaside|seafront', caseSensitive: false),
    nightlife: RegExp(
        r'נייטלייף|חיי לילה|בילוי|לבלות|מקום לבלות|\bבר\b|ברים|פאב|פאבים|מועדון|'
        r'מסעד|בית קפה|בתי קפה|תוסס|תוססת|בוהמיינ|בוהמי|היפסטר|אמנותי|סצנה|'
        r'אזור צעיר|שכונה צעיר|מקום צעיר|צעיר ותוסס|'
        r'nightlife|bars|pubs|clubs|hipster|trendy|bohemian',
        caseSensitive: false),
    quiet: RegExp(
        r'שקט|שקטה|רגוע|רגועה|שלוו|שליו|פסטורל|מבוגר|גמלא|פנסי|קשיש|'
        r'בלי רעש|ללא רעש|רחוק מרעש|נטול רעש|רחוק מכביש|רחוק מהרעש|'
        r'retire|quiet|calm|peaceful|tranquil',
        caseSensitive: false),
    central: RegExp(
        r'מרכזי|מרכזית|מרכז העיר|לב העיר|במרכז|סנטר|אזור עסקים|מרכז עסקים|'
        r'מגדלי משרדים|central|downtown|business district',
        caseSensitive: false),
    spacious: RegExp(r'מרווח|מרווחת|מרווחים|מרווחות|חדרים גדולים|גדולה מאוד|spacious',
        caseSensitive: false),
    accessible: RegExp(
        r'נגיש|נגישות|כיסא גלגלים|כסא גלגלים|מוגבלות|נכה|עגלה|wheelchair|accessible|step.?free',
        caseSensitive: false),
    luxury: RegExp(r'יוקר|מפואר|פרימיום|luxur|penthouse|פנטהאוז', caseSensitive: false),
    view: RegExp(r'נוף|קומה גבוה|פנטהאוז|view|penthouse', caseSensitive: false),
    student: RegExp(r'סטודנט|סטודנטית|קמפוס|מכלל|student|campus', caseSensitive: false),
    nearUniversity:
        RegExp(r'אוניברסיט|קמפוס|מכלל|university|campus', caseSensitive: false),
    investment: RegExp(r'השקע|תשוא|invest|yield|rental income', caseSensitive: false),
    roommates: RegExp(r'שותפ|שותפות|roommate|flatmate', caseSensitive: false),
    wfh: RegExp(
        r'עבודה מהבית|עובד מהבית|עובדת מהבית|חדר עבודה|מהבית|רימוט|remote|wfh|work from home',
        caseSensitive: false),
    goodSchools: RegExp(r'בתי ספר|בית ספר|בית הספר|חינוך|מוסדות חינוך|schools?',
        caseSensitive: false),
    qualityArea: RegExp(
        r'שכונה טובה|אזור טוב|אזור איכותי|אזור יוקרתי|שכונה יוקרתית|שכונה שקטה|'
        r'מטופח|מטופחת|אזור מבוקש|שכונה מבוקש|מבוקשת|נחשב|נחשבת|שכונה בעלייה|'
        r'בעלייה|אזור מתפתח|מתפתח|מתפתחת|מתחדש|מתחדשת|שכונה נקייה|אזור נקי|'
        r'good area|nice area|prime|up.and.coming|sought.after',
        caseSensitive: false),
    safety: RegExp(
        r'בטוח|בטוחה|בטיחות|לא מסוכן|לא מסוכנת|בלי פשיעה|ללא פשיעה|פשיעה נמוכה|'
        r'ללא אלימות|בלי אלימות|safe|low.crime|secure',
        caseSensitive: false),
    transit: RegExp(
        r'תחבורה ציבורית|קרוב לתחבורה|נגיש לתחבורה|קרוב לרכבת|ליד רכבת|תחנת רכבת|'
        r'רכבת קלה|קו אדום|קו סגול|מטרו|קרוב לאוטובוס|ליד אוטובוס|תחנת אוטובוס|'
        r'קרוב לתחנה|public transport|near.*train|metro|light.rail|\bbus\b|transit|'
        r'near transit|well.connected',
        caseSensitive: false),
    employment: RegExp(
        r'קרוב לעבודה|ליד העבודה|קרוב למקום העבודה|אזור תעסוקה|אזור תעשייה|'
        r'הייטק|היי[- ]?טק|פארק הייטק|קרוב למשרדים|ליד משרדים|מרכז עסקים|'
        r'אזור עסקים|קרוב לאזור התעשייה|near work|close to work|tech park|'
        r'business district|job hub|employment',
        caseSensitive: false),
    green: RegExp(
        r'אזור ירוק|הרבה ירוק|הרבה גינות|גינות|גינה ציבורית|פארק|קרוב לפארק|'
        r'גן ציבורי|גנים ציבוריים|שטח פתוח|אזור פתוח|טבע|ריאות ירוקות|אוויר נקי|'
        r'green|park|garden',
        caseSensitive: false),
    health: RegExp(
        r'בית חולים|קופת חולים|מרפאה|קרוב לרפואה|שירותי בריאות|קרוב לבריאות|'
        r'clinic|hospital|medical',
        caseSensitive: false),
    youngPop: RegExp(
        r'אזור צעיר|סביבה צעירה|שכונה צעיר|מקום צעיר|אוכלוס\S* צעיר|'
        r'אזור של צעירים|קהל צעיר|הרבה צעירים|young (area|crowd|people|vibe)',
        caseSensitive: false),
    convenience: RegExp(
        r'ליד סופר|קרוב לסופר|סופרמרקט|ליד מכולת|מרכז קניות|מרכזי קניות|קניון|'
        r'קרוב לקניות|ליד מרכז מסחרי|מרכז מסחרי|קרוב לחנויות|ליד חנויות|'
        r'supermarket|grocer|shopping|\bmall\b|errands',
        caseSensitive: false),
    growth: RegExp(
        r'פוטנציאל|פוטנציאל השבחה|השבחה|פינוי בינוי|פינוי[- ]?בינוי|תמ[״"]?א|'
        r'התחדשות עירונית|אזור מתפתח|בעלייה|לפני עלייה|קרוב למטרו|מטרו עתידי|'
        r'קו מטרו|רכבת קלה עתידית|רק[״"]?ל עתיד|ערך עתידי|appreciation|upside|'
        r'up.and.coming|future (metro|value)|urban renewal',
        caseSensitive: false),
    religiousArea: RegExp(
        r'דתי|דתיה|דתיים|חרדי|חרדית|חרדים|שומר שבת|שומרי שבת|בית כנסת|בתי כנסת|'
        r'קהילה דתית|אזור דתי|שכונה דתית|מסורתי|מסורתית|כשר|מקווה|עירוב|ישיבה|אולפנה|תלמוד תורה|'
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
      if (RegExp(r'תינוק|פעוט|רך נולד|בהריון|הריון|גן ילדים|ילד קטן|'
              r'ילדים קטנים|בייבי|baby|toddler')
          .hasMatch(text)) {
        out.add(youngChildren);
      }
      if (RegExp(r'מתבגר|מתבגרת|מתבגרים|נוער|גיל העשרה|בני נוער|תיכון|teen')
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
    if (RegExp(r'בלי רעש|ללא רעש|לא רוצה רעש|לא באזור רועש|לא בסביבה רועש|'
            r'רחוק מרעש|רחוק מכביש|נטול רעש|no noise|away from.*(road|highway)')
        .hasMatch(text)) {
      out.add(quiet);
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
