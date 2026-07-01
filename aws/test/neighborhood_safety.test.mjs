// Pure-logic tests for the safety locality-join (no network, no aws-sdk).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeLocalityName } from '../lambda/router/lib/muni.mjs';
import { buildLocalityMap, crimeCountToSafety } from '../lambda/router/lib/neighborhood.mjs';

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
