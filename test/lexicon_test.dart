import 'package:dating_app/core/search/smart_search.dart';
import 'package:flutter_test/flutter_test.dart';

// Phase 1 — the parser understands everyday Israeli abbreviations / slang.
void main() {
  test('expandLexicon rewrites abbreviations to full phrases', () {
    expect(SmartSearch.expandLexicon('קרוב לתחב"צ'), contains('תחבורה ציבורית'));
    expect(SmartSearch.expandLexicon('דירה עם רק"ל'), contains('רכבת קלה'));
    expect(SmartSearch.expandLexicon('שכ"ד 5000'), contains('שכר דירה'));
    expect(SmartSearch.expandLexicon('דירת יח"ד'), contains('יחידת דיור'));
    expect(SmartSearch.expandLexicon('דירה ק"ק'), contains('קומת קרקע'));
  });

  test('"תחב״צ" / "רק״ל" flag the transit signal, like the full words', () {
    expect(SmartSearch.parse('דירה בחיפה קרוב לתחב"צ').nearTrain, isTrue);
    expect(SmartSearch.parse('דירה ליד רק"ל בתל אביב').nearTrain, isTrue);
    // regression: a search with no transit word stays false.
    expect(SmartSearch.parse('דירה שקטה בתל אביב').nearTrain, isFalse);
  });

  test('slang for real features is understood', () {
    expect(SmartSearch.parse('דירה עם ממ"ד').amenities.contains('feat_mamad'),
        isTrue);
    expect(
        SmartSearch.parse('דירה עם מרפסת שמש').amenities.contains('feat_balcony'),
        isTrue);
  });
}
