// Tests for the 11-cohort taxonomy + signal extraction (no aws-sdk/network).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  querySignals, profileSignals, definedOnly, cohortFromSignals,
} from '../lambda/router/lib/cohort.mjs';
import { rankWeightsFor, cohortPriceTarget } from '../lambda/router/lib/ranking.mjs';

test('taxonomy priority: intent > sector > lifeStage > household', () => {
  // investor intent wins over everything
  assert.equal(cohortFromSignals({ isInvestor: true, household: 'family', sector: 'arab' }), 'investor');
  // sector arab → arab_family
  assert.equal(cohortFromSignals({ sector: 'arab', household: 'family' }), 'arab_family');
  // oleh via langPref
  assert.equal(cohortFromSignals({ langPref: 'en', household: 'family' }), 'oleh');
  // religious family
  assert.equal(cohortFromSignals({ sector: 'jewish-religious', numChildren: 5 }), 'religious_family');
  // senior via age
  assert.equal(cohortFromSignals({ age: 70, household: 'couple' }), 'senior');
  // single parent (kids + carFree)
  assert.equal(cohortFromSignals({ hasChildren: true, carFree: true }), 'single_parent');
  // new parents (expecting)
  assert.equal(cohortFromSignals({ expecting: true, household: 'couple' }), 'new_parents');
  // remote (wfh + single)
  assert.equal(cohortFromSignals({ wfh: true, household: 'single' }), 'remote');
  // student via vibe
  assert.equal(cohortFromSignals({ vibe: 'סטודנטיאלי' }), 'student');
  // young professional (single + vibrant)
  assert.equal(cohortFromSignals({ household: 'single', vibe: 'תוסס' }), 'young_professional');
});

test('coarse household fallbacks and null', () => {
  assert.equal(cohortFromSignals({ household: 'family' }), 'family');
  assert.equal(cohortFromSignals({ household: 'couple' }), 'couple');
  assert.equal(cohortFromSignals({ household: 'single' }), 'single');
  assert.equal(cohortFromSignals({}), null);
  assert.equal(cohortFromSignals(null), null);
});

test('querySignals parses GET params (booleans + numbers)', () => {
  const s = querySignals({ household: 'single', wfh: 'true', age: '31', vibe: 'תוסס' });
  assert.equal(s.household, 'single');
  assert.equal(s.wfh, true);
  assert.equal(s.age, 31);
  // wfh+single is the stronger signal → remote (beats young_professional).
  assert.equal(cohortFromSignals(s), 'remote');
  // without wfh, single+vibrant → young_professional.
  assert.equal(cohortFromSignals(querySignals({ household: 'single', vibe: 'תוסס' })), 'young_professional');
});

test('profileSignals unwraps {value} fields', () => {
  const profile = { searchProfile: { household: { value: 'family' }, sector: { value: 'arab' } } };
  assert.equal(cohortFromSignals(profileSignals(profile)), 'arab_family');
});

test('definedOnly lets query override profile without wiping gaps', () => {
  const profile = profileSignals({ searchProfile: { household: { value: 'family' }, vibePref: { value: 'שקט' } } });
  const query = definedOnly(querySignals({ isInvestor: 'true' })); // only investor set
  const merged = { ...profile, ...query };
  assert.equal(merged.household, 'family');   // preserved from profile
  assert.equal(merged.isInvestor, true);      // added from query
  assert.equal(cohortFromSignals(merged), 'investor');
});

test('every taxonomy label has ranking weights + a price target', () => {
  const labels = ['young_professional', 'new_parents', 'religious_family', 'student',
    'oleh', 'senior', 'single_parent', 'remote', 'arab_family', 'investor',
    'family', 'couple', 'single'];
  for (const c of labels) {
    assert.ok(rankWeightsFor(c).neighborhood > 0, `${c} missing weights`);
    assert.ok(['low', 'mid', 'high', 'invert'].includes(cohortPriceTarget(c)), `${c} bad priceTarget`);
  }
  assert.equal(cohortPriceTarget('investor'), 'invert');
  assert.equal(cohortPriceTarget('young_professional'), 'high');
});
