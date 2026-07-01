// Pure-logic tests for the cohort-aware main-feed scorer (no aws-sdk/network).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  rankWeightsFor, cohortPriceTarget, priceFitScore, neighborhoodFitScore, cohortGateReject,
} from '../lambda/router/lib/ranking.mjs';

const listingWith = (schoolsMeta) => ({ neighborhoodScore: { sub: {}, schoolsMeta } });

test('rankWeightsFor: family weights neighborhood higher than default', () => {
  assert.ok(rankWeightsFor('family').neighborhood > rankWeightsFor(null).neighborhood);
  assert.ok(rankWeightsFor('single').semantic > rankWeightsFor(null).semantic);
  assert.deepEqual(rankWeightsFor('nonsense'), rankWeightsFor(null)); // fallback
});

test('cohortPriceTarget mapping', () => {
  assert.equal(cohortPriceTarget('family'), 'low');
  assert.equal(cohortPriceTarget('student'), 'low');
  assert.equal(cohortPriceTarget('single'), 'mid');
  assert.equal(cohortPriceTarget(null), 'mid');
});

test('priceFitScore: low target prefers the cheap end, high prefers premium', () => {
  const win = { minBudget: 4000, maxBudget: 8000 };
  const cheap = 4500;
  const pricey = 7500;
  // low: cheaper scores higher
  assert.ok(priceFitScore(cheap, win, 'low') > priceFitScore(pricey, win, 'low'));
  // high: pricier scores higher
  assert.ok(priceFitScore(pricey, win, 'high') > priceFitScore(cheap, win, 'high'));
  // mid: the middle beats both ends
  const mid = priceFitScore(6000, win, 'mid');
  assert.ok(mid > priceFitScore(4001, win, 'mid'));
  assert.ok(mid > priceFitScore(7999, win, 'mid'));
  // invert behaves like low
  assert.equal(priceFitScore(cheap, win, 'invert'), priceFitScore(cheap, win, 'low'));
});

test('priceFitScore: out-of-window decays; no-signal is neutral', () => {
  const win = { minBudget: 4000, maxBudget: 8000 };
  assert.ok(priceFitScore(9000, win, 'low') < priceFitScore(8000, win, 'low'));
  assert.equal(priceFitScore(5000, {}, 'mid'), 0.5); // no budget, no target
  assert.equal(priceFitScore(0, win, 'low'), 0.5);   // bad price
});

test('cohortGateReject: religious_family requires חמ"ד-dominant area (fraction)', () => {
  // secular-dominant (0% חמ"ד) → excluded
  assert.equal(cohortGateReject('religious_family', listingWith({ pikuah: { mamlachti: 20 }, total: 20 })), true);
  // charedi-dominant, 4% חמ"ד → excluded (charedi ≠ דתי-לאומי; the key fix)
  assert.equal(cohortGateReject('religious_family', listingWith({ pikuah: { charedi: 165, mamlachti_dati: 8 }, total: 204 })), true);
  // חמ"ד-dominant (83%) → kept
  assert.equal(cohortGateReject('religious_family', listingWith({ pikuah: { mamlachti_dati: 5, mamlachti: 1 }, total: 6 })), false);
});

test('cohortGateReject: arab_family requires Arab-sector-dominant area', () => {
  assert.equal(cohortGateReject('arab_family', listingWith({ sectors: { jewish: 100 }, total: 100 })), true);
  assert.equal(cohortGateReject('arab_family', listingWith({ sectors: { arab: 5, jewish: 5 }, total: 10 })), false);
});

test('cohortGateReject fail-soft: missing/empty metadata never excludes', () => {
  for (const cohort of ['religious_family', 'arab_family']) {
    assert.equal(cohortGateReject(cohort, listingWith(undefined)), false); // no schoolsMeta
    assert.equal(cohortGateReject(cohort, { }), false);                    // no neighborhoodScore
    assert.equal(cohortGateReject(cohort, listingWith({ pikuah: {}, sectors: {}, total: 0 })), false); // empty
  }
  // cohorts without a gate are never excluded
  assert.equal(cohortGateReject('family', listingWith({ pikuah: { mamlachti: 5 }, total: 5 })), false);
  assert.equal(cohortGateReject(null, listingWith({ sectors: { jewish: 9 }, total: 9 })), false);
});

test('neighborhoodFitScore: family vs student flip; fallbacks', () => {
  const schoolArea = { sub: { safety: 90, schools: 95, green: 80, walkability: 40, transit: 20 } };
  const transitArea = { sub: { safety: 50, schools: 30, green: 30, walkability: 90, transit: 95 } };
  assert.ok(neighborhoodFitScore(schoolArea, 'family') > neighborhoodFitScore(transitArea, 'family'));
  assert.ok(neighborhoodFitScore(transitArea, 'student') > neighborhoodFitScore(schoolArea, 'student'));
  // no sub → fall back to stored composite score/100
  assert.equal(neighborhoodFitScore({ score: 80 }, 'family'), 0.8);
  // nothing at all → neutral
  assert.equal(neighborhoodFitScore(null, 'family'), 0.5);
  assert.equal(neighborhoodFitScore({}, 'student'), 0.5);
});
