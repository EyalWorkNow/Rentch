// Self-check for the fail-open audience visibility gate. No test framework —
// run: node aws/lambda/router/audience_gate.selfcheck.mjs
// Exits non-zero on the first failed assertion.
import assert from 'node:assert/strict';
import { isListingVisibleToCohort, COHORT_KEYS } from './lib/cohort.mjs';

const exclusive = (audienceCohorts, extra = {}) => ({
  id: 'p1', ownerUserId: 'owner-1', exclusiveToAudience: true,
  audienceCohorts, ...extra,
});

// 1) caller's cohort IS in the audience → visible.
assert.equal(isListingVisibleToCohort(exclusive(['family', 'couple']), 'family', 'tenant-9'), true,
  'cohort in list should be visible');

// 2) caller's cohort NOT in the audience + exclusive → hidden.
assert.equal(isListingVisibleToCohort(exclusive(['family']), 'student', 'tenant-9'), false,
  'known cohort not in list + exclusive should be hidden');

// 3) unknown / unrecognized cohort → fail-open visible.
assert.equal(isListingVisibleToCohort(exclusive(['family']), 'martian', 'tenant-9'), true,
  'unrecognized cohort should be visible (fail-open)');

// 4) null / empty caller cohort → fail-open visible.
assert.equal(isListingVisibleToCohort(exclusive(['family']), null, 'tenant-9'), true,
  'null cohort should be visible (fail-open)');
assert.equal(isListingVisibleToCohort(exclusive(['family']), '', 'tenant-9'), true,
  'empty cohort should be visible (fail-open)');

// 5) owner viewing their OWN exclusive listing → always visible.
assert.equal(isListingVisibleToCohort(exclusive(['family']), 'student', 'owner-1'), true,
  'owner should always see own listing');

// 6) exclusive but EMPTY audience → fail-open visible.
assert.equal(isListingVisibleToCohort(exclusive([]), 'student', 'tenant-9'), true,
  'empty audienceCohorts should be visible (fail-open)');

// 7) NOT exclusive → always visible regardless of cohort mismatch.
assert.equal(
  isListingVisibleToCohort({ ...exclusive(['family']), exclusiveToAudience: false }, 'student', 'tenant-9'),
  true, 'non-exclusive listing should be visible');

// 8) missing exclusiveToAudience (undefined) → visible.
assert.equal(isListingVisibleToCohort({ audienceCohorts: ['family'] }, 'student', 'tenant-9'), true,
  'listing without exclusiveToAudience should be visible');

// 9) null/garbage listing → visible (never throws).
assert.equal(isListingVisibleToCohort(null, 'student', 'tenant-9'), true, 'null listing → visible');

// Sanity: taxonomy is exactly the 14 keys.
assert.equal(COHORT_KEYS.length, 14, 'expected 14 cohort keys');

console.log('audience_gate self-check: ALL PASS (10 assertions)');
