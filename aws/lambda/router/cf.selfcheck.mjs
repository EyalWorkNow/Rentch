// cf.selfcheck.mjs — node-assert self-check for the pure consumption-layer
// helpers in lib/cf.mjs. Run:
//   node aws/lambda/router/cf.selfcheck.mjs
//
// cf.mjs is dependency-free, so unlike index.mjs it can be imported directly.
import assert from 'node:assert/strict';
import { implicitScore, cfRecommend, trainingRowsFrom, expectedDwellMs } from './lib/cf.mjs';

let n = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); n++; };
const eq = (a, b, msg) => { assert.strictEqual(a, b, msg); n++; };

// ── implicitScore: individual weights ────────────────────────────────────────
eq(implicitScore({}), 0, 'empty record → 0');
eq(implicitScore({ contacted: true }), 5, 'contact +5');
eq(implicitScore({ superliked: true }), 4, 'superlike +4');
eq(implicitScore({ liked: true }), 3, 'like +3');
// Length-normalized dwell (landmine #3). With no media/desc info the expected
// dwell is the 6s BASE, so ratio = dwellMs/6000.
eq(expectedDwellMs(0, 0), 6000, 'bare listing expects the 6s base');
eq(expectedDwellMs(4, 100), 6000 + 4 * 1800 + 100 * 12, 'expected scales w/ media+desc');
eq(implicitScore({ dwellMs: 40000 }), 2, 'dwell ≫ expected → +2 (bounded)');
eq(implicitScore({ dwellMs: 12000 }), 2, 'dwell 2× expected → +2 (bound hit)');
eq(implicitScore({ dwellMs: 3000 }), 0, 'dwell ≤ 0.5× expected → +0 (skim)');
// SAME dwell, but a media-heavy listing (higher expected) contributes LESS — the
// core anti-skew property: a big listing can't auto-score higher on raw dwell.
{
  const bare = implicitScore({ dwellMs: 9000, mediaCount: 0, descLen: 0 });
  const heavy = implicitScore({ dwellMs: 9000, mediaCount: 12, descLen: 800 });
  ok(bare > heavy, 'same dwell scores lower on a media-heavy listing');
  ok(heavy >= 0, 'normalized dwell never goes negative');
}
eq(implicitScore({ opened360: true }), 1.5, 'opened360 +1.5');
eq(implicitScore({ opened3d: true }), 1.5, 'opened3d +1.5');
eq(implicitScore({ openedVideo: true }), 1.5, 'openedVideo +1.5');
eq(implicitScore({ opened360: true, opened3d: true, openedVideo: true }), 1.5,
  'media flags do not stack (single +1.5)');
eq(implicitScore({ photosViewed: 4 }), 1, 'photosViewed>3 +1');
eq(implicitScore({ photosViewed: 3 }), 0, 'photosViewed==3 +0');
eq(implicitScore({ scrollDepth: 0.8 }), 1, 'scrollDepth>0.7 +1');
eq(implicitScore({ scrollDepth: 0.7 }), 0, 'scrollDepth==0.7 +0');
eq(implicitScore({ viewCount: 1 }), 0.5, 'viewCount>0 +0.5');
eq(implicitScore({ viewCount: 0 }), 0, 'viewCount==0 +0');
eq(implicitScore({ bounced: true }), -1, 'bounce -1');
eq(implicitScore({ passed: true }), -2, 'passed -2');

// ── implicitScore: combined + clamp ──────────────────────────────────────────
// contact5 + superlike4 + like3 + dwell2 + media1.5 + photos1 + scroll1 + view0.5
//   = 18 → clamps to 12
eq(implicitScore({
  contacted: true, superliked: true, liked: true, dwellMs: 40000,
  opened360: true, photosViewed: 5, scrollDepth: 0.9, viewCount: 2,
}), 12, 'positive stack clamps high → 12');
// passed-2 + bounced-1 + (nothing else) = -3, add more to exceed -5 floor
eq(implicitScore({ passed: true, bounced: true, dwellMs: 0 }), -3, 'negative sum -3');
// force below the floor: many negatives can't go below -5 (only 2 exist → -3),
// so assert the clamp mechanically via a synthetic over-negative record isn't
// reachable; instead confirm the floor holds for the max negative + no positives.
ok(implicitScore({ passed: true, bounced: true }) >= -5, 'never below -5 floor');
// mixed: like3 + dwell2 (12s = 2× the 6s expected → bound) + view0.5 - pass2 = 3.5
eq(implicitScore({ liked: true, dwellMs: 12000, viewCount: 1, passed: true }), 3.5,
  'mixed positive/negative sums correctly');

// ── cfRecommend: co-engaged property ranks above non-co-engaged; seen excluded ─
{
  // Caller positively engaged P1 (a seed). They've also already SEEN P9.
  const seeds = [
    { propertyId: 'P1', score: 3 },
    { propertyId: 'P9', score: -2 }, // engaged-but-negative → still excluded from output
  ];
  const coUsers = [
    // coA shares the seed P1 (overlap) and also likes P2 → P2 becomes a candidate.
    { userId: 'a', interactions: [{ propertyId: 'P1', score: 3 }, { propertyId: 'P2', score: 4 }] },
    // coB shares NO seed → P3 must NOT surface.
    { userId: 'b', interactions: [{ propertyId: 'P3', score: 5 }] },
    // coC shares the seed P1 and also re-likes P9 (already seen) → P9 excluded.
    { userId: 'c', interactions: [{ propertyId: 'P1', score: 2 }, { propertyId: 'P9', score: 5 }] },
  ];
  const items = cfRecommend(seeds, coUsers, { limit: 10 });
  const ids = items.map((x) => x.propertyId);
  ok(ids.includes('P2'), 'co-engaged P2 recommended');
  ok(!ids.includes('P3'), 'non-co-engaged P3 excluded');
  ok(!ids.includes('P1') && !ids.includes('P9'), 'already-engaged props excluded');
  eq(ids[0], 'P2', 'P2 ranks first');
  // P2 score = overlapWeight(coA = seedScore[P1]=3) * candScore(4) = 12
  eq(items[0].cfScore, 12, 'cfScore = overlapWeight * candidateScore');
}

// ── cfRecommend: ranks a strongly co-engaged prop above a weakly co-engaged one ─
{
  const seeds = [{ propertyId: 'S', score: 5 }];
  const coUsers = [
    { userId: 'a', interactions: [{ propertyId: 'S', score: 5 }, { propertyId: 'HOT', score: 5 }] },
    { userId: 'b', interactions: [{ propertyId: 'S', score: 1 }, { propertyId: 'COLD', score: 1 }] },
  ];
  const items = cfRecommend(seeds, coUsers, { limit: 10 });
  eq(items[0].propertyId, 'HOT', 'strongly co-engaged ranks first');
  ok(items[0].cfScore > items[1].cfScore, 'HOT scored above COLD');
}

// ── cfRecommend: no positive seeds → empty ───────────────────────────────────
eq(cfRecommend([{ propertyId: 'x', score: 0 }], [{ userId: 'a', interactions: [] }]).length, 0,
  'no positive seeds → []');
eq(cfRecommend([], []).length, 0, 'empty inputs → []');

// ── trainingRowsFrom: join impression + outcome → labeled row ────────────────
{
  const impressions = [
    { searchId: 's1', propertyId: 'P1', features: { a: 1 }, rank: 0, score: 2.5 },
    { searchId: 's1', propertyId: 'P2', features: { a: 2 }, rank: 1, score: 1.0 },
    { searchId: 's1', propertyId: 'P3', features: { a: 3 }, rank: 2, score: 0.5 }, // no outcome
  ];
  const outcomes = [
    { searchId: 's1', propertyId: 'P1', outcome: 'like' },   // → label 1
    { searchId: 's1', propertyId: 'P2', outcome: 'skip' },   // → label 0
  ];
  const rows = trainingRowsFrom(impressions, outcomes);
  eq(rows.length, 3, 'one row per impression');
  eq(rows[0].label, 1, 'like → label 1');
  eq(rows[0].features.a, 1, 'features carried from impression');
  eq(rows[0].score, 2.5, 'score carried from impression');
  eq(rows[1].label, 0, 'skip → label 0');
  eq(rows[2].label, 0, 'no matching outcome → label 0');
}

// ── trainingRowsFrom: superlike/contact are positive; positive beats skip ─────
{
  const impressions = [
    { searchId: 's2', propertyId: 'A', features: {}, rank: 0, score: 1 },
    { searchId: 's2', propertyId: 'B', features: {}, rank: 1, score: 1 },
  ];
  const outcomes = [
    { searchId: 's2', propertyId: 'A', outcome: 'superlike' },
    { searchId: 's2', propertyId: 'B', outcome: 'contact' },
    { searchId: 's2', propertyId: 'A', outcome: 'skip' }, // duplicate: positive must win
  ];
  const rows = trainingRowsFrom(impressions, outcomes);
  eq(rows[0].label, 1, 'superlike positive, wins over a later skip');
  eq(rows[1].label, 1, 'contact → label 1');
}

console.log(`cf.selfcheck: ${n} assertions passed`);
