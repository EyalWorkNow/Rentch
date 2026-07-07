import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

RentalProperty f(String id, double rooms, int price) => RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: (30 + rooms * 18).toInt(),
      floor: '2', totalFloors: '6', city: 'תל אביב', neighborhood: '',
      street: 'דיזנגוף', streetNumber: 5, lat: 32.08, lon: 34.78,
      propertyType: 'דירה', transactionType: PropertyTransactionType.rent,
      entryDate: '', condition: 'טוב', ownerName: 'o', agencyListing: false,
      features: const [],
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ]);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try { await GovData.instance.init(); } catch (_) {}
    await IsraelGeoIndex.loadParks();
    await IsraelGeoIndex.loadSchools();
    await IsraelGeoIndex.loadNightlife();
  });

  group('young-area phrasings fire the nightlife signal', () {
    for (final q in [
      'דירה בתל אביב עד 6000 באיזור עם סביבה צעירה',
      'שכונה עם אוכלוסייה צעירה',
      'מקום עם קהל צעיר',
      'אזור עם אנרגיה צעירה',
    ]) {
      test(q, () =>
          expect(SearchIntent.fromText(q).contains(SearchIntent.nightlife), true));
    }
  });

  group('family size → estimated rooms floor', () {
    final cases = {
      'דירה למשפחה עם ילד אחד בתל אביב': 3.0,
      'דירה למשפחה עם 3 ילדים בתל אביב עד 8000': 4.0,
      'משפחה עם 5 ילדים': 5.0,
      'משפחה עם שלושה ילדים': 4.0,
      'משפחה בת 6 נפשות': 4.0,
      'דירה למשפחה בתל אביב': 3.0,
    };
    cases.forEach((q, want) {
      test('$q → $want', () => expect(SmartSearch.parse(q).minRooms, want));
    });
    test('explicit rooms / non-family untouched', () {
      expect(SmartSearch.parse('דירת 3 חדרים בתל אביב').minRooms, 3.0);
      expect(SmartSearch.parse('זוג צעיר בתל אביב').minRooms, 2.0);
      expect(SmartSearch.parse('דירה בתל אביב עד 6000').minRooms, isNull);
      expect(SmartSearch.parse('אחרי שהילדים עזבו דירה קטנה יותר').minRooms, 2.0);
    });
    test('3-kid family ranks a 4-room above a 2-room in the same band', () {
      final cat = [
        f('r2', 2.0, 6500), f('r3', 3.0, 6800), f('r4', 4.0, 7000),
        for (var i = 0; i < 6; i++) f('bg$i', 3.0 + (i % 3), 6000 + i * 200),
      ];
      final q = SmartSearch.parse('דירה למשפחה עם 3 ילדים בתל אביב עד 8000');
      final res = RecommendationEngine.recommendAsScored(
          candidates: cat, query: q, limit: 20, seed: 3);
      int rank(String id) => res.indexWhere((s) => s.property.id == id);
      expect(rank('r4') < rank('r2'), true);
    });
  });

  test('a bare-city search flags an adjacent-town match and sorts it last', () {
    // Bare "בתל אביב" (NOT "אזור") with ≥3 in-city listings clustered ~32.08,34.78
    // + one strong-fit רמת גן listing hugging the border (~2 km from the centroid).
    final cat = [
      for (var i = 0; i < 5; i++) f('tlv$i', 3.0, 6000 + i * 80),
      RentalProperty(
        id: 'rg', price: 6000, rooms: 3.0, sizeM2: 84, floor: '2',
        totalFloors: '6', city: 'רמת גן', neighborhood: '', street: 'ביאליק',
        streetNumber: 3, lat: 32.075, lon: 34.800, propertyType: 'דירה',
        transactionType: PropertyTransactionType.rent, entryDate: '',
        condition: 'טוב', ownerName: 'o', agencyListing: false,
        features: const [],
        media: const [
          PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
        ],
      ),
    ];
    final q = SmartSearch.parse('דירת 3 חדרים בתל אביב עד 7000');
    final res = RecommendationEngine.recommendAsScored(
        candidates: cat, query: q, limit: 20, seed: 5);
    final rgIdx = res.indexWhere((s) => s.property.id == 'rg');
    expect(rgIdx >= 0, true, reason: 'the adjacent strong-fit listing should surface');
    // It must carry the 📍 neighbour flag and sit after every in-city result.
    expect(res[rgIdx].tags.any((t) => t.startsWith('📍')), true,
        reason: 'neighbour-city listing must carry the 📍 flag');
    final lastInCity = res.lastIndexWhere((s) => s.property.city == 'תל אביב');
    expect(rgIdx > lastInCity, true,
        reason: 'neighbour-city listing must sort after in-city results');
  });
}
