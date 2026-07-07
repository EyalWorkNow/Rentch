import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/search_intent.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:flutter_test/flutter_test.dart';

// Area-mode ("אזור X") understanding + everyday city short-forms/abbreviations.
void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    try {
      await GovData.instance.init();
    } catch (_) {}
  });

  bool area(String t) =>
      SmartSearch.parse(t).intents.contains(SearchIntent.cityArea);
  String? city(String t) => SmartSearch.parse(t).city;

  group('area-mode "אזור X"', () {
    test('אזור <city> → cityArea (even with CBS-suffixed name)', () {
      expect(area('דירה באזור תל אביב'), isTrue); // resolves to תל אביב - יפו
      expect(area('משהו באזור פתח תקווה עד 5000'), isTrue);
      expect(area('אזור הרצליה'), isTrue);
      expect(area('דירה באיזור רמת גן'), isTrue);
      expect(area('פתח תקווה והסביבה'), isTrue);
    });

    test('"אזור שקט" (adjective, not a town) → NOT cityArea', () {
      expect(area('דירה באזור שקט בנתניה'), isFalse);
      expect(city('דירה באזור שקט בנתניה'), isNotNull); // still נתניה
    });
  });

  group('city short-forms / abbreviations', () {
    test('ראשון / רשל״צ → ראשון לציון', () {
      expect(city('דירה בראשון עד 5000'), 'ראשון לציון');
      expect(city('דירת 4 חדרים ברשל״צ'), 'ראשון לציון');
      expect(city('רשלצ דירה'), 'ראשון לציון');
    });

    test('quote abbreviations', () {
      expect(city('דירה בפ״ת'), 'פתח תקווה');
      expect(city('משהו בר״ג'), 'רמת גן');
      expect(city('דירה בב״ש'), 'באר שבע');
      expect(city('דירה בכ״ס'), 'כפר סבא');
      expect(city('דירה בי״ם'), 'ירושלים');
    });

    test('"יום ראשון" (Sunday) must NOT become ראשון לציון', () {
      // Entry on Sunday, city is Netanya — the day word must be left alone.
      expect(city('דירה בנתניה כניסה ביום ראשון'), 'נתניה');
    });

    test('"ראשון לציון" full stays intact', () {
      expect(city('דירה בראשון לציון'), 'ראשון לציון');
    });
  });
}
