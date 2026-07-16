// eligibility.mjs — per-listing tenant ELIGIBILITY GATE (pure + testable).
//
// A landlord attaches precise tenant criteria to a listing; only tenants whose
// searchProfile matches get to SEE the listing in GET /properties. Each rule has
// an "importance" that controls HOW HARD it gates visibility:
//
//   • must:      rule fails OR tenant value UNKNOWN → HIDE  (fail-closed)
//   • important: HIDE only if the tenant value is KNOWN and the rule fails;
//                UNKNOWN keeps the listing visible                (fail-open)
//   • prefer:    never affects visibility (reserved for ranking; v1 no-op)
//
// Dependency-free so it unit-tests without aws-sdk. The evaluator reads the
// caller's persisted searchProfile (`{ <field>: {value, ...} }`) — same shape
// cohort.mjs/profileSignals reads.

// Read a tenant field's raw value off a users-table row's searchProfile.
// Returns `undefined` when the field is "unknown" (entry missing, or its value
// is null/undefined/''), so callers get one consistent unknown sentinel.
export function readFieldValue(profile, field) {
  const sp = (profile && profile.searchProfile) || {};
  const entry = sp[field];
  if (!entry || typeof entry !== 'object') return undefined;
  const v = entry.value;
  if (v === null || v === undefined || v === '') return undefined;
  return v;
}

const num = (v) => {
  if (v === null || v === undefined || v === '') return undefined;
  const n = Number(v);
  return Number.isFinite(n) ? n : undefined;
};
const inList = (v, list) => Array.isArray(list) && list.includes(v);

// Move-in urgency ranking: lower = able to move sooner. A 'flexible' tenant can
// move whenever, so it ranks as 0 (satisfies any requirement). Returns undefined
// for an unrecognized token so callers can fail such rules closed.
const MOVE_IN_RANK = { immediate: 0, month: 1, quarter: 2, flexible: 0 };
const urgencyRank = (v) => (typeof v === 'string' && v in MOVE_IN_RANK ? MOVE_IN_RANK[v] : undefined);

// Criteria catalog: key → { field, pass(tenantValue, ruleValue) → boolean }.
// `field` names the tenant searchProfile key that decides KNOWN vs UNKNOWN.
// `pass` is only ever called with a KNOWN (non-undefined) tenantValue.
const CRITERIA = {
  budgetMin:     { field: 'priceMax',        pass: (tv, rv) => { const t = num(tv), r = num(rv); return t !== undefined && r !== undefined && t >= r; } },
  maxChildren:   { field: 'numChildren',     pass: (tv, rv) => { const t = num(tv), r = num(rv); return t !== undefined && r !== undefined && t <= r; } },
  noPets:        { field: 'hasPets',         pass: (tv) => tv === false },
  hasCar:        { field: 'carFree',         pass: (tv) => tv === false },
  occupation:    { field: 'occupation',      pass: (tv, rv) => inList(tv, rv) },
  wfh:           { field: 'wfh',             pass: (tv) => tv === true },
  household:     { field: 'household',       pass: (tv, rv) => inList(tv, rv) },
  lifeStage:     { field: 'lifeStage',       pass: (tv, rv) => inList(tv, rv) },
  oleh:          { field: 'isOleh',          pass: (tv) => tv === true },
  minAge:        { field: 'age',             pass: (tv, rv) => { const t = num(tv), r = num(rv); return t !== undefined && r !== undefined && t >= r; } },
  maxAge:        { field: 'age',             pass: (tv, rv) => { const t = num(tv), r = num(rv); return t !== undefined && r !== undefined && t <= r; } },
  accessibility: { field: 'accessibilityNeed', pass: (tv) => tv === true },
  // Tenant's desired room count meets/exceeds the required minimum.
  minRooms:      { field: 'minRooms',          pass: (tv, rv) => { const t = num(tv), r = num(rv); return t !== undefined && r !== undefined && t >= r; } },
  // Tenant can move in at least as soon as the listing requires (rank ≤ required).
  moveInWithin:  { field: 'moveInBucket',      pass: (tv, rv) => { const t = urgencyRank(tv), r = urgencyRank(rv); return t !== undefined && r !== undefined && t <= r; } },
};

// PURE: does `profile` (a users-table row) pass `listing`'s eligibility gate?
//   • eligibility absent/disabled          → visible
//   • caller is the listing owner           → always visible
//   • enabled with empty rules              → visible
//   • otherwise visible iff no must-rule triggers a hide AND no important-rule
//     known-fails (unknown fields keep important-rules open, hide must-rules).
export function passesEligibility(listing, profile, callerUid) {
  if (!listing || typeof listing !== 'object') return true;
  const elig = listing.eligibility;
  if (!elig || elig.enabled !== true) return true;

  // Owner always sees their own listing.
  if (callerUid && listing.ownerUserId &&
      String(listing.ownerUserId) === String(callerUid)) return true;

  const rules = Array.isArray(elig.rules) ? elig.rules : [];
  if (rules.length === 0) return true;

  for (const rule of rules) {
    if (!rule || typeof rule !== 'object') continue;
    const spec = CRITERIA[rule.key];
    if (!spec) continue; // unknown criterion → ignore (forward-compatible)
    const importance = rule.importance;
    if (importance === 'prefer') continue; // ranking-only, never gates visibility

    const tenantValue = readFieldValue(profile, spec.field);
    const known = tenantValue !== undefined;

    if (importance === 'must') {
      // Fail-closed: unknown OR failing rule hides the listing.
      if (!known || !spec.pass(tenantValue, rule.value)) return false;
    } else if (importance === 'important') {
      // Fail-open: only a KNOWN value that fails hides the listing.
      if (known && !spec.pass(tenantValue, rule.value)) return false;
    }
    // any other importance value → treat as non-gating (ignore)
  }
  return true;
}
