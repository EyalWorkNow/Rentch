import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/etti_plan.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> _diskReader(String path) => File(path).readAsString();

RentalProperty flat({
  required String id,
  required int price,
  required double rooms,
  required int sizeM2,
  required String city,
  required double lat,
  required double lon,
  String floor = '3',
  List<String> features = const [],
  PropertyTransactionType type = PropertyTransactionType.rent,
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: sizeM2, floor: floor,
      totalFloors: '20', city: city, neighborhood: '', street: 'הרצל',
      streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: type, entryDate: '', condition: 'טוב',
      ownerName: 'בעלים', agencyListing: false, features: features,
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
      marketSignals: const PropertyMarketSignals(views: 120, likes: 14, saves: 4),
      verification: PropertyVerification.cameraVideo(
          videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

int rankOf(List<ScoredProperty> l, String id) =>
    l.indexWhere((s) => s.property.id == id);

void show(String persona, String q, List<ScoredProperty> recs) {
  // ignore: avoid_print
  print('\n════════ $persona ════════\n   🔎 "$q"');
  for (final s in recs.take(3)) {
    final p = s.property;
    final sc = s.scorecard!;
    final top = (List.of(sc.dimensions)
          ..sort((a, b) => b.weightPct.compareTo(a.weightPct)))
        .take(5)
        .map((d) => '${d.label} ${(d.contributionPct * 100).round()}%')
        .join(', ');
    // ignore: avoid_print
    print('   • ${p.id}: ${p.priceLabel}, ${p.rooms.toInt()}חד׳/${p.sizeM2}מ״ר, '
        '${p.city} · fit ${sc.fitPct}%\n       $top');
    if (sc.concerns.isNotEmpty) {
      // ignore: avoid_print
      print('       ⚠ ${sc.concerns.join(" | ")}');
    }
  }
}

// Real Tel-Aviv-area + Haifa stock at real coordinates.
List<RentalProperty> catalogue() => [
      // near a rail station (TA השלום ~32.073,34.792) vs far east
      flat(id: 'ta-rail', price: 6100, rooms: 3, sizeM2: 80, city: 'תל אביב',
          lat: 32.073, lon: 34.792, features: ['ac']),
      flat(id: 'ta-eastfar', price: 6100, rooms: 3, sizeM2: 80, city: 'תל אביב',
          lat: 32.058, lon: 34.86, features: ['ac']),
      // beachfront vs inland
      flat(id: 'ta-beach', price: 8000, rooms: 2, sizeM2: 56, city: 'תל אביב',
          lat: 32.081, lon: 34.767, features: ['ac', 'balcony']),
      // by Tel Aviv University
      flat(id: 'tau', price: 5400, rooms: 2, sizeM2: 55, city: 'תל אביב',
          lat: 32.113, lon: 34.805, features: ['ac']),
      // pet-friendly ground floor
      flat(id: 'ta-ground-pet', price: 6800, rooms: 3, sizeM2: 78,
          city: 'תל אביב', lat: 32.07, lon: 34.79, floor: '0',
          features: ['ac', 'petsAllowed', 'garden']),
      flat(id: 'ta-high-nopet', price: 6700, rooms: 3, sizeM2: 80,
          city: 'תל אביב', lat: 32.072, lon: 34.79, floor: '9',
          features: ['ac', 'elevator']),
      // Ramat Gan (metro) — family
      flat(id: 'rg-family', price: 5900, rooms: 4, sizeM2: 96, city: 'רמת גן',
          lat: 32.083, lon: 34.814, features: ['ac', 'elevator', 'mamad']),
      // Haifa sale stock (investor)
      flat(id: 'hf-sale-cheap', price: 1150000, rooms: 4, sizeM2: 92,
          city: 'חיפה', lat: 32.80, lon: 34.99,
          type: PropertyTransactionType.sale),
      flat(id: 'hf-sale-pricey', price: 1950000, rooms: 3, sizeM2: 78,
          city: 'חיפה', lat: 32.81, lon: 34.98,
          type: PropertyTransactionType.sale),
    ];

List<ScoredProperty> run(String q) => RecommendationEngine.recommendAsScored(
    candidates: catalogue(), query: SmartSearch.parse(q), limit: 8, seed: 21);

void main() {
  setUpAll(() async {
    GovData.instance.resetForTest();
    await GovData.instance.init(reader: _diskReader);
  });
  tearDownAll(() => GovData.instance.resetForTest());

  test('gov data actually loaded', () {
    expect(GovData.instance.loaded, true);
  });

  test('דן — קרוב לרכבת בתל אביב', () {
    const q = 'דירה בתל אביב קרוב לרכבת עד 6800';
    final recs = run(q);
    show('דן · רכבת · ת״א', q, recs);
    expect(rankOf(recs, 'ta-rail') < rankOf(recs, 'ta-eastfar'), true,
        reason: 'near-rail flat should beat the far-east one');
  });

  test('נועה — ליד הים בתל אביב', () {
    const q = 'דירה בתל אביב קרוב לים עד 8500';
    final recs = run(q);
    show('נועה · ים · ת״א', q, recs);
    final ids = recs.map((s) => s.property.id).toList();
    // The gate: the far-from-sea flat (~9km inland) is excluded, and the actual
    // beachfront flat is present — no more "far from the sea despite asking".
    expect(ids.contains('ta-eastfar'), false,
        reason: 'a flat ~9km from the sea must be gated out for "קרוב לים"');
    expect(ids.contains('ta-beach'), true,
        reason: 'the beachfront flat must be in the near-sea results');
  });

  test('יעל — סטודנטית ליד אוניברסיטת תל אביב', () {
    const q = 'דירה לסטודנטית ליד האוניברסיטה בתל אביב עד 6000';
    final recs = run(q);
    show('יעל · סטודנטית · TAU', q, recs);
    expect(recs.first.property.id == 'tau', true,
        reason: 'the flat by the campus should lead for a student');
  });

  test('קובי — בעל כלב, קומת קרקע', () {
    const q = 'דירה בתל אביב לבעל כלב קומת קרקע עד 7000';
    final recs = run(q);
    show('קובי · כלב · קומת קרקע · ת״א', q, recs);
    // A dog owner CANNOT take a no-pets flat → it must be EXCLUDED, not just
    // out-ranked (pets is now a hard requirement whenever a pet is mentioned).
    expect(recs.any((r) => r.property.id == 'ta-ground-pet'), true,
        reason: 'the pet-friendly ground floor must be shown');
    expect(recs.every((r) => r.property.features.contains('petsAllowed')), true,
        reason: 'no no-pets flat may be offered to a dog owner');
  });

  test('רון — יש לי מכונית, צריך חניה', () {
    final candidates = [
      flat(id: 'with-parking', price: 6500, rooms: 3, sizeM2: 78,
          city: 'תל אביב', lat: 32.07, lon: 34.79,
          features: ['ac', 'parking']),
      flat(id: 'no-parking', price: 6500, rooms: 3, sizeM2: 78, city: 'תל אביב',
          lat: 32.07, lon: 34.79, features: ['ac']),
    ];
    final recs = RecommendationEngine.recommendAsScored(
        candidates: candidates,
        query: SmartSearch.parse('דירה בתל אביב יש לי מכונית עד 7000'),
        limit: 8,
        seed: 21);
    show('רון · מכונית · חניה', 'דירה בתל אביב יש לי מכונית עד 7000', recs);
    expect(recs.first.property.id == 'with-parking', true,
        reason: '"יש לי מכונית" should imply a parking need');
  });

  test('דנה — דירה מרכזית', () {
    final candidates = [
      flat(id: 'central', price: 6800, rooms: 3, sizeM2: 78, city: 'תל אביב',
          lat: 32.0733, lon: 34.7800, features: ['ac']), // TA core
      flat(id: 'peripheral', price: 6800, rooms: 3, sizeM2: 78, city: 'תל אביב',
          lat: 32.052, lon: 34.872, features: ['ac']), // TA edge
    ];
    final recs = RecommendationEngine.recommendAsScored(
        candidates: candidates,
        query: SmartSearch.parse('דירה מרכזית בתל אביב עד 7000'),
        limit: 8,
        seed: 21);
    show('דנה · מרכזי', 'דירה מרכזית בתל אביב עד 7000', recs);
    expect(rankOf(recs, 'central') < rankOf(recs, 'peripheral'), true,
        reason: 'a central flat should beat a peripheral one for "מרכזית"');
  });

  test('CONTRACT — assistant-supplied intents gate the SAME as typed text', () {
    // Simulate the assistant emitting the structured contract DIRECTLY (no
    // rawText to regex) — the way GPT's search_listings tool now fills intents[].
    final q = SearchQuery(
      city: 'תל אביב',
      maxPrice: 8500,
      intents: const {'near_sea'},
    );
    final recs = RecommendationEngine.recommendAsScored(
        candidates: catalogue(), query: q, limit: 8, seed: 21);
    final ids = recs.map((s) => s.property.id).toList();
    expect(ids.contains('ta-eastfar'), false,
        reason: 'assistant near_sea intent must gate out the 9km-inland flat');
    expect(ids.contains('ta-beach'), true,
        reason: 'the beachfront flat survives the near-sea gate');
  });

  test('LLM WEIGHTS drive the ranking — the assistant is the brain', () {
    // The assistant understood the user and decided: the sea matters a lot,
    // size barely. The engine must obey — beachfront leads despite being smaller.
    final seaBrain = SearchQuery(
      city: 'תל אביב',
      maxPrice: 8500,
      weights: const {'near_sea': 0.97, 'budget': 0.3, 'size': 0.1},
    );
    final r1 = RecommendationEngine.recommendAsScored(
        candidates: catalogue(), query: seaBrain, limit: 8, seed: 21);
    expect(r1.first.property.id == 'ta-beach', true,
        reason: 'a high sea-weight from the model must put the beachfront first');

    // Same listings; now the model decided size matters and the sea does NOT.
    final sizeBrain = SearchQuery(
      city: 'תל אביב',
      maxPrice: 8500,
      weights: const {'size': 0.95, 'value': 0.6, 'budget': 0.4},
    );
    final r2 = RecommendationEngine.recommendAsScored(
        candidates: catalogue(), query: sizeBrain, limit: 8, seed: 21);
    expect(r2.first.property.id != 'ta-beach', true,
        reason: 'with no sea-weight, the small beach flat must NOT lead');
  });

  test('ETTI E2E — the extracted plan drives the real engine', () {
    // The full Etti output for "studio in central TA, near the sea, size doesn't
    // matter" → the plan alone must lead with the beachfront flat.
    final q = EttiPlan.fromJson({
      'hard_constraints': {'city': 'תל אביב'},
      'soft_weights': {'near_sea': 2.0, 'central_location': 1.5, 'size': -1.0},
      'inferred_persona': 'single professional, sea lifestyle',
    }).toQuery();
    final recs = RecommendationEngine.recommendAsScored(
        candidates: catalogue(), query: q, limit: 8, seed: 21);
    final ids = recs.map((s) => s.property.id).toList();
    expect(recs.first.property.id == 'ta-beach', true,
        reason: 'Etti near_sea:2.0 → the beachfront flat leads');
    expect(ids.contains('ta-eastfar'), false,
        reason: 'the near_sea intent from Etti also gates out the inland flat');
  });

  test('אבי — משקיע בחיפה לתשואה', () {
    const q = 'דירה להשקעה בחיפה עם תשואה טובה עד 1500000';
    final recs = run(q);
    show('אבי · משקיע · חיפה · תשואה', q, recs);
    expect(
        recs.every(
            (s) => s.property.transactionType == PropertyTransactionType.sale),
        true,
        reason: 'investor search must be sales only');
    expect(recs.first.property.price <= 1500000, true,
        reason: '"עד 1500000" caps the budget');
  });
}
