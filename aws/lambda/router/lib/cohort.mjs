// cohort.mjs — the 11-cohort personalization taxonomy (Phase 2).
//
// A cohort is resolved from "signals" — a flat bag of what we know about the
// searcher. Signals come from TWO sources, cheapest first:
//   • querySignals(query)   — GET params the client already sent (no DB read)
//   • profileSignals(profile) — the persisted searchProfile (one DynamoDB get)
// index.mjs merges them (query wins) and calls cohortFromSignals().
//
// Pure + dependency-free so the taxonomy unit-tests without aws-sdk.

const bool = (v) => v === true || v === 'true' || v === '1';
const nOrU = (v) => { const n = Number(v); return Number.isFinite(n) ? n : undefined; };

// Signals straight off GET query params (fast path).
export function querySignals(query) {
  const q = query || {};
  return {
    household: q.household, vibe: q.vibe || q.vibePref, sector: q.sector,
    isOleh: bool(q.isOleh), langPref: q.langPref, isReligious: bool(q.isReligious),
    religiousStream: q.religiousStream, // 'dati_leumi' | 'charedi'
    lifeStage: q.lifeStage, age: nOrU(q.age),
    wfh: bool(q.wfh), carFree: bool(q.carFree),
    hasChildren: bool(q.hasChildren), expecting: bool(q.expecting),
    numChildren: nOrU(q.numChildren), childAge: nOrU(q.childAge),
    accessibilityNeed: bool(q.accessibilityNeed),
    isSolo: bool(q.isSolo), isInvestor: bool(q.isInvestor), intent: q.intent,
  };
}

// Signals from a persisted searchProfile (fields are {value,...}-wrapped).
export function profileSignals(profile) {
  const sp = (profile && profile.searchProfile) || {};
  const v = (k) => (sp[k] && sp[k].value !== undefined ? sp[k].value : undefined);
  return {
    household: v('household'), vibe: v('vibePref'), sector: v('sector'),
    isOleh: v('isOleh'), langPref: v('langPref'), isReligious: v('isReligious'),
    religiousStream: v('religiousStream'),
    lifeStage: v('lifeStage'), age: nOrU(v('age')),
    wfh: v('wfh'), carFree: v('carFree'),
    hasChildren: v('hasChildren'), expecting: v('expecting'),
    numChildren: nOrU(v('numChildren')), childAge: nOrU(v('childAge')),
    accessibilityNeed: v('accessibilityNeed'),
    isSolo: v('isSolo'), isInvestor: v('isInvestor'), intent: v('intent'),
  };
}

// Keep only meaningful values so a merge {...profile, ...definedOnly(query)}
// lets query override profile without wiping fields the query didn't mention.
export function definedOnly(o) {
  const r = {};
  for (const k in o) {
    const val = o[k];
    if (val === undefined || val === '' || val === false) continue;
    if (typeof val === 'number' && Number.isNaN(val)) continue;
    r[k] = val;
  }
  return r;
}

// The taxonomy: most-specific cohort first. Returns one of the 11 labels, a
// coarse household fallback, or null when there's no signal at all.
export function cohortFromSignals(s) {
  if (!s) return null;
  const vibe = typeof s.vibe === 'string' ? s.vibe : '';
  const truthy = (x) => x === true || x === 'true' || x === '1';

  // (a) intent crosses everything.
  if (truthy(s.isInvestor) || s.intent === 'investment') return 'investor';

  // (b) sector / community.
  if (s.sector === 'arab') return 'arab_family';
  if (truthy(s.isOleh) || s.langPref === 'en' || s.langPref === 'fr') return 'oleh';
  const religious = s.sector === 'jewish-religious' || truthy(s.isReligious);
  if (religious && (s.household === 'family' || (s.numChildren || 0) >= 4)) {
    // Split by stream — different communities with OPPOSITE school needs.
    return s.religiousStream === 'charedi' ? 'charedi' : 'dati_leumi';
  }

  // (c) life stage / accessibility.
  if (truthy(s.accessibilityNeed) || (s.age || 0) >= 65 || s.lifeStage === 'senior') return 'senior';

  // (d) mobility / family structure.
  if (truthy(s.hasChildren) && truthy(s.carFree)) return 'single_parent';
  if (truthy(s.expecting) ||
      (truthy(s.hasChildren) && s.childAge !== undefined && s.childAge < 2) ||
      (s.household === 'couple' && vibe.includes('משפח'))) return 'new_parents';
  if (truthy(s.wfh) && (s.household === 'single' || s.lifeStage === 'young-professional')) return 'remote';
  if (vibe.includes('סטודנט') || s.lifeStage === 'student' || s.household === 'student') return 'student';
  if (s.household === 'single' && vibe.includes('תוסס')) return 'young_professional';

  // (e) coarse household fallbacks.
  if (s.household === 'family' || vibe.includes('משפח')) return 'family';
  if (s.household === 'couple') return 'couple';
  if (s.household === 'single') return 'single';
  return null;
}
