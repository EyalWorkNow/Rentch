import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/govdata/gov_sources.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies the future-infrastructure layer: a flat near a PLANNED metro/light-rail
// station (or urban-renewal project) reads as higher investor upside, and an
// investment/growth query ranks it above one with no planned infra nearby.

Future<String> _diskReader(String p) => File(p).readAsString();

RentalProperty saleFlat(String id, double lat, double lon) => RentalProperty(
      id: id, price: 2500000, rooms: 3, sizeM2: 80, floor: '3', totalFloors: '20',
      city: 'תל אביב', neighborhood: '', street: 'הרצל', streetNumber: 10,
      lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: PropertyTransactionType.sale, entryDate: '',
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

  test('growth intent fires on upside phrasing', () {
    for (final q in ['דירה עם פוטנציאל השבחה', 'אזור פינוי בינוי',
      'קרוב למטרו העתידי', 'urban renewal upside']) {
      expect(SmartSearch.parse(q).intents.contains(SearchIntent.growth), true,
          reason: 'growth intent missing for "$q"');
    }
  });

  test('futureValueScore is high on a planned station, ~0 far away', () {
    // On an actual sampled under-construction line point in central TLV.
    expect(GovData.instance.futureValueScore(32.0619, 34.7872) > 0.8, true);
    // Deep Arava desert — 67km from any planned line → ~0.
    expect(GovData.instance.futureValueScore(30.35, 35.10) < 0.1, true);
    expect(GovData.instance.futureValueScore(double.infinity, 34.0), 0.0);
  });

  test('an investor-with-upside query ranks the near-metro flat first', () {
    final cat = [
      saleFlat('near-metro', 32.090, 34.800), // on a planned station
      saleFlat('far', 32.02, 34.73),          // no planned infra nearby
    ];
    final recs = RecommendationEngine.recommendAsScored(
      candidates: cat,
      query: SmartSearch.parse('דירה להשקעה עם פוטנציאל השבחה בתל אביב עד 3 מיליון'),
      profile: null, limit: 8, seed: 7,
    );
    expect(recs, isNotEmpty);
    expect(recs.every((r) => r.property.transactionType == PropertyTransactionType.sale),
        true, reason: 'investor search must be sale-only');
    expect(rankOf(recs, 'near-metro') < rankOf(recs, 'far'), true,
        reason: 'near a planned station should outrank no-upside');
    final fv = recs.first.scorecard!.dimensions.where((d) => d.key == 'future_value');
    expect(fv.isNotEmpty && fv.first.weightPct > 0, true,
        reason: 'future_value dimension not engaged');
  });

  test('future_value dimension carries provenance', () {
    expect(GovSources.forDimension('future_value'), isNotNull);
  });
}
