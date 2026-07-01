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
export const RANK_WEIGHTS_BY_COHORT = {
  default: { freshness: 0.25, popularity: 0.20, completeness: 0.15, priceFit: 0.20, neighborhood: 0.12, semantic: 0.08 },
  // Families/couples: neighborhood quality dominates, popularity de-emphasized.
  family:  { freshness: 0.18, popularity: 0.10, completeness: 0.17, priceFit: 0.22, neighborhood: 0.25, semantic: 0.08 },
  couple:  { freshness: 0.20, popularity: 0.12, completeness: 0.15, priceFit: 0.22, neighborhood: 0.23, semantic: 0.08 },
  // Students: budget-driven, transit-heavy neighborhood.
  student: { freshness: 0.20, popularity: 0.10, completeness: 0.10, priceFit: 0.30, neighborhood: 0.22, semantic: 0.08 },
  // Singles (young professionals): semantic + freshness up, price less anchored.
  single:  { freshness: 0.25, popularity: 0.15, completeness: 0.15, priceFit: 0.15, neighborhood: 0.18, semantic: 0.12 },
};

export function rankWeightsFor(cohort) {
  return RANK_WEIGHTS_BY_COHORT[cohort] || RANK_WEIGHTS_BY_COHORT.default;
}

// Where in the budget window a cohort's ideal sits.
//   low    — cheap end best (budget-sensitive)
//   high   — premium end best (lifestyle buyers)
//   mid    — peak in the middle (neutral default)
//   invert — cheaper is always better (investor/yield); treated like `low` here
const COHORT_PRICE_TARGET = { family: 'low', couple: 'low', student: 'low', single: 'mid' };
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
const NB_BASE = { safety: 0.30, walkability: 0.25, schools: 0.20, transit: 0.15, green: 0.10 };
const NB_BY_COHORT = {
  family:  { safety: 0.30, walkability: 0.10, schools: 0.35, transit: 0.05, green: 0.20 },
  couple:  { safety: 0.30, walkability: 0.15, schools: 0.25, transit: 0.10, green: 0.20 },
  student: { safety: 0.10, walkability: 0.35, schools: 0.00, transit: 0.45, green: 0.10 },
  single:  { safety: 0.15, walkability: 0.35, schools: 0.00, transit: 0.35, green: 0.15 },
};
export function neighborhoodWeightsFor(cohort) {
  return NB_BY_COHORT[cohort] || NB_BASE;
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
