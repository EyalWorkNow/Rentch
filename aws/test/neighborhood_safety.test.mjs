// Pure-logic tests for the neighborhood parsers (no network, no aws-sdk).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { normalizeLocalityName } from '../lambda/router/lib/muni.mjs';
import { isKindergarten, normPikuah, normSector } from '../lambda/router/lib/neighborhood.mjs';

test('normalizeLocalityName strips muni prefixes and punctuation', () => {
  const k = normalizeLocalityName('תל אביב');
  assert.equal(normalizeLocalityName('עיריית תל אביב'), k);
  assert.equal(normalizeLocalityName('  תל-אביב  '), k);
  assert.equal(normalizeLocalityName('מ. מ. אבו גוש'), normalizeLocalityName('אבו גוש'));
  assert.equal(normalizeLocalityName(''), '');
  assert.equal(normalizeLocalityName(null), '');
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
