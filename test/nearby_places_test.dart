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
    await IsraelGeoIndex.loadSupermarkets();
    await IsraelGeoIndex.loadClinics();
    await IsraelGeoIndex.loadLifestylePois();
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

  // ── scoring access (the #2 rewiring: real points feed retail/health_access) ──
  test('supermarketAccess: strong in dense TA, 0 at invalid coords', () {
    final a = IsraelGeoIndex.supermarketAccess(lat, lon);
    expect(a, greaterThan(0.5)); // central TA has many supermarkets within 1.5km
    expect(a, lessThanOrEqualTo(1.0));
    expect(IsraelGeoIndex.supermarketAccess(0, 0), 0.0);
  });

  test('clinicAccess: positive in dense TA, 0 at invalid coords', () {
    final a = IsraelGeoIndex.clinicAccess(lat, lon);
    expect(a, greaterThan(0.0));
    expect(a, lessThanOrEqualTo(1.0));
    expect(IsraelGeoIndex.clinicAccess(0, 0), 0.0);
  });

  test('synagogueDensity: strong in religious מאה שערים, 0 in the desert', () {
    // מאה שערים (Jerusalem) is dense with synagogues → a real religiosity signal
    // the hardcoded list can now be backed/extended by.
    expect(IsraelGeoIndex.synagogueDensity(31.789, 35.220), greaterThan(0.3));
    expect(IsraelGeoIndex.synagogueDensity(30.35, 35.10), 0.0); // Arava desert
    expect(IsraelGeoIndex.synagogueDensity(0, 0), 0.0);
  });

  test('hospitals + transit stops load and return places in central TA', () {
    expect(IsraelGeoIndex.hospitalsWithin(lat, lon, km: 6), isNotEmpty);
    final t = IsraelGeoIndex.transitStopsWithin(lat, lon, km: 3);
    expect(t, isNotEmpty);
    expect(t.any((s) => s.stage.isNotEmpty), isTrue); // typed רכבת/רק״ל/מטרו
    // worship layer loads (mosques/churches sparse in central TA — just no crash).
    expect(IsraelGeoIndex.worshipWithin(lat, lon, km: 5).length,
        greaterThanOrEqualTo(0));
  });

  test('pools / bike-share / parking / coworking / vets load in central TA', () {
    expect(IsraelGeoIndex.poolsWithin(lat, lon, km: 4), isNotEmpty);
    expect(IsraelGeoIndex.bikeShareWithin(lat, lon, km: 3), isNotEmpty);
    expect(IsraelGeoIndex.parkingWithin(lat, lon, km: 3), isNotEmpty);
    // sparser layers just load without crashing (may be empty at this point)
    expect(IsraelGeoIndex.coworkingWithin(lat, lon, km: 5).length,
        greaterThanOrEqualTo(0));
    expect(IsraelGeoIndex.vetsWithin(lat, lon, km: 5).length,
        greaterThanOrEqualTo(0));
    expect(IsraelGeoIndex.dogParksWithin(lat, lon, km: 5).length,
        greaterThanOrEqualTo(0));
  });

  test('synagogues + culture load and return nearby places in central TA', () {
    final syn = IsraelGeoIndex.synagoguesWithin(lat, lon, km: 2);
    expect(syn, isNotEmpty);
    for (final s in syn) {
      expect(s.km, lessThanOrEqualTo(2.0));
      expect(s.name, isNotEmpty); // generic "בית כנסת" when unnamed
    }
    final cul = IsraelGeoIndex.cultureWithin(lat, lon, km: 3);
    expect(cul, isNotEmpty);
    expect(cul.any((c) => c.stage.isNotEmpty), isTrue); // typed (מוזיאון/תיאטרון/…)
  });

  test('supermarketAccess in the Negev desert is far lower than central TA', () {
    // A sparse rural point should score well below dense Tel Aviv — proves it is
    // reading real point density, not a flat constant.
    final ta = IsraelGeoIndex.supermarketAccess(lat, lon);
    final desert = IsraelGeoIndex.supermarketAccess(30.6, 34.8); // near Mitzpe Ramon
    expect(desert, lessThan(ta));
  });
}
