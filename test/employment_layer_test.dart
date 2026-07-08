import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/govdata/gov_sources.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies the employment layer: "קרוב לעבודה" resolves to real job-hub
// proximity (not just transit), and ranks a flat near a job cluster above one
// in a residential-only area of the same city.

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

  test('"קרוב לעבודה" / "הייטק" set the employment intent', () {
    for (final q in ['דירה קרוב לעבודה בתל אביב', 'ליד פארק הייטק',
      'אזור תעסוקה', 'near work']) {
      expect(SmartSearch.parse(q).intents.contains(SearchIntent.employment),
          true, reason: 'employment intent missing for "$q"');
    }
  });

  test('employmentAccessScore >0 in a job cluster, 0 in a residential area', () {
    expect(GovData.instance.employmentAccessScore(32.072, 34.790) > 0, true);
    expect(GovData.instance.employmentAccessScore(32.02, 34.74), 0.0);
    expect(GovData.instance.employmentAccessScore(double.infinity, 34.0), 0.0);
  });

  test('"קרוב לעבודה" ranks the job-cluster flat above the residential one', () {
    final cat = [
      flat('near-jobs', 32.072, 34.790), // Ayalon business cell
      flat('residential', 32.02, 34.74), // no job cell nearby
    ];
    final recs = RecommendationEngine.recommendAsScored(
      candidates: cat,
      query: SmartSearch.parse('דירה קרוב לעבודה בתל אביב עד 9000'),
      profile: null, limit: 8, seed: 7,
    );
    expect(recs.length, 2);
    expect(rankOf(recs, 'near-jobs') < rankOf(recs, 'residential'), true,
        reason: 'the flat near a job cluster should outrank the residential one');
    final emp = recs.first.scorecard!.dimensions.where((d) => d.key == 'employment');
    expect(emp.isNotEmpty && emp.first.weightPct > 0, true,
        reason: 'employment dimension not engaged');
  });

  test('employment dimension carries provenance', () {
    expect(GovSources.forDimension('employment'), isNotNull);
  });
}
