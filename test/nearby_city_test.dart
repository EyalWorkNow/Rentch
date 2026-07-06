import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Tel Aviv centre; a neighbour ~2.5km away (adjacent); a town ~9km away (its own).
RentalProperty prop(String id, String city, double lat, double lon,
        {int price = 6000, double rooms = 3}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: 80, floor: '2',
      totalFloors: '5', city: city, neighborhood: '', street: 'x',
      streetNumber: 1, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'o', agencyListing: false,
      features: const ['ac', 'elevator', 'balcony'],
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
      marketSignals: const PropertyMarketSignals(views: 20, likes: 3, saves: 2),
      verification: PropertyVerification.cameraVideo(
          videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

void main() {
  // 3 Tel Aviv listings (ample stock → the tight gate) + a strong Ramat Gan
  // listing ~2.5km from the TLV centroid + a Rishon listing ~14km away.
  final cat = <RentalProperty>[
    prop('tlv-1', 'תל אביב', 32.0853, 34.7818),
    prop('tlv-2', 'תל אביב', 32.0880, 34.7840),
    prop('tlv-3', 'תל אביב', 32.0820, 34.7790),
    prop('rg-near', 'רמת גן', 32.0870 + 0.012, 34.7818 + 0.018), // ~2.5km
    prop('rishon-far', 'ראשון לציון', 31.9730, 34.7925), // ~13km
  ];

  test('adjacent town (≤4km) can surface with a "בעיר שכנה" reason; a far town cannot',
      () {
    final q = SmartSearch.parse('דירה בתל אביב 3 חדרים');
    final res = RecommendationEngine.recommendAsScored(
        candidates: cat, query: q, limit: 10, seed: 1);
    final cities = res.map((s) => s.property.city).toSet();

    // The far town (its own city, ~13km) must NEVER leak in.
    expect(cities.contains('ראשון לציון'), isFalse,
        reason: 'a distinct far city must not leak: $cities');

    // If the adjacent Ramat Gan listing is shown, it MUST carry the reason and be
    // a strong (>70%) match — it is only ever a highlighted bonus, never noise.
    final rg = res.where((s) => s.property.id == 'rg-near').toList();
    if (rg.isNotEmpty) {
      expect(rg.single.score, greaterThan(0.70),
          reason: 'nearby-city results are kept only above 70%');
      expect(rg.single.tags.any((t) => t.contains('בעיר שכנה')), isTrue,
          reason: 'the nearby listing must explain WHY it was suggested');
    }

    // Tel Aviv itself is always present.
    expect(cities.contains('תל אביב'), isTrue);
  });
}
