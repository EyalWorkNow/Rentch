import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Examination of the LIVE assistant on-device path: exactly what _send() does —
// SmartSearch.parse(freeText) → RecommendationEngine → inspect ordered results.
Future<String> _diskReader(String path) => File(path).readAsString();

RentalProperty f({
  required String id,
  required int price,
  required double rooms,
  required int sizeM2,
  required String city,
  required double lat,
  required double lon,
  String floor = '3',
  List<String> features = const [],
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: sizeM2, floor: floor,
      totalFloors: '20', city: city, neighborhood: '', street: 'הרצל',
      streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'בעלים', agencyListing: false,
      features: features,
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: const PropertyMarketSignals(views: 120, likes: 14, saves: 4),
      verification: PropertyVerification.cameraVideo(
          videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

List<RentalProperty> catalogue() => [
      f(id: 'ta-2r-8k', price: 8000, rooms: 2, sizeM2: 56, city: 'תל אביב', lat: 32.081, lon: 34.767, floor: '4', features: ['ac', 'balcony', 'elevator']),
      f(id: 'ta-3r-9k', price: 9000, rooms: 3, sizeM2: 78, city: 'תל אביב', lat: 32.072, lon: 34.781, floor: '5', features: ['ac', 'elevator']),
      f(id: 'ta-2r-6k', price: 6200, rooms: 2, sizeM2: 50, city: 'תל אביב', lat: 32.073, lon: 34.792, features: ['ac']),
      f(id: 'ta-4r-12k', price: 12000, rooms: 4, sizeM2: 105, city: 'תל אביב', lat: 32.086, lon: 34.774, floor: '6', features: ['ac', 'elevator', 'mamad', 'parking']),
      f(id: 'rg-3r-6k', price: 6000, rooms: 3, sizeM2: 80, city: 'רמת גן', lat: 32.083, lon: 34.814, features: ['ac', 'elevator', 'mamad']),
      f(id: 'pt-4r-6k', price: 6000, rooms: 4, sizeM2: 104, city: 'פתח תקווה', lat: 32.088, lon: 34.887, floor: '2', features: ['ac', 'elevator', 'mamad', 'balcony', 'parking']),
      f(id: 'pt-3r-5k', price: 5200, rooms: 3, sizeM2: 68, city: 'פתח תקווה', lat: 32.09, lon: 34.88, floor: '7', features: ['ac', 'elevator']),
      f(id: 'bb-4r-5k', price: 5000, rooms: 4, sizeM2: 95, city: 'בני ברק', lat: 32.084, lon: 34.833, features: ['ac', 'mamad', 'elevator']),
      f(id: 'hf-3r-4k', price: 4200, rooms: 3, sizeM2: 78, city: 'חיפה', lat: 32.79, lon: 34.99, floor: '6', features: ['ac', 'elevator']),
      f(id: 'js-3r-6k', price: 6000, rooms: 3, sizeM2: 75, city: 'ירושלים', lat: 31.78, lon: 35.21, features: ['ac', 'mamad']),
    ];

void main() {
  setUpAll(() async {
    GovData.instance.resetForTest();
    await GovData.instance.init(reader: _diskReader);
  });
  tearDownAll(() => GovData.instance.resetForTest());

  List<ScoredProperty> run(String text) {
    final q = SmartSearch.parse(text);
    return RecommendationEngine.recommendAsScored(
        candidates: catalogue(), query: q, limit: 6, seed: 30);
  }

  void report(String text) {
    final q = SmartSearch.parse(text);
    final recs = run(text);
    // ignore: avoid_print
    print('\n════ "$text"');
    // ignore: avoid_print
    print('   parsed: city=${q.city} max=${q.maxPrice} minRooms=${q.minRooms} amen=${q.amenities}');
    for (final s in recs.take(4)) {
      final p = s.property;
      // ignore: avoid_print
      print('   • ${p.id}: ${p.city} ${p.price}₪ ${p.rooms.toInt()}חד fit${s.scorecard?.fitPct}%');
    }
  }

  test('EXAM · live assistant parse+rank on 10 real queries', () {
    for (final t in [
      'דירה לזוג בתל אביב עד 8500',
      'דירה באזור צעיר בתל אביב',
      'זוג דתי בבני ברק 4 חדרים',
      'משפחה עם ילדים פתח תקווה 4 חדרים',
      'דירה זולה בתל אביב',
      'דירה בחיפה עד 5000',
      'דירה בירושלים דתי',
      'סטודנט תקציב נמוך רמת גן',
      'דירה גדולה עם ממ״ד וחניה',
      'משהו נחמד לגור',
    ]) {
      report(t);
    }

    // ── Correctness gates (what "gives correct answers / works with DB" means) ──

    // 1. City honored — TA request must return TA first.
    final ta = run('דירה לזוג בתל אביב עד 8500');
    expect(ta.first.property.city, 'תל אביב', reason: 'TA request → TA first');
    // 2. Budget honored — nothing grossly over the ceiling on top.
    expect(ta.first.property.price, lessThanOrEqualTo(8500),
        reason: 'top result must respect stated budget');
    // 3. Rooms honored.
    final fam = run('משפחה עם ילדים פתח תקווה 4 חדרים');
    expect(fam.first.property.city, 'פתח תקווה');
    expect(fam.first.property.rooms, greaterThanOrEqualTo(4));
    // 4. Religious city routing works.
    final bb = run('זוג דתי בבני ברק 4 חדרים');
    expect(bb.first.property.city, 'בני ברק');
    // 5. Cheap request surfaces the cheapest TA stock, not the 12k flat.
    final cheap = run('דירה זולה בתל אביב');
    expect(cheap.first.property.price, lessThan(9000),
        reason: 'cheap → not the most expensive flat first');
    // 6. Vague query never hallucinates a city filter.
    expect(SmartSearch.parse('משהו נחמד לגור').city, isNull);
  });
}
