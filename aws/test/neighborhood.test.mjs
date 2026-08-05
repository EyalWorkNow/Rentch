// Pure-logic tests for the R8 neighbourhood scorers (no network — the pure
// scorer exports only; osmCounts/neighborhoodScore stay integration-tested by
// the live demo in the module footer).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  transitScoreFrom, greenScoreFrom, walkScoreFrom, quietScoreFrom,
  crimePercentileScore,
} from '../lambda/router/lib/neighborhood.mjs';

test('transit: a train station outweighs the same count of bus stops', () => {
  const railHeavy = transitScoreFrom({ bus: 2, rail: 2, railNearestM: 400 });
  const busHeavy = transitScoreFrom({ bus: 4 });
  assert.ok(railHeavy > busHeavy);
});

test('transit: nearer rail scores higher at equal counts', () => {
  const near = transitScoreFrom({ bus: 3, rail: 1, railNearestM: 150 });
  const far = transitScoreFrom({ bus: 3, rail: 1, railNearestM: 750 });
  assert.ok(near > far);
});

test('green: nearby park beats same count far away', () => {
  const near = greenScoreFrom({ count: 2, nearestM: 120 });
  const far = greenScoreFrom({ count: 2, nearestM: 780 });
  assert.ok(near > far);
  assert.ok(greenScoreFrom({ count: 0, nearestM: Infinity }) === 0);
});

test('walkability: essential coverage lifts the score beyond raw count', () => {
  const cafesOnly = walkScoreFrom({ count: 40, essentials: 0 });
  const fullDailyLife = walkScoreFrom({ count: 40, essentials: 5 });
  assert.ok(fullDailyLife > cafesOnly + 30); // coverage is worth 45 points
  assert.ok(fullDailyLife <= 100);
});

test('quiet: big roads cost points, monotonically, floored at 0', () => {
  const silent = quietScoreFrom({});
  const primaryNearby = quietScoreFrom({ primary: 2 });
  const motorway = quietScoreFrom({ motorwayTrunk: 2, primary: 3, secondary: 4 });
  assert.equal(silent, 100);
  assert.ok(primaryNearby < silent);
  assert.ok(motorway < primaryNearby);
  assert.ok(motorway >= 0);
});

// build a synthetic weighted distribution: rates 0.001..0.1, equal pops
function makeDist(n = 100, popEach = 10000) {
  const rows = Array.from({ length: n }, (_, i) => ({ rate: (i + 1) / 1000, pop: popEach }));
  let cum = 0;
  const total = n * popEach;
  for (const r of rows) { cum += r.pop; r.cumFrac = cum / total; }
  return rows;
}

test('crime percentile: calibrated against the given weighted distribution', () => {
  const dist = makeDist();
  assert.ok(crimePercentileScore(0.0005, dist) === 95); // safest tail, capped at 95
  const median = crimePercentileScore(0.0505, dist);
  assert.ok(median > 40 && median < 60);                // mid-distribution ≈ 50
  assert.ok(crimePercentileScore(0.2, dist) === 5);     // worst tail, floored at 5
  assert.ok(Number.isNaN(crimePercentileScore(NaN, dist)));
});

test('crime percentile: population weighting shifts the rank', () => {
  // two localities: big safe city (90% of pop), small risky town (10%)
  const rows = [
    { rate: 0.01, pop: 900000 },
    { rate: 0.05, pop: 100000 },
  ];
  let cum = 0; const total = 1000000;
  for (const r of rows) { cum += r.pop; r.cumFrac = cum / total; }
  // a rate between the two ranks above 90% of the population → low score
  // (but the thin-dist fallback kicks in under 30 rows, so pad with safe rows)
  const padded = Array.from({ length: 28 }, (_, i) => ({ rate: 0.001 + i * 0.0001, pop: 1 }));
  const dist = [...padded, ...rows].sort((a, b) => a.rate - b.rate);
  cum = 0; const t2 = dist.reduce((s, r) => s + r.pop, 0);
  for (const r of dist) { cum += r.pop; r.cumFrac = cum / t2; }
  assert.ok(crimePercentileScore(0.03, dist) < 15); // above the big city's rate
});

test('crime percentile: thin distribution falls back to the R7 benchmark', () => {
  const thin = makeDist(2);
  assert.equal(crimePercentileScore(0.05, thin), 50); // 100·(1−0.05/0.10)
});
