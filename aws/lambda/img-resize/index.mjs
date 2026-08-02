import Jimp from 'jimp';

// On-the-fly image thumbnailer behind CloudFront. CloudFront routes
// /thumb/<key>?w=N to this Lambda's Function URL; we fetch the PUBLIC original
// from S3, resize to width N (keep aspect, never upscale), and return a JPEG.
// CloudFront caches the result per (path,w) so each thumb is generated once.
const S3_HOST = 'rentch-media-543897290879.s3.us-east-1.amazonaws.com';
const MAX_W = 2048, MIN_W = 32, DEFAULT_W = 400;

export const handler = async (event) => {
  try {
    let path = (event.rawPath || '/').replace(/^\/+/, '');
    if (path.startsWith('thumb/')) path = path.slice(6);
    const key = decodeURIComponent(path);
    if (!key) return { statusCode: 400, body: 'missing key' };

    let w = parseInt(
      (event.queryStringParameters && event.queryStringParameters.w) || String(DEFAULT_W), 10);
    if (!Number.isFinite(w)) w = DEFAULT_W;
    w = Math.min(MAX_W, Math.max(MIN_W, w));

    const srcUrl = `https://${S3_HOST}/${key.split('/').map(encodeURIComponent).join('/')}`;
    const res = await fetch(srcUrl);
    if (!res.ok) return { statusCode: res.status === 404 ? 404 : 502, body: 'source fetch failed' };
    const buf = Buffer.from(await res.arrayBuffer());

    const img = await Jimp.read(buf);
    if (img.bitmap.width > w) img.resize(w, Jimp.AUTO);
    const out = await img.quality(78).getBufferAsync(Jimp.MIME_JPEG);

    return {
      statusCode: 200,
      headers: {
        'content-type': 'image/jpeg',
        'cache-control': 'public, max-age=31536000, immutable',
      },
      body: out.toString('base64'),
      isBase64Encoded: true,
    };
  } catch (e) {
    console.error('resize error:', e);
    return { statusCode: 502, body: 'resize failed' };
  }
};
