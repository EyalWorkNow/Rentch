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
  dati_leumi:         { freshness: 0.10, popularity: 0.06, completeness: 0.15, priceFit: 0.20, neighborhood: 0.25, semantic: 0.08, community_fit: 0.16 },
  charedi:            { freshness: 0.10, popularity: 0.06, completeness: 0.15, priceFit: 0.20, neighborhood: 0.25, semantic: 0.08, community_fit: 0.16 },
  oleh:               { freshness: 0.20, popularity: 0.08, completeness: 0.15, priceFit: 0.12, neighborhood: 0.27, semantic: 0.18 },
  senior:             { freshness: 0.12, popularity: 0.05, completeness: 0.20, priceFit: 0.13, neighborhood: 0.35, semantic: 0.15 },
  single_parent:      { freshness: 0.13, popularity: 0.08, completeness: 0.12, priceFit: 0.27, neighborhood: 0.30, semantic: 0.10 },
  remote:             { freshness: 0.22, popularity: 0.10, completeness: 0.13, priceFit: 0.20, neighborhood: 0.17, semantic: 0.18 },
  arab_family:        { freshness: 0.12, popularity: 0.06, completeness: 0.17, priceFit: 0.12, neighborhood: 0.27, semantic: 0.10, community_fit: 0.16 },
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

// ── Community fit — a SOFT ranking signal (replaced the hard gates) ───────────
// The earlier design HARD-EXCLUDED listings by religious stream / ethnic sector,
// which is a housing-discrimination/steering exposure and produced silent
// all-or-nothing fallbacks. Instead we now emit a soft `community_fit` score in
// [0,1]: a community-mismatched area ranks LOWER, never disappears. Neutral 0.5
// for unknown areas and for cohorts with no community preference (no effect).
function schoolsMetaOf(listing) {
  const ns = listing && listing.neighborhoodScore;
  return ns && typeof ns === 'object' ? ns.schoolsMeta : null;
}

// Denominator is meta.total = schools WITH a classified pikuah within ~1.5km
// (see schoolsNear). Fraction saturates to a full match at COMMUNITY_TARGET.
const COMMUNITY_TARGET = 0.30;
const fractionOf = (counts, key, total) =>
  (total > 0 ? (Number(counts && counts[key]) || 0) / total : 0);
const COMMUNITY_SPEC = {
  dati_leumi: (m) => fractionOf(m.pikuah, 'mamlachti_dati', m.total),
  charedi: (m) => fractionOf(m.pikuah, 'charedi', m.total),
  arab_family: (m) => fractionOf(m.sectors, 'arab', m.total),
};

// Soft [0,1] fit of an area to a community cohort's school profile. 0.5 neutral
// when unknown or for non-community cohorts.
export function communityFitScore(cohort, listing) {
  const spec = COMMUNITY_SPEC[cohort];
  if (!spec) return 0.5;
  const meta = schoolsMetaOf(listing);
  if (!meta || !meta.total) return 0.5;
  return clamp01(spec(meta) / COMMUNITY_TARGET);
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
      // A present sub-score of 0 (e.g. no schools within radius) is a real
      // NEGATIVE signal — include it; only skip genuinely-absent dimensions.
      if (Number.isFinite(v)) { acc += w[k] * clamp01(v / 100); wsum += w[k]; }
    }
    if (wsum > 0) return clamp01(acc / wsum);
  }
  const s = ns && Number(ns.score);
  return Number.isFinite(s) ? clamp01(s / 100) : 0.5;
}

// ── Pure main-feed scoring (extracted from index.mjs for testability) ─────────
// These are dependency-free; index.mjs loads the popularity counts from DynamoDB
// and hands them in, so the whole scoring pipeline unit-tests without aws-sdk.
const LIKE_RATE_PRIOR = 0.12;   // assumed global like-per-view rate
const LIKE_RATE_STRENGTH = 8;   // pseudo-views of prior weight
export const round3 = (n) => Math.round((Number(n) || 0) * 1000) / 1000;

// Exponential recency decay, 14-day half-life. Missing/garbage date → neutral 0.5.
export function freshnessScore(createdAt, now) {
  const t = Date.parse(createdAt);
  if (!Number.isFinite(t)) return 0.5;
  const ageDays = Math.max(0, (now - t) / 86_400_000);
  return Math.exp(-Math.LN2 * ageDays / 14);
}
// Bayesian-shrunk like-rate, normalised so the prior maps to ~0.5.
export function shrinkLikeRate(likes, views) {
  const l = Math.max(0, Number(likes) || 0);
  const v = Math.max(l, Number(views) || 0); // views can't be below likes
  const rate = (l + LIKE_RATE_PRIOR * LIKE_RATE_STRENGTH) / (v + LIKE_RATE_STRENGTH);
  return Math.max(0, Math.min(1, 0.5 * (rate / LIKE_RATE_PRIOR)));
}
export function completenessScore(p) {
  const checks = [
    Number(p.price) > 0, Number(p.rooms) > 0, !!p.city, !!p.street,
    Number(p.sizeM2) > 0, Array.isArray(p.imageUrls) && p.imageUrls.length > 0,
    !!(p.description && String(p.description).trim().length > 20),
    Array.isArray(p.smartTags) && p.smartTags.length > 0, !!p.neighborhood,
  ];
  return checks.filter(Boolean).length / checks.length;
}

// Scores every listing in-place (sets p.rankSignals + p.rankScore) for a cohort.
// `counts` is { id: {views,likes} } loaded upstream. NO exclusion — community_fit
// is a soft signal. Pure/unit-testable. Returns the same items array.
export function scoreListings(items, ctx, counts, nowMs) {
  const { cohort, minBudget, maxBudget, targetPrice } = ctx || {};
  const W = rankWeightsFor(cohort);
  const priceTarget = cohortPriceTarget(cohort);
  for (const p of items) {
    const c = (counts && counts[String(p.id || '')]) || { views: 0, likes: 0 };
    const freshness = freshnessScore(p.createdAt, nowMs);
    const popularity = shrinkLikeRate(c.likes, c.views);
    const completeness = completenessScore(p);
    const priceFit = priceFitScore(Number(p.price), { minBudget, maxBudget, targetPrice }, priceTarget);
    const neighborhood = neighborhoodFitScore(p.neighborhoodScore, cohort);
    const semRaw = Number(p.semanticSim);
    const semantic = Number.isFinite(semRaw) ? clamp01(semRaw) : 0.5;
    const community = communityFitScore(cohort, p);
    const rankScore = W.freshness * freshness + W.popularity * popularity
      + W.completeness * completeness + W.priceFit * priceFit
      + W.neighborhood * neighborhood + W.semantic * semantic
      + (W.community_fit || 0) * community;
    p.rankSignals = {
      freshness: round3(freshness), popularity: round3(popularity), completeness: round3(completeness),
      priceFit: round3(priceFit), neighborhood: round3(neighborhood), semantic: round3(semantic),
      community_fit: round3(community), cohort: cohort || 'default', views: c.views, likes: c.likes,
    };
    p.rankScore = round3(rankScore);
  }
  return items;
}
