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
      // ── Tel Aviv metro ───────────────────────────────────────────────────────
      f(id: 'ta-beach-2r', price: 8000, rooms: 2, sizeM2: 56, city: 'תל אביב', lat: 32.081, lon: 34.767, floor: '4', features: ['ac', 'balcony']),
      f(id: 'ta-beach-ground-pet', price: 8200, rooms: 2, sizeM2: 58, city: 'תל אביב', lat: 32.082, lon: 34.769, floor: '0', features: ['ac', 'petsAllowed', 'garden']),
      f(id: 'ta-center-3r', price: 8800, rooms: 3, sizeM2: 78, city: 'תל אביב', lat: 32.072, lon: 34.781, floor: '5', features: ['ac', 'elevator']),
      f(id: 'ta-cheap-far', price: 5400, rooms: 2, sizeM2: 52, city: 'תל אביב', lat: 32.055, lon: 34.86, features: ['ac']),
      f(id: 'ta-rail-cheap', price: 5500, rooms: 2, sizeM2: 50, city: 'תל אביב', lat: 32.073, lon: 34.792, features: ['ac']),
      f(id: 'rg-4room', price: 5300, rooms: 4, sizeM2: 92, city: 'רמת גן', lat: 32.083, lon: 34.814, features: ['ac', 'elevator', 'mamad']),
      // ── Petah Tikva — family ─────────────────────────────────────────────────
      f(id: 'pt-family-4r', price: 5900, rooms: 4, sizeM2: 104, city: 'פתח תקווה', lat: 32.088, lon: 34.887, floor: '2', features: ['ac', 'elevator', 'mamad', 'balcony']),
      f(id: 'pt-small-3r', price: 5600, rooms: 3, sizeM2: 68, city: 'פתח תקווה', lat: 32.09, lon: 34.88, floor: '7', features: ['ac']),
      f(id: 'pt-cheap-2r', price: 4800, rooms: 2, sizeM2: 55, city: 'פתח תקווה', lat: 32.087, lon: 34.885, features: ['ac']),
      // ── Haifa ────────────────────────────────────────────────────────────────
      f(id: 'hf-elevator', price: 4800, rooms: 3, sizeM2: 78, city: 'חיפה', lat: 32.79, lon: 34.99, floor: '6', features: ['ac', 'elevator']),
      f(id: 'hf-ground', price: 4700, rooms: 3, sizeM2: 74, city: 'חיפה', lat: 32.81, lon: 34.99, floor: '0', features: ['ac']),
      f(id: 'hf-walkup5', price: 4500, rooms: 3, sizeM2: 82, city: 'חיפה', lat: 32.80, lon: 34.98, floor: '5', features: ['ac']),
      f(id: 'hf-sale-hi', price: 1150000, rooms: 4, sizeM2: 92, city: 'חיפה', lat: 32.80, lon: 34.99, type: PropertyTransactionType.sale),
      f(id: 'hf-sale-lo', price: 1950000, rooms: 3, sizeM2: 78, city: 'חיפה', lat: 32.81, lon: 34.98, type: PropertyTransactionType.sale),
      // ── Netanya — retiree ────────────────────────────────────────────────────
      f(id: 'net-elev-quiet', price: 4900, rooms: 3, sizeM2: 82, city: 'נתניה', lat: 32.32, lon: 34.853, floor: '2', features: ['ac', 'elevator']),
      f(id: 'net-walkup', price: 4600, rooms: 3, sizeM2: 80, city: 'נתניה', lat: 32.31, lon: 34.86, floor: '4', features: ['ac']),
    ];

void show(String persona, EttiPlan plan) {
  final q = plan.toQuery();
  final recs = RecommendationEngine.recommendAsScored(
      candidates: catalogue(), query: q, limit: 8, seed: 30);
  // ignore: avoid_print
  print('\n════════ $persona ════════');
  // ignore: avoid_print
  print('   plan: hc=${plan.hardConstraints} weights=${q.weights.map((k, v) => MapEntry(k, v.toStringAsFixed(2)))}');
  for (final s in recs.take(3)) {
    final p = s.property;
    final sc = s.scorecard!;
    // ignore: avoid_print
    print('   • ${p.id}: ${p.priceLabel}, ${p.rooms.toInt()}חד׳/${p.sizeM2}מ״ר '
        'קומה${p.floorNumber ?? "?"}, ${p.city} · fit ${sc.fitPct}%'
        '${sc.concerns.isNotEmpty ? "  ⚠ ${sc.concerns.first}" : ""}');
  }
}

void main() {
  setUpAll(() async {
    GovData.instance.resetForTest();
    await GovData.instance.init(reader: _diskReader);
  });
  tearDownAll(() => GovData.instance.resetForTest());

  test('critical exam — 6 real personas via Etti plans', () {
    show('A · זוג צעיר · ת״א · תקציב הדוק · תחב״צ', EttiPlan.fromJson({
      'hard_constraints': {'city': 'תל אביב', 'max_price': 5600},
      'soft_weights': {'transit': 1.9, 'value': 1.7, 'budget': 1.9, 'size': -0.5},
      'inferred_persona': 'priced-out young couple, car-free',
    }));
    show('B · משפחה מתרחבת · פ״ת · ליד הורים', EttiPlan.fromJson({
      'hard_constraints': {'city': 'פתח תקווה', 'min_rooms': 4},
      'soft_weights': {'family_friendly': 1.8, 'schools_nearby': 1.6, 'security': 1.7, 'accessibility_stroller': 1.5, 'quiet_neighborhood': 1.4},
      'inferred_persona': 'family expanding near parents',
    }));
    show('C · משקיע · חיפה · תשואה', EttiPlan.fromJson({
      'hard_constraints': {'city': 'חיפה', 'transaction_type': 'sale', 'max_price': 1500000},
      'soft_weights': {'yield': 2.0, 'value': 1.5},
      'inferred_persona': 'yield investor',
    }));
    show('D · רווק + כלב + ים (התנגשות)', EttiPlan.fromJson({
      'hard_constraints': {'city': 'תל אביב', 'pets': true},
      'soft_weights': {'near_sea': 1.9, 'central_location': 1.7, 'ground_floor': 1.6, 'size': -1.0},
      'inferred_persona': 'single dog-owner, beach lifestyle',
    }));
    show('E · כיסא גלגלים · חיפה', EttiPlan.fromJson({
      'hard_constraints': {'city': 'חיפה', 'accessible': true},
      'soft_weights': {'accessibility': 2.0, 'security': 1.3},
      'inferred_persona': 'wheelchair user',
    }));
    show('F · גמלאים · נתניה · שקט+מרפאה', EttiPlan.fromJson({
      'hard_constraints': {'city': 'נתניה'},
      'soft_weights': {'quiet_neighborhood': 1.8, 'accessibility': 1.6, 'safety': 1.4},
      'inferred_persona': 'retired couple, quiet + accessible',
    }));
    expect(true, true); // this test EXISTS to print for critique, not to assert
  });
}
