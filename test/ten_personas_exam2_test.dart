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
      totalFloors: '25', city: city, neighborhood: '', street: 'הרצל',
      streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: type, entryDate: '', condition: 'טוב',
      ownerName: 'בעלים', agencyListing: false, features: features,
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: const PropertyMarketSignals(views: 120, likes: 14, saves: 4),
      verification: PropertyVerification.cameraVideo(
          videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

List<RentalProperty> catalogue() => [
      // Beer Sheva — roommates (BGU 31.263,34.802)
      f(id: 'bs-5r-campus', price: 3200, rooms: 5, sizeM2: 110, city: 'באר שבע', lat: 31.264, lon: 34.803, features: ['ac']),
      f(id: 'bs-3r-campus', price: 2600, rooms: 3, sizeM2: 70, city: 'באר שבע', lat: 31.262, lon: 34.801, features: ['ac']),
      f(id: 'bs-4r-far', price: 2800, rooms: 4, sizeM2: 88, city: 'באר שבע', lat: 31.24, lon: 34.78, features: ['ac']),
      // Herzliya — luxury
      f(id: 'hrz-penthouse', price: 16000, rooms: 4, sizeM2: 150, city: 'הרצליה', lat: 32.163, lon: 34.806, floor: '18', features: ['ac', 'elevator', 'pool', 'parking', 'storage', 'balcony']),
      f(id: 'hrz-lux-mid', price: 11000, rooms: 4, sizeM2: 120, city: 'הרצליה', lat: 32.16, lon: 34.83, floor: '6', features: ['ac', 'elevator', 'parking', 'balcony']),
      f(id: 'hrz-basic', price: 7000, rooms: 3, sizeM2: 80, city: 'הרצליה', lat: 32.165, lon: 34.84, floor: '2', features: ['ac']),
      // Modiin — family sale + religious
      f(id: 'mod-sale-fam', price: 2450000, rooms: 5, sizeM2: 130, city: 'מודיעין', lat: 31.898, lon: 35.010, features: ['mamad', 'elevator', 'parking'], type: PropertyTransactionType.sale),
      f(id: 'mod-sale-small', price: 1900000, rooms: 3, sizeM2: 78, city: 'מודיעין', lat: 31.90, lon: 35.012, type: PropertyTransactionType.sale),
      f(id: 'mod-rent-mamad', price: 6200, rooms: 4, sizeM2: 100, city: 'מודיעין', lat: 31.895, lon: 35.008, features: ['ac', 'mamad', 'elevator']),
      f(id: 'mod-rent-nomamad', price: 5800, rooms: 4, sizeM2: 98, city: 'מודיעין', lat: 31.899, lon: 35.011, features: ['ac']),
      // Tel Aviv
      f(id: 'ta-flor-ground', price: 5800, rooms: 2, sizeM2: 48, city: 'תל אביב', lat: 32.057, lon: 34.770, floor: '0', features: ['ac']),
      f(id: 'ta-flor-3rd', price: 6200, rooms: 2, sizeM2: 50, city: 'תל אביב', lat: 32.058, lon: 34.771, floor: '3', features: ['ac']),
      f(id: 'ta-highrise-view', price: 11000, rooms: 3, sizeM2: 85, city: 'תל אביב', lat: 32.083, lon: 34.79, floor: '22', features: ['ac', 'elevator', 'balcony', 'parking']),
      f(id: 'ta-low-nice', price: 10500, rooms: 3, sizeM2: 88, city: 'תל אביב', lat: 32.075, lon: 34.782, floor: '2', features: ['ac', 'elevator']),
      f(id: 'ta-rail', price: 7000, rooms: 2, sizeM2: 52, city: 'תל אביב', lat: 32.073, lon: 34.792, features: ['ac']),
      f(id: 'ta-far-cheap', price: 6500, rooms: 2, sizeM2: 55, city: 'תל אביב', lat: 32.055, lon: 34.86, features: ['ac']),
      f(id: 'ta-sale-beach', price: 3200000, rooms: 2, sizeM2: 58, city: 'תל אביב', lat: 32.081, lon: 34.767, type: PropertyTransactionType.sale),
      f(id: 'ta-sale-inland', price: 2600000, rooms: 3, sizeM2: 72, city: 'תל אביב', lat: 32.06, lon: 34.85, type: PropertyTransactionType.sale),
      // Petah Tikva — baby
      f(id: 'pt-baby-elev', price: 5600, rooms: 3, sizeM2: 80, city: 'פתח תקווה', lat: 32.088, lon: 34.887, floor: '1', features: ['ac', 'elevator', 'mamad']),
      f(id: 'pt-highfloor', price: 5400, rooms: 3, sizeM2: 78, city: 'פתח תקווה', lat: 32.09, lon: 34.885, floor: '8', features: ['ac']),
      f(id: 'pt-cheap', price: 4600, rooms: 2, sizeM2: 55, city: 'פתח תקווה', lat: 32.087, lon: 34.888, features: ['ac']),
    ];

void show(int n, String persona, Map<String, dynamic> ettiJson) {
  final plan = EttiPlan.fromJson(ettiJson);
  final recs = RecommendationEngine.recommendAsScored(
      candidates: catalogue(), query: plan.toQuery(), limit: 8, seed: 50);
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

  test('10 fresh personas — different use-cases', () {
    show(1, 'שותפים · 3 סטודנטים · ב״ש · הרבה חדרים', {
      'hard_constraints': {'city': 'באר שבע', 'min_rooms': 4, 'max_price': 3500},
      'soft_weights': {'university': 1.9, 'spacious': 1.6, 'value': 1.5},
      'inferred_persona': 'three roommates near BGU',
    });
    show(2, 'זוג אמיד · הרצליה · יוקרה+נוף+בריכה', {
      'hard_constraints': {'city': 'הרצליה'},
      'soft_weights': {'luxury': 2.0, 'view': 1.8, 'central_location': 1.4},
      'inferred_persona': 'affluent couple, premium lifestyle',
    });
    show(3, 'משפחת לוי · קונים forever-home · מודיעין · בי״ס+בטוח', {
      'hard_constraints': {'city': 'מודיעין', 'transaction_type': 'sale', 'max_price': 2600000},
      'soft_weights': {'schools_nearby': 1.9, 'safety': 1.8, 'family_friendly': 1.7},
      'inferred_persona': 'family buying a forever-home',
    });
    show(4, 'נעמה · אמנית · ת״א פלורנטין · קרקע+זול', {
      'hard_constraints': {'city': 'תל אביב', 'max_price': 6500},
      'soft_weights': {'ground_floor': 1.8, 'value': 1.6, 'central_location': 1.3},
      'inferred_persona': 'artist, ground-floor studio, Florentin vibe',
    });
    show(5, 'רון · צעיר ללא רכב · ת״א · רכבת קלה', {
      'hard_constraints': {'city': 'תל אביב', 'max_price': 7500},
      'soft_weights': {'transit': 2.0, 'central_location': 1.6, 'value': 1.4},
      'inferred_persona': 'car-free young professional',
    });
    show(6, 'משפחת כהן · תינוק בדרך · פ״ת · מעלית+שקט', {
      'hard_constraints': {'city': 'פתח תקווה', 'elevator': true},
      'soft_weights': {'accessibility_stroller': 1.9, 'quiet_neighborhood': 1.6, 'safety': 1.6},
      'inferred_persona': 'expecting a baby, stroller access',
    });
    show(7, 'איתי · משקיע Airbnb · ת״א · sale · ליד ים', {
      'hard_constraints': {'city': 'תל אביב', 'transaction_type': 'sale', 'max_price': 3500000},
      'soft_weights': {'near_sea': 2.0, 'yield': 1.8, 'central_location': 1.5},
      'inferred_persona': 'short-term-rental investor near the beach',
    });
    show(8, 'הרב פישר · דתי-לאומי · מודיעין · ממ״ד+בי״ס', {
      'hard_constraints': {'city': 'מודיעין', 'mamad': true, 'min_rooms': 4},
      'soft_weights': {'schools_nearby': 1.8, 'family_friendly': 1.7, 'safety': 1.5},
      'inferred_persona': 'religious-national family',
    });
    show(9, 'מיה · מחפשת נוף · ת״א · קומה גבוהה', {
      'hard_constraints': {'city': 'תל אביב', 'max_price': 12000},
      'soft_weights': {'view': 2.0, 'luxury': 1.5, 'central_location': 1.4},
      'inferred_persona': 'high-floor view seeker',
    });
    show(10, 'דנה+טל · זוג צעיר · ת״א · תקציב + ים אם אפשר', {
      'hard_constraints': {'city': 'תל אביב', 'max_price': 7000},
      'soft_weights': {'budget': 1.9, 'value': 1.6, 'near_sea': 1.3},
      'inferred_persona': 'young couple, budget-first, sea is a bonus',
    });
    expect(true, true);
  });
}
