import { Body, Controller, Delete, Get, HttpCode, Module, Patch, Post, Query } from '@nestjs/common';
import { z } from 'zod';
import { audit } from '../platform/audit.js';
import { Auth, IdemKey, RequireUser, type UserAuth } from '../platform/auth.js';
import { CryptoService } from '../platform/crypto.js';
import { Db } from '../platform/db.js';
import { AppError } from '../platform/errors.js';
import { parse } from '../platform/validation.js';
import { applyReferral } from './engage.js';
import { LedgerService } from './ledger.js';
import { mukafaahBalance } from './mukafaah.js';
import { saveImage } from './media.js';
import { MEMBER_QR_PREFIX, mediaUrl, memberCode, prettyPhone } from './shared.js';

/** Older rotating QR tokens (still accepted at the counter). */
export const QR_PREFIX = 'MKF1:';

const zProfile = z.strictObject({
  name: z.string().trim().min(1).max(60).optional(),
  locale: z.enum(['ar', 'en']).optional(),
});
const zComplete = z.strictObject({
  name: z.string().trim().min(2).max(60),
  age: z.number().int().min(13).max(100).optional(),
  gender: z.enum(['MALE', 'FEMALE']).optional(),
  referralCode: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{5,10}$/).optional(),
  locale: z.enum(['ar', 'en']).optional(),
});
const zPage = z.object({ limit: z.coerce.number().int().min(1).max(100).default(30) });

@Controller('v1/customer')
@RequireUser()
export class CustomerController {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
    private readonly ledger: LedgerService,
  ) {}

  @Get('me')
  async me(@Auth() auth: UserAuth) {
    return this.profile(auth.userId);
  }

  private async profile(userId: string) {
    const u = await this.db.one(
      `SELECT id, name, locale, phone_last4, phone_enc, email, gender, birth_year, google_sub IS NOT NULL AS google,
              password_hash IS NOT NULL AS has_password, avatar_media_id, profile_completed_at, created_at
         FROM users WHERE id = $1`,
      [userId],
    );
    const owns = await this.db.one(`SELECT id, name FROM businesses WHERE owner_user_id = $1`, [userId]);
    return {
      id: u.id,
      name: u.name,
      locale: u.locale,
      phoneLast4: u.phone_last4 ?? null,
      /** The member's own number, shown on their member card. */
      phone: u.phone_enc ? prettyPhone(this.crypto.decrypt(u.phone_enc)) : null,
      email: u.email ?? null,
      gender: u.gender ?? null,
      age: u.birth_year ? new Date().getFullYear() - u.birth_year : null,
      signInMethod: u.google ? 'GOOGLE' : 'PHONE',
      hasPassword: !!u.has_password,
      avatarUrl: mediaUrl(u.avatar_media_id),
      needsProfile: !u.profile_completed_at,
      business: owns ?? null,
    };
  }

  /**
   * Finishes signing up. Phone members give their name, age and gender;
   * Google members only what to be called. An optional invite code links the
   * friend who invited them. All of it is saved together or not at all.
   */
  @Post('profile')
  @HttpCode(200)
  async completeProfile(@Auth() auth: UserAuth, @Body() body: unknown) {
    const b = parse(zComplete, body);
    await this.db.tx(async (c) => {
      const u = (await c.query(`SELECT * FROM users WHERE id = $1 FOR UPDATE`, [auth.userId])).rows[0];
      // Already set up (for example the app asked again after signing back in):
      // just save the new details instead of refusing, so the member is never stuck.
      const again = !!u.profile_completed_at;
      const byPhone = !u.google_sub;
      if (byPhone && !again && (b.age == null || !b.gender)) {
        throw new AppError(400, 'PROFILE_INCOMPLETE', 'Age and gender are needed');
      }
      await c.query(
        `UPDATE users SET name = $2, birth_year = COALESCE($3, birth_year), gender = COALESCE($4, gender),
                locale = COALESCE($5, locale), profile_completed_at = COALESCE(profile_completed_at, now()), updated_at = now()
          WHERE id = $1`,
        [auth.userId, b.name, b.age == null ? null : new Date().getFullYear() - b.age, b.gender ?? null, b.locale ?? null],
      );
      // An invite code only counts on the first setup.
      if (b.referralCode && !again) await applyReferral(c, this.ledger, auth.userId, b.referralCode);
      await audit(c, { actorType: 'USER', actorId: auth.userId, action: again ? 'profile.update' : 'profile.complete', data: { referral: !!b.referralCode && !again } });
    });
    return this.profile(auth.userId);
  }

  /** Profile photo: upload replaces the old one; delete goes back to the Mukafaah avatar. */
  @Post('avatar')
  @HttpCode(200)
  async setAvatar(@Auth() auth: UserAuth, @Body() body: unknown) {
    const b = parse(z.strictObject({ dataBase64: z.string().min(20).max(4_500_000) }), body);
    await this.db.tx(async (c) => {
      const old = (await c.query(`SELECT avatar_media_id FROM users WHERE id = $1 FOR UPDATE`, [auth.userId])).rows[0]?.avatar_media_id;
      const id = await saveImage(c, null, b.dataBase64);
      await c.query(`UPDATE users SET avatar_media_id = $2, updated_at = now() WHERE id = $1`, [auth.userId, id]);
      if (old) await c.query(`DELETE FROM media WHERE id = $1`, [old]);
    });
    return this.profile(auth.userId);
  }

  @Delete('avatar')
  async deleteAvatar(@Auth() auth: UserAuth) {
    await this.db.tx(async (c) => {
      const old = (await c.query(`SELECT avatar_media_id FROM users WHERE id = $1 FOR UPDATE`, [auth.userId])).rows[0]?.avatar_media_id;
      await c.query(`UPDATE users SET avatar_media_id = NULL, updated_at = now() WHERE id = $1`, [auth.userId]);
      if (old) await c.query(`DELETE FROM media WHERE id = $1`, [old]);
    });
    return this.profile(auth.userId);
  }

  @Patch('me')
  async update(@Auth() auth: UserAuth, @Body() body: unknown) {
    const b = parse(zProfile, body);
    await this.db.query(
      `UPDATE users SET name = COALESCE($2, name), locale = COALESCE($3, locale), updated_at = now() WHERE id = $1`,
      [auth.userId, b.name ?? null, b.locale ?? null],
    );
    return this.me(auth);
  }

  /** Balances per program, with where each balance can be used. */
  @Get('wallet')
  async wallet(@Auth() auth: UserAuth) {
    const r = await this.db.query(
      `SELECT p.id AS program_id, p.type, p.name AS program_name, p.redeem_points_per_unit,
              ab.balance,
              (SELECT json_agg(json_build_object('id', b.id, 'name', b.name, 'category', b.category) ORDER BY b.name)
                 FROM program_members pm JOIN businesses b ON b.id = pm.business_id
                WHERE pm.program_id = p.id AND pm.active AND pm.can_redeem) AS usable_at
         FROM ledger_accounts a
         JOIN account_balances ab ON ab.account_id = a.id
         JOIN programs p ON p.id = a.program_id AND p.type <> 'PLATFORM'
        WHERE a.owner_type = 'CUSTOMER' AND a.owner_id = $1
        ORDER BY ab.balance DESC`,
      [auth.userId],
    );
    const total = r.rows.reduce((s, x) => s + Number(x.balance), 0);
    return {
      // Shop points only; Mukafaah Points are separate.
      totalPoints: total,
      mukafaahPoints: await mukafaahBalance(this.db, auth.userId),
      programs: r.rows.map((x) => ({
        programId: x.program_id,
        type: x.type,
        name: x.program_name,
        balance: Number(x.balance),
        pointsPerUnitDiscount: x.redeem_points_per_unit,
        usableAt: x.usable_at ?? [],
      })),
    };
  }

  @Get('wallet/transactions')
  async transactions(@Auth() auth: UserAuth, @Query() q: unknown) {
    const { limit } = parse(zPage, q);
    const r = await this.db.query(
      `SELECT t.id, t.type, t.created_at, e.amount, p.name AS program_name, p.type AS program_type,
              b.name AS business_name, br.name AS branch_name
         FROM ledger_transactions t
         JOIN ledger_entries e ON e.transaction_id = t.id
         JOIN ledger_accounts a ON a.id = e.account_id AND a.owner_type = 'CUSTOMER' AND a.owner_id = $1
         JOIN programs p ON p.id = t.program_id
         LEFT JOIN businesses b ON b.id = t.business_id
         LEFT JOIN branches br ON br.id = t.branch_id
        ORDER BY t.created_at DESC
        LIMIT $2`,
      [auth.userId, limit],
    );
    return r.rows.map((x) => ({
      id: x.id,
      type: x.type,
      points: Number(x.amount),
      programName: x.program_name,
      programType: x.program_type,
      businessName: x.business_name,
      branchName: x.branch_name,
      createdAt: x.created_at,
    }));
  }

  /** Pre-Points waiting for this verified phone number. */
  @Get('prepoints')
  async prepoints(@Auth() auth: UserAuth) {
    const r = await this.db.query(
      `SELECT p.id AS program_id, p.type, p.name AS program_name, ab.balance,
              (SELECT json_agg(DISTINCT b.name)
                 FROM ledger_transactions t JOIN businesses b ON b.id = t.business_id
                WHERE t.pending_holder_id = h.id AND t.program_id = p.id AND t.type = 'PREPOINT_EARN') AS from_businesses
         FROM users u
         JOIN pending_holders h ON h.phone_hash = u.phone_hash
         JOIN ledger_accounts a ON a.owner_type = 'PENDING' AND a.owner_id = h.id
         JOIN account_balances ab ON ab.account_id = a.id AND ab.balance > 0
         JOIN programs p ON p.id = a.program_id
        WHERE u.id = $1`,
      [auth.userId],
    );
    const total = r.rows.reduce((s, x) => s + Number(x.balance), 0);
    return {
      totalPoints: total,
      items: r.rows.map((x) => ({
        programId: x.program_id,
        type: x.type,
        programName: x.program_name,
        points: Number(x.balance),
        fromBusinesses: x.from_businesses ?? [],
      })),
    };
  }

  /** Moves every pending balance for this phone into the customer's wallet. No merchant approval. */
  @Post('prepoints/collect')
  @HttpCode(200)
  async collect(@Auth() auth: UserAuth, @IdemKey() key: string) {
    return this.db.tx(async (c) => {
      const pend = await c.query(
        `SELECT a.id AS account_id, a.program_id, h.id AS holder_id
           FROM users u
           JOIN pending_holders h ON h.phone_hash = u.phone_hash
           JOIN ledger_accounts a ON a.owner_type = 'PENDING' AND a.owner_id = h.id
          WHERE u.id = $1
          ORDER BY a.id`,
        [auth.userId],
      );
      let collected = 0;
      for (const row of pend.rows) {
        const idem = `collect:${auth.userId}:${key}:${row.account_id}`;
        if (await this.ledger.existing(c, idem)) continue;
        // lock and read the pending balance
        const bal = await c.query(`SELECT balance FROM account_balances WHERE account_id = $1 FOR UPDATE`, [
          row.account_id,
        ]);
        const points = Number(bal.rows[0]?.balance ?? 0);
        if (points <= 0) continue;
        const wallet = await this.ledger.account(c, row.program_id, 'CUSTOMER', auth.userId);
        await this.ledger.post(c, {
          type: 'PREPOINT_CLAIM',
          programId: row.program_id,
          idempotencyKey: idem,
          userId: auth.userId,
          pendingHolderId: row.holder_id,
          entries: [
            { accountId: row.account_id, amount: -points },
            { accountId: wallet, amount: points },
          ],
        });
        collected += points;
      }
      if (collected > 0) {
        await audit(c, { actorType: 'USER', actorId: auth.userId, action: 'prepoints.collect', data: { points: collected } });
      }
      return { collectedPoints: collected };
    });
  }

  /**
   * The member's fixed QR: MKF2:<memberCode>. It never changes, so the app can
   * keep it offline. Earning needs nothing more; spending always needs the
   * customer's approval in the app.
   */
  @Get('qr')
  async qr(@Auth() auth: UserAuth) {
    const code = await memberCode(this.db, auth.userId);
    return { payload: MEMBER_QR_PREFIX + code, memberCode: code };
  }

  /** Kept for older app builds: returns the same fixed QR. */
  @Post('qr/token')
  @HttpCode(200)
  async qrToken(@Auth() auth: UserAuth) {
    const { payload } = await this.qr(auth);
    return { token: payload, payload, ttlSeconds: 0, expiresAt: null };
  }

  /** Businesses on Mukafaah, with the programs they belong to. */
  @Get('businesses')
  async businesses() {
    const r = await this.db.query(
      `SELECT b.id, b.name, b.category,
              json_agg(json_build_object('programId', p.id, 'type', p.type, 'name', p.name,
                                         'earnPointsPerUnit', p.earn_points_per_unit) ORDER BY p.type) AS programs
         FROM businesses b
         JOIN program_members pm ON pm.business_id = b.id AND pm.active
         JOIN programs p ON p.id = pm.program_id AND p.status = 'ACTIVE'
        WHERE b.status = 'ACTIVE'
        GROUP BY b.id
        ORDER BY b.created_at DESC
        LIMIT 100`,
    );
    return r.rows;
  }
}

@Module({ controllers: [CustomerController] })
export class CustomerModule {}
