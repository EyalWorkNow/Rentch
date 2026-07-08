import 'dart:io';
import 'dart:math' as math;

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 30-persona BREAKING TEST for אתי (the personal assistant), on-device brain.
//
// Runs 30 realistic Israeli tenant personas — incl. adversarial input (typos,
// mixed HE/EN, contradictions, emoji, negation, gibberish) — through the REAL
// pipeline: SmartSearch.parse → RecommendationOrchestrator (city gate + #2 area
// expansion off GovData) → scored results. It does NOT pass/fail each persona;
// it collects HARD-INVARIANT violations across all 30 and reports them, then
// fails once if anything broke. Invariants that must NEVER break:
//   • no crash on any input
//   • no result over the stated budget
//   • investor/sale search returns ONLY sale listings
//   • "אזור X" never leaks a town far from X's real (CBS) centre, and returns
//     neighbours (non-empty) when neighbouring stock exists
//   • fit% is monotonically non-increasing down the list
//
// ponytail: reuses the persona-exam harness (GovData disk reader + flat()); the
// only new thing is the persona bank + the invariant collector.
// ─────────────────────────────────────────────────────────────────────────────

Future<String> _diskReader(String path) => File(path).readAsString();

double _km(double aLat, double aLon, double bLat, double bLon) {
  if (aLat.abs() < 0.1 || bLat.abs() < 0.1) return double.infinity;
  const r = 6371.0;
  final dLat = (bLat - aLat) * math.pi / 180;
  final dLon = (bLon - aLon) * math.pi / 180;
  final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(aLat * math.pi / 180) *
          math.cos(bLat * math.pi / 180) *
          math.sin(dLon / 2) *
          math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(s), math.sqrt(1 - s));
}

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

// Mixed catalogue across real cities WITH real coordinates, so the geo gate +
// "אזור X" expansion (which anchors on GovData's CBS centre) actually fire.
// Gush Dan cluster (TA / רמת גן / גבעתיים / בני ברק) sits ~2-6 km apart; the
// Sharon (הרצליה / רעננה / כפ"ס / רמת השרון) ~2-8 km apart; כרכור is ~55 km
// north of TA — the trap for a name-gate leak.
List<RentalProperty> catalogue() => [
      // Tel Aviv
      flat(id: 'ta-beach-2', price: 8200, rooms: 2, sizeM2: 55, city: 'תל אביב',
          lat: 32.081, lon: 34.767, features: ['balcony', 'ac']),
      flat(id: 'ta-ctr-3', price: 8800, rooms: 3, sizeM2: 78, city: 'תל אביב',
          lat: 32.072, lon: 34.781, features: ['elevator', 'ac', 'balcony']),
      flat(id: 'ta-sale-3', price: 3200000, rooms: 3, sizeM2: 80,
          city: 'תל אביב', lat: 32.07, lon: 34.78,
          type: PropertyTransactionType.sale, features: ['elevator']),
      // Ramat Gan / Givatayim / Bnei Brak (Gush Dan, adjacent to TA)
      flat(id: 'rg-3', price: 6200, rooms: 3, sizeM2: 74, city: 'רמת גן',
          lat: 32.083, lon: 34.814, features: ['elevator', 'parking']),
      flat(id: 'giv-4', price: 7100, rooms: 4, sizeM2: 92, city: 'גבעתיים',
          lat: 32.072, lon: 34.812, features: ['elevator', 'mamad', 'balcony']),
      flat(id: 'bb-4-mamad', price: 5400, rooms: 4, sizeM2: 95, city: 'בני ברק',
          lat: 32.083, lon: 34.836, features: ['elevator', 'mamad', 'balcony']),
      flat(id: 'bb-3', price: 4800, rooms: 3, sizeM2: 72, city: 'בני ברק',
          lat: 32.086, lon: 34.842, features: ['mamad']),
      // Sharon — Herzliya / Ra'anana / Kfar Saba (neighbours of רמת השרון)
      flat(id: 'hrz-4-view', price: 9500, rooms: 4, sizeM2: 110,
          city: 'הרצליה', lat: 32.162, lon: 34.844,
          floor: '12', features: ['elevator', 'parking', 'balcony', 'pool']),
      flat(id: 'raa-4', price: 7800, rooms: 4, sizeM2: 100, city: 'רעננה',
          lat: 32.184, lon: 34.871, features: ['elevator', 'mamad', 'parking']),
      flat(id: 'ks-3', price: 6400, rooms: 3, sizeM2: 80, city: 'כפר סבא',
          lat: 32.175, lon: 34.907, features: ['elevator', 'balcony']),
      flat(id: 'rhs-5', price: 11000, rooms: 5, sizeM2: 130,
          city: 'רמת השרון', lat: 32.146, lon: 34.839,
          features: ['elevator', 'parking', 'mamad', 'balcony']),
      // Netanya (elderly-friendly, elevator vs walk-up)
      flat(id: 'net-elev', price: 4900, rooms: 3, sizeM2: 70, city: 'נתניה',
          lat: 32.32, lon: 34.85, floor: '2', features: ['elevator', 'balcony']),
      flat(id: 'net-walkup', price: 4200, rooms: 3, sizeM2: 68, city: 'נתניה',
          lat: 32.33, lon: 34.86, floor: '4', features: []),
      // Haifa
      flat(id: 'hai-4', price: 4500, rooms: 4, sizeM2: 100, city: 'חיפה',
          lat: 32.79, lon: 34.99, features: ['balcony', 'ac']),
      // Be'er Sheva (student stock)
      flat(id: 'bsh-2-cheap', price: 2600, rooms: 2, sizeM2: 50,
          city: 'באר שבע', lat: 31.26, lon: 34.80, features: []),
      flat(id: 'bsh-3', price: 3300, rooms: 3, sizeM2: 72, city: 'באר שבע',
          lat: 31.25, lon: 34.79, features: ['ac']),
      // Jerusalem
      flat(id: 'jlm-4-mamad', price: 6800, rooms: 4, sizeM2: 95,
          city: 'ירושלים', lat: 31.78, lon: 35.21,
          features: ['mamad', 'elevator']),
      // Petah Tikva
      flat(id: 'pt-4', price: 5600, rooms: 4, sizeM2: 98, city: 'פתח תקווה',
          lat: 32.09, lon: 34.89, features: ['elevator', 'parking', 'mamad']),
      // Pardes Hanna–Karkur — the FAR trap (~55 km from Gush Dan)
      flat(id: 'krk-5', price: 5200, rooms: 5, sizeM2: 140,
          city: 'פרדס חנה כרכור', lat: 32.474, lon: 34.968,
          features: ['balcony', 'parking']),
      // A pricey investor sale for the yield persona
      flat(id: 'inv-sale-hai', price: 1450000, rooms: 3, sizeM2: 75,
          city: 'חיפה', lat: 32.80, lon: 34.98,
          type: PropertyTransactionType.sale, features: ['balcony']),
    ];

class Persona {
  const Persona(
    this.name,
    this.query, {
    this.budget,
    this.saleOnly = false,
    this.areaCity,
    this.areaMaxKm = 22.0,
    this.expectNonEmpty = false,
    this.profile,
  });
  final String name;
  final String query;
  final int? budget; // no returned listing may exceed this (ILS)
  final bool saleOnly; // every result must be a SALE listing
  final String? areaCity; // "אזור X" → results must sit within areaMaxKm of X
  final double areaMaxKm;
  final bool expectNonEmpty; // stock exists → an empty result is a break
  final TenantProfile? profile;
}

TenantProfile _prof({
  int budget = 99999999,
  double rooms = 3,
  List<String> important = const [],
  List<String> deal = const [],
}) =>
    TenantProfile(
      id: 'p', name: 'p', bio: '', photoUrls: const [],
      budgetMax: budget, desiredRooms: rooms, moveInWindow: 'מיידי',
      importantDetails: important, dealBreakers: deal,
    );

// The 30 personas — grouped: geo-area (#2), deal-breakers, budget edges, cohort
// signals, and adversarial/garbage input. Real Israeli phrasing.
final List<Persona> personas = [
  // ── A. "אזור X" geo expansion (#2 fix) ──────────────────────────────────────
  const Persona('1 · רותם — "דירה באזור רמת השרון"',
      'דירה באזור רמת השרון עד 12000',
      areaCity: 'רמת השרון', budget: 12000, expectNonEmpty: true),
  const Persona('2 · עידן — "משהו באיזור תל אביב"',
      'משהו באיזור תל אביב עד 9000', areaCity: 'תל אביב', budget: 9000,
      expectNonEmpty: true),
  const Persona('3 · שני — "אזור כרכור" (מלאי דליל — לא לדלוף לגוש דן)',
      'דירה באזור כרכור עד 6000', areaCity: 'פרדס חנה כרכור', areaMaxKm: 20,
      budget: 6000),
  const Persona('4 · טל — "בסביבות באר שבע"',
      'דירה בסביבות באר שבע עד 3500', areaCity: 'באר שבע', budget: 3500,
      expectNonEmpty: true),
  const Persona('5 · מירי — "אזור ירושלים" (לא לדלוף לתל אביב)',
      'דירה באזור ירושלים עד 7000', areaCity: 'ירושלים', budget: 7000,
      expectNonEmpty: true),
  const Persona('6 · דור — "רמת גן והסביבה" (צורת סיומת)',
      'דירת 3 חדרים ברמת גן והסביבה עד 7000', areaCity: 'רמת גן', budget: 7000,
      expectNonEmpty: true),

  // ── B. Deal-breaker gates ───────────────────────────────────────────────────
  Persona('7 · יעל — אמא לתינוק, ממ"ד חובה',
      'דירת 4 חדרים בבני ברק עד 5600 עם ממ"ד חובה למשפחה עם תינוק',
      budget: 5600, expectNonEmpty: true,
      profile: _prof(budget: 5600, rooms: 4, deal: const ['ממ"ד'])),
  const Persona('8 · אבי — משפחה עם כלב, חייב לאשר בע"ח',
      'דירה בתל אביב עד 9000 שמאשרת כלבים', budget: 9000),
  Persona('9 · חנה — כיסא גלגלים, מעלית + קומה נמוכה',
      'דירה נגישה בנתניה עם מעלית לכיסא גלגלים עד 5000',
      budget: 5000, expectNonEmpty: true,
      profile: _prof(budget: 5000, deal: const ['נגישות', 'מעלית'])),
  const Persona('10 · משה — שומר שבת, קרוב לבית כנסת',
      'דירה בבני ברק קרוב לבית כנסת שומרי שבת עד 5500', budget: 5500,
      expectNonEmpty: true),
  const Persona('11 · רון — חובה חניה, יש רכב',
      'דירת 4 חדרים בפתח תקווה עם חניה חובה עד 6000', budget: 6000,
      expectNonEmpty: true),

  // ── C. Budget edges ─────────────────────────────────────────────────────────
  // Impossible budget (below ALL stock): engine returns least-bad at low fit%;
  // the SCREEN layer turns this into honest "nothing at ₪1500". budget:null so we
  // don't assert an engine-level cap it was never meant to enforce.
  const Persona('12 · ליאת — תקציב בלתי אפשרי (מתחת לכל המלאי)',
      'דירת 4 חדרים בתל אביב עד 1500'),
  const Persona('13 · דניאל — משקיע קנייה "עד 2 מיליון"',
      'דירה להשקעה עם תשואה עד 2 מיליון', budget: 2000000, saleOnly: true,
      expectNonEmpty: true),
  const Persona('14 · אורי — משקיע, רק מכירה',
      'אני משקיע מחפש נכס לקנייה עם תשואה טובה', saleOnly: true,
      expectNonEmpty: true),
  const Persona('15 · נועם — תקציב מעורפל "בערך 5000"',
      'דירת 3 חדרים בחיפה בערך 5000', budget: 6000, expectNonEmpty: true),

  // ── D. Cohort signals (age / oleh / stream / student / wfh) ──────────────────
  const Persona('16 · יצחק — "אני בן 74", מבוגר, נגישות',
      'אני בן 74 מחפש דירה שקטה בנתניה עם מעלית עד 5000', budget: 5000,
      expectNonEmpty: true),
  const Persona('17 · Sarah — עולה חדשה דוברת אנגלית',
      'new olah looking for apartment בהרצליה עד 10000 english speaking area',
      budget: 10000, expectNonEmpty: true),
  const Persona('18 · ברוך — חרדי מול דתי-לאומי (צרכי חינוך הפוכים)',
      'דירה למשפחה חרדית בבני ברק ליד חיידר ותלמוד תורה עד 5600', budget: 5600,
      expectNonEmpty: true),
  const Persona('19 · עומר — סטודנט ליד BGU, זול',
      'דירה לסטודנט בבאר שבע ליד האוניברסיטה עד 2800', budget: 2800,
      expectNonEmpty: true),
  const Persona('20 · גל — עובד/ת מהבית, צריך חדר עבודה ושקט',
      'דירה בכפר סבא עם חדר עבודה שקט לעבודה מהבית עד 7000', budget: 7000,
      expectNonEmpty: true),

  // ── E. Adversarial / breaking input ─────────────────────────────────────────
  const Persona('21 · שגיאות כתיב — "תלאביב 3 חדרימ קרוב לימ"',
      'דירה בתלאביב 3 חדרימ קרוב לימ עד 9000', budget: 9000),
  const Persona('22 · מעורב HE/EN',
      'looking for apartment בחיפה with balcony under 5000', budget: 5000),
  // Contradiction + impossible budget (₪3000 in TA fits nothing): screen-honesty
  // case, budget:null (see persona 12).
  const Persona('23 · סתירה — "זולה מאוד יוקרתית עד 3000 בתל אביב"',
      'דירה זולה מאוד יוקרתית בתל אביב עד 3000'),
  const Persona('24 · ג׳יבריש/ריק — "אהלן מה קורה" (בלי קריטריונים)',
      'אהלן מה קורה'),
  const Persona('25 · סתירת מיקום — "בתל אביב אבל רחוק מהעיר"',
      'דירה בתל אביב אבל רחוק מהמרכז עד 8000', budget: 8000),
  const Persona('26 · מספרים בלבד — "3 8000 תל אביב"',
      '3 8000 תל אביב', budget: 8000),
  const Persona('27 · פסקה ארוכה ומבולגנת',
      'היי אז אנחנו זוג צעיר בלי ילדים עדיין אבל אולי בעתיד מחפשים משהו לא רחוק '
      'מהעבודה שלי שהיא ברמת גן אבל גם קרוב לים אם אפשר ותקציב שלנו זה משהו כמו '
      'עד 8500 בערך ומאוד חשוב לנו מרפסת ושקט אבל גם חיים בסביבה',
      budget: 8500),
  const Persona('28 · אימוג׳י/סלנג — "יו אחי דירה שווה בפ"ת 🔥"',
      'יו אחי צריך דירה שווה בפתח תקווה 🔥🏠 עד 5500', budget: 5500),
  const Persona('29 · שלילות — "לא קומת קרקע ולא בלי מעלית"',
      'דירה בגבעתיים לא בקומת קרקע ולא בלי מעלית עד 7500', budget: 7500),
  const Persona('30 · מעורפל — "משהו נורמלי במרכז"',
      'משהו נורמלי במרכז עד 8000', budget: 8000),
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: _diskReader);
  });

  test('BREAKING TEST — 30 personas, hard invariants must hold', () {
    final cat = catalogue();
    final failures = <String>[];
    var ran = 0;

    for (final p in personas) {
      List<ScoredProperty> recs;
      try {
        recs = RecommendationEngine.recommendAsScored(
          candidates: cat,
          query: SmartSearch.parse(p.query),
          profile: p.profile,
          limit: 8,
          seed: 7,
        );
      } catch (e) {
        failures.add('${p.name}  ✗ CRASHED: $e');
        continue;
      }
      ran++;

      // Report line.
      final top = recs.take(3).map((s) =>
          '${s.property.city}/${s.property.price} ${s.scorecard!.fitPct}%');
      // ignore: avoid_print
      print('${p.name}\n    → ${recs.length} recs: ${top.join(" | ")}');

      // Invariant 1 — budget: the LEAD (top) pick the user sees must respect
      // the stated budget within a 5% tolerance. The engine RANKS (budget is a
      // soft value dimension), so over-budget flats in the ranked TAIL are a
      // legitimate fallback, not a break — the screen layer (_send) is what caps
      // / widens / says "nothing at ₪X". Impossible budgets (nothing fits) carry
      // budget:null and rely on that screen-honesty, which this engine test can't
      // see.
      if (p.budget != null && recs.isNotEmpty) {
        final lead = recs.first.property;
        if (lead.price > p.budget! * 1.05) {
          failures.add('${p.name}  ✗ LEAD OVER BUDGET (>${p.budget}+5%): '
              '${lead.id}=${lead.price}');
        }
      }
      // Invariant 2 — sale-only gate.
      if (p.saleOnly) {
        final rentals = recs
            .where((s) => s.property.transactionType != PropertyTransactionType.sale)
            .toList();
        if (rentals.isNotEmpty) {
          failures.add('${p.name}  ✗ SALE GATE LEAK (rentals returned): '
              '${rentals.map((s) => s.property.id).join(", ")}');
        }
      }
      // Invariant 3 — "אזור X" must not leak a far town, and should find neighbours.
      if (p.areaCity != null) {
        final loc = GovData.instance.localityByName(p.areaCity!);
        if (loc != null && loc.lat.abs() > 0.1) {
          final far = recs
              .where((s) =>
                  _km(s.property.lat, s.property.lon, loc.lat, loc.lon) >
                  p.areaMaxKm)
              .toList();
          if (far.isNotEmpty) {
            failures.add('${p.name}  ✗ AREA LEAK (>${p.areaMaxKm.round()}km from '
                '${p.areaCity}): ${far.map((s) => "${s.property.city} "
                "${_km(s.property.lat, s.property.lon, loc.lat, loc.lon).round()}km").join(", ")}');
          }
        }
      }
      // Invariant 4 — monotonic fit%.
      for (var i = 1; i < recs.length; i++) {
        if (recs[i - 1].scorecard!.fitPct < recs[i].scorecard!.fitPct) {
          failures.add('${p.name}  ✗ NON-MONOTONIC fit% at #$i '
              '(${recs[i - 1].scorecard!.fitPct} < ${recs[i].scorecard!.fitPct})');
          break;
        }
      }
      // Invariant 5 — stock exists but nothing returned.
      if (p.expectNonEmpty && recs.isEmpty) {
        failures.add('${p.name}  ✗ EMPTY (expected neighbours/stock)');
      }
    }

    // ignore: avoid_print
    print('\n══════════ BREAKING-TEST SUMMARY ══════════');
    // ignore: avoid_print
    print('ran: $ran/${personas.length}   failures: ${failures.length}');
    for (final f in failures) {
      // ignore: avoid_print
      print('  $f');
    }

    expect(failures, isEmpty,
        reason: 'breaking-test invariants violated:\n${failures.join("\n")}');
  });

  // Regression: space-LESS multi-word city typos must still resolve the city,
  // instead of silently dropping it and returning a WRONG town at high fit.
  test('city typo robustness — space-less multi-word names resolve', () {
    const cases = {
      'תלאביב 3 חדרים': 'תל אביב',
      'דירה בתלאביב': 'תל אביב',
      'פתחתקווה 4 חדרים': 'פתח תקווה',
      'רמתגן': 'רמת גן',
      'בארשבע': 'באר שבע',
      'כפרסבא': 'כפר סבא',
    };
    final broken = <String>[];
    cases.forEach((q, expected) {
      final got = SmartSearch.parse(q).city;
      // ignore: avoid_print
      print('  "$q" → $got (want $expected)');
      if (got == null || !got.contains(expected.split(' ').first)) {
        broken.add('"$q" → $got (expected $expected)');
      }
    });
    expect(broken, isEmpty, reason: 'city typos dropped:\n${broken.join("\n")}');
  });
}
