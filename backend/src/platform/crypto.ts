import { Global, Injectable, Module, OnModuleInit } from '@nestjs/common';
import {
  createCipheriv,
  createDecipheriv,
  createHash,
  createHmac,
  randomBytes,
  randomInt,
  randomUUID,
  timingSafeEqual,
} from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import {
  exportJWK,
  generateKeyPair,
  importJWK,
  jwtVerify,
  SignJWT,
  type JWK,
  type JWTPayload,
} from 'jose';
import { parsePhoneNumberFromString } from 'libphonenumber-js/max';
import { config } from '../config.js';
import { Errors } from './errors.js';

interface KeyFile {
  kid: string;
  jwtPrivate: JWK;
  jwtPublic: JWK;
  phoneEncKey: string; // base64, 32 bytes
  phoneHashKey: string; // base64, 32 bytes
  otpPepper: string; // base64, 32 bytes
}

type JoseKey = Awaited<ReturnType<typeof importJWK>>;

/** pwset: a short-lived pass to choose a new password after a WhatsApp code. */
export type Audience = 'user' | 'staff' | 'qr' | 'pwset';

/**
 * Key material and crypto helpers. In development keys are generated once and
 * stored in KEYS_DIR (a Docker volume). In staging/production they come from
 * AWS Secrets Manager / KMS (wired in a later phase).
 */
@Injectable()
export class CryptoService implements OnModuleInit {
  private kid!: string;
  private priv!: JoseKey;
  private pub!: JoseKey;
  private encKey!: Buffer;
  private hashKey!: Buffer;
  private pepper!: Buffer;

  async onModuleInit() {
    const file = join(config.KEYS_DIR, 'keys.json');
    let k: KeyFile;
    try {
      const raw = config.KEYS_JSON.trim();
      k = raw
        ? (JSON.parse(raw.startsWith('{') ? raw : Buffer.from(raw, 'base64').toString('utf8')) as KeyFile)
        : (JSON.parse(await readFile(file, 'utf8')) as KeyFile);
    } catch {
      if (config.KEYS_JSON.trim()) throw new Error('KEYS_JSON is set but is not valid');
      if (config.NODE_ENV === 'production') throw new Error('Key file missing in production');
      const { privateKey, publicKey } = await generateKeyPair('ES256', { extractable: true });
      k = {
        kid: randomUUID(),
        jwtPrivate: await exportJWK(privateKey),
        jwtPublic: await exportJWK(publicKey),
        phoneEncKey: randomBytes(32).toString('base64'),
        phoneHashKey: randomBytes(32).toString('base64'),
        otpPepper: randomBytes(32).toString('base64'),
      };
      await mkdir(config.KEYS_DIR, { recursive: true });
      await writeFile(file, JSON.stringify(k), { mode: 0o600 });
    }
    this.kid = k.kid;
    this.priv = await importJWK(k.jwtPrivate, 'ES256');
    this.pub = await importJWK(k.jwtPublic, 'ES256');
    this.encKey = Buffer.from(k.phoneEncKey, 'base64');
    this.hashKey = Buffer.from(k.phoneHashKey, 'base64');
    this.pepper = Buffer.from(k.otpPepper, 'base64');
  }

  // ---------- JWT ----------
  async sign(aud: Audience, sub: string, claims: Record<string, unknown>, ttl: string) {
    const jti = randomUUID();
    const token = await new SignJWT(claims)
      .setProtectedHeader({ alg: 'ES256', kid: this.kid })
      .setIssuer('mukafaah')
      .setAudience(aud)
      .setSubject(sub)
      .setJti(jti)
      .setIssuedAt()
      .setExpirationTime(ttl)
      .sign(this.priv);
    return { token, jti };
  }

  async verify(aud: Audience, token: string): Promise<JWTPayload> {
    try {
      const { payload } = await jwtVerify(token, this.pub, { issuer: 'mukafaah', audience: aud, algorithms: ['ES256'] });
      return payload;
    } catch {
      throw Errors.unauthorized();
    }
  }

  // ---------- Phones ----------
  /** Normalise to E.164; throws if invalid or country not allowed. */
  normalizePhone(input: string, allowedOnly = true): string {
    const p = parsePhoneNumberFromString(String(input ?? '').trim(), config.DEFAULT_PHONE_REGION as never);
    if (!p || !p.isValid()) throw Errors.validation({ phone: ['INVALID_PHONE'] });
    const allowed = config.OTP_ALLOWED_COUNTRIES.split(',').map((s) => s.trim());
    if (allowedOnly && p.country && !allowed.includes(p.country)) {
      throw Errors.validation({ phone: ['COUNTRY_NOT_SUPPORTED'] });
    }
    return p.number;
  }

  phoneHash(e164: string): Buffer {
    return createHmac('sha256', this.hashKey).update(e164).digest();
  }

  encrypt(plain: string): Buffer {
    const iv = randomBytes(12);
    const c = createCipheriv('aes-256-gcm', this.encKey, iv);
    const body = Buffer.concat([c.update(plain, 'utf8'), c.final()]);
    return Buffer.concat([iv, c.getAuthTag(), body]);
  }

  decrypt(blob: Buffer): string {
    const iv = blob.subarray(0, 12);
    const tag = blob.subarray(12, 28);
    const d = createDecipheriv('aes-256-gcm', this.encKey, iv);
    d.setAuthTag(tag);
    return Buffer.concat([d.update(blob.subarray(28)), d.final()]).toString('utf8');
  }

  // ---------- Secrets ----------
  otpHash(challengeId: string, code: string): Buffer {
    return createHmac('sha256', this.pepper).update(`${challengeId}:${code}`).digest();
  }

  sha256(v: string): Buffer {
    return createHash('sha256').update(v).digest();
  }

  safeEqual(a: Buffer, b: Buffer) {
    return a.length === b.length && timingSafeEqual(a, b);
  }

  randomToken(bytes = 32) {
    return randomBytes(bytes).toString('base64url');
  }

  randomDigits(n: number) {
    let s = '';
    for (let i = 0; i < n; i++) s += String(randomInt(0, 10));
    return s;
  }

  /** Human-friendly code without ambiguous characters. */
  randomCode(n: number) {
    const alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
    let s = '';
    for (let i = 0; i < n; i++) s += alphabet[randomInt(0, alphabet.length)];
    return s;
  }
}

@Global()
@Module({ providers: [CryptoService], exports: [CryptoService] })
export class CryptoModule {}
