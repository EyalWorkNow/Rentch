// muni.mjs — canonical locality dimension for joining public datasets.
//
// Israeli open-data sources key localities inconsistently (CBS id, Education id,
// Tax id, or free-text name). This module gives ONE canonical join key:
//   • normalizeLocalityName() — a stable string key usable across any dataset.
//   • resolveLocality()       — name → {cbs_id, edu_id, tax_id} via muni_ids,
//                               for datasets keyed by numeric id.
//
// The muni_ids table (matanhakim/general_files muni_ids.csv) is generated into
// muni_ids.generated.json by scripts/build-muni-ids.mjs. Fail-soft: if that file
// hasn't been built, resolveLocality() returns null and callers fall back to
// name-based joins (which normalizeLocalityName already enables).

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

// Municipality-type prefixes to strip so "עיריית תל אביב", "מ. מ. אבו גוש" and
// the bare name all collapse to the same key.
const MUNI_PREFIX =
  /^(עיריית|עירית|מועצה מקומית|מועצה אזורית|מ\.?\s*מ\.?|מ\.?\s*א\.?|מ"מ|מ"א)\s+/;

/// Stable, comparable locality key: strip prefixes/quotes/punctuation, collapse
/// whitespace, lowercase. Same output for the same locality across datasets.
export function normalizeLocalityName(name) {
  if (!name) return '';
  return String(name)
    .replace(/["'׳״]/g, '')
    .replace(MUNI_PREFIX, '')
    .replace(/[\-–_]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .toLowerCase();
}

// Lazily loaded once per Lambda container. Absent file → empty map (fail-soft).
let _muni = null;
function muniTable() {
  if (_muni) return _muni;
  _muni = {};
  try {
    const here = dirname(fileURLToPath(import.meta.url));
    const rows = JSON.parse(readFileSync(join(here, 'muni_ids.generated.json'), 'utf8'));
    for (const r of rows) {
      const key = normalizeLocalityName(r.cbs_name);
      if (key) _muni[key] = r;
    }
  } catch { /* not built yet — name-based joins still work */ }
  return _muni;
}

/// name → { cbs_id, cbs_name, edu_id, tax_id } or null when unknown/not built.
/// Exact-key first, then a contains-either-way fallback so "תל אביב" resolves to
/// the canonical "תל אביב-יפו" (and vice versa).
export function resolveLocality(name) {
  const key = normalizeLocalityName(name);
  if (!key) return null;
  const t = muniTable();
  if (t[key]) return t[key];
  for (const k in t) {
    if (k === key) return t[k];
    if (k.length >= 3 && key.length >= 3 && (k.includes(key) || key.includes(k))) return t[k];
  }
  return null;
}
