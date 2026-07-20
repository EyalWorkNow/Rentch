// Standalone self-check for the user-tower math. Run: node lib/_user_embedding_check.mjs
import assert from 'node:assert';
import {
  userEmbeddingFrom, weightedCentroid, cosine01, l2normalize, ACTION_WEIGHT,
  topKBySimilarity,
} from './user_embedding.mjs';

// l2normalize → unit length
{
  const u = l2normalize([3, 4]);
  assert.ok(Math.abs(Math.hypot(u[0], u[1]) - 1) < 1e-9, 'l2normalize → unit');
}

// centroid of identical vectors = that (normalized) vector
{
  const v = [0.1, 0.2, 0.3];
  const c = weightedCentroid([{ vec: v }, { vec: v }, { vec: v }]);
  const n = l2normalize(v);
  for (let i = 0; i < v.length; i++) assert.ok(Math.abs(c[i] - n[i]) < 1e-9, 'identical centroid');
}

// cosine: identical = 1, orthogonal = 0.5, opposite = 0
assert.ok(Math.abs(cosine01([1, 0], [1, 0]) - 1) < 1e-9, 'cosine identical = 1');
assert.ok(Math.abs(cosine01([1, 0], [0, 1]) - 0.5) < 1e-9, 'cosine orthogonal = 0.5');
assert.ok(Math.abs(cosine01([1, 0], [-1, 0]) - 0) < 1e-9, 'cosine opposite = 0');

// action weighting pulls the centroid toward the stronger action
{
  const a = [1, 0];
  const b = [0, 1];
  // one 'like' on a, one 'contact' (weight 3) on b → centroid closer to b
  const c = userEmbeddingFrom([{ embedding: a, action: 'like' }, { embedding: b, action: 'contact' }]);
  assert.ok(c[1] > c[0], 'contact (w=3) outweighs like (w=1)');
  assert.strictEqual(ACTION_WEIGHT.contact, 3);
}

// empty / unusable → null (never fabricate a vector)
assert.strictEqual(userEmbeddingFrom([]), null, 'empty → null');
assert.strictEqual(userEmbeddingFrom([{ action: 'like' }]), null, 'no vecs → null');
assert.strictEqual(weightedCentroid([{ vec: [1], weight: 0 }]), null, 'zero weight → null');

// mismatched-dim vectors are skipped, not crashing
{
  const c = userEmbeddingFrom([{ embedding: [1, 0], action: 'like' }, { embedding: [1, 0, 0], action: 'like' }]);
  assert.strictEqual(c.length, 2, 'mismatched dim skipped');
}

// look-alike: ranks by cosine, respects exclude + dim-mismatch + k
{
  const q = [1, 0];
  const cands = [
    { id: 'a', vec: [1, 0], name: 'near' },     // score 1
    { id: 'b', vec: [0.7, 0.7], name: 'mid' },  // score ~0.85
    { id: 'c', vec: [-1, 0], name: 'far' },     // score 0
    { id: 'd', vec: [1, 0, 0] },                // wrong dim → skipped
    { id: 'e' },                                 // no vec → skipped
  ];
  const top = topKBySimilarity(q, cands, 2, new Set(['c']));
  assert.strictEqual(top.length, 2, 'k respected');
  assert.strictEqual(top[0].id, 'a', 'closest first');
  assert.strictEqual(top[0].name, 'near', 'meta carried through');
  assert.strictEqual(top[1].id, 'b', 'second closest');
  assert.ok(!top.some((t) => t.id === 'c'), 'exclude honored');
  assert.ok(!top.some((t) => t.id === 'd' || t.id === 'e'), 'bad vectors skipped');
  assert.strictEqual(topKBySimilarity([], cands).length, 0, 'empty query → []');
}

console.log('user_embedding self-check: OK');
