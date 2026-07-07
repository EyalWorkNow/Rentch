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

  /// The seeker wants a religiously-observant community (חרדי / דתי-לאומי) or a
  /// place near a synagogue → prefer known religious localities/neighbourhoods.
  static const religiousArea = 'religious_area';

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
        r'נייטלייף|חיי לילה|בילוי|\bבר\b|ברים|פאב|פאבים|מועדון|מסעד|בית קפה|בתי קפה|תוסס|nightlife|bars|pubs|clubs',
        caseSensitive: false),
    quiet: RegExp(r'שקט|שקטה|רגוע|מבוגר|גמלא|פנסי|קשיש|retire|quiet|calm',
        caseSensitive: false),
    central: RegExp(r'מרכזי|מרכזית|מרכז העיר|לב העיר|במרכז|סנטר|central|downtown',
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
        r'שכונה טובה|אזור טוב|אזור איכותי|אזור יוקרתי|שכונה יוקרתית|שכונה שקטה|good area|nice area',
        caseSensitive: false),
    religiousArea: RegExp(
        r'דתי|דתיה|דתיים|חרדי|חרדית|חרדים|שומר שבת|שומרי שבת|בית כנסת|בתי כנסת|'
        r'קהילה דתית|אזור דתי|שכונה דתית|כשר|מקווה|עירוב|ישיבה|אולפנה|תלמוד תורה|'
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
    // Retiree / elderly → step-free access + a quiet area.
    if (RegExp(r'מבוגר|גמלא|פנסי|קשיש|בגיל השלישי|retire|senior|elderly')
        .hasMatch(text)) {
      out..add(accessible)..add(quiet);
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
