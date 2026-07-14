// Guards the mid-conversation CITY SWITCH semantics in SearchChatScreen: when a
// later turn names a different city, the old location context (city / hood /
// excluded-areas / accumulated rawText) is dropped while budget/rooms/amenity
// preferences carry over. Mirrors _merge / _prefsOnly / _cityKey in the screen.
import 'package:dating_app/core/search/smart_search.dart';
import 'package:flutter_test/flutter_test.dart';

// ── mirrors of the private screen helpers ──────────────────────────────────
SearchQuery merge(SearchQuery a, SearchQuery b) => SearchQuery(
      city: b.city ?? a.city,
      neighborhood: b.neighborhood ?? a.neighborhood,
      excludeAreas: {...a.excludeAreas, ...b.excludeAreas}.toList(),
      areaDir: b.areaDir ?? a.areaDir,
      minPrice: b.minPrice ?? a.minPrice,
      maxPrice: b.maxPrice ?? a.maxPrice,
      minRooms: b.minRooms ?? a.minRooms,
      maxRooms: b.maxRooms ?? a.maxRooms,
      propertyType: b.propertyType ?? a.propertyType,
      amenities: {...a.amenities, ...b.amenities},
      nearTrain: a.nearTrain || b.nearTrain,
      cheapPreference: a.cheapPreference || b.cheapPreference,
      rawText: '${a.rawText} ${b.rawText}'.trim(),
      intents: {...a.intents, ...b.intents},
      weights: {...a.weights, ...b.weights},
      requiredFeatures: {...a.requiredFeatures, ...b.requiredFeatures},
    );
String cityKey(String c) => c.split('-').first.split('(').first.trim();
SearchQuery prefsOnly(SearchQuery q) => SearchQuery(
      minPrice: q.minPrice, maxPrice: q.maxPrice,
      minRooms: q.minRooms, maxRooms: q.maxRooms,
      propertyType: q.propertyType, amenities: {...q.amenities},
      nearTrain: q.nearTrain, cheapPreference: q.cheapPreference,
      intents: {...q.intents}, weights: {...q.weights},
      requiredFeatures: {...q.requiredFeatures},
    );

// The screen's turn logic.
SearchQuery applyTurn(SearchQuery current, String text) {
  final parsed = SmartSearch.parse(text);
  if (parsed.city != null &&
      current.city != null &&
      cityKey(parsed.city!) != cityKey(current.city!)) {
    return merge(prefsOnly(current), parsed);
  }
  return merge(current, parsed);
}

void main() {
  test('naming a different city fully switches + drops old location', () {
    var q = applyTurn(SearchQuery(), 'דירה בתל אביב עד 8000 עם מרפסת');
    expect(q.city, contains('תל אביב'));
    q = applyTurn(q, 'בעצם תראה לי בחיפה'); // switch
    expect(cityKey(q.city!), 'חיפה', reason: 'city must switch to חיפה');
    expect(q.rawText.contains('תל אביב'), isFalse,
        reason: 'old city must NOT linger in rawText');
    expect(q.maxPrice, 8000, reason: 'budget preference carries over');
    expect(q.amenities, contains('feat_balcony'),
        reason: 'amenity preference carries over');
  });

  test('same-city refinement still accumulates (not a switch)', () {
    var q = applyTurn(SearchQuery(), 'דירה בתל אביב');
    q = applyTurn(q, 'עם ממ״ד וחניה'); // refine, no new city
    expect(cityKey(q.city!), 'תל אביב');
    expect(q.rawText.contains('תל אביב'), isTrue); // history kept within a city
  });

  test('"תל אביב" vs "תל אביב - יפו" is NOT a false switch', () {
    var q = applyTurn(SearchQuery(), 'דירה בתל אביב');
    final before = q.rawText;
    q = applyTurn(q, 'משהו בתל אביב יפו'); // same city, canonical variant
    expect(cityKey(q.city!), 'תל אביב');
    expect(q.rawText.length, greaterThan(before.length)); // accumulated, not reset
  });

  test('excluded areas from the old city do not leak into the new one', () {
    var q = applyTurn(SearchQuery(), 'תל אביב חוץ מפלורנטין');
    q = applyTurn(q, 'בוא ננסה חיפה');
    expect(cityKey(q.city!), 'חיפה');
    expect(q.excludeAreas.any((a) => a.contains('פלורנטין')), isFalse);
  });
}
