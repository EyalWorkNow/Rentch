import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:flutter_test/flutter_test.dart';

// The named + typed school proximity, named parks, named rail stations, and the
// age → school-type intents — verified against real bundled data.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await GovData.instance.init();
    } catch (_) {}
    await IsraelGeoIndex.loadParks();
    await IsraelGeoIndex.loadSchools();
  });

  test('nearestRailStation returns a NAMED station', () {
    final st = GovData.instance.nearestRailStation(32.0836, 34.7980);
    expect(st, isNotNull);
    expect(st!.name.trim(), isNotEmpty);
    // ignore: avoid_print
    print('TLV nearest station: ${st.name} ${(st.km * 1000).round()}m');
  });

  test('age cue → young/teen school intent', () {
    expect(SearchIntent.fromText('משפחה עם תינוק בתל אביב')
        .contains(SearchIntent.youngChildren), isTrue);
    expect(SearchIntent.fromText('משפחה עם ילדים מתבגרים בפתח תקווה')
        .contains(SearchIntent.teens), isTrue);
  });

  test("type 'יסודי' includes generic 'בית ספר'", () {
    final y = IsraelGeoIndex.nearestSchool(32.0809, 34.7806, type: 'יסודי');
    expect(y, isNotNull); // would be null if only 106 explicit יסודי matched
  });

  test('nearestSchool returns a REAL named school near Tel Aviv centre', () {
    final s = IsraelGeoIndex.nearestSchool(32.0809, 34.7806);
    expect(s, isNotNull);
    expect(s!.name.trim(), isNotEmpty);
    expect(s.km, lessThan(3.0)); // there's a school within a few km of TLV centre
    // ignore: avoid_print
    print('TLV nearest school: ${s.name} (${s.type}) ${(s.km * 1000).round()}m');
  });

  test('nearestSchool can filter by TYPE (גן / תיכון)', () {
    final gan = IsraelGeoIndex.nearestSchool(32.0809, 34.7806, type: 'גן');
    expect(gan, isNotNull);
    expect(gan!.type, 'גן');
    final tichon = IsraelGeoIndex.nearestSchool(32.0809, 34.7806, type: 'תיכון');
    expect(tichon, isNotNull);
    expect(tichon!.type, 'תיכון');
  });

  test('nearestParkName returns a real park', () {
    final n = IsraelGeoIndex.nearestParkName(31.7774, 35.2186); // near גן העצמאות
    expect(n, isNotNull);
    expect(n!.trim(), isNotEmpty);
  });
}
