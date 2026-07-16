// model_scorer.mjs — Phase-1 learned-ranker serving hook (DORMANT by default).
//
// The main feed's ranking is a transparent LINEAR weighted sum computed by
// scoreListings (lib/ranking.mjs). This module lets a trained LightGBM model be
// blended on TOP of that linear score WITHOUT changing the linear math, and is a
// no-op until a model is actually provisioned:
//
//   • loadModel()            → the LightGBM `dump_model()` JSON from env
//                              RANK_MODEL_JSON (inline) or RANK_MODEL_S3 (an S3
//                              object). Cached. Returns null when neither is set
//                              or on ANY error → callers fall back to pure linear.
//   • scoreWithModel(m, f)   → traverse the tree ensemble over the feature object
//                              and squash to [0,1] with a sigmoid.
//   • RANK_FEATURE_ORDER     → the CANONICAL, ordered feature-key list. This is
//                              the single source of truth the client (impression
//                              logging), the trainer (feature columns) and the
//                              scorer (tree `split_feature` index → key) all agree
//                              on. NEVER reorder or remove a key: the model JSON
//                              references features by their INDEX in this array.
//
// Pure + (mostly) dependency-free so it unit-tests standalone: the only external
// dependency is the S3 fetch, which is imported LAZILY inside loadModel and only
// when RANK_MODEL_S3 is set — so importing this module (and the self-check) never
// needs the aws-sdk.

// ── Canonical feature order ──────────────────────────────────────────────────
// These are EXACTLY the per-listing components scoreListings emits (see its
// rankSignals block), in a stable order. `cohort` is carried alongside as
// categorical context (in rankFeatures) but is NOT a numeric tree feature, so it
// is intentionally absent from this index-addressable vector.
export const RANK_FEATURE_ORDER = Object.freeze([
  'freshness',
  'popularity',
  'completeness',
  'priceFit',
  'neighborhood',
  'semantic',
  'community_fit',
]);

const clamp01 = (x) => Math.max(0, Math.min(1, x));
const sigmoid = (x) => 1 / (1 + Math.exp(-x));

// ── Model loading (cached, fail-soft) ────────────────────────────────────────
// undefined = not yet attempted, null = confirmed absent/failed, object = model.
let _modelCache;
let _modelPromise;

// Parse the raw dump_model() JSON into { trees:[rootNode,...] }. Accepts the
// canonical LightGBM shape ({ tree_info:[{ tree_structure }] }) and a couple of
// tolerant fallbacks. Returns null if no trees can be found.
function normalizeModel(raw) {
  if (!raw || typeof raw !== 'object') return null;
  let trees = null;
  if (Array.isArray(raw.tree_info)) {
    trees = raw.tree_info.map((t) => (t && t.tree_structure) || t).filter(Boolean);
  } else if (Array.isArray(raw.trees)) {
    trees = raw.trees.map((t) => (t && t.tree_structure) || t).filter(Boolean);
  }
  if (!trees || trees.length === 0) return null;
  return { trees, raw };
}

// Lazy S3 read — only reached when RANK_MODEL_S3 is set. `ref` is either
// "s3://bucket/key" or "bucket/key/path". Dynamic import keeps the aws-sdk off
// this module's import graph (so the self-check runs without it).
async function s3GetJson(ref) {
  let r = String(ref).trim();
  if (r.startsWith('s3://')) r = r.slice(5);
  const slash = r.indexOf('/');
  if (slash <= 0) throw new Error(`RANK_MODEL_S3 must be "bucket/key": ${ref}`);
  const Bucket = r.slice(0, slash);
  const Key = r.slice(slash + 1);
  const { S3Client, GetObjectCommand } = await import('@aws-sdk/client-s3');
  const s3 = new S3Client({ region: process.env.AWS_REGION });
  const obj = await s3.send(new GetObjectCommand({ Bucket, Key }));
  const text = typeof obj.Body.transformToString === 'function'
    ? await obj.Body.transformToString('utf-8')
    : await streamToString(obj.Body);
  return text;
}

async function streamToString(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf-8');
}

async function _load(opts) {
  const raw = process.env.RANK_MODEL_JSON;
  if (raw && String(raw).trim()) return normalizeModel(JSON.parse(raw));
  const s3ref = process.env.RANK_MODEL_S3;
  if (s3ref && String(s3ref).trim()) {
    // Allow the caller (index.mjs) to inject its own S3 getter; otherwise use the
    // lazy default. Either way JSON.parse the returned text.
    const text = typeof opts.s3Get === 'function'
      ? await opts.s3Get(s3ref)
      : await s3GetJson(s3ref);
    return normalizeModel(JSON.parse(text));
  }
  return null; // neither source configured → dormant → pure linear
}

// Returns the parsed model (cached) or null. NEVER throws: any failure (bad JSON,
// S3 error, missing env) resolves to null so the ranking path stays pure-linear.
// The null result is cached too, so a misconfiguration doesn't retry every feed.
export async function loadModel(opts = {}) {
  if (_modelCache !== undefined) return _modelCache;
  if (_modelPromise) return _modelPromise;
  _modelPromise = _load(opts)
    .then((m) => { _modelCache = m; _modelPromise = null; return m; })
    .catch((e) => {
      // eslint-disable-next-line no-console
      console.warn('loadModel failed → pure linear:', e && e.message);
      _modelCache = null; _modelPromise = null; return null;
    });
  return _modelPromise;
}

// Test/deploy hook: force-reset the cache (e.g. after a model rotation).
export function _resetModelCache() { _modelCache = undefined; _modelPromise = null; }

// ── Tree traversal ───────────────────────────────────────────────────────────
// Walk one LightGBM tree_structure node to its leaf. Internal nodes carry
// split_feature (INDEX into RANK_FEATURE_ORDER), threshold, decision_type
// (default '<='), left_child/right_child, and default_left (which way a
// missing/NaN feature goes). Leaf nodes carry leaf_value.
function walkTree(node, feats) {
  let n = node;
  // Bounded by tree depth; the extra guard defends against a malformed cyclic JSON.
  for (let guard = 0; guard < 512 && n; guard++) {
    if (n.leaf_value !== undefined) return Number(n.leaf_value) || 0;
    if (n.left_child === undefined && n.right_child === undefined) {
      // Not an internal node and no leaf_value → treat as 0 contribution.
      return 0;
    }
    const key = RANK_FEATURE_ORDER[n.split_feature];
    const v = key === undefined ? NaN : Number(feats[key]);
    let goLeft;
    if (!Number.isFinite(v)) {
      goLeft = n.default_left !== false; // default_left defaults to true
    } else {
      const thr = Number(n.threshold);
      // Only '<=' is emitted for numeric splits by dump_model; treat anything
      // else as '<=' too (safe default).
      goLeft = v <= thr;
    }
    n = goLeft ? n.left_child : n.right_child;
  }
  return 0;
}

// Score a feature object with the loaded model → a number in [0,1]. Sums the leaf
// values across all trees (raw margin) then applies a sigmoid. Returns 0.5
// (neutral) if the model is null/empty so a caller that forgot to null-check
// still degrades gracefully.
export function scoreWithModel(model, featuresObj) {
  if (!model || !Array.isArray(model.trees) || model.trees.length === 0) return 0.5;
  const feats = featuresObj || {};
  let margin = 0;
  for (const tree of model.trees) margin += walkTree(tree, feats);
  return clamp01(sigmoid(margin));
}

// ── Blend ────────────────────────────────────────────────────────────────────
// finalScore = α·linear + (1−α)·model. α from env RANK_MODEL_ALPHA (default 0.7).
// When model is null the caller should NOT call this — behavior must be EXACTLY
// today's pure-linear score. This helper just centralizes the α parse + math for
// the treated path.
export function modelAlpha() {
  const a = Number(process.env.RANK_MODEL_ALPHA);
  return Number.isFinite(a) && a >= 0 && a <= 1 ? a : 0.7;
}
export function blendScore(linearScore, modelScore, alpha = modelAlpha()) {
  const l = Number(linearScore) || 0;
  const m = Number.isFinite(Number(modelScore)) ? Number(modelScore) : 0.5;
  return alpha * l + (1 - alpha) * m;
}

// Build the canonical, ordered rankFeatures object from a scored listing's
// rankSignals block. Keys are exactly RANK_FEATURE_ORDER (in order) plus `cohort`
// as trailing categorical context. This is the vector the client logs back
// verbatim and the trainer/scorer index into.
export function rankFeaturesFrom(rankSignals) {
  const rs = rankSignals || {};
  const out = {};
  for (const k of RANK_FEATURE_ORDER) {
    const v = Number(rs[k]);
    out[k] = Number.isFinite(v) ? v : 0;
  }
  out.cohort = rs.cohort || 'default';
  return out;
}
