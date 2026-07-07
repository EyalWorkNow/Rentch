import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AGE-VOICED FAST-MODE AUDIT — how well does the parser handle how people REALLY
// talk? 5 personas aged 18-25 (slang, English mix, abbreviations, typos) and 5
// aged 45+ (formal, full sentences, traditional/life-stage phrasing).
// Prints the PARSE + top results per persona; asserts the non-negotiables.
// ─────────────────────────────────────────────────────────────────────────────

RentalProperty p(String id,
        {required String city,
        required double lat,
        required double lon,
        int price = 4000,
        double rooms = 3,
        int size = 70,
        String cond = 'טוב',
        List<String> feats = const ['ac'],
        PropertyTransactionType tx = PropertyTransactionType.rent,
        String neighborhood = ''}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: size, floor: '2',
      totalFloors: '5', city: city, neighborhood: neighborhood, street: 'רחוב',
      streetNumber: 1, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: tx, entryDate: '', condition: cond, ownerName: 'o',
      agencyListing: false, features: feats,
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
      marketSignals: const PropertyMarketSignals(views: 20, likes: 2, saves: 1),
    );

final _cat = <RentalProperty>[
  // Tel Aviv (Florentin / centre) — young crowd.
  p('tlv_flor', city: 'תל אביב', neighborhood: 'פלורנטין', lat: 32.0570, lon: 34.7700, price: 4800, rooms: 2, feats: ['ac', 'balcony']),
  p('tlv_cheap2', city: 'תל אביב', lat: 32.0670, lon: 34.7760, price: 2400, rooms: 1, size: 30),
  p('tlv_studio', city: 'תל אביב', lat: 32.0790, lon: 34.7810, price: 4000, rooms: 1.5, size: 35, feats: ['ac']),
  p('tlv_wfh', city: 'תל אביב', lat: 32.0790, lon: 34.7810, price: 4200, rooms: 2, feats: ['ac', 'internet']),
  // Herzliya — near sea, parking (Gen-Z English-mix persona).
  p('herz_chill', city: 'הרצליה', lat: 32.1700, lon: 34.7960, price: 3900, rooms: 2, feats: ['ac', 'parking', 'balcony']),
  // Beer Sheva near Ben Gurion University.
  p('bs_uni', city: 'באר שבע', lat: 31.2620, lon: 34.8010, price: 1700, rooms: 3, feats: ['ac']),
  p('bs_far', city: 'באר שבע', lat: 31.2400, lon: 34.7700, price: 1600, rooms: 3),
  // Kfar Saba — family, schools.
  p('ks_fam', city: 'כפר סבא', lat: 32.1750, lon: 34.9070, price: 7500, rooms: 5, size: 120, feats: ['ac', 'balcony', 'parking', 'mamad', 'elevator']),
  // Netanya — empty-nesters, elevator/accessible.
  p('net_small', city: 'נתניה', lat: 32.3215, lon: 34.8532, price: 4200, rooms: 3, feats: ['ac', 'elevator', 'accessible']),
  // Rishon LeZion — divorced parent, mamad, near school.
  p('rish_mamad', city: 'ראשון לציון', lat: 31.9730, lon: 34.7925, price: 5800, rooms: 4, feats: ['ac', 'mamad', 'parking']),
  p('rish_no', city: 'ראשון לציון', lat: 31.9600, lon: 34.8000, price: 5500, rooms: 4, feats: ['ac']),
  // Jerusalem — religious retiree, quiet. One in a religious neighbourhood.
  p('jer_quiet', city: 'ירושלים', lat: 31.7780, lon: 35.2100, price: 5000, rooms: 3, feats: ['ac', 'elevator']),
  p('jer_relig', city: 'ירושלים', neighborhood: 'מאה שערים', lat: 31.7870, lon: 35.2230, price: 4900, rooms: 3, feats: ['ac', 'elevator']),
  // Periphery sale — investor.
  p('afula_sale', city: 'עפולה', lat: 32.6100, lon: 35.2900, price: 900000, rooms: 3, tx: PropertyTransactionType.sale),
];

List<ScoredProperty> verify(List<ScoredProperty> res, SearchQuery q) {
  var out = res;
  final city = q.city?.trim();
  if (city != null && city.isNotEmpty) {
    final loc = GovData.instance.localityByName(city);
    if (loc != null) {
      final maxKm = q.intents.contains('city_area') ? 20.0 : 15.0;
      final near = out
          .where((r) =>
              Geolocator.distanceBetween(r.property.lat, r.property.lon, loc.lat, loc.lon) / 1000 <= maxKm)
          .toList();
      if (near.isNotEmpty) out = near;
    }
  }
  final cap = q.maxPrice;
  if (cap != null && cap > 0) {
    out = out.where((r) => r.property.price <= 0 || r.property.price <= cap * 1.35).toList();
  }
  return out;
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await GovData.instance.init();
    } catch (_) {}
  });

  ({SearchQuery q, List<ScoredProperty> shown}) run(String text) {
    final q = SmartSearch.parse(text);
    final ranked = RecommendationEngine.recommendAsScored(candidates: _cat, query: q, limit: 10, seed: 5);
    return (q: q, shown: verify(ranked, q));
  }

  void report(String who, String text, ({SearchQuery q, List<ScoredProperty> shown}) r) {
    final q = r.q;
    // ignore: avoid_print
    print('\n══ $who');
    // ignore: avoid_print
    print('   said: "$text"');
    // ignore: avoid_print
    print('   parsed: city=${q.city} budget=${q.maxPrice} rooms=${q.minRooms}'
        '${q.maxRooms != null ? '-${q.maxRooms}' : ''} type=${q.propertyType} '
        'intents=${q.intents} req=${q.requiredFeatures} nearTrain=${q.nearTrain}');
    for (final s in r.shown.take(3)) {
      // ignore: avoid_print
      print('   → ${s.property.id} | ${s.property.city}'
          '${s.property.neighborhood.isNotEmpty ? '/${s.property.neighborhood}' : ''} '
          '| ₪${s.property.price} | ${s.property.rooms}חד | exact=${s.exact}');
    }
    if (r.shown.isEmpty) {
      // ignore: avoid_print
      print('   → (empty → honest flow)');
    }
  }

  // ══════════════════ 18-25 — slang, English mix, abbreviations ══════════════
  test('Y1 · student roommates, cheap, nightlife (slang)', () {
    final r = run('אחשלי מחפש דירת שותפים בתל אביב משהו זול עד 2500 קרוב לברים ולתחנת רכבת');
    report('Y1 · 22, student, slang', 'אחשלי… שותפים ת"א זול עד 2500 קרוב לברים ולרכבת', r);
    expect(r.q.city, isNotNull, reason: 'must still parse ת"א through the slang');
    expect(r.q.maxPrice, 2500);
    for (final s in r.shown) {
      expect(s.property.price <= 2500 * 1.35, isTrue);
    }
  });

  test('Y2 · new job, WFH, studio, central', () {
    final r = run('היי עברתי לתל אביב לעבודה חדשה, מחפשת סטודיו או 2 חדרים במרכז עד 4000, חשוב אינטרנט טוב לעבודה מהבית');
    report('Y2 · 24, new job, WFH', 'סטודיו/2חד ת"א מרכז עד 4000 אינטרנט WFH', r);
    expect(r.q.maxPrice, 4000);
    expect(r.q.intents.contains('wfh') || r.q.intents.contains('central'), isTrue,
        reason: 'WFH / central intent should register');
  });

  test('Y3 · couple, Florentin vibe, cheap, balcony', () {
    final r = run('אנחנו זוג צעיר רוצים משהו כיפי בפלורנטין עד 5000 עם מרפסת קטנה');
    report('Y3 · 25, couple, Florentin', 'זוג כיפי פלורנטין עד 5000 מרפסת', r);
    expect(r.q.maxPrice, 5000);
    expect(r.q.minRooms, 2, reason: 'couple → 2 rooms (not 3)');
  });

  test('Y4 · student Beer Sheva near BGU, roommates', () {
    final r = run('סטודנט בבן גוריון מחפש דירת שותפים בבאר שבע ליד האוני עד 1800 לחודש');
    report('Y4 · 21, BGU student', 'סטודנט ב"ש ליד האוני שותפים עד 1800', r);
    expect(r.q.city, isNotNull);
    expect(r.q.maxPrice, 1800);
    expect(r.q.intents.contains('student') || r.q.intents.contains('near_university'), isTrue);
  });

  test('Y5 · Gen-Z English mix + typos', () {
    final r = run('יאללה מחפש דירה בהרצליה משהו chill קרוב לים לא יותר מ4000 עם parking');
    report('Y5 · 23, English mix', 'chill הרצליה קרוב לים עד 4000 parking', r);
    expect(r.q.city, isNotNull, reason: 'must parse הרצליה');
    expect(r.q.maxPrice, 4000, reason: 'must read "לא יותר מ4000"');
    expect(r.q.intents.contains('near_sea'), isTrue, reason: 'קרוב לים');
  });

  // ══════════════════ 45+ — formal, life-stage, traditional ══════════════════
  test('O1 · family with teens, schools, quiet, 5 rooms', () {
    final r = run('שלום, אנו משפחה עם שלושה ילדים מתבגרים, מחפשים דירת 5 חדרים בשכונה שקטה עם בתי ספר טובים בכפר סבא, תקציב עד 8000');
    report('O1 · 48, family+teens', 'משפחה 5חד שקט בי"ס כפ"ס עד 8000', r);
    expect(r.q.city, isNotNull);
    expect(r.q.minRooms, 5, reason: 'explicit 5 rooms');
    expect(r.q.intents.contains('good_schools'), isTrue);
  });

  test('O2 · empty-nesters downsizing, elevator, quiet', () {
    final r = run('אנחנו זוג מבוגר, הילדים עזבו את הבית, מחפשים דירה קטנה יותר עם מעלית באזור שקט בנתניה');
    report('O2 · 60, empty-nesters', 'זוג מבוגר דירה קטנה מעלית שקט נתניה', r);
    expect(r.q.city, isNotNull, reason: 'נתניה — not hijacked by "אזור שקט"');
    expect(r.q.intents.contains('quiet'), isTrue);
  });

  test('O3 · investor, sale, yield, periphery', () {
    final r = run('מעוניין לרכוש דירה להשקעה עם תשואה טובה בפריפריה, תקציב עד מיליון שקל');
    report('O3 · 52, investor', 'רכישה להשקעה תשואה פריפריה עד מיליון', r);
    expect(r.q.intents.contains('investment'), isTrue);
    for (final s in r.shown) {
      expect(s.property.transactionType, PropertyTransactionType.sale,
          reason: 'a purchase/investment must not surface rentals');
    }
  });

  test('O4 · divorced parent, mamad, near school', () {
    final r = run('אני גרוש עם שתי בנות, צריך דירת 4 חדרים עם ממ"ד קרוב לבית ספר בראשון לציון עד 6000');
    report('O4 · 45, divorced parent', 'גרוש 4חד ממ"ד ליד בי"ס ראשל"צ עד 6000', r);
    expect(r.q.city, isNotNull);
    expect(r.q.minRooms, 4);
    expect(r.q.intents.contains('good_schools'), isTrue, reason: 'קרוב לבית ספר');
  });

  test('O5 · religious retiree, near synagogue, quiet, Jerusalem', () {
    final r = run('אנחנו זוג דתי מבוגר מחפשים דירה קרובה לבית כנסת באזור שקט בירושלים, שלושה חדרים');
    report('O5 · 67, religious retiree', 'זוג דתי קרוב לביה"כ שקט ירושלים 3חד', r);
    expect(r.q.city, isNotNull);
    expect(r.q.intents.contains('quiet'), isTrue);
    expect(r.q.intents.contains('religious_area'), isTrue,
        reason: '"דתי"/"בית כנסת" must register the religious-area intent');
    // The מאה שערים flat should out-rank the secular one on a religious search.
    final ids = r.shown.map((s) => s.property.id).toList();
    if (ids.contains('jer_relig') && ids.contains('jer_quiet')) {
      expect(ids.indexOf('jer_relig') < ids.indexOf('jer_quiet'), isTrue,
          reason: 'religious-neighbourhood flat should rank first for a דתי seeker');
    }
  });
}
