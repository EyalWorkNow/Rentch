import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:flutter_test/flutter_test.dart';

// COVERAGE PROBE: ~100 real qualitative phrases Israelis search with. For each we
// collect what the assistant understands — SearchIntent keys + the area/vibe
// signals from SmartSearch — and flag phrases that produce NOTHING meaningful
// (silently dropped) or an obviously wrong mapping. Not a pass/fail gate; it
// prints a coverage report and fails only if the DROPPED rate is high.

// phrase → the signal(s) we'd expect a competent assistant to derive.
const Map<String, String> phrases = {
  // ── spatial / area ──
  'דירה באזור תל אביב': 'city_area',
  'משהו באזור של רמת גן': 'city_area',
  'בסביבות חיפה': 'city_area',
  'ירושלים והסביבה': 'city_area',
  'קרוב לתל אביב': 'near/area',
  'בצפון תל אביב': 'neighborhood/area',
  'מרכז העיר': 'central',
  'לב העיר': 'central',
  'אזור מרכזי': 'central',
  // ── neighborhood quality ──
  'שכונה טובה': 'quality_area',
  'אזור טוב': 'quality_area',
  'אזור איכותי': 'quality_area',
  'שכונה יוקרתית': 'quality_area/luxury',
  'אזור יוקרתי': 'quality_area/luxury',
  'שכונה שקטה': 'quality_area/quiet',
  'שכונה מטופחת': 'quality_area',
  'אזור מבוקש': 'quality_area',
  'שכונה נחשבת': 'quality_area',
  'שכונה בעלייה': 'quality_area/emerging',
  'אזור מתפתח': 'emerging',
  'שכונה מתחדשת': 'emerging',
  // ── demographic / vibe ──
  'אזור צעיר': 'young_area',
  'סביבה צעירה': 'young_area',
  'שכונה צעירה': 'young_area',
  'אוכלוסייה צעירה': 'young_area',
  'אזור של צעירים': 'young_area',
  'אזור תוסס': 'nightlife/young',
  'מקום תוסס': 'nightlife/young',
  'צעיר ותוסס': 'nightlife/young',
  'אזור בוהמייני': 'nightlife/hipster',
  'שכונה היפסטרית': 'nightlife/hipster',
  'אזור אמנותי': 'nightlife/hipster',
  'מקום שקט': 'quiet',
  'אזור רגוע': 'quiet',
  'סביבה רגועה': 'quiet',
  'שכונה שלווה': 'quiet',
  'אזור מבוגר': 'senior_area/quiet',
  'אזור למבוגרים': 'senior_area/quiet',
  'שכונה משפחתית': 'family/quality',
  'אזור משפחתי': 'family/quality',
  'סביבה משפחתית': 'family/quality',
  'שכונה של משפחות': 'family/quality',
  // ── safety ──
  'שכונה בטוחה': 'safety',
  'מקום בטוח': 'safety',
  'אזור בטוח': 'safety',
  'אזור לא מסוכן': 'safety',
  'בלי פשיעה': 'safety',
  'שכונה נקייה': 'safety/quality',
  // ── community / religion ──
  'אזור דתי': 'religious_area',
  'שכונה דתית': 'religious_area',
  'קהילה דתית': 'religious_area',
  'אזור חרדי': 'religious_area',
  'שכונה חילונית': 'secular_area',
  'קהילה מעורבת': 'mixed_community',
  'אזור אנגלוסקסי': 'anglo/quality',
  'קהילה אנגלוסקסית': 'anglo/quality',
  'שכונה מסורתית': 'religious_area',
  // ── green / environment ──
  'אזור ירוק': 'green',
  'הרבה גינות': 'green',
  'קרוב לפארק': 'park',
  'ליד הים': 'near_sea',
  'קרוב לים': 'near_sea',
  'נוף לים': 'near_sea/view',
  'אוויר נקי': 'clean_air',
  'אזור פתוח': 'green',
  // ── convenience / transit ──
  'קרוב לתחבורה': 'transit',
  'ליד רכבת': 'transit',
  'נגיש לתחבורה ציבורית': 'transit/carfree',
  'קרוב לרכבת קלה': 'transit',
  'ליד תחנת אוטובוס': 'transit',
  'קרוב לעבודה': 'commute',
  'קרוב למרכזי קניות': 'convenience',
  'ליד סופר': 'convenience',
  'קרוב לבית חולים': 'health',
  'ליד קופת חולים': 'health',
  // ── lifestyle ──
  'מקום לבלות': 'nightlife',
  'חיי לילה': 'nightlife',
  'הרבה בתי קפה': 'nightlife',
  'אזור סטודנטיאלי': 'student/young',
  'קרוב לאוניברסיטה': 'near_university',
  'ליד הקמפוס': 'near_university',
  'מתאים לשותפים': 'roommates',
  'אזור עסקים': 'central/business',
  // ── size / quality of flat ──
  'דירה מרווחת': 'spacious',
  'חדרים גדולים': 'spacious',
  'הרבה אור': 'light/view',
  'קומה גבוהה': 'view',
  'עם נוף': 'view',
  'דירה מפוארת': 'luxury',
  'דירה משופצת': 'renovated',
  // ── negations ──
  'לא באזור רועש': 'quiet(neg noise)',
  'בלי רעש': 'quiet',
  'רחוק מכביש ראשי': 'quiet(neg road)',
  'לא בקומת קרקע': 'neg-ground',
  'לא ליד הים': 'neg near_sea',
  'לא באזור דתי': 'neg religious',
  // ── compound / realistic ──
  'שכונה טובה ושקטה למשפחה': 'quality+quiet+family',
  'אזור צעיר ותוסס עם חיי לילה': 'young+nightlife',
  'מקום שקט ובטוח למבוגרים': 'quiet+safety+senior',
  'אזור מרכזי אבל שקט': 'central+quiet',
  'קרוב לים ולחיי לילה': 'near_sea+nightlife',
  'שכונה דתית עם בתי ספר טובים': 'religious+schools',
};

void main() {
  test('semantic coverage — ~100 qualitative phrases', () {
    final dropped = <String>[];
    final report = StringBuffer();
    phrases.forEach((phrase, expected) {
      final intents = SearchIntent.fromText(phrase);
      final q = SmartSearch.parse(phrase);
      final vibe = SmartSearch.cohortSignals(phrase)['vibe'];
      final signals = <String>{
        ...intents,
        ...q.intents,
        ...q.amenities,
        ...q.requiredFeatures,
        if (vibe != null) 'vibe:$vibe',
      };
      final isDropped = signals.isEmpty && q.city == null;
      if (isDropped) dropped.add(phrase);
      report.writeln(
          '${isDropped ? "❌ DROP" : "  ok  "} | "$phrase"  →  ${signals.join(", ")}'
          '${q.city != null ? " [city:${q.city}]" : ""}   (want: $expected)');
    });
    // ignore: avoid_print
    print(report.toString());
    // ignore: avoid_print
    print('DROPPED ${dropped.length}/${phrases.length}: ${dropped.join(" · ")}');
    // Fail only if a large fraction is silently dropped.
    expect(dropped.length <= phrases.length * 0.20, true,
        reason: 'too many phrases produce NO signal (${dropped.length}): '
            '${dropped.join(", ")}');
  });
}
