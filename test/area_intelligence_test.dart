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

  test('CRUSH — bad coords do not crash the profiler', () {
    for (final ll in const [[0.0, 0.0], [double.nan, 34.0]]) {
      final p = AreaIntelligence.profileAt(ll[0], ll[1]);
      expect(p.safety, inInclusiveRange(0.0, 1.0));
      final fit = AreaIntelligence.fit(p.pfv, TargetPersona.all.first);
      expect(fit.pct, inInclusiveRange(0, 100));
    }
  });
}
