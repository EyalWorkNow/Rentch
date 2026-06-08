// Rentch API router — single Lambda handling all REST routes.
//
// Routes (see docs/AWS_BACKEND_CONTRACT.md):
//   GET    /{table}            list (with query filters)
//   GET    /{table}/{id}       get one
//   POST   /{table}            create
//   PUT    /{table}/{id}       upsert
//   DELETE /{table}/{id}       delete
//   POST   /storage/presign    → { uploadUrl, publicUrl }
//   DELETE /storage/{key+}     delete S3 object
//   POST   /3d/viewers         → create hosted viewer HTML for uploaded 3D assets
//
// Uses the AWS SDK v3 bundled in the Node.js 20 Lambda runtime (no node_modules).

import {
  DynamoDBClient,
} from '@aws-sdk/client-dynamodb';
import {
  DynamoDBDocumentClient,
  GetCommand,
  PutCommand,
  DeleteCommand,
  QueryCommand,
  ScanCommand,
} from '@aws-sdk/lib-dynamodb';
import { S3Client, DeleteObjectCommand, PutObjectCommand, GetObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

const REGION = process.env.AWS_REGION;
const S3_BUCKET = process.env.S3_BUCKET;
const TABLE_PREFIX = process.env.TABLE_PREFIX || 'rentch-';
const LUMA_API_KEY = process.env.LUMA_API_KEY || '';
// Luma Agents image API (uni-1) — virtual staging via image_edit.
const LUMA_BASE = 'https://agents.lumalabs.ai/v1';

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});
const s3 = new S3Client({ region: REGION });

// Path segment → DynamoDB table name. Also defines the partition-key attribute
// and an optional GSI used for list queries.
const TABLES = {
  properties:      { name: `${TABLE_PREFIX}properties`,      gsi: { name: 'status-createdAt',     pk: 'status',         filterKey: 'status' }, ownerIndex: 'ownerUserId-createdAt' },
  messages:        { name: `${TABLE_PREFIX}messages`,        gsi: { name: 'matchId-createdAt',    pk: 'matchId',        filterKey: 'matchId' } },
  users:           { name: `${TABLE_PREFIX}users`,           gsi: { name: 'discoverable-updatedAt', pk: 'discoverable', filterKey: 'discoverable' } },
  events:          { name: `${TABLE_PREFIX}events`,          gsi: null },
  reports:         { name: `${TABLE_PREFIX}reports`,         gsi: null },
  blocks:          { name: `${TABLE_PREFIX}blocks`,          gsi: null },
  reviews:         { name: `${TABLE_PREFIX}reviews`,         gsi: { name: 'targetKey-createdAt', pk: 'targetKey', filterKey: 'targetKey' } },
  property_views:  { name: `${TABLE_PREFIX}property-views`,  gsi: { name: 'propertyId-index', pk: 'propertyId', filterKey: 'propertyId' } },
  property_likes:  { name: `${TABLE_PREFIX}property-likes`,  gsi: { name: 'propertyId-index', pk: 'propertyId', filterKey: 'propertyId' } },
  app_state:       { name: `${TABLE_PREFIX}app-state`,       gsi: null },
};

const json = (status, body) => ({
  statusCode: status,
  headers: {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Headers': 'Authorization,Content-Type,x-api-key',
    'Access-Control-Allow-Methods': 'GET,POST,PUT,DELETE,OPTIONS',
  },
  body: JSON.stringify(body),
});

export const handler = async (event) => {
  try {
    const method = event.httpMethod;
    const path = event.path || '';
    const segments = path.split('/').filter(Boolean);

    if (method === 'OPTIONS') return json(200, {});

    // ── Storage routes ──────────────────────────────────────────────────────
    if (segments[0] === 'storage') {
      return await handleStorage(method, segments, event);
    }

    // ── 3D viewer routes ────────────────────────────────────────────────────
    if (segments[0] === '3d' && segments[1] === 'viewers' && method === 'POST') {
      return await create3dViewer(event);
    }

    // ── Scan routes ─────────────────────────────────────────────────────────
    if (segments[0] === 'scans') {
      const scanId = segments[1] ? decodeURIComponent(segments[1]) : null;
      // POST /scans → create scan job + presigned upload URL
      if (method === 'POST' && !scanId) return await createScan(event);
      // POST /scans/:id/process → build video viewer HTML
      if (method === 'POST' && scanId && segments[2] === 'process') return await processScan(scanId);
      // GET /scans/:id → return scan status + viewerUrl
      if (method === 'GET' && scanId) return await getScan(scanId);
      return json(404, { message: 'Unknown scan route' });
    }

    // ── Table CRUD ──────────────────────────────────────────────────────────
    const tableKey = segments[0];
    const table = TABLES[tableKey];
    if (!table) return json(404, { message: `Unknown resource: ${tableKey}` });

    const id = segments[1] ? decodeURIComponent(segments[1]) : null;
    const body = event.body ? JSON.parse(event.body) : {};
    const query = event.queryStringParameters || {};

    switch (method) {
      case 'GET':
        return id
          ? await getOne(table, id)
          : await listItems(table, query);
      case 'POST':
        return await putItem(table, body.id || body.propertyId || body.userId, body);
      case 'PUT':
        return await putItem(table, id, body);
      case 'DELETE':
        return await deleteItem(table, id);
      default:
        return json(405, { message: 'Method not allowed' });
    }
  } catch (e) {
    console.error('Router error:', e);
    return json(500, { message: e.message });
  }
};

// ── DynamoDB handlers ────────────────────────────────────────────────────────

async function getOne(table, id) {
  const r = await ddb.send(new GetCommand({ TableName: table.name, Key: { id } }));
  return r.Item ? json(200, r.Item) : json(404, {});
}

async function listItems(table, query) {
  const limit = Math.min(parseInt(query.limit || '150', 10), 500);
  const filterKey = table.gsi?.filterKey;
  const filterVal = filterKey ? query[filterKey] : undefined;
  const cursor = parseCursor(query.lastKey);

  // Per-owner query (e.g. GET /properties?ownerUserId=<uid>) — uses a dedicated
  // GSI so a user only ever reads their own rows, never a full-table scan.
  if (table.ownerIndex && query.ownerUserId) {
    const out = await ddb.send(new QueryCommand({
      TableName: table.name,
      IndexName: table.ownerIndex,
      KeyConditionExpression: '#o = :o',
      ExpressionAttributeNames: { '#o': 'ownerUserId' },
      ExpressionAttributeValues: { ':o': String(query.ownerUserId) },
      Limit: limit,
      ExclusiveStartKey: cursor,
      ScanIndexForward: query.order !== 'desc',
    }));
    return json(200, pageBody(out));
  }

  // Query the GSI when the matching filter is supplied (efficient path).
  if (table.gsi && filterVal !== undefined) {
    const out = await ddb.send(new QueryCommand({
      TableName: table.name,
      IndexName: table.gsi.name,
      KeyConditionExpression: '#pk = :v',
      ExpressionAttributeNames: { '#pk': table.gsi.pk },
      ExpressionAttributeValues: { ':v': castFilter(filterVal) },
      Limit: limit,
      ExclusiveStartKey: cursor,
      ScanIndexForward: query.order !== 'desc',
    }));
    return json(200, pageBody(out));
  }

  // Fallback: Scan with optional FilterExpression.
  const params = { TableName: table.name, Limit: limit, ExclusiveStartKey: cursor };
  if (filterKey && filterVal !== undefined) {
    params.FilterExpression = '#k = :v';
    params.ExpressionAttributeNames = { '#k': filterKey };
    params.ExpressionAttributeValues = { ':v': castFilter(filterVal) };
  }
  const out = await ddb.send(new ScanCommand(params));
  return json(200, pageBody(out));
}

function pageBody(out) {
  return {
    items: out.Items || [],
    hasMore: !!out.LastEvaluatedKey,
    lastKey: out.LastEvaluatedKey
      ? encodeURIComponent(JSON.stringify(out.LastEvaluatedKey))
      : null,
  };
}

function parseCursor(cursor) {
  if (!cursor) return undefined;
  try {
    return JSON.parse(decodeURIComponent(cursor));
  } catch {
    return undefined;
  }
}

async function putItem(table, id, body) {
  if (!id) return json(400, { message: 'Missing id' });
  const item = { ...body, id };
  await ddb.send(new PutCommand({ TableName: table.name, Item: item }));
  return json(200, item);
}

async function deleteItem(table, id) {
  if (!id) return json(400, { message: 'Missing id' });
  await ddb.send(new DeleteCommand({ TableName: table.name, Key: { id } }));
  return json(200, { id, deleted: true });
}

function castFilter(v) {
  if (v === 'true') return true;
  if (v === 'false') return false;
  const n = Number(v);
  return Number.isFinite(n) && v.trim?.() !== '' ? v : v; // keep strings as-is
}

// ── S3 storage handlers ───────────────────────────────────────────────────────

async function handleStorage(method, segments, event) {
  // POST /storage/presign
  if (method === 'POST' && segments[1] === 'presign') {
    const body = event.body ? JSON.parse(event.body) : {};
    const key = body.key;
    const contentType = body.contentType || 'application/octet-stream';
    if (!key) return json(400, { message: 'Missing key' });

    const uploadUrl = await getSignedUrl(
      s3,
      new PutObjectCommand({ Bucket: S3_BUCKET, Key: key, ContentType: contentType }),
      { expiresIn: 900 },
    );
    const publicUrl = `https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/${key}`;
    return json(200, { uploadUrl, publicUrl, key });
  }

  // DELETE /storage/{key+}
  if (method === 'DELETE') {
    const key = segments.slice(1).map(decodeURIComponent).join('/');
    if (!key) return json(400, { message: 'Missing key' });
    await s3.send(new DeleteObjectCommand({ Bucket: S3_BUCKET, Key: key }));
    return json(200, { key, deleted: true });
  }

  return json(404, { message: 'Unknown storage route' });
}

async function create3dViewer(event) {
  const body = event.body ? JSON.parse(event.body) : {};
  const propertyId = sanitizeId(body.propertyId || body.id || 'property');
  const title = sanitizeText(body.title || 'Rentch 3D Tour');
  const assets = normalizeAssets(body.assets);
  if (assets.length === 0) {
    return json(400, { message: 'At least one 3D asset URL is required.' });
  }

  const manifest = build3dManifest(assets);
  const html = renderViewerHtml({
    title,
    manifest,
    propertyId,
  });
  const key = `3d-viewers/${propertyId}/${Date.now()}-${Math.random().toString(36).slice(2, 10)}.html`;
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: key,
    Body: html,
    ContentType: 'text/html; charset=utf-8',
    CacheControl: 'public, max-age=300',
  }));

  const viewerUrl = `https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/${key}`;
  return json(200, {
    data: {
      scanId: `scan_${propertyId}_${Date.now()}`,
      viewerUrl,
      downloadUrl: manifest.downloadUrl,
      format: manifest.format,
      model3d: {
        viewerUrl,
        glbUrl: manifest.glbUrl,
        objUrl: manifest.objUrl,
        mtlUrl: manifest.mtlUrl,
        usdzUrl: manifest.usdzUrl,
        spzUrl: manifest.spzUrl,
        plyUrl: manifest.plyUrl,
        textureFolder: manifest.textureFolder,
        assets,
      },
    },
  });
}

function normalizeAssets(rawAssets) {
  if (!Array.isArray(rawAssets)) return [];
  return rawAssets
    .map((item) => {
      if (!item || typeof item !== 'object') return null;
      const url = typeof item.url === 'string' ? item.url.trim() : '';
      if (!isAllowedAssetUrl(url)) return null;
      const fileName = sanitizeText(item.fileName || fileNameFromUrl(url));
      const kind = sanitizeAssetKind(item.kind || inferAssetKind(fileName, url));
      const contentType = typeof item.contentType === 'string'
        ? item.contentType.trim()
        : '';
      const sizeBytes = Number.isFinite(Number(item.sizeBytes))
        ? Number(item.sizeBytes)
        : null;
      return {
        kind,
        url,
        fileName,
        contentType,
        sizeBytes,
      };
    })
    .filter(Boolean);
}

function build3dManifest(assets) {
  const byKind = (kind) => assets.find((item) => item.kind === kind)?.url || '';
  const textureAssets = assets.filter((item) => item.kind === 'texture');
  return {
    format: preferredFormat(assets),
    downloadUrl: preferredDownloadUrl(assets),
    glbUrl: byKind('glb'),
    objUrl: byKind('obj'),
    mtlUrl: byKind('mtl'),
    usdzUrl: byKind('usdz'),
    spzUrl: byKind('spz'),
    plyUrl: byKind('ply'),
    textureFolder: textureAssets.length > 0 ? commonPrefix(textureAssets.map((item) => item.url)) : '',
    assets,
  };
}

function preferredFormat(assets) {
  const order = ['glb', 'usdz', 'obj', 'spz', 'ply', 'sog'];
  for (const kind of order) {
    if (assets.some((item) => item.kind === kind)) return kind;
  }
  return assets[0]?.kind || '';
}

function preferredDownloadUrl(assets) {
  const order = ['glb', 'usdz', 'obj', 'spz', 'ply', 'sog'];
  for (const kind of order) {
    const match = assets.find((item) => item.kind === kind);
    if (match?.url) return match.url;
  }
  return assets[0]?.url || '';
}

function renderViewerHtml({ title, manifest, propertyId }) {
  const config = JSON.stringify(manifest);
  const safeTitle = escapeHtml(title);
  const safePropertyId = escapeHtml(propertyId);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${safeTitle}</title>
  <style>
    :root { color-scheme: dark; }
    html, body { margin: 0; height: 100%; background: #07111c; color: #f5f7fb; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { display: flex; flex-direction: column; }
    header { padding: 16px 18px 12px; border-bottom: 1px solid rgba(255,255,255,0.08); background: rgba(7,17,28,0.92); backdrop-filter: blur(12px); }
    h1 { margin: 0; font-size: 18px; line-height: 1.2; }
    p { margin: 6px 0 0; color: rgba(245,247,251,0.72); font-size: 13px; }
    #viewer { flex: 1; position: relative; min-height: 320px; }
    #fallback, #obj-container, model-viewer, iframe { position: absolute; inset: 0; width: 100%; height: 100%; border: 0; }
    #fallback { display: none; padding: 24px; overflow: auto; box-sizing: border-box; }
    ul { padding-left: 20px; }
    a { color: #9bd1ff; }
    canvas { display: block; width: 100%; height: 100%; }
  </style>
  <script type="module" src="https://unpkg.com/@google/model-viewer/dist/model-viewer.min.js"></script>
</head>
<body>
  <header>
    <h1>${safeTitle}</h1>
    <p>Rentch property ${safePropertyId}</p>
  </header>
  <div id="viewer">
    <model-viewer id="model-viewer" camera-controls touch-action="pan-y" interaction-prompt="auto" ar></model-viewer>
    <div id="obj-container" hidden></div>
    <iframe id="external-viewer" hidden allowfullscreen></iframe>
    <div id="fallback"></div>
  </div>
  <script type="module">
    const config = ${config};
    const modelViewer = document.getElementById('model-viewer');
    const objContainer = document.getElementById('obj-container');
    const externalViewer = document.getElementById('external-viewer');
    const fallback = document.getElementById('fallback');

    const renderFallback = (reason) => {
      modelViewer.hidden = true;
      objContainer.hidden = true;
      externalViewer.hidden = true;
      fallback.style.display = 'block';
      const links = (config.assets || []).map((asset) =>
        '<li><a href="' + asset.url + '" target="_blank" rel="noreferrer">' +
        (asset.fileName || asset.kind || asset.url) + '</a> (' + asset.kind + ')</li>'
      ).join('');
      fallback.innerHTML =
        '<h2 style="margin-top:0">Viewer unavailable</h2>' +
        '<p>' + reason + '</p>' +
        '<ul>' + links + '</ul>';
    };

    if (config.glbUrl || config.usdzUrl) {
      modelViewer.src = config.glbUrl || '';
      if (config.usdzUrl) modelViewer.setAttribute('ios-src', config.usdzUrl);
      modelViewer.hidden = false;
    } else if (config.objUrl) {
      modelViewer.hidden = true;
      objContainer.hidden = false;
      const THREE = await import('https://unpkg.com/three@0.166.1/build/three.module.js');
      const { OrbitControls } = await import('https://unpkg.com/three@0.166.1/examples/jsm/controls/OrbitControls.js');
      const { OBJLoader } = await import('https://unpkg.com/three@0.166.1/examples/jsm/loaders/OBJLoader.js');
      const { MTLLoader } = await import('https://unpkg.com/three@0.166.1/examples/jsm/loaders/MTLLoader.js');

      const scene = new THREE.Scene();
      scene.background = new THREE.Color(0x07111c);
      const camera = new THREE.PerspectiveCamera(60, objContainer.clientWidth / Math.max(objContainer.clientHeight, 1), 0.01, 1000);
      camera.position.set(0, 1.4, 3.8);

      const renderer = new THREE.WebGLRenderer({ antialias: true });
      renderer.setPixelRatio(window.devicePixelRatio || 1);
      renderer.setSize(objContainer.clientWidth, Math.max(objContainer.clientHeight, 1));
      objContainer.appendChild(renderer.domElement);

      scene.add(new THREE.AmbientLight(0xffffff, 1.2));
      const keyLight = new THREE.DirectionalLight(0xffffff, 1.4);
      keyLight.position.set(4, 8, 6);
      scene.add(keyLight);

      const controls = new OrbitControls(camera, renderer.domElement);
      controls.enableDamping = true;

      const fitCamera = (object) => {
        const box = new THREE.Box3().setFromObject(object);
        const size = box.getSize(new THREE.Vector3());
        const center = box.getCenter(new THREE.Vector3());
        controls.target.copy(center);
        const maxDim = Math.max(size.x, size.y, size.z, 1);
        camera.position.set(center.x, center.y + maxDim * 0.3, center.z + maxDim * 1.8);
        camera.near = maxDim / 100;
        camera.far = maxDim * 100;
        camera.updateProjectionMatrix();
      };

      const loader = new OBJLoader();
      if (config.mtlUrl) {
        const materials = await new MTLLoader().loadAsync(config.mtlUrl);
        materials.preload();
        loader.setMaterials(materials);
      }
      const object = await loader.loadAsync(config.objUrl);
      scene.add(object);
      fitCamera(object);

      const onResize = () => {
        const width = objContainer.clientWidth;
        const height = Math.max(objContainer.clientHeight, 1);
        camera.aspect = width / height;
        camera.updateProjectionMatrix();
        renderer.setSize(width, height);
      };
      window.addEventListener('resize', onResize);
      onResize();

      const tick = () => {
        controls.update();
        renderer.render(scene, camera);
        requestAnimationFrame(tick);
      };
      tick();
    } else if (config.viewerUrl) {
      modelViewer.hidden = true;
      externalViewer.hidden = false;
      externalViewer.src = config.viewerUrl;
    } else {
      renderFallback('No renderable GLB, USDZ, or OBJ asset was uploaded for this property.');
    }
  </script>
</body>
</html>`;
}

function isAllowedAssetUrl(value) {
  try {
    const url = new URL(value);
    return url.protocol === 'https:';
  } catch {
    return false;
  }
}

function inferAssetKind(fileName, url) {
  const source = (fileName || url || '').toLowerCase();
  if (source.endsWith('.glb') || source.endsWith('.gltf')) return 'glb';
  if (source.endsWith('.obj')) return 'obj';
  if (source.endsWith('.mtl')) return 'mtl';
  if (source.endsWith('.usdz')) return 'usdz';
  if (source.endsWith('.spz')) return 'spz';
  if (source.endsWith('.ply')) return 'ply';
  if (source.endsWith('.sog')) return 'sog';
  if (source.endsWith('.png') || source.endsWith('.jpg') || source.endsWith('.jpeg') || source.endsWith('.webp') || source.endsWith('.ktx2')) return 'texture';
  if (source.endsWith('.bin')) return 'buffer';
  return 'asset';
}

function sanitizeAssetKind(value) {
  const normalized = String(value || '').toLowerCase().replace(/[^a-z0-9_-]/g, '');
  return normalized || 'asset';
}

function sanitizeId(value) {
  return String(value || 'property').replace(/[^A-Za-z0-9._/-]/g, '_').slice(0, 120) || 'property';
}

function sanitizeText(value) {
  return String(value || '').replace(/[\u0000-\u001f]+/g, ' ').trim().slice(0, 180);
}

function fileNameFromUrl(value) {
  try {
    const url = new URL(value);
    return decodeURIComponent(url.pathname.split('/').pop() || '');
  } catch {
    return '';
  }
}

function commonPrefix(values) {
  if (values.length === 0) return '';
  let prefix = values[0];
  for (const value of values.slice(1)) {
    while (!value.startsWith(prefix) && prefix) {
      prefix = prefix.slice(0, -1);
    }
  }
  const slash = prefix.lastIndexOf('/');
  return slash >= 0 ? prefix.slice(0, slash + 1) : prefix;
}

// ── Scan handlers (video → virtual-tour viewer) ──────────────────────────────

// ── Virtual staging ("הדמיה") via Luma Agents uni-1 image_edit ───────────────
// Flow: POST /scans → presigned PUT for the source photo; client uploads it;
// POST /scans/:id/process → kick off a Luma image_edit generation;
// GET /scans/:id → poll Luma, re-host the result on S3, return the staged URL.

const STAGING_STYLES = ['modern', 'scandinavian', 'cozy', 'luxury', 'empty_to_furnished'];

function sanitizeStyle(value) {
  const s = (value || '').toString().toLowerCase().trim();
  return STAGING_STYLES.includes(s) ? s : 'modern';
}

function stagingPrompt(style) {
  const styleText = {
    modern: 'Furnish and decorate this room as a warm, modern living space with contemporary furniture, a sofa, coffee table, rug, plants and soft natural lighting.',
    scandinavian: 'Furnish this room in a bright Scandinavian style: light wood furniture, neutral tones, cozy textiles, minimal decor and abundant natural light.',
    cozy: 'Furnish this room as a cozy, inviting home: warm lighting, comfortable sofa, soft rugs, cushions, plants and homely decor.',
    luxury: 'Furnish this room as a high-end luxury interior: elegant designer furniture, refined materials, tasteful art, ambient lighting and a premium real-estate look.',
    empty_to_furnished: 'Fully furnish this empty room with tasteful modern furniture and decor appropriate to the space, with pleasant lighting.',
  }[style] || '';
  return `${styleText} Photorealistic real-estate listing photo, high quality. Preserve the existing windows, doors, walls, floor, ceiling and overall room architecture exactly as they are — only add furniture, decor and lighting. Do not change the room layout, structure or proportions.`;
}

async function getScanMeta(scanId) {
  try {
    const obj = await s3.send(new GetObjectCommand({
      Bucket: S3_BUCKET,
      Key: `3d-scans/meta/${scanId}.json`,
    }));
    return JSON.parse(await streamToString(obj.Body));
  } catch {
    return null;
  }
}

async function putScanMeta(scanId, meta) {
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: `3d-scans/meta/${scanId}.json`,
    Body: JSON.stringify(meta),
    ContentType: 'application/json',
  }));
}

function scanResponse(meta) {
  const url = meta.stagedUrl || meta.viewerUrl || '';
  return json(200, {
    data: {
      id: meta.scanId,
      scanId: meta.scanId,
      status: meta.status || 'pending',
      viewerUrl: url,
      previewImageUrl: url,
      downloadUrl: url,
      processingError: meta.error || '',
      format: 'image',
    },
  });
}

// Download the Luma presigned result (expires in 1h) and re-host permanently on S3.
async function rehostImage(sourceUrl, key) {
  const res = await fetch(sourceUrl);
  if (!res.ok) throw new Error(`rehost download failed ${res.status}`);
  const buf = Buffer.from(await res.arrayBuffer());
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: key,
    Body: buf,
    ContentType: 'image/png',
    CacheControl: 'public, max-age=31536000',
  }));
  return `https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/${key}`;
}

async function createScan(event) {
  const body = event.body ? JSON.parse(event.body) : {};
  const propertyId = sanitizeId(body.propertyId || body.id || 'prop');
  const style = sanitizeStyle(body.style);
  const contentType = (body.contentType || 'image/jpeg').toLowerCase();
  const ts = Date.now();
  const rand = Math.random().toString(36).slice(2, 10);
  const scanId = `st_${ts}_${rand}`;
  const ext = contentType.includes('png') ? 'png'
    : contentType.includes('webp') ? 'webp'
    : contentType.includes('heic') ? 'heic'
    : 'jpg';
  const srcKey = `staging-src/${propertyId}/${scanId}.${ext}`;

  const uploadUrl = await getSignedUrl(
    s3,
    new PutObjectCommand({ Bucket: S3_BUCKET, Key: srcKey, ContentType: contentType }),
    { expiresIn: 3600 },
  );

  const meta = { scanId, propertyId, srcKey, style, contentType, provider: 'luma-staging', status: 'pending', createdAt: ts };
  await putScanMeta(scanId, meta);
  return json(200, { data: { scanId, uploadUrl } });
}

async function processScan(scanId) {
  const meta = await getScanMeta(scanId);
  if (!meta) return json(404, { message: 'Scan not found' });

  if (!LUMA_API_KEY) {
    const updated = { ...meta, status: 'failed', error: 'Staging is not configured (no LUMA_API_KEY).' };
    await putScanMeta(scanId, updated);
    return scanResponse(updated);
  }

  const srcUrl = `https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/${meta.srcKey}`;
  try {
    const res = await fetch(`${LUMA_BASE}/generations`, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${LUMA_API_KEY}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        type: 'image_edit',
        model: 'uni-1',
        prompt: stagingPrompt(meta.style),
        source: { url: srcUrl },
      }),
    });
    if (!res.ok) {
      const txt = await res.text();
      console.warn('Luma create generation failed', res.status, txt);
      const updated = { ...meta, status: 'failed', error: `Luma error ${res.status}` };
      await putScanMeta(scanId, updated);
      return scanResponse(updated);
    }
    const data = await res.json();
    if (!data.id) {
      const updated = { ...meta, status: 'failed', error: 'Luma returned no generation id' };
      await putScanMeta(scanId, updated);
      return scanResponse(updated);
    }
    const updated = { ...meta, generationId: data.id, srcUrl, status: 'processing', processedAt: Date.now() };
    await putScanMeta(scanId, updated);
    return json(200, { data: { id: scanId, scanId, status: 'processing', viewerUrl: '', previewImageUrl: '', format: 'image' } });
  } catch (e) {
    console.warn('Luma create generation error', e.message);
    const updated = { ...meta, status: 'failed', error: e.message };
    await putScanMeta(scanId, updated);
    return scanResponse(updated);
  }
}

async function getScan(scanId) {
  const meta = await getScanMeta(scanId);
  if (!meta) return json(404, { message: 'Scan not found' });

  if (meta.status === 'ready' || meta.status === 'failed') {
    return scanResponse(meta);
  }

  if (meta.generationId && LUMA_API_KEY) {
    try {
      const res = await fetch(`${LUMA_BASE}/generations/${meta.generationId}`, {
        headers: { 'Authorization': `Bearer ${LUMA_API_KEY}` },
      });
      if (res.ok) {
        const data = await res.json();
        const state = (data.state || '').toLowerCase();
        if (state === 'completed') {
          const outUrl = data.output && data.output[0] && data.output[0].url;
          if (outUrl) {
            const stagedKey = `staged/${meta.propertyId}/${scanId}.png`;
            const stagedUrl = await rehostImage(outUrl, stagedKey);
            const updated = { ...meta, status: 'ready', viewerUrl: stagedUrl, stagedUrl, completedAt: Date.now() };
            await putScanMeta(scanId, updated);
            return scanResponse(updated);
          }
          const updated = { ...meta, status: 'failed', error: 'Luma completed with no image output' };
          await putScanMeta(scanId, updated);
          return scanResponse(updated);
        }
        if (state === 'failed') {
          const updated = { ...meta, status: 'failed', error: data.failure_reason || 'Luma generation failed' };
          await putScanMeta(scanId, updated);
          return scanResponse(updated);
        }
        // queued / processing
        return json(200, { data: { id: scanId, scanId, status: 'processing', viewerUrl: '', previewImageUrl: '', format: 'image' } });
      }
      console.warn('Luma getScan poll HTTP', res.status);
    } catch (e) {
      console.warn('Luma getScan poll failed:', e.message);
    }
  }

  return scanResponse(meta);
}

async function streamToString(stream) {
  const chunks = [];
  for await (const chunk of stream) chunks.push(chunk);
  return Buffer.concat(chunks).toString('utf-8');
}

function renderVideoViewerHtml({ title, videoUrl, propertyId }) {
  const safeTitle = escapeHtml(title);
  const safePropId = escapeHtml(propertyId);
  const safeVideoUrl = escapeHtml(videoUrl);
  return `<!doctype html>
<html lang="he" dir="rtl">
<head>
  <meta charset="utf-8"/>
  <meta name="viewport" content="width=device-width,initial-scale=1,user-scalable=no,viewport-fit=cover"/>
  <meta name="apple-mobile-web-app-capable" content="yes"/>
  <meta name="apple-mobile-web-app-status-bar-style" content="black-translucent"/>
  <title>${safeTitle} · סיור וירטואלי</title>
  <script src="https://aframe.io/releases/1.5.0/aframe.min.js"><\/script>
  <style>
    *{box-sizing:border-box;margin:0;padding:0;-webkit-tap-highlight-color:transparent}
    html,body{width:100%;height:100%;background:#07111c;overflow:hidden;
      font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;color:#f5f7fb}
    a-scene{position:fixed;top:0;left:0;width:100vw;height:100vh;z-index:0}
    #overlay{position:fixed;top:0;left:0;right:0;bottom:0;z-index:100;pointer-events:none}

    /* Header */
    #hdr{position:absolute;top:0;left:0;right:0;
      padding:max(env(safe-area-inset-top,16px),16px) 18px 18px;
      background:linear-gradient(to bottom,rgba(7,17,28,.92) 0%,rgba(7,17,28,.5) 60%,transparent 100%);
      display:flex;align-items:center;gap:12px}
    .logo{width:38px;height:38px;flex-shrink:0;
      background:linear-gradient(135deg,#0ea5e9,#1d4ed8);border-radius:10px;
      display:flex;align-items:center;justify-content:center;
      font-weight:900;font-size:16px;color:#fff;
      box-shadow:0 2px 14px rgba(14,165,233,.45)}
    .prop-name{font-size:15px;font-weight:700;letter-spacing:-.3px;line-height:1.25}
    .prop-sub{font-size:11px;color:rgba(245,247,251,.5);margin-top:2px}
    .badge{margin-right:auto;white-space:nowrap;
      background:rgba(14,165,233,.14);border:1px solid rgba(14,165,233,.3);
      color:#7dd3fc;font-size:11px;font-weight:700;letter-spacing:.5px;
      padding:4px 11px;border-radius:20px}

    /* Loading */
    #loading{position:absolute;inset:0;
      display:flex;flex-direction:column;align-items:center;justify-content:center;gap:18px;
      background:#07111c;transition:opacity .6s ease}
    #loading.gone{opacity:0;pointer-events:none}
    .spin{width:52px;height:52px;border-radius:50%;
      border:3px solid rgba(14,165,233,.15);border-top-color:#0ea5e9;
      animation:spin 1s linear infinite}
    @keyframes spin{to{transform:rotate(360deg)}}
    .load-lbl{font-size:14px;color:rgba(245,247,251,.55);letter-spacing:.2px}

    /* Toast hint */
    #toast{position:absolute;bottom:110px;left:50%;transform:translateX(-50%);
      background:rgba(7,17,28,.88);border:1px solid rgba(255,255,255,.1);
      border-radius:24px;padding:10px 20px;
      font-size:13px;color:rgba(245,247,251,.78);text-align:center;white-space:nowrap;
      transition:opacity .6s ease;pointer-events:none}
    #toast.gone{opacity:0}
    #toast.tap{pointer-events:all;cursor:pointer}

    /* Progress */
    #pgwrap{position:absolute;left:0;right:0;bottom:60px;padding:0 18px;
      pointer-events:all;cursor:pointer}
    #pg{height:3px;background:rgba(255,255,255,.18);border-radius:2px;
      overflow:hidden;transition:height .15s}
    #pgwrap:hover #pg{height:5px}
    #pgbar{height:100%;background:#0ea5e9;border-radius:2px;width:0;transition:width .1s linear}

    /* Controls bar */
    #ctrl{position:absolute;bottom:0;left:0;right:0;
      padding:10px 18px max(env(safe-area-inset-bottom,12px),12px);
      background:linear-gradient(to top,rgba(7,17,28,.92) 0%,rgba(7,17,28,.5) 60%,transparent 100%);
      display:flex;align-items:center;gap:12px;pointer-events:none}
    .btn{background:rgba(255,255,255,.09);border:1px solid rgba(255,255,255,.13);
      color:#fff;cursor:pointer;border-radius:50%;width:42px;height:42px;
      display:flex;align-items:center;justify-content:center;
      pointer-events:all;transition:background .15s,border-color .15s;flex-shrink:0}
    .btn:hover,.btn:active{background:rgba(255,255,255,.2);border-color:rgba(255,255,255,.25)}
    .btn svg{display:block}
    .btnw{border-radius:21px;width:auto;padding:0 14px;gap:6px;
      font-size:11px;font-weight:700;letter-spacing:.4px}
    #timer{font-size:12px;color:rgba(245,247,251,.5);pointer-events:none;margin-right:auto}
    @keyframes fadeUp{from{opacity:0;transform:translateY(14px)}to{opacity:1;transform:translateY(0)}}
    #hdr,#ctrl{animation:fadeUp .5s ease both}
    #ctrl{animation-delay:.08s}
  </style>
</head>
<body>

<a-scene
  embedded
  vr-mode-ui="enabled:true"
  device-orientation-permission-ui="enabled:true"
  renderer="antialias:true;colorManagement:true"
  loading-screen="enabled:false"
>
  <a-assets timeout="30000">
    <video id="tv" src="${safeVideoUrl}"
      crossorigin="anonymous" preload="auto"
      playsinline webkit-playsinline loop>
    </video>
  </a-assets>

  <a-sky color="#050d14"></a-sky>

  <!-- Video wraps inner surface of sphere — user stands inside, looking out -->
  <a-videosphere src="#tv" rotation="0 -90 0"
    segments-height="64" segments-width="64" radius="100">
  </a-videosphere>

  <a-light type="ambient" color="#0d2540" intensity="0.5"></a-light>

  <a-camera
    look-controls="pointerLockEnabled:false;reverseMouseDrag:false;touchEnabled:true;magicWindowTrackingEnabled:true"
    wasd-controls="enabled:false"
    fov="80" near="0.1" user-height="0">
    <a-cursor fuse="false" color="#0ea5e9" opacity="0.45"
      radius-inner="0.004" radius-outer="0.006" position="0 0 -1">
    </a-cursor>
  </a-camera>
</a-scene>

<div id="overlay">
  <div id="hdr">
    <div class="logo">R</div>
    <div>
      <div class="prop-name">${safeTitle}</div>
      <div class="prop-sub">גרור / הטה מכשיר לסיבוב · נכס ${safePropId}</div>
    </div>
    <div class="badge">360° סיור</div>
  </div>

  <div id="loading">
    <div class="spin"></div>
    <div class="load-lbl">טוען סיור וירטואלי…</div>
  </div>

  <div id="toast">📱 הטה את המכשיר לסיבוב המבט &nbsp;·&nbsp; 🖱️ גרור לניווט</div>

  <div id="pgwrap"><div id="pg"><div id="pgbar"></div></div></div>

  <div id="ctrl">
    <button class="btn" id="btnPlay">
      <svg id="icPlay" width="20" height="20" viewBox="0 0 24 24" fill="#fff"><path d="M8 5v14l11-7z"/></svg>
      <svg id="icPause" width="20" height="20" viewBox="0 0 24 24" fill="#fff" hidden><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
    </button>
    <span id="timer">0:00 / 0:00</span>
    <button class="btn" id="btnMute">
      <svg id="icVol" width="20" height="20" viewBox="0 0 24 24" fill="#fff"><path d="M3 9v6h4l5 5V4L7 9H3zm13.5 3c0-1.77-1.02-3.29-2.5-4.03v8.05c1.48-.73 2.5-2.25 2.5-4.02zM14 3.23v2.06c2.89.86 5 3.54 5 6.71s-2.11 5.85-5 6.71v2.06c4.01-.91 7-4.49 7-8.77s-2.99-7.86-7-8.77z"/></svg>
      <svg id="icMute" width="20" height="20" viewBox="0 0 24 24" fill="#fff" hidden><path d="M16.5 12c0-1.77-1.02-3.29-2.5-4.03v2.21l2.45 2.45c.03-.2.05-.41.05-.63zm2.5 0c0 .94-.2 1.82-.54 2.64l1.51 1.51C20.63 14.91 21 13.5 21 12c0-4.28-2.99-7.86-7-8.77v2.06c2.89.86 5 3.54 5 6.71zM4.27 3L3 4.27 7.73 9H3v6h4l5 5v-6.73l4.25 4.25c-.67.52-1.42.93-2.25 1.18v2.06c1.38-.31 2.63-.95 3.69-1.81L19.73 21 21 19.73l-9-9L4.27 3zM12 4L9.91 6.09 12 8.18V4z"/></svg>
    </button>
    <button class="btn" id="btnFs">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="#fff"><path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z"/></svg>
    </button>
    <button class="btn btnw" id="btnVR">
      <svg width="16" height="16" viewBox="0 0 24 24" fill="#fff"><path d="M20.74 6H3.26C2.01 6 1 7.01 1 8.26v7.48C1 16.99 2.01 18 3.26 18h4.01c.63 0 1.21-.3 1.59-.8l1.84-2.45c.12-.16.31-.25.51-.25h1.59c.2 0 .39.09.51.25l1.84 2.45c.38.5.96.8 1.59.8h4.01C21.99 18 23 16.99 23 15.74V8.26C23 7.01 21.99 6 20.74 6zM7.5 15C5.57 15 4 13.43 4 11.5S5.57 8 7.5 8 11 9.57 11 11.5 9.43 15 7.5 15zm9 0c-1.93 0-3.5-1.57-3.5-3.5S14.57 8 16.5 8 20 9.57 20 11.5 18.43 15 16.5 15z"/></svg>
      VR
    </button>
  </div>
</div>

<script>
(function(){
  const tv=document.getElementById('tv');
  const loading=document.getElementById('loading');
  const toast=document.getElementById('toast');
  const pgbar=document.getElementById('pgbar');
  const pgwrap=document.getElementById('pgwrap');
  const timer=document.getElementById('timer');
  const btnPlay=document.getElementById('btnPlay');
  const icPlay=document.getElementById('icPlay');
  const icPause=document.getElementById('icPause');
  const btnMute=document.getElementById('btnMute');
  const icVol=document.getElementById('icVol');
  const icMuteEl=document.getElementById('icMute');
  const btnFs=document.getElementById('btnFs');
  const btnVR=document.getElementById('btnVR');

  const fmt=s=>{const m=Math.floor(s/60),sc=Math.floor(s%60);return m+':'+(sc<10?'0':'')+sc};

  // Hide loading when video is ready
  const hideLoad=()=>{loading.classList.add('gone');tv.play().catch(()=>{})};
  tv.addEventListener('canplay',hideLoad,{once:true});
  tv.addEventListener('loadeddata',hideLoad,{once:true});
  setTimeout(()=>loading.classList.add('gone'),7000);

  // Dismiss hint after 4 seconds
  setTimeout(()=>toast.classList.add('gone'),4000);

  // Progress bar
  tv.addEventListener('timeupdate',()=>{
    if(!tv.duration)return;
    pgbar.style.width=(tv.currentTime/tv.duration*100).toFixed(2)+'%';
    timer.textContent=fmt(tv.currentTime)+' / '+fmt(tv.duration);
  });
  pgwrap.addEventListener('click',e=>{
    const r=pgwrap.getBoundingClientRect();
    tv.currentTime=((e.clientX-r.left)/r.width)*tv.duration;
  });

  // Play / pause
  const syncPlay=()=>{icPlay.hidden=!tv.paused;icPause.hidden=tv.paused};
  tv.addEventListener('play',syncPlay);
  tv.addEventListener('pause',syncPlay);
  btnPlay.onclick=()=>tv.paused?tv.play():tv.pause();

  // Mute
  btnMute.onclick=()=>{
    tv.muted=!tv.muted;
    icVol.hidden=tv.muted;icMuteEl.hidden=!tv.muted;
  };

  // Fullscreen
  btnFs.onclick=()=>{
    if(document.fullscreenElement){document.exitFullscreen?.()}
    else{(document.documentElement.requestFullscreen||document.documentElement.webkitRequestFullscreen)?.call(document.documentElement)}
  };

  // VR button wires into A-Frame's built-in VR mode
  btnVR.onclick=()=>{
    const scene=document.querySelector('a-scene');
    if(scene){scene.enterVR?.()}
  };

  // iOS 13+ device orientation permission
  if(typeof DeviceOrientationEvent!=='undefined'&&
     typeof DeviceOrientationEvent.requestPermission==='function'){
    toast.textContent='📱 לחץ/י כדי לאפשר ניווט בהטיית מכשיר';
    toast.classList.remove('gone');
    toast.classList.add('tap');
    toast.onclick=()=>{
      DeviceOrientationEvent.requestPermission()
        .then(p=>{
          if(p==='granted'){
            toast.textContent='✅ ניווט פעיל — הטה את המכשיר!';
            setTimeout(()=>toast.classList.add('gone'),2500);
          }
          toast.classList.remove('tap');
          toast.onclick=null;
        }).catch(()=>{toast.classList.add('gone')});
    };
  }

  tv.play().catch(()=>{});
})();
<\/script>
</body>
</html>`;
}

function escapeHtml(value) {
  return String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}
