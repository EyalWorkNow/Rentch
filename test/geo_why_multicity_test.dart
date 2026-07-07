import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// My own persona sweep — checks the geo "why" tags across MULTIPLE cities (not
// just Tel Aviv) and adversarial intent mixes, to prove the calibration + intent
// gating hold up in the real pipeline.

RentalProperty flat(String id, String city, double lat, double lon,
        {double rooms = 3, int price = 6500}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms,
      sizeM2: (55 + rooms * 12).toInt(), floor: '3', totalFloors: '7',
      city: city, neighborhood: '', street: 'הרצל', streetNumber: 10,
      lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'o', agencyListing: false, features: const [],
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
    );

// Small stock clustered around a centre point (jittered), so the engine has a
// market context and several candidates.
List<RentalProperty> stock(String city, double lat, double lon) => [
      for (var i = 0; i < 6; i++)
        flat('$city$i', city, lat + (i - 3) * 0.0015, lon + (i - 3) * 0.0012,
            rooms: 2.0 + (i % 3), price: 5500 + i * 400),
    ];

const GEO = ['🏫', '🌳', '🏖️', '🎓', '🍸'];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try { await GovData.instance.init(); } catch (_) {}
    await IsraelGeoIndex.loadParks();
    await IsraelGeoIndex.loadSchools();
    await IsraelGeoIndex.loadNightlife();
  });

  List<String> tagsFor(String query, List<RentalProperty> cat) {
    final q = SmartSearch.parse(query);
    final res = RecommendationEngine.recommendAsScored(
        candidates: cat, query: q, limit: 10, seed: 7);
    final tags = <String>[];
    for (final s in res) {
      tags.addAll(s.tags);
    }
    return tags;
  }

  bool has(List<String> tags, String emoji) =>
      tags.any((t) => t.contains(emoji));

  // (name, city, lat, lon, query, forbid[], require '')
  final cases = <List>[
    // Nightlife across DIFFERENT cities — the calibration fix must generalise.
    ['נייטלייף הרצליה', 'הרצליה', 32.1621, 34.8410,
      'דירה בהרצליה באיזור עם ברים ומסעדות', ['🏫', '🎓', '🏖️'], '🍸'],
    ['נייטלייף רעננה', 'רעננה', 32.1848, 34.8713,
      'דירה ברעננה באזור תוסס עם פאבים ובתי קפה', ['🏫', '🎓', '🏖️'], '🍸'],
    ['נייטלייף באר שבע', 'באר שבע', 31.2530, 34.7915,
      'דירה בבאר שבע באזור צעיר עם חיי לילה', ['🏫', '🎓', '🏖️'], ''],
    ['נייטלייף תל אביב', 'תל אביב', 32.0791, 34.7681,
      'דירה בתל אביב עם ברים ומסעדות', ['🏫', '🎓', '🏖️'], '🍸'],
    // Family — schools, never nightlife/sea.
    ['משפחה חיפה', 'חיפה', 32.7940, 34.9896,
      'דירה למשפחה עם ילדים בחיפה', ['🍸', '🎓', '🏖️'], ''],
    ['משפחה תינוק פ"ת', 'פתח תקווה', 32.0840, 34.8878,
      'משפחה עם תינוק בפתח תקווה', ['🍸', '🎓', '🏖️'], ''],
    // Sea — only the beach chip.
    ['חוף נתניה', 'נתניה', 32.3215, 34.8532,
      'דירה בנתניה קרוב לים', ['🏫', '🎓', '🍸'], ''],
    // Student — campus, never schools/nightlife.
    ['סטודנט ת"א', 'תל אביב', 32.1133, 34.8044,
      'סטודנט מחפש דירה ליד האוניברסיטה בתל אביב', ['🏫', '🍸', '🏖️'], ''],
    // Quiet retiree — no lifestyle geo chips at all.
    ['זוג מבוגר שקט', 'רמת גן', 32.0684, 34.8248,
      'זוג מבוגר מחפש דירה שקטה ברמת גן', ['🏫', '🍸', '🎓', '🏖️'], ''],
    // Adversarial: negation — "בלי ברים" must NOT fire nightlife.
    ['שלילת נייטלייף', 'תל אביב', 32.0791, 34.7681,
      'דירה שקטה בתל אביב בלי ברים ורעש', ['🍸', '🎓', '🏖️'], ''],
    // Neutral — no lifestyle intent → no geo lifestyle chips.
    ['ניטרלי', 'תל אביב', 32.0791, 34.7681,
      'דירת 3 חדרים בתל אביב עד 8000', ['🏫', '🍸', '🎓', '🏖️'], ''],
  ];

  for (final c in cases) {
    final name = c[0] as String;
    final city = c[1] as String;
    final lat = c[2] as double;
    final lon = c[3] as double;
    final query = c[4] as String;
    final forbid = (c[5] as List).cast<String>();
    final require = c[6] as String;

    test(name, () {
      final tags = tagsFor(query, stock(city, lat, lon));
      final geo = tags.where((t) => GEO.any(t.contains)).toList();
      // ignore: avoid_print
      print('[$name] geo tags: ${geo.isEmpty ? "(none)" : geo.toSet().join(" | ")}');
      for (final f in forbid) {
        expect(has(tags, f), isFalse,
            reason: '[$name] must NOT show "$f" — geo: ${geo.join(" | ")}');
      }
      if (require.isNotEmpty) {
        expect(has(tags, require), isTrue,
            reason: '[$name] expected "$require" — geo: ${geo.join(" | ")}');
      }
    });
  }
}
