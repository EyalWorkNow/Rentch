// #3 perf: the market baseline is cached (catalogue-constant). This pins the two
// correctness properties: a cache HIT is transparent (same list ⇒ identical
// ranking), and the key INVALIDATES when the catalogue changes (append/replace).
import 'dart:io';
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> _disk(String p) => File(p).readAsString();

RentalProperty f(String id, int price, double rooms) => RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: 70, floor: '3',
      totalFloors: '6', city: 'תל אביב', neighborhood: '', street: 'הרצל',
      streetNumber: 10, lat: 32.07, lon: 34.78, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'x', agencyListing: false, features: const [],
      media: const [PropertyMedia(url: 'u', type: PropertyMediaType.image)],
    );

List<String> ids(List<Recommendation> r) => r.map((x) => x.property.id).toList();
List<int> fits(List<Recommendation> r) => r.map((x) => x.fitPct).toList();

void main() {
  setUpAll(() async {
    GovData.instance.resetForTest();
    await GovData.instance.init(reader: _disk);
  });
  tearDownAll(() => GovData.instance.resetForTest());

  final q = SmartSearch.parse('דירה בתל אביב');

  test('cache HIT is transparent: same list twice ⇒ identical ranking', () {
    final cat = [for (var i = 0; i < 14; i++) f('a$i', 5000 + i * 250, 3)];
    // explore:false so the exploration policy doesn't legitimately vary the tail —
    // then any difference would be the cached baseline corrupting the scoring.
    final r1 = RecommendationEngine.recommend(
        candidates: cat, query: q, limit: 6, explore: false);
    final r2 = RecommendationEngine.recommend(
        candidates: cat, query: q, limit: 6, explore: false);
    expect(ids(r2), ids(r1));
    expect(fits(r2), fits(r1)); // identical fit% ⇒ baseline reused, not corrupted
  });

  test('appending to the catalogue invalidates the baseline', () {
    final cat = [for (var i = 0; i < 14; i++) f('b$i', 5000 + i * 250, 3)];
    RecommendationEngine.recommend(candidates: cat, query: q, limit: 6); // warm
    // Append a cluster of very cheap listings → the price distribution shifts, so
    // the previously-mid-priced flats now read as relatively expensive.
    final grown = [...cat, for (var i = 0; i < 10; i++) f('cheap$i', 2500, 3)];
    final rGrown =
        RecommendationEngine.recommend(candidates: grown, query: q, limit: 8);
    // The new cheap listings must surface (baseline recomputed, not stale).
    expect(rGrown.any((r) => r.property.id.startsWith('cheap')), isTrue,
        reason: 'a stale baseline would ignore the new cheaper stock');
  });

  test('a different catalogue is not served a stale baseline', () {
    final cheapCat = [for (var i = 0; i < 12; i++) f('lo$i', 3000 + i * 50, 3)];
    final pricyCat = [for (var i = 0; i < 12; i++) f('hi$i', 12000 + i * 300, 3)];
    final rCheap =
        RecommendationEngine.recommend(candidates: cheapCat, query: q, limit: 4);
    final rPricy =
        RecommendationEngine.recommend(candidates: pricyCat, query: q, limit: 4);
    // Distinct catalogues ⇒ distinct id sets (no cross-contamination).
    expect(ids(rCheap).toSet().intersection(ids(rPricy).toSet()), isEmpty);
  });
}
