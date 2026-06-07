// WebSocket REQUEST authorizer — verifies the Firebase ID token passed as the
// `token` query-string param on $connect. Zero dependencies (Node crypto+https).

import crypto from 'node:crypto';
import https from 'node:https';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID;
const CERT_URL =
  'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
const ISSUER = `https://securetoken.google.com/${PROJECT_ID}`;

let certCache = null;

function fetchCerts() {
  return new Promise((resolve, reject) => {
    https.get(CERT_URL, (res) => {
      let body = '';
      res.on('data', (c) => (body += c));
      res.on('end', () => {
        try {
          const certs = JSON.parse(body);
          const cc = res.headers['cache-control'] || '';
          const m = cc.match(/max-age=(\d+)/);
          const ttl = m ? parseInt(m[1], 10) * 1000 : 3600 * 1000;
          certCache = { certs, expiresAt: Date.now() + ttl };
          resolve(certs);
        } catch (e) { reject(e); }
      });
    }).on('error', reject);
  });
}

async function getCerts() {
  if (certCache && certCache.expiresAt > Date.now()) return certCache.certs;
  return fetchCerts();
}

const b64 = (s) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
const b64json = (s) => JSON.parse(b64(s).toString('utf8'));

async function verify(token) {
  const [h, p, sig] = token.split('.');
  if (!h || !p || !sig) throw new Error('Malformed');
  const header = b64json(h);
  const payload = b64json(p);
  const now = Math.floor(Date.now() / 1000);
  if (header.alg !== 'RS256' || !header.kid) throw new Error('Bad header');
  if (payload.exp <= now) throw new Error('Expired');
  if (payload.aud !== PROJECT_ID) throw new Error('Bad aud');
  if (payload.iss !== ISSUER) throw new Error('Bad iss');
  if (!payload.sub) throw new Error('No sub');
  const certs = await getCerts();
  const pem = certs[header.kid];
  if (!pem) throw new Error('No cert');
  const v = crypto.createVerify('RSA-SHA256');
  v.update(`${h}.${p}`); v.end();
  if (!v.verify(pem, b64(sig))) throw new Error('Bad signature');
  return payload.sub;
}

export const handler = async (event) => {
  const token = event.queryStringParameters?.token || '';
  if (!token) throw new Error('Unauthorized');
  try {
    const uid = await verify(token);
    return {
      principalId: uid,
      policyDocument: {
        Version: '2012-10-17',
        Statement: [{
          Action: 'execute-api:Invoke',
          Effect: 'Allow',
          Resource: event.methodArn,
        }],
      },
      context: { uid },
    };
  } catch (e) {
    console.log('WS auth failed:', e.message);
    throw new Error('Unauthorized');
  }
};
