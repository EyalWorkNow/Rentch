import 'package:dating_app/core/search/nearby_relevance.dart';
import 'package:dating_app/core/search/scenario_layers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // rootBundle asset loading needs the test binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await ScenarioLayers.instance.ensureLoaded();
  });

  test('spec asset loads (504 scenarios)', () {
    expect(ScenarioLayers.instance.isLoaded, isTrue);
  });

  test('deriveKey maps profile → the 5-dimension scenario key', () {
    final sl = ScenarioLayers.instance;
    // single + secular + dog + office(default) + rent(default)
    expect(sl.deriveKey(const NearbyProfile(single: true, secular: true, dog: true)),
        'ravak_ravaka|chiloni|dog|office|rent');
    // school-age family + observant + no pet + student + buy
    expect(
        sl.deriveKey(
            const NearbyProfile(
                family: true, schoolChild: true, observant: true, student: true),
            purpose: 'buy'),
        'mishpacha_yeladim|dati|none|student|buy');
    // retiree + cat + wfh
    expect(sl.deriveKey(const NearbyProfile(senior: true, pet: true, wfh: true)),
        'gimlaim|masorti|cat|remote|rent');
    // explicit religiosity from the persona overrides the coarse derivation
    expect(
        sl.deriveKey(const NearbyProfile(couple: true), religiosity: 'haredi'),
        'zug_bli_yeladim|charedi|none|office|rent');
  });

  test('sectionsFor returns the scenario core layers mapped to NearbyKind', () {
    // matches the asset row ravak_ravaka|chiloni|dog|office|rent →
    // core [transit_stops, nightlife, dining, dog_parks, parks, culture]
    final s = ScenarioLayers.instance
        .sectionsFor(const NearbyProfile(single: true, secular: true, dog: true));
    expect(s, isNotNull);
    final kinds = s!.map((e) => e.kind).toSet();
    for (final k in [
      NearbyKind.transit,
      NearbyKind.nightlife,
      NearbyKind.dining,
      NearbyKind.dogParks,
      NearbyKind.parks,
      NearbyKind.culture,
    ]) {
      expect(kinds, contains(k), reason: 'core layer $k missing');
    }
    // core layers must outrank the always-on base layers (crime/supermarkets…).
    final nightlife = s.firstWhere((e) => e.kind == NearbyKind.nightlife);
    final superm = s.where((e) => e.kind == NearbyKind.supermarkets);
    if (superm.isNotEmpty) {
      expect(nightlife.priority, greaterThan(superm.first.priority));
    }
  });

  test('weightsFor exposes the per-layer weights for scoring', () {
    final w = ScenarioLayers.instance
        .weightsFor(const NearbyProfile(single: true, secular: true, dog: true));
    expect(w, isNotNull);
    expect(w!['transit_stops'], 5); // top weight in this scenario
    expect(w['nightlife'], 5); // v2 weights nightlife on par with transit
    expect(w.containsKey('poi_retail'), isTrue); // base layer, low weight
  });

  test('secular seeker is never shown synagogues/worship', () {
    final s = ScenarioLayers.instance
        .sectionsFor(const NearbyProfile(single: true, secular: true));
    if (s != null) {
      final kinds = s.map((e) => e.kind).toSet();
      expect(kinds.contains(NearbyKind.synagogues), isFalse);
      expect(kinds.contains(NearbyKind.worship), isFalse);
    }
  });

  test('dimensionBoostsFor maps spec layers → gentle dimension targets', () {
    // single + secular + dog: core [transit_stops(5), nightlife(4), … dog_parks]
    final b = ScenarioLayers.instance.dimensionBoostsFor(
        const NearbyProfile(single: true, secular: true, dog: true));
    expect(b, isNotNull);
    // transit_stops weight 5 → 0.5 + 5*0.09 = 0.95 target on 'transit'
    expect(b!['transit'], closeTo(0.95, 1e-9));
    // nightlife weight 5 → 0.95
    expect(b['nightlife'], closeTo(0.95, 1e-9));
    // dog_parks → 'park' dimension present, targets clamp to ≤1.0
    expect(b['park'], isNotNull);
    for (final t in b.values) {
      expect(t, inInclusiveRange(0.0, 1.0));
    }
    // pure-display layers (culture/dining) never leak into scoring dims.
    expect(b.containsKey('culture'), isFalse);
  });

  test('coreOnly returns only the highlighted core band', () {
    final all = personalizedNearbySections(
        const NearbyProfile(single: true, secular: true, dog: true));
    final core = personalizedNearbySections(
        const NearbyProfile(single: true, secular: true, dog: true),
        coreOnly: true);
    expect(core.length, lessThan(all.length)); // core ⊂ core+secondary+base
    expect(core, isNotEmpty);
  });
}
