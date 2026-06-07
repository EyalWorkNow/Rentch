// Firebase ID-token authorizer for API Gateway (REST, TOKEN type).
//
// Verifies a Firebase JWT with ZERO external dependencies using Node's built-in
// crypto + https. Caches Google's x509 signing certs until their max-age.
//
// Env:
//   FIREBASE_PROJECT_ID  e.g. mydatingapp-4c043
//
// Returns an IAM policy. On success, the verified `uid` is passed downstream
// via context.uid (readable in the router Lambda as event.requestContext.authorizer.uid).

import crypto from 'node:crypto';
import https from 'node:https';

const PROJECT_ID = process.env.FIREBASE_PROJECT_ID;
const CERT_URL =
  'https://www.googleapis.com/robot/v1/metadata/x509/securetoken@system.gserviceaccount.com';
const ISSUER = `https://securetoken.google.com/${PROJECT_ID}`;

let certCache = null; // { certs: {kid: pem}, expiresAt: epochMs }

function fetchCerts() {
  return new Promise((resolve, reject) => {
    https
      .get(CERT_URL, (res) => {
        let body = '';
        res.on('data', (c) => (body += c));
        res.on('end', () => {
          try {
            const certs = JSON.parse(body);
            // Honor Cache-Control max-age
            const cc = res.headers['cache-control'] || '';
            const m = cc.match(/max-age=(\d+)/);
            const ttl = m ? parseInt(m[1], 10) * 1000 : 3600 * 1000;
            certCache = { certs, expiresAt: Date.now() + ttl };
            resolve(certs);
          } catch (e) {
            reject(e);
          }
        });
      })
      .on('error', reject);
  });
}

async function getCerts() {
  if (certCache && certCache.expiresAt > Date.now()) return certCache.certs;
  return fetchCerts();
}

function b64urlDecode(str) {
  return Buffer.from(str.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}

function b64urlJson(str) {
  return JSON.parse(b64urlDecode(str).toString('utf8'));
}

async function verifyFirebaseToken(token) {
  const parts = token.split('.');
  if (parts.length !== 3) throw new Error('Malformed JWT');
  const [headerB64, payloadB64, sigB64] = parts;

  const header = b64urlJson(headerB64);
  const payload = b64urlJson(payloadB64);

  if (header.alg !== 'RS256') throw new Error('Unexpected alg');
  if (!header.kid) throw new Error('Missing kid');

  // Claim checks
  const now = Math.floor(Date.now() / 1000);
  if (payload.exp <= now) throw new Error('Token expired');
  if (payload.iat > now + 300) throw new Error('Token issued in the future');
  if (payload.aud !== PROJECT_ID) throw new Error('Bad audience');
  if (payload.iss !== ISSUER) throw new Error('Bad issuer');
  if (!payload.sub) throw new Error('Missing sub');

  // Signature check against Google's cert for this kid
  const certs = await getCerts();
  const pem = certs[header.kid];
  if (!pem) throw new Error('No matching cert for kid');

  const verifier = crypto.createVerify('RSA-SHA256');
  verifier.update(`${headerB64}.${payloadB64}`);
  verifier.end();
  const ok = verifier.verify(pem, b64urlDecode(sigB64));
  if (!ok) throw new Error('Invalid signature');

  return payload.sub; // Firebase UID
}

function policy(effect, resource, uid) {
  const doc = {
    principalId: uid || 'unknown',
    policyDocument: {
      Version: '2012-10-17',
      Statement: [
        { Action: 'execute-api:Invoke', Effect: effect, Resource: resource },
      ],
    },
  };
  if (uid) doc.context = { uid };
  return doc;
}

export const handler = async (event) => {
  // Allow CORS preflight without a token
  const raw = event.authorizationToken || '';
  const token = raw.startsWith('Bearer ') ? raw.slice(7) : raw;

  // Wildcard the resource so the cached policy works across methods/paths.
  const arnParts = (event.methodArn || '').split('/');
  const wildcard = arnParts.length >= 2 ? `${arnParts[0]}/${arnParts[1]}/*` : event.methodArn;

  if (!token) {
    // Returning Deny lets API Gateway respond 401.
    throw new Error('Unauthorized');
  }

  try {
    const uid = await verifyFirebaseToken(token);
    return policy('Allow', wildcard, uid);
  } catch (e) {
    console.log('Auth failed:', e.message);
    throw new Error('Unauthorized');
  }
};
