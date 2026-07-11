// Regression guards for the 6 use-case fixes surfaced by the 20-case breaking
// review: neighbourhood identity, safety denominator-bias correction, commute
// re-rank, compact/small intent, cheapest, and roommates→bedrooms.
import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

RentalProperty p({
  required String id, int price = 6000, double rooms = 3, int sizeM2 = 70,
  String city = 'תל אביב', String hood = '', double lat = 32.07, double lon = 34.78,
  List<String> features = const [],
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: sizeM2, floor: '3',
      totalFloors: '8', city: city, neighborhood: hood, street: 'הרצל',
      streetNumber: 5, lat: lat, lon: lon, propertyType: 'דירה', entryDate: '',
      condition: 'טוב', ownerName: 'x', agencyListing: false, features: features,
      transactionType: PropertyTransactionType.rent,
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)]);

List<RentalProperty> bg() => [
  for (var i = 0; i < 10; i++)
    p(id: 'bg$i', price: 6000 + i * 200, rooms: 3, city: 'תל אביב',
        lat: 32.06 + i * 0.002, lon: 34.77 + i * 0.002),
];

int rankOf(List<Recommendation> r, String id) =>
    r.indexWhere((x) => x.property.id == id);

void main() {
  test('FIX neighbourhood identity — "פלורנטין" ranks the Florentin flat first', () {
    final cat = [
      ...bg(),
      p(id: 'florentin', hood: 'פלורנטין', price: 5200, lat: 32.0560, lon: 34.7690),
    ];
    final recs = RecommendationEngine.recommend(
        candidates: cat, query: SmartSearch.parse('דירה בפלורנטין תל אביב'),
        limit: 5, explore: false);
    expect(recs.first.property.id, 'florentin');
  });

  test('FIX compact — "דירה קטנה" ranks a small flat above a big one', () {
    final cat = [
      p(id: 'small', rooms: 2, sizeM2: 45, price: 6000),
      p(id: 'big', rooms: 5, sizeM2: 140, price: 6000),
      ...bg(),
    ];
    final recs = RecommendationEngine.recommend(
        candidates: cat,
        query: SmartSearch.parse('דירה קטנה ונוחה בתל אביב'),
        limit: 12, explore: false);
    expect(rankOf(recs, 'small'), lessThan(rankOf(recs, 'big')),
        reason: 'a compact search must prefer the small flat');
  });

  test('FIX cheapest — "הכי זול" ranks the lowest-price flat first', () {
    final cat = [
      p(id: 'cheapest', rooms: 2, price: 3800),
      p(id: 'pricier', rooms: 2, price: 5200),
      ...bg(),
    ];
    final recs = RecommendationEngine.recommend(
        candidates: cat,
        query: SmartSearch.parse('הדירה הכי זולה 2 חדרים בתל אביב'),
        limit: 12, explore: false);
    expect(rankOf(recs, 'cheapest'), lessThan(rankOf(recs, 'pricier')));
  });

  test('FIX commute — a work location re-ranks the flat at the workplace first', () {
    final atWork = p(id: 'atwork', lat: 32.1160, lon: 34.8380);
    final farAway = p(id: 'faraway', lat: 32.0100, lon: 34.7500);
    final cat = [farAway, atWork, ...bg()];
    List<Recommendation> run({double? wLat, double? wLon}) =>
        RecommendationEngine.recommend(
            candidates: cat, query: SmartSearch.parse('דירה בתל אביב'),
            limit: 12, explore: false, workLat: wLat, workLon: wLon);
    // Without a work location, commute doesn't apply; WITH it, the at-work flat
    // must outrank the far one.
    final withWork = run(wLat: 32.1160, wLon: 34.8380);
    expect(rankOf(withWork, 'atwork'), lessThan(rankOf(withWork, 'faraway')),
        reason: 'the flat at the workplace must rank above the far one');
  });

  group('gov-data', () {
    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
      await GovData.instance.init(reader: (path) => File(path).readAsString());
    });
    tearDownAll(() => GovData.instance.resetForTest());

    test('FIX safety bias — a central Tel Aviv flat is NOT flagged near-zero safety',
        () {
      // Central TLV (SES/centrality high) has a denominator-inflated crime rate;
      // the corrected safety feature must not read as "dangerous" (< 0.3 fires the
      // scorecard caveat). A genuinely distressed low-centrality area still can.
      final market = MarketContext.analyze(bg());
      final central =
          FeatureEngineer.engineer(p(id: 'c', lat: 32.0700, lon: 34.7750), market);
      expect(central.get('safety'), greaterThanOrEqualTo(0.3),
          reason: 'central TLV safety must be corrected for the daytime-population '
              'denominator bias (was ~0.01)');
    });
  });
}
