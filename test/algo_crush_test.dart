// ════════════════════════════════════════════════════════════════════════════
// ALGO CRUSH TESTS — adversarial attempts to BREAK the ranking engine.
// Not "does it do what we told it" (those live elsewhere) but "can pathological
// input make it crash, emit NaN, leak an unsafe/over-budget/wrong listing, or
// return a non-monotonic / out-of-range fit%". Every test here is trying to break
// an invariant that MUST hold no matter what garbage the catalogue contains.
// ════════════════════════════════════════════════════════════════════════════

import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

RentalProperty p({
  required String id,
  int price = 6000,
  double rooms = 3,
  int sizeM2 = 70,
  String city = 'תל אביב',
  String floor = '2',
  double lat = 32.07,
  double lon = 34.78,
  List<String> features = const [],
  PropertyTransactionType tx = PropertyTransactionType.rent,
}) =>
    RentalProperty(
      id: id,
      price: price,
      rooms: rooms,
      sizeM2: sizeM2,
      floor: floor,
      totalFloors: '5',
      city: city,
      neighborhood: '',
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
      transactionType: tx,
    );

List<RentalProperty> market([int n = 14]) => [
      for (var i = 0; i < n; i++)
        p(id: 'm$i', price: 5000 + i * 300, rooms: 2 + (i % 4).toDouble(),
            sizeM2: 55 + i * 5, lat: 32.06 + i * 0.002, lon: 34.77 + i * 0.002),
    ];

List<Recommendation> run(List<RentalProperty> c, String q, {int limit = 10}) =>
    RecommendationEngine.recommend(
        candidates: c, query: SmartSearch.parse(q), limit: limit, explore: false);

void _assertSane(List<Recommendation> recs) {
  for (var i = 0; i < recs.length; i++) {
    final r = recs[i];
    expect(r.fitScore.isFinite, true, reason: '${r.property.id} fitScore not finite');
    expect(r.fitPct, inInclusiveRange(0, 100), reason: '${r.property.id} fit% OOB');
    expect(r.confidence.isFinite && r.confidence >= 0 && r.confidence <= 1, true,
        reason: '${r.property.id} confidence OOB');
    if (i > 0) {
      expect(recs[i - 1].fitPct >= r.fitPct, true,
          reason: 'fit% must be monotonic (${recs[i - 1].fitPct} < ${r.fitPct})');
    }
  }
}

void main() {
  test('CRUSH — NaN / Infinity coordinates never crash or emit NaN', () {
    final bad = [
      p(id: 'nan', lat: double.nan, lon: double.nan),
      p(id: 'inf', lat: double.infinity, lon: double.negativeInfinity),
      p(id: 'zero', lat: 0, lon: 0),
      ...market(),
    ];
    final recs = run(bad, 'דירה בתל אביב קרוב לים');
    expect(recs, isNotEmpty);
    _assertSane(recs);
  });

  test('CRUSH — empty and single-listing catalogues degrade gracefully', () {
    expect(run(const [], 'דירה בתל אביב'), isEmpty);
    final one = run([p(id: 'solo')], 'דירה בתל אביב עד 5000 עם מעלית וחניה');
    _assertSane(one);
  });

  test('CRUSH — degenerate budgets (0, negative, min>max) never crash', () {
    for (final q in [
      'דירה בתל אביב עד 0',
      'דירה בתל אביב בין 9000 ל 3000', // min > max
      'דירה בתל אביב עד 999999999',
    ]) {
      final recs = run(market(), q);
      _assertSane(recs);
    }
  });

  test('CRUSH — a single ₪999,999 outlier rental cannot wreck the baseline', () {
    final withOutlier = [p(id: 'outlier', price: 999999, sizeM2: 70), ...market()];
    final recs = run(withOutlier, 'דירה בתל אביב');
    _assertSane(recs);
    // the normal ₪5k flats must still rank above the absurd outlier
    final outlierRank = recs.indexWhere((r) => r.property.id == 'outlier');
    if (outlierRank != -1) {
      expect(outlierRank, greaterThan(0),
          reason: 'a ₪999,999 flat must not top a normal-market search');
    }
  });

  test('CRUSH — budget hard cap holds at the exact boundary and just over it', () {
    final c = [
      ...market(), // 5000..8900
      p(id: 'at', price: 5000),
      p(id: 'over1', price: 5001),
      p(id: 'under', price: 4900),
    ];
    final recs = run(c, 'דירה בתל אביב עד 5000');
    expect(recs, isNotEmpty);
    for (final r in recs) {
      expect(r.property.price, lessThanOrEqualTo(5000),
          reason: '${r.property.id} @ ${r.property.price} breaks the ₪5000 cap');
    }
  });

  test('CRUSH — wheelchair search never surfaces a walk-up in the results', () {
    final c = [
      p(id: 'walkup3', floor: '3', features: const []), // 3rd-floor walk-up
      p(id: 'walkup4', floor: '4', features: const []),
      p(id: 'elevator', floor: '3', features: ['elevator']),
      p(id: 'ground', floor: '0', features: const []),
      ...market(),
    ];
    final recs = run(c, 'דירה בתל אביב נגישה לכיסא גלגלים');
    // an accessible option exists, so no high-floor walk-up should appear
    final ids = recs.map((r) => r.property.id).toSet();
    expect(ids.contains('walkup3'), false, reason: '3rd-floor walk-up leaked');
    expect(ids.contains('walkup4'), false, reason: '4th-floor walk-up leaked');
  });

  test('CRUSH — explore:true is DETERMINISTIC for a fixed seed', () {
    final c = market(20);
    List<String> order(int seed) => RecommendationEngine.recommend(
          candidates: c,
          query: SmartSearch.parse('דירה בתל אביב'),
          limit: 10,
          explore: true,
          seed: seed,
        ).map((r) => r.property.id).toList();
    expect(order(42), order(42), reason: 'same seed must reproduce the order');
  });

  test('CRUSH — all-identical listings do not NaN the diversity reranker', () {
    final clones = [for (var i = 0; i < 12; i++) p(id: 'clone$i')];
    final recs = run(clones, 'דירה בתל אביב');
    expect(recs.length, 10);
    _assertSane(recs);
  });

  test('CRUSH — sizeM2 / rooms = 0 (missing data) never emit NaN fit%', () {
    final c = [
      p(id: 'nosize', sizeM2: 0),
      p(id: 'norooms', rooms: 0),
      p(id: 'both0', sizeM2: 0, rooms: 0, price: 0),
      ...market(),
    ];
    _assertSane(run(c, 'דירה בתל אביב עד 6000 מרווחת'));
  });

  test('CRUSH — everything over budget: falls back sanely, still monotonic', () {
    final c = [for (var i = 0; i < 12; i++) p(id: 'exp$i', price: 12000 + i * 500)];
    final recs = run(c, 'דירה בתל אביב עד 5000');
    expect(recs, isNotEmpty, reason: 'must not dead-end when nothing fits');
    _assertSane(recs);
  });

  test('CRUSH — match% genuinely DISCRIMINATES perfect vs terrible', () {
    final c = [
      p(id: 'perfect', price: 4800, rooms: 3, city: 'תל אביב',
          features: ['elevator', 'parking']),
      p(id: 'terrible', price: 20000, rooms: 1, city: 'באר שבע',
          lat: 31.25, lon: 34.79, features: const []),
      ...market(),
    ];
    final recs = run(c, 'דירת 3 חדרים בתל אביב עד 5000 עם מעלית וחניה');
    final perfect = recs.firstWhere((r) => r.property.id == 'perfect');
    // >70, not ~100: HONEST match%. In the test env gov data isn't loaded, so the
    // neighborhood/SES axis (stated by naming the city) sits at a neutral 0.5,
    // legitimately capping a signal-less synthetic flat. Production SES lifts it.
    expect(perfect.fitPct, greaterThan(70),
        reason: 'a flat meeting every stated criterion must read high');
    // the terrible one is gated out entirely (wrong city + over budget) — good.
    // If present at all it must be far weaker than the perfect match.
    final t = recs.where((r) => r.property.id == 'terrible');
    if (t.isNotEmpty) {
      expect(t.first.fitPct, lessThan(perfect.fitPct - 25));
    }
  });

  test('CRUSH — scale: 2000 listings returns a sane top-10 without NaN', () {
    final big = [
      for (var i = 0; i < 2000; i++)
        p(id: 'b$i', price: 4000 + (i % 60) * 200, rooms: 1 + (i % 5).toDouble(),
            sizeM2: 40 + (i % 80), lat: 32.0 + (i % 100) * 0.003,
            lon: 34.7 + (i % 100) * 0.003),
    ];
    final recs = run(big, 'דירה בתל אביב עד 7000');
    expect(recs.length, 10);
    _assertSane(recs);
  });
}
