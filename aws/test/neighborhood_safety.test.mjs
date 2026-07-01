// Pure-logic tests for the safety locality-join (no network, no aws-sdk).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeLocalityName } from '../lambda/router/lib/muni.mjs';
import {
  buildLocalityMap, crimeCountToSafety, buildCrimeRateMap,
  isKindergarten, normPikuah, normSector,
} from '../lambda/router/lib/neighborhood.mjs';

test('normalizeLocalityName strips muni prefixes and punctuation', () => {
  const k = normalizeLocalityName('תל אביב');
  assert.equal(normalizeLocalityName('עיריית תל אביב'), k);
  assert.equal(normalizeLocalityName('  תל-אביב  '), k);
  assert.equal(normalizeLocalityName('מ. מ. אבו גוש'), normalizeLocalityName('אבו גוש'));
  assert.equal(normalizeLocalityName(''), '');
  assert.equal(normalizeLocalityName(null), '');
});

test('buildLocalityMap: last-wins for socio, sum for crime', () => {
  const recs = [
    { 'שם_ישוב': 'תל אביב', v: 8 },
    { 'שם_ישוב': 'עיריית תל אביב', v: 5 }, // same locality after normalize
    { 'שם_ישוב': 'חיפה', v: 3 },
  ];
  const socio = buildLocalityMap(recs, ['שם_ישוב'], (r) => r.v, false);
  assert.equal(socio[normalizeLocalityName('תל אביב')], 5); // last wins
  const crime = buildLocalityMap(recs, ['שם_ישוב'], (r) => r.v, true);
  assert.equal(crime[normalizeLocalityName('תל אביב')], 13); // 8 + 5 summed
  assert.equal(crime[normalizeLocalityName('חיפה')], 3);
});

test('buildLocalityMap skips rows with no name or non-numeric value', () => {
  const recs = [{ other: 'x', v: 5 }, { 'שם_ישוב': 'אילת', v: 'NaN' }];
  const m = buildLocalityMap(recs, ['שם_ישוב'], (r) => Number(r.v), true);
  assert.deepEqual(m, {});
});

test('crimeCountToSafety inverts count vs max', () => {
  assert.equal(crimeCountToSafety(0, 100), 100); // zero crime → safest
  assert.equal(crimeCountToSafety(100, 100), 0); // max crime → least safe
  assert.equal(crimeCountToSafety(25, 100), 75);
  assert.ok(Number.isNaN(crimeCountToSafety(5, 0)));  // guard bad max
});

test('safety join: low-crime high-cluster locality beats the opposite', () => {
  const socio = buildLocalityMap(
    [{ 'שם_ישוב': 'רעננה', c: 9 }, { 'שם_ישוב': 'עיר ב', c: 3 }],
    ['שם_ישוב'], (r) => r.c, false);
  const crime = buildLocalityMap(
    [{ 'שם_ישוב': 'רעננה', n: 10 }, { 'שם_ישוב': 'עיר ב', n: 200 }],
    ['שם_ישוב'], (r) => r.n, true);
  const max = Math.max(...Object.values(crime));

  const safetyOf = (name) => {
    const k = normalizeLocalityName(name);
    return ((socio[k] / 10) * 100 + crimeCountToSafety(crime[k], max)) / 2;
  };
  assert.ok(safetyOf('רעננה') > safetyOf('עיר ב'));
});

// ── Phase 3 ────────────────────────────────────────────────────────────────
test('per-capita crime flips the ranking vs absolute counts', () => {
  // Big city: 1000 crimes / 500k people. Small town: 100 crimes / 5k people.
  const crime = { bigcity: 1000, smalltown: 100 };
  const pop = { bigcity: 500000, smalltown: 5000 };
  // Absolute: big city looks far worse. Per-capita: small town is worse (0.02 vs 0.002).
  const rate = buildCrimeRateMap(crime, pop);
  assert.ok(rate.smalltown > rate.bigcity);
  const maxRate = Math.max(...Object.values(rate));
  assert.ok(crimeCountToSafety(rate.bigcity, maxRate) > crimeCountToSafety(rate.smalltown, maxRate));
});

test('buildCrimeRateMap falls back to absolute count when population missing', () => {
  assert.deepEqual(buildCrimeRateMap({ x: 50 }, {}), { x: 50 });
  assert.deepEqual(buildCrimeRateMap({ x: 50 }, { x: 0 }), { x: 50 }); // guard div-by-zero
});

test('isKindergarten detects gan from the real name/type columns', () => {
  assert.equal(isKindergarten({ 'סוג מוסד': 'גן ילדים' }), true);   // mosdot type
  assert.equal(isKindergarten({ SHEM_MOSAD: 'גן שלוה' }), true);    // coords name
  assert.equal(isKindergarten({ SHEM_MOSAD: 'מעון יום' }), true);
  assert.equal(isKindergarten({ SHEM_MOSAD: 'בית ספר יסודי רחל' }), false);
  assert.equal(isKindergarten({ SHEM_MOSAD: 'תיכון גני תקווה' }), false); // place name, not "גן "
  assert.equal(isKindergarten({}), false);
});

test('normPikuah handles the real mosdot abbreviations + doubled-quote escaping', () => {
  // real dataset values carry CSV double-quote escaping
  assert.equal(normPikuah('"חמ""ד'), 'mamlachti_dati'); // religious-state (the gate)
  assert.equal(normPikuah('"מ""מ"'), 'mamlachti');      // state, escaped form
  assert.equal(normPikuah('חמ"ד'), 'mamlachti_dati');
  assert.equal(normPikuah('ממ"ד'), 'mamlachti_dati');
  assert.equal(normPikuah('ממלכתי דתי'), 'mamlachti_dati');
  assert.equal(normPikuah('מ"מ'), 'mamlachti');
  assert.equal(normPikuah('ממלכתי'), 'mamlachti');
  assert.equal(normPikuah('חרדי'), 'charedi');
  assert.equal(normSector('יהודי'), 'jewish');
  assert.equal(normSector('ערבי'), 'arab');
  assert.equal(normSector(''), '');
});
