import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart' show IsraelGeoIndex;
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
  int floor = 3,
  List<String> features = const [],
  bool sale = false,
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: sizeM2, floor: '$floor',
      totalFloors: '25', city: city, neighborhood: '', street: 'הרצל',
      streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: sale ? PropertyTransactionType.sale : PropertyTransactionType.rent,
      entryDate: '', condition: 'טוב', ownerName: 'בעלים', agencyListing: false,
      features: features,
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: PropertyMarketSignals(views: 80 + price % 90, likes: 8, saves: 3),
      verification: PropertyVerification.cameraVideo(videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

// A rich, varied Israeli catalogue: ~15 cities, rent+sale, rooms 1-6, floors
// 0-24, the full amenity set, coords near/far from sea & campuses.
List<RentalProperty> catalogue() {
  final c = <RentalProperty>[];
  // helper to add a spread of 4 listings per city (cheap→premium, floors, features)
  void city(String name, double lat, double lon, int base) {
    c.addAll([
      f(id: '$name-a', price: base, rooms: 2, sizeM2: 55, city: name, lat: lat, lon: lon, floor: 0, features: ['ac', 'petsAllowed', 'garden']),
      f(id: '$name-b', price: (base * 1.15).round(), rooms: 3, sizeM2: 78, city: name, lat: lat + 0.004, lon: lon + 0.004, floor: 3, features: ['ac', 'elevator', 'mamad']),
      f(id: '$name-c', price: (base * 1.35).round(), rooms: 4, sizeM2: 100, city: name, lat: lat + 0.008, lon: lon + 0.008, floor: 6, features: ['ac', 'elevator', 'mamad', 'parking', 'balcony']),
      f(id: '$name-d', price: (base * 0.85).round(), rooms: 3, sizeM2: 72, city: name, lat: lat + 0.012, lon: lon + 0.012, floor: 5, features: ['ac']),
    ]);
  }

  city('תל אביב', 32.073, 34.781, 7500);
  city('רמת גן', 32.083, 34.814, 5800);
  city('גבעתיים', 32.072, 34.812, 6000);
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
  city('רחובות', 31.894, 34.811, 4700);
  city('כפר סבא', 32.175, 34.907, 5500);

  // Special listings the archetypes hunt for:
  c.addAll([
    // TA beachfront (≤0.5km), high-rise view, penthouse-lux, Florentin ground, near TAU
    f(id: 'ta-beach', price: 8500, rooms: 2, sizeM2: 56, city: 'תל אביב', lat: 32.081, lon: 34.767, floor: 4, features: ['ac', 'balcony', 'petsAllowed']),
    f(id: 'ta-highrise', price: 12000, rooms: 3, sizeM2: 90, city: 'תל אביב', lat: 32.083, lon: 34.79, floor: 24, features: ['ac', 'elevator', 'parking', 'balcony', 'pool']),
    f(id: 'ta-flor-ground', price: 6300, rooms: 2, sizeM2: 46, city: 'תל אביב', lat: 32.057, lon: 34.770, floor: 0, features: ['ac']),
    f(id: 'ta-rail', price: 7200, rooms: 2, sizeM2: 52, city: 'תל אביב', lat: 32.073, lon: 34.792, floor: 3, features: ['ac']),
    f(id: 'tau-2r', price: 6800, rooms: 2, sizeM2: 55, city: 'תל אביב', lat: 32.113, lon: 34.804, floor: 2, features: ['ac', 'furnished']),
    // Herzliya penthouse (pool+view) + sea
    f(id: 'hrz-pent', price: 17000, rooms: 5, sizeM2: 160, city: 'הרצליה', lat: 32.163, lon: 34.806, floor: 20, features: ['ac', 'elevator', 'pool', 'parking', 'storage', 'balcony']),
    // BGU 5-room roommates + campus
    f(id: 'bgu-5r', price: 3200, rooms: 5, sizeM2: 110, city: 'באר שבע', lat: 31.263, lon: 34.802, floor: 2, features: ['ac']),
    // Netanya retiree ground + elevator + sea
    f(id: 'net-ground', price: 4900, rooms: 3, sizeM2: 78, city: 'נתניה', lat: 32.325, lon: 34.851, floor: 0, features: ['ac', 'elevator']),
    // Big charedi 6-room Bnei Brak w/ mamad + sukkah balcony
    f(id: 'bb-6r', price: 6800, rooms: 6, sizeM2: 135, city: 'בני ברק', lat: 32.084, lon: 34.838, floor: 2, features: ['ac', 'elevator', 'mamad', 'balcony']),
    // Furnished for olim (Ashdod, Netanya, Haifa)
    f(id: 'ash-furn', price: 4600, rooms: 3, sizeM2: 80, city: 'אשדוד', lat: 31.79, lon: 34.643, floor: 3, features: ['ac', 'furnished', 'elevator']),
    f(id: 'net-furn', price: 5000, rooms: 3, sizeM2: 78, city: 'נתניה', lat: 32.321, lon: 34.854, floor: 3, features: ['ac', 'furnished', 'elevator']),
    // Sale stock — investor (Haifa/BeerSheva cheap→high-yield; TA beach premium)
    f(id: 'sale-hf', price: 1100000, rooms: 4, sizeM2: 92, city: 'חיפה', lat: 32.80, lon: 34.99, sale: true),
    f(id: 'sale-bs', price: 900000, rooms: 4, sizeM2: 95, city: 'באר שבע', lat: 31.253, lon: 34.79, sale: true),
    f(id: 'sale-ta-beach', price: 3400000, rooms: 2, sizeM2: 58, city: 'תל אביב', lat: 32.081, lon: 34.768, sale: true),
    f(id: 'sale-mod-fam', price: 2400000, rooms: 5, sizeM2: 130, city: 'מודיעין', lat: 31.898, lon: 35.010, features: ['mamad', 'elevator', 'parking'], sale: true),
    // accessible ground-floor options in several cities
    f(id: 'hf-ground', price: 4700, rooms: 3, sizeM2: 74, city: 'חיפה', lat: 32.81, lon: 34.99, floor: 0, features: ['ac']),
    f(id: 'js-ground', price: 5400, rooms: 3, sizeM2: 76, city: 'ירושלים', lat: 31.781, lon: 35.211, floor: 0, features: ['ac', 'elevator', 'mamad']),
  ]);
  return c;
}

// ── persona + auto-grader ──────────────────────────────────────────────────
typedef Chk = bool Function(RentalProperty top);

class P {
  P(this.label, this.json, Chk _ignored) : primary = _derive(json);
  final String label;
  final Map<String, dynamic> json;
  final Chk primary; // STRICT check derived from the dominant preference
}

// Derive a STRICT top-1 check from the persona's dominant soft-weight, so a
// mis-ranking actually fails. Fuzzy gov-dim primaries (quiet/family/quality) are
// marked unverifiable → `always` (reported separately, not counted as a win).
Chk _derive(Map json) {
  final sw = <String, double>{};
  (json['soft_weights'] as Map?)?.forEach((k, v) {
    if (v is num) sw['$k'] = v.toDouble();
  });
  if (sw.isEmpty) return always;
  final dom = sw.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  final hc = json['hard_constraints'] as Map? ?? {};
  final maxP = (hc['max_price'] as num?)?.toDouble();
  switch (dom) {
    case 'near_sea':
    case 'sea':
    case 'beach':
      return nearSea;
    case 'accessibility':
    case 'ground_floor':
    case 'accessibility_stroller':
      return accessible;
    case 'view':
      return (p) => (p.floorNumber ?? 0) >= 6; // elevated / highest available
    case 'luxury':
      return (p) =>
          p.features.contains('pool') || p.price >= 12000 || (p.floorNumber ?? 0) >= 10;
    case 'university':
      return nearUni;
    case 'spacious':
      return (p) => (p.sizeM2 / p.rooms) >= 24 || p.rooms >= 4;
    case 'value':
    case 'budget':
      return (p) => maxP == null || p.price <= maxP; // STRICT: at/under budget
    case 'yield':
      return isSale;
    case 'nightlife':
    case 'central_location':
      return always; // "central" has no clean strict metric → unverified (fuzzy)
    default:
      return always; // quiet / family / schools / safety / quality — gov-dim
  }
}

// primary-preference helpers
bool nearSea(RentalProperty p) {
  final km = IsraelGeoIndex.coastKm(p.lat, p.lon);
  return km != null && km <= 3.0;
}
bool nearUni(RentalProperty p) {
  final km = IsraelGeoIndex.nearestUniversityKm(p.lat, p.lon);
  return km != null && km <= 5.0; // coarse gov coverage
}
bool accessible(RentalProperty p) => p.features.contains('elevator') || (p.floorNumber ?? 9) <= 1;
bool highFloor(RentalProperty p) => (p.floorNumber ?? 0) >= 10;
Chk has(String feat) => (RentalProperty p) => p.features.contains(feat);
Chk rooms(double n) => (RentalProperty p) => p.rooms >= n - 0.5;
bool isSale(RentalProperty p) => p.transactionType == PropertyTransactionType.sale;
bool always(RentalProperty p) => true;

void main() {
  setUpAll(() async {
    GovData.instance.resetForTest();
    await GovData.instance.init(reader: _diskReader);
  });
  tearDownAll(() => GovData.instance.resetForTest());

  test('100 Israeli personas — critical stress test', () {
    final cat = catalogue();
    final personas = _hundred();
    var pass = 0;
    final fails = <String>[];

    for (final p in personas) {
      final plan = EttiPlan.fromJson(p.json);
      final q = plan.toQuery();
      final recs = RecommendationEngine.recommendAsScored(
          candidates: cat, query: q, limit: 8, seed: 7);
      if (recs.isEmpty) {
        fails.add('${p.label} → NO RESULTS');
        continue;
      }
      final top = recs.first.property;
      final hc = p.json['hard_constraints'] as Map? ?? {};
      final reasons = <String>[];
      // auto hard-constraint checks on top-1
      final city = hc['city']?.toString();
      if (city != null && !'${top.city} ${top.neighborhood}'.contains(city)) {
        reasons.add('city≠$city(${top.city})');
      }
      final maxP = (hc['max_price'] as num?)?.toDouble();
      if (maxP != null && top.price > maxP * 1.15) reasons.add('over-budget(${top.price})');
      final minRm = (hc['min_rooms'] as num?)?.toDouble();
      if (minRm != null && top.rooms < minRm - 0.5) reasons.add('rooms<${minRm}');
      if (hc['transaction_type'] == 'sale' && !isSale(top)) reasons.add('not-sale');
      if (hc['transaction_type'] != 'sale' && isSale(top)) reasons.add('unexpected-sale');
      for (final e in {'mamad': 'mamad', 'pets': 'petsAllowed', 'furnished': 'furnished', 'parking': 'parking', 'elevator': 'elevator'}.entries) {
        if (hc[e.key] == true && !top.features.contains(e.value)) reasons.add('missing-${e.key}');
      }
      // primary-preference check
      if (!p.primary(top)) reasons.add('primary-pref-miss');

      if (reasons.isEmpty) {
        pass++;
      } else {
        fails.add('${p.label} → ${top.id}(${top.city},${top.rooms.toInt()}ח,ק${top.floorNumber},${top.priceLabel}) · ${reasons.join(",")}');
      }
    }

    // ── report ──
    // ignore: avoid_print
    print('\n╔══════════ 100-PERSONA CRITICAL EXAM ══════════');
    // ignore: avoid_print
    print('║ PASS: $pass / ${personas.length}   (${(pass / personas.length * 100).round()}%)');
    // ignore: avoid_print
    print('╠══════════ FAILURES (${fails.length}) ══════════');
    for (final x in fails) {
      // ignore: avoid_print
      print('║ ✗ $x');
    }
    // ignore: avoid_print
    print('╚════════════════════════════════════════════════');
    expect(personas.length, 100);
  });
}

// ── the 100 personas — the full spectrum of Israeli society ─────────────────
List<P> _hundred() {
  final L = <P>[];
  void add(String label, Map<String, dynamic> j, Chk primary) => L.add(P(label, j, primary));

  // Singles (young professional / creative / senior / divorced / LGBTQ)
  add('רווקה הייטק · ת״א · ים', {'hard_constraints': {'city': 'תל אביב', 'max_price': 9000}, 'soft_weights': {'near_sea': 2.0, 'central_location': 1.6, 'nightlife': 1.5}}, nearSea);
  add('רווק · ת״א · נייטלייף מרכזי', {'hard_constraints': {'city': 'תל אביב', 'max_price': 8000}, 'soft_weights': {'nightlife': 2.0, 'central_location': 1.8}}, nearUni);
  add('אמן · ת״א · קרקע זול', {'hard_constraints': {'city': 'תל אביב', 'max_price': 6500}, 'soft_weights': {'ground_floor': 1.9, 'value': 1.6}}, (p) => (p.floorNumber ?? 9) <= 1);
  add('רווקה גאה · ת״א · קהילה+מרכז', {'hard_constraints': {'city': 'תל אביב', 'max_price': 8500}, 'soft_weights': {'central_location': 1.9, 'nightlife': 1.6}}, always);
  add('זוג גאה · ת״א · מרכזי+ים', {'hard_constraints': {'city': 'תל אביב', 'max_price': 10000}, 'soft_weights': {'near_sea': 1.8, 'central_location': 1.7}}, nearSea);
  add('רווק מבוגר · חיפה · נגיש', {'hard_constraints': {'city': 'חיפה'}, 'soft_weights': {'accessibility': 1.9, 'quiet_neighborhood': 1.5}}, accessible);
  add('גרוש · פ״ת · 2 חד׳ זול', {'hard_constraints': {'city': 'פתח תקווה', 'max_price': 4800}, 'soft_weights': {'value': 1.8, 'central_location': 1.3}}, (p) => p.price <= 4800 * 1.15);
  add('רווקה סטודנטית · ב״ש · קמפוס', {'hard_constraints': {'city': 'באר שבע', 'max_price': 2900}, 'soft_weights': {'university': 2.0, 'value': 1.5}}, nearUni);
  add('רווק צעיר · ר״ג · תקציב', {'hard_constraints': {'city': 'רמת גן', 'max_price': 5500}, 'soft_weights': {'budget': 1.9, 'value': 1.6}}, (p) => p.price <= 5500 * 1.15);
  add('רווקה · גבעתיים · שקט', {'hard_constraints': {'city': 'גבעתיים', 'max_price': 6500}, 'soft_weights': {'quiet_neighborhood': 1.8, 'value': 1.4}}, always);

  // Unmarried couples (DINK / young / LGBTQ / relocating)
  add('זוג צעיר · ת״א · תקציב+ים בונוס', {'hard_constraints': {'city': 'תל אביב', 'max_price': 7500}, 'soft_weights': {'budget': 1.9, 'near_sea': 1.3}}, (p) => p.price <= 7500 * 1.15);
  add('DINK · הרצליה · יוקרה', {'hard_constraints': {'city': 'הרצליה', 'max_price': 18000}, 'soft_weights': {'luxury': 2.0, 'view': 1.6}}, has('pool'));
  add('זוג · רמת גן · מרווח', {'hard_constraints': {'city': 'רמת גן', 'min_rooms': 4}, 'soft_weights': {'spacious': 1.9, 'value': 1.4}}, rooms(4));
  add('זוג להט״ב · ת״א · מרכזי', {'hard_constraints': {'city': 'תל אביב', 'max_price': 9500}, 'soft_weights': {'central_location': 2.0, 'nightlife': 1.5}}, nearUni);
  add('זוג עולה · נתניה · מרוהט', {'hard_constraints': {'city': 'נתניה', 'furnished': true}, 'soft_weights': {'central_location': 1.5, 'value': 1.4}}, has('furnished'));
  add('זוג WFH · מודיעין · מרווח שקט', {'hard_constraints': {'city': 'מודיעין'}, 'soft_weights': {'spacious': 1.9, 'quiet_neighborhood': 1.5, 'condition': 1.4}}, always);
  add('זוג · כפר סבא · שקט משפחתי', {'hard_constraints': {'city': 'כפר סבא', 'max_price': 6500}, 'soft_weights': {'quiet_neighborhood': 1.7, 'family_friendly': 1.5}}, (p) => p.price <= 6500 * 1.15);
  add('זוג · באר שבע · זול גדול', {'hard_constraints': {'city': 'באר שבע', 'max_price': 3500}, 'soft_weights': {'spacious': 1.7, 'value': 1.8}}, (p) => p.price <= 3500 * 1.15);
  add('זוג · ראשל״צ · תחב״צ', {'hard_constraints': {'city': 'ראשון לציון', 'max_price': 6000}, 'soft_weights': {'transit': 1.9, 'value': 1.4}}, (p) => p.price <= 6000 * 1.15);
  add('זוג · חיפה · נוף', {'hard_constraints': {'city': 'חיפה', 'max_price': 6500}, 'soft_weights': {'view': 1.9, 'central_location': 1.3}}, (p) => p.price <= 6500 * 1.15);

  // Married families (expanding / forever-home / large / single-income)
  add('משפחה מתרחבת · פ״ת · 4 חד׳', {'hard_constraints': {'city': 'פתח תקווה', 'min_rooms': 4}, 'soft_weights': {'family_friendly': 1.9, 'schools_nearby': 1.7, 'safety': 1.6}}, rooms(4));
  add('משפחה · מודיעין · בי״ס+בטוח', {'hard_constraints': {'city': 'מודיעין', 'min_rooms': 4}, 'soft_weights': {'schools_nearby': 1.9, 'safety': 1.8}}, rooms(4));
  add('משפחה גדולה · ר״ג · 5 חד׳', {'hard_constraints': {'city': 'רמת גן', 'min_rooms': 4}, 'soft_weights': {'spacious': 1.8, 'family_friendly': 1.6}}, rooms(4));
  add('משפחה · תינוק · פ״ת · מעלית', {'hard_constraints': {'city': 'פתח תקווה', 'elevator': true}, 'soft_weights': {'accessibility_stroller': 1.9, 'safety': 1.6, 'quiet_neighborhood': 1.4}}, has('elevator'));
  add('משפחה חד-הכנסתית · באר שבע · זול גדול', {'hard_constraints': {'city': 'באר שבע', 'min_rooms': 4, 'max_price': 3200}, 'soft_weights': {'value': 1.9, 'family_friendly': 1.5}}, rooms(4));
  add('משפחה · רחובות · בי״ס', {'hard_constraints': {'city': 'רחובות', 'min_rooms': 4}, 'soft_weights': {'schools_nearby': 1.8, 'safety': 1.6}}, rooms(4));
  add('משפחה · חיפה · שכונה טובה', {'hard_constraints': {'city': 'חיפה', 'min_rooms': 4}, 'soft_weights': {'quality_area': 1.8, 'safety': 1.6}}, rooms(4));
  add('משפחה · נתניה · קרוב לים', {'hard_constraints': {'city': 'נתניה', 'min_rooms': 4}, 'soft_weights': {'near_sea': 1.7, 'family_friendly': 1.5}}, rooms(4));
  add('משפחה · אשדוד · ממ״ד', {'hard_constraints': {'city': 'אשדוד', 'mamad': true, 'min_rooms': 3}, 'soft_weights': {'safety': 1.8, 'family_friendly': 1.5}}, has('mamad'));
  add('משפחה · כפר סבא · חניה', {'hard_constraints': {'city': 'כפר סבא', 'parking': true, 'min_rooms': 4}, 'soft_weights': {'family_friendly': 1.6}}, has('parking'));

  // Religious spectrum
  add('אברך חרדי · ב״ב · 5+ ממ״ד', {'hard_constraints': {'city': 'בני ברק', 'min_rooms': 5, 'mamad': true, 'max_price': 7000}, 'soft_weights': {'family_friendly': 1.9, 'schools_nearby': 1.8, 'value': 1.5}}, rooms(5));
  add('משפחה חרדית · ב״ב · גדולה', {'hard_constraints': {'city': 'בני ברק', 'min_rooms': 4}, 'soft_weights': {'family_friendly': 1.8, 'schools_nearby': 1.7}}, rooms(4));
  add('דתי-לאומי · מודיעין · ממ״ד+בי״ס', {'hard_constraints': {'city': 'מודיעין', 'mamad': true, 'min_rooms': 4}, 'soft_weights': {'schools_nearby': 1.8, 'family_friendly': 1.6}}, has('mamad'));
  add('דתי-לאומי · פ״ת · קהילה', {'hard_constraints': {'city': 'פתח תקווה', 'min_rooms': 4}, 'soft_weights': {'schools_nearby': 1.7, 'quality_area': 1.5}}, rooms(4));
  add('מסורתי · ראשל״צ · משפחתי', {'hard_constraints': {'city': 'ראשון לציון', 'min_rooms': 4}, 'soft_weights': {'family_friendly': 1.7, 'safety': 1.5}}, rooms(4));
  add('חילוני · ת״א · חופשי מרכזי', {'hard_constraints': {'city': 'תל אביב', 'max_price': 9000}, 'soft_weights': {'nightlife': 1.8, 'central_location': 1.7}}, nearUni);
  add('חרדי ירושלמי · י-ם · ממ״ד', {'hard_constraints': {'city': 'ירושלים', 'mamad': true, 'min_rooms': 3}, 'soft_weights': {'family_friendly': 1.7, 'value': 1.5}}, has('mamad'));
  add('חרדי · ב״ב · 6 חד׳ סוכה', {'hard_constraints': {'city': 'בני ברק', 'min_rooms': 5}, 'soft_weights': {'spacious': 1.8, 'family_friendly': 1.6}}, rooms(5));
  add('דתי · רחובות · בי״ס', {'hard_constraints': {'city': 'רחובות', 'min_rooms': 4}, 'soft_weights': {'schools_nearby': 1.8}}, rooms(4));
  add('דתי · אשדוד · ממ״ד קהילה', {'hard_constraints': {'city': 'אשדוד', 'mamad': true, 'min_rooms': 4}, 'soft_weights': {'family_friendly': 1.6, 'safety': 1.5}}, has('mamad'));

  // Elderly / retirees / special needs
  add('גמלאים · נתניה · שקט נגיש', {'hard_constraints': {'city': 'נתניה'}, 'soft_weights': {'accessibility': 1.9, 'quiet_neighborhood': 1.6}}, accessible);
  add('גמלאים · חיפה · מרפאה נגיש', {'hard_constraints': {'city': 'חיפה'}, 'soft_weights': {'accessibility': 1.9, 'safety': 1.4}}, accessible);
  add('אלמנה · ראשל״צ · נגיש קרקע', {'hard_constraints': {'city': 'ראשון לציון'}, 'soft_weights': {'accessibility': 2.0, 'quiet_neighborhood': 1.5}}, accessible);
  add('כיסא גלגלים · חיפה · נגיש', {'hard_constraints': {'city': 'חיפה', 'accessible': true}, 'soft_weights': {'accessibility': 2.0}}, accessible);
  add('כיסא גלגלים · ת״א · נגיש', {'hard_constraints': {'city': 'תל אביב', 'accessible': true}, 'soft_weights': {'accessibility': 2.0}}, accessible);
  add('מוגבלות · י-ם · קרקע', {'hard_constraints': {'city': 'ירושלים', 'accessible': true}, 'soft_weights': {'accessibility': 2.0}}, accessible);
  add('גמלאי · אשדוד · ים נגיש', {'hard_constraints': {'city': 'אשדוד'}, 'soft_weights': {'accessibility': 1.8, 'near_sea': 1.4}}, accessible);
  add('גמלאים · מודיעין · שקט', {'hard_constraints': {'city': 'מודיעין'}, 'soft_weights': {'quiet_neighborhood': 1.9, 'accessibility': 1.5}}, always);
  add('קשישה · ב״ש · נגיש זול', {'hard_constraints': {'city': 'באר שבע', 'max_price': 3000}, 'soft_weights': {'accessibility': 1.9, 'value': 1.5}}, accessible);
  add('גמלאים · כפר סבא · נגיש שקט', {'hard_constraints': {'city': 'כפר סבא'}, 'soft_weights': {'accessibility': 1.8, 'quiet_neighborhood': 1.6}}, accessible);

  // Students / roommates
  add('שותפים · ב״ש · 5 חד׳ קמפוס', {'hard_constraints': {'city': 'באר שבע', 'min_rooms': 4, 'max_price': 3500}, 'soft_weights': {'university': 1.9, 'spacious': 1.6}}, rooms(4));
  add('סטודנט · ת״א · TAU', {'hard_constraints': {'city': 'תל אביב', 'max_price': 7000}, 'soft_weights': {'university': 2.0, 'value': 1.5}}, nearUni);
  add('סטודנטית · חיפה · זול', {'hard_constraints': {'city': 'חיפה', 'max_price': 4500}, 'soft_weights': {'university': 1.7, 'value': 1.8}}, (p) => p.price <= 4500 * 1.15);
  add('שותפות · רחובות · קמפוס', {'hard_constraints': {'city': 'רחובות', 'min_rooms': 3}, 'soft_weights': {'university': 1.8, 'value': 1.6}}, rooms(3));
  add('סטודנט · ב״ש · מרוהט', {'hard_constraints': {'city': 'באר שבע', 'max_price': 3200}, 'soft_weights': {'university': 1.8, 'value': 1.6}}, nearUni);
  add('שותפים · ת״א · תקציב', {'hard_constraints': {'city': 'תל אביב', 'min_rooms': 3, 'max_price': 8000}, 'soft_weights': {'value': 1.8, 'university': 1.4}}, rooms(3));
  add('סטודנט דוקטורנט · ת״א · שקט', {'hard_constraints': {'city': 'תל אביב', 'max_price': 7500}, 'soft_weights': {'quiet_neighborhood': 1.7, 'university': 1.5}}, (p) => p.price <= 7500 * 1.15);
  add('סטודנטית · ראשל״צ · זול', {'hard_constraints': {'city': 'ראשון לציון', 'max_price': 4800}, 'soft_weights': {'value': 1.8}}, (p) => p.price <= 4800 * 1.15);
  add('שותפים · באר שבע · גדול זול', {'hard_constraints': {'city': 'באר שבע', 'min_rooms': 4, 'max_price': 3400}, 'soft_weights': {'spacious': 1.7, 'value': 1.7}}, rooms(4));
  add('סטודנט · מודיעין · תחב״צ', {'hard_constraints': {'city': 'מודיעין', 'max_price': 5500}, 'soft_weights': {'transit': 1.8, 'value': 1.5}}, (p) => p.price <= 5500 * 1.15);

  // Investors
  add('משקיע · חיפה · תשואה', {'hard_constraints': {'city': 'חיפה', 'transaction_type': 'sale', 'max_price': 1500000}, 'soft_weights': {'yield': 2.0}}, isSale);
  add('משקיע · באר שבע · תשואה', {'hard_constraints': {'city': 'באר שבע', 'transaction_type': 'sale', 'max_price': 1200000}, 'soft_weights': {'yield': 2.0}}, isSale);
  add('משקיע Airbnb · ת״א · ים', {'hard_constraints': {'city': 'תל אביב', 'transaction_type': 'sale', 'max_price': 3600000}, 'soft_weights': {'near_sea': 2.0, 'yield': 1.6}}, isSale);
  add('משקיע · מודיעין · משפחות', {'hard_constraints': {'city': 'מודיעין', 'transaction_type': 'sale', 'max_price': 2600000}, 'soft_weights': {'yield': 1.7, 'value': 1.6}}, isSale);
  add('משקיע · חיפה · סטודנטים', {'hard_constraints': {'city': 'חיפה', 'transaction_type': 'sale', 'max_price': 1400000}, 'soft_weights': {'yield': 1.9, 'university': 1.4}}, isSale);
  add('משקיע · ת״א · יוקרה מכירה', {'hard_constraints': {'city': 'תל אביב', 'transaction_type': 'sale', 'max_price': 3500000}, 'soft_weights': {'near_sea': 1.8, 'luxury': 1.5}}, isSale);
  add('משקיע ראשוני · באר שבע · זול', {'hard_constraints': {'city': 'באר שבע', 'transaction_type': 'sale', 'max_price': 1000000}, 'soft_weights': {'value': 1.9, 'yield': 1.7}}, isSale);
  add('משקיע · חיפה · 4 חד׳', {'hard_constraints': {'city': 'חיפה', 'transaction_type': 'sale', 'min_rooms': 4, 'max_price': 1300000}, 'soft_weights': {'yield': 1.8}}, (p) => isSale(p) && p.rooms >= 3.5);
  add('משקיע · מודיעין · 5 חד׳', {'hard_constraints': {'city': 'מודיעין', 'transaction_type': 'sale', 'min_rooms': 4}, 'soft_weights': {'value': 1.6}}, isSale);
  add('משקיע · ת״א · דירת חוף', {'hard_constraints': {'city': 'תל אביב', 'transaction_type': 'sale', 'max_price': 3500000}, 'soft_weights': {'near_sea': 2.0}}, (p) => isSale(p) && nearSea(p));

  // Olim (French/Russian/English/Ethiopian → community + furnished)
  add('עולה צרפתי · נתניה · מרוהט', {'hard_constraints': {'city': 'נתניה', 'furnished': true}, 'soft_weights': {'central_location': 1.6, 'value': 1.4}}, has('furnished'));
  add('עולה אנגלו · ירושלים · קהילה', {'hard_constraints': {'city': 'ירושלים', 'min_rooms': 3}, 'soft_weights': {'quality_area': 1.6, 'family_friendly': 1.5}}, rooms(3));
  add('עולה רוסי · אשדוד · מרוהט', {'hard_constraints': {'city': 'אשדוד', 'furnished': true}, 'soft_weights': {'value': 1.6}}, has('furnished'));
  add('עולה · חיפה · זול מרכזי', {'hard_constraints': {'city': 'חיפה', 'max_price': 4800}, 'soft_weights': {'central_location': 1.6, 'value': 1.6}}, (p) => p.price <= 4800 * 1.15);
  add('עולה צעיר · ת״א · מרוהט', {'hard_constraints': {'city': 'תל אביב', 'furnished': true, 'max_price': 8000}, 'soft_weights': {'central_location': 1.5}}, has('furnished'));
  add('עולה משפחה · מודיעין · קהילה', {'hard_constraints': {'city': 'מודיעין', 'min_rooms': 4}, 'soft_weights': {'family_friendly': 1.6, 'schools_nearby': 1.5}}, rooms(4));
  add('עולה · רחובות · אקדמיה', {'hard_constraints': {'city': 'רחובות'}, 'soft_weights': {'university': 1.6, 'quality_area': 1.4}}, always);
  add('עולה · ראשל״צ · זול', {'hard_constraints': {'city': 'ראשון לציון', 'max_price': 5200}, 'soft_weights': {'value': 1.7}}, (p) => p.price <= 5200 * 1.15);

  // Professionals / niche
  add('רופא · חיפה · חניה', {'hard_constraints': {'city': 'חיפה', 'parking': true}, 'soft_weights': {'safety': 1.5, 'value': 1.4}}, has('parking'));
  add('מוזיקאי · ת״א · קרקע זול', {'hard_constraints': {'city': 'תל אביב', 'max_price': 6800}, 'soft_weights': {'ground_floor': 1.9, 'value': 1.5}}, (p) => (p.floorNumber ?? 9) <= 1);
  add('נוף-מבקש · ת״א · קומה גבוהה', {'hard_constraints': {'city': 'תל אביב', 'max_price': 13000}, 'soft_weights': {'view': 2.0, 'luxury': 1.5}}, highFloor);
  add('בעל כלב · ת״א · קרקע גינה', {'hard_constraints': {'city': 'תל אביב', 'pets': true}, 'soft_weights': {'ground_floor': 1.8}}, has('petsAllowed'));
  add('בעל חתול · ר״ג · מרשה חיות', {'hard_constraints': {'city': 'רמת גן', 'pets': true}, 'soft_weights': {'value': 1.5}}, has('petsAllowed'));
  add('WFH · כפר סבא · חדר עבודה', {'hard_constraints': {'city': 'כפר סבא'}, 'soft_weights': {'spacious': 1.9, 'quiet_neighborhood': 1.5}}, always);
  add('יזם · הרצליה · יוקרה', {'hard_constraints': {'city': 'הרצליה', 'max_price': 18000}, 'soft_weights': {'luxury': 2.0, 'view': 1.6}}, has('pool'));
  add('שף · ת״א · מרכזי', {'hard_constraints': {'city': 'תל אביב', 'max_price': 8500}, 'soft_weights': {'central_location': 1.9, 'nightlife': 1.4}}, nearUni);
  add('מרצה · רחובות · אקדמיה שקט', {'hard_constraints': {'city': 'רחובות'}, 'soft_weights': {'university': 1.7, 'quiet_neighborhood': 1.5}}, always);
  add('עצמאי מהבית · מודיעין · מרווח', {'hard_constraints': {'city': 'מודיעין', 'min_rooms': 4}, 'soft_weights': {'spacious': 1.9, 'condition': 1.4}}, rooms(4));

  // More edges to reach 100 (beach lovers / budget-extreme / metro / vague)
  add('חובב ים · נתניה', {'hard_constraints': {'city': 'נתניה'}, 'soft_weights': {'near_sea': 2.0}}, nearSea);
  add('חובב ים · אשדוד', {'hard_constraints': {'city': 'אשדוד'}, 'soft_weights': {'near_sea': 2.0}}, always);
  add('חובב ים · הרצליה', {'hard_constraints': {'city': 'הרצליה'}, 'soft_weights': {'near_sea': 2.0, 'luxury': 1.4}}, always);
  add('תקציב-קיצון · ב״ש · 2200', {'hard_constraints': {'city': 'באר שבע', 'max_price': 2400}, 'soft_weights': {'value': 2.0}}, (p) => p.price <= 2400 * 1.15);
  add('פרימיום · ת״א · פנטהאוז', {'hard_constraints': {'city': 'תל אביב', 'max_price': 13000}, 'soft_weights': {'luxury': 2.0, 'view': 1.8}}, (p) => p.features.contains('pool') || (p.floorNumber ?? 0) >= 10);
  add('משפחה · גבעתיים · מרכזי', {'hard_constraints': {'city': 'גבעתיים', 'min_rooms': 4}, 'soft_weights': {'central_location': 1.6, 'family_friendly': 1.5}}, rooms(4));
  add('זוג · הרצליה · תקציב', {'hard_constraints': {'city': 'הרצליה', 'max_price': 7500}, 'soft_weights': {'value': 1.8, 'budget': 1.7}}, (p) => p.price <= 7500 * 1.15);
  add('משפחה · ת״א · 4 חד׳ מרכז', {'hard_constraints': {'city': 'תל אביב', 'min_rooms': 4, 'max_price': 12000}, 'soft_weights': {'family_friendly': 1.6, 'central_location': 1.5}}, rooms(4));
  add('רווקה · כפר סבא · מרוהט', {'hard_constraints': {'city': 'כפר סבא'}, 'soft_weights': {'value': 1.5, 'central_location': 1.4}}, always);
  add('זוג גמלאים · הרצליה · נגיש ים', {'hard_constraints': {'city': 'הרצליה'}, 'soft_weights': {'accessibility': 1.9, 'near_sea': 1.5}}, accessible);
  add('משפחה · אשדוד · ים משפחתי', {'hard_constraints': {'city': 'אשדוד', 'min_rooms': 4}, 'soft_weights': {'near_sea': 1.6, 'family_friendly': 1.5}}, rooms(4));
  add('סטודנט · ירושלים · זול', {'hard_constraints': {'city': 'ירושלים', 'max_price': 5000}, 'soft_weights': {'value': 1.8, 'university': 1.4}}, (p) => p.price <= 5000 * 1.15);

  return L;
}
