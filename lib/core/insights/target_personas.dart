// Target tenant/buyer personas for Area Intelligence (supply side). Each persona
// is expressed as a SearchQuery so it reuses the WHOLE preference model — the
// intent sharpening + the 67 inference rules — to produce a realistic weight
// profile. The area-fit scorer then measures how well a LOCATION serves it.
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/l10n/app_localizations.dart';

class TargetPersona {
  const TargetPersona(this.key, this.emoji, this.query);
  final String key;
  final String emoji;
  final SearchQuery query;

  /// User-facing label for this persona, localized. Kept as a lookup (rather
  /// than a stored field) because the persona list is built once at load time
  /// with no BuildContext available yet.
  String label(AppLocalizations l10n) {
    switch (key) {
      case 'young_couples':
        return l10n.targetPersonasB0b0c3cf;
      case 'families':
        return l10n.targetPersonasF56f1edd;
      case 'students':
        return l10n.targetPersonas99e7c02f;
      case 'tech':
        return l10n.targetPersonasD468d495;
      case 'seniors':
        return l10n.targetPersonasA8dc0f49;
      case 'yield_investor':
        return l10n.targetPersonasE86bb514;
      case 'valueadd_investor':
        return l10n.targetPersonas55c1710d;
      default:
        return key;
    }
  }

  static SearchQuery _q(String rawText, Set<String> intents) =>
      SearchQuery(rawText: rawText, intents: intents);

  /// The 7 presets. Order = display order.
  static final List<TargetPersona> all = [
    TargetPersona('young_couples', '💑', _couples),
    TargetPersona('families', '👨‍👩‍👧', _families),
    TargetPersona('students', '🎓', _students),
    TargetPersona('tech', '💻', _tech),
    TargetPersona('seniors', '🌿', _seniors),
    TargetPersona('yield_investor', '📈', _yieldInvestor),
    TargetPersona('valueadd_investor', '🏗️', _valueAdd),
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
