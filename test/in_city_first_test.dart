import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Locks: for an EXPLICIT city (not "אזור X"), an in-city flat always ranks above
// an adjacent-town one, fit% stays monotonic, and demographic proxies
// (senior_area/young_area) are never shown as "concerns".

Future<String> _r(String p) => File(p).readAsString();

RentalProperty f(String id, int price, double rooms, String city, double lat, double lon,
        {int? m2, List<String> ft = const []}) =>
    RentalProperty(id: id, price: price, rooms: rooms, sizeM2: m2 ?? (rooms * 26).round(), floor: '3', totalFloors: '20',
        city: city, neighborhood: '', street: 'הרצל', streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
        transactionType: PropertyTransactionType.rent, entryDate: '', condition: 'טוב', ownerName: 'x',
        agencyListing: false, features: ft,
        media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
        marketSignals: const PropertyMarketSignals(views: 130, likes: 20, saves: 6),
        verification: PropertyVerification.cameraVideo(videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)));

List<RentalProperty> cat() => [
  f('ta-a', 7500, 3, 'תל אביב', 32.072, 34.790, ft: ['elevator', 'ac']),
  f('ta-b', 8000, 3, 'תל אביב', 32.072, 34.781, ft: ['elevator', 'balcony']),
  f('rg-strong', 7000, 3, 'רמת גן', 32.083, 34.814, m2: 108, ft: ['elevator', 'renovated', 'balcony']),
];

void main() {
  setUpAll(() async { TestWidgetsFlutterBinding.ensureInitialized(); await GovData.instance.init(reader: _r); });

  List<ScoredProperty> run(String q) => RecommendationEngine.recommendAsScored(
      candidates: cat(), query: SmartSearch.parse(q), profile: null, limit: 5, seed: 7);

  test('explicit city: an in-city flat leads over a stronger neighbour, monotonic', () {
    final recs = run('דירה באזור צעיר קרוב לעבודה בתל אביב עד 8000');
    expect(recs.first.property.city.contains('תל אביב'), true,
        reason: 'top result for "בתל אביב" must be in Tel Aviv, got ${recs.first.property.city}');
    for (var i = 1; i < recs.length; i++) {
      expect(recs[i - 1].scorecard!.fitPct >= recs[i].scorecard!.fitPct, true,
          reason: 'fit% must stay monotonic');
    }
  });

  test('"אזור X" search still lets a neighbour lead (expansion intact)', () {
    final recs = run('דירה באזור תל אביב עד 8000');
    // rg-strong is the strongest and, in an AREA search, may lead — the point is
    // the neighbour is NOT demoted below in-city here.
    expect(recs.any((s) => s.property.city == 'רמת גן'), true);
    expect(recs.first.property.city == 'רמת גן', true,
        reason: 'an area search ranks by fit; the strong neighbour should lead');
  });

  test('senior_area / young_area are never shown as concerns', () {
    final recs = run('דירה שקטה בתל אביב עד 8000');
    for (final s in recs) {
      final c = s.scorecard!.concerns.join(' ');
      expect(c.contains('שקט ומבוגר') || c.contains('צעיר'), false,
          reason: 'demographic proxy shown as a concern: ${s.scorecard!.concerns}');
    }
  });
}
