// eligibility.selfcheck.mjs — node-assert self-check for the eligibility gate.
// Run: node aws/lambda/router/eligibility.selfcheck.mjs
import assert from 'node:assert/strict';
import { passesEligibility, readFieldValue } from './lib/eligibility.mjs';

// Build a users-table row with the given searchProfile fields.
const profile = (fields) => ({
  searchProfile: Object.fromEntries(
    // source:'profile' = declared data (must-rules hard-gate only on declared).
    Object.entries(fields).map(([k, v]) => [k, { value: v, confidence: 1, source: 'profile' }])),
});
// Build a listing with an eligibility block.
const listing = (rules, extra = {}) => ({
  ownerUserId: 'owner-1',
  eligibility: { enabled: true, rules },
  ...extra,
});

let n = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); n++; };

// ── readFieldValue helper ────────────────────────────────────────────────────
ok(readFieldValue(profile({ age: 30 }), 'age') === 30, 'read known');
ok(readFieldValue(profile({}), 'age') === undefined, 'read missing → undefined');
ok(readFieldValue({ searchProfile: { age: { value: '' } } }, 'age') === undefined, 'read empty → undefined');
ok(readFieldValue({ searchProfile: { age: { value: null } } }, 'age') === undefined, 'read null → undefined');
ok(readFieldValue(null, 'age') === undefined, 'read no profile → undefined');

// ── disabled / no eligibility → always visible ───────────────────────────────
ok(passesEligibility({ eligibility: { enabled: false, rules: [] } }, profile({}), 'x') === true, 'disabled shows');
ok(passesEligibility({}, profile({}), 'x') === true, 'no eligibility shows');
ok(passesEligibility(listing([]), profile({}), 'x') === true, 'enabled + empty rules shows');

// ── owner always shows (even when a must-rule would hide) ─────────────────────
ok(passesEligibility(
  listing([{ key: 'minAge', value: 99, importance: 'must' }]),
  profile({ age: 20 }), 'owner-1') === true, 'owner always shows');

// ── must: fail hides, unknown hides, pass shows ──────────────────────────────
ok(passesEligibility(
  listing([{ key: 'minAge', value: 25, importance: 'must' }]),
  profile({ age: 20 }), 'tenant') === false, 'must known-fail hides');
ok(passesEligibility(
  listing([{ key: 'minAge', value: 25, importance: 'must' }]),
  profile({}), 'tenant') === false, 'must unknown hides');
ok(passesEligibility(
  listing([{ key: 'minAge', value: 25, importance: 'must' }]),
  profile({ age: 30 }), 'tenant') === true, 'must pass shows');

// ── important: unknown shows, known-fail hides, pass shows ────────────────────
ok(passesEligibility(
  listing([{ key: 'minAge', value: 25, importance: 'important' }]),
  profile({}), 'tenant') === true, 'important unknown shows');
ok(passesEligibility(
  listing([{ key: 'minAge', value: 25, importance: 'important' }]),
  profile({ age: 20 }), 'tenant') === false, 'important known-fail hides');
ok(passesEligibility(
  listing([{ key: 'minAge', value: 25, importance: 'important' }]),
  profile({ age: 30 }), 'tenant') === true, 'important pass shows');

// ── prefer: never affects visibility (even on a hard fail / unknown) ──────────
ok(passesEligibility(
  listing([{ key: 'minAge', value: 99, importance: 'prefer' }]),
  profile({ age: 20 }), 'tenant') === true, 'prefer known-fail shows');
ok(passesEligibility(
  listing([{ key: 'minAge', value: 99, importance: 'prefer' }]),
  profile({}), 'tenant') === true, 'prefer unknown shows');

// ── budgetMin: priceMax >= value ─────────────────────────────────────────────
ok(passesEligibility(
  listing([{ key: 'budgetMin', value: 5000, importance: 'must' }]),
  profile({ priceMax: 6000 }), 'tenant') === true, 'budgetMin pass');
ok(passesEligibility(
  listing([{ key: 'budgetMin', value: 5000, importance: 'must' }]),
  profile({ priceMax: 4000 }), 'tenant') === false, 'budgetMin fail hides');

// ── maxChildren: numChildren <= value ────────────────────────────────────────
ok(passesEligibility(
  listing([{ key: 'maxChildren', value: 2, importance: 'must' }]),
  profile({ numChildren: 1 }), 'tenant') === true, 'maxChildren pass');
ok(passesEligibility(
  listing([{ key: 'maxChildren', value: 2, importance: 'must' }]),
  profile({ numChildren: 4 }), 'tenant') === false, 'maxChildren fail hides');
// numChildren of 0 is a KNOWN value (not unknown) and must pass.
ok(passesEligibility(
  listing([{ key: 'maxChildren', value: 2, importance: 'must' }]),
  profile({ numChildren: 0 }), 'tenant') === true, 'maxChildren zero known-pass');

// ── occupation: occupation ∈ value[] ─────────────────────────────────────────
ok(passesEligibility(
  listing([{ key: 'occupation', value: ['hi-tech', 'medic'], importance: 'must' }]),
  profile({ occupation: 'hi-tech' }), 'tenant') === true, 'occupation pass');
ok(passesEligibility(
  listing([{ key: 'occupation', value: ['hi-tech', 'medic'], importance: 'must' }]),
  profile({ occupation: 'student' }), 'tenant') === false, 'occupation fail hides');

// ── noPets: hasPets === false ────────────────────────────────────────────────
ok(passesEligibility(
  listing([{ key: 'noPets', value: null, importance: 'must' }]),
  profile({ hasPets: false }), 'tenant') === true, 'noPets pass (no pets)');
ok(passesEligibility(
  listing([{ key: 'noPets', value: null, importance: 'must' }]),
  profile({ hasPets: true }), 'tenant') === false, 'noPets fail hides (has pets)');

// ── multi-rule: any must-fail hides; important-unknown doesn't ────────────────
ok(passesEligibility(
  listing([
    { key: 'budgetMin', value: 5000, importance: 'must' },      // pass
    { key: 'occupation', value: ['medic'], importance: 'important' }, // unknown → open
  ]),
  profile({ priceMax: 6000 }), 'tenant') === true, 'multi: must-pass + important-unknown shows');
ok(passesEligibility(
  listing([
    { key: 'budgetMin', value: 5000, importance: 'must' },      // pass
    { key: 'noPets', value: null, importance: 'must' },         // fail
  ]),
  profile({ priceMax: 6000, hasPets: true }), 'tenant') === false, 'multi: one must-fail hides');

// ── minRooms: desired minRooms >= value ──────────────────────────────────────
ok(passesEligibility(
  listing([{ key: 'minRooms', value: 3, importance: 'must' }]),
  profile({ minRooms: 4 }), 'tenant') === true, 'minRooms pass (4 >= 3)');
ok(passesEligibility(
  listing([{ key: 'minRooms', value: 3, importance: 'must' }]),
  profile({ minRooms: 2 }), 'tenant') === false, 'minRooms fail hides (2 >= 3)');
ok(passesEligibility(
  listing([{ key: 'minRooms', value: 3, importance: 'must' }]),
  profile({}), 'tenant') === false, 'minRooms unknown + must hides');

// ── moveInWithin: urgencyRank(tenant) <= urgencyRank(required) ────────────────
ok(passesEligibility(
  listing([{ key: 'moveInWithin', value: 'month', importance: 'must' }]),
  profile({ moveInBucket: 'immediate' }), 'tenant') === true, 'moveInWithin immediate vs month → pass');
ok(passesEligibility(
  listing([{ key: 'moveInWithin', value: 'month', importance: 'must' }]),
  profile({ moveInBucket: 'quarter' }), 'tenant') === false, 'moveInWithin quarter vs month → fail hides');
ok(passesEligibility(
  listing([{ key: 'moveInWithin', value: 'quarter', importance: 'must' }]),
  profile({ moveInBucket: 'flexible' }), 'tenant') === true, 'moveInWithin flexible vs quarter → pass (flexible=0)');
ok(passesEligibility(
  listing([{ key: 'moveInWithin', value: 'month', importance: 'important' }]),
  profile({}), 'tenant') === true, 'moveInWithin unknown + important shows (fail-open)');

console.log(`eligibility.selfcheck: ${n} assertions passed`);
