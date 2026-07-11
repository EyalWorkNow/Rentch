// Regression guards for the parser/ranking fixes surfaced by the 50-persona
// aggressive break-test (messy natural language).
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

RentalProperty p({required String id, int price = 6000, double rooms = 3, String city = 'תל אביב', double lat = 32.07, double lon = 34.78}) =>
    RentalProperty(id: id, price: price, rooms: rooms, sizeM2: 70, floor: '3',
        totalFloors: '8', city: city, neighborhood: '', street: 'x', streetNumber: 1,
        lat: lat, lon: lon, propertyType: 'דירה', entryDate: '', condition: 'טוב',
        ownerName: 'x', agencyListing: false, features: const [],
        media: const [PropertyMedia(url: 'u', type: PropertyMediaType.image)]);

void main() {
  test('"בערך" is NOT parsed as the city ערד', () {
    for (final q in ['תקציב בערך 4500 אני לבד', 'משהו קטן במרכז בערך 5000', 'דירה יפה בערך 6000']) {
      expect(SmartSearch.parse(q).city, isNot('ערד'), reason: '"$q" leaked to ערד');
    }
    // a REAL "בערד" still resolves to Arad.
    expect(SmartSearch.parse('דירה בערד עם מרפסת').city, 'ערד');
  });

  test('vague budget words → cheapPreference (no number needed)', () {
    for (final q in ['תקציב קטן מחפש דירה בתל אביב', 'יש לי תקציב מוגבל', 'משהו חסכוני', 'תקציב נמוך']) {
      expect(SmartSearch.parse(q).cheapPreference, true, reason: '"$q"');
    }
  });

  test('roommates ("שותפים") infer a 3-room floor, beating the student cap', () {
    final q = SmartSearch.parse('סטודנטים 3 שותפים מחפשים דירה גדולה בתל אביב');
    expect(q.minRooms, greaterThanOrEqualTo(3),
        reason: 'roommates need bedrooms; must not fall to the student 1-2 cap');
  });

  test('minor round-2 fixes: יפו / spelled numbers / monthly / typos', () {
    // Jaffa resolves to Tel Aviv.
    expect(SmartSearch.parse('דירה ביפו 3 חדרים').city, 'תל אביב');
    // spelled rooms + spelled thousands.
    final q = SmartSearch.parse('תלת חדר בתל אביב עד ששת אלפים');
    expect(q.minRooms, 3);
    expect(q.maxPrice, 6000);
    expect(SmartSearch.parse('שבעה חדרים').minRooms, 7);
    expect(SmartSearch.parse('דירה חמשת אלפים בתל אביב').maxPrice, 5000);
    // "בחודש" forces rent even for an absurd number.
    expect(SmartSearch.parse('דירה בתל אביב עד 500000 בחודש').transactionType,
        TransactionTypeFilter.rent);
    // longer-city typo now resolves.
    expect(SmartSearch.parse('דירה בירשלים').city, 'ירושלים');
  });

  group('central region', () {
    setUpAll(() async {
      // gov data not required for this ranking behaviour; keep it lightweight.
    });
    test('"במרכז" with NO city prefers Gush Dan over the periphery', () {
      final cat = [
        p(id: 'tlv', city: 'תל אביב', lat: 32.07, lon: 34.78, price: 6000),
        p(id: 'rg', city: 'רמת גן', lat: 32.085, lon: 34.81, price: 6000),
        p(id: 'bes', city: 'באר שבע', lat: 31.25, lon: 34.79, price: 2600),
        p(id: 'haifa', city: 'חיפה', lat: 32.79, lon: 34.99, price: 3200),
      ];
      final recs = RecommendationEngine.recommend(
          candidates: cat,
          query: SmartSearch.parse('זוג מחפש משהו נחמד במרכז'),
          limit: 4, explore: false);
      final ids = recs.map((r) => r.property.id).toList();
      // a central-region city must rank above the peripheral ones.
      final firstCentral = ids.indexWhere((i) => i == 'tlv' || i == 'rg');
      final firstPeriph = ids.indexWhere((i) => i == 'bes' || i == 'haifa');
      expect(firstCentral, greaterThanOrEqualTo(0));
      expect(firstPeriph == -1 || firstCentral < firstPeriph, true,
          reason: '"במרכז" must not surface Beer Sheva / Haifa above Gush Dan');
      expect(SmartSearch.parse('משהו במרכז').intents.contains(SearchIntent.central), true);
    });
  });
}
