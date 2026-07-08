import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/govdata/gov_sources.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies the road/rail NOISE layer: a flat on a major artery reads as loud,
// one away from it as quiet, and "מקום שקט" ranks the quiet one higher.

Future<String> _diskReader(String p) => File(p).readAsString();

RentalProperty flat(String id, double lat, double lon) => RentalProperty(
      id: id, price: 7000, rooms: 3, sizeM2: 80, floor: '3', totalFloors: '20',
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

  test('roadNoiseScore: loud on an artery, quiet away, null when unknown', () {
    // On a seeded Ayalon cell → loud.
    expect(GovData.instance.roadNoiseScore(32.072, 34.790), 1.0);
    // Away from any artery cell → quiet.
    expect(GovData.instance.roadNoiseScore(32.09, 34.77), 0.0);
    // Invalid coord → null (unknown, not silent-quiet).
    expect(GovData.instance.roadNoiseScore(double.infinity, double.infinity), isNull);
  });

  test('"מקום שקט" ranks the road-adjacent flat below the quiet one', () {
    final cat = [
      flat('noisy', 32.072, 34.790), // on the Ayalon cell
      flat('quiet', 32.09, 34.77),   // away from arteries
    ];
    final recs = RecommendationEngine.recommendAsScored(
      candidates: cat,
      query: SmartSearch.parse('דירה במקום שקט בתל אביב עד 9000'),
      profile: null, limit: 8, seed: 7,
    );
    expect(recs.length, 2);
    expect(rankOf(recs, 'quiet') < rankOf(recs, 'noisy'), true,
        reason: 'quiet flat should outrank the road-adjacent one');
    // low_noise dimension must be engaged (driving the ranking).
    final ln = recs.first.scorecard!.dimensions.where((d) => d.key == 'low_noise');
    expect(ln.isNotEmpty && ln.first.weightPct > 0, true,
        reason: 'low_noise dimension not engaged');
  });

  test('low_noise dimension carries provenance', () {
    expect(GovSources.forDimension('low_noise'), isNotNull);
  });
}
