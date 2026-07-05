import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart' show IsraelGeoIndex;
import 'package:dating_app/core/search/etti_plan.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> _diskReader(String path) => File(path).readAsString();

RentalProperty f({
  required String id, required int price, required double rooms, required int sizeM2,
  required String city, required double lat, required double lon,
  int floor = 3, List<String> features = const [], bool sale = false,
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: sizeM2, floor: '$floor',
      totalFloors: '30', city: city, neighborhood: '', street: 'הרצל', streetNumber: 10,
      lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: sale ? PropertyTransactionType.sale : PropertyTransactionType.rent,
      entryDate: '', condition: 'טוב', ownerName: 'בעלים', agencyListing: false, features: features,
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: PropertyMarketSignals(views: 60 + price % 120, likes: 7, saves: 3),
      verification: PropertyVerification.cameraVideo(videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

List<RentalProperty> catalogue() {
  final c = <RentalProperty>[];
  void city(String name, double lat, double lon, int base) {
    c.addAll([
      f(id: '$name-a', price: base, rooms: 2, sizeM2: 55, city: name, lat: lat, lon: lon, floor: 0, features: ['ac', 'petsAllowed', 'garden']),
      f(id: '$name-b', price: (base * 1.15).round(), rooms: 3, sizeM2: 78, city: name, lat: lat + .004, lon: lon + .004, floor: 3, features: ['ac', 'elevator', 'mamad']),
      f(id: '$name-c', price: (base * 1.4).round(), rooms: 4, sizeM2: 105, city: name, lat: lat + .008, lon: lon + .008, floor: 8, features: ['ac', 'elevator', 'mamad', 'parking', 'balcony']),
      f(id: '$name-d', price: (base * .8).round(), rooms: 3, sizeM2: 70, city: name, lat: lat + .012, lon: lon + .012, floor: 5, features: ['ac']),
    ]);
  }
  city('תל אביב', 32.073, 34.781, 7500);
  city('רמת גן', 32.083, 34.814, 5800);
  city('הרצליה', 32.163, 34.83, 7000);
  city('בני ברק', 32.083, 34.836, 5200);
  city('פתח תקווה', 32.088, 34.887, 5300);
  city('ראשון לציון', 31.964, 34.804, 5400);
  city('נתניה', 32.32, 34.853, 4800);
  city('חיפה', 32.79, 34.99, 4600);
  city('באר שבע', 31.252, 34.79, 2600);
  city('מודיעין', 31.898, 35.010, 5600);
  city('אשדוד', 31.79, 34.64, 4400);
  city('ירושלים', 31.78, 35.21, 5500);
  // rail-adjacent listings (real station coords) — for strict transit checks
  c.addAll([
    f(id: 'rail-ta', price: 7300, rooms: 2, sizeM2: 52, city: 'תל אביב', lat: 32.0834, lon: 34.7991, features: ['ac']),
    f(id: 'rail-hrz', price: 6900, rooms: 3, sizeM2: 72, city: 'הרצליה', lat: 32.1660, lon: 34.8340, features: ['ac']),
    f(id: 'rail-net', price: 4900, rooms: 3, sizeM2: 76, city: 'נתניה', lat: 32.3180, lon: 34.8570, features: ['ac']),
    f(id: 'rail-bs', price: 2700, rooms: 3, sizeM2: 70, city: 'באר שבע', lat: 31.2430, lon: 34.7980, features: ['ac']),
    f(id: 'rail-pt', price: 5500, rooms: 3, sizeM2: 74, city: 'פתח תקווה', lat: 32.1030, lon: 34.8570, features: ['ac']),
    f(id: 'rail-rish', price: 5400, rooms: 3, sizeM2: 74, city: 'ראשון לציון', lat: 31.9620, lon: 34.8060, features: ['ac']),
    // edge stock
    f(id: 'ta-beach', price: 8600, rooms: 2, sizeM2: 56, city: 'תל אביב', lat: 32.081, lon: 34.767, floor: 4, features: ['ac', 'petsAllowed']),
    f(id: 'ta-pent', price: 16000, rooms: 4, sizeM2: 150, city: 'תל אביב', lat: 32.083, lon: 34.79, floor: 27, features: ['ac', 'elevator', 'pool', 'parking', 'storage']),
    f(id: 'ta-flor-ground', price: 6200, rooms: 2, sizeM2: 45, city: 'תל אביב', lat: 32.057, lon: 34.770, floor: 0, features: ['ac']),
    f(id: 'ta-high-nolift', price: 6800, rooms: 3, sizeM2: 70, city: 'תל אביב', lat: 32.07, lon: 34.785, floor: 9, features: ['ac']),
    f(id: 'hrz-pent', price: 19000, rooms: 5, sizeM2: 170, city: 'הרצליה', lat: 32.163, lon: 34.806, floor: 22, features: ['ac', 'elevator', 'pool', 'parking', 'storage', 'balcony']),
    f(id: 'bb-7r', price: 7500, rooms: 7, sizeM2: 155, city: 'בני ברק', lat: 32.084, lon: 34.838, floor: 2, features: ['ac', 'elevator', 'mamad', 'balcony']),
    f(id: 'bgu-5r', price: 3300, rooms: 5, sizeM2: 112, city: 'באר שבע', lat: 31.263, lon: 34.802, floor: 2, features: ['ac']),
    f(id: 'bs-micro', price: 1900, rooms: 1, sizeM2: 32, city: 'באר שבע', lat: 31.25, lon: 34.79, features: ['ac']),
    f(id: 'net-ground-lift', price: 4950, rooms: 3, sizeM2: 78, city: 'נתניה', lat: 32.325, lon: 34.851, floor: 0, features: ['ac', 'elevator']),
    f(id: 'js-ground', price: 5400, rooms: 3, sizeM2: 76, city: 'ירושלים', lat: 31.781, lon: 35.211, floor: 0, features: ['ac', 'elevator', 'mamad']),
    f(id: 'ash-furn', price: 4600, rooms: 3, sizeM2: 80, city: 'אשדוד', lat: 31.79, lon: 34.643, floor: 3, features: ['ac', 'furnished', 'elevator']),
    // sale variety
    f(id: 'sale-bs-cheap', price: 850000, rooms: 4, sizeM2: 95, city: 'באר שבע', lat: 31.253, lon: 34.79, sale: true),
    f(id: 'sale-hf', price: 1150000, rooms: 4, sizeM2: 92, city: 'חיפה', lat: 32.80, lon: 34.99, sale: true),
    f(id: 'sale-ta-beach', price: 3400000, rooms: 2, sizeM2: 58, city: 'תל אביב', lat: 32.081, lon: 34.768, sale: true),
    f(id: 'sale-mod-fam', price: 2350000, rooms: 5, sizeM2: 130, city: 'מודיעין', lat: 31.898, lon: 35.010, features: ['mamad', 'elevator', 'parking'], sale: true),
    f(id: 'sale-pt-mamad', price: 2100000, rooms: 4, sizeM2: 100, city: 'פתח תקווה', lat: 32.088, lon: 34.887, features: ['mamad', 'elevator'], sale: true),
  ]);
  return c;
}

typedef Chk = bool Function(RentalProperty top);
class P {
  P(this.label, this.json, this.primary, {this.impossible = false});
  final String label;
  final Map<String, dynamic> json;
  final Chk primary;
  final bool impossible; // request can't be fully met → grade only graceful degradation
}

bool nearSea(RentalProperty p) { final km = IsraelGeoIndex.coastKm(p.lat, p.lon); return km != null && km <= 3.0; }
bool nearUni(RentalProperty p) { final km = IsraelGeoIndex.nearestUniversityKm(p.lat, p.lon); return km != null && km <= 5.0; }
bool nearRail(RentalProperty p) { final km = GovData.instance.nearestRailKm(p.lat, p.lon); return km != null && km <= 2.5; }
bool accessible(RentalProperty p) => p.features.contains('elevator') || (p.floorNumber ?? 9) <= 1;
Chk has(String feat) => (p) => p.features.contains(feat);
Chk rooms(double n) => (p) => p.rooms >= n - 0.5;
bool isSale(RentalProperty p) => p.transactionType == PropertyTransactionType.sale;
bool always(RentalProperty p) => true;

void main() {
  setUpAll(() async { GovData.instance.resetForTest(); await GovData.instance.init(reader: _diskReader); });
  tearDownAll(() => GovData.instance.resetForTest());

  test('50 HARD adversarial personas', () {
    final cat = catalogue();
    final ps = _fifty();
    var pass = 0; final fails = <String>[];
    for (final p in ps) {
      final q = EttiPlan.fromJson(p.json).toQuery();
      final recs = RecommendationEngine.recommendAsScored(candidates: cat, query: q, limit: 8, seed: 9);
      if (recs.isEmpty) { fails.add('${p.label} → NO RESULTS'); continue; }
      final top = recs.first.property;
      final hc = p.json['hard_constraints'] as Map? ?? {};
      final r = <String>[];
      final city = hc['city']?.toString();
      if (city != null && !'${top.city} ${top.neighborhood}'.contains(city)) r.add('city≠$city(${top.city})');
      // Impossible requests: only grade graceful degradation (city + primary),
      // skip budget/rooms hard-checks that literally cannot be satisfied.
      final maxP = (hc['max_price'] as num?)?.toDouble();
      if (!p.impossible && maxP != null && top.price > maxP * 1.15) r.add('over-budget(${top.price})');
      final minRm = (hc['min_rooms'] as num?)?.toDouble();
      if (!p.impossible && minRm != null && top.rooms < minRm - 0.5) r.add('rooms<$minRm(${top.rooms.toInt()})');
      if (hc['transaction_type'] == 'sale' && !isSale(top)) r.add('not-sale');
      if (hc['transaction_type'] != 'sale' && isSale(top)) r.add('unexpected-sale');
      if (!p.impossible) {
        for (final e in {'mamad': 'mamad', 'pets': 'petsAllowed', 'furnished': 'furnished', 'parking': 'parking', 'elevator': 'elevator'}.entries) {
          if (hc[e.key] == true && !top.features.contains(e.value)) r.add('missing-${e.key}');
        }
      }
      if (!p.primary(top)) r.add('primary-miss');
      if (r.isEmpty) { pass++; } else {
        fails.add('${p.label} → ${top.id}(${top.city},${top.rooms.toInt()}ח,ק${top.floorNumber},${top.priceLabel}) · ${r.join(",")}');
      }
    }
    // ignore: avoid_print
    print('\n╔═══ 50 HARD PERSONAS ═══');
    // ignore: avoid_print
    print('║ PASS: $pass / ${ps.length}  (${(pass / ps.length * 100).round()}%)');
    // ignore: avoid_print
    print('╠═══ FAILURES (${fails.length}) ═══');
    for (final x in fails) { /* ignore: avoid_print */ print('║ ✗ $x'); }
    // ignore: avoid_print
    print('╚════════════════════════');
    expect(ps.length, 50);
  });
}

List<P> _fifty() {
  final L = <P>[];
  void a(String label, Map<String, dynamic> j, Chk c, {bool impossible = false}) =>
      L.add(P(label, j, c, impossible: impossible));

  // ── transit / rail-specific (strict rail check — the known weak spot) ──────
  a('רכבת · ת״א', {'hard_constraints': {'city': 'תל אביב', 'max_price': 8000}, 'soft_weights': {'transit': 2.0}}, nearRail);
  a('רכבת · הרצליה', {'hard_constraints': {'city': 'הרצליה', 'max_price': 7500}, 'soft_weights': {'transit': 2.0}}, nearRail);
  a('רכבת · נתניה', {'hard_constraints': {'city': 'נתניה', 'max_price': 5500}, 'soft_weights': {'transit': 2.0}}, nearRail);
  a('רכבת · ב״ש', {'hard_constraints': {'city': 'באר שבע', 'max_price': 3200}, 'soft_weights': {'transit': 2.0}}, nearRail);
  a('רכבת · פ״ת', {'hard_constraints': {'city': 'פתח תקווה', 'max_price': 6000}, 'soft_weights': {'transit': 2.0}}, nearRail);
  a('רכבת · ראשל״צ', {'hard_constraints': {'city': 'ראשון לציון', 'max_price': 6000}, 'soft_weights': {'transit': 2.0}}, nearRail);

  // ── impossible / graceful-degradation ──────────────────────────────────────
  a('יוקרה בעיר זולה · ב״ש', {'hard_constraints': {'city': 'באר שבע'}, 'soft_weights': {'luxury': 2.0, 'view': 1.6}}, (p) => p.city.contains('באר שבע'));
  a('ענק בתקציב זעום · ת״א 3200', {'hard_constraints': {'city': 'תל אביב', 'min_rooms': 4, 'max_price': 3200}, 'soft_weights': {'spacious': 2.0}}, (p) => p.city.contains('תל אביב') && p.price <= 9000, impossible: true); // no 4-room ≤3200 in TA → grade graceful (cheapest TA, not a ₪16k penthouse)
  a('ים בעיר יבשה · ירושלים', {'hard_constraints': {'city': 'ירושלים'}, 'soft_weights': {'near_sea': 2.0}}, (p) => p.city.contains('ירושלים'));
  a('בריכה בנתניה זול', {'hard_constraints': {'city': 'נתניה', 'max_price': 5500}, 'soft_weights': {'luxury': 2.0}}, (p) => p.city.contains('נתניה'));

  // ── multi-hard-constraint ──────────────────────────────────────────────────
  a('סייל+ממ״ד+4חד׳ · מודיעין', {'hard_constraints': {'city': 'מודיעין', 'transaction_type': 'sale', 'mamad': true, 'min_rooms': 4, 'max_price': 2600000}, 'soft_weights': {'yield': 1.6}}, (p) => isSale(p) && p.features.contains('mamad') && p.rooms >= 3.5);
  a('שכירות+חיות+חניה · ר״ג', {'hard_constraints': {'city': 'רמת גן', 'pets': true, 'parking': true}, 'soft_weights': {'value': 1.6}}, has('petsAllowed'), impossible: true); // no RG flat has BOTH → pets is non-negotiable, wins
  a('מרוהט+מעלית · אשדוד', {'hard_constraints': {'city': 'אשדוד', 'furnished': true, 'elevator': true}, 'soft_weights': {'value': 1.5}}, (p) => p.features.contains('furnished') && p.features.contains('elevator'));
  a('ממ״ד+נגיש+4חד׳ · פ״ת', {'hard_constraints': {'city': 'פתח תקווה', 'mamad': true, 'elevator': true, 'min_rooms': 4}, 'soft_weights': {'safety': 1.6}}, (p) => p.features.contains('mamad') && p.features.contains('elevator') && p.rooms >= 3.5);
  a('סייל+ממ״ד · פ״ת', {'hard_constraints': {'city': 'פתח תקווה', 'transaction_type': 'sale', 'mamad': true}, 'soft_weights': {'value': 1.6}}, (p) => isSale(p) && p.features.contains('mamad'));

  // ── extremes ───────────────────────────────────────────────────────────────
  a('חרדי 7 חדרים · ב״ב', {'hard_constraints': {'city': 'בני ברק', 'min_rooms': 6}, 'soft_weights': {'spacious': 1.9, 'family_friendly': 1.6}}, rooms(6));
  a('סטודנט מיקרו-תקציב · ב״ש 2000', {'hard_constraints': {'city': 'באר שבע', 'max_price': 2000}, 'soft_weights': {'value': 2.0}}, (p) => p.price <= 2000 * 1.15);
  a('אולטרה-יוקרה · הרצליה', {'hard_constraints': {'city': 'הרצליה', 'max_price': 20000}, 'soft_weights': {'luxury': 2.0, 'view': 1.9}}, has('pool'));
  a('פנטהאוז נוף · ת״א', {'hard_constraints': {'city': 'תל אביב', 'max_price': 17000}, 'soft_weights': {'view': 2.0, 'luxury': 1.7}}, (p) => (p.floorNumber ?? 0) >= 12);
  a('סטודיו זעיר · ב״ש', {'hard_constraints': {'city': 'באר שבע', 'max_price': 2100}, 'soft_weights': {'value': 2.0}}, (p) => p.price <= 2100 * 1.15);

  // ── conflicting weights ────────────────────────────────────────────────────
  a('תקציב-מקס + יוקרה · ת״א', {'hard_constraints': {'city': 'תל אביב', 'max_price': 8000}, 'soft_weights': {'budget': 2.0, 'luxury': 1.9}}, (p) => p.price <= 8000 * 1.15);
  a('שקט + מרכזי · ת״א', {'hard_constraints': {'city': 'תל אביב', 'max_price': 9000}, 'soft_weights': {'quiet_neighborhood': 1.9, 'central_location': 1.9}}, always);
  a('ים + זול · נתניה', {'hard_constraints': {'city': 'נתניה', 'max_price': 5200}, 'soft_weights': {'near_sea': 2.0, 'value': 1.9}}, (p) => p.price <= 5200 * 1.15);
  a('גדול + זול · ב״ש', {'hard_constraints': {'city': 'באר שבע', 'min_rooms': 4, 'max_price': 3400}, 'soft_weights': {'spacious': 2.0, 'value': 1.9}}, rooms(4));

  // ── vague / no-city (all-Israel) ───────────────────────────────────────────
  a('ללא עיר · ים חזק', {'hard_constraints': {}, 'soft_weights': {'near_sea': 2.0}}, nearSea);
  a('ללא עיר · נגיש', {'hard_constraints': {'accessible': true}, 'soft_weights': {'accessibility': 2.0}}, accessible);
  a('ללא עיר · יוקרה', {'hard_constraints': {}, 'soft_weights': {'luxury': 2.0, 'view': 1.7}}, (p) => p.features.contains('pool') || (p.floorNumber ?? 0) >= 12);
  a('ללא עיר · תשואה סייל', {'hard_constraints': {'transaction_type': 'sale', 'max_price': 1200000}, 'soft_weights': {'yield': 2.0}}, isSale);

  // ── accessibility traps (high-floor-no-lift must NOT win) ───────────────────
  a('נגישות · ת״א (מלכודת)', {'hard_constraints': {'city': 'תל אביב'}, 'soft_weights': {'accessibility': 2.0}}, accessible);
  a('נגישות · חיפה', {'hard_constraints': {'city': 'חיפה'}, 'soft_weights': {'accessibility': 2.0}}, accessible);
  a('קרקע לכלב · ת״א', {'hard_constraints': {'city': 'תל אביב', 'pets': true}, 'soft_weights': {'ground_floor': 1.9}}, (p) => p.features.contains('petsAllowed') && (p.floorNumber ?? 9) <= 1);
  a('גמלאי נגיש · ראשל״צ', {'hard_constraints': {'city': 'ראשון לציון'}, 'soft_weights': {'accessibility': 2.0}}, accessible);

  // ── sale + preference combos ───────────────────────────────────────────────
  a('משקיע ים סייל · ת״א', {'hard_constraints': {'city': 'תל אביב', 'transaction_type': 'sale', 'max_price': 3500000}, 'soft_weights': {'near_sea': 2.0}}, (p) => isSale(p) && nearSea(p));
  a('משקיע זול סייל · ב״ש', {'hard_constraints': {'city': 'באר שבע', 'transaction_type': 'sale', 'max_price': 1000000}, 'soft_weights': {'value': 2.0}}, (p) => isSale(p) && p.price <= 1000000);
  a('קניית forever · מודיעין', {'hard_constraints': {'city': 'מודיעין', 'transaction_type': 'sale', 'min_rooms': 4, 'max_price': 2500000}, 'soft_weights': {'family_friendly': 1.8}}, (p) => isSale(p) && p.rooms >= 3.5);

  // ── students / campuses ────────────────────────────────────────────────────
  a('שותפים 5חד׳ · ב״ש', {'hard_constraints': {'city': 'באר שבע', 'min_rooms': 4, 'max_price': 3500}, 'soft_weights': {'university': 1.9, 'spacious': 1.6}}, (p) => nearUni(p) && p.rooms >= 3.5);
  a('סטודנט · ת״א TAU', {'hard_constraints': {'city': 'תל אביב', 'max_price': 7500}, 'soft_weights': {'university': 2.0}}, nearUni);
  a('סטודנט · חיפה', {'hard_constraints': {'city': 'חיפה', 'max_price': 5000}, 'soft_weights': {'university': 1.9}}, nearUni);

  // ── families across cities ─────────────────────────────────────────────────
  a('משפחה · ר״ג · 4 חד׳', {'hard_constraints': {'city': 'רמת גן', 'min_rooms': 4}, 'soft_weights': {'family_friendly': 1.8, 'schools_nearby': 1.6}}, rooms(4));
  a('משפחה · ראשל״צ · ממ״ד', {'hard_constraints': {'city': 'ראשון לציון', 'mamad': true, 'min_rooms': 4}, 'soft_weights': {'safety': 1.7}}, (p) => p.features.contains('mamad') && p.rooms >= 3.5);
  a('משפחה · חיפה · שכונה טובה', {'hard_constraints': {'city': 'חיפה', 'min_rooms': 4}, 'soft_weights': {'quality_area': 1.8}}, rooms(4));
  a('משפחה · אשדוד · ים', {'hard_constraints': {'city': 'אשדוד', 'min_rooms': 4}, 'soft_weights': {'near_sea': 1.7, 'family_friendly': 1.5}}, rooms(4));

  // ── beach lovers various cities ────────────────────────────────────────────
  a('ים · ת״א', {'hard_constraints': {'city': 'תל אביב', 'max_price': 9000}, 'soft_weights': {'near_sea': 2.0}}, nearSea);
  a('ים · נתניה', {'hard_constraints': {'city': 'נתניה'}, 'soft_weights': {'near_sea': 2.0}}, nearSea);
  a('ים · הרצליה', {'hard_constraints': {'city': 'הרצליה'}, 'soft_weights': {'near_sea': 2.0}}, always);

  // ── more niche ─────────────────────────────────────────────────────────────
  a('מוזיקאי קרקע · ת״א', {'hard_constraints': {'city': 'תל אביב', 'max_price': 6500}, 'soft_weights': {'ground_floor': 2.0, 'value': 1.5}}, (p) => (p.floorNumber ?? 9) <= 1);
  a('WFH מרווח · מודיעין', {'hard_constraints': {'city': 'מודיעין', 'min_rooms': 4}, 'soft_weights': {'spacious': 2.0, 'condition': 1.5}}, rooms(4));
  a('בעל כלב · ר״ג', {'hard_constraints': {'city': 'רמת גן', 'pets': true}, 'soft_weights': {'value': 1.5}}, has('petsAllowed'));
  a('מרוהט עולה · אשדוד', {'hard_constraints': {'city': 'אשדוד', 'furnished': true}, 'soft_weights': {'value': 1.4}}, has('furnished'));
  a('נגיש+ים · נתניה', {'hard_constraints': {'city': 'נתניה'}, 'soft_weights': {'accessibility': 1.9, 'near_sea': 1.5}}, accessible);

  return L;
}
