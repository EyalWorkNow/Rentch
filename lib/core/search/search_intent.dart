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

  // Distance-from-sea thresholds (km) — a shared, explicit definition of "close".
  static const double seaCloseKm = 1.5; // "on the sea" / walkable to the beach
  static const double seaOkKm = 3.0; // still "near the sea"
  // >seaOkKm ⇒ not near the sea.

  static final Map<String, RegExp> _patterns = {
    nearSea: RegExp(r'הים|לים|חוף|ליד המים|beach|seaside|seafront', caseSensitive: false),
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
  };

  /// The set of intents present in [text]. Elderly/retiree phrasing implies both
  /// quiet and accessibility; a student implies being near a campus.
  static Set<String> fromText(String text) {
    if (text.trim().isEmpty) return <String>{};
    final out = <String>{};
    for (final e in _patterns.entries) {
      if (e.value.hasMatch(text)) out.add(e.key);
    }
    // Implications.
    if (RegExp(r'מבוגר|גמלא|פנסי|קשיש|retire').hasMatch(text)) {
      out.add(accessible);
    }
    if (out.contains(student)) out.add(nearUniversity);
    return out;
  }
}
