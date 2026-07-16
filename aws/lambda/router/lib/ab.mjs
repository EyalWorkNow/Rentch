// ab.mjs — Phase-0 deterministic A/B bucketing. No service, no storage: a caller
// is assigned to a variant purely by hashing (uid + experiment), so the SAME user
// always lands in the SAME bucket for a given experiment (stable across requests
// and Lambda cold starts) and different experiments bucket independently.
//
//   variantFor(uid, experiment, buckets=2) → integer in [0, buckets)
//
// Used to stamp the caller's ranking-experiment variant on the feed response so
// the client logs it with every impression (train/serve join can then slice by
// variant). Pure + dependency-free → unit-testable standalone.

// FNV-1a 32-bit — tiny, fast, well-distributed, and DETERMINISTIC across runtimes
// (no crypto dependency, no platform-dependent hashing). Returns an unsigned int.
function fnv1a32(str) {
  let h = 0x811c9dc5;
  for (let i = 0; i < str.length; i++) {
    h ^= str.charCodeAt(i);
    // h *= 16777619, kept in 32-bit unsigned via Math.imul + >>> 0
    h = Math.imul(h, 0x01000193) >>> 0;
  }
  return h >>> 0;
}

// Deterministic bucket assignment. A missing/empty uid falls into bucket 0 (the
// control) so anonymous/unauthenticated callers get the baseline experience.
export function variantFor(uid, experiment, buckets = 2) {
  const b = Math.max(1, Math.floor(Number(buckets) || 1));
  if (b === 1) return 0;
  const u = (uid == null ? '' : String(uid));
  if (!u) return 0;
  const e = (experiment == null ? '' : String(experiment));
  return fnv1a32(`${u}::${e}`) % b;
}
