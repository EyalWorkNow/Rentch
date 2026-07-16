// eligibility.selfcheck.mjs — dependency-free assertions for passesEligibility.
// Run: node aws/lambda/router/lib/eligibility.selfcheck.mjs
//
// Focus: the source-aware `must` gate. A must rule may HIDE on a FAILED
// comparison ONLY when the tenant value is DECLARED (source==='profile').
// Truly-missing values still fail closed; inferred values never hard-exclude.

import { passesEligibility } from './eligibility.mjs';

let pass = 0, fail = 0;
function check(name, got, want) {
  if (got === want) { pass += 1; return; }
  fail += 1;
  console.error(`FAIL: ${name} → got ${got}, want ${want}`);
}

// Build a listing with a single rule.
const listing = (key, importance, value) => ({
  eligibility: { enabled: true, rules: [{ key, importance, value }] },
});
// Build a tenant profile with one searchProfile field entry.
const profile = (field, value, source) => ({
  searchProfile: { [field]: { value, source, updatedAt: 1 } },
});

// priceMax rule: budgetMin requires tenant priceMax >= listing.value (2000).
// A tenant priceMax of 1000 FAILS the comparison.

// 1) must + DECLARED (source='profile') failing → HIDE (not visible).
check('must declared failing → hide',
  passesEligibility(listing('budgetMin', 'must', 2000), profile('priceMax', 1000, 'profile'), 'u1'),
  false);

// 2) must + SAME value but source='search' (inferred) failing → NOT hide (visible).
check('must inferred(search) failing → visible',
  passesEligibility(listing('budgetMin', 'must', 2000), profile('priceMax', 1000, 'search'), 'u1'),
  true);

// 3) must + truly UNKNOWN (no field) → HIDE (fail-closed).
check('must unknown → hide',
  passesEligibility(listing('budgetMin', 'must', 2000), { searchProfile: {} }, 'u1'),
  false);

// 4) must + DECLARED passing (priceMax 3000 >= 2000) → visible.
check('must declared passing → visible',
  passesEligibility(listing('budgetMin', 'must', 2000), profile('priceMax', 3000, 'profile'), 'u1'),
  true);

// 5) important + source='search' failing → HIDE (important is source-agnostic).
check('important inferred(search) failing → hide',
  passesEligibility(listing('budgetMin', 'important', 2000), profile('priceMax', 1000, 'search'), 'u1'),
  false);

// 6) important + UNKNOWN → visible (fail-open).
check('important unknown → visible',
  passesEligibility(listing('budgetMin', 'important', 2000), { searchProfile: {} }, 'u1'),
  true);

console.log(`\neligibility.selfcheck: ${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
