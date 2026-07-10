import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// The geo "why" chips must ALWAYS be relevant to the search: each persona names a
// need, and only the matching lifestyle chips may appear — never the others.
//
// Geo emojis: 🏫 school · 🌳 park · 🏖️ sea · 🎓 university · 🍸 nightlife.

RentalProperty tlvFlat(String id, double rooms, int price, double dLat) =>
    RentalProperty(
      id: id, price: price, rooms: rooms,
      sizeM2: (55 + rooms * 12).toInt(), floor: '2',
      totalFloors: '6', city: 'תל אביב', neighborhood: '', street: 'דיזנגוף',
      streetNumber: 100, lat: 32.078 + dLat, lon: 34.774, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'o', agencyListing: false, features: const [],
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
    );

class _Persona {
  const _Persona(this.name, this.query, this.forbid, [this.require = '']);
  final String name;
  final String query;
  final List<String> forbid; // geo emojis that must NOT appear
  final String require; // a geo emoji that MUST appear (empty = skip)
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await GovData.instance.init();
    } catch (_) {}
    await IsraelGeoIndex.loadParks();
    await IsraelGeoIndex.loadSchools();
    await IsraelGeoIndex.loadNightlife();
  });

  // Mixed stock (2–4 rooms) in central TLV — near schools, bars, ~1.4km from sea.
  final cat = [
    tlvFlat('a', 2.0, 5000, 0.000),
    tlvFlat('b', 2.0, 5500, 0.002),
    tlvFlat('c', 3.0, 6000, 0.004),
    tlvFlat('d', 3.0, 6500, 0.006),
    tlvFlat('e', 4.0, 7000, 0.008),
    tlvFlat('f', 4.0, 7500, 0.010),
  ];

  List<String> tagsFor(String text) {
    final q = SmartSearch.parse(text);
    final res = RecommendationEngine.recommendAsScored(
        candidates: cat, query: q, limit: 10, seed: 7);
    return [for (final s in res) ...s.tags];
  }

  const personas = [
    _Persona('חיי לילה', 'אזור צעיר עם ברים ומסעדות בתל אביב עד 8000',
        ['🏫', '🎓', '🏖️'], '🍸'),
    _Persona('משפחה', 'דירה למשפחה עם ילדים בתל אביב עד 9000',
        ['🍸', '🎓', '🏖️'], '🏫'),
    _Persona('משפחה עם תינוק', 'משפחה עם תינוק בתל אביב עד 9000',
        ['🍸', '🎓', '🏖️'], '🏫'),
    _Persona('משפחה עם מתבגרים', 'משפחה עם ילדים מתבגרים בתל אביב עד 9000',
        ['🍸', '🎓', '🏖️'], '🏫'),
    _Persona('סטודנט', 'סטודנט מחפש דירה ליד האוניברסיטה בתל אביב',
        ['🏫', '🍸', '🏖️']),
    _Persona('חוף ים', 'דירה קרוב לים בתל אביב עד 9000', ['🏫', '🎓', '🍸']),
    _Persona('זוג מבוגר שקט', 'זוג מבוגר מחפש דירה שקטה בתל אביב עד 9000',
        ['🏫', '🍸', '🎓', '🏖️']),
    _Persona('השקעה', 'דירה להשקעה בתל אביב עד 9000',
        ['🏫', '🍸', '🎓', '🏖️']),
    _Persona('שותפים', 'דירה לשותפים בתל אביב עד 8000', ['🏫', '🏖️', '🎓']),
    _Persona('ניטרלי', 'דירת 3 חדרים בתל אביב עד 8000',
        ['🏫', '🍸', '🎓', '🏖️']),
    // ── combinations: two intents must BOTH gate in, others stay out ──
    _Persona('משפחה קרוב לים', 'משפחה עם ילדים שרוצה לגור קרוב לים בתל אביב עד 9000',
        ['🍸', '🎓'], '🏖️'),
    _Persona('זוג צעיר יוצא לברים', 'זוג צעיר שאוהב לצאת לברים ופאבים בתל אביב עד 8000',
        ['🏫', '🎓', '🏖️'], '🍸'),
    _Persona('סטודנט חיי לילה', 'סטודנט שאוהב חיי לילה ליד הקמפוס בתל אביב',
        ['🏫', '🏖️'], '🍸'),
    _Persona('ליד האוניברסיטה', 'דירה ליד אוניברסיטת תל אביב עד 9000',
        ['🏫', '🍸', '🏖️']),
    _Persona('משפחה דתית', 'משפחה דתית שומרת שבת בתל אביב עד 9000',
        ['🍸', '🎓', '🏖️'], '🏫'),
    // ── traps: text mentions a trigger word but the intent must NOT fire ──
    // "ילדים" appears, but empty-nesters downsizing → never a school chip.
    _Persona('קן ריק', 'זוג מבוגר שהילדים עזבו מחפש דירה קטנה בתל אביב עד 9000',
        ['🏫', '🍸', '🎓', '🏖️']),
    // Negated sea reference must not sea-gate the search.
    _Persona('לא ליד הים', 'דירה שקטה בתל אביב, לא ליד הים, עד 9000',
        ['🏫', '🍸', '🎓', '🏖️']),
    // WFH — a lifestyle need with no geo chip at all.
    _Persona('עבודה מהבית', 'דירה עם חדר עבודה לעובד מהבית בתל אביב עד 9000',
        ['🏫', '🍸', '🎓', '🏖️']),
  ];

  for (final p in personas) {
    test('${p.name}: only relevant chips', () {
      final tags = tagsFor(p.query);
      final joined = tags.join(' | ');
      for (final f in p.forbid) {
        expect(tags.any((t) => t.contains(f)), isFalse,
            reason: '[${p.name}] must NOT show "$f" — got: $joined');
      }
      if (p.require.isNotEmpty) {
        expect(tags.any((t) => t.contains(p.require)), isTrue,
            reason: '[${p.name}] expected "${p.require}" — got: $joined');
      }
    });
  }
}
