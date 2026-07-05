import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/etti_plan.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

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
  PropertyTransactionType type = PropertyTransactionType.rent,
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: sizeM2, floor: floor,
      totalFloors: '20', city: city, neighborhood: '', street: 'הרצל',
      streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: type, entryDate: '', condition: 'טוב',
      ownerName: 'בעלים', agencyListing: false, features: features,
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: const PropertyMarketSignals(views: 120, likes: 14, saves: 4),
      verification: PropertyVerification.cameraVideo(
          videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

List<RentalProperty> catalogue() => [
      // Bnei Brak — charedi family
      f(id: 'bb-5r', price: 6200, rooms: 5, sizeM2: 118, city: 'בני ברק', lat: 32.083, lon: 34.836, floor: '2', features: ['elevator', 'mamad', 'balcony']),
      f(id: 'bb-4r', price: 5500, rooms: 4, sizeM2: 95, city: 'בני ברק', lat: 32.085, lon: 34.84, features: ['mamad', 'elevator']),
      f(id: 'bb-3r', price: 4800, rooms: 3, sizeM2: 70, city: 'בני ברק', lat: 32.084, lon: 34.838, floor: '6', features: []),
      // Tel Aviv
      f(id: 'ta-beach', price: 8300, rooms: 2, sizeM2: 55, city: 'תל אביב', lat: 32.081, lon: 34.767, floor: '4', features: ['ac', 'balcony']),
      f(id: 'ta-ground-pet', price: 8000, rooms: 2, sizeM2: 58, city: 'תל אביב', lat: 32.078, lon: 34.772, floor: '0', features: ['ac', 'petsAllowed', 'garden']),
      f(id: 'ta-center', price: 8800, rooms: 3, sizeM2: 78, city: 'תל אביב', lat: 32.072, lon: 34.781, floor: '5', features: ['ac', 'elevator']),
      f(id: 'ta-far', price: 7000, rooms: 3, sizeM2: 82, city: 'תל אביב', lat: 32.055, lon: 34.86, features: ['ac']),
      // Beer Sheva — student (BGU 31.262,34.801)
      f(id: 'bs-campus', price: 2700, rooms: 4, sizeM2: 90, city: 'באר שבע', lat: 31.263, lon: 34.802, features: ['ac']),
      f(id: 'bs-far', price: 2400, rooms: 3, sizeM2: 72, city: 'באר שבע', lat: 31.24, lon: 34.78, features: ['ac']),
      f(id: 'bs-cheap', price: 2200, rooms: 2, sizeM2: 55, city: 'באר שבע', lat: 31.25, lon: 34.79, features: ['ac']),
      // Netanya — retiree
      f(id: 'net-elev', price: 4900, rooms: 3, sizeM2: 82, city: 'נתניה', lat: 32.32, lon: 34.853, floor: '2', features: ['ac', 'elevator']),
      f(id: 'net-walkup', price: 4600, rooms: 3, sizeM2: 80, city: 'נתניה', lat: 32.31, lon: 34.86, floor: '4', features: ['ac']),
      f(id: 'net-ground', price: 4800, rooms: 3, sizeM2: 78, city: 'נתניה', lat: 32.325, lon: 34.855, floor: '0', features: ['ac']),
      // Haifa — investor + wheelchair
      f(id: 'hf-sale-hi', price: 1150000, rooms: 4, sizeM2: 92, city: 'חיפה', lat: 32.80, lon: 34.99, type: PropertyTransactionType.sale),
      f(id: 'hf-sale-lo', price: 1950000, rooms: 3, sizeM2: 78, city: 'חיפה', lat: 32.81, lon: 34.98, type: PropertyTransactionType.sale),
      f(id: 'hf-sale-mid', price: 1400000, rooms: 3, sizeM2: 80, city: 'חיפה', lat: 32.79, lon: 34.985, type: PropertyTransactionType.sale),
      f(id: 'hf-elev', price: 4800, rooms: 3, sizeM2: 78, city: 'חיפה', lat: 32.79, lon: 34.99, floor: '6', features: ['ac', 'elevator']),
      f(id: 'hf-ground', price: 4700, rooms: 3, sizeM2: 74, city: 'חיפה', lat: 32.81, lon: 34.99, floor: '0', features: ['ac']),
      f(id: 'hf-walkup', price: 4500, rooms: 3, sizeM2: 82, city: 'חיפה', lat: 32.80, lon: 34.98, floor: '5', features: ['ac']),
      // Petah Tikva — divorced mom
      f(id: 'pt-3r-elev', price: 5400, rooms: 3, sizeM2: 78, city: 'פתח תקווה', lat: 32.088, lon: 34.887, floor: '2', features: ['ac', 'elevator', 'mamad']),
      f(id: 'pt-4r', price: 6000, rooms: 4, sizeM2: 100, city: 'פתח תקווה', lat: 32.09, lon: 34.885, features: ['ac', 'elevator']),
      f(id: 'pt-cheap', price: 4700, rooms: 2, sizeM2: 55, city: 'פתח תקווה', lat: 32.087, lon: 34.888, features: ['ac']),
      // Modiin — WFH
      f(id: 'mod-spacious', price: 6300, rooms: 4, sizeM2: 120, city: 'מודיעין', lat: 31.898, lon: 35.010, floor: '3', features: ['ac', 'balcony', 'renovated']),
      f(id: 'mod-small', price: 5800, rooms: 3, sizeM2: 68, city: 'מודיעין', lat: 31.90, lon: 35.012, features: ['ac']),
      f(id: 'mod-mid', price: 6000, rooms: 4, sizeM2: 90, city: 'מודיעין', lat: 31.895, lon: 35.008, features: ['ac']),
      // Ashdod — oleh
      f(id: 'ash-furn', price: 4500, rooms: 3, sizeM2: 80, city: 'אשדוד', lat: 31.79, lon: 34.64, floor: '3', features: ['ac', 'furnished', 'elevator']),
      f(id: 'ash-bare', price: 4300, rooms: 3, sizeM2: 82, city: 'אשדוד', lat: 31.80, lon: 34.65, features: ['ac']),
      f(id: 'ash-cheap', price: 4000, rooms: 2, sizeM2: 58, city: 'אשדוד', lat: 31.79, lon: 34.645, features: ['ac']),
    ];

void show(int n, String persona, Map<String, dynamic> ettiJson) {
  final plan = EttiPlan.fromJson(ettiJson);
  final recs = RecommendationEngine.recommendAsScored(
      candidates: catalogue(), query: plan.toQuery(), limit: 8, seed: 40);
  // ignore: avoid_print
  print('\n═══ $n. $persona ═══');
  for (final s in recs.take(3)) {
    final p = s.property;
    final sc = s.scorecard!;
    // ignore: avoid_print
    print('   • ${p.id}: ${p.priceLabel}, ${p.rooms.toInt()}חד׳/${p.sizeM2}מ״ר '
        'ק${p.floorNumber ?? "?"}, ${p.city} · ${sc.fitPct}%'
        '${sc.concerns.isNotEmpty ? "  ⚠${sc.concerns.first}" : ""}');
  }
}

void main() {
  setUpAll(() async {
    GovData.instance.resetForTest();
    await GovData.instance.init(reader: _diskReader);
  });
  tearDownAll(() => GovData.instance.resetForTest());

  test('10 authentic Israeli personas', () {
    show(1, 'אברהם · אברך חרדי · בני ברק · 5 חד׳', {
      'hard_constraints': {'city': 'בני ברק', 'min_rooms': 4, 'mamad': true, 'max_price': 6500},
      'soft_weights': {'family_friendly': 1.9, 'schools_nearby': 1.8, 'value': 1.5, 'safety': 1.4},
      'inferred_persona': 'haredi avrech, large family, tight budget',
    });
    show(2, 'נועה · הייטקיסטית · ת״א · ים+נייטלייף', {
      'hard_constraints': {'city': 'תל אביב', 'max_price': 9000},
      'soft_weights': {'near_sea': 2.0, 'nightlife': 1.7, 'central_location': 1.6, 'size': -0.5},
      'inferred_persona': 'single hi-tech, beach + nightlife',
    });
    show(3, 'יוסי · סטודנט · באר שבע · ליד קמפוס', {
      'hard_constraints': {'city': 'באר שבע', 'max_price': 2800},
      'soft_weights': {'university': 2.0, 'value': 1.6, 'transit': 1.3},
      'inferred_persona': 'BGU student, roommates',
    });
    show(4, 'רחל ומשה · גמלאים · נתניה · שקט+נגיש', {
      'hard_constraints': {'city': 'נתניה'},
      'soft_weights': {'accessibility': 1.9, 'quiet_neighborhood': 1.7, 'safety': 1.4},
      'inferred_persona': 'retired couple',
    });
    show(5, 'דניאל · משקיע · חיפה · תשואה', {
      'hard_constraints': {'city': 'חיפה', 'transaction_type': 'sale', 'max_price': 1500000},
      'soft_weights': {'yield': 2.0, 'value': 1.5},
      'inferred_persona': 'yield investor',
    });
    show(6, 'לירון · אמא גרושה · פ״ת · 3 חד׳ בטוח', {
      'hard_constraints': {'city': 'פתח תקווה', 'min_rooms': 3},
      'soft_weights': {'safety': 1.8, 'schools_nearby': 1.6, 'family_friendly': 1.5, 'accessibility_stroller': 1.4},
      'inferred_persona': 'divorced mom, two kids',
    });
    show(7, 'קובי · בעל כלב · ת״א · קרקע', {
      'hard_constraints': {'city': 'תל אביב', 'pets': true},
      'soft_weights': {'ground_floor': 1.8, 'central_location': 1.5, 'size': -0.5},
      'inferred_persona': 'dog owner',
    });
    show(8, 'יעקב · כיסא גלגלים · חיפה', {
      'hard_constraints': {'city': 'חיפה', 'accessible': true},
      'soft_weights': {'accessibility': 2.0, 'safety': 1.3},
      'inferred_persona': 'wheelchair user',
    });
    show(9, 'מיכל · עובדת מהבית · מודיעין · מרווח+שקט', {
      'hard_constraints': {'city': 'מודיעין'},
      'soft_weights': {'spacious': 1.9, 'quiet_neighborhood': 1.6, 'condition': 1.5},
      'inferred_persona': 'work-from-home, needs a home office',
    });
    show(10, 'אלכס · עולה חדש · אשדוד · מרוהט', {
      'hard_constraints': {'city': 'אשדוד', 'furnished': true},
      'soft_weights': {'central_location': 1.5, 'value': 1.4},
      'inferred_persona': 'new immigrant, needs furnished + community',
    });
    expect(true, true);
  });
}
