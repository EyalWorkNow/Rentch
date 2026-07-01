// Pure-logic tests for the cohort-aware main-feed scorer (no aws-sdk/network).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  rankWeightsFor, cohortPriceTarget, priceFitScore, neighborhoodFitScore, communityFitScore,
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

test('communityFitScore: soft signal, dati_leumi vs charedi are INVERSE', () => {
  const charediArea = listingWith({ pikuah: { charedi: 165, mamlachti_dati: 8 }, total: 204 }); // 4% חמ"ד, 81% charedi
  const datiArea = listingWith({ pikuah: { mamlachti_dati: 5, mamlachti: 1 }, total: 6 });       // 83% חמ"ד
  // dati_leumi: high fit in the חמ"ד area, LOW (not excluded) in the charedi area
  assert.ok(communityFitScore('dati_leumi', datiArea) > communityFitScore('dati_leumi', charediArea));
  assert.equal(communityFitScore('dati_leumi', datiArea), 1); // ≥30% → saturates to 1
  assert.ok(communityFitScore('dati_leumi', charediArea) < 0.2);
  // charedi is the inverse
  assert.ok(communityFitScore('charedi', charediArea) > communityFitScore('charedi', datiArea));
  assert.equal(communityFitScore('charedi', datiArea), 0);
});

test('communityFitScore: arab_family tracks Arab-sector fraction', () => {
  assert.equal(communityFitScore('arab_family', listingWith({ sectors: { jewish: 100 }, total: 100 })), 0);
  assert.ok(communityFitScore('arab_family', listingWith({ sectors: { arab: 5, jewish: 5 }, total: 10 })) >= 1);
});

test('communityFitScore: neutral 0.5 when unknown or non-community cohort', () => {
  for (const cohort of ['dati_leumi', 'charedi', 'arab_family']) {
    assert.equal(communityFitScore(cohort, listingWith(undefined)), 0.5); // no schoolsMeta
    assert.equal(communityFitScore(cohort, {}), 0.5);                     // no neighborhoodScore
    assert.equal(communityFitScore(cohort, listingWith({ pikuah: {}, sectors: {}, total: 0 })), 0.5);
  }
  // cohorts with no community preference → always neutral (no effect)
  assert.equal(communityFitScore('family', listingWith({ pikuah: { mamlachti: 5 }, total: 5 })), 0.5);
  assert.equal(communityFitScore(null, listingWith({ sectors: { jewish: 9 }, total: 9 })), 0.5);
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

// ── Integration: scoreListings (the extracted attachRankSignals core) ─────────
import { scoreListings } from '../lambda/router/lib/ranking.mjs';

test('scoreListings scores every listing, sets rankSignals, excludes nothing', () => {
  const items = [
    { id: 'a', price: 6000, createdAt: '2026-06-30T00:00:00Z' },
    { id: 'b', price: 6000, createdAt: '2026-06-30T00:00:00Z' },
  ];
  scoreListings(items, { cohort: 'family', minBudget: 5000, maxBudget: 8000 },
    { a: { views: 100, likes: 30 }, b: { views: 100, likes: 1 } }, Date.parse('2026-07-01T00:00:00Z'));
  assert.equal(items.length, 2); // nothing removed
  for (const p of items) {
    assert.ok(Number.isFinite(p.rankScore));
    assert.ok('community_fit' in p.rankSignals && p.rankSignals.cohort === 'family');
  }
  // a (higher like-rate) outranks b, all else equal
  assert.ok(items[0].rankScore > items[1].rankScore);
});

test('scoreListings: dati_leumi community_fit lifts a חמ"ד area over a charedi area', () => {
  const dati = { id: 'd', price: 6000, neighborhoodScore: { sub: { safety: 80 }, schoolsMeta: { pikuah: { mamlachti_dati: 5 }, total: 6 } } };
  const charedi = { id: 'c', price: 6000, neighborhoodScore: { sub: { safety: 80 }, schoolsMeta: { pikuah: { charedi: 5 }, total: 6 } } };
  const items = [charedi, dati];
  scoreListings(items, { cohort: 'dati_leumi', minBudget: 5000, maxBudget: 8000 }, {}, Date.now());
  const byId = Object.fromEntries(items.map((p) => [p.id, p]));
  assert.ok(byId.d.rankScore > byId.c.rankScore);            // חמ"ד area wins
  assert.ok(byId.c.rankScore > 0);                            // but charedi area NOT excluded
  assert.ok(byId.d.rankSignals.community_fit > byId.c.rankSignals.community_fit);
});

test('scoreListings: cheaper listing wins for a low-price-target cohort', () => {
  const cheap = { id: 'cheap', price: 5200 };
  const pricey = { id: 'pricey', price: 7800 };
  const items = [pricey, cheap];
  scoreListings(items, { cohort: 'student', minBudget: 5000, maxBudget: 8000 }, {}, Date.now());
  const byId = Object.fromEntries(items.map((p) => [p.id, p]));
  assert.ok(byId.cheap.rankScore > byId.pricey.rankScore);
});
