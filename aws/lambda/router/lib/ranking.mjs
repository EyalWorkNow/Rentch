// ranking.mjs — cohort-aware scoring for the MAIN feed (attachRankSignals).
//
// Phase 0/1 of the personalization spec: the main feed's rankScore now (a) uses
// a per-cohort weight-set, (b) folds in the public-data neighborhood fit and the
// semantic similarity, and (c) shapes price-fit by a per-cohort target
// (cheap-end / mid / premium / invert) instead of a flat "anywhere in budget".
//
// Pure + dependency-free so it unit-tests without the aws-sdk. Cohort comes from
// profileCohort() in index.mjs: family | single | student | couple | null.

const clamp01 = (x) => Math.max(0, Math.min(1, x));

// Per-cohort feature weights (each set sums to ~1 for interpretability; the score
// is only a sort key so exact sums don't matter). Six features: the original
// four + neighborhood + semantic.
// Six-feature weight-sets. Coarse buckets (family/couple/student/single) are the
// household-only fallback; the 11 fine cohorts (Phase 2, per the persona spec
// §2) are used when richer signals resolve. Each set sums to ~1 (sort key, so
// exact sums don't matter). rankWeightsFor() falls back to `default`.
export const RANK_WEIGHTS_BY_COHORT = {
  default:            { freshness: 0.25, popularity: 0.20, completeness: 0.15, priceFit: 0.20, neighborhood: 0.12, semantic: 0.08 },
  // ── coarse household fallbacks ──
  family:             { freshness: 0.18, popularity: 0.10, completeness: 0.17, priceFit: 0.22, neighborhood: 0.25, semantic: 0.08 },
  couple:             { freshness: 0.20, popularity: 0.12, completeness: 0.15, priceFit: 0.22, neighborhood: 0.23, semantic: 0.08 },
  student:            { freshness: 0.20, popularity: 0.10, completeness: 0.10, priceFit: 0.30, neighborhood: 0.22, semantic: 0.08 },
  single:             { freshness: 0.25, popularity: 0.15, completeness: 0.15, priceFit: 0.15, neighborhood: 0.18, semantic: 0.12 },
  // ── 11 fine cohorts ──
  young_professional: { freshness: 0.25, popularity: 0.10, completeness: 0.15, priceFit: 0.12, neighborhood: 0.20, semantic: 0.18 },
  new_parents:        { freshness: 0.15, popularity: 0.10, completeness: 0.17, priceFit: 0.23, neighborhood: 0.27, semantic: 0.08 },
  dati_leumi:         { freshness: 0.10, popularity: 0.08, completeness: 0.20, priceFit: 0.22, neighborhood: 0.30, semantic: 0.10 },
  charedi:            { freshness: 0.10, popularity: 0.08, completeness: 0.20, priceFit: 0.22, neighborhood: 0.30, semantic: 0.10 },
  oleh:               { freshness: 0.20, popularity: 0.08, completeness: 0.15, priceFit: 0.12, neighborhood: 0.27, semantic: 0.18 },
  senior:             { freshness: 0.12, popularity: 0.05, completeness: 0.20, priceFit: 0.13, neighborhood: 0.35, semantic: 0.15 },
  single_parent:      { freshness: 0.13, popularity: 0.08, completeness: 0.12, priceFit: 0.27, neighborhood: 0.30, semantic: 0.10 },
  remote:             { freshness: 0.22, popularity: 0.10, completeness: 0.13, priceFit: 0.20, neighborhood: 0.17, semantic: 0.18 },
  arab_family:        { freshness: 0.12, popularity: 0.08, completeness: 0.20, priceFit: 0.13, neighborhood: 0.32, semantic: 0.15 },
  investor:           { freshness: 0.18, popularity: 0.15, completeness: 0.07, priceFit: 0.20, neighborhood: 0.22, semantic: 0.18 },
};

export function rankWeightsFor(cohort) {
  return RANK_WEIGHTS_BY_COHORT[cohort] || RANK_WEIGHTS_BY_COHORT.default;
}

// Where in the budget window a cohort's ideal sits.
//   low    — cheap end best (budget-sensitive)
//   high   — premium end best (lifestyle buyers)
//   mid    — peak in the middle (neutral default)
//   invert — cheaper is always better (investor/yield); treated like `low` here
const COHORT_PRICE_TARGET = {
  // coarse
  family: 'low', couple: 'low', student: 'low', single: 'mid',
  // fine (spec §6: price is asymmetric — most want the cheap end, a few premium)
  young_professional: 'high', new_parents: 'low', dati_leumi: 'low', charedi: 'low',
  oleh: 'high', senior: 'low', single_parent: 'low', remote: 'low',
  arab_family: 'high', investor: 'invert',
};
export function cohortPriceTarget(cohort) {
  return COHORT_PRICE_TARGET[cohort] || 'mid';
}

// In-window shape as a function of t (0 = cheap end, 1 = expensive end).
function priceShape(t, priceTarget) {
  switch (priceTarget) {
    case 'low':
    case 'invert': return 1 - 0.6 * t;          // cheap end best   → [0.4, 1]
    case 'high':   return 0.4 + 0.6 * t;         // premium end best → [0.4, 1]
    case 'mid':
    default:       return 1 - Math.abs(t - 0.5); // middle best      → [0.5, 1]
  }
}

// Closeness of a listing price to the cohort's ideal within the budget window,
// decaying CONTINUOUSLY from the boundary value once outside it (so a listing
// just over budget is never scored above one at the top of budget).
export function priceFitScore(price, { minBudget, maxBudget, targetPrice }, priceTarget = 'mid') {
  if (!Number.isFinite(price) || price <= 0) return 0.5;
  if (minBudget !== undefined || maxBudget !== undefined) {
    const lo = minBudget ?? 0;
    const hi = maxBudget ?? Infinity;
    if (hi === Infinity || hi <= lo) return price >= lo ? 1.0 : 0.5;
    if (price >= lo && price <= hi) {
      return priceShape((price - lo) / (hi - lo), priceTarget);
    }
    // Out of window: decay from the nearer boundary's in-window score toward 0.
    const boundary = price < lo ? priceShape(0, priceTarget) : priceShape(1, priceTarget);
    const overshoot = price < lo ? (lo - price) / lo : (price - hi) / hi;
    return Math.max(0, boundary * (1 - Math.min(1, overshoot)));
  }
  if (targetPrice !== undefined && targetPrice > 0) {
    const rel = Math.abs(price - targetPrice) / targetPrice;
    return Math.max(0, 1 - Math.min(1, rel));
  }
  return 0.5;
}

// Per-cohort weights over the public-data neighborhood sub-scores.
// Per-cohort weights over the neighborhood sub-scores (relative 0..1; the fit
// renormalizes over present dimensions). Fine-cohort rows are the persona spec
// §3 (columns there: safety, schools, transit, walkability, green).
// `kindergarten` (Phase 3) matters to family cohorts with young kids; absent on
// others (0 weight → ignored). neighborhoodFitScore renormalizes over present
// dimensions, so listings without a kindergarten sub-score degrade gracefully.
const NB_BASE = { safety: 0.30, walkability: 0.25, schools: 0.20, transit: 0.15, green: 0.10 };
const NB_BY_COHORT = {
  // coarse
  family:  { safety: 0.28, walkability: 0.10, schools: 0.32, kindergarten: 0.15, transit: 0.05, green: 0.18 },
  couple:  { safety: 0.30, walkability: 0.15, schools: 0.22, kindergarten: 0.10, transit: 0.10, green: 0.18 },
  student: { safety: 0.10, walkability: 0.35, schools: 0.00, transit: 0.45, green: 0.10 },
  single:  { safety: 0.15, walkability: 0.35, schools: 0.00, transit: 0.35, green: 0.15 },
  // fine
  young_professional: { safety: 0.70, schools: 0.00, transit: 0.90, walkability: 1.00, green: 0.20 },
  new_parents:        { safety: 0.35, schools: 0.10, kindergarten: 0.45, transit: 0.15, walkability: 0.25, green: 0.15 },
  dati_leumi:         { safety: 0.30, schools: 0.35, kindergarten: 0.30, transit: 0.05, walkability: 0.20, green: 0.10 },
  charedi:            { safety: 0.30, schools: 0.35, kindergarten: 0.30, transit: 0.05, walkability: 0.20, green: 0.10 },
  oleh:               { safety: 0.95, schools: 0.85, kindergarten: 0.40, transit: 0.25, walkability: 0.80, green: 0.50 },
  senior:             { safety: 0.90, schools: 0.05, transit: 0.25, walkability: 0.95, green: 0.70 },
  single_parent:      { safety: 0.85, schools: 0.70, kindergarten: 0.55, transit: 1.00, walkability: 0.95, green: 0.35 },
  remote:             { safety: 0.15, schools: 0.00, transit: 0.15, walkability: 0.40, green: 0.30 },
  arab_family:        { safety: 0.45, schools: 0.90, kindergarten: 0.40, transit: 0.15, walkability: 0.85, green: 0.30 },
  investor:           { safety: 0.40, schools: 0.20, transit: 1.00, walkability: 0.55, green: 0.10 },
};
export function neighborhoodWeightsFor(cohort) {
  return NB_BY_COHORT[cohort] || NB_BASE;
}

// ── Cohort deal-breaker gates (Phase 4) ──────────────────────────────────────
// A gate HARD-EXCLUDES a listing for a cohort with a strict environmental
// requirement, using the parsed schoolsMeta (pikuah / sector) from Phase 3.
// CRITICAL fail-soft rule: exclude ONLY on positive evidence of a mismatch.
// Missing/empty metadata → keep (we can't verify, so we must not hard-filter, or
// un-enriched listings would vanish from the feed).
function schoolsMetaOf(listing) {
  const ns = listing && listing.neighborhoodScore;
  return ns && typeof ns === 'object' ? ns.schoolsMeta : null;
}

// schoolsMeta.pikuah / .sectors are per-stream COUNTS of schools within ~1.5km,
// with .total. Gates use the FRACTION (dominance), because in dense metros every
// stream is *present* within range — only dominance distinguishes the community.
const DATI_MIN_FRACTION = 0.15;    // ≥15% ממלכתי-דתי → a national-religious area
const CHAREDI_MIN_FRACTION = 0.15; // ≥15% charedi → an ultra-orthodox area
const ARAB_MIN_FRACTION = 0.15;    // ≥15% Arab-sector schools → an Arab area
const fractionOf = (counts, key, total) =>
  (total > 0 ? (Number(counts && counts[key]) || 0) / total : 0);

const COHORT_GATES = {
  // National-religious (דתי-לאומי) → needs a ממלכתי-דתי (חמ"ד)-dominant area.
  dati_leumi: (l) => {
    const meta = schoolsMetaOf(l);
    if (!meta || !meta.total) return false; // unknown → keep (fail-soft)
    return fractionOf(meta.pikuah, 'mamlachti_dati', meta.total) < DATI_MIN_FRACTION;
  },
  // Ultra-orthodox (חרדי) → needs a charedi-dominant area (the inverse community).
  charedi: (l) => {
    const meta = schoolsMetaOf(l);
    if (!meta || !meta.total) return false;
    return fractionOf(meta.pikuah, 'charedi', meta.total) < CHAREDI_MIN_FRACTION;
  },
  // Arab families → an Arab-sector-dominant area.
  arab_family: (l) => {
    const meta = schoolsMetaOf(l);
    if (!meta || !meta.total) return false;
    return fractionOf(meta.sectors, 'arab', meta.total) < ARAB_MIN_FRACTION;
  },
};

// True → this listing should be hard-excluded for this cohort.
export function cohortGateReject(cohort, listing) {
  const gate = COHORT_GATES[cohort];
  if (!gate) return false;
  try { return gate(listing) === true; } catch { return false; }
}

// neighborhood_fit for the main feed: weight the listing's stored sub-scores
// (0..100) by the cohort's priorities, renormalizing over present dimensions.
// Falls back to the stored generic composite `score` when sub-scores are absent,
// and to a neutral 0.5 when there's no enriched neighborhood data at all.
export function neighborhoodFitScore(ns, cohort) {
  const sub = ns && ns.sub;
  if (sub && typeof sub === 'object') {
    const w = neighborhoodWeightsFor(cohort);
    let acc = 0;
    let wsum = 0;
    for (const k in w) {
      const v = Number(sub[k]);
      if (Number.isFinite(v) && v > 0) { acc += w[k] * clamp01(v / 100); wsum += w[k]; }
    }
    if (wsum > 0) return clamp01(acc / wsum);
  }
  const s = ns && Number(ns.score);
  return Number.isFinite(s) ? clamp01(s / 100) : 0.5;
}
