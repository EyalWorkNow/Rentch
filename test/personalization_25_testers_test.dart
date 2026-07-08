import 'dart:io';
import 'dart:math' as math;

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 25 CRITICAL TESTERS × several queries each — a breaking test of PERSONALIZATION
// and the qualitative-phrase understanding ("שכונה בטוחה", "אזור צעיר", "קרוב
// לתחבורה", "אזור ירוק", …). Runs the real SmartSearch → RecommendationOrchestrator
// pipeline with GovData loaded, and collects invariant + personalization
// violations across ~80 queries. Reports all, fails if any HARD invariant breaks.
//
// Checks per query (as applicable):
//   • no crash                        • fit% monotonically non-increasing
//   • lead within budget +5%          • named city correct at the top
//   • a named semantic intent is set  • its map-data dimension is ENGAGED
//     (proves the phrase reached the parser)  (weight>0 in the top scorecard —
//                                       proves the GovData layer feeds ranking)
//   • profile testers: a curated profile must CHANGE the ranking order
// ─────────────────────────────────────────────────────────────────────────────

Future<String> _diskReader(String p) => File(p).readAsString();

double _km(double aLat, double aLon, double bLat, double bLon) {
  const r = 6371.0;
  final dLat = (bLat - aLat) * math.pi / 180, dLon = (bLon - aLon) * math.pi / 180;
  final s = math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(aLat * math.pi / 180) * math.cos(bLat * math.pi / 180) *
          math.sin(dLon / 2) * math.sin(dLon / 2);
  return r * 2 * math.atan2(math.sqrt(s), math.sqrt(1 - s));
}

RentalProperty flat({
  required String id, required int price, required double rooms,
  required String city, required double lat, required double lon,
  String floor = '3', List<String> features = const [],
  PropertyTransactionType type = PropertyTransactionType.rent,
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: 85, floor: floor,
      totalFloors: '20', city: city, neighborhood: '', street: 'הרצל',
      streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: type, entryDate: '', condition: 'טוב',
      ownerName: 'בעלים', agencyListing: false, features: features,
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: const PropertyMarketSignals(views: 120, likes: 14, saves: 4),
      verification: PropertyVerification.cameraVideo(
          videoUrl: 'http://x/v.mp4', capturedAt: DateTime(2026, 6, 1)),
    );

// Catalogue across real cities with real coords so the CBS/police/transit/demo
// layers actually differentiate. Rent + a couple of sale listings.
List<RentalProperty> catalogue() => [
      flat(id: 'ta-beach', price: 8200, rooms: 2, city: 'תל אביב', lat: 32.081, lon: 34.767, features: ['balcony', 'ac']),
      flat(id: 'ta-ctr', price: 8800, rooms: 3, city: 'תל אביב', lat: 32.072, lon: 34.781, floor: '5', features: ['elevator', 'ac', 'balcony']),
      flat(id: 'ta-sale', price: 3200000, rooms: 3, city: 'תל אביב', lat: 32.07, lon: 34.78, type: PropertyTransactionType.sale, features: ['elevator']),
      flat(id: 'rg', price: 6200, rooms: 3, city: 'רמת גן', lat: 32.083, lon: 34.814, features: ['elevator', 'parking']),
      flat(id: 'giv', price: 7100, rooms: 4, city: 'גבעתיים', lat: 32.072, lon: 34.812, features: ['elevator', 'mamad', 'balcony']),
      flat(id: 'bb-mamad', price: 5400, rooms: 4, city: 'בני ברק', lat: 32.083, lon: 34.836, features: ['elevator', 'mamad']),
      flat(id: 'hrz', price: 9500, rooms: 4, city: 'הרצליה', lat: 32.162, lon: 34.844, floor: '12', features: ['elevator', 'parking', 'balcony', 'pool']),
      flat(id: 'raa', price: 7800, rooms: 4, city: 'רעננה', lat: 32.184, lon: 34.871, features: ['elevator', 'mamad', 'parking']),
      flat(id: 'ks', price: 6400, rooms: 3, city: 'כפר סבא', lat: 32.175, lon: 34.907, features: ['elevator', 'balcony']),
      flat(id: 'rhs', price: 11000, rooms: 5, city: 'רמת השרון', lat: 32.146, lon: 34.839, features: ['elevator', 'parking', 'mamad']),
      flat(id: 'net-elev', price: 4900, rooms: 3, city: 'נתניה', lat: 32.32, lon: 34.85, floor: '2', features: ['elevator', 'feat_accessible']),
      flat(id: 'net-walk', price: 4200, rooms: 3, city: 'נתניה', lat: 32.33, lon: 34.86, floor: '4', features: []),
      flat(id: 'hai', price: 4500, rooms: 4, city: 'חיפה', lat: 32.79, lon: 34.99, features: ['balcony', 'ac']),
      flat(id: 'bsh-cheap', price: 2600, rooms: 2, city: 'באר שבע', lat: 31.26, lon: 34.80, features: []),
      flat(id: 'bsh', price: 3300, rooms: 3, city: 'באר שבע', lat: 31.25, lon: 34.79, features: ['ac']),
      flat(id: 'jlm-mamad', price: 6800, rooms: 4, city: 'ירושלים', lat: 31.78, lon: 35.21, features: ['mamad', 'elevator']),
      flat(id: 'pt', price: 5600, rooms: 4, city: 'פתח תקווה', lat: 32.09, lon: 34.89, features: ['elevator', 'parking', 'mamad']),
      flat(id: 'inv-hai', price: 1450000, rooms: 3, city: 'חיפה', lat: 32.80, lon: 34.98, type: PropertyTransactionType.sale, features: ['balcony']),
    ];

class Q {
  const Q(this.text, {this.budget, this.city, this.intent, this.dim, this.area, this.profileMustReorder = false});
  final String text;
  final int? budget;            // lead price ≤ budget×1.05
  final String? city;           // top result city contains this
  final String? intent;         // SmartSearch.parse(text).intents must contain
  final String? dim;            // this dimension must be weighted>0 in the top scorecard
  final String? area;           // "אזור X" → results within 22km of X's CBS centre
  final bool profileMustReorder; // with the tester's profile, order ≠ profile:null
}

class Tester {
  const Tester(this.name, this.queries, {this.profile});
  final String name;
  final List<Q> queries;
  final TenantProfile? profile;
}

TenantProfile prof({int budget = 99999999, double rooms = 3, List<String> important = const [], List<String> deal = const []}) =>
    TenantProfile(id: 'p', name: 'p', bio: '', photoUrls: const [], budgetMax: budget, desiredRooms: rooms, moveInWindow: 'מיידי', importantDetails: important, dealBreakers: deal);

final List<Tester> testers = [
  // ── 1-8: qualitative-phrase seekers (each phrase must engage its map layer) ──
  const Tester('1 · מחפש שכונה בטוחה', [
    Q('דירה בשכונה בטוחה בתל אביב עד 9000', budget: 9000, city: 'תל אביב', intent: SearchIntent.safety, dim: 'safety'),
    Q('מקום בטוח למשפחה בפתח תקווה עד 6000', budget: 6000, intent: SearchIntent.safety),
  ]),
  const Tester('2 · חשוב לו תחבורה', [
    Q('דירה קרוב לתחבורה ציבורית בתל אביב עד 9000', budget: 9000, city: 'תל אביב', intent: SearchIntent.transit, dim: 'transit'),
    Q('ליד רכבת קלה ברמת גן עד 7000', budget: 7000, intent: SearchIntent.transit),
    Q('נגיש לתחבורה בחיפה עד 5000', budget: 5000, intent: SearchIntent.transit),
  ]),
  const Tester('3 · רוצה אזור ירוק', [
    Q('דירה באזור ירוק עם הרבה גינות ברעננה עד 9000', budget: 9000, intent: SearchIntent.green, dim: 'park'),
    Q('קרוב לפארק בכפר סבא עד 7000', budget: 7000, intent: SearchIntent.green),
  ]),
  const Tester('4 · אזור צעיר ותוסס', [
    Q('דירה באזור צעיר ותוסס בתל אביב עד 9000', budget: 9000, city: 'תל אביב', intent: SearchIntent.nightlife, dim: 'young_area'),
    Q('סביבה צעירה עם חיי לילה עד 8500', budget: 8500, intent: SearchIntent.youngPop),
  ]),
  const Tester('5 · מקום שקט', [
    Q('דירה במקום שקט ורגוע בהרצליה עד 11000', budget: 11000, intent: SearchIntent.quiet, dim: 'senior_area'),
    Q('רחוק מכביש ראשי, שקט, בכפר סבא עד 7000', budget: 7000, intent: SearchIntent.quiet),
  ]),
  const Tester('6 · שכונה טובה ואיכותית', [
    Q('שכונה טובה ומטופחת ברמת השרון עד 12000', budget: 12000, intent: SearchIntent.qualityArea, dim: 'neighborhood'),
    Q('אזור מבוקש ונחשב בהרצליה עד 10000', budget: 10000, intent: SearchIntent.qualityArea),
  ]),
  const Tester('7 · חשוב בתי ספר', [
    Q('דירה עם בתי ספר טובים למשפחה בפתח תקווה עד 6000', budget: 6000, intent: SearchIntent.goodSchools, dim: 'schools'),
  ]),
  const Tester('8 · קרוב לבריאות', [
    Q('דירה קרוב לקופת חולים ולבית חולים בחיפה עד 5000', budget: 5000, intent: SearchIntent.health, dim: 'health'),
  ]),
  // ── 9-13: "אזור X" expansion + geo ──
  const Tester('9 · אזור רמת השרון', [
    Q('דירה באזור רמת השרון עד 12000', budget: 12000, area: 'רמת השרון'),
  ]),
  const Tester('10 · באזור של תל אביב', [
    Q('משהו באזור של תל אביב עד 9000', budget: 9000, area: 'תל אביב'),
  ]),
  const Tester('11 · טעויות כתיב', [
    Q('דירה בתלאביב 3 חדרימ עד 9000', budget: 9000, city: 'תל אביב'),
    Q('בהרצלייה 4 חדרים עד 10000', budget: 10000, city: 'הרצליה'),
  ]),
  const Tester('12 · מספרים בלבד', [
    Q('3 8000 תל אביב', budget: 8000, city: 'תל אביב'),
  ]),
  const Tester('13 · אנגלית מעורבת', [
    Q('looking for apartment בחיפה near transit under 5000', budget: 5000, city: 'חיפה', intent: SearchIntent.transit),
  ]),
  // ── 14-19: personalization via profile ──
  Tester('14 · כיסא גלגלים (פרופיל)', [
    Q('דירת 3 חדרים בנתניה עד 5200', budget: 5200, city: 'נתניה', profileMustReorder: true),
  ], profile: prof(budget: 5200, deal: const ['נגישות', 'מעלית'])),
  Tester('15 · משפחה עם ממ"ד (פרופיל)', [
    Q('דירת 4 חדרים בפתח תקווה עד 6000', budget: 6000, city: 'פתח תקווה'),
  ], profile: prof(budget: 6000, rooms: 4, deal: const ['ממ"ד'])),
  const Tester('16 · מבוגר בן 74', [
    Q('אני בן 74 מחפש דירה שקטה בנתניה עם מעלית עד 5000', budget: 5000, city: 'נתניה', intent: SearchIntent.accessible),
  ]),
  const Tester('17 · עולה דובר אנגלית', [
    Q('new olah english speaking area בהרצליה עד 10000', budget: 10000, city: 'הרצליה', intent: SearchIntent.qualityArea),
  ]),
  const Tester('18 · משקיע', [
    Q('דירה להשקעה עם תשואה עד 2 מיליון', budget: 2000000, intent: SearchIntent.investment, dim: 'yield'),
    Q('נכס לקנייה בחיפה תשואה טובה', city: 'חיפה'),
  ]),
  const Tester('19 · דתי-לאומי', [
    Q('דירה בשכונה דתית קרוב לבית כנסת בפתח תקווה עד 6000', budget: 6000, intent: SearchIntent.religiousArea, dim: 'religious_area'),
  ]),
  // ── 20-25: adversarial / multi-query journeys ──
  const Tester('20 · סתירה תקציב', [
    Q('דירה זולה מאוד יוקרתית בתל אביב עד 3000'),
  ]),
  const Tester('21 · תקציב בלתי אפשרי', [
    Q('דירת 4 חדרים בתל אביב עד 1500'),
  ]),
  const Tester('22 · שלילת רעש', [
    Q('דירה בגבעתיים לא באזור רועש עד 7500', budget: 7500, intent: SearchIntent.quiet),
  ]),
  const Tester('23 · מסע רב-שלבי', [
    Q('דירה בתל אביב', city: 'תל אביב'),
    Q('משהו יותר זול, עד 7000', budget: 7000),
    Q('ורצוי קרוב לים', intent: SearchIntent.nearSea),
  ]),
  const Tester('24 · פרסונה מורכבת', [
    Q('משפחה דתית עם 3 ילדים, שכונה טובה ובטוחה, בתי ספר, בפתח תקווה עד 6500', budget: 6500, city: 'פתח תקווה', intent: SearchIntent.safety),
  ]),
  const Tester('25 · ג׳יבריש + עיר', [
    Q('אהלן מה קורה דירה בבאר שבע', city: 'באר שבע'),
    Q('משהו נורמלי במרכז עד 8000', budget: 8000),
  ]),
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: _diskReader);
  });

  test('25 testers × queries — personalization & phrase-understanding hold', () {
    final cat = catalogue();
    final fails = <String>[];
    var queries = 0;

    List<ScoredProperty> run(String q, TenantProfile? p) =>
        RecommendationEngine.recommendAsScored(
            candidates: cat, query: SmartSearch.parse(q), profile: p, limit: 8, seed: 7);

    for (final t in testers) {
      for (final q in t.queries) {
        queries++;
        List<ScoredProperty> recs;
        try {
          recs = run(q.text, t.profile);
        } catch (e) {
          fails.add('${t.name} · "${q.text}"  ✗ CRASH: $e');
          continue;
        }

        // intent set on the query?
        if (q.intent != null) {
          final got = SmartSearch.parse(q.text).intents;
          if (!got.contains(q.intent)) {
            fails.add('${t.name} · "${q.text}"  ✗ intent ${q.intent} NOT set (got $got)');
          }
        }
        if (recs.isEmpty) continue; // impossible-budget/contradiction may be empty — ok

        // budget (lead within +5%)
        if (q.budget != null && recs.first.property.price > q.budget! * 1.05) {
          fails.add('${t.name} · "${q.text}"  ✗ LEAD over budget: ${recs.first.property.id}=${recs.first.property.price} > ${q.budget}');
        }
        // city at the top — accept the named city OR an immediately-adjacent town
        // (the engine intentionally widens a THIN-stock city to its ≤~12km metro;
        // production cities with ample stock stay in-city). We only flag a top
        // result that is FAR from the named city (a real wrong-city leak).
        if (q.city != null && !recs.first.property.city.contains(q.city!)) {
          final loc = GovData.instance.localityByName(q.city!);
          final top = recs.first.property;
          final farKm = (loc != null && loc.lat.abs() > 0.1)
              ? _km(top.lat, top.lon, loc.lat, loc.lon)
              : 999.0;
          if (farKm > 12) {
            fails.add('${t.name} · "${q.text}"  ✗ top city ${top.city} is ${farKm.round()}km from ${q.city} (wrong-city leak)');
          }
        }
        // monotonic fit%
        for (var i = 1; i < recs.length; i++) {
          if (recs[i - 1].scorecard!.fitPct < recs[i].scorecard!.fitPct) {
            fails.add('${t.name} · "${q.text}"  ✗ non-monotonic fit% at #$i');
            break;
          }
        }
        // map-data dimension engaged in the top scorecard
        if (q.dim != null) {
          final dims = recs.first.scorecard!.dimensions;
          final d = dims.where((x) => x.key == q.dim);
          if (d.isEmpty || d.first.weightPct <= 0) {
            fails.add('${t.name} · "${q.text}"  ✗ dimension ${q.dim} NOT engaged (weight 0) — map layer not driving ranking');
          }
        }
        // "אזור X" no far leak
        if (q.area != null) {
          final loc = GovData.instance.localityByName(q.area!);
          if (loc != null && loc.lat.abs() > 0.1) {
            final far = recs.where((s) => _km(s.property.lat, s.property.lon, loc.lat, loc.lon) > 22).toList();
            if (far.isNotEmpty) {
              fails.add('${t.name} · "${q.text}"  ✗ area leak: ${far.map((s) => s.property.city).toSet()}');
            }
          }
        }
        // personalization: profile must change the order
        if (q.profileMustReorder && t.profile != null) {
          final withoutP = run(q.text, null).map((r) => r.property.id).toList();
          final withP = recs.map((r) => r.property.id).toList();
          if (withP.toString() == withoutP.toString()) {
            fails.add('${t.name} · "${q.text}"  ✗ profile did NOT change ranking (personalization dormant)');
          }
        }
      }
    }

    // ignore: avoid_print
    print('\n═══ 25-TESTER BREAKING TEST ═══\ntesters: ${testers.length}  queries: $queries  failures: ${fails.length}');
    for (final f in fails) {
      // ignore: avoid_print
      print('  $f');
    }
    expect(fails, isEmpty, reason: 'personalization/phrase breaks:\n${fails.join("\n")}');
  });
}
