import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:flutter_test/flutter_test.dart';

// #1 verification: the retail/employment/noise/future_value layers used to be
// Tel-Aviv-only SEED stubs, so their scoring signals were 0/neutral everywhere
// else. After running the national ETL, these must now be live OUTSIDE Gush Dan.
// Coordinates: Haifa centre, Be'er Sheva centre, Jerusalem centre.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const haifa = [32.7940, 34.9896];
  const beerSheva = [31.2518, 34.7913];
  const jerusalem = [31.7683, 35.2137];

  setUpAll(() async {
    await GovData.instance.init();
  });

  final g = GovData.instance;

  test('retail access is national (non-zero in Haifa, Be\'er Sheva, Jerusalem)',
      () {
    expect(g.retailAccessScore(haifa[0], haifa[1]), greaterThan(0.0));
    expect(g.retailAccessScore(beerSheva[0], beerSheva[1]), greaterThan(0.0));
    expect(g.retailAccessScore(jerusalem[0], jerusalem[1]), greaterThan(0.0));
  });

  test('employment access is national outside Tel Aviv', () {
    expect(g.employmentAccessScore(haifa[0], haifa[1]), greaterThan(0.0));
    expect(g.employmentAccessScore(beerSheva[0], beerSheva[1]), greaterThan(0.0));
  });

  test('road noise is measured (non-null) in Haifa & Be\'er Sheva', () {
    // Was effectively null everywhere but the 10-cell TLV seed before.
    expect(g.roadNoiseScore(haifa[0], haifa[1]), isNotNull);
    expect(g.roadNoiseScore(beerSheva[0], beerSheva[1]), isNotNull);
  });

  test('future_value lights up along the Gush-Dan construction corridors', () {
    // Near the Green/Purple LRT + Metro works in central Tel Aviv.
    expect(g.futureValueScore(32.0700, 34.7900), greaterThan(0.0));
  });

  test('scores stay bounded [0,1]', () {
    for (final c in [haifa, beerSheva, jerusalem]) {
      expect(g.retailAccessScore(c[0], c[1]), inInclusiveRange(0.0, 1.0));
      expect(g.employmentAccessScore(c[0], c[1]), inInclusiveRange(0.0, 1.0));
      expect(g.futureValueScore(c[0], c[1]), inInclusiveRange(0.0, 1.0));
    }
  });
}
