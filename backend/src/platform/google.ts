import { createPublicKey, verify, type KeyObject } from 'node:crypto';
import { config } from '../config.js';
import { AppError } from './errors.js';

/** What Mukafaah keeps from a verified Google sign-in. */
export interface GoogleIdentity {
  sub: string;
  email: string;
  givenName: string | null;
  name: string | null;
}

const CERTS_URL = 'https://www.googleapis.com/oauth2/v3/certs';
const ISSUERS = new Set(['accounts.google.com', 'https://accounts.google.com']);

let keys = new Map<string, KeyObject>();
let keysUntil = 0;

async function loadKeys(force = false): Promise<Map<string, KeyObject>> {
  if (!force && Date.now() < keysUntil && keys.size) return keys;
  const res = await fetch(CERTS_URL);
  if (!res.ok) throw new AppError(503, 'GOOGLE_UNAVAILABLE', 'Google sign-in is not reachable right now');
  const body = (await res.json()) as { keys: Array<{ kid: string } & Record<string, unknown>> };
  const next = new Map<string, KeyObject>();
  for (const k of body.keys) next.set(k.kid, createPublicKey({ key: k as never, format: 'jwk' }));
  const maxAge = /max-age=(\d+)/.exec(res.headers.get('cache-control') ?? '')?.[1];
  keys = next;
  keysUntil = Date.now() + Math.min(Number(maxAge ?? 3600), 6 * 3600) * 1000;
  return keys;
}

const b64url = (s: string) => Buffer.from(s.replace(/-/g, '+').replace(/_/g, '/'), 'base64');

/**
 * Checks a Google ID token the app received from Google sign-in: RS256
 * signature against Google's published keys, issuer, audience (our client
 * IDs), expiry and a verified Gmail address. No password ever reaches us.
 */
export async function verifyGoogleIdToken(idToken: string): Promise<GoogleIdentity> {
  const audiences = config.GOOGLE_CLIENT_IDS.split(',').map((x) => x.trim()).filter(Boolean);
  if (!audiences.length) throw new AppError(503, 'GOOGLE_NOT_CONFIGURED', 'Google sign-in is not set up yet');
  const bad = new AppError(401, 'GOOGLE_TOKEN_INVALID', 'Google sign-in could not be verified');

  const parts = idToken.split('.');
  if (parts.length !== 3) throw bad;
  let header: { alg?: string; kid?: string };
  let claims: Record<string, unknown>;
  try {
    header = JSON.parse(b64url(parts[0]).toString('utf8'));
    claims = JSON.parse(b64url(parts[1]).toString('utf8'));
  } catch {
    throw bad;
  }
  if (header.alg !== 'RS256' || !header.kid) throw bad;
  let key = (await loadKeys()).get(header.kid);
  if (!key) key = (await loadKeys(true)).get(header.kid);
  if (!key) throw bad;
  const ok = verify('RSA-SHA256', Buffer.from(`${parts[0]}.${parts[1]}`), key, b64url(parts[2]));
  if (!ok) throw bad;

  const now = Math.floor(Date.now() / 1000);
  const aud = claims.aud;
  const audOk = Array.isArray(aud) ? aud.some((a) => audiences.includes(String(a))) : audiences.includes(String(aud));
  if (!ISSUERS.has(String(claims.iss)) || !audOk) throw bad;
  if (typeof claims.exp !== 'number' || claims.exp < now - 60) throw bad;
  if (typeof claims.iat === 'number' && claims.iat > now + 300) throw bad;
  if (typeof claims.sub !== 'string' || typeof claims.email !== 'string') throw bad;
  if (claims.email_verified !== true && claims.email_verified !== 'true') {
    throw new AppError(401, 'GOOGLE_EMAIL_UNVERIFIED', 'Verify your Google email address first');
  }
  return {
    sub: claims.sub,
    email: claims.email.toLowerCase(),
    givenName: typeof claims.given_name === 'string' ? claims.given_name : null,
    name: typeof claims.name === 'string' ? claims.name : null,
  };
}
