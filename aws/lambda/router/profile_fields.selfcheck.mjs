// profile_fields.selfcheck.mjs — node-assert self-check for the batch-merge
// helper behind POST /profile/fields. Run:
//   node aws/lambda/router/profile_fields.selfcheck.mjs
//
// index.mjs pulls the AWS SDK at import, so rather than import it we mirror the
// PURE mergeProfileFields logic here VERBATIM and assert its contract:
//   - only allowlisted keys are written; non-allowlisted are dropped
//   - each written key is wrapped in {value, confidence, source, updatedAt}
//   - confidence is clamped to 0..1 (default 0.6); source truncated to 40 chars
//   - `written` counts only accepted keys
// Keep this copy in lockstep with mergeProfileFields in index.mjs.
import assert from 'node:assert/strict';

// A representative allowlist subset — must include the eligibility-gate fields.
const PROFILE_WRITABLE_FIELDS = new Set([
  'occupation', 'numChildren', 'hasPets', 'carFree', 'priceMax', 'priceMin',
  'household', 'cityPref', 'vibePref',
]);

// ── verbatim copy of mergeProfileFields from index.mjs ───────────────────────
function mergeProfileFields(current, fields, confidence, source) {
  const sp = (current && current.searchProfile) || {};
  const conf = typeof confidence === 'number' ? Math.max(0, Math.min(1, confidence)) : 0.6;
  const src = typeof source === 'string' ? source.slice(0, 40) : 'assistant';
  const now = new Date().toISOString();
  let written = 0;
  for (const [field, value] of Object.entries(fields || {})) {
    if (!PROFILE_WRITABLE_FIELDS.has(field)) continue;
    sp[field] = { value, confidence: conf, source: src, updatedAt: now };
    written += 1;
  }
  return { sp, written };
}

let n = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); n++; };

// ── allowlisted keys are merged, non-allowlisted are dropped ─────────────────
{
  const { sp, written } = mergeProfileFields(null,
    { occupation: 'hi-tech', hacker: 'x', priceMax: 6000 }, 0.9, 'profile');
  ok(written === 2, 'writes 2 allowlisted keys');
  ok(sp.occupation && sp.occupation.value === 'hi-tech', 'occupation stored');
  ok(sp.priceMax && sp.priceMax.value === 6000, 'priceMax stored');
  ok(!('hacker' in sp), 'non-allowlisted key dropped');
}

// ── envelope shape: value/confidence/source/updatedAt ────────────────────────
{
  const { sp } = mergeProfileFields(null, { carFree: true }, 0.9, 'profile');
  const e = sp.carFree;
  ok(e.value === true, 'value preserved (boolean)');
  ok(e.confidence === 0.9, 'confidence stored');
  ok(e.source === 'profile', 'source stored');
  ok(typeof e.updatedAt === 'string' && e.updatedAt.includes('T'), 'updatedAt ISO');
}

// ── all six eligibility-gate fields are writable ─────────────────────────────
{
  const { written } = mergeProfileFields(null,
    { occupation: 'x', numChildren: 2, hasPets: false, carFree: true, priceMax: 5000, priceMin: 2000 },
    0.9, 'profile');
  ok(written === 6, 'all six gate fields writable');
}

// ── existing searchProfile is preserved and merged, not clobbered ────────────
{
  const current = { searchProfile: { cityPref: { value: 'תל אביב', confidence: 1, source: 't' } } };
  const { sp, written } = mergeProfileFields(current, { priceMax: 7000 }, 0.9, 'profile');
  ok(written === 1, 'one new field');
  ok(sp.cityPref && sp.cityPref.value === 'תל אביב', 'pre-existing field kept');
  ok(sp.priceMax && sp.priceMax.value === 7000, 'new field added');
}

// ── nothing allowlisted → written 0 (route then skips the DB write) ──────────
{
  const { written } = mergeProfileFields(null, { foo: 1, bar: 2 }, 0.9, 'profile');
  ok(written === 0, 'all-dropped → written 0');
  const empty = mergeProfileFields(null, {}, 0.9, 'profile');
  ok(empty.written === 0, 'empty batch → written 0');
  const nullish = mergeProfileFields(null, null, 0.9, 'profile');
  ok(nullish.written === 0, 'null fields → written 0');
}

// ── confidence clamp + source truncation ─────────────────────────────────────
{
  const hi = mergeProfileFields(null, { priceMin: 1 }, 5, 'profile');
  ok(hi.sp.priceMin.confidence === 1, 'confidence clamped high → 1');
  const lo = mergeProfileFields(null, { priceMin: 1 }, -3, 'profile');
  ok(lo.sp.priceMin.confidence === 0, 'confidence clamped low → 0');
  const def = mergeProfileFields(null, { priceMin: 1 }, undefined, 'profile');
  ok(def.sp.priceMin.confidence === 0.6, 'confidence default 0.6');
  const long = mergeProfileFields(null, { priceMin: 1 }, 0.9, 'x'.repeat(80));
  ok(long.sp.priceMin.source.length === 40, 'source truncated to 40');
}

console.log(`profile_fields.selfcheck: ${n} assertions passed`);
