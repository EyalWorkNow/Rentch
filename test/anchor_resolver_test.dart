import 'package:dating_app/core/search/anchor_resolver.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:flutter_test/flutter_test.dart';

// "לא רחוק מ-X": named-anchor resolution — hospitals by household name,
// universities with aliases, radius phrasing, and non-anchors staying null.
void main() {
  test('resolves major hospitals by household name', () {
    final a = AnchorResolver.resolve('מחפש דירה לא רחוק מאיכילוב');
    expect(a, isNotNull);
    expect(a!.name, 'איכילוב');
    expect(a.kindLabel, 'בית חולים');
    expect(a.radiusKm, 4.0);
    // Tel Aviv center-ish coords.
    expect(a.lat, closeTo(32.08, 0.05));

    expect(AnchorResolver.resolve('קרוב לתל השומר')!.name, 'שיבא תל השומר');
    expect(AnchorResolver.resolve('ליד רמב"ם')!.name, 'רמב"ם');
    expect(AnchorResolver.resolve('בקרבת בית חולים סורוקה')!.name, 'סורוקה');
  });

  test('resolves universities incl. full names and aliases', () {
    final a = AnchorResolver.resolve('דירה קרוב לאוניברסיטת תל אביב');
    expect(a, isNotNull);
    expect(a!.kindLabel, 'אוניברסיטה');
    expect(a.radiusKm, 3.0);

    expect(AnchorResolver.resolve('לא רחוק מהטכניון'), isNotNull);
    expect(AnchorResolver.resolve('ליד רייכמן')!.name, 'אוניברסיטת רייכמן');
    expect(AnchorResolver.resolve('קרוב לבן גוריון')!.name,
        'אוניברסיטת בן גוריון');
  });

  test('explicit radius and walking phrases override the default', () {
    expect(AnchorResolver.resolve('עד 2 ק"מ מאיכילוב, לא רחוק מאיכילוב')!
        .radiusKm, 2.0);
    expect(AnchorResolver.resolve('במרחק הליכה מהטכניון')!.radiusKm, 1.2);
  });

  test('generic nears and unknown names resolve to null', () {
    expect(AnchorResolver.resolve('דירה ליד הים'), isNull);
    expect(AnchorResolver.resolve('קרוב לפארק גדול'), isNull);
    expect(AnchorResolver.resolve('דירה בתל אביב עד 6000'), isNull);
    expect(AnchorResolver.resolve('לא רחוק ממקום כלשהו לא קיים'), isNull);
  });

  test('name tail stops at clause boundaries', () {
    final a =
        AnchorResolver.resolve('לא רחוק מאיכילוב עם מרפסת ועד 7000 שקל');
    expect(a, isNotNull);
    expect(a!.name, 'איכילוב');
  });

  test('resolveNamed handles the assistant near_place path', () {
    expect(AnchorResolver.resolveNamed('שיבא')!.name, 'שיבא תל השומר');
    expect(AnchorResolver.resolveNamed(''), isNull);
  });

  test('SmartSearch.parse carries the anchor into the query', () {
    final q = SmartSearch.parse('דירת 3 חדרים לא רחוק מבילינסון עד 6000');
    expect(q.anchor, isNotNull);
    expect(q.anchor!.name, 'בילינסון');
    expect(q.maxPrice, 6000);
    // copyWith keeps it (used by what-if mutators).
    expect(q.copyWith(maxPrice: 7000).anchor!.name, 'בילינסון');
  });
}
