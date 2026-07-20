import 'package:dating_app/core/matching/match_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// Drift guard for the two-sided match weights. These are the CANONICAL values
/// mirrored by the server scorer `scoreLandlordToTenant` / `MATCH_W` in
/// aws/lambda/router/index.mjs. If you change a value here, change it there too
/// (and vice-versa) — the two scorers must not drift again (they had: server
/// sharedTagBonus was 4 vs 6 here).
void main() {
  test('canonical MatchWeights are pinned (keep the server MATCH_W in sync)', () {
    const w = MatchWeights.standard;
    expect(w.budgetHeadroomBonus, 10);
    expect(w.sharedTagBonus, 6); // server MATCH_W.sharedTagBonus must equal this
    expect(w.dealBreakerPenalty, 45);
    expect(w.propertyFitWeight, 0.62);
    expect(w.tenantFitWeight, 0.38);
    // property + tenant fit weights partition the blended score.
    expect(w.propertyFitWeight + w.tenantFitWeight, closeTo(1.0, 1e-9));
  });
}
