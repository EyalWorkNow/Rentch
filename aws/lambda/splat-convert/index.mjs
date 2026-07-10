// rentch-splat-convert — turns a Gaussian-splat .ply/.spz upload into a compact
// .ksplat that the in-app GaussianSplats3D viewer loads fast.
//
// A Scaniverse apartment .ply is 200-400 MB (uncompressed, ~200+ bytes/splat);
// .ksplat (level 1, half-float + spatial buckets) is a few × smaller AND pre-
// bucketed for a fast sort — the difference between "works in a lab" and "loads
// on a phone". The conversion uses mkkellogg's OWN parser/serializer (same lib
// version the app bundles) so the output is guaranteed viewer-compatible.
//
// Invoked async (Event) by the router after /3d/viewers stores the upload:
//   { bucket, key, propertyId?, tableName?, compressionLevel? }
// Writes <key>.ksplat next to the source and, when propertyId+tableName are
// given, sets model3d.ksplatUrl on the property so the client prefers it.

// The loaders only touch window.setTimeout (chunked-yield) — no WebGL/DOM. Shim it.
globalThis.window = globalThis.window || {
  setTimeout: (...a) => setTimeout(...a),
  clearTimeout: (...a) => clearTimeout(...a),
};
globalThis.document = globalThis.document || {};

import GS from '@mkkellogg/gaussian-splats-3d';
import {
  S3Client, GetObjectCommand, PutObjectCommand,
} from '@aws-sdk/client-s3';
import { DynamoDBClient } from '@aws-sdk/client-dynamodb';
import { DynamoDBDocumentClient, UpdateCommand } from '@aws-sdk/lib-dynamodb';

const REGION = process.env.AWS_REGION || 'us-east-1';
const s3 = new S3Client({ region: REGION });
const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }));

// Drop near-transparent splats (0..255); keep quality high but shed the haze that
// bloats an indoor scan. Half-float compression (level 1). SH degree 0 keeps size
// down (view-dependent colour off) — indoor lighting barely benefits from SH.
const ALPHA_REMOVAL = Number(process.env.SPLAT_ALPHA_REMOVAL || 5);
const SH_DEGREE = Number(process.env.SPLAT_SH_DEGREE || 0);

function bytesOf(splatBuffer) {
  const v = splatBuffer.bufferData;
  if (!v) throw new Error('SplatBuffer has no bufferData');
  return Buffer.from(v);
}

async function streamToBuffer(stream) {
  const chunks = [];
  for await (const c of stream) chunks.push(c);
  return Buffer.concat(chunks);
}

// Parse a .ply / .spz ArrayBuffer → viewer-ready .ksplat bytes (level 1).
export async function convertToKsplat(arrayBuffer, sourceKey, compressionLevel = 1) {
  const isSpz = sourceKey.toLowerCase().endsWith('.spz');
  const loader = isSpz ? GS.SpzLoader : GS.PlyLoader;
  // (fileData, alphaRemovalThreshold, compressionLevel, optimizeSplatData, outSphericalHarmonicsDegree)
  const splatBuffer = await loader.loadFromFileData(
    arrayBuffer, ALPHA_REMOVAL, compressionLevel, true, SH_DEGREE,
  );
  return { bytes: bytesOf(splatBuffer), splatCount: splatBuffer.getSplatCount() };
}

export async function handler(event) {
  const { bucket, key, propertyId, tableName, compressionLevel } = event || {};
  if (!bucket || !key) {
    return { ok: false, error: 'missing bucket/key' };
  }
  const lower = key.toLowerCase();
  if (!lower.endsWith('.ply') && !lower.endsWith('.spz')) {
    return { ok: false, error: `unsupported source: ${key}` };
  }

  const obj = await s3.send(new GetObjectCommand({ Bucket: bucket, Key: key }));
  const buf = await streamToBuffer(obj.Body);
  const ab = buf.buffer.slice(buf.byteOffset, buf.byteOffset + buf.byteLength);

  const { bytes, splatCount } = await convertToKsplat(
    ab, key, Number(compressionLevel) || 1,
  );

  const outKey = key.replace(/\.(ply|spz)$/i, '.ksplat');
  await s3.send(new PutObjectCommand({
    Bucket: bucket,
    Key: outKey,
    Body: bytes,
    ContentType: 'application/octet-stream',
    CacheControl: 'public, max-age=31536000, immutable',
  }));
  const ksplatUrl = `https://${bucket}.s3.${REGION}.amazonaws.com/${outKey}`;

  // Point the property at the converted asset so the client prefers it. Fail-soft:
  // if the update fails, the .ksplat still exists and the router already returned
  // the predicted URL — the client just falls back to the .ply.
  if (propertyId && tableName) {
    try {
      await ddb.send(new UpdateCommand({
        TableName: tableName,
        Key: { id: String(propertyId) },
        UpdateExpression: 'SET model3d.ksplatUrl = :u',
        ExpressionAttributeValues: { ':u': ksplatUrl },
      }));
    } catch (e) {
      console.warn('ksplatUrl DDB update failed:', e.message);
    }
  }

  console.log(`converted ${key} → ${outKey} (${splatCount} splats, ${bytes.length} bytes)`);
  return { ok: true, ksplatUrl, outKey, splatCount, bytes: bytes.length };
}
