import 'package:dating_app/core/search/search_intent.dart';
import 'package:flutter_test/flutter_test.dart';
void main() {
  test('wheelchair query is NOT a beach search', () {
    final w = SearchIntent.fromText('דירה נגישה לכיסא גלגלים בחיפה עם מעלית');
    expect(w.contains(SearchIntent.nearSea), isFalse, reason: '"גלגלים" must not trigger near_sea');
    expect(w.contains(SearchIntent.accessible), isTrue);
  });
  test('real sea request still detected', () {
    expect(SearchIntent.fromText('דירה קרוב לים בתל אביב').contains(SearchIntent.nearSea), isTrue);
    expect(SearchIntent.fromText('משהו על יד הים').contains(SearchIntent.nearSea), isTrue);
    expect(SearchIntent.fromText('דירה עם נוף לחוף').contains(SearchIntent.nearSea), isTrue);
  });
}
