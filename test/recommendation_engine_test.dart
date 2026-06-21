import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// ── helpers ───────────────────────────────────────────────────────────────────

RentalProperty prop({
  required String id,
  int price = 6000,
  double rooms = 3,
  int sizeM2 = 70,
  String city = 'תל אביב',
  String neighborhood = '',
  double lat = 32.07,
  double lon = 34.78,
  List<String> features = const [],
  PropertyMarketSignals? signals,
  bool verified = false,
  DateTime? createdAt,
}) {
  return RentalProperty(
    id: id,
    price: price,
    rooms: rooms,
    sizeM2: sizeM2,
    floor: '2',
    totalFloors: '5',
    city: city,
    neighborhood: neighborhood,
    street: 'הרצל',
    streetNumber: 10,
    lat: lat,
    lon: lon,
    propertyType: 'דירה',
    entryDate: '',
    condition: 'טוב',
    ownerName: 'בעלים',
    agencyListing: false,
    features: features,
    media: const [
      PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image),
    ],
    marketSignals: signals,
    verification: verified
        ? PropertyVerification.cameraVideo(
            videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1))
        : null,
    createdAt: createdAt,
  );
}

// A realistic-ish background market so MarketContext/hedonic have data to fit.
List<RentalProperty> backgroundMarket() => [
      for (var i = 0; i < 14; i++)
        prop(
          id: 'bg$i',
          price: 5500 + i * 350,
          rooms: 2 + (i % 4).toDouble(),
          sizeM2: 55 + i * 6,
          lat: 32.06 + i * 0.002,
          lon: 34.77 + i * 0.002,
          signals: PropertyMarketSignals(views: 40 + i, likes: 5 + i, saves: 2),
        ),
    ];

int rankOf(List<Recommendation> recs, String id) =>
    recs.indexWhere((r) => r.property.id == id);

void main() {
  test('canonicalFeatureKey bridges the feat_ namespace bug', () {
    expect(canonicalFeatureKey('feat_pets'), 'petsAllowed');
    expect(canonicalFeatureKey('feat_parking'), 'parking');
    expect(canonicalFeatureKey('renovated'), 'renovated'); // passthrough
  });

  test('propertyHasFeature honours feat_ query keys against catalogue', () {
    final p = prop(id: 'p', features: ['parking']);
    expect(propertyHasFeature(p, 'feat_parking'), true);
    expect(propertyHasFeature(p, 'feat_pets'), false);
  });

  test('ranks descending by fit and never dead-ends', () {
    final candidates = [
      ...backgroundMarket(),
      prop(id: 'target', price: 6000, rooms: 3),
    ];
    final q = SmartSearch.parse('דירת 3 חדרים בתל אביב עד 7000');
    final recs = RecommendationEngine.recommend(
      candidates: candidates,
      query: q,
      limit: 8,
      explore: false,
    );
    expect(recs.isNotEmpty, true);
    for (var i = 1; i < recs.length; i++) {
      expect(recs[i - 1].fitScore >= recs[i].fitScore, true);
    }
  });

  test('in-budget property outranks an identical over-budget one', () {
    final candidates = [
      ...backgroundMarket(),
      prop(id: 'inBudget', price: 6500),
      prop(id: 'overBudget', price: 13000),
    ];
    final q = SmartSearch.parse('דירה בתל אביב עד 7000');
    final recs = RecommendationEngine.recommend(
      candidates: candidates,
      query: q,
      limit: 20,
      explore: false,
    );
    expect(rankOf(recs, 'inBudget') < rankOf(recs, 'overBudget'), true);
  });

  test('requested amenity present outranks absent (feat_ bug fixed)', () {
    final candidates = [
      ...backgroundMarket(),
      prop(id: 'withParking', price: 6500, features: ['parking']),
      prop(id: 'noParking', price: 6500, features: const []),
    ];
    final q = SmartSearch.parse('דירה בתל אביב עם חניה עד 7000');
    expect(q.amenities.contains('feat_parking'), true);
    final recs = RecommendationEngine.recommend(
      candidates: candidates,
      query: q,
      limit: 20,
      explore: false,
    );
    expect(rankOf(recs, 'withParking') < rankOf(recs, 'noParking'), true);
  });

  test('matching city outranks a far wrong-city listing', () {
    final candidates = [
      ...backgroundMarket(),
      prop(id: 'rightCity', city: 'תל אביב', price: 6500),
      prop(
        id: 'wrongCity',
        city: 'באר שבע',
        price: 6500,
        lat: 31.25,
        lon: 34.79,
      ),
    ];
    final q = SmartSearch.parse('דירה בתל אביב עד 7000');
    final recs = RecommendationEngine.recommend(
      candidates: candidates,
      query: q,
      limit: 20,
      explore: false,
    );
    expect(rankOf(recs, 'rightCity') < rankOf(recs, 'wrongCity'), true);
  });

  test('Wilson bound: confident demand beats a lucky 1/1', () {
    final candidates = [
      ...backgroundMarket(),
      prop(
        id: 'proven',
        price: 6500,
        signals: const PropertyMarketSignals(
            views: 500, likes: 400, saves: 50, contactRequests: 30),
      ),
      prop(
        id: 'lucky',
        price: 6500,
        signals: const PropertyMarketSignals(views: 1, likes: 1),
      ),
    ];
    final q = SmartSearch.parse('דירה בתל אביב עד 7000');
    final recs = RecommendationEngine.recommend(
      candidates: candidates,
      query: q,
      limit: 20,
      explore: false,
    );
    expect(rankOf(recs, 'proven') < rankOf(recs, 'lucky'), true);
  });

  test('hedonic value model flags an underpriced unit', () {
    final candidates = [
      ...backgroundMarket(),
      // large flat priced like a small one ⇒ great value
      prop(id: 'deal', price: 6000, rooms: 5, sizeM2: 130),
      // small flat priced like a large one ⇒ poor value
      prop(id: 'ripoff', price: 9500, rooms: 2, sizeM2: 45),
    ];
    final market = MarketContext.analyze(candidates);
    final deal = FeatureEngineer.engineer(
        candidates.firstWhere((p) => p.id == 'deal'), market);
    final ripoff = FeatureEngineer.engineer(
        candidates.firstWhere((p) => p.id == 'ripoff'), market);
    expect(deal.valueScore > ripoff.valueScore, true);
  });

  test('results are diverse (no duplicate properties)', () {
    final candidates = [
      ...backgroundMarket(),
      for (var i = 0; i < 6; i++) prop(id: 'extra$i', price: 6200 + i * 50),
    ];
    final q = SmartSearch.parse('דירה בתל אביב עד 8000');
    final recs = RecommendationEngine.recommend(
      candidates: candidates,
      query: q,
      limit: 10,
      explore: false,
    );
    final ids = recs.map((r) => r.property.id).toSet();
    expect(ids.length, recs.length);
  });

  test('every recommendation carries an explanation', () {
    final candidates = [
      ...backgroundMarket(),
      prop(id: 'nice', price: 6000, features: ['parking', 'elevator'], verified: true),
    ];
    final q = SmartSearch.parse('דירה בתל אביב עם חניה עד 7000');
    final recs = RecommendationEngine.recommend(
      candidates: candidates,
      query: q,
      limit: 5,
      explore: false,
    );
    expect(recs.every((r) => r.explanation.isNotEmpty), true);
    expect(recs.first.fitPct >= 0 && recs.first.fitPct <= 100, true);
  });

  test('SmartSearch.rankAdvanced delegates without throwing', () {
    final candidates = [
      ...backgroundMarket(),
      prop(id: 't', price: 6000),
    ];
    final q = SmartSearch.parse('דירת 3 חדרים בתל אביב עד 7000 עם מרפסת');
    final scored = SmartSearch.rankAdvanced(candidates, q, limit: 6);
    expect(scored.isNotEmpty, true);
    expect(scored.first.tags.any((t) => t.contains('התאמה')), true);
  });
}
