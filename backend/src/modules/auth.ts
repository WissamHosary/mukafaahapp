import { randomUUID } from 'node:crypto';
import { Body, Controller, HttpCode, Inject, Module, Post } from '@nestjs/common';
import { z } from 'zod';
import { config } from '../config.js';
import { audit } from '../platform/audit.js';
import { Auth, ClientIp, RequireUser, type UserAuth } from '../platform/auth.js';
import { CryptoService } from '../platform/crypto.js';
import { Db, type Tx } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse } from '../platform/validation.js';
import { LedgerService } from './ledger.js';
import { grantRule } from './mukafaah.js';
import { ConsoleOtpProvider, OTP_PROVIDER, type OtpProvider } from './otp-provider.js';

const OTP_TTL_SEC = 300;
const OTP_MAX_ATTEMPTS = 5;
const OTP_MAX_PER_PHONE_HOUR = 5;
const OTP_MAX_PER_PHONE_DAY = 10;
const OTP_MAX_PER_IP_HOUR = 20;
const OTP_MAX_PER_DEVICE_HOUR = 10;
const ACCESS_TTL = '15m';
const REFRESH_TTL_DAYS = 30;

const zApp = z.enum(['CUSTOMER', 'BUSINESS', 'ADMIN']);

const zRequest = z.strictObject({
  phone: z.string().min(6).max(20),
  app: zApp,
  deviceId: z.string().min(8).max(100).optional(),
  locale: z.enum(['ar', 'en']).default('ar'),
});
const zVerify = z.strictObject({
  challengeId: z.uuid(),
  code: z.string().regex(/^\d{6}$/),
  app: zApp,
  deviceLabel: z.string().max(80).optional(),
});
const zRefresh = z.strictObject({ refreshToken: z.string().min(20).max(200) });

@Controller('v1/auth')
export class AuthController {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
    @Inject(OTP_PROVIDER) private readonly otp: OtpProvider,
    private readonly ledger: LedgerService,
  ) {}

  @Post('otp/request')
  @HttpCode(200)
  async request(@Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zRequest, body);
    const phone = this.crypto.normalizePhone(b.phone);
    const ph = this.crypto.phoneHash(phone);

    const stats = await this.db.one(
      `SELECT
         count(*) FILTER (WHERE created_at > now() - interval '1 hour')::int AS hour,
         count(*) FILTER (WHERE created_at > now() - interval '1 day')::int AS day,
         EXTRACT(EPOCH FROM now() - max(created_at))::int AS since_last
       FROM otp_challenges WHERE phone_hash = $1`,
      [ph],
    );
    const hour = stats?.hour ?? 0;
    if (hour >= OTP_MAX_PER_PHONE_HOUR || (stats?.day ?? 0) >= OTP_MAX_PER_PHONE_DAY) {
      throw Errors.tooMany('OTP_LIMIT_PHONE');
    }
    // Resend cooldown grows with each request: 30s, 60s, 120s, 240s...
    const cooldown = hour === 0 ? 0 : Math.min(30 * 2 ** (hour - 1), 600);
    if (stats?.since_last != null && stats.since_last < cooldown) {
      throw Errors.tooMany('OTP_COOLDOWN', cooldown - stats.since_last);
    }
    const ipCount = await this.db.one(
      `SELECT count(*)::int AS n FROM otp_challenges WHERE ip = $1 AND created_at > now() - interval '1 hour'`,
      [ip],
    );
    if ((ipCount?.n ?? 0) >= OTP_MAX_PER_IP_HOUR) throw Errors.tooMany('OTP_LIMIT_IP');
    if (b.deviceId) {
      const dc = await this.db.one(
        `SELECT count(*)::int AS n FROM otp_challenges WHERE device_id = $1 AND created_at > now() - interval '1 hour'`,
        [b.deviceId],
      );
      if ((dc?.n ?? 0) >= OTP_MAX_PER_DEVICE_HOUR) throw Errors.tooMany('OTP_LIMIT_DEVICE');
    }

    const code = this.crypto.randomDigits(6);
    const challengeId = randomUUID();
    await this.db.query(
      `INSERT INTO otp_challenges(id, phone_hash, phone_enc, phone_last4, code_hash, ip, device_id, expires_at)
       VALUES ($1, $2, $3, $4, $5, $6, $7, now() + make_interval(secs => $8))`,
      [challengeId, ph, this.crypto.encrypt(phone), phone.slice(-4), this.crypto.otpHash(challengeId, code), ip, b.deviceId ?? null, OTP_TTL_SEC],
    );
    await this.otp.send(phone, code, b.locale);

    const nextCooldown = Math.min(30 * 2 ** hour, 600);
    return {
      challengeId,
      expiresInSec: OTP_TTL_SEC,
      resendInSec: nextCooldown,
      ...(config.OTP_DEV_ECHO ? { devCode: code } : {}),
    };
  }

  @Post('otp/verify')
  @HttpCode(200)
  async verify(@Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zVerify, body);
    const out = await this.db.tx(async (c) => {
      const r = await c.query(`SELECT * FROM otp_challenges WHERE id = $1 FOR UPDATE`, [b.challengeId]);
      const ch = r.rows[0];
      const invalid = new AppError(400, 'OTP_INVALID', 'Code is wrong or expired');
      if (!ch || ch.consumed_at || new Date(ch.expires_at) < new Date()) throw invalid;
      if (ch.attempts >= OTP_MAX_ATTEMPTS) throw new AppError(429, 'OTP_TOO_MANY_ATTEMPTS');
      const ok = this.crypto.safeEqual(this.crypto.otpHash(ch.id, b.code), ch.code_hash);
      if (!ok) {
        // Commit the failed attempt (no throw inside the transaction), then reject.
        await c.query(`UPDATE otp_challenges SET attempts = attempts + 1 WHERE id = $1`, [ch.id]);
        return null;
      }
      await c.query(`UPDATE otp_challenges SET consumed_at = now(), attempts = attempts + 1 WHERE id = $1`, [ch.id]);

      let user = (await c.query(`SELECT * FROM users WHERE phone_hash = $1`, [ch.phone_hash])).rows[0];
      let isNew = false;
      if (!user) {
        user = (
          await c.query(
            `INSERT INTO users(phone_hash, phone_enc, phone_last4) VALUES ($1,$2,$3) RETURNING *`,
            [ch.phone_hash, ch.phone_enc, ch.phone_last4],
          )
        ).rows[0];
        isNew = true;
      }
      if (user.status !== 'ACTIVE') throw Errors.forbidden();
      // Mukafaah Points for joining (once per user).
      if (isNew) await grantRule(c, this.ledger, 'SIGNUP', user.id);
      // Phones listed in ADMIN_PHONES become Mukafaah Manager admins on first sign-in.
      const adminPhones = config.ADMIN_PHONES.split(',').map((x) => x.trim()).filter(Boolean);
      if (adminPhones.length) {
        const phone = this.crypto.decrypt(user.phone_enc);
        const listed = adminPhones.some((x) => {
          try {
            return this.crypto.normalizePhone(x, false) === phone;
          } catch {
            return false;
          }
        });
        if (listed) {
          await c.query(`INSERT INTO admins(user_id, role) VALUES ($1, 'OWNER') ON CONFLICT (user_id) DO NOTHING`, [user.id]);
        }
      }
      if (b.app === 'ADMIN' && config.OTP_DEV_ECHO) {
        // Development only: the first person to sign in to the Manager becomes its owner.
        const none = (await c.query(`SELECT count(*)::int AS n FROM admins`)).rows[0].n === 0;
        if (none) await c.query(`INSERT INTO admins(user_id, role) VALUES ($1, 'OWNER')`, [user.id]);
      }
      if (b.app === 'ADMIN') {
        const adm = (await c.query(`SELECT 1 FROM admins WHERE user_id = $1 AND active`, [user.id])).rows[0];
        if (!adm) throw new AppError(403, 'NOT_ADMIN', 'This number is not a Mukafaah Manager admin');
      }
      const tokens = await this.createSession(c, user.id, b.app, b.deviceLabel ?? null, null);
      await audit(c, { actorType: 'USER', actorId: user.id, action: 'auth.login', data: { app: b.app }, ip });
      return { ...tokens, isNew, user: { id: user.id, name: user.name, phoneLast4: user.phone_last4 } };
    });
    if (!out) throw new AppError(400, 'OTP_INVALID', 'Code is wrong or expired');
    return out;
  }

  @Post('refresh')
  @HttpCode(200)
  async refresh(@Body() body: unknown) {
    const b = parse(zRefresh, body);
    const hash = this.crypto.sha256(b.refreshToken);
    return this.db.tx(async (c) => {
      const s = (await c.query(`SELECT * FROM sessions WHERE refresh_hash = $1 FOR UPDATE`, [hash])).rows[0];
      if (!s) throw Errors.unauthorized();
      if (s.rotated_at || s.revoked_at) {
        // Reuse of an already-rotated token: assume theft, revoke the whole family.
        await c.query(`UPDATE sessions SET revoked_at = now() WHERE family_id = $1 AND revoked_at IS NULL`, [s.family_id]);
        throw Errors.unauthorized();
      }
      if (new Date(s.expires_at) < new Date()) throw Errors.unauthorized();
      await c.query(`UPDATE sessions SET rotated_at = now(), revoked_at = now() WHERE id = $1`, [s.id]);
      return this.createSession(c, s.user_id, s.app, s.device_label, s.family_id);
    });
  }

  @Post('logout')
  @HttpCode(200)
  @RequireUser()
  async logout(@Auth() auth: UserAuth) {
    await this.db.query(`UPDATE sessions SET revoked_at = now() WHERE id = $1`, [auth.sessionId]);
    return { ok: true };
  }

  @Post('logout-all')
  @HttpCode(200)
  @RequireUser()
  async logoutAll(@Auth() auth: UserAuth) {
    await this.db.query(`UPDATE sessions SET revoked_at = now() WHERE user_id = $1 AND revoked_at IS NULL`, [auth.userId]);
    return { ok: true };
  }

  private async createSession(c: Tx, userId: string, app: string, label: string | null, familyId: string | null) {
    const refreshToken = this.crypto.randomToken(32);
    const s = (
      await c.query(
        `INSERT INTO sessions(user_id, family_id, refresh_hash, device_label, app, expires_at)
         VALUES ($1, COALESCE($2::uuid, uuidv7()), $3, $4, $5, now() + make_interval(days => $6)) RETURNING id`,
        [userId, familyId, this.crypto.sha256(refreshToken), label, app, REFRESH_TTL_DAYS],
      )
    ).rows[0];
    const { token } = await this.crypto.sign('user', userId, { sid: s.id, app }, ACCESS_TTL);
    return { accessToken: token, refreshToken, accessExpiresInSec: 900 };
  }
}

@Module({
  controllers: [AuthController],
  providers: [{ provide: OTP_PROVIDER, useClass: ConsoleOtpProvider }],
})
export class AuthModule {}
