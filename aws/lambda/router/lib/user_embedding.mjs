// user_embedding.mjs — the "USER TOWER" (Phase-2 of the targeting plan).
//
// A content-based user vector: the ACTION-WEIGHTED, L2-normalised mean of the
// embeddings of the listings a person engaged with. It lives in the SAME 768-dim
// space as the listing embeddings (gemini-embedding-001), so:
//   • cosine(userVec, listingVec)  → a personalised semantic ranking score
//     (replaces the neutral `semantic` signal + the vibeTargetVibrancy TODO).
//   • cosine(userVecA, userVecB)   → two people are LOOK-ALIKES (Phase-3 audiences).
//
// No training, no model server: just pooling vectors we already store. Pure and
// dependency-free so it unit-tests standalone (see _user_embedding_check.mjs).

// How much each engagement action pulls the user vector toward that listing.
// A contact is a far stronger preference signal than a swipe-right.
export const ACTION_WEIGHT = Object.freeze({
  contact: 3,
  superlike: 2,
  like: 1,
  click: 0.5,
});

export function l2normalize(v) {
  let n = 0;
  for (const x of v) n += x * x;
  n = Math.sqrt(n);
  if (n === 0) return v.slice();
  return v.map((x) => x / n);
}

// items: [{ vec:number[], weight?:number }] → the unit-length weighted centroid,
// or null when there is no usable vector. Vectors of a mismatched dimension are
// skipped (defensive against a stale/other-model embedding sneaking in).
export function weightedCentroid(items) {
  let dim = 0;
  for (const it of items) {
    if (it && Array.isArray(it.vec) && it.vec.length) { dim = it.vec.length; break; }
  }
  if (!dim) return null;
  const acc = new Array(dim).fill(0);
  let wsum = 0;
  for (const it of items) {
    const v = it && it.vec;
    if (!Array.isArray(v) || v.length !== dim) continue;
    // Undefined weight defaults to 1; an explicit non-positive weight = ignore.
    let w;
    if (it.weight === undefined || it.weight === null) w = 1;
    else if (Number.isFinite(it.weight) && it.weight > 0) w = it.weight;
    else continue;
    for (let i = 0; i < dim; i++) acc[i] += v[i] * w;
    wsum += w;
  }
  if (wsum === 0) return null;
  for (let i = 0; i < dim; i++) acc[i] /= wsum;
  return l2normalize(acc);
}

// Build a user embedding from engaged listings.
// engaged: [{ embedding:number[], action:'contact'|'superlike'|'like'|'click' }].
// Returns the unit user vector, or null when nothing usable was engaged.
export function userEmbeddingFrom(engaged) {
  const items = [];
  for (const e of engaged || []) {
    const vec = e && (e.embedding || e.vec);
    if (!Array.isArray(vec) || !vec.length) continue;
    items.push({ vec, weight: ACTION_WEIGHT[e && e.action] || 1 });
  }
  return weightedCentroid(items);
}

// Rank candidates by cosine to a query vector — the LOOK-ALIKE primitive
// (Phase-3). candidates: [{ id, vec|embedding|userEmbedding, ...meta }].
// Returns [{ ...meta, id, score }] sorted desc, capped at k, skipping `exclude`
// ids and any candidate whose vector is absent or of a mismatched dimension.
export function topKBySimilarity(queryVec, candidates, k = 20, exclude = new Set()) {
  if (!Array.isArray(queryVec) || !queryVec.length) return [];
  const out = [];
  for (const c of candidates || []) {
    if (!c || !c.id || (exclude && exclude.has && exclude.has(c.id))) continue;
    const v = c.vec || c.embedding || c.userEmbedding;
    if (!Array.isArray(v) || v.length !== queryVec.length) continue;
    out.push({ ...c, score: cosine01(queryVec, v) });
  }
  out.sort((a, b) => b.score - a.score);
  return out.slice(0, Math.max(1, k));
}

// Cosine similarity mapped to [0,1] — MUST match index.mjs cosineSim so a
// user↔listing score is on the same scale as the query↔listing KNN score.
export function cosine01(a, b) {
  if (!Array.isArray(a) || !Array.isArray(b) || a.length !== b.length || !a.length) {
    return 0.5;
  }
  let dot = 0, na = 0, nb = 0;
  for (let i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    na += a[i] * a[i];
    nb += b[i] * b[i];
  }
  if (na === 0 || nb === 0) return 0.5;
  const s = dot / (Math.sqrt(na) * Math.sqrt(nb));
  return Math.max(0, Math.min(1, (s + 1) / 2));
}
