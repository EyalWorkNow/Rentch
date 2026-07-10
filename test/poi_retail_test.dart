import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/govdata/gov_sources.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies the new retail/errands POI map-layer end-to-end:
// intent ("ליד סופר") → GovData.retailAccessScore → 'convenience' dimension
// engaged in ranking, plus graceful degradation for a coord with no POI cell.

Future<String> _diskReader(String p) => File(p).readAsString();

RentalProperty flat(String id, double lat, double lon) => RentalProperty(
      id: id, price: 6500, rooms: 3, sizeM2: 80, floor: '3', totalFloors: '20',
      city: 'תל אביב', neighborhood: '', street: 'הרצל', streetNumber: 10,
      lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'x', agencyListing: false, features: const [],
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: const PropertyMarketSignals(views: 120, likes: 14, saves: 4),
      verification: PropertyVerification.cameraVideo(
          videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: _diskReader);
  });

  test('"ליד סופר" / "מרכז קניות" set the convenience intent', () {
    for (final q in ['דירה ליד סופר בתל אביב', 'קרוב למרכז קניות',
      'ליד קניון', 'near a supermarket']) {
      expect(SmartSearch.parse(q).intents.contains(SearchIntent.convenience),
          true, reason: 'convenience intent missing for "$q"');
    }
  });

  test('retailAccessScore is >0 in a retail-dense cell, 0 in an empty one', () {
    // Tel Aviv centre sits in a seeded dense cell.
    expect(GovData.instance.retailAccessScore(32.072, 34.781) > 0, true);
    // A remote desert coord has no POI cell → neutral 0 (degrades, no crash).
    // Mitzpe-Ramon (30.61,34.80) now has real shops under the NATIONAL data, so
    // use the truly-empty deep Arava instead.
    expect(GovData.instance.retailAccessScore(30.35, 35.10), 0.0);
  });

  test('convenience dimension is ENGAGED in ranking for an errands query', () {
    final cat = [flat('a', 32.072, 34.781), flat('b', 32.07, 34.78)];
    final recs = RecommendationEngine.recommendAsScored(
      candidates: cat,
      query: SmartSearch.parse('דירה ליד סופר ומרכז קניות בתל אביב עד 8000'),
      profile: null, limit: 8, seed: 7,
    );
    expect(recs, isNotEmpty);
    final conv = recs.first.scorecard!.dimensions
        .where((d) => d.key == 'convenience');
    expect(conv.isNotEmpty && conv.first.weightPct > 0, true,
        reason: 'convenience dimension not driving ranking');
  });

  test('the convenience dimension carries a data source (provenance)', () {
    expect(GovSources.forDimension('convenience'), isNotNull);
  });
}
