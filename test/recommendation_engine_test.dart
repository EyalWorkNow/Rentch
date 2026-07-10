import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/preference_model.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/search_intent.dart';
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

  test('stated max budget is a HARD cap — "עד 5000" never shows a ₪5500 flat', () {
    final candidates = [
      ...backgroundMarket(), // all ≥ ₪5500
      prop(id: 'in_a', price: 4800, rooms: 3, city: 'תל אביב'),
      prop(id: 'in_b', price: 4500, rooms: 3, city: 'תל אביב'),
      prop(id: 'in_c', price: 5000, rooms: 3, city: 'תל אביב'), // exactly at the cap
    ];
    final q = SmartSearch.parse('דירת 3 חדרים בתל אביב עד 5000');
    final recs = RecommendationEngine.recommend(
      candidates: candidates,
      query: q,
      limit: 10,
      explore: false,
    );
    expect(recs, isNotEmpty);
    for (final r in recs) {
      expect(r.property.price, lessThanOrEqualTo(5000),
          reason: '${r.property.id} @ ₪${r.property.price} exceeds the ₪5000 cap');
    }
  });

  test('display fit% is honest — a near-match is NOT inflated toward 100%', () {
    // In-budget and right city/rooms, but MISSING both requested amenities → a
    // strong-but-partial match. The OLD cosmetic upper-half expansion
    // (0.5+(m-0.5)*1.5) pushed such a listing to ~100% ("perfect"); honest display
    // must read it as strong-but-not-perfect.
    final candidates = [
      ...backgroundMarket(),
      prop(id: 'target', price: 6800, rooms: 3, city: 'תל אביב', features: const []),
    ];
    final q = SmartSearch.parse('דירת 3 חדרים בתל אביב עד 7000 עם מעלית וחניה');
    final recs = RecommendationEngine.recommend(
      candidates: candidates,
      query: q,
      limit: 10,
      explore: false,
    );
    final target = recs.firstWhere((r) => r.property.id == 'target');
    expect(target.fitPct, lessThan(95)); // would have been ~100 under inflation
    expect(target.fitPct, greaterThan(50)); // still clearly a good match
  });

  test('persona intents reach RANKING weights (not just the nearby card)', () {
    final market = MarketContext.analyze(backgroundMarket());
    UserPreferenceModel model(String q) =>
        PreferenceModelBuilder.build(query: SmartSearch.parse(q), market: market);
    final neutral = model('דירה בתל אביב');
    final single = model('רווק צעיר מחפש דירה בתל אביב');
    final couple = model('זוג מחפש דירה בתל אביב');
    final room = model('שלושה שותפים מחפשים דירה בתל אביב');

    // The distinctive dims start at a 0.0 prior, so any elevation is the persona
    // actually reaching the ranker (location is excluded — the named city already
    // saturates it, so it isn't a clean discriminator).
    expect(single.weight('nightlife'),
        greaterThan(neutral.weight('nightlife')));
    expect(single.weight('young_area'),
        greaterThan(neutral.weight('young_area')));
    expect(couple.weight('nightlife'),
        greaterThan(neutral.weight('nightlife')));
    expect(room.weight('spaciousness'),
        greaterThan(neutral.weight('spaciousness')));
    expect(room.weight('young_area'), greaterThan(neutral.weight('young_area')));
  });

  test('persona detection: single/couple/roommates, with negation guard', () {
    expect(SearchIntent.fromText('רווק שמחפש דירה'),
        contains(SearchIntent.single));
    expect(SearchIntent.fromText('זוג צעיר'), contains(SearchIntent.couple));
    expect(SearchIntent.fromText('שלושה שותפים'),
        contains(SearchIntent.roommates));
    // no false single on a neutral query…
    expect(SearchIntent.fromText('דירת 3 חדרים במרכז'),
        isNot(contains(SearchIntent.single)));
    // …and "לא לבד" (not alone) must be suppressed by the negator.
    expect(
        SearchIntent.fromText('לא לבד'), isNot(contains(SearchIntent.single)));
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
    // The budget gate excludes a listing far over the stated max (₪13k vs ₪7k)
    // when in-budget options exist — stronger than merely ranking it lower.
    expect(rankOf(recs, 'inBudget') >= 0, true);
    expect(rankOf(recs, 'overBudget'), -1);
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
    // The city gate now EXCLUDES the wrong-city listing when the named city has
    // stock (stronger than merely ranking it lower).
    expect(rankOf(recs, 'rightCity') >= 0, true);
    expect(rankOf(recs, 'wrongCity'), -1);
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

  test('recommendAsScored attaches a populated Scorecard with a tier', () {
    final candidates = [
      ...backgroundMarket(),
      prop(
        id: 'star',
        price: 6000,
        features: ['parking', 'elevator', 'petsAllowed'],
        verified: true,
      ),
    ];
    final q = SmartSearch.parse('דירת 3 חדרים בתל אביב עם חניה עד 7000');
    final scored = RecommendationEngine.recommendAsScored(
      candidates: candidates,
      query: q,
      limit: 6,
      seed: 1,
    );
    expect(scored.isNotEmpty, true);
    // Every result must carry a non-null Scorecard with dimensions + a tier.
    for (final s in scored) {
      final card = s.scorecard;
      expect(card, isNotNull, reason: 'scorecard must be attached');
      expect(card!.dimensions, isNotEmpty,
          reason: 'dimensions must be populated');
      expect(card.tier, isNotEmpty, reason: 'tier label required');
      expect(card.fitPct >= 0 && card.fitPct <= 100, true);
      // dimension keys are either scoring dims or known informational axes
      // (commute / total-cost explain but don't re-rank).
      const informational = {'commute', 'total_cost'};
      for (final d in card.dimensions) {
        expect(
            kScoringDimensions.contains(d.key) || informational.contains(d.key),
            true,
            reason: 'dim key ${d.key} aligns with kScoringDimensions');
      }
    }
  });

  test('persona reasons surface for matching tenant tags', () {
    final candidates = [
      ...backgroundMarket(),
      prop(id: 'pet', price: 6000, features: ['petsAllowed', 'parking']),
    ];
    final q = SmartSearch.parse('דירה בתל אביב עד 7000');
    final profile = TenantProfile(
      id: 'u1',
      name: 'דנה',
      bio: '',
      photoUrls: const [],
      budgetMax: 7000,
      desiredRooms: 3,
      moveInWindow: 'מיידי',
      importantDetails: const ['מתאים לחיות מחמד'],
      dealBreakers: const ['מתאים לחיות מחמד'],
    );
    final scored = RecommendationEngine.recommendAsScored(
      candidates: candidates,
      query: q,
      profile: profile,
      limit: 8,
      seed: 1,
    );
    final pet = scored.firstWhere((s) => s.property.id == 'pet');
    expect(pet.scorecard, isNotNull);
    expect(
      pet.scorecard!.personaReasons.any((r) => r.contains('חיות מחמד')),
      true,
      reason: 'pet-friendly persona reason expected',
    );
  });

  // ════════════════════════════════════════════════════════════════════════════
  // CRUSH TESTS — persistent market baseline (#1)
  // The value/percentile/hedonic features must be fit over the WHOLE catalogue,
  // not the per-query filtered set, so a listing's assessment doesn't drift with
  // whoever happens to co-occur in a result page.
  // ════════════════════════════════════════════════════════════════════════════

  test('BASELINE bug is real — per-query market swings a listing\'s value', () {
    // Same target flat, judged against two DIFFERENT competitor pools. The old
    // per-batch behaviour (analyze the filtered set) gives it wildly different
    // value_scores; that instability is exactly what the persistent baseline kills.
    final target = prop(id: 't', price: 8000, sizeM2: 80); // ₪100/m²
    final cheap = [
      for (var i = 0; i < 10; i++)
        prop(id: 'c$i', price: 4000, sizeM2: 80) // ₪50/m² — target looks pricey
    ];
    final pricey = [
      for (var i = 0; i < 10; i++)
        prop(id: 'p$i', price: 16000, sizeM2: 80) // ₪200/m² — target looks cheap
    ];
    final vsCheap =
        FeatureEngineer.engineer(target, MarketContext.analyze([target, ...cheap]))
            .valueScore;
    final vsPricey =
        FeatureEngineer.engineer(target, MarketContext.analyze([target, ...pricey]))
            .valueScore;
    expect((vsCheap - vsPricey).abs(), greaterThan(0.2),
        reason: 'per-batch value assessment is unstable — the bug we fix');
  });

  test('BASELINE fix — a listing\'s fit is stable across differently-filtered '
      'queries over the SAME catalogue', () {
    // One catalogue; two queries that survive to DIFFERENT competitor pools via a
    // required amenity (never budget, so the value dimension\'s weight is identical
    // in both). The target carries BOTH amenities. With the persistent baseline the
    // target\'s value is fit over the whole catalogue either way ⇒ its fit% barely
    // moves. Under the old per-query market it would swing.
    final target =
        prop(id: 'tgt', price: 8000, sizeM2: 80, features: ['elevator', 'parking']);
    final catalogue = [
      target,
      // cheap pool — has PARKING only (surfaces on the "חניה" query)
      for (var i = 0; i < 9; i++)
        prop(id: 'ch$i', price: 4200, sizeM2: 80, features: ['parking']),
      // pricey pool — has ELEVATOR only (surfaces on the "מעלית" query)
      for (var i = 0; i < 9; i++)
        prop(id: 'pr$i', price: 15500, sizeM2: 80, features: ['elevator']),
    ];
    List<Recommendation> run(String q) => RecommendationEngine.recommend(
          candidates: catalogue,
          query: SmartSearch.parse(q),
          limit: 10,
          explore: false,
        );
    final withPricey =
        run('דירה בתל אביב עם מעלית'); // target + elevator (pricey) pool
    final withCheap =
        run('דירה בתל אביב עם חניה'); // target + parking (cheap) pool
    final a = withPricey.firstWhere((r) => r.property.id == 'tgt').fitPct;
    final b = withCheap.firstWhere((r) => r.property.id == 'tgt').fitPct;
    expect((a - b).abs(), lessThanOrEqualTo(3),
        reason: 'baseline should keep the target\'s fit stable ($a vs $b)');
  });

  test('BASELINE segments rent vs sale — a rental\'s value is NOT judged against '
      'million-shekel sale prices', () {
    final rental = prop(id: 'r', price: 6000, sizeM2: 70);
    final rentals = [
      rental,
      for (var i = 0; i < 10; i++) prop(id: 'r$i', price: 5000 + i * 300, sizeM2: 70),
    ];
    final sales = [
      for (var i = 0; i < 10; i++)
        RentalProperty(
          id: 's$i',
          price: 2000000 + i * 100000,
          rooms: 3,
          sizeM2: 70,
          floor: '2',
          totalFloors: '5',
          city: 'תל אביב',
          neighborhood: '',
          street: 'הרצל',
          streetNumber: 10,
          lat: 32.07,
          lon: 34.78,
          propertyType: 'דירה',
          entryDate: '',
          condition: 'טוב',
          ownerName: 'בעלים',
          agencyListing: false,
          features: const [],
          media: const [
            PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image),
          ],
          transactionType: PropertyTransactionType.sale,
        ),
    ];
    final q = SmartSearch.parse('דירה בתל אביב');
    final rentOnly = RecommendationEngine.recommend(
        candidates: rentals, query: q, limit: 10, explore: false);
    final mixed = RecommendationEngine.recommend(
        candidates: [...rentals, ...sales], query: q, limit: 10, explore: false);
    final a = rentOnly.firstWhere((r) => r.property.id == 'r').fitPct;
    final b = mixed.firstWhere((r) => r.property.id == 'r').fitPct;
    expect((a - b).abs(), lessThanOrEqualTo(2),
        reason: 'sale prices must not pollute the rental baseline ($a vs $b)');
    // and no sale ever leaks into a rent search
    expect(mixed.every((r) => r.property.transactionType != PropertyTransactionType.sale),
        true);
  });

  test('SLATE — a city with ample stock returns a full 10 options, best-first', () {
    final candidates = [
      for (var i = 0; i < 25; i++)
        prop(
          id: 'ta$i',
          price: 5000 + i * 150,
          rooms: 2 + (i % 4).toDouble(),
          city: 'תל אביב',
          lat: 32.06 + i * 0.001,
          lon: 34.77 + i * 0.001,
        ),
    ];
    final recs = RecommendationEngine.recommend(
      candidates: candidates,
      query: SmartSearch.parse('דירה בתל אביב'),
      limit: 10,
      explore: false,
    );
    expect(recs.length, 10);
    for (var i = 1; i < recs.length; i++) {
      expect(recs[i - 1].fitPct, greaterThanOrEqualTo(recs[i].fitPct),
          reason: 'options must be ordered most→least relevant');
    }
  });
}
