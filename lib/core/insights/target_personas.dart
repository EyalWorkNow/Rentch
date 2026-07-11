// Target tenant/buyer personas for Area Intelligence (supply side). Each persona
// is expressed as a SearchQuery so it reuses the WHOLE preference model — the
// intent sharpening + the 67 inference rules — to produce a realistic weight
// profile. The area-fit scorer then measures how well a LOCATION serves it.
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/search/smart_search.dart';

class TargetPersona {
  const TargetPersona(this.key, this.label, this.emoji, this.query);
  final String key;
  final String label; // Hebrew, user-facing
  final String emoji;
  final SearchQuery query;

  static SearchQuery _q(String rawText, Set<String> intents) =>
      SearchQuery(rawText: rawText, intents: intents);

  /// The 7 presets. Order = display order.
  static final List<TargetPersona> all = [
    TargetPersona('young_couples', 'זוגות צעירים', '💑', _couples),
    TargetPersona('families', 'משפחות עם ילדים', '👨‍👩‍👧', _families),
    TargetPersona('students', 'סטודנטים', '🎓', _students),
    TargetPersona('tech', 'אנשי הייטק', '💻', _tech),
    TargetPersona('seniors', 'מבוגרים / פרישה', '🌿', _seniors),
    TargetPersona('yield_investor', 'משקיע תשואה', '📈', _yieldInvestor),
    TargetPersona('valueadd_investor', 'משקיע השבחה', '🏗️', _valueAdd),
  ];

  static final _couples = _q('זוג צעיר מחפש דירה מרכזית באזור איכותי',
      {SearchIntent.couple, SearchIntent.central});
  static final _families = _q('משפחה עם ילדים, שכונה טובה ובטוחה, קרוב לבתי ספר',
      {SearchIntent.goodSchools, SearchIntent.safety, SearchIntent.qualityArea});
  static final _students = _q('סטודנט ליד האוניברסיטה, אזור צעיר ותוסס, תחבורה',
      {SearchIntent.student, SearchIntent.nearUniversity, SearchIntent.nightlife,
        SearchIntent.transit});
  static final _tech = _q('הייטקיסט צעיר, מרכזי ותוסס, קרוב לתחבורה וחיי לילה',
      {SearchIntent.single, SearchIntent.central, SearchIntent.nightlife,
        SearchIntent.transit});
  static final _seniors = _q('זוג מבוגר בפרישה, שקט, נגיש, קרוב לשירותי בריאות',
      {SearchIntent.quiet, SearchIntent.health, SearchIntent.accessible});
  static final _yieldInvestor = _q('השקעה לשכירות עם תשואה גבוהה, ביקוש שוכרים',
      {SearchIntent.investment, SearchIntent.transit});
  static final _valueAdd = _q('השקעה להשבחה, פוטנציאל עליית ערך, תשתית מתוכננת',
      {SearchIntent.growth, SearchIntent.investment});

  static TargetPersona? byKey(String key) {
    for (final p in all) {
      if (p.key == key) return p;
    }
    return null;
  }
}
