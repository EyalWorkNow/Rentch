#!/usr/bin/env node
// Backfill listing embeddings (בינוני tier, step 2). One-off / rerunnable: pages
// the properties table, embeds any row missing `embedding`, writes it back.
// Idempotent (skips rows that already have one). Rate-limited to respect quota.
//
// Usage:
//   GEMINI_API_KEY=... TABLE_PREFIX=rently- AWS_REGION=us-east-1 \
//     node scripts/backfill-embeddings.mjs [--dry-run] [--limit N] [--rate-ms 200]
//
// The embed logic mirrors geminiEmbed/listingEmbedText in
// aws/lambda/router/index.mjs — small and stable on purpose; keep in sync if the
// embed contract there changes. Self-contained so it runs with minimal blast
// radius (no importing the whole Lambda).

import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, ScanCommand, UpdateCommand } from '@aws-sdk/lib-dynamodb';

const API_KEY = process.env.GEMINI_API_KEY || '';
const MODEL = process.env.GEMINI_EMBED_MODEL || 'gemini-embedding-001';
const DIM = Number(process.env.EMBED_DIM) || 768;
const TABLE = `${process.env.TABLE_PREFIX || 'rently-'}properties`;
const REGION = process.env.AWS_REGION || 'us-east-1';
// Optional: also upsert into the S3 Vectors index (mirrors the router). Only
// runs when both are set; otherwise the script just writes embeddings to Dynamo.
const VEC_BUCKET = process.env.S3_VECTORS_BUCKET || '';
const VEC_INDEX = process.env.S3_VECTORS_INDEX || '';

const args = process.argv.slice(2);
const DRY = args.includes('--dry-run');
const LIMIT = numArg('--limit', Infinity);
const RATE_MS = numArg('--rate-ms', 200);

function numArg(flag, dflt) {
  const i = args.indexOf(flag);
  return i >= 0 && args[i + 1] ? Number(args[i + 1]) : dflt;
}

if (!API_KEY) {
  console.error('GEMINI_API_KEY required');
  process.exit(1);
}

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));

function listingEmbedText(body) {
  const title = (body.title || [body.street, body.city].filter(Boolean).join(' ') || '')
    .toString();
  const description = (body.description || '').toString();
  const tags = Array.isArray(body.smartTags) && body.smartTags.length
    ? body.smartTags.join(', ')
    : (Array.isArray(body.featureLabels) ? body.featureLabels.join(', ') : '');
  return [title, description, tags].filter(Boolean).join('\n').trim();
}

async function embed(text) {
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:embedContent?key=${API_KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: `models/${MODEL}`,
      content: { parts: [{ text: String(text).slice(0, 8000) }] },
      outputDimensionality: DIM,
    }),
  });
  if (!res.ok) throw new Error(`embed HTTP ${res.status}`);
  const data = await res.json();
  const vec = data?.embedding?.values;
  if (!Array.isArray(vec) || !vec.length) throw new Error('no vector in response');
  return vec;
}

// Lazy S3 Vectors upsert — dynamic import so the script still runs (embeddings
// only) when the SDK isn't installed. No-op unless bucket+index are configured.
let _s3v = null;
async function upsertVector(id, vector, item) {
  if (!VEC_BUCKET || !VEC_INDEX) return;
  if (!_s3v) {
    const mod = await import('@aws-sdk/client-s3vectors');
    _s3v = { mod, client: new mod.S3VectorsClient({ region: REGION }) };
  }
  await _s3v.client.send(new _s3v.mod.PutVectorsCommand({
    vectorBucketName: VEC_BUCKET,
    indexName: VEC_INDEX,
    vectors: [{
      key: String(id),
      data: { float32: vector },
      metadata: { city: item.city || '', price: Number(item.price) || 0, rooms: Number(item.rooms) || 0 },
    }],
  }));
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

async function main() {
  let scanned = 0;
  let embedded = 0;
  let skipped = 0;
  let failed = 0;
  let ExclusiveStartKey;
  console.log(
    `Backfill embeddings → ${TABLE} (model=${MODEL}, dim=${DIM}${DRY ? ', DRY-RUN' : ''})`,
  );
  do {
    const page = await ddb.send(new ScanCommand({ TableName: TABLE, ExclusiveStartKey }));
    for (const item of page.Items || []) {
      if (embedded >= LIMIT) break;
      scanned++;
      if (Array.isArray(item.embedding) && item.embedding.length) { skipped++; continue; }
      const text = listingEmbedText(item);
      if (!text) { skipped++; continue; }
      try {
        const vec = await embed(text);
        if (!DRY) {
          await ddb.send(new UpdateCommand({
            TableName: TABLE,
            Key: { id: item.id },
            UpdateExpression: 'SET embedding = :v, embeddingDim = :d, embeddingModel = :m',
            ExpressionAttributeValues: { ':v': vec, ':d': DIM, ':m': MODEL },
          }));
          await upsertVector(item.id, vec, item);
        }
        embedded++;
        if (embedded % 25 === 0) console.log(`  embedded ${embedded}…`);
        await sleep(RATE_MS);
      } catch (e) {
        failed++;
        console.warn(`  ${item.id}: ${e.message}`);
      }
    }
    ExclusiveStartKey = page.LastEvaluatedKey;
    if (embedded >= LIMIT) break;
  } while (ExclusiveStartKey);
  console.log(`Done. scanned=${scanned} embedded=${embedded} skipped=${skipped} failed=${failed}`);
}

main().catch((e) => { console.error(e); process.exit(1); });
