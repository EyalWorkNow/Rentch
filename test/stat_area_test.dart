import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies the CBS statistical-area layer: point-in-polygon resolves a flat's
// own block, and its block-level SES OVERRIDES the city average so two flats in
// the SAME city (תל אביב) but different blocks rank differently for "שכונה טובה".

Future<String> _diskReader(String p) => File(p).readAsString();

RentalProperty flat(String id, double lat, double lon) => RentalProperty(
      id: id, price: 8000, rooms: 3, sizeM2: 80, floor: '3', totalFloors: '20',
      city: 'תל אביב', neighborhood: '', street: 'הרצל', streetNumber: 10,
      lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'x', agencyListing: false, features: const [],
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: const PropertyMarketSignals(views: 120, likes: 14, saves: 4),
      verification: PropertyVerification.cameraVideo(
          videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

int rankOf(List<ScoredProperty> l, String id) =>
    l.indexWhere((s) => s.property.id == id);

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: _diskReader);
  });

  test('point-in-polygon resolves the block (and null outside)', () {
    expect(GovData.instance.statAreaAt(32.05, 34.75)?.ses, 2);   // low-SES block
    expect(GovData.instance.statAreaAt(32.09, 34.79)?.ses, 9);   // high-SES block
    expect(GovData.instance.statAreaAt(32.07, 34.77), isNull);   // no polygon here
    expect(GovData.instance.statAreaAt(double.infinity, 34.0), isNull);
  });

  test('"שכונה טובה" ranks the high-SES block above the low-SES block (same city)',
      () {
    final cat = [
      flat('poor-block', 32.05, 34.75), // inside the ses=2 polygon
      flat('rich-block', 32.09, 34.79), // inside the ses=9 polygon
    ];
    final recs = RecommendationEngine.recommendAsScored(
      candidates: cat,
      query: SmartSearch.parse('דירה בשכונה טובה בתל אביב עד 9000'),
      profile: null, limit: 8, seed: 7,
    );
    expect(recs.length, 2);
    expect(rankOf(recs, 'rich-block') < rankOf(recs, 'poor-block'), true,
        reason: 'the high-SES micro-block should outrank the low-SES one');
    final nb = recs.first.scorecard!.dimensions.where((d) => d.key == 'neighborhood');
    expect(nb.isNotEmpty && nb.first.weightPct > 0, true,
        reason: 'neighborhood dimension not engaged');
  });
}
