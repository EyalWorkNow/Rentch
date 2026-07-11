// Round 2 aggressive break-test: ADVERSARIAL inputs — contradictions, typos,
// extreme values, ambiguous/region names, heavy constraint-stacking, negations,
// and vague/emotional queries. Prints top-3 for critique + asserts the engine
// never crashes / dead-ends unexpectedly.
import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

RentalProperty lp({required String id, required int price, required double rooms, int sizeM2 = 70,
  required String city, String hood = '', required double lat, required double lon, String floor = '3',
  List<String> features = const [], PropertyTransactionType tx = PropertyTransactionType.rent}) =>
    RentalProperty(id: id, price: price, rooms: rooms, sizeM2: sizeM2, floor: floor, totalFloors: '8',
        city: city, neighborhood: hood, street: 'הרצל', streetNumber: 5, lat: lat, lon: lon,
        propertyType: 'דירה', entryDate: '', condition: 'טוב', ownerName: 'x', agencyListing: false,
        features: features, transactionType: tx,
        media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
        marketSignals: const PropertyMarketSignals(views: 60, likes: 8, saves: 3));

List<RentalProperty> catalogue() => [
  lp(id: 'tlv_center', price: 8500, rooms: 3, city: 'תל אביב', hood: 'לב העיר', lat: 32.0700, lon: 34.7750, features: ['elevator','balcony']),
  lp(id: 'tlv_florentin', price: 5200, rooms: 2, city: 'תל אביב', hood: 'פלורנטין', lat: 32.0560, lon: 34.7690, floor: '1'),
  lp(id: 'tlv_studio', price: 3900, rooms: 1, sizeM2: 30, city: 'תל אביב', lat: 32.0850, lon: 34.7810, floor: '4'),
  lp(id: 'tlv_penthouse', price: 21000, rooms: 5, sizeM2: 180, city: 'תל אביב', hood: 'רוטשילד', lat: 32.0650, lon: 34.7710, floor: '20', features: ['elevator','pool','gym','mamad']),
  lp(id: 'tlv_fam', price: 10000, rooms: 4, sizeM2: 110, city: 'תל אביב', hood: 'רמת אביב', lat: 32.1130, lon: 34.8040, features: ['elevator','parking','mamad']),
  lp(id: 'tlv_low', price: 6200, rooms: 3, city: 'תל אביב', hood: 'נווה צדק', lat: 32.0620, lon: 34.7640, floor: '1', features: ['petsAllowed','garden']),
  lp(id: 'jlm_center', price: 5800, rooms: 3, city: 'ירושלים', lat: 31.7810, lon: 35.2180, features: ['elevator']),
  lp(id: 'jlm_relig', price: 4800, rooms: 4, city: 'ירושלים', hood: 'מאה שערים', lat: 31.7890, lon: 35.2200),
  lp(id: 'haifa', price: 3200, rooms: 3, city: 'חיפה', lat: 32.8100, lon: 34.9950),
  lp(id: 'haifa_carmel', price: 5000, rooms: 4, city: 'חיפה', hood: 'כרמל', lat: 32.7900, lon: 34.9800, features: ['elevator','parking']),
  lp(id: 'bes_cheap', price: 2100, rooms: 2, city: 'באר שבע', lat: 31.2500, lon: 34.7900),
  lp(id: 'bes_sale', price: 1100000, rooms: 4, city: 'באר שבע', lat: 31.2560, lon: 34.7980, tx: PropertyTransactionType.sale, features: ['mamad']),
  lp(id: 'pt_fam', price: 5500, rooms: 4, sizeM2: 105, city: 'פתח תקווה', lat: 32.0900, lon: 34.8870, features: ['elevator','parking','mamad','balcony']),
  lp(id: 'bb_relig', price: 5000, rooms: 4, city: 'בני ברק', lat: 32.0830, lon: 34.8330, features: ['mamad']),
  lp(id: 'rg', price: 6300, rooms: 3, city: 'רמת גן', lat: 32.0853, lon: 34.8110, features: ['elevator']),
  lp(id: 'herz', price: 7500, rooms: 4, city: 'הרצליה', lat: 32.1660, lon: 34.8420, features: ['parking','mamad']),
  lp(id: 'by_beach', price: 6000, rooms: 3, city: 'בת ים', lat: 32.0170, lon: 34.7440, features: ['elevator','balcony']),
  lp(id: 'net', price: 5200, rooms: 3, city: 'נתניה', lat: 32.3215, lon: 34.8532, features: ['elevator']),
  lp(id: 'pardes', price: 4000, rooms: 4, city: 'פרדס חנה כרכור', lat: 32.4700, lon: 34.9700),
  lp(id: 'yafo', price: 5500, rooms: 3, city: 'תל אביב', hood: 'יפו', lat: 32.0500, lon: 34.7550, features: ['balcony']),
];

void _show(String label, List<Recommendation> recs) {
  final b = StringBuffer('\n▸ $label\n');
  if (recs.isEmpty) { b.write('   (אין תוצאות)\n'); }
  for (var i = 0; i < recs.length && i < 3; i++) {
    final r = recs[i]; final p = r.property;
    b.write('   #${i+1} ${p.id}|${p.city}|₪${p.price}|${p.rooms}ח|${r.fitPct}% ${r.highlights.take(1).join()}\n');
  }
  print(b.toString());
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: (p) => File(p).readAsString());
  });
  tearDownAll(() => GovData.instance.resetForTest());

  test('35 adversarial inputs — no crash, print for critique', () {
    final cat = catalogue();
    List<Recommendation> run(String q) => RecommendationEngine.recommend(
        candidates: cat, query: SmartSearch.parse(q), limit: 3, explore: false);

    final qs = <String>[
      // contradictions
      'רוצה דירה שקטה אבל גם קרוב לכל הבילויים והמסיבות בתל אביב',
      'תקציב של 3000 אבל אני רוצה פנטהאוז יוקרתי עם בריכה בתל אביב',
      'משפחה גדולה עם 5 ילדים אבל דירה קטנה וזולה בתל אביב',
      'דירה במרכז תל אביב הכי זול שיש אבל שתהיה מפוארת',
      'רוצה גם קרוב לים וגם באזור שקט מבודד בתל אביב',
      // typos / malformed
      'דירה בתא אביב 3 חדרים עד 8000',
      'דירה בירשלים 3 חדרים',
      '3 חדרים בחיפא עד 4000',
      'apartment in tel aviv 3 rooms up to 8000',
      'דירה בבאר שבע 2חד עד 2500 ליד הקמפוס דחוף!!!',
      'צריךךך דירהה בתל אביב 3 חדרים',
      // extreme values
      'דירה בתל אביב עד 100 שקל',
      'דירה בתל אביב עד 500000 בחודש',
      'דירה עם 20 חדרים בתל אביב',
      'דירה בתל אביב עד 0',
      // ambiguous / region / rare
      'דירה ביפו 3 חדרים',
      'דירה בפרדס חנה 4 חדרים',
      'משהו בשרון עד 6000',
      'דירה בעיר גדולה',
      'משהו איפשהו שיהיה בסדר',
      // heavy stacking
      'משפחה דתית עם 4 ילדים וכלב צריכה 5 חדרים ממד מעלית חניה מרפסת בפתח תקווה עד 7000 קרוב לבית ספר ובית כנסת',
      'רווק צמחוני שעובד מהבית אוהב ספורט וטבע רוצה שקט אבל קרוב לעיר בתל אביב עד 5000',
      'זוג דתי מבוגר עם בעיות ניידות רוצה נגישות שקט וקרוב לבית כנסת ולבית חולים בירושלים',
      // vague / emotional
      'אני פשוט רוצה בית שארגיש בו טוב',
      'משהו שיתאים לי בבקשה',
      'עזרו לי אני לא יודע מה אני מחפש',
      'דירה יפה',
      // negations
      'דירה בתל אביב אבל לא בדרום ולא ליד רעש',
      'לא רוצה קומה גבוהה בתל אביב 3 חדרים',
      'משהו שלא יקר בתל אביב',
      // mixed / numbers
      'דירה בתל אביב בין 5000 ל 7000 3-4 חדרים עם מרפסת וחניה',
      'תלת חדר בתל אביב עד ששת אלפים',
      'דירה 2.5 חדרים בתל אביב',
      'דירה בתל אביב מיידי דחוף חייב להיכנס מחר',
      'זוג צעיר תל אביב תקציב פתוח מה שהכי טוב',
    ];
    var crashes = 0, empties = 0;
    for (var i = 0; i < qs.length; i++) {
      List<Recommendation> r;
      try { r = run(qs[i]); } catch (e) { crashes++; print('✗ CRASH #${i+1}: $e'); continue; }
      if (r.isEmpty) empties++;
      _show('${i + 1}. ${qs[i]}', r);
      for (final rec in r) {
        expect(rec.fitPct, inInclusiveRange(0, 100), reason: 'q${i+1} OOB fit');
      }
    }
    print('\n=== crashes: $crashes · empties: $empties / ${qs.length} ===');
    expect(crashes, 0);
  });
}
