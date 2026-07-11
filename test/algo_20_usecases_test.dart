// Exploratory BREAKING harness: 20 diverse real-world use-cases run through the
// REAL engine with REAL gov data (stat-areas/SES/centrality). It PRINTS the top
// results so a human can judge whether the #1 truly fits — not a pass/fail suite.
import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

RentalProperty lp({
  required String id,
  required int price,
  required double rooms,
  required int sizeM2,
  required String city,
  String hood = '',
  required double lat,
  required double lon,
  String floor = '3',
  List<String> features = const [],
  String condition = 'טוב',
  PropertyTransactionType tx = PropertyTransactionType.rent,
}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: sizeM2, floor: floor,
      totalFloors: '8', city: city, neighborhood: hood, street: 'הרצל',
      streetNumber: 5, lat: lat, lon: lon, propertyType: 'דירה', entryDate: '',
      condition: condition, ownerName: 'בעלים', agencyListing: false,
      features: features, transactionType: tx,
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: const PropertyMarketSignals(views: 60, likes: 8, saves: 3),
    );

// A realistic, diverse national catalogue (real coordinates so gov data resolves).
List<RentalProperty> catalogue() => [
  // ── Tel Aviv — varied blocks ──
  lp(id: 'tlv_center_9', price: 9000, rooms: 3, sizeM2: 78, city: 'תל אביב', hood: 'לב העיר', lat: 32.0700, lon: 34.7750, features: ['elevator', 'balcony', 'airConditioning']),
  lp(id: 'tlv_shapira_cheap', price: 4200, rooms: 2, sizeM2: 48, city: 'תל אביב', hood: 'שפירא', lat: 32.0545, lon: 34.7790, features: ['airConditioning']),
  lp(id: 'tlv_florentin_young', price: 5200, rooms: 2, sizeM2: 45, city: 'תל אביב', hood: 'פלורנטין', lat: 32.0560, lon: 34.7690, floor: '1', features: ['airConditioning', 'balcony']),
  lp(id: 'tlv_ramataviv_fam', price: 11000, rooms: 4, sizeM2: 110, city: 'תל אביב', hood: 'רמת אביב', lat: 32.1130, lon: 34.8040, features: ['elevator', 'parking', 'mamad', 'balcony']),
  lp(id: 'tlv_studio_studio', price: 3800, rooms: 1, sizeM2: 30, city: 'תל אביב', hood: 'הצפון הישן', lat: 32.0850, lon: 34.7810, floor: '4', features: ['airConditioning']),
  lp(id: 'tlv_lux_penthouse', price: 22000, rooms: 5, sizeM2: 180, city: 'תל אביב', hood: 'רוטשילד', lat: 32.0650, lon: 34.7710, floor: '20', features: ['elevator', 'parking', 'pool', 'gym', 'balcony', 'mamad']),
  lp(id: 'tlv_big_share', price: 8500, rooms: 5, sizeM2: 130, city: 'תל אביב', hood: 'יד אליהו', lat: 32.0640, lon: 34.7930, features: ['balcony', 'airConditioning']),
  lp(id: 'tlv_walkup_3rd', price: 5000, rooms: 3, sizeM2: 65, city: 'תל אביב', hood: 'התקווה', lat: 32.0555, lon: 34.7880, floor: '3', features: ['airConditioning']),
  lp(id: 'tlv_ground_access', price: 6800, rooms: 3, sizeM2: 70, city: 'תל אביב', hood: 'בבלי', lat: 32.0950, lon: 34.7920, floor: '0', features: ['airConditioning', 'garden']),
  lp(id: 'tlv_wfh_spacious', price: 9500, rooms: 4, sizeM2: 120, city: 'תל אביב', hood: 'רמת החייל', lat: 32.1160, lon: 34.8380, features: ['elevator', 'parking', 'balcony', 'airConditioning'], condition: 'משופצת'),
  lp(id: 'tlv_dog_low', price: 6200, rooms: 3, sizeM2: 68, city: 'תל אביב', hood: 'נווה צדק', lat: 32.0620, lon: 34.7640, floor: '1', features: ['petsAllowed', 'garden', 'airConditioning']),
  // ── Bat Yam — beachfront + inland ──
  lp(id: 'batyam_beach', price: 6500, rooms: 3, sizeM2: 72, city: 'בת ים', hood: '', lat: 32.0170, lon: 34.7440, features: ['elevator', 'balcony', 'airConditioning']),
  lp(id: 'batyam_inland', price: 5200, rooms: 3, sizeM2: 70, city: 'בת ים', hood: '', lat: 32.0250, lon: 34.7550, features: ['airConditioning']),
  lp(id: 'batyam_fam', price: 5800, rooms: 4, sizeM2: 95, city: 'בת ים', hood: '', lat: 32.0200, lon: 34.7480, features: ['elevator', 'mamad', 'parking']),
  // ── Jerusalem — center, Mea Shearim, Rehavia ──
  lp(id: 'jlm_center', price: 6000, rooms: 3, sizeM2: 70, city: 'ירושלים', hood: 'מרכז העיר', lat: 31.7810, lon: 35.2180, features: ['elevator', 'airConditioning']),
  lp(id: 'jlm_meashearim', price: 4900, rooms: 3, sizeM2: 68, city: 'ירושלים', hood: 'מאה שערים', lat: 31.7890, lon: 35.2200, features: ['airConditioning']),
  lp(id: 'jlm_rehavia_quiet', price: 8000, rooms: 3, sizeM2: 85, city: 'ירושלים', hood: 'רחביה', lat: 31.7720, lon: 35.2080, features: ['elevator', 'balcony']),
  // ── Beer Sheva — near BGU + far + sale ──
  lp(id: 'bes_bgu', price: 2600, rooms: 3, sizeM2: 65, city: 'באר שבע', hood: '', lat: 31.2620, lon: 34.8010, features: ['airConditioning']),
  lp(id: 'bes_far', price: 2200, rooms: 3, sizeM2: 70, city: 'באר שבע', hood: '', lat: 31.2400, lon: 34.7700, features: []),
  lp(id: 'bes_sale', price: 1150000, rooms: 4, sizeM2: 95, city: 'באר שבע', hood: '', lat: 31.2560, lon: 34.7980, tx: PropertyTransactionType.sale, features: ['parking', 'mamad']),
  // ── Herzliya / Ramat Gan / Petah Tikva ──
  lp(id: 'herz_quiet', price: 7500, rooms: 4, sizeM2: 100, city: 'הרצליה', hood: '', lat: 32.1660, lon: 34.8420, features: ['parking', 'balcony', 'mamad']),
  lp(id: 'rg_central', price: 6300, rooms: 3, sizeM2: 72, city: 'רמת גן', hood: '', lat: 32.0853, lon: 34.8110, features: ['elevator', 'airConditioning']),
  lp(id: 'pt_family', price: 5500, rooms: 4, sizeM2: 105, city: 'פתח תקווה', hood: '', lat: 32.0900, lon: 34.8870, features: ['elevator', 'parking', 'mamad', 'balcony']),
];

void _show(String title, List<Recommendation> recs, {int n = 3}) {
  final b = StringBuffer('\n### $title\n');
  if (recs.isEmpty) {
    b.write('   (no results)\n');
  } else {
    for (var i = 0; i < recs.length && i < n; i++) {
      final r = recs[i];
      final p = r.property;
      final hi = r.highlights.take(2).join(' · ');
      final conc = r.scorecard?.concerns.take(1).join('; ') ?? '';
      b.write('   #${i + 1} ${p.id} | ${p.city}${p.neighborhood.isNotEmpty ? '/${p.neighborhood}' : ''} '
          '| ₪${p.price} | ${p.rooms}חד | ${r.fitPct}%  ${hi.isNotEmpty ? '→ $hi' : ''}'
          '${conc.isNotEmpty ? '  ⚠ $conc' : ''}\n');
    }
  }
  print(b.toString());
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: (p) => File(p).readAsString());
  });
  tearDownAll(() => GovData.instance.resetForTest());

  test('20 diverse use-cases — print top results for human judgement', () {
    final cat = catalogue();
    List<Recommendation> run(String q, {TenantProfile? profile, double? wLat, double? wLon}) =>
        RecommendationEngine.recommend(
          candidates: cat, query: SmartSearch.parse(q), profile: profile,
          limit: 3, explore: false, workLat: wLat, workLon: wLon);

    _show('1. משפחה 3 ילדים, 4 חדרים, שכונה טובה ובטוחה בתל אביב עד 12000',
        run('משפחה עם שלושה ילדים דירת 4 חדרים בשכונה טובה ובטוחה בתל אביב עד 12000'));
    _show('2. סטודנט ליד אוניברסיטת תל אביב תקציב נמוך עד 4500',
        run('סטודנט מחפש דירה ליד אוניברסיטת תל אביב עד 4500'));
    _show('3. משקיע — דירה להשקעה תשואה טובה בבאר שבע',
        run('דירה להשקעה עם תשואה טובה בבאר שבע'));
    _show('4. זוג דתי מבוגר שקט קרוב לבית כנסת ירושלים 3 חדרים',
        run('זוג דתי מבוגר מחפש דירה שקטה קרוב לבית כנסת בירושלים 3 חדרים'));
    _show('5. מבוגר עם מגבלת ניידות — נגישות מלאה בתל אביב',
        run('דירה נגישה לכיסא גלגלים בתל אביב עם מעלית קומה נמוכה'));
    _show('6. עבודה מהבית — מרווחת עם חדר עבודה שקטה בתל אביב',
        run('עובד מהבית מחפש דירה מרווחת עם חדר עבודה שקטה בתל אביב'));
    _show('7. רווק צעיר — חיי לילה ותחבורה במרכז תל אביב',
        run('רווק צעיר מחפש דירה במרכז תל אביב קרוב לחיי לילה ותחבורה'));
    _show('8. משפחה קרוב לים בבת ים',
        run('משפחה מחפשת דירה קרוב לים בבת ים 4 חדרים'));
    _show('9. תקציב צמוד — הכי זול 2 חדרים בתל אביב',
        run('הדירה הכי זולה שאפשר 2 חדרים בתל אביב'));
    _show('10. יוקרה — פנטהאוז עם נוף תל אביב תקציב גבוה',
        run('פנטהאוז יוקרה עם נוף בתל אביב עד 25000'));
    _show('11. שלושה שותפים — דירה גדולה מחוברת לתחבורה בתל אביב',
        run('שלושה שותפים מחפשים דירה גדולה מחוברת לתחבורה בתל אביב'));
    _show('12. זוג צעיר — מרכזי אזור איכותי בתל אביב',
        run('זוג צעיר מחפש דירה מרכזית באזור איכותי בתל אביב'));
    _show('13. משפחה קרוב לבתי ספר ופארק בתל אביב',
        run('משפחה מחפשת דירה קרוב לבתי ספר טובים ופארק בתל אביב'));
    _show('14. בעל כלב — ידידותי לחיות קומה נמוכה בתל אביב',
        run('בעל כלב מחפש דירה ידידותית לחיות מחמד קומת קרקע בתל אביב'));
    _show('15. קרוב לעבודה (עבודה ברמת החייל) בתל אביב',
        run('דירה בתל אביב קרוב לעבודה', wLat: 32.1160, wLon: 34.8380));
    _show('16. דירה ראשונה — תמורה למחיר מוכנה למגורים בתל אביב עד 7000',
        run('דירה ראשונה עם תמורה טובה למחיר מוכנה למגורים בתל אביב עד 7000'));
    _show('17. קן ריק / downsizer — קטנה מרכזית נוחה בתל אביב',
        run('זוג מבוגר רוצה להקטין דירה קטנה ומרכזית ונוחה בתל אביב'));
    _show('18. שקט מרעש — רחוק מצירי תנועה בתל אביב',
        run('דירה שקטה רחוקה מכבישים ראשיים ורעש בתל אביב'));
    _show('19. קרוב לתחבורה — רכבת/רק"ל בתל אביב',
        run('דירה בתל אביב קרוב לרכבת ולרכבת קלה'));
    _show('20. שכונה ספציפית — פלורנטין תל אביב',
        run('דירה בפלורנטין תל אביב'));

    expect(true, true);
  });
}
