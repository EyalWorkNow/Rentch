import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// ── "Tester" pass over אתי's VOICE conversation logic ────────────────────────
// I can't speak to her, so this drives the exact pipeline a spoken turn runs:
// what the user SAID (transcript) → SmartSearch.parse → the ranking engine that
// produces the apartments + relevance chips she voices back. Each tester is a
// realistic, messy, spoken sentence with a concrete expectation. A failure = אתי
// mis-hears/mis-searches that phrasing.

RentalProperty flat({
  required String id,
  required int price,
  required double rooms,
  required int sizeM2,
  required String city,
  required double lat,
  required double lon,
  String floor = '3',
  String neighborhood = '',
  List<String> features = const [],
  PropertyTransactionType type = PropertyTransactionType.rent,
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: sizeM2, floor: floor,
      totalFloors: '20', city: city, neighborhood: neighborhood, street: 'הרצל',
      streetNumber: 10, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: type, entryDate: '', condition: 'טוב',
      ownerName: 'בעלים', agencyListing: false, features: features,
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
      marketSignals: PropertyMarketSignals(views: 120, likes: 14, saves: 4),
    );

List<RentalProperty> catalogue() => [
      // Tel Aviv — beach / center / nightlife
      flat(id: 'ta-beach-2rm', price: 8200, rooms: 2, sizeM2: 55,
          city: 'תל אביב', lat: 32.081, lon: 34.767, floor: '5',
          features: ['balcony', 'ac']),
      flat(id: 'ta-center-3rm', price: 8800, rooms: 3, sizeM2: 78,
          city: 'תל אביב', lat: 32.072, lon: 34.781,
          features: ['elevator', 'ac', 'balcony']),
      flat(id: 'ta-cheap-2rm', price: 6000, rooms: 2, sizeM2: 50,
          city: 'תל אביב', lat: 32.06, lon: 34.79, features: ['ac']),
      flat(id: 'ta-penthouse', price: 15000, rooms: 4, sizeM2: 140,
          city: 'תל אביב', lat: 32.083, lon: 34.77, floor: '22',
          features: ['elevator', 'ac', 'parking', 'balcony', 'pool']),
      flat(id: 'tau-2rm', price: 6400, rooms: 2, sizeM2: 58, city: 'תל אביב',
          lat: 32.1133, lon: 34.8044, features: ['ac', 'elevator']),
      // Jerusalem — for the cross-city neighbourhood→city guard (רחביה)
      flat(id: 'jlm-3rm', price: 6800, rooms: 3, sizeM2: 80, city: 'ירושלים',
          lat: 31.7767, lon: 35.2145, features: ['ac', 'elevator']),
      // Bnei Brak — charedi family
      flat(id: 'bb-4rm', price: 5400, rooms: 4, sizeM2: 95, city: 'בני ברק',
          lat: 32.083, lon: 34.836, features: ['elevator', 'mamad', 'balcony']),
      flat(id: 'bb-3rm', price: 4800, rooms: 3, sizeM2: 72, city: 'בני ברק',
          lat: 32.086, lon: 34.842, features: ['mamad']),
      // Beer Sheva — student stock by BGU
      flat(id: 'bgu-3rm', price: 2600, rooms: 3, sizeM2: 70, city: 'באר שבע',
          lat: 31.2635, lon: 34.8018, features: ['ac']),
      flat(id: 'bs-4rm', price: 3200, rooms: 4, sizeM2: 90, city: 'באר שבע',
          lat: 31.25, lon: 34.79, features: ['ac', 'elevator']),
      // Netanya — retirees, quiet, near sea
      flat(id: 'net-elev', price: 4900, rooms: 3, sizeM2: 82, city: 'נתניה',
          lat: 32.32, lon: 34.853, floor: '2', features: ['elevator', 'ac']),
      flat(id: 'net-walkup', price: 4600, rooms: 3, sizeM2: 80, city: 'נתניה',
          lat: 32.31, lon: 34.86, floor: '4', features: ['ac']),
      // Herzliya — luxury
      flat(id: 'hrz-lux', price: 13500, rooms: 4, sizeM2: 135, city: 'הרצליה',
          lat: 32.16, lon: 34.84, floor: '10',
          features: ['elevator', 'ac', 'parking', 'pool', 'balcony']),
      // For-sale — investor stock
      flat(id: 'sale-ta', price: 3400000, rooms: 3, sizeM2: 78, city: 'תל אביב',
          lat: 32.07, lon: 34.78, type: PropertyTransactionType.sale),
      flat(id: 'sale-bs', price: 1250000, rooms: 4, sizeM2: 95, city: 'באר שבע',
          lat: 31.25, lon: 34.79, type: PropertyTransactionType.sale),
    ];

class Tester {
  const Tester(this.who, this.said, this.check, this.expect);
  final String who;
  final String said; // the spoken transcript
  final bool Function(List<ScoredProperty> recs, SearchQuery q) check;
  final String expect; // human description of what should happen
}

void main() {
  final cat = catalogue();

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await GovData.instance.init();
    } catch (_) {}
    await IsraelGeoIndex.loadParks();
    await IsraelGeoIndex.loadSchools();
    await IsraelGeoIndex.loadNightlife();
  });

  ({List<ScoredProperty> recs, SearchQuery q}) run(String said) {
    final q = SmartSearch.parse(said);
    final recs = RecommendationEngine.recommendAsScored(
        candidates: cat, query: q, limit: 10, seed: 7);
    return (recs: recs, q: q);
  }

  String cityOfTop(List<ScoredProperty> r) =>
      r.isEmpty ? '(none)' : r.first.property.city;
  bool topInCity(List<ScoredProperty> r, String city) =>
      r.isNotEmpty && r.first.property.city == city;
  bool anyInTop(List<ScoredProperty> r, String id, int n) =>
      r.take(n).any((s) => s.property.id == id);
  List<String> tagsOf(List<ScoredProperty> r) =>
      [for (final s in r.take(3)) ...s.tags];

  final testers = <Tester>[
    // ── everyday, clean phrasing ──
    Tester('משפחה דתית בבני ברק', 'אנחנו משפחה דתית מחפשת ארבעה חדרים בבני ברק עד 6000',
        (r, q) => topInCity(r, 'בני ברק'),
        'עיר=בני ברק, לזהות משפחה+דתי'),
    Tester('סטודנט באר שבע', 'סטודנט מחפש דירה זולה ליד האוניברסיטה בבאר שבע',
        (r, q) => topInCity(r, 'באר שבע'),
        'עיר=באר שבע, מזהה סטודנט'),
    Tester('משקיע', 'אני משקיע, מחפש דירה למכירה עם תשואה טובה בתל אביב',
        (r, q) => r.isNotEmpty && r.first.property.transactionType == PropertyTransactionType.sale,
        'עסקה=מכירה (sale) בראש'),
    Tester('זוג ליד הים', 'זוג צעיר שרוצה דירה קרוב לים בתל אביב עד 8500',
        (r, q) => topInCity(r, 'תל אביב'),
        'עיר=תל אביב, near_sea'),
    Tester('פנסיונר נתניה', 'זוג מבוגר מחפש דירה שקטה עם מעלית בנתניה',
        (r, q) => topInCity(r, 'נתניה') && r.first.property.features.contains('elevator'),
        'עיר=נתניה, מעלית (נגישות)'),
    Tester('יוקרה הרצליה', 'מחפשים דירת יוקרה מפוארת בהרצליה עם בריכה',
        (r, q) => topInCity(r, 'הרצליה'),
        'עיר=הרצליה, luxury'),

    // ── messy / spoken fillers / typos ──
    Tester('דיבור מגומגם', 'אהм… יעני… אנחנו מחפשים ככה שלושה חדרים בתל אביב, משהו במרכז',
        (r, q) => topInCity(r, 'תל אביב') && q.minRooms == 3,
        'לחלץ 3 חדרים+תל אביב מתוך רעש דיבור'),
    Tester('מספר במילים', 'דירת שלושה חדרים בבאר שבע בבקשה',
        (r, q) => q.minRooms == 3 && topInCity(r, 'באר שבע'),
        'מספר חדרים כתוב במילה'),
    Tester('תקציב באלף', 'משהו בתל אביב עד 8 אלף שקל',
        (r, q) => q.maxPrice != null && q.maxPrice! <= 8000 && q.maxPrice! >= 7000,
        'לפרש "8 אלף" כ-8000'),
    Tester('שכונה בלי עיר מפורשת', 'דירה ברמת אביב ליד האוניברסיטה',
        (r, q) => topInCity(r, 'תל אביב') && q.neighborhood == 'רמת אביב',
        'שכונה→עיר אב (רמת אביב→תל אביב), לא 0 תוצאות'),
    Tester('שכונה בירושלים', 'שלושה חדרים ברחביה',
        (r, q) => topInCity(r, 'ירושלים') && q.neighborhood == 'רחביה',
        'שכונה חוצת-עיר (רחביה→ירושלים)'),

    // ── intent / lifestyle inference ──
    Tester('חיות מחמד', 'יש לי כלב גדול, צריך דירה שמתירה חיות בתל אביב',
        (r, q) => topInCity(r, 'תל אביב'),
        'עיר נכונה למרות שהפוקוס על כלב'),
    Tester('עבודה מהבית', 'אני עובד מהבית, צריך חדר עבודה שקט בנתניה',
        (r, q) => topInCity(r, 'נתניה'),
        'wfh — עיר נכונה'),
    Tester('שותפים', 'מחפש דירה לשותפים בבאר שבע, תקציב קטן',
        (r, q) => topInCity(r, 'באר שבע'),
        'roommates — עיר נכונה'),

    // ── edge cases a tester WILL try ──
    Tester('בלי תקציב', 'סתם דירה בתל אביב',
        (r, q) => r.isNotEmpty && topInCity(r, 'תל אביב'),
        'בלי תקציב — עדיין מחזירה'),
    Tester('שתי ערים', 'תל אביב או הרצליה, מה שיש',
        (r, q) => r.isNotEmpty,
        'לא לקרוס על שתי ערים'),
    Tester('שלילה', 'דירה בתל אביב אבל לא בקומה גבוהה',
        (r, q) => topInCity(r, 'תל אביב'),
        'שלילה לא הופכת את הכוונה'),
    Tester('אנגלית', 'looking for a 3 room apartment in Tel Aviv up to 9000',
        (r, q) => topInCity(r, 'תל אביב') && q.minRooms == 3,
        'אנגלית — עיר+חדרים'),
    Tester('תקציב הדוק', 'דירה בבאר שבע עד 2800',
        (r, q) => r.isNotEmpty && r.first.property.price <= 2800,
        'top-1 בתוך תקציב הדוק'),
  ];

  var passed = 0;
  final failures = <String>[];
  for (final t in testers) {
    test('${t.who}: ${t.expect}', () {
      final res = run(t.said);
      final ok = t.check(res.recs, res.q);
      // ignore: avoid_print
      print('${ok ? "✅" : "❌"} ${t.who} — "${t.said}"\n'
          '     → top=${cityOfTop(res.recs)} '
          'rooms=${res.q.minRooms} max=${res.q.maxPrice} '
          'intents=${res.q.intents} results=${res.recs.length}\n'
          '     chips: ${tagsOf(res.recs).join(" · ")}');
      if (ok) {
        passed++;
      } else {
        failures.add(t.who);
      }
      expect(ok, isTrue, reason: '[${t.who}] expected: ${t.expect}');
    });
  }

  tearDownAll(() {
    // ignore: avoid_print
    print('\n═══ TESTER SUMMARY: ${passed}/${testers.length} passed'
        '${failures.isEmpty ? "" : " · fails: ${failures.join(", ")}"} ═══');
  });
}
