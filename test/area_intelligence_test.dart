// Area Intelligence engine: profiling a point and scoring persona-fit, with real
// gov data (stat-areas/SES/centrality/transit).
import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/insights/area_intelligence.dart';
import 'package:dating_app/core/insights/target_personas.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: (p) => File(p).readAsString());
  });
  tearDownAll(() => GovData.instance.resetForTest());

  test('7 target personas are defined', () {
    expect(TargetPersona.all.length, 7);
    expect(TargetPersona.byKey('families')?.label, 'משפחות עם ילדים');
  });

  test('profileAt returns sane gov-data layers for central Tel Aviv', () {
    final p = AreaIntelligence.profileAt(32.0700, 34.7750, city: 'תל אביב');
    expect(p.sesCluster, inInclusiveRange(1, 10));
    for (final v in [p.socioeconomic, p.safety, p.centrality, p.transit,
      p.schools, p.youngShare, p.childShare, p.seniorShare]) {
      expect(v, inInclusiveRange(0.0, 1.0));
    }
    // central TLV is highly central + high SES
    expect(p.centrality, greaterThan(0.6));
    expect(p.sesCluster, greaterThanOrEqualTo(7));
  });

  test('persona fit discriminates — central TLV suits young/tech over seniors', () {
    final pfv = AreaIntelligence.profileAt(32.0700, 34.7750, city: 'תל אביב').pfv;
    final tech = AreaIntelligence.fit(pfv, TargetPersona.byKey('tech')!);
    final seniors = AreaIntelligence.fit(pfv, TargetPersona.byKey('seniors')!);
    expect(tech.pct, greaterThan(seniors.pct),
        reason: 'a central lively block should serve tech better than retirees');
    expect(tech.pct, inInclusiveRange(0, 100));
    expect(tech.reasons, isNotEmpty);
  });

  test('suitablePersonas returns all 7, sorted best-first', () {
    final pfv = AreaIntelligence.profileAt(32.0700, 34.7750, city: 'תל אביב').pfv;
    final ranked = AreaIntelligence.suitablePersonas(pfv);
    expect(ranked.length, 7);
    for (var i = 1; i < ranked.length; i++) {
      expect(ranked[i - 1].pct, greaterThanOrEqualTo(ranked[i].pct));
    }
  });

  test('statAreasInCity resolves a big city (normalized name)', () {
    final tlv = GovData.instance.statAreasInCity('תל אביב');
    expect(tlv.length, greaterThan(50), reason: 'TLV has many statistical blocks');
    expect(tlv.every((a) => a.centroid[0] > 31 && a.centroid[0] < 33), true);
  });

  test('rankCityAreas — sorted best-first + persona discriminates', () {
    final forFamilies =
        AreaIntelligence.rankCityAreas('תל אביב', TargetPersona.byKey('families')!);
    final forTech =
        AreaIntelligence.rankCityAreas('תל אביב', TargetPersona.byKey('tech')!);
    expect(forFamilies.length, greaterThan(50));
    // sorted desc by fit
    for (var i = 1; i < forFamilies.length; i++) {
      expect(forFamilies[i - 1].fit.pct, greaterThanOrEqualTo(forFamilies[i].fit.pct));
    }
    // the #1 family block and the #1 tech block should not be identical (the
    // personas value different layers), proving the ranking discriminates.
    final famTop = forFamilies.first.area.id;
    final techTop = forTech.first.area.id;
    expect(famTop != techTop || forFamilies.first.fit.pct != forTech.first.fit.pct,
        true);
    // limit is honoured
    expect(
        AreaIntelligence.rankCityAreas('תל אביב', TargetPersona.byKey('tech')!,
                limit: 10)
            .length,
        10);
  });

  test('rankCityAreas — unknown city → empty, no throw', () {
    expect(AreaIntelligence.rankCityAreas('עיר-שלא-קיימת', TargetPersona.all.first),
        isEmpty);
  });

  test('CRUSH — bad coords do not crash the profiler', () {
    for (final ll in const [[0.0, 0.0], [double.nan, 34.0]]) {
      final p = AreaIntelligence.profileAt(ll[0], ll[1]);
      expect(p.safety, inInclusiveRange(0.0, 1.0));
      final fit = AreaIntelligence.fit(p.pfv, TargetPersona.all.first);
      expect(fit.pct, inInclusiveRange(0, 100));
    }
  });
}
