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

const ddb = DynamoDBDocumentClient.from(new DynamoDBClient({ region: REGION }), {
  marshallOptions: { removeUndefinedValues: true },
});
const s3 = new S3Client({ region: REGION });

// Path segment → DynamoDB table name. Also defines the partition-key attribute
// and an optional GSI used for list queries.
const TABLES = {
  properties:      { name: `${TABLE_PREFIX}properties`,      gsi: { name: 'status-createdAt',     pk: 'status',         filterKey: 'status' } },
  messages:        { name: `${TABLE_PREFIX}messages`,        gsi: { name: 'matchId-createdAt',    pk: 'matchId',        filterKey: 'matchId' } },
  users:           { name: `${TABLE_PREFIX}users`,           gsi: { name: 'discoverable-updatedAt', pk: 'discoverable', filterKey: 'discoverable' } },
  events:          { name: `${TABLE_PREFIX}events`,          gsi: null },
  reports:         { name: `${TABLE_PREFIX}reports`,         gsi: null },
  blocks:          { name: `${TABLE_PREFIX}blocks`,          gsi: null },
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

async function createScan(event) {
  const body = event.body ? JSON.parse(event.body) : {};
  const propertyId = sanitizeId(body.propertyId || body.id || 'prop');
  const contentType = body.contentType || 'video/mp4';
  const ts = Date.now();
  const rand = Math.random().toString(36).slice(2, 10);
  const scanId = `sc_${ts}_${rand}`;
  const ext = contentType.includes('quicktime') ? 'mov'
    : contentType.includes('m4v') ? 'm4v'
    : contentType.includes('webm') ? 'webm'
    : 'mp4';
  const videoKey = `3d-scans/${propertyId}/${scanId}.${ext}`;

  const uploadUrl = await getSignedUrl(
    s3,
    new PutObjectCommand({ Bucket: S3_BUCKET, Key: videoKey, ContentType: contentType }),
    { expiresIn: 3600 },
  );

  const meta = { scanId, propertyId, videoKey, contentType, status: 'pending', createdAt: ts };
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: `3d-scans/meta/${scanId}.json`,
    Body: JSON.stringify(meta),
    ContentType: 'application/json',
  }));

  return json(200, { data: { scanId, uploadUrl } });
}

async function processScan(scanId) {
  let meta;
  try {
    const obj = await s3.send(new GetObjectCommand({
      Bucket: S3_BUCKET,
      Key: `3d-scans/meta/${scanId}.json`,
    }));
    meta = JSON.parse(await streamToString(obj.Body));
  } catch {
    return json(404, { message: 'Scan not found' });
  }

  const videoUrl = `https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/${meta.videoKey}`;
  const html = renderVideoViewerHtml({
    title: 'Rentch Virtual Tour',
    videoUrl,
    propertyId: meta.propertyId,
  });
  const viewerKey = `3d-viewers/${meta.propertyId}/${scanId}-viewer.html`;
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: viewerKey,
    Body: html,
    ContentType: 'text/html; charset=utf-8',
    CacheControl: 'public, max-age=3600',
  }));

  const viewerUrl = `https://${S3_BUCKET}.s3.${REGION}.amazonaws.com/${viewerKey}`;
  const updated = { ...meta, status: 'ready', viewerUrl, videoUrl, processedAt: Date.now() };
  await s3.send(new PutObjectCommand({
    Bucket: S3_BUCKET,
    Key: `3d-scans/meta/${scanId}.json`,
    Body: JSON.stringify(updated),
    ContentType: 'application/json',
  }));

  return json(200, {
    data: {
      id: scanId,
      scanId,
      status: 'ready',
      viewerUrl,
      downloadUrl: videoUrl,
      format: 'video',
    },
  });
}

async function getScan(scanId) {
  let meta;
  try {
    const obj = await s3.send(new GetObjectCommand({
      Bucket: S3_BUCKET,
      Key: `3d-scans/meta/${scanId}.json`,
    }));
    meta = JSON.parse(await streamToString(obj.Body));
  } catch {
    return json(404, { message: 'Scan not found' });
  }
  return json(200, {
    id: scanId,
    status: meta.status || 'pending',
    viewerUrl: meta.viewerUrl || '',
    downloadUrl: meta.videoUrl || '',
    format: 'video',
  });
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
  <meta name="viewport" content="width=device-width,initial-scale=1,viewport-fit=cover"/>
  <title>${safeTitle}</title>
  <style>
    *{box-sizing:border-box;margin:0;padding:0}
    html,body{height:100%;background:#07111c;color:#f5f7fb;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;overflow:hidden}
    #wrap{position:relative;height:100%;display:flex;flex-direction:column}
    header{position:absolute;top:0;left:0;right:0;z-index:10;padding:env(safe-area-inset-top,16px) 18px 12px;
      background:linear-gradient(to bottom,rgba(7,17,28,.85) 0%,transparent 100%);
      display:flex;align-items:center;gap:12px}
    .logo{width:32px;height:32px;background:linear-gradient(135deg,#0ea5e9,#1d4ed8);border-radius:8px;
      display:flex;align-items:center;justify-content:center;font-weight:900;font-size:14px;color:#fff;flex-shrink:0}
    h1{font-size:16px;font-weight:700;letter-spacing:-.2px}
    .sub{font-size:12px;color:rgba(245,247,251,.55)}
    video{width:100%;height:100%;object-fit:contain;background:#000}
    #controls{position:absolute;bottom:0;left:0;right:0;z-index:10;
      padding:12px 18px calc(env(safe-area-inset-bottom,12px) + 12px);
      background:linear-gradient(to top,rgba(7,17,28,.85) 0%,transparent 100%)}
    #progress{width:100%;height:3px;background:rgba(255,255,255,.2);border-radius:2px;margin-bottom:10px;cursor:pointer}
    #bar{height:100%;background:#0ea5e9;border-radius:2px;width:0;transition:width .1s linear}
    .btns{display:flex;align-items:center;gap:14px}
    button{background:none;border:none;color:#fff;cursor:pointer;padding:4px;opacity:.9}
    button:hover{opacity:1}
    svg{display:block}
    #time{font-size:12px;color:rgba(245,247,251,.65);margin-right:auto}
    #badge{background:rgba(14,165,233,.18);border:1px solid rgba(14,165,233,.35);
      color:#7dd3fc;font-size:11px;font-weight:600;letter-spacing:.4px;
      padding:3px 8px;border-radius:20px;white-space:nowrap}
  </style>
</head>
<body>
<div id="wrap">
  <header>
    <div class="logo">R</div>
    <div><h1>${safeTitle}</h1><div class="sub">נכס #${safePropId}</div></div>
    <div id="badge">סיור וירטואלי</div>
  </header>
  <video id="v" src="${safeVideoUrl}" playsinline preload="metadata"></video>
  <div id="controls">
    <div id="progress"><div id="bar"></div></div>
    <div class="btns">
      <button id="btnPlay" title="נגן/עצור">
        <svg id="iconPlay" width="28" height="28" viewBox="0 0 24 24" fill="currentColor"><path d="M8 5v14l11-7z"/></svg>
        <svg id="iconPause" width="28" height="28" viewBox="0 0 24 24" fill="currentColor" hidden><path d="M6 19h4V5H6v14zm8-14v14h4V5h-4z"/></svg>
      </button>
      <span id="time">0:00 / 0:00</span>
      <button id="btnFs" title="מסך מלא">
        <svg width="22" height="22" viewBox="0 0 24 24" fill="currentColor"><path d="M7 14H5v5h5v-2H7v-3zm-2-4h2V7h3V5H5v5zm12 7h-3v2h5v-5h-2v3zM14 5v2h3v3h2V5h-5z"/></svg>
      </button>
    </div>
  </div>
</div>
<script>
  const v=document.getElementById('v'),bar=document.getElementById('bar'),
    btnPlay=document.getElementById('btnPlay'),iconPlay=document.getElementById('iconPlay'),
    iconPause=document.getElementById('iconPause'),timeEl=document.getElementById('time'),
    progress=document.getElementById('progress'),btnFs=document.getElementById('btnFs');
  const fmt=s=>{const m=Math.floor(s/60),sec=Math.floor(s%60);return m+':'+(sec<10?'0':'')+sec};
  v.addEventListener('timeupdate',()=>{
    if(!v.duration)return;
    bar.style.width=(v.currentTime/v.duration*100)+'%';
    timeEl.textContent=fmt(v.currentTime)+' / '+fmt(v.duration);
  });
  v.addEventListener('play',()=>{iconPlay.hidden=true;iconPause.hidden=false});
  v.addEventListener('pause',()=>{iconPlay.hidden=false;iconPause.hidden=true});
  btnPlay.onclick=()=>v.paused?v.play():v.pause();
  progress.onclick=e=>{const r=progress.getBoundingClientRect();v.currentTime=(e.clientX-r.left)/r.width*v.duration};
  btnFs.onclick=()=>document.fullscreenElement?document.exitFullscreen():document.documentElement.requestFullscreen();
  v.play().catch(()=>{});
</script>
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
