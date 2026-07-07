import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:dating_app/core/search/engine/recommendation_orchestrator.dart';
import 'package:dating_app/data/models/rental_models.dart';
import 'package:flutter_test/flutter_test.dart';

// ─────────────────────────────────────────────────────────────────────────────
// "BREAK IT" — adversarial, everyday, weird natural language. Goal: crash the
// parser, make it hallucinate a city/budget, or return nonsense. Each query runs
// through the REAL pipeline; we assert NO crash and flag suspicious parses.
// ─────────────────────────────────────────────────────────────────────────────

RentalProperty p(String id, String city, double lat, double lon,
        {int price = 4000, double rooms = 3}) =>
    RentalProperty(
      id: id, price: price, rooms: rooms, sizeM2: 70, floor: '2',
      totalFloors: '5', city: city, neighborhood: '', street: 'x',
      streetNumber: 1, lat: lat, lon: lon, propertyType: 'דירה',
      transactionType: PropertyTransactionType.rent, entryDate: '',
      condition: 'טוב', ownerName: 'o', agencyListing: false,
      features: const ['ac'],
      media: const [
        PropertyMedia(url: 'http://x/a.jpg', type: PropertyMediaType.image)
      ],
      marketSignals: const PropertyMarketSignals(views: 5, likes: 1, saves: 0),
    );

final _cat = [
  p('tlv', 'תל אביב', 32.0809, 34.7806, price: 5000, rooms: 3),
  p('tlv2', 'תל אביב', 32.0700, 34.7750, price: 3000, rooms: 2),
  p('rg', 'רמת גן', 32.0700, 34.8240, price: 4500, rooms: 3),
  p('giv', 'גבעתיים', 32.0720, 34.8120, price: 5000, rooms: 3),
  p('ptk', 'פתח תקווה', 32.0840, 34.8878, price: 4000, rooms: 3),
  p('bs', 'באר שבע', 31.2520, 34.7915, price: 2000, rooms: 3),
  p('hai', 'חיפה', 32.7940, 34.9896, price: 3200, rooms: 3),
  p('net', 'נתניה', 32.3215, 34.8532, price: 4200, rooms: 3),
  p('had', 'חדרה', 32.4340, 34.9196, price: 3500, rooms: 3),
  p('ris', 'ראשון לציון', 31.9730, 34.7925, price: 4800, rooms: 4),
];

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await GovData.instance.init();
    } catch (_) {}
  });

  SearchQuery parseSafe(String t) => SmartSearch.parse(t);

  void probe(String label, String text, {void Function(SearchQuery q)? check}) {
    test(label, () {
      late SearchQuery q;
      // 1) Must not throw on ANY input.
      expect(() => q = parseSafe(text), returnsNormally,
          reason: 'parse threw on: "$text"');
      // 2) The engine must not throw either.
      late List<ScoredProperty> res;
      expect(
          () => res = RecommendationEngine.recommendAsScored(
              candidates: _cat, query: q, limit: 5, seed: 3),
          returnsNormally,
          reason: 'engine threw on: "$text"');
      // ignore: avoid_print
      print('\n══ $label\n   "$text"\n   → city=${q.city} budget=${q.maxPrice} '
          'rooms=${q.minRooms}${q.maxRooms != null ? '-${q.maxRooms}' : ''} '
          'intents=${q.intents} req=${q.requiredFeatures} '
          '| results=${res.length}${res.isEmpty ? '' : ' top=${res.first.property.city}/₪${res.first.property.price}'}');
      if (check != null) check(q);
    });
  }

  // 1. "my area" — must NOT hallucinate a city (needs GPS).
  probe('B01 · my area', 'תמצא לי דירה באזור שלי', check: (q) {
    expect(q.city, isNull, reason: '"אזור שלי" must not resolve to a city');
  });

  // 2. cheap BUT luxurious, impossible budget.
  probe('B02 · contradiction', 'דירה זולה אבל מפוארת ויוקרתית בתל אביב עד 2000');

  // 3. mansion for pocket change.
  probe('B03 · impossible', 'וילה ענקית עם בריכה בהרצליה פיתוח ב1500 שקל בחודש');

  // 4. negations.
  probe('B04 · negations',
      'דירה בתל אביב בלי קומה גבוהה, לא ליד כביש רועש, ובלי שכנים מעצבנים',
      check: (q) {
    expect(q.intents.contains('view'), isFalse,
        reason: '"בלי קומה גבוהה" must NOT add a high-floor/view intent');
  });

  // 5. OR-cities.
  probe('B05 · or-cities', 'משהו בתל אביב או בגבעתיים עד 5000');

  // 6. vague / emotional — no concrete filter.
  probe('B06 · emotional',
      'אני רק רוצה מקום שקט שירגיע אותי אחרי יום עבודה ארוך', check: (q) {
    expect(q.city, isNull);
  });

  // 7. fuzzy slang budget.
  probe('B07 · fuzzy budget', 'תמצא לי משהו בראשון בסביבות ה4 אולי 4 וחצי');

  // 8. spelled-out big number.
  probe('B08 · spelled number', 'דירת שלושה חדרים בחיפה בשלושת אלפים שקל');

  // 9. question form.
  probe('B09 · question', 'יש לך אולי משהו קטן וזול בבאר שבע לסטודנט?');

  // 10. rambling paragraph.
  probe('B10 · rambling',
      'אז ככה, אני ומירי חשבנו אולי לעבור לפתח תקווה כי אמא שלה גרה שם ויש '
      'גן ילדים טוב ליד, תקציב בערך 4000 אולי טיפה יותר, חשוב מרפסת בגלל הכלב, '
      'ולא גבוה מדי כי אני לא אוהב מעליות');

  // 11. typo (מזגן → מזוג).
  probe('B11 · typo', 'דירה בנתניה עם מרפסת גדולה ומזוג ונוף לים עד 6000');

  // 12. emoji.
  probe('B12 · emoji', 'דירה על הים בנתניה 🏖️🌊 עד 6000 😍🔥');

  // 13. mixed English.
  probe('B13 · english', 'apartment in tel aviv, cheap, near the beach, max 4000');

  // 14. gibberish + a real keyword.
  probe('B14 · gibberish', 'אבגדהוזח קוקוריקו דירה בחדרה', check: (q) {
    expect(q.city, 'חדרה', reason: 'should still find חדרה amid gibberish');
  });

  // 15. bare city.
  probe('B15 · bare city', 'חדרה', check: (q) {
    expect(q.city, isNotNull);
  });

  // 16. bare number.
  probe('B16 · bare number', '5000');

  // 17. sarcasm about salary.
  probe('B17 · sarcasm', 'משהו שלא יעלה לי את כל המשכורת בתל אביב');

  // 18. superlative.
  probe('B18 · superlative', 'הכי זול שיש בפתח תקווה');

  // 19. politeness noise.
  probe('B19 · politeness', 'בבקשה תמצאי לי דירה נחמדה ומוארת ברמת גן, תודה רבה!!!');

  // 20. contradictory room range.
  probe('B20 · contradictory rooms', 'דירת 2 או 5 חדרים בגבעתיים');

  // 21. empty / whitespace.
  probe('B21 · empty', '   ');

  // 22. only emoji.
  probe('B22 · only emoji', '🏠🔑😍');
}
