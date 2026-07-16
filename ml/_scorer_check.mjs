// Cross-language loop check: load the model.json that train.py just emitted
// (LightGBM dump_model format) through the SAME JS scorer the Node Lambda uses,
// and assert it ranks a strong feature vector above a weak one. This guards the
// one seam unit tests can't cover from a single language: Python trainer output
// ⇄ JS server scorer. Run from ml/: node _scorer_check.mjs <model.json>
import { readFileSync } from 'node:fs';
import { RANK_FEATURE_ORDER, loadModel, scoreWithModel }
  from '../aws/lambda/router/lib/model_scorer.mjs';
import assert from 'node:assert/strict';

const path = process.argv[2] || 'model.json';
process.env.RANK_MODEL_JSON = readFileSync(path, 'utf8');
const model = await loadModel();
assert.ok(model && Array.isArray(model.trees) && model.trees.length > 0,
  'JS scorer failed to parse the LightGBM dump_model JSON');

// gen_synthetic.py makes label correlate with priceFit+popularity+community_fit.
const good = { freshness:0.5, popularity:0.9, completeness:0.8, priceFit:0.95, neighborhood:0.6, semantic:0.5, community_fit:0.9 };
const bad  = { freshness:0.5, popularity:0.1, completeness:0.3, priceFit:0.05, neighborhood:0.4, semantic:0.5, community_fit:0.1 };
const sg = scoreWithModel(model, good), sb = scoreWithModel(model, bad);
assert.ok(sg >= 0 && sg <= 1 && sb >= 0 && sb <= 1, 'scores out of [0,1]');
assert.ok(sg > sb + 0.05, `JS scorer did not separate good(${sg.toFixed(3)}) > bad(${sb.toFixed(3)})`);
console.log(`OK: JS scorer reads Python LightGBM model — good ${sg.toFixed(3)} > bad ${sb.toFixed(3)}`);
console.log(`    (features: ${RANK_FEATURE_ORDER.join(',')})`);
