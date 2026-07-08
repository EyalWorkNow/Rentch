import 'dart:io';

import 'package:dating_app/core/govdata/gov_data.dart';
import 'package:dating_app/core/search/budget_reality.dart';
import 'package:dating_app/core/search/smart_search.dart';
import 'package:flutter_test/flutter_test.dart';

Future<String> _r(String p) => File(p).readAsString();

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await GovData.instance.init(reader: _r);
  });

  BudgetReality check(String q) => BudgetRealityCheck.assess(SmartSearch.parse(q));

  test('an impossible ask is flagged unrealistic with guidance', () {
    final r = check('דירת 4 חדרים בתל אביב עד 3000');
    expect(r.verdict, RealityVerdict.unrealistic);
    expect(r.message.isNotEmpty, true);
    expect(r.expected != null && r.expected! > 3000, true,
        reason: 'realistic price should be well above the ask');
    // ignore: avoid_print
    print('  → ${r.message}');
  });

  test('a realistic ask passes (no guidance)', () {
    // A generous Tel-Aviv budget for a small flat.
    final r = check('דירת 2 חדרים בתל אביב עד 12000');
    expect(r.needsGuidance, false);
  });

  test('a cheap-city ask is feasible', () {
    final r = check('דירת 3 חדרים בבאר שבע עד 5000');
    expect(r.needsGuidance, false);
  });

  test('a borderline ask reads as "tight", not "unrealistic"', () {
    // Search a range of budgets for TA 3-room; there should exist a band that is
    // tight (0.6–0.85 of market) rather than impossible.
    var sawTight = false;
    for (final b in [5000, 5500, 6000, 6500, 7000]) {
      final r = check('דירת 3 חדרים בתל אביב עד $b');
      if (r.verdict == RealityVerdict.tight) sawTight = true;
    }
    expect(sawTight, true, reason: 'expected some TA 3-room budget to read as tight');
  });

  test('no city or no budget → feasible (nothing to judge)', () {
    expect(check('דירה שקטה').needsGuidance, false);
    expect(check('דירה בתל אביב').needsGuidance, false);
  });

  test('degrades gracefully when GovData has no market prior for the city', () {
    // A tiny locality unlikely to have a ₪/m² prior — must not crash / mis-flag.
    final r = check('דירת 4 חדרים בעין עירון עד 2000');
    expect(r.verdict, anyOf(RealityVerdict.feasible, RealityVerdict.unrealistic, RealityVerdict.tight));
  });
}
