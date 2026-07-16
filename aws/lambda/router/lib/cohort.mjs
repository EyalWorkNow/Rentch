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

// Pure cohort resolution: query params win (fast path), else fall back to the
// (already-loaded) profile with query overriding profile fields. index.mjs wraps
// this with the DynamoDB profile load; this function is the unit-testable core.
export function resolveCohortFrom(query, profile) {
  const qs = querySignals(query);
  const fromQuery = cohortFromSignals(qs);
  if (fromQuery) return fromQuery;
  return cohortFromSignals({ ...profileSignals(profile), ...definedOnly(qs) });
}

// ── Audience targeting (Phase — landlord-declared cohorts) ───────────────────
// The complete set of valid cohort keys cohortFromSignals can return. Shared as
// the single source of truth for: validating landlord-declared audiences, the
// Gemini suggestion enum, and the visibility gate below.
export const COHORT_KEYS = [
  'investor', 'arab_family', 'oleh', 'charedi', 'dati_leumi', 'senior',
  'single_parent', 'new_parents', 'remote', 'student', 'young_professional',
  'family', 'couple', 'single',
];

// Short Hebrew definition per cohort — fed to Gemini so the audience-suggestion
// prompt reasons over a well-defined taxonomy (not free-association).
export const COHORT_DEFS = {
  investor: 'משקיע/ת נדל"ן — קונה לתשואה/השקעה, לא למגורים עצמיים',
  arab_family: 'משפחה ערבית — קרבה לקהילה ולשירותים ערביים',
  oleh: 'עולים חדשים / דוברי אנגלית או צרפתית, קהילה תומכת קליטה',
  charedi: 'משפחה חרדית — בית כנסת, מוסדות חרדיים, אופי שכונה דתי',
  dati_leumi: 'משפחה דתית-לאומית — עירוב, בתי כנסת, מוסדות דתיים-לאומיים',
  senior: 'גיל שלישי / צרכי נגישות — מעלית, קומה נמוכה, קרבה למרפאות',
  single_parent: 'הורה יחיד/ה — קרבה לתחבורה, גנים ובתי ספר, ללא רכב',
  new_parents: 'הורים טריים / הריון — שקט, מרחב לתינוק, קרבה לגנים',
  remote: 'עובד/ת מהבית (סינגל/צעיר) — חדר עבודה, אינטרנט, שקט ביום',
  student: 'סטודנט/ית — מחיר נמוך, קרבה לקמפוס ולתחבורה, שותפים',
  young_professional: 'צעיר/ה מקצועי/ת — עיר תוססת, חיי לילה, קרבה למרכז',
  family: 'משפחה (כללי) — מספר חדרים, קרבה לבתי ספר, שכונה שקטה',
  couple: 'זוג — 2-3 חדרים, שכונה נעימה',
  single: 'רווק/ה — יחידה קטנה, גמישות, מיקום נוח',
};

// Fail-OPEN visibility gate for the tenant-facing catalog. Pure + dependency-free
// so it unit-tests without aws-sdk. A listing is HIDDEN from a caller ONLY when
// ALL of these hold — otherwise it is always shown:
//   • listing.exclusiveToAudience === true, AND
//   • listing.audienceCohorts is a non-empty array, AND
//   • the caller is NOT the listing owner, AND
//   • the caller's resolved cohort is a non-empty KNOWN cohort key, AND
//   • that cohort is NOT in listing.audienceCohorts.
// Any missing/unknown signal (null cohort, unknown cohort, empty audience, not
// exclusive, owner viewing own listing) → visible. Never throws.
export function isListingVisibleToCohort(listing, callerCohort, callerUid) {
  if (!listing || typeof listing !== 'object') return true;
  if (listing.exclusiveToAudience !== true) return true;       // not restricted
  // Owner always sees their own listing (never hide a landlord's row from them).
  if (callerUid && listing.ownerUserId &&
      String(listing.ownerUserId) === String(callerUid)) return true;
  const audience = Array.isArray(listing.audienceCohorts) ? listing.audienceCohorts : [];
  if (audience.length === 0) return true;                      // no audience → open
  if (!callerCohort || typeof callerCohort !== 'string') return true; // unknown → open
  if (!COHORT_KEYS.includes(callerCohort)) return true;        // unrecognized → open
  return audience.includes(callerCohort);                      // gate on membership
}
