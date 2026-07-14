// FTRL closure — step 2: prove the LOOP is wired end-to-end at the engine level.
//   rank → learnerFeatureSink is populated for shown listings;
//   those vectors feed a learner; the learner is accepted back into ranking.
import 'dart:io';
import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/preference_model.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> _disk(String p) => File(p).readAsString();

RentalProperty f(String id, int price, double rooms, String city, double lat,
        double lon) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: 70, floor: '3',
      totalFloors: '6', city: city, neighborhood: '', street: 'הרצל',
      streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'x', agencyListing: false,
      features: const [],
      media: const [PropertyMedia(url: 'u', type: PropertyMediaType.image)],
    );

List<RentalProperty> catalog() => [
      for (var i = 0; i < 10; i++)
        f('ta$i', 6000 + i * 200, 3, 'תל אביב', 32.07 + i * 0.001, 34.78),
      for (var i = 0; i < 6; i++)
        f('hf$i', 4200 + i * 150, 3, 'חיפה', 32.79, 34.99 + i * 0.001),
    ];

void main() {
  setUpAll(() async {
    GovData.instance.resetForTest();
    await GovData.instance.init(reader: _disk);
  });
  tearDownAll(() => GovData.instance.resetForTest());

  test('recommend() populates the learnerFeatureSink for shown listings', () {
    final sink = <String, Map<String, double>>{};
    final recs = RecommendationEngine.recommend(
      candidates: catalog(),
      query: SmartSearch.parse('דירה בתל אביב'),
      limit: 5,
      learnerFeatureSink: sink,
    );
    expect(recs, isNotEmpty);
    // every SHOWN listing has a stashed feature vector...
    for (final r in recs) {
      expect(sink.containsKey(r.property.id), isTrue,
          reason: '${r.property.id} should have a stashed pfv');
      expect(sink[r.property.id], contains('bias')); // learnerFeatures shape
      expect(sink[r.property.id]!.length, greaterThan(3));
    }
  });

  test('a learner fed from the sink is accepted back into ranking (loop closes)',
      () {
    final sink = <String, Map<String, double>>{};
    RecommendationEngine.recommend(
      candidates: catalog(),
      query: SmartSearch.parse('דירה בתל אביב'),
      limit: 8,
      learnerFeatureSink: sink,
    );
    // Feed real "swipes" from the stashed vectors into a fresh learner.
    final learner = OnlineLogisticLearner();
    var i = 0;
    for (final feats in sink.values) {
      learner.update(feats, (i++).isEven ? 1.0 : 0.0);
    }
    expect(learner.updates, sink.length);
    expect(learner.confidence, greaterThan(0.0));
    // Re-rank WITH the learned model — must not throw and still returns results
    // (the learner is confidence-blended inside the ranker).
    final recs2 = RecommendationEngine.recommend(
      candidates: catalog(),
      query: SmartSearch.parse('דירה בתל אביב'),
      limit: 5,
      learner: learner,
    );
    expect(recs2, isNotEmpty);
    // persistence round-trip keeps the fed learner usable
    final restored = OnlineLogisticLearner.fromJson(learner.toJson());
    expect(restored.updates, learner.updates);
  });
}
