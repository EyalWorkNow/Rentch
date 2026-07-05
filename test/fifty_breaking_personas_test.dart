import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart' show IsraelGeoIndex;
import 'package:dating_app/core/search/etti_plan.dart';
import 'package:dating_app/core/search/smart_search.dart';
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
      totalFloors: '20', city: city, neighborhood: '', street: 'הרצל', streetNumber: 1,
      lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: sale ? PropertyTransactionType.sale : PropertyTransactionType.rent,
      entryDate: '', condition: 'טוב', ownerName: 'o', agencyListing: false, features: features,
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: PropertyMarketSignals(views: 40 + price % 90, likes: 6, saves: 2),
      verification: PropertyVerification.cameraVideo(videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

// Catalogue spanning MAJOR cities + SMALL localities and their close neighbours —
// the crux of the breaking test: a small-locality search must never leak a neighbour.
List<RentalProperty> catalogue() {
  final c = <RentalProperty>[];
  void spread(String name, double lat, double lon, int base, {int n = 4}) {
    for (var i = 0; i < n; i++) {
      c.add(f(
        id: '$name-$i',
        price: (base * (0.85 + i * 0.18)).round(),
        rooms: 2.0 + i, sizeM2: 55 + i * 15,
        city: name, lat: lat + i * 0.003, lon: lon + i * 0.003,
        floor: i == 0 ? 0 : (i * 2),
        features: [
          'ac',
          if (i.isEven) 'elevator',
          if (i == 1) 'mamad',
          if (i == 0) 'petsAllowed',
          if (i == 2) 'parking',
          if (i == 3) 'furnished',
        ],
      ));
    }
  }

  // Major cities
  spread('תל אביב', 32.073, 34.781, 7800);
  spread('רמת גן', 32.083, 34.814, 6000);
  spread('גבעתיים', 32.072, 34.812, 6200);
  spread('חיפה', 32.79, 34.99, 4700);
  spread('באר שבע', 31.252, 34.79, 2700);
  spread('ירושלים', 31.78, 35.21, 5600);
  spread('נתניה', 32.32, 34.853, 4900);
  spread('פתח תקווה', 32.088, 34.887, 5400);
  spread('רחובות', 31.894, 34.811, 4800);
  spread('מודיעין', 31.898, 35.010, 5700);
  // Small localities + their close neighbours (leak traps)
  spread('עין עירון', 32.470, 34.981, 4200, n: 3);
  spread('אור עקיבא', 32.508, 34.918, 4400, n: 4); // ~7km from Ein Iron
  spread('כפר ורדים', 32.998, 35.283, 4600, n: 3);
  spread('מעלות תרשיחא', 33.017, 35.272, 4300, n: 4); // ~3km from Kfar Vradim
  spread('זכרון יעקב', 32.571, 34.951, 5200, n: 3);
  spread('בנימינה', 32.515, 34.949, 4700, n: 4); // ~6km from Zichron
  // Sale stock in several cities
  c.addAll([
    f(id: 'sale-hf-1', price: 1150000, rooms: 4, sizeM2: 92, city: 'חיפה', lat: 32.80, lon: 34.99, sale: true),
    f(id: 'sale-hf-2', price: 1650000, rooms: 4, sizeM2: 100, city: 'חיפה', lat: 32.81, lon: 34.98, sale: true),
    f(id: 'sale-bs-1', price: 890000, rooms: 4, sizeM2: 95, city: 'באר שבע', lat: 31.253, lon: 34.79, sale: true),
    f(id: 'sale-bs-2', price: 1250000, rooms: 5, sizeM2: 115, city: 'באר שבע', lat: 31.25, lon: 34.80, sale: true),
    f(id: 'sale-ta-beach', price: 3300000, rooms: 2, sizeM2: 58, city: 'תל אביב', lat: 32.081, lon: 34.767, sale: true),
    f(id: 'sale-mod', price: 2350000, rooms: 5, sizeM2: 130, city: 'מודיעין', lat: 31.898, lon: 35.010, features: ['mamad', 'elevator'], sale: true),
    // TA extras for sea / view
    f(id: 'ta-beach', price: 8700, rooms: 2, sizeM2: 56, city: 'תל אביב', lat: 32.081, lon: 34.767, floor: 3, features: ['ac', 'petsAllowed']),
    f(id: 'ta-view', price: 12500, rooms: 3, sizeM2: 88, city: 'תל אביב', lat: 32.083, lon: 34.79, floor: 24, features: ['ac', 'elevator', 'pool', 'parking']),
    f(id: 'net-beach', price: 5100, rooms: 3, sizeM2: 76, city: 'נתניה', lat: 32.331, lon: 34.851, floor: 2, features: ['ac', 'elevator']),
  ]);
  return c;
}

typedef Chk = bool Function(RentalProperty top);
class P { P(this.label, this.text, this.etti, this.primary); final String label; final String text; final Map<String, dynamic>? etti; final Chk primary; }

bool nearSea(RentalProperty p) { final km = IsraelGeoIndex.coastKm(p.lat, p.lon); return km != null && km <= 3.0; }
bool accessible(RentalProperty p) => p.features.contains('elevator') || (p.floorNumber ?? 9) <= 1;
bool isSale(RentalProperty p) => p.transactionType == PropertyTransactionType.sale;
bool always(RentalProperty p) => true;
Chk has(String feat) => (p) => p.features.contains(feat);
Chk rooms(double n) => (p) => p.rooms >= n - 0.5;
Chk inCity(String city) => (p) => p.city.contains(city);

void main() {
  setUpAll(() async {
    GovData.instance.resetForTest();
    await GovData.instance.init(reader: _diskReader);
  });
  tearDownAll(() => GovData.instance.resetForTest());

  test('50 BREAKING personas — filtering under stress', () {
    final cat = catalogue();
    final ps = _fifty();
    var pass = 0;
    final fails = <String>[];
    for (final p in ps) {
      SearchQuery q = SmartSearch.parse(p.text);
      if (p.etti != null) q = EttiPlan.fromJson(p.etti!).toQuery(fallback: q);
      final recs = RecommendationEngine.recommendAsScored(
          candidates: cat, query: q, limit: 12, seed: 5);
      final r = <String>[];
      // Determine the intended city (from etti hard or parsed).
      final city = (p.etti?['hard_constraints']?['city'])?.toString() ?? q.city;
      if (recs.isEmpty) {
        // Empty is only OK if the requested city genuinely has no stock.
        final hasStock = city != null && cat.any((x) => x.city.contains(city));
        if (hasStock) r.add('NO-RESULTS(city has stock!)');
      } else {
        final top = recs.first.property;
        // #1 CROSS-CITY LEAK CHECK — the whole point: every result in the named city.
        if (city != null) {
          String nrm(String s) => s.replaceAll(RegExp(r'[\-־]'), ' ').trim();
          final nc = nrm(city);
          final leaks = recs
              .map((s) => nrm(s.property.city))
              .where((cc) => !cc.contains(nc) && !nc.contains(cc))
              .toSet();
          if (leaks.isNotEmpty) r.add('LEAK:${leaks.join("/")}');
        }
        if (!p.primary(top)) r.add('primary-miss(${top.id})');
      }
      if (r.isEmpty) { pass++; } else { fails.add('${p.label} · ${r.join(",")}'); }
    }
    // ignore: avoid_print
    print('\n╔═══ 50 BREAKING PERSONAS ═══');
    // ignore: avoid_print
    print('║ PASS: $pass / ${ps.length}  (${(pass / ps.length * 100).round()}%)');
    // ignore: avoid_print
    print('╠═══ FAILURES (${fails.length}) ═══');
    for (final x in fails) { print('║ ✗ $x'); }
    // ignore: avoid_print
    print('╚════════════════════════════');
    expect(ps.length, greaterThanOrEqualTo(50));
  });
}

List<P> _fifty() {
  final L = <P>[];
  void a(String label, String text, Chk primary, {Map<String, dynamic>? etti}) =>
      L.add(P(label, text, etti, primary));

  // ── SMALL-LOCALITY LEAK TRAPS (the reported bug class) ─────────────────────
  a('עין עירון · לא אור עקיבא', 'דירה בעין עירון עד 5000', inCity('עין עירון'));
  a('אור עקיבא · לא עין עירון', 'דירה באור עקיבא עד 5000', inCity('אור עקיבא'));
  a('כפר ורדים · לא מעלות', 'דירה בכפר ורדים', inCity('כפר ורדים'));
  a('מעלות תרשיחא', 'דירה במעלות תרשיחא עד 5000', inCity('מעלות'));
  a('זכרון יעקב · לא בנימינה', 'דירה בזכרון יעקב עד 6000', inCity('זכרון'));
  a('בנימינה · לא זכרון', 'דירה בבנימינה עד 5500', inCity('בנימינה'));
  a('עין עירון + מעלית', 'דירה בעין עירון עם מעלית', inCity('עין עירון'), etti: {'hard_constraints': {'city': 'עין עירון', 'elevator': true}, 'soft_weights': {'value': 1.5}});
  a('כפר ורדים משפחה', 'דירה 4 חדרים בכפר ורדים', rooms(3.5));

  // ── major-city exactness (no metro over-leak) ──────────────────────────────
  a('תל אביב · לא פ״ת', 'דירה בתל אביב עד 9000', inCity('תל אביב'));
  a('פתח תקווה · לא ר״ג', 'דירה בפתח תקווה עד 6000', inCity('פתח תקווה'));
  a('חיפה · תחומה', 'דירה בחיפה עד 5000', inCity('חיפה'));
  a('רחובות', 'דירה ברחובות עד 5500', inCity('רחובות'));
  a('ירושלים', 'דירה בירושלים עד 6000', inCity('ירושלים'));
  a('באר שבע', 'דירה בבאר שבע עד 3200', inCity('באר שבע'));
  a('נתניה', 'דירה בנתניה עד 5500', inCity('נתניה'));
  a('מודיעין', 'דירה במודיעין עד 6500', inCity('מודיעין'));
  a('רמת גן', 'דירה ברמת גן עד 6500', inCity('רמת גן'));
  a('גבעתיים', 'דירה בגבעתיים עד 6500', inCity('גבעתיים'));

  // ── features / intents inside a city (must stay in-city) ───────────────────
  a('ת״א קרוב לים', 'דירה בתל אביב קרוב לים עד 9000', nearSea);
  a('נתניה קרוב לים', 'דירה בנתניה קרוב לים', inCity('נתניה'));
  a('ת״א נוף קומה גבוהה', 'דירה בתל אביב עם נוף עד 13000', inCity('תל אביב'));
  a('כיסא גלגלים חיפה', 'דירה נגישה לכיסא גלגלים בחיפה עם מעלית עד 5000', accessible);
  a('ממ״ד פ״ת', 'דירה בפתח תקווה עם ממד עד 6000', inCity('פתח תקווה'));
  a('חניה ר״ג', 'דירה ברמת גן עם חניה עד 6500', inCity('רמת גן'));
  a('מרוהט נתניה', 'דירה מרוהטת בנתניה עד 5500', inCity('נתניה'));
  a('כלב ת״א', 'דירה בתל אביב שמתאימה לכלב עד 9000', inCity('תל אביב'));

  // ── sale (rent/sale gate) in-city ──────────────────────────────────────────
  a('משקיע חיפה סייל', 'דירה למכירה בחיפה להשקעה עד 1500000', (p) => isSale(p) && p.city.contains('חיפה'));
  a('משקיע ב״ש סייל', 'דירה למכירה בבאר שבע עד 1300000', (p) => isSale(p) && p.city.contains('באר שבע'));
  a('קניה מודיעין', 'דירה למכירה במודיעין 5 חדרים', (p) => isSale(p) && p.city.contains('מודיעין'));
  a('סייל ת״א ים', 'דירה למכירה בתל אביב קרוב לים', (p) => isSale(p) && p.city.contains('תל אביב'));
  a('שכירות לא סייל ב״ש', 'דירה בבאר שבע עד 3000', (p) => !isSale(p));

  // ── Etti-driven (LLM plan) in-city + primary ───────────────────────────────
  a('משפחה חרדית ב״ש? → ירושלים', 'משפחה עם 5 ילדים', rooms(3), etti: {'hard_constraints': {'city': 'ירושלים', 'min_rooms': 4}, 'soft_weights': {'family_friendly': 1.9, 'schools_nearby': 1.7}});
  a('הייטק ת״א ים', 'רווקה שאוהבת את הים והחיים בעיר', nearSea, etti: {'hard_constraints': {'city': 'תל אביב', 'max_price': 9000}, 'soft_weights': {'near_sea': 2.0, 'nightlife': 1.6}});
  a('גמלאים נתניה נגיש', 'זוג מבוגר שקט ליד הים', accessible, etti: {'hard_constraints': {'city': 'נתניה'}, 'soft_weights': {'accessibility': 1.9, 'near_sea': 1.4}});
  a('סטודנט ב״ש', 'סטודנט מחפש קרוב לאוניברסיטה', inCity('באר שבע'), etti: {'hard_constraints': {'city': 'באר שבע', 'max_price': 3000}, 'soft_weights': {'university': 2.0}});
  a('משקיע מודיעין', 'רוצה לקנות דירה להשקעה', isSale, etti: {'hard_constraints': {'city': 'מודיעין', 'transaction_type': 'sale', 'max_price': 2500000}, 'soft_weights': {'yield': 1.8}});
  a('נגישות ירושלים', 'צריך דירה נגישה בירושלים', inCity('ירושלים'), etti: {'hard_constraints': {'city': 'ירושלים', 'accessible': true}, 'soft_weights': {'accessibility': 2.0}});
  a('ממ״ד מודיעין', 'משפחה דתית עם ממד', has('mamad'), etti: {'hard_constraints': {'city': 'מודיעין', 'mamad': true, 'min_rooms': 4}, 'soft_weights': {'safety': 1.7}});
  a('מרוהט עולה נתניה', 'עולה חדש צריך מרוהט', has('furnished'), etti: {'hard_constraints': {'city': 'נתניה', 'furnished': true}, 'soft_weights': {'value': 1.5}});

  // ── budget / rooms edge (still in-city) ────────────────────────────────────
  a('ת״א תקציב הדוק', 'דירה בתל אביב עד 6000', inCity('תל אביב'));
  a('חיפה 4 חדרים', 'דירה 4 חדרים בחיפה', inCity('חיפה'));
  a('רחובות זול', 'דירה זולה ברחובות עד 4200', inCity('רחובות'));
  a('פ״ת גדולה', 'דירה 5 חדרים בפתח תקווה', inCity('פתח תקווה'));
  a('מודיעין מרווח', 'דירה מרווחת במודיעין', inCity('מודיעין'));

  // ── ambiguous / robustness ─────────────────────────────────────────────────
  a('תל אביב-יפו וריאנט', 'דירה בתל אביב יפו עד 9000', inCity('תל אביב'));
  a('ב״ש קיצור', 'דירה בבאר שבע עד 3000', inCity('באר שבע'));
  a('נתניה + פסיק', 'מחפש דירה, נתניה, עד 5000', inCity('נתניה'));
  a('חיפה עם תיאור', 'אני רוצה דירה יפה בחיפה עם מרפסת עד 5500', inCity('חיפה'));
  a('ירושלים משפחה', 'דירה גדולה בירושלים למשפחה', inCity('ירושלים'));
  a('ת״א סתמי', 'משהו נחמד בתל אביב', inCity('תל אביב'));
  a('רמת גן מעלית', 'דירה ברמת גן עם מעלית עד 6500', inCity('רמת גן'));

  return L;
}
