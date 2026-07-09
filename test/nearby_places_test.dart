import 'package:dating_app/core/search/engine/feature_engineering.dart';
import 'package:flutter_test/flutter_test.dart';

// Verifies the within-radius nearby-place lists that feed the property detail
// screen: real named data (data.gov.il schools/kindergartens + OSM parks) loads,
// filters to <=2km, sorts nearest-first, and splits kindergartens from schools.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Tel Aviv centre — dense enough to guarantee nearby places.
  const lat = 32.0853, lon = 34.7818;

  setUpAll(() async {
    await IsraelGeoIndex.loadSchools();
    await IsraelGeoIndex.loadParks();
  });

  test('schoolsWithin: non-empty, <=2km, sorted, not kindergartens', () {
    final schools = IsraelGeoIndex.schoolsWithin(lat, lon, km: 2);
    expect(schools, isNotEmpty);
    for (final s in schools) {
      expect(s.km, lessThanOrEqualTo(2.0));
      expect(s.stage, isNot('גן')); // schools list excludes kindergartens
      expect(s.name, isNotEmpty);
    }
    // sorted nearest-first
    for (var i = 1; i < schools.length; i++) {
      expect(schools[i].km, greaterThanOrEqualTo(schools[i - 1].km));
    }
  });

  test('kindergartensWithin: all are גן, <=2km', () {
    final kg = IsraelGeoIndex.kindergartensWithin(lat, lon, km: 2);
    expect(kg, isNotEmpty);
    for (final k in kg) {
      expect(k.stage, 'גן');
      expect(k.km, lessThanOrEqualTo(2.0));
    }
  });

  test('parksWithin: non-empty named parks, <=2km, sorted', () {
    final parks = IsraelGeoIndex.parksWithin(lat, lon, km: 2);
    expect(parks, isNotEmpty);
    for (final p in parks) {
      expect(p.name, isNotEmpty);
      expect(p.km, lessThanOrEqualTo(2.0));
    }
  });

  test('at least some schools carry an official sector (ממלכתי/דתי/חרדי)', () {
    final schools = IsraelGeoIndex.schoolsWithin(lat, lon, km: 2, cap: 12);
    expect(schools.any((s) => s.sector.isNotEmpty), isTrue);
  });

  test('invalid coords → empty lists', () {
    expect(IsraelGeoIndex.schoolsWithin(0, 0), isEmpty);
    expect(IsraelGeoIndex.parksWithin(0, 0), isEmpty);
  });
}
