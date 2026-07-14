// Regression suite: the Hebrew \b + definite-article + spelling fixes applied to
// SearchIntent and SmartSearch (mirrors the nearby_relevance audit fixes).
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchIntent · Hebrew \\b (H1)', () {
    test('standalone בר → nightlife, but not inside a longer word', () {
      expect(SearchIntent.fromText('יש בר טוב קרוב'), contains(SearchIntent.nightlife));
      expect(SearchIntent.fromText('אזור בריא ושקט'),
          isNot(contains(SearchIntent.nightlife)));
    });
  });

  group('SearchIntent · definite article ה (H2)', () {
    test('young-area phrases with ה', () {
      expect(SearchIntent.fromText('דירה באזור הצעיר'),
          contains(SearchIntent.youngPop));
      expect(SearchIntent.fromText('אוהב חיי הלילה'),
          contains(SearchIntent.nightlife));
    });
    test('transit / school / hospital / synagogue / café with ה', () {
      expect(SearchIntent.fromText('ליד הרכבת הקלה'), contains(SearchIntent.transit));
      expect(SearchIntent.fromText('קרוב לבית הספר'),
          contains(SearchIntent.goodSchools));
      expect(SearchIntent.fromText('ליד בית החולים'), contains(SearchIntent.health));
      expect(SearchIntent.fromText('קרוב לבית הכנסת'),
          contains(SearchIntent.religiousArea));
      expect(SearchIntent.fromText('אזור עם בית הקפה'),
          contains(SearchIntent.nightlife));
    });
    test('the non-article forms still work (no regression)', () {
      expect(SearchIntent.fromText('אזור צעיר'), contains(SearchIntent.youngPop));
      expect(SearchIntent.fromText('רכבת קלה'), contains(SearchIntent.transit));
      expect(SearchIntent.fromText('בית ספר טוב'), contains(SearchIntent.goodSchools));
    });
  });

  group('SearchIntent · Phase-2 life-stage phrases with ה (3rd sweep)', () {
    test('גן הילדים / בני הנוער infer young-children / teens', () {
      expect(SearchIntent.fromText('קרוב לגן הילדים'),
          contains(SearchIntent.youngChildren));
      expect(SearchIntent.fromText('יש לי בני הנוער בבית'),
          contains(SearchIntent.teens));
      // non-article forms still work
      expect(SearchIntent.fromText('גן ילדים קרוב'),
          contains(SearchIntent.youngChildren));
    });
  });

  group('SearchIntent · spelling איזור (M1)', () {
    test('"איזור" (with yud) is normalized', () {
      expect(SearchIntent.fromText('מחפש באיזור צעיר'),
          contains(SearchIntent.youngPop));
      expect(SearchIntent.fromText('איזור ירוק'), contains(SearchIntent.green));
    });
  });

  group('SmartSearch · negator בלי (H1) + area spelling (M1)', () {
    test('"בלי <place>" excludes that place (בלי\\b was broken)', () {
      final q = SmartSearch.parse('דירה בתל אביב בלי רמת גן');
      expect(q.city, contains('תל אביב'));
      expect(q.excludeAreas.any((a) => a.contains('רמת גן')), isTrue,
          reason: 'בלי should negate רמת גן');
    });
    test('couple detected with "בני הזוג"', () {
      // both spellings resolve (bare זוג is article-proof; בני הזוג now too)
      expect(SmartSearch.parse('אנחנו בני הזוג מחפשים').intents.isNotEmpty ||
          SearchIntent.fromText('בני הזוג').contains(SearchIntent.couple), isTrue);
    });
  });
}
