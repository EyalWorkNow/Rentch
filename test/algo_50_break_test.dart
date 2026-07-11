// Aggressive break-test: 50 personas in MESSY natural Hebrew (run-on, slang, no
// structure) run through the REAL engine with REAL gov data. Prints the top-3 per
// query for human critique — an eval harness, not pass/fail.
import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

RentalProperty lp({
  required String id, required int price, required double rooms, required int sizeM2,
  required String city, String hood = '', required double lat, required double lon,
  String floor = '3', List<String> features = const [], String cond = 'טוב',
  PropertyTransactionType tx = PropertyTransactionType.rent,
}) => RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: sizeM2, floor: floor,
      totalFloors: '8', city: city, neighborhood: hood, street: 'הרצל', streetNumber: 5,
      lat: lat, lon: lon, propertyType: 'דירה', entryDate: '', condition: cond,
      ownerName: 'x', agencyListing: false, features: features, transactionType: tx,
      media: const [PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)],
      marketSignals: const PropertyMarketSignals(views: 60, likes: 8, saves: 3));

List<RentalProperty> catalogue() => [
  // Tel Aviv — varied blocks/prices
  lp(id: 'tlv_center', price: 8500, rooms: 3, sizeM2: 75, city: 'תל אביב', hood: 'לב העיר', lat: 32.0700, lon: 34.7750, features: ['elevator','balcony','airConditioning']),
  lp(id: 'tlv_shapira', price: 4300, rooms: 2, sizeM2: 48, city: 'תל אביב', hood: 'שפירא', lat: 32.0545, lon: 34.7790, features: ['airConditioning']),
  lp(id: 'tlv_florentin', price: 5200, rooms: 2, sizeM2: 45, city: 'תל אביב', hood: 'פלורנטין', lat: 32.0560, lon: 34.7690, floor: '1', features: ['airConditioning','balcony']),
  lp(id: 'tlv_ramataviv', price: 10500, rooms: 4, sizeM2: 110, city: 'תל אביב', hood: 'רמת אביב', lat: 32.1130, lon: 34.8040, features: ['elevator','parking','mamad','balcony']),
  lp(id: 'tlv_studio', price: 3900, rooms: 1, sizeM2: 30, city: 'תל אביב', hood: 'הצפון הישן', lat: 32.0850, lon: 34.7810, floor: '4', features: ['airConditioning']),
  lp(id: 'tlv_penthouse', price: 21000, rooms: 5, sizeM2: 180, city: 'תל אביב', hood: 'רוטשילד', lat: 32.0650, lon: 34.7710, floor: '20', features: ['elevator','parking','pool','gym','balcony','mamad']),
  lp(id: 'tlv_share', price: 8000, rooms: 5, sizeM2: 130, city: 'תל אביב', hood: 'יד אליהו', lat: 32.0640, lon: 34.7930, features: ['balcony','airConditioning']),
  lp(id: 'tlv_ground', price: 6500, rooms: 3, sizeM2: 70, city: 'תל אביב', hood: 'בבלי', lat: 32.0950, lon: 34.7920, floor: '0', features: ['airConditioning','garden']),
  lp(id: 'tlv_wfh', price: 9000, rooms: 4, sizeM2: 120, city: 'תל אביב', hood: 'רמת החייל', lat: 32.1160, lon: 34.8380, features: ['elevator','parking','balcony','airConditioning'], cond: 'משופצת'),
  lp(id: 'tlv_dog', price: 6200, rooms: 3, sizeM2: 68, city: 'תל אביב', hood: 'נווה צדק', lat: 32.0620, lon: 34.7640, floor: '1', features: ['petsAllowed','garden','airConditioning']),
  lp(id: 'tlv_nearTAU', price: 5000, rooms: 2, sizeM2: 52, city: 'תל אביב', hood: 'רמת אביב', lat: 32.1120, lon: 34.8050, features: ['airConditioning']),
  // Bat Yam
  lp(id: 'by_beach', price: 6000, rooms: 3, sizeM2: 72, city: 'בת ים', lat: 32.0170, lon: 34.7440, features: ['elevator','balcony','airConditioning']),
  lp(id: 'by_fam', price: 5500, rooms: 4, sizeM2: 95, city: 'בת ים', lat: 32.0200, lon: 34.7480, features: ['elevator','mamad','parking']),
  // Jerusalem
  lp(id: 'jlm_center', price: 5800, rooms: 3, sizeM2: 70, city: 'ירושלים', hood: 'מרכז העיר', lat: 31.7810, lon: 35.2180, features: ['elevator','airConditioning']),
  lp(id: 'jlm_meashearim', price: 4800, rooms: 3, sizeM2: 68, city: 'ירושלים', hood: 'מאה שערים', lat: 31.7890, lon: 35.2200, features: ['airConditioning']),
  lp(id: 'jlm_rehavia', price: 7800, rooms: 3, sizeM2: 85, city: 'ירושלים', hood: 'רחביה', lat: 31.7720, lon: 35.2080, features: ['elevator','balcony']),
  lp(id: 'jlm_fam', price: 6500, rooms: 4, sizeM2: 100, city: 'ירושלים', hood: 'קרית יובל', lat: 31.7550, lon: 35.1850, features: ['elevator','mamad','parking']),
  // Beer Sheva (+sale)
  lp(id: 'bes_bgu', price: 2600, rooms: 3, sizeM2: 65, city: 'באר שבע', lat: 31.2620, lon: 34.8010, features: ['airConditioning']),
  lp(id: 'bes_cheap', price: 2100, rooms: 2, sizeM2: 55, city: 'באר שבע', lat: 31.2500, lon: 34.7900, features: []),
  lp(id: 'bes_sale', price: 1100000, rooms: 4, sizeM2: 95, city: 'באר שבע', lat: 31.2560, lon: 34.7980, tx: PropertyTransactionType.sale, features: ['parking','mamad']),
  lp(id: 'net_sale', price: 1650000, rooms: 4, sizeM2: 100, city: 'נתניה', lat: 32.3215, lon: 34.8532, tx: PropertyTransactionType.sale, features: ['elevator','parking','mamad','balcony']),
  // Herzliya / Ramat Gan / Bnei Brak / Rishon / Petah Tikva / Netanya / Haifa
  lp(id: 'herz', price: 7500, rooms: 4, sizeM2: 100, city: 'הרצליה', lat: 32.1660, lon: 34.8420, features: ['parking','balcony','mamad']),
  lp(id: 'rg_central', price: 6300, rooms: 3, sizeM2: 72, city: 'רמת גן', lat: 32.0853, lon: 34.8110, features: ['elevator','airConditioning']),
  lp(id: 'bb_relig', price: 5000, rooms: 4, sizeM2: 90, city: 'בני ברק', lat: 32.0830, lon: 34.8330, features: ['mamad','airConditioning']),
  lp(id: 'rish_fam', price: 5800, rooms: 4, sizeM2: 105, city: 'ראשון לציון', lat: 31.9730, lon: 34.7925, features: ['elevator','parking','mamad','balcony']),
  lp(id: 'pt_fam', price: 5500, rooms: 4, sizeM2: 105, city: 'פתח תקווה', lat: 32.0900, lon: 34.8870, features: ['elevator','parking','mamad','balcony']),
  lp(id: 'pt_small', price: 4200, rooms: 3, sizeM2: 68, city: 'פתח תקווה', lat: 32.0870, lon: 34.8850, features: ['airConditioning']),
  lp(id: 'net_beach', price: 5200, rooms: 3, sizeM2: 78, city: 'נתניה', lat: 32.3300, lon: 34.8560, features: ['elevator','balcony']),
  lp(id: 'haifa_carmel', price: 5000, rooms: 4, sizeM2: 100, city: 'חיפה', hood: 'כרמל', lat: 32.7900, lon: 34.9800, features: ['elevator','balcony','parking']),
  lp(id: 'haifa_center', price: 3200, rooms: 3, sizeM2: 70, city: 'חיפה', lat: 32.8100, lon: 34.9950, features: ['airConditioning']),
  lp(id: 'haifa_tech', price: 4500, rooms: 3, sizeM2: 75, city: 'חיפה', hood: 'נווה שאנן', lat: 32.7770, lon: 35.0230, features: ['elevator','parking']),
];

void _show(String label, List<Recommendation> recs) {
  final b = StringBuffer('\n■ $label\n');
  if (recs.isEmpty) { b.write('   (אין תוצאות)\n'); }
  for (var i = 0; i < recs.length && i < 3; i++) {
    final r = recs[i]; final p = r.property;
    final hi = r.highlights.take(2).join(' · ');
    final c = r.scorecard?.concerns.take(1).join('') ?? '';
    b.write('   #${i+1} ${p.id} | ${p.city}${p.neighborhood.isNotEmpty?'/${p.neighborhood}':''} | ₪${p.price} | ${p.rooms}ח | ${r.fitPct}% ${hi.isNotEmpty?'→ $hi':''}${c.isNotEmpty?'  ⚠$c':''}\n');
  }
  print(b.toString());
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: (p) => File(p).readAsString());
  });
  tearDownAll(() => GovData.instance.resetForTest());

  test('50 messy-language personas — print for critique', () {
    final cat = catalogue();
    List<Recommendation> run(String q) => RecommendationEngine.recommend(
        candidates: cat, query: SmartSearch.parse(q), limit: 3, explore: false);

    final qs = <String>[
      'אני ומירי מחפשים משהו קטן בתל אביב לא יותר מ6000 שיהיה קרוב לבילויים כי אנחנו יוצאים המון',
      'היי אז יש לי תקציב בערך 4500 אני לבד רוצה משהו ליד רכבת שאני יכול להגיע לעבודה',
      'משפחה עם 3 ילדים צריכים לפחות 4 חדרים באזור טוב עם בתי ספר טובים בפתח תקווה עד 8000',
      'אמא שלי מבוגרת צריכה דירה נגישה בלי מדרגות קרוב לקופת חולים בחיפה',
      'סטודנט שנה ראשונה בבן גוריון מחפש משהו ממש זול בבאר שבע קרוב לקמפוס',
      'אנחנו זוג דתי מחפשים בבני ברק קרוב לבית כנסת ושכונה שקטה 4 חדרים',
      'יש לי כלב לברדור גדול צריך דירה שמסכימה חיות ורצוי קומת קרקע עם גינה בתל אביב',
      'רוצה להשקיע בדירה שתביא תשואה טובה איפה הכי כדאי לקנות בפריפריה',
      'עברתי לגור לבד אחרי פרידה מחפש משהו קטן ונחמד במרכז בערך 5000',
      'בחורה בת 26 עובדת בהייטק בהרצליה רוצה משהו כיפי ותוסס לא רחוק מהעבודה',
      'זוג מבוגר בפנסיה רוצים משהו שקט ונוח בירושלים קרוב לשירותי בריאות',
      'סטודנטים 3 שותפים מחפשים דירה גדולה בתל אביב מחוברת לתחבורה',
      'משפחה חרדית עם המון ילדים צריכה 4 חדרים בבני ברק ליד בית כנסת',
      'אני עובד מהבית כל היום צריך חדר עבודה שקט ומרווח בתל אביב',
      'רוצה דירה על הים ממש קרוב לחוף בבת ים לא משנה כמה חדרים',
      'תקציב שלי מוגבל בטירוף מחפש הכי זול שיש בבאר שבע 2 חדרים',
      'אנחנו זוג צעיר בלי ילדים אוהבים לצאת ולבלות רוצים משהו במרכז תל אביב',
      'משפחה שרוצה לקנות דירה גדולה בנתניה קרוב לים להשקעה ולגור',
      'רווק שקט שאוהב טבע ופארקים מחפש משהו ירוק בתל אביב לא רועש',
      'צריך דירה עם ממד זה חובה בגלל המצב הביטחוני בראשון לציון 4 חדרים',
      'זוג עם תינוק בדרך מחפשים דירה בטוחה עם גן ילדים קרוב בפתח תקווה',
      'אני נכה בכיסא גלגלים חייב מעלית וקומה נמוכה נגיש לגמרי בחיפה',
      'סתם מחפש דירה יפה בתל אביב שיהיה נחמד לגור בה',
      'מהנדס שעובד באזור התעשייה של הרצליה רוצה לגור קרוב לעבודה',
      'זוג דתי מבוגר שקט קרוב לבית כנסת בירושלים 3 חדרים לא יקר',
      'סטודנטית באוניברסיטת תל אביב רוצה משהו קרוב לקמפוס וזול',
      'משפחה עם ילדים בתיכון רוצה שכונה טובה עם בתי ספר טובים בראשון',
      'אני אוהב לרוץ ולעשות ספורט רוצה דירה קרוב לפארק גדול בתל אביב',
      'רוצה פנטהאוז יוקרתי עם נוף מהמם בתל אביב הכסף לא בעיה',
      'זוג טרי שהתחתן מחפש דירה ראשונה נחמדה במחיר סביר במרכז',
      'אני מבשל המון ואוהב מסעדות ובתי קפה טובים רוצה אזור קולינרי בתל אביב',
      'משפחה חד הורית אמא עם 2 ילדים תקציב מוגבל צריכה משהו בטוח בפתח תקווה',
      'עולה חדש מצרפת לא מכיר טוב את הארץ רוצה משהו קהילתי ונחמד בנתניה',
      'זוג להטבים מחפש שכונה פתוחה ומקבלת בתל אביב קרוב לחיי לילה',
      'איש עסקים שטס הרבה רוצה משהו מרכזי קרוב לנתבג ולרכבת בלי כאב ראש',
      'סבתא שרוצה לגור קרוב לנכדים בראשון לציון משהו נגיש וקטן',
      'זוג צמחוני שאוהב אורח חיים בריא רוצה קרוב לשוק ולפארקים בתל אביב',
      'רוצה להשקיע בדירה לסטודנטים ליד אוניברסיטה שתמיד תהיה מושכרת',
      'משפחה שעוברת מארהב רוצה בית גדול באזור אנגלוסקסי בהרצליה',
      'צעיר בן 22 אחרי צבא עבודה ראשונה תקציב קטן רוצה משהו מגניב בתל אביב',
      'זוג שמתכנן ילדים בקרוב מחפש דירה עם פוטנציאל להתרחב בשכונה טובה',
      'אני חולה שצריך להיות קרוב לבית חולים גדול חשוב לי מאוד בתל אביב',
      'סטודנט לרפואה בטכניון בחיפה רוצה קרוב לקמפוס ולבית חולים',
      'משפחה מסורתית רוצה איזון בין דתי לחילוני שכונה מעורבת בפתח תקווה',
      'רווקה שאוהבת שקט אבל גם קצת חיים בסביבה בתל אביב תקציב 6000',
      'זוג שרוצה לחסוך כסף מחפש הכי משתלם שיש קרוב לתחבורה בפתח תקווה',
      'משפחה עם ילד עם צרכים מיוחדים צריכה נגישות ובית ספר מתאים בראשון',
      'איש דת רב שצריך לגור ליד בית כנסת גדול וקהילה בבני ברק',
      'זוג מבוגר שרוצה להקטין דירה קטנה ונוחה ומרכזית בתל אביב',
      'אני DJ שעובד בלילות רוצה לגור בלב הבילויים בתל אביב לא אכפת לי מרעש',
    ];
    for (var i = 0; i < qs.length; i++) {
      _show('${i + 1}. ${qs[i]}', run(qs[i]));
    }
    expect(qs.length, 50);
  });
}
