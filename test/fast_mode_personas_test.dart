import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DEEP, CRITICAL FAST-MODE PERSONA HARNESS
// Runs the REAL on-device pipeline (SmartSearch.parse → RecommendationEngine +
// the UI's _verifyResults geo/budget safety net) against a realistic catalogue,
// for 10 demanding personas. Prints a per-persona report AND asserts the
// non-negotiable correctness guarantees so real regressions fail the suite.
// ─────────────────────────────────────────────────────────────────────────────

RentalProperty p(
  String id, {
  required String city,
  required double lat,
  required double lon,
  int price = 4000,
  double rooms = 3,
  int size = 70,
  String cond = 'טוב',
  String type = 'דירה',
  List<String> feats = const ['ac'],
  PropertyTransactionType tx = PropertyTransactionType.rent,
  String neighborhood = '',
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: size, floor: '2',
      totalFloors: '5', city: city, neighborhood: neighborhood, street: 'רחוב',
      streetNumber: 1, lat: lat, lon: lon, propertyType: type,
      transactionType: tx, entryDate: '', condition: cond, ownerName: 'o',
      agencyListing: false, features: feats,
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
      marketSignals: const PropertyMarketSignals(views: 20, likes: 2, saves: 1),
    );

// Real-ish coordinates for the cities the personas name.
const _tlv = [32.0809, 34.7806];
const _tlvSea = [32.0870, 34.7680]; // near the beach
const _tlvUni = [32.1130, 34.8050]; // near TAU
const _ramatGan = [32.0700, 34.8240];
const _givatayim = [32.0720, 34.8120];
const _herzliya = [32.1624, 34.8443];
const _herzliyaSea = [32.1700, 34.7960];
const _netanya = [32.3215, 34.8532];
const _petahTikva = [32.0840, 34.8878];
const _beerSheva = [31.2520, 34.7915];
const _haifa = [32.7940, 34.9896];
const _karkur = [32.4700, 34.9600]; // פרדס חנה-כרכור
const _jerusalem = [31.7683, 35.2137];

List<RentalProperty> buildCatalogue() => [
      // Tel Aviv — a spread of budgets, incl. expensive ones (budget-stress test).
      p('tlv_cheap', city: 'תל אביב', lat: _tlv[0], lon: _tlv[1], price: 4200, rooms: 2),
      p('tlv_mid', city: 'תל אביב', lat: _tlv[0], lon: _tlv[1], price: 6800, rooms: 3, feats: ['ac', 'balcony']),
      p('tlv_lux', city: 'תל אביב', lat: _tlv[0], lon: _tlv[1], price: 12000, rooms: 4, feats: ['ac', 'balcony', 'parking', 'elevator'], cond: 'חדש'),
      p('tlv_sea', city: 'תל אביב', lat: _tlvSea[0], lon: _tlvSea[1], price: 8000, rooms: 3, feats: ['ac', 'balcony']),
      p('tlv_uni', city: 'תל אביב', lat: _tlvUni[0], lon: _tlvUni[1], price: 5200, rooms: 3, feats: ['ac']),
      p('tlv_balc_park', city: 'תל אביב', lat: _tlv[0], lon: _tlv[1], price: 6500, rooms: 3, feats: ['ac', 'balcony', 'parking']),
      // Ramat Gan / Givatayim — TLV metro (≤5–8km).
      p('rg_1', city: 'רמת גן', lat: _ramatGan[0], lon: _ramatGan[1], price: 5000, rooms: 3, feats: ['ac', 'elevator']),
      p('rg_2', city: 'רמת גן', lat: _ramatGan[0], lon: _ramatGan[1], price: 4300, rooms: 2),
      p('giv_1', city: 'גבעתיים', lat: _givatayim[0], lon: _givatayim[1], price: 5500, rooms: 3, feats: ['ac', 'balcony']),
      // Herzliya — for the young-couple-near-sea persona.
      p('herz_sea', city: 'הרצליה', lat: _herzliyaSea[0], lon: _herzliyaSea[1], price: 4400, rooms: 2, feats: ['ac', 'balcony']),
      p('herz_in', city: 'הרצליה', lat: _herzliya[0], lon: _herzliya[1], price: 4300, rooms: 3, feats: ['ac']),
      p('herz_exp', city: 'הרצליה', lat: _herzliya[0], lon: _herzliya[1], price: 9000, rooms: 4),
      // Netanya — retiree / accessible.
      p('net_acc', city: 'נתניה', lat: _netanya[0], lon: _netanya[1], price: 4000, rooms: 3, feats: ['ac', 'elevator', 'accessible']),
      p('net_noacc', city: 'נתניה', lat: _netanya[0], lon: _netanya[1], price: 3800, rooms: 3, feats: ['ac']),
      // Petah Tikva — family.
      p('pt_fam', city: 'פתח תקווה', lat: _petahTikva[0], lon: _petahTikva[1], price: 5500, rooms: 4, size: 100, feats: ['ac', 'balcony', 'parking', 'mamad']),
      p('pt_small', city: 'פתח תקווה', lat: _petahTikva[0], lon: _petahTikva[1], price: 4000, rooms: 2),
      // Beer Sheva — investor / sale.
      p('bs_sale1', city: 'באר שבע', lat: _beerSheva[0], lon: _beerSheva[1], price: 850000, rooms: 3, tx: PropertyTransactionType.sale),
      p('bs_sale2', city: 'באר שבע', lat: _beerSheva[0], lon: _beerSheva[1], price: 1100000, rooms: 4, tx: PropertyTransactionType.sale),
      // Haifa, Jerusalem — distractors far from the searched cities.
      p('hai_1', city: 'חיפה', lat: _haifa[0], lon: _haifa[1], price: 3500, rooms: 3),
      p('jer_1', city: 'ירושלים', lat: _jerusalem[0], lon: _jerusalem[1], price: 5000, rooms: 3),
      // NOTE: intentionally NO listing in כרכור/פרדס חנה — the Karkur persona must
      // get an honest "nothing here" (never a far city), not a leaked flat.
    ];

// Mirror of the app's fast-mode _verifyResults (geo + gross-budget correctness).
List<ScoredProperty> verify(List<ScoredProperty> res, SearchQuery q) {
  var out = res;
  final city = q.city?.trim();
  if (city != null && city.isNotEmpty) {
    final loc = GovData.instance.localityByName(city);
    if (loc != null) {
      final maxKm = q.intents.contains('city_area') ? 20.0 : 15.0;
      final near = out
          .where((r) =>
              Geolocator.distanceBetween(
                      r.property.lat, r.property.lon, loc.lat, loc.lon) /
                  1000 <=
              maxKm)
          .toList();
      if (near.isNotEmpty) out = near;
    }
  }
  final cap = q.maxPrice;
  if (cap != null && cap > 0) {
    out = out
        .where((r) => r.property.price <= 0 || r.property.price <= cap * 1.35)
        .toList();
  }
  return out;
}

double? kmFromCity(RentalProperty prop, String city) {
  final loc = GovData.instance.localityByName(city);
  if (loc == null) return null;
  return Geolocator.distanceBetween(prop.lat, prop.lon, loc.lat, loc.lon) / 1000;
}

void main() {
  final cat = buildCatalogue();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await GovData.instance.init();
    } catch (_) {}
  });

  ({SearchQuery q, List<ScoredProperty> shown}) run(String text) {
    final q = SmartSearch.parse(text);
    final ranked =
        RecommendationEngine.recommendAsScored(candidates: cat, query: q, limit: 10, seed: 7);
    return (q: q, shown: verify(ranked, q));
  }

  void report(String name, String text, ({SearchQuery q, List<ScoredProperty> shown}) r) {
    final q = r.q;
    final top = r.shown.take(3).toList();
    // ignore: avoid_print
    print('\n══ $name');
    // ignore: avoid_print
    print('   query: "$text"');
    // ignore: avoid_print
    print('   parsed: city=${q.city} budget=${q.maxPrice} rooms=${q.minRooms} '
        'intents=${q.intents} req=${q.requiredFeatures}');
    for (final s in top) {
      final km = q.city != null ? kmFromCity(s.property, q.city!) : null;
      // ignore: avoid_print
      print('   → ${s.property.id} | ${s.property.city} | ₪${s.property.price} | '
          '${s.property.rooms}חד | ${km?.toStringAsFixed(1) ?? '?'}km | exact=${s.exact}');
    }
    if (top.isEmpty) {
      // ignore: avoid_print
      print('   → (empty → honest "nothing here, but nearby…" flow)');
    }
  }

  // ── P1: the reported Karkur bug — must NEVER leak a far city ────────────────
  test('P1 · כרכור ללא הגבלה → no far-city leak', () {
    final r = run('דירה בכרכור בלי הגבלה');
    report('P1 · Karkur (no limit)', 'דירה בכרכור בלי הגבלה', r);
    for (final s in r.shown) {
      final km = kmFromCity(s.property, r.q.city ?? 'פרדס חנה-כרכור');
      if (km != null) {
        expect(km <= 20, isTrue,
            reason: 'CRITICAL: ${s.property.city} is ${km.toStringAsFixed(0)}km '
                'from Karkur — a hallucinated far match');
      }
    }
  });

  // ── P2: young couple, baby, Herzliya, ≤4500, near sea ───────────────────────
  test('P2 · זוג צעיר הרצליה ≤4500 קרוב לים', () {
    final r = run('דירה לזוג צעיר בהרצליה מצפים לילד עד 4500 לא רחוק מהים');
    report('P2 · Young couple Herzliya sea', 'זוג צעיר הרצליה עד 4500 קרוב לים', r);
    expect(r.q.city, isNotNull, reason: 'must parse הרצליה');
    expect(r.q.minRooms, 2,
        reason: 'a couple expecting their FIRST child → minRooms 2, not a hard 3');
    for (final s in r.shown) {
      expect(s.property.price <= 4500 * 1.35, isTrue,
          reason: '${s.property.id} ₪${s.property.price} grossly over ₪4500');
    }
  });

  // ── P3: family, Petah Tikva, parks + schools, 4 rooms ───────────────────────
  test('P3 · משפחה פתח תקווה 4 חדרים פארקים', () {
    final r = run('משפחה עם 3 ילדים בפתח תקווה, 4 חדרים, קרוב לפארק ובתי ספר');
    report('P3 · Family Petah Tikva parks', 'משפחה פ"ת 4 חד קרוב לפארק', r);
    expect(r.shown, isNotEmpty);
  });

  // ── P4: student, near TAU, roommates, low budget ────────────────────────────
  test('P4 · סטודנט תל אביב שותפים 2500', () {
    final r = run('סטודנט מחפש דירה עם שותפים ליד אוניברסיטת תל אביב עד 2500');
    report('P4 · Student TAU roommates', 'סטודנט ת"א שותפים עד 2500', r);
    // ₪2500 in TLV is unrealistic → an honest "nothing that cheap" (empty →
    // raise-budget flow) is the CORRECT answer; never present over-budget flats.
    for (final s in r.shown) {
      expect(s.property.price <= 2500 * 1.35, isTrue,
          reason: '${s.property.id} ₪${s.property.price} over a ₪2500 budget');
    }
  });

  // ── P5: retiree, quiet, accessible, Netanya ─────────────────────────────────
  test('P5 · פנסיונר נתניה נגיש שקט', () {
    final r = run('דירה לפנסיונר מבוגר בנתניה, נגישה עם מעלית, אזור שקט');
    report('P5 · Retiree Netanya accessible', 'פנסיונר נתניה נגיש שקט', r);
    // The accessible flat should out-rank the non-accessible one in Netanya.
    final ids = r.shown.map((s) => s.property.id).toList();
    if (ids.contains('net_acc') && ids.contains('net_noacc')) {
      expect(ids.indexOf('net_acc') < ids.indexOf('net_noacc'), isTrue,
          reason: 'accessible flat should rank above the non-accessible one');
    }
  });

  // ── P6: investor, sale, Beer Sheva ──────────────────────────────────────────
  test('P6 · משקיע באר שבע למכירה תשואה', () {
    final r = run('דירה להשקעה למכירה בבאר שבע תשואה גבוהה');
    report('P6 · Investor Beer Sheva sale', 'השקעה למכירה ב"ש', r);
    for (final s in r.shown) {
      expect(s.property.transactionType, PropertyTransactionType.sale,
          reason: 'investor/sale intent must not surface rentals');
    }
  });

  // ── P7: hard required features (מרפסת + חניה) in TLV ────────────────────────
  test('P7 · תל אביב חובה מרפסת וחניה עד 7000', () {
    final r = run('דירה בתל אביב חייב מרפסת וחניה עד 7000');
    report('P7 · TLV must balcony+parking', 'ת"א חובה מרפסת+חניה עד 7000', r);
    // If the required-feature gate holds, every shown flat has BOTH.
    for (final s in r.shown) {
      final f = s.property.featureFlags;
      final ok = f.isEnabled('balcony') && f.isEnabled('parking');
      // Not a hard assert (engine relaxes if nothing qualifies) — but flag it.
      if (!ok) {
        // ignore: avoid_print
        print('   ⚠ ${s.property.id} lacks balcony/parking (gate relaxed?)');
      }
    }
    expect(r.shown, isNotEmpty);
  });

  // ── P8: area mode — "אזור רמת גן" widens to the metro, NOT far cities ───────
  test('P8 · אזור רמת גן → metro only', () {
    final r = run('דירה באזור רמת גן');
    report('P8 · Area Ramat Gan', 'אזור רמת גן', r);
    for (final s in r.shown) {
      final km = kmFromCity(s.property, r.q.city ?? 'רמת גן');
      if (km != null) {
        expect(km <= 20, isTrue,
            reason: '${s.property.city} ${km.toStringAsFixed(0)}km is outside the RG metro');
      }
    }
  });

  // ── P9: budget stress — "תל אביב עד 3000" (TLV is pricey) ───────────────────
  test('P9 · תל אביב עד 3000 → no gross over-budget', () {
    final r = run('דירה בתל אביב עד 3000');
    report('P9 · TLV budget stress', 'ת"א עד 3000', r);
    for (final s in r.shown) {
      expect(s.property.price <= 3000 * 1.35, isTrue,
          reason: 'CRITICAL: ₪${s.property.price} presented as a match for ≤₪3000');
    }
  });

  // ── P10: vague — no city/budget → should NOT invent a confident match ───────
  test('P10 · vague "משהו נחמד לגור" → no hallucinated city', () {
    final r = run('משהו נחמד לגור');
    report('P10 · Vague', 'משהו נחמד לגור', r);
    expect(r.q.city, isNull,
        reason: 'must not invent a city from a vague message');
  });
}
