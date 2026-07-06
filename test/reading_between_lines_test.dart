import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

RentalProperty prop(String id, double lat, double lon,
        {int price = 3000, double rooms = 2}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: 55, floor: '2', totalFloors: '5',
      city: 'תל אביב', neighborhood: '', street: 'x', streetNumber: 1,
      lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'o', agencyListing: false, features: const ['ac'],
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: const PropertyMarketSignals(views: 10, likes: 1, saves: 1),
      verification: PropertyVerification.cameraVideo(
          videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)));

void main() {
  // Two identical ₪3,000 flats — one next to a Tel Aviv train station, one far.
  final nearStation = prop('near', 32.0836, 34.7980); // ~Savidor Center
  final farFromStation = prop('far', 32.0500, 34.7550); // south-west, off the rail

  test('low budget (₪3,000) softly lifts the transit-adjacent flat', () {
    // The seeker never SAID "near transit" — only a low budget. The inference
    // (low budget → likely no car → transit matters) should nudge the station
    // flat to the top, without either being explicitly requested.
    final q = SmartSearch.parse('דירה בתל אביב עד 3000');
    final res = RecommendationEngine.recommendAsScored(
        candidates: [farFromStation, nearStation], query: q, limit: 5, seed: 1);
    expect(res.first.property.id, 'near',
        reason: 'transit nudge should rank the station flat first');
  });
}
