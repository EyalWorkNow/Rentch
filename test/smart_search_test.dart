import 'package:dating_app/core/search/smart_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the natural-language example', () {
    final q = SmartSearch.parse(
      'אני מחפש דירה באזור של הרכבת, משופצת עם 3 חדרים לזוג עם כלבה בלי ילדים',
    );
    expect(q.nearTrain, true);
    expect(q.minRooms, 3);
    expect(q.amenities.contains('feat_renovated'), true);
    expect(q.amenities.contains('feat_pets'), true);
    expect(q.isEmpty, false);
  });

  test('a bare single room count becomes a tight band [n, n+0.5]', () {
    // "3 חדרים" must not surface 4/5/6-room units — it means ~3.
    final q = SmartSearch.parse('דירת 3 חדרים בתל אביב');
    expect(q.minRooms, 3);
    expect(q.maxRooms, 3.5);
    // spelled-out too
    final s = SmartSearch.parse('דירה שלושה חדרים');
    expect(s.minRooms, 3);
    expect(s.maxRooms, 3.5);
    // "3+" stays open-ended (a minimum, no cap)
    final open = SmartSearch.parse('דירת 3+ חדרים');
    expect(open.minRooms, 3);
    expect(open.maxRooms, isNull);
    // "לפחות 3" keeps its deliberate open upper bound
    final atLeast = SmartSearch.parse('לפחות 3 חדרים');
    expect(atLeast.minRooms, 3);
    expect(atLeast.maxRooms, isNull);
    // an explicit range is untouched
    final range = SmartSearch.parse('דירת 3-4 חדרים');
    expect(range.minRooms, 3);
    expect(range.maxRooms, 4);
  });

  test('"חדר וחצי" → 1.5 rooms with a tight band', () {
    final q = SmartSearch.parse('דירת חדר וחצי בתל אביב');
    expect(q.minRooms, 1.5);
    expect(q.maxRooms, 2.0);
  });

  test('studio caps at 2 but keeps no floor (0.5/1 units match)', () {
    final q = SmartSearch.parse('סטודיו בפלורנטין עד 5000');
    expect(q.propertyType, 'סטודיו');
    expect(q.minRooms, isNull); // no floor → a 0.5/1-room micro-unit still matches
    expect(q.maxRooms, 2);
  });

  test('parses city and budget', () {
    final q = SmartSearch.parse('אני צריך דירת 4 חדרים בתל אביב עד 7500 שקל');
    expect(q.city, 'תל אביב');
    expect(q.minRooms, 4);
    expect(q.maxPrice, 7500);
  });

  test('parses Hebrew "אלף" budgets and pet+city', () {
    final q = SmartSearch.parse(
      'דירה במקסימום 7 וחצי אלף שח במרכז תל אביב עם אפשרות להכניס כלב',
    );
    expect(q.maxPrice, 7500);
    expect(q.city, 'תל אביב');
    expect(q.amenities.contains('feat_pets'), true);
  });

  test('plain "7 אלף" → 7000', () {
    expect(SmartSearch.parse('עד 7 אלף בחיפה').maxPrice, 7000);
  });

  test('budget range "בין X ל-Y"', () {
    final q = SmartSearch.parse('דירה בין 5000 ל-7000 בתל אביב');
    expect(q.minPrice, 5000);
    expect(q.maxPrice, 7000);
  });

  test('million shorthand "M" in a sale range', () {
    final q = SmartSearch.parse('דירה למכירה בין 1.5M ל-2M בתל אביב');
    expect(q.minPrice, 1500000);
    expect(q.maxPrice, 2000000);
  });

  test('budget "בערך" → window', () {
    final q = SmartSearch.parse('משהו בערך 6000 בחיפה');
    expect(q.minPrice, 5100);
    expect(q.maxPrice, 6900);
  });

  test('rooms range "3-4"', () {
    final q = SmartSearch.parse('דירת 3-4 חדרים');
    expect(q.minRooms, 3);
    expect(q.maxRooms, 4);
  });

  test('half rooms "שלוש וחצי"', () {
    expect(SmartSearch.parse('דירה שלוש וחצי חדרים').minRooms, 3.5);
  });

  test('neighborhood + property type + studio sizing', () {
    final q = SmartSearch.parse('סטודיו בפלורנטין עד 5000');
    expect(q.neighborhood, 'פלורנטין');
    expect(q.propertyType, 'סטודיו');
    expect(q.maxRooms, 2); // studio capped
    expect(q.maxPrice, 5000);
  });

  test('persona: student defaults to small when rooms unstated', () {
    final q = SmartSearch.parse('אני סטודנט מחפש משהו זול בבאר שבע');
    expect(q.minRooms, 1);
    expect(q.maxRooms, 2);
    expect(q.cheapPreference, true);
  });

  test('empty when nothing concrete', () {
    expect(SmartSearch.parse('שלום מה נשמע').isEmpty, true);
  });

  test('fuzzy city matching: תל אביב (typo)', () {
    final q = SmartSearch.parse('דירה בתל אביים עד 5000');
    expect(q.city, 'תל אביב'); // typo corrected
  });

  test('fuzzy city matching: חיפה (different spelling)', () {
    final q = SmartSearch.parse('מחפש בחיפא לפחות 2 חדרים');
    expect(q.city, 'חיפה');
  });

  test('locality suggestion: haifa prefix', () {
    final suggestions = LocalityMatcher.suggestLocalities('חי');
    expect(suggestions.contains('חיפה'), true);
  });

  test('locality suggestion: fuzzy typo', () {
    final best = LocalityMatcher.findBestMatch('תל אבו');
    expect(best, 'תל אביב');
  });

  // ── persona-miss regressions (found by the persona test loop, 2026-07-03) ──
  test('wheelchair persona: נגישות + כיסא גלגלים → feat_accessible', () {
    final q = SmartSearch.parse(
      'בן משפחה בכיסא גלגלים, צריך דירת קומת קרקע נגישה עם חניית נכה בנתניה, 3 חדרים, 5500',
    );
    expect(q.amenities.contains('feat_accessible'), true);
    expect(q.amenities.contains('feat_parking'), true); // "חניית נכה" stem
    expect(q.city, 'נתניה');
  });

  test('oleh persona: English "light rail" → nearTrain', () {
    final q = SmartSearch.parse(
      'looking for a 2 bedroom near the light rail in tel aviv',
    );
    expect(q.nearTrain, true);
  });

  test('single-parent persona: "תחבורה ציבורית" → nearTrain', () {
    final q = SmartSearch.parse('3 חדרים בירושלים ליד תחבורה ציבורית עד 5000');
    expect(q.nearTrain, true);
  });

  test('student persona: "שותפים" → feat_roommates', () {
    final q = SmartSearch.parse('מחפשת דירת שותפים ליד האוניברסיטה בתל אביב');
    expect(q.amenities.contains('feat_roommates'), true);
  });

  // ── cohort signals routed to the backend 14-cohort engine ──────────────────
  test('charedi family → religiousStream=charedi + household=family', () {
    final s = SmartSearch.cohortSignals(
        'משפחה חרדית עם 5 ילדים ליד תלמוד תורה וחיידר בבני ברק');
    expect(s['religiousStream'], 'charedi');
    expect(s['isReligious'], 'true');
    expect(s['household'], 'family');
    expect(s['hasChildren'], 'true');
  });

  test('dati-leumi family → religiousStream=dati_leumi', () {
    final s = SmartSearch.cohortSignals('זוג דתי לאומי עם ילדים ליד אולפנה');
    expect(s['religiousStream'], 'dati_leumi');
    expect(s['household'], 'family');
  });

  test('oleh English speaker → isOleh + langPref=en', () {
    final s = SmartSearch.cohortSignals(
        "i'm a new immigrant, english speaker looking in tel aviv");
    expect(s['isOleh'], 'true');
    expect(s['langPref'], 'en');
  });

  test('senior wheelchair → accessibilityNeed + lifeStage=senior + age', () {
    final s = SmartSearch.cohortSignals('גמלאי בן 72 בכיסא גלגלים צריך נגישות');
    expect(s['accessibilityNeed'], 'true');
    expect(s['lifeStage'], 'senior');
    expect(s['age'], '72');
  });

  test('single parent car-free → carFree + hasChildren', () {
    final s = SmartSearch.cohortSignals('אמא חד הורית עם ילד בלי רכב');
    expect(s['carFree'], 'true');
    expect(s['hasChildren'], 'true');
  });

  test('new parents expecting → expecting=true', () {
    final s = SmartSearch.cohortSignals('זוג צעיר בהריון מחפש 3 חדרים');
    expect(s['expecting'], 'true');
    expect(s['household'], 'couple');
  });

  test('remote worker → wfh=true', () {
    final s = SmartSearch.cohortSignals('עובד מהבית צריך חדר עבודה שקט');
    expect(s['wfh'], 'true');
    expect(s['vibe'], 'שקט');
  });

  test('investor → isInvestor + intent=investment', () {
    final s = SmartSearch.cohortSignals('משקיע מחפש דירה עם תשואה טובה לקנייה');
    expect(s['isInvestor'], 'true');
    expect(s['intent'], 'investment');
  });

  test('young professional → vibe=תוסס', () {
    final s = SmartSearch.cohortSignals('רווק בן 29 רוצה מרכז תוסס עם חיי לילה');
    expect(s['vibe'], 'תוסס');
    expect(s['household'], 'single');
  });

  test('non-persona text → no false signals', () {
    final s = SmartSearch.cohortSignals('דירת 3 חדרים בחיפה עד 5000');
    expect(s.containsKey('religiousStream'), false);
    expect(s.containsKey('isInvestor'), false);
    expect(s.containsKey('accessibilityNeed'), false);
  });
}
