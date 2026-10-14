import { Body, Controller, Get, HttpCode, Module, Param, Patch, Post, Put, Query } from '@nestjs/common';
import { hash, verify } from '@node-rs/argon2';
import { z } from 'zod';
import { audit } from '../platform/audit.js';
import { AdminScope, Auth, ClientIp, RequireAdmin, assertShopScope, type AdminAuth } from '../platform/auth.js';
import { CryptoService } from '../platform/crypto.js';
import { Db, type Tx } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zUuid } from '../platform/validation.js';

/**
 * Usernames and passwords for Mukafaah Business. Mukafaah creates them in
 * Mukafaah Manager for each shop's owner and workers; nobody signs up alone.
 * Owners get the owner app (dashboard, offers, store, team); workers get the
 * counter (give and redeem points).
 */

export const zUsername = z
  .string()
  .trim()
  .toLowerCase()
  .regex(/^[a-z0-9][a-z0-9._-]{2,31}$/, 'Use 3 to 32 English letters, numbers, dot, dash or underscore');
export const zPassword = z.string().min(8, 'At least 8 characters').max(72);

const MAX_FAILURES = 5;
const LOCK_MINUTES = 15;
const ACCESS_TTL = '15m';
const REFRESH_TTL_DAYS = 30;
const STAFF_TOKEN_TTL = '12h';

export const zWorker = z.strictObject({
  name: z.string().trim().min(1).max(60),
  username: zUsername,
  password: zPassword,
  branchId: zUuid.optional(),
  canRedeem: z.boolean().optional(),
});
const zOwnerLogin = z.strictObject({ username: zUsername, password: zPassword.optional() });
const zLoginPatch = z.strictObject({
  username: zUsername.optional(),
  password: zPassword.optional(),
  active: z.boolean().optional(),
  name: z.string().trim().min(1).max(60).optional(),
  canRedeem: z.boolean().optional(),
});
const zLogin = z.strictObject({
  username: z.string().trim().min(1).max(64),
  password: z.string().min(1).max(200),
  deviceLabel: z.string().trim().max(60).optional(),
});

async function assertFree(c: Tx, username: string, exceptId?: string) {
  const r = await c.query(`SELECT id FROM business_logins WHERE lower(username) = lower($1) AND ($2::uuid IS NULL OR id <> $2)`, [
    username,
    exceptId ?? null,
  ]);
  if (r.rowCount) throw new AppError(409, 'USERNAME_TAKEN', 'This username is already used', { username });
}

/** Creates the owner's login for a shop (the owner user must already exist). */
export async function createOwnerLogin(c: Tx, x: { businessId: string; userId: string; username: string; password: string; by: string }) {
  await assertFree(c, x.username);
  await c.query(
    `INSERT INTO business_logins(business_id, kind, user_id, username, password_hash, created_by) VALUES ($1,'OWNER',$2,$3,$4,$5)`,
    [x.businessId, x.userId, x.username, await hash(x.password), x.by],
  );
}

/** Creates a worker (counter staff) with a login. Returns the new staff id. */
export async function createWorker(c: Tx, x: { businessId: string; branchId?: string; name: string; username: string; password: string; canRedeem?: boolean; by: string }) {
  await assertFree(c, x.username);
  const branchId =
    x.branchId ??
    (await c.query(`SELECT id FROM branches WHERE business_id = $1 ORDER BY created_at LIMIT 1`, [x.businessId])).rows[0]?.id;
  if (!branchId) throw Errors.notFound('Branch');
  const ok = (await c.query(`SELECT 1 FROM branches WHERE id = $1 AND business_id = $2`, [branchId, x.businessId])).rowCount;
  if (!ok) throw Errors.notFound('Branch');
  const staffId = (
    await c.query(`INSERT INTO staff(business_id, branch_id, name, can_redeem) VALUES ($1,$2,$3,$4) RETURNING id`, [
      x.businessId,
      branchId,
      x.name,
      x.canRedeem ?? true,
    ])
  ).rows[0].id as string;
  await c.query(
    `INSERT INTO business_logins(business_id, kind, staff_id, username, password_hash, created_by) VALUES ($1,'STAFF',$2,$3,$4,$5)`,
    [x.businessId, staffId, x.username, await hash(x.password), x.by],
  );
  return staffId;
}

/** Mukafaah Manager: the logins of one shop. Shop accounts can manage their own shop's workers. */
@Controller('v1/admin')
@RequireAdmin()
@AdminScope('SHOP')
export class AdminLoginsController {
  constructor(private readonly db: Db) {}

  private shop(a: AdminAuth, id: string) {
    const bid = parse(zUuid, id);
    assertShopScope(a, bid);
    return bid;
  }

  @Get('logins/check')
  async check(@Query() q: unknown) {
    const u = zUsername.safeParse((q as { username?: unknown } | null)?.username);
    if (!u.success) return { valid: false, available: false };
    const r = await this.db.one(`SELECT 1 FROM business_logins WHERE lower(username) = lower($1)`, [u.data]);
    return { valid: true, available: !r };
  }

  @Get('shops/:id/logins')
  async list(@Auth() a: AdminAuth, @Param('id') id: string) {
    const bid = this.shop(a, id);
    const [owner, workers, branches] = await Promise.all([
      this.db.one(
        `SELECT l.id, l.username, l.active, l.last_login_at, u.name, u.phone_last4
           FROM business_logins l JOIN users u ON u.id = l.user_id WHERE l.business_id = $1 AND l.kind = 'OWNER'`,
        [bid],
      ),
      this.db.query(
        `SELECT s.id AS staff_id, s.name, s.active AS staff_active, s.can_redeem, br.name AS branch_name, s.branch_id,
                l.id AS login_id, l.username, l.active AS login_active, l.last_login_at
           FROM staff s JOIN branches br ON br.id = s.branch_id
           LEFT JOIN business_logins l ON l.staff_id = s.id
          WHERE s.business_id = $1 ORDER BY s.created_at`,
        [bid],
      ),
      this.db.query(`SELECT id, name FROM branches WHERE business_id = $1 ORDER BY created_at`, [bid]),
    ]);
    const ownerUser = owner ? null : await this.db.one(`SELECT u.name, u.phone_last4 FROM businesses b JOIN users u ON u.id = b.owner_user_id WHERE b.id = $1`, [bid]);
    return {
      owner: owner
        ? { id: owner.id, username: owner.username, active: owner.active, lastLoginAt: owner.last_login_at, name: owner.name, phoneLast4: owner.phone_last4 }
        : null,
      ownerName: owner?.name ?? ownerUser?.name ?? null,
      workers: workers.rows.map((w) => ({
        staffId: w.staff_id,
        loginId: w.login_id ?? null,
        name: w.name,
        username: w.username ?? null,
        active: w.login_id ? w.login_active && w.staff_active : w.staff_active,
        canRedeem: w.can_redeem,
        branchId: w.branch_id,
        branchName: w.branch_name,
        lastLoginAt: w.last_login_at ?? null,
      })),
      branches: branches.rows.map((b) => ({ id: b.id, name: b.name })),
    };
  }

  /** Creates the owner's login, or changes its username / password. */
  @Put('shops/:id/logins/owner')
  async setOwner(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const bid = this.shop(a, id);
    const b = parse(zOwnerLogin, body);
    await this.db.tx(async (c) => {
      const cur = (await c.query(`SELECT id FROM business_logins WHERE business_id = $1 AND kind = 'OWNER' FOR UPDATE`, [bid])).rows[0];
      if (!cur) {
        if (!b.password) throw Errors.validation({ password: ['REQUIRED'] });
        const owner = (await c.query(`SELECT owner_user_id FROM businesses WHERE id = $1`, [bid])).rows[0];
        if (!owner) throw Errors.notFound('Shop');
        await createOwnerLogin(c, { businessId: bid, userId: owner.owner_user_id, username: b.username, password: b.password, by: a.userId });
      } else {
        await assertFree(c, b.username, cur.id);
        await c.query(
          `UPDATE business_logins SET username = $2, password_hash = COALESCE($3, password_hash), failures = 0, locked_until = NULL, updated_at = now() WHERE id = $1`,
          [cur.id, b.username, b.password ? await hash(b.password) : null],
        );
      }
      await audit(c, { actorType: 'USER', actorId: a.userId, businessId: bid, action: 'admin.login.owner', data: { username: b.username, newPassword: !!b.password }, ip });
    });
    return { ok: true };
  }

  @Post('shops/:id/logins/workers')
  async addWorker(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const bid = this.shop(a, id);
    const b = parse(zWorker, body);
    const staffId = await this.db.tx(async (c) => {
      const sid = await createWorker(c, { businessId: bid, ...b, by: a.userId });
      await audit(c, { actorType: 'USER', actorId: a.userId, businessId: bid, action: 'admin.login.worker.create', entityId: sid, data: { username: b.username }, ip });
      return sid;
    });
    return { staffId };
  }

  /** Changes a worker: password, username, name, redeem permission, or switch off. */
  @Patch('shops/:id/logins/workers/:staffId')
  async patchWorker(@Auth() a: AdminAuth, @Param('id') id: string, @Param('staffId') staffId: string, @Body() body: unknown, @ClientIp() ip: string) {
    const bid = this.shop(a, id);
    const sid = parse(zUuid, staffId);
    const b = parse(zLoginPatch, body);
    await this.db.tx(async (c) => {
      const s = (await c.query(`SELECT id FROM staff WHERE id = $1 AND business_id = $2 FOR UPDATE`, [sid, bid])).rows[0];
      if (!s) throw Errors.notFound('Worker');
      if (b.name !== undefined || b.canRedeem !== undefined || b.active !== undefined) {
        await c.query(`UPDATE staff SET name = COALESCE($2, name), can_redeem = COALESCE($3, can_redeem), active = COALESCE($4, active) WHERE id = $1`, [
          sid,
          b.name ?? null,
          b.canRedeem ?? null,
          b.active ?? null,
        ]);
      }
      const login = (await c.query(`SELECT id FROM business_logins WHERE staff_id = $1`, [sid])).rows[0];
      if (login) {
        if (b.username) await assertFree(c, b.username, login.id);
        await c.query(
          `UPDATE business_logins SET username = COALESCE($2, username), password_hash = COALESCE($3, password_hash),
                  active = COALESCE($4, active), failures = 0, locked_until = NULL, updated_at = now() WHERE id = $1`,
          [login.id, b.username ?? null, b.password ? await hash(b.password) : null, b.active ?? null],
        );
      } else if (b.username && b.password) {
        // An older counter worker (PIN only) gets a login.
        await assertFree(c, b.username);
        await c.query(
          `INSERT INTO business_logins(business_id, kind, staff_id, username, password_hash, created_by) VALUES ($1,'STAFF',$2,$3,$4,$5)`,
          [bid, sid, b.username, await hash(b.password), a.userId],
        );
      }
      // Switching a worker off also signs them out of every phone.
      if (b.active === false) {
        await c.query(`UPDATE devices SET status = 'REVOKED' WHERE business_id = $1 AND staff_id = $2`, [bid, sid]);
      }
      await audit(c, { actorType: 'USER', actorId: a.userId, businessId: bid, action: 'admin.login.worker.update', entityId: sid, data: { ...b, password: b.password ? 'changed' : undefined }, ip });
    });
    return { ok: true };
  }
}

/** Mukafaah Business sign-in with the username and password from Mukafaah. */
@Controller('v1/auth/business')
export class BusinessAuthController {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
  ) {}

  @Post('login')
  @HttpCode(200)
  async login(@Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zLogin, body);
    const wrong = new AppError(401, 'LOGIN_INVALID', 'Wrong username or password');
    const l = await this.db.one(
      `SELECT l.*, b.name AS business_name, b.status AS business_status
         FROM business_logins l JOIN businesses b ON b.id = l.business_id
        WHERE lower(l.username) = lower($1)`,
      [b.username.trim()],
    );
    if (!l) {
      // Same work as a real check so timing does not reveal which usernames exist.
      await hash(b.password).catch(() => undefined);
      throw wrong;
    }
    if (!l.active || l.business_status !== 'ACTIVE') throw new AppError(403, 'LOGIN_DISABLED', 'This account is switched off. Contact Mukafaah.');
    if (l.locked_until && new Date(l.locked_until) > new Date()) {
      throw new AppError(423, 'LOGIN_LOCKED', 'Too many wrong passwords. Try again in 15 minutes.');
    }
    const ok = await verify(l.password_hash, b.password).catch(() => false);
    if (!ok) {
      await this.db.query(
        `UPDATE business_logins SET failures = failures + 1,
                locked_until = CASE WHEN failures + 1 >= $2 THEN now() + make_interval(mins => $3) ELSE locked_until END
          WHERE id = $1`,
        [l.id, MAX_FAILURES, LOCK_MINUTES],
      );
      throw wrong;
    }
    return this.db.tx(async (c) => {
      await c.query(`UPDATE business_logins SET failures = 0, locked_until = NULL, last_login_at = now() WHERE id = $1`, [l.id]);
      if (l.kind === 'OWNER') {
        const user = (await c.query(`SELECT status FROM users WHERE id = $1`, [l.user_id])).rows[0];
        if (!user || user.status !== 'ACTIVE') throw Errors.forbidden();
        const refreshToken = this.crypto.randomToken(32);
        const s = (
          await c.query(
            `INSERT INTO sessions(user_id, family_id, refresh_hash, device_label, app, expires_at)
             VALUES ($1, uuidv7(), $2, $3, 'BUSINESS', now() + make_interval(days => $4)) RETURNING id`,
            [l.user_id, this.crypto.sha256(refreshToken), b.deviceLabel ?? 'Mukafaah Business', REFRESH_TTL_DAYS],
          )
        ).rows[0];
        const { token } = await this.crypto.sign('user', l.user_id, { sid: s.id, app: 'BUSINESS' }, ACCESS_TTL);
        await audit(c, { actorType: 'OWNER', actorId: l.user_id, businessId: l.business_id, action: 'auth.business.login', ip });
        return { kind: 'OWNER', accessToken: token, refreshToken, accessExpiresInSec: 900, businessName: l.business_name };
      }
      const st = (
        await c.query(
          `SELECT s.*, br.name AS branch_name FROM staff s JOIN branches br ON br.id = s.branch_id WHERE s.id = $1`,
          [l.staff_id],
        )
      ).rows[0];
      if (!st || !st.active) throw new AppError(403, 'LOGIN_DISABLED', 'This account is switched off. Contact Mukafaah.');
      // Each worker's phone is a counter device the owner can see and sign out.
      const label = `${(b.deviceLabel ?? 'Phone').slice(0, 30)} · ${st.name}`;
      let dev = (
        await c.query(`SELECT id FROM devices WHERE staff_id = $1 AND branch_id = $2 AND label = $3 AND status = 'ACTIVE'`, [st.id, st.branch_id, label])
      ).rows[0];
      if (!dev) {
        dev = (
          await c.query(`INSERT INTO devices(business_id, branch_id, label, secret_hash, staff_id) VALUES ($1,$2,$3,$4,$5) RETURNING id`, [
            st.business_id,
            st.branch_id,
            label,
            this.crypto.sha256(this.crypto.randomToken(32)),
            st.id,
          ])
        ).rows[0];
      }
      await c.query(`UPDATE devices SET last_seen_at = now() WHERE id = $1`, [dev.id]);
      const { token } = await this.crypto.sign('staff', st.id, { bid: st.business_id, brid: st.branch_id, dev: dev.id, role: 'CASHIER' }, STAFF_TOKEN_TTL);
      await audit(c, { actorType: 'STAFF', actorId: st.id, businessId: st.business_id, action: 'auth.business.login', ip });
      return {
        kind: 'STAFF',
        accessToken: token,
        expiresInSec: 12 * 3600,
        staff: { id: st.id, name: st.name, canRedeem: st.can_redeem },
        businessName: l.business_name,
        branchName: st.branch_name,
      };
    });
  }
}

@Module({ controllers: [AdminLoginsController, BusinessAuthController] })
export class LoginsModule {}
