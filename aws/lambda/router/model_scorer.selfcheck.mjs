// model_scorer.selfcheck.mjs — node-assert self-check for the Phase-1 learned-
// ranker serving hook (lib/model_scorer.mjs) and lib/ab.mjs. Run:
//   node aws/lambda/router/model_scorer.selfcheck.mjs
//
// model_scorer imports the aws-sdk LAZILY (only when RANK_MODEL_S3 is set), so
// this check runs without it — we exercise only the inline-JSON / null paths.
import assert from 'node:assert/strict';
import {
  RANK_FEATURE_ORDER, loadModel, scoreWithModel, blendScore, modelAlpha,
  rankFeaturesFrom, _resetModelCache,
} from './lib/model_scorer.mjs';
import { variantFor } from './lib/ab.mjs';

let n = 0;
const ok = (cond, msg) => { assert.ok(cond, msg); n++; };
const eq = (a, b, msg) => { assert.strictEqual(a, b, msg); n++; };
const near = (a, b, msg, eps = 1e-6) => { assert.ok(Math.abs(a - b) < eps, `${msg} (got ${a})`); n++; };

// ── RANK_FEATURE_ORDER: the locked, ordered feature contract ─────────────────
assert.deepStrictEqual([...RANK_FEATURE_ORDER],
  ['freshness', 'popularity', 'completeness', 'priceFit', 'neighborhood', 'semantic', 'community_fit'],
  'RANK_FEATURE_ORDER matches the scoreListings components'); n++;
ok(Object.isFrozen(RANK_FEATURE_ORDER), 'RANK_FEATURE_ORDER is frozen (immutable contract)');

// ── scoreWithModel: hand-built 1-tree model on feature index 0 (freshness) ────
// freshness <= 0.5 → leaf -1.0 ; else → leaf +2.0
const oneTree = {
  tree_info: [{
    tree_index: 0,
    tree_structure: {
      split_feature: 0, threshold: 0.5, decision_type: '<=', default_left: true,
      left_child: { leaf_value: -1.0 },
      right_child: { leaf_value: 2.0 },
    },
  }],
};
const parsed1 = (await (async () => {
  _resetModelCache();
  process.env.RANK_MODEL_JSON = JSON.stringify(oneTree);
  const m = await loadModel();
  delete process.env.RANK_MODEL_JSON;
  return m;
})());
ok(parsed1 && Array.isArray(parsed1.trees) && parsed1.trees.length === 1, 'loadModel parses inline JSON → 1 tree');
const sigmoid = (x) => 1 / (1 + Math.exp(-x));
near(scoreWithModel(parsed1, { freshness: 0.8 }), sigmoid(2.0), 'high freshness → right leaf +2 → sigmoid(2)');
near(scoreWithModel(parsed1, { freshness: 0.2 }), sigmoid(-1.0), 'low freshness → left leaf -1 → sigmoid(-1)');
near(scoreWithModel(parsed1, {}), sigmoid(-1.0), 'missing feature → default_left → left leaf');
eq(scoreWithModel(parsed1, { freshness: 0.8 }) > 0.5, true, 'positive-margin score > 0.5');
eq(scoreWithModel(parsed1, { freshness: 0.2 }) < 0.5, true, 'negative-margin score < 0.5');

// ── scoreWithModel: 2-tree ensemble sums leaf margins across trees ────────────
const twoTree = {
  tree_info: [
    { tree_structure: { split_feature: 0, threshold: 0.5, decision_type: '<=', left_child: { leaf_value: 0.5 }, right_child: { leaf_value: 1.0 } } },
    { tree_structure: { split_feature: 6, threshold: 0.5, decision_type: '<=', left_child: { leaf_value: 0.0 }, right_child: { leaf_value: 1.0 } } },
  ],
};
_resetModelCache();
process.env.RANK_MODEL_JSON = JSON.stringify(twoTree);
const parsed2 = await loadModel();
delete process.env.RANK_MODEL_JSON;
// freshness 0.8 → tree0 right (1.0) ; community_fit 0.9 → tree1 right (1.0) → margin 2.0
near(scoreWithModel(parsed2, { freshness: 0.8, community_fit: 0.9 }), sigmoid(2.0), 'two positive leaves sum → sigmoid(2)');
// freshness 0.2 → tree0 left (0.5) ; community_fit 0.2 → tree1 left (0.0) → margin 0.5
near(scoreWithModel(parsed2, { freshness: 0.2, community_fit: 0.2 }), sigmoid(0.5), 'mixed leaves sum → sigmoid(0.5)');

// ── null model → neutral / pure-linear path ──────────────────────────────────
eq(scoreWithModel(null, { freshness: 1 }), 0.5, 'null model → neutral 0.5 (no crash)');
eq(scoreWithModel({ trees: [] }, {}), 0.5, 'empty tree list → neutral 0.5');

// loadModel with NEITHER env set → null (dormant → callers stay pure linear).
_resetModelCache();
delete process.env.RANK_MODEL_JSON;
delete process.env.RANK_MODEL_S3;
eq(await loadModel(), null, 'no env configured → loadModel null (pure-linear path)');
// A second call is served from cache (still null, no retry).
eq(await loadModel(), null, 'null result is cached');

// Malformed JSON → null (fail-soft, not a throw).
_resetModelCache();
process.env.RANK_MODEL_JSON = '{not valid json';
eq(await loadModel(), null, 'malformed RANK_MODEL_JSON → null (fail-soft)');
delete process.env.RANK_MODEL_JSON;
_resetModelCache();

// ── blendScore + modelAlpha ──────────────────────────────────────────────────
delete process.env.RANK_MODEL_ALPHA;
eq(modelAlpha(), 0.7, 'default alpha 0.7');
process.env.RANK_MODEL_ALPHA = '0.4';
eq(modelAlpha(), 0.4, 'env overrides alpha');
delete process.env.RANK_MODEL_ALPHA;
near(blendScore(0.8, 0.5, 0.7), 0.7 * 0.8 + 0.3 * 0.5, 'blend = α·linear + (1−α)·model');
near(blendScore(0.8, 0.5, 1.0), 0.8, 'α=1 → pure linear');
near(blendScore(0.8, 0.5, 0.0), 0.5, 'α=0 → pure model');

// ── rankFeaturesFrom: canonical ordered object, cohort trailing ──────────────
{
  const rs = {
    freshness: 0.9, popularity: 0.2, completeness: 0.8, priceFit: 0.5,
    neighborhood: 0.7, semantic: 0.3, community_fit: 0.6, cohort: 'family',
    views: 10, likes: 3, // extra fields must NOT leak into the vector
  };
  const f = rankFeaturesFrom(rs);
  assert.deepStrictEqual(Object.keys(f), [...RANK_FEATURE_ORDER, 'cohort'],
    'rankFeatures keys = RANK_FEATURE_ORDER + cohort'); n++;
  eq(f.freshness, 0.9, 'freshness carried through');
  eq(f.cohort, 'family', 'cohort carried through');
  eq(f.views, undefined, 'non-feature fields dropped');
  eq(rankFeaturesFrom({}).cohort, 'default', 'missing cohort → default');
  eq(rankFeaturesFrom({}).freshness, 0, 'missing feature → 0');
}

// ── A/B: deterministic, stable, distributes ──────────────────────────────────
{
  eq(variantFor('u1', RANK_FEATURE_ORDER ? 'exp' : 'exp', 2), variantFor('u1', 'exp', 2), 'same input → same bucket');
  eq(variantFor('', 'exp', 2), 0, 'empty uid → control bucket 0');
  eq(variantFor('u1', 'exp', 1), 0, 'buckets=1 → always 0');
  for (const b of [2, 3, 5]) {
    for (const u of ['a', 'b', 'user-42', 'xyz']) {
      const v = variantFor(u, 'e', b);
      ok(Number.isInteger(v) && v >= 0 && v < b, `variant in [0,${b}) for ${u}`);
    }
  }
  // Different experiments bucket independently (not all users collide).
  const spread = new Set();
  for (let i = 0; i < 200; i++) spread.add(variantFor(`user${i}`, 'exp', 2));
  eq(spread.size, 2, 'both buckets are populated across many users');
}

console.log(`model_scorer.selfcheck: ${n} assertions passed`);
