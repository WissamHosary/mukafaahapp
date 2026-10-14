import { Body, Controller, Get, HttpCode, Module, Param, Post, Query } from '@nestjs/common';
import { z } from 'zod';
import { audit } from '../platform/audit.js';
import { Auth, IdemKey, RequireUser, type UserAuth } from '../platform/auth.js';
import { CryptoService } from '../platform/crypto.js';
import { Db, pgCode, type Tx } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zPoints, zUuid } from '../platform/validation.js';
import { LedgerService } from './ledger.js';
import { grantRule } from './mukafaah.js';
import {
  alertBusiness,
  bookingCode,
  bookingJson,
  fmtPts,
  getSetting,
  lifetimePoints,
  loadTierRows,
  notify,
  tierName,
  tierProgress,
} from './shared.js';

const zBook = z.strictObject({
  requestedFor: z.iso.datetime({ offset: true }).optional(),
  partySize: z.number().int().min(1).max(100).optional(),
  note: z.string().trim().max(300).optional(),
});
const zHistory = z.object({
  filter: z.enum(['all', 'earned', 'used']).default('all'),
  q: z.string().trim().max(60).optional(),
  limit: z.coerce.number().int().min(1).max(200).default(60),
});
const zRecipient = z.object({ to: z.string().trim().min(4).max(20) });
const zTransfer = z.strictObject({
  to: z.string().trim().min(4).max(20),
  programId: zUuid,
  points: zPoints,
  note: z.string().trim().max(120).optional(),
});
export const zReferral = z.strictObject({ code: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{5,10}$/) });

type TransferRules = { minPoints: number; dailyMaxPoints: number; dailyMaxCount: number; minTier: string };
const TRANSFER_DEFAULTS: TransferRules = { minPoints: 10, dailyMaxPoints: 20000, dailyMaxCount: 10, minTier: 'GOLD' };

const BENEFITS: Record<string, { ar: string; en: string }[]> = {
  SILVER: [
    { ar: 'جمع نقاط بكل المحلات', en: 'Earn points at every shop' },
    { ar: 'نقاط مسبقة بتنحفظلك', en: 'Pre-Points saved for you' },
    { ar: 'عروض المحلات', en: 'Shop offers' },
  ],
  GOLD: [
    { ar: 'تحويل نقاط للأصحاب', en: 'Send points to friends' },
    { ar: 'عروض خاصة للأعضاء الذهبيين', en: 'Gold member offers' },
    { ar: 'أولوية بالدعم', en: 'Priority support' },
  ],
  PLATINUM: [
    { ar: 'عروض الشركاء الحصرية', en: 'Exclusive partner offers' },
    { ar: 'هدايا مكافأة', en: 'Mukafaah gifts' },
    { ar: 'دعوات لفعاليات خاصة', en: 'Invitations to special events' },
  ],
};

/** "Lara Haddad" becomes "Lara H." (what other members are shown). */
export function shortName(name: string | null) {
  if (!name) return null;
  const parts = name.trim().split(/\s+/);
  return parts.length > 1 ? `${parts[0]} ${parts[parts.length - 1][0]}.` : parts[0];
}

/**
 * Links a member to the friend who invited them and gives that friend their
 * Mukafaah Points. Used from sign-up and from the Invite screen. Returns the
 * friend's short name.
 */
export async function applyReferral(c: Tx, ledger: LedgerService, userId: string, rawCode: string): Promise<string | null> {
  const code = rawCode.trim().toUpperCase();
  const me = (await c.query(`SELECT * FROM users WHERE id = $1 FOR UPDATE`, [userId])).rows[0];
  if (me.referred_by) throw new AppError(409, 'REFERRAL_USED', 'You already used an invite code');
  const windowDays = Number((await getSetting<{ windowDays?: number }>(c, 'referral', {})).windowDays ?? 14);
  if (Date.now() - new Date(me.created_at).getTime() > windowDays * 86_400_000) {
    throw new AppError(409, 'REFERRAL_EXPIRED', 'Invite codes can only be used in your first 14 days');
  }
  const ref = (await c.query(`SELECT id, name FROM users WHERE referral_code = $1 AND status = 'ACTIVE'`, [code])).rows[0];
  if (!ref || ref.id === userId) throw new AppError(404, 'REFERRAL_NOT_FOUND', 'This invite code does not exist');
  await c.query(`UPDATE users SET referred_by = $2, referred_at = now() WHERE id = $1`, [userId, ref.id]);
  // Mukafaah Points for the friend who invited (once per invited member).
  await grantRule(c, ledger, 'REFERRAL', ref.id, userId);
  const who = shortName(me.name) ?? '';
  await notify(c, ref.id, 'REFERRAL', {
    ar: { title: 'صاحبك انضم لمكافأة', body: `${who} استعمل رمز الدعوة تبعك` },
    en: { title: 'Your friend joined Mukafaah', body: `${who} used your invite code` },
  });
  return shortName(ref.name);
}

@Controller('v1/customer')
@RequireUser()
export class EngageController {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
    private readonly ledger: LedgerService,
  ) {}

  // ---------- Bookings ----------
  /** The customer asks to book an offer; the shop accepts or declines in Mukafaah Business. */
  @Post('offers/:id/book')
  @HttpCode(200)
  async book(@Auth() a: UserAuth, @Param('id') id: string, @Body() body: unknown) {
    const offerId = parse(zUuid, id);
    const b = parse(zBook, body);
    return this.db.tx(async (c) => {
      const o = (
        await c.query(
          `SELECT o.*, b.name AS business_name FROM offers o JOIN businesses b ON b.id = o.business_id
            WHERE o.id = $1 AND o.status = 'ACTIVE' AND NOT o.hidden_by_admin AND b.status = 'ACTIVE'
              AND o.valid_from <= current_date AND (o.valid_to IS NULL OR o.valid_to >= current_date)
            FOR UPDATE OF o`,
          [offerId],
        )
      ).rows[0];
      if (!o) throw new AppError(404, 'OFFER_UNAVAILABLE', 'This offer is no longer available');
      if (!o.requires_booking) throw new AppError(409, 'NO_BOOKING_NEEDED', 'Show your QR at the shop to use this offer');
      if (b.requestedFor && new Date(b.requestedFor).getTime() < Date.now() - 5 * 60_000) {
        throw Errors.validation({ requestedFor: ['IN_THE_PAST'] });
      }
      const open = await c.query(
        `SELECT 1 FROM offer_bookings WHERE offer_id = $1 AND user_id = $2 AND status IN ('REQUESTED','ACCEPTED')`,
        [offerId, a.userId],
      );
      if (open.rowCount) throw new AppError(409, 'BOOKING_EXISTS', 'You already have a booking for this offer');
      const used = await c.query(
        `SELECT count(*)::int AS n FROM offer_bookings WHERE offer_id = $1 AND user_id = $2 AND status = 'REDEEMED'`,
        [offerId, a.userId],
      );
      if (used.rows[0].n >= o.max_per_customer) throw new AppError(409, 'OFFER_LIMIT_REACHED', 'You already used this offer');
      if (o.total_limit) {
        const all = await c.query(
          `SELECT count(*)::int AS n FROM offer_bookings WHERE offer_id = $1 AND status IN ('REQUESTED','ACCEPTED','REDEEMED')`,
          [offerId],
        );
        if (all.rows[0].n >= o.total_limit) throw new AppError(409, 'OFFER_SOLD_OUT', 'This offer is fully booked');
      }
      let row: any;
      for (let i = 0; i < 5 && !row; i++) {
        try {
          await c.query('SAVEPOINT bk');
          row = (
            await c.query(
              `INSERT INTO offer_bookings(offer_id, business_id, user_id, requested_for, party_size, note, code, saving_minor)
               VALUES ($1,$2,$3,$4,$5,$6,$7,$8) RETURNING *`,
              [offerId, o.business_id, a.userId, b.requestedFor ?? null, b.partySize ?? null, b.note ?? null, bookingCode(), o.saving_minor],
            )
          ).rows[0];
          await c.query('RELEASE SAVEPOINT bk');
        } catch (e) {
          await c.query('ROLLBACK TO SAVEPOINT bk');
          if (pgCode(e) !== '23505') throw e;
        }
      }
      if (!row) throw new AppError(500, 'BOOKING_CODE');
      await audit(c, { actorType: 'USER', actorId: a.userId, businessId: o.business_id, action: 'booking.request', entityId: row.id });
      const who = (await c.query(`SELECT name, phone_last4 FROM users WHERE id = $1`, [a.userId])).rows[0];
      const label = who?.name || `•••• ${who?.phone_last4 ?? ''}`;
      const when = b.partySize ? ` · ${b.partySize}` : '';
      await alertBusiness(
        c,
        o.business_id,
        'BOOKING',
        {
          ar: { title: 'طلب حجز جديد', body: `${o.title} · ${label}${when}` },
          en: { title: 'New booking request', body: `${o.title} · ${label}${when}` },
        },
        row.id,
      );
      return bookingJson({ ...row, offer_title: o.title, offer_media: o.media_id, points_cost: o.points_cost, business_name: o.business_name });
    });
  }

  @Get('bookings')
  async bookings(@Auth() a: UserAuth) {
    const r = await this.db.query(
      `SELECT k.*, o.title AS offer_title, o.media_id AS offer_media, o.points_cost, b.name AS business_name, b.logo_media_id AS business_logo
         FROM offer_bookings k JOIN offers o ON o.id = k.offer_id JOIN businesses b ON b.id = k.business_id
        WHERE k.user_id = $1 ORDER BY k.created_at DESC LIMIT 100`,
      [a.userId],
    );
    return r.rows.map(bookingJson);
  }

  @Post('bookings/:id/cancel')
  @HttpCode(200)
  async cancel(@Auth() a: UserAuth, @Param('id') id: string) {
    const r = await this.db.query(
      `UPDATE offer_bookings SET status = 'CANCELLED', updated_at = now()
        WHERE id = $1 AND user_id = $2 AND status IN ('REQUESTED','ACCEPTED') RETURNING id`,
      [parse(zUuid, id), a.userId],
    );
    if (!r.rowCount) throw Errors.notFound('Booking');
    return { ok: true };
  }

  // ---------- History ----------
  @Get('history')
  async history(@Auth() a: UserAuth, @Query() q: unknown) {
    const f = parse(zHistory, q);
    const totals = await this.db.one(
      `SELECT COALESCE(SUM(e.amount) FILTER (WHERE e.amount > 0), 0) AS earned,
              COALESCE(-SUM(e.amount) FILTER (WHERE e.amount < 0), 0) AS used
         FROM ledger_entries e
         JOIN ledger_accounts a ON a.id = e.account_id AND a.owner_type = 'CUSTOMER' AND a.owner_id = $1`,
      [a.userId],
    );
    const r = await this.db.query(
      `SELECT t.id, t.type, t.created_at, e.amount, b.name AS business_name, b.logo_media_id,
              pt.from_user_id, pt.to_user_id, fu.name AS from_name, tu.name AS to_name,
              w.title AS reward_title, o.title AS offer_title
         FROM ledger_entries e
         JOIN ledger_accounts a ON a.id = e.account_id AND a.owner_type = 'CUSTOMER' AND a.owner_id = $1
         JOIN ledger_transactions t ON t.id = e.transaction_id
         JOIN programs p ON p.id = t.program_id
         LEFT JOIN businesses b ON b.id = COALESCE(t.business_id, p.owner_business_id)
         LEFT JOIN point_transfers pt ON pt.ledger_tx_id = t.id
         LEFT JOIN users fu ON fu.id = pt.from_user_id
         LEFT JOIN users tu ON tu.id = pt.to_user_id
         LEFT JOIN visits v ON v.ledger_tx_id = t.id
         LEFT JOIN rewards w ON v.ref_type = 'REWARD' AND w.id = v.ref_id
         LEFT JOIN offers o ON v.ref_type = 'OFFER' AND o.id = v.ref_id
        WHERE ($2::text = 'all' OR ($2::text = 'earned' AND e.amount > 0) OR ($2::text = 'used' AND e.amount < 0))
          AND ($3::text IS NULL OR b.name ILIKE '%' || $3 || '%')
        ORDER BY e.id DESC LIMIT $4`,
      [a.userId, f.filter, f.q || null, f.limit],
    );
    return {
      totalEarned: Number(totals?.earned ?? 0),
      totalUsed: Number(totals?.used ?? 0),
      items: r.rows.map((x) => ({
        id: x.id,
        type: x.type,
        points: Number(x.amount),
        businessName: x.business_name ?? null,
        businessLogoUrl: x.logo_media_id ? `/v1/media/${x.logo_media_id}` : null,
        counterpartName: x.type === 'TRANSFER' ? (Number(x.amount) > 0 ? x.from_name : x.to_name) ?? null : null,
        detail: x.reward_title ?? x.offer_title ?? null,
        createdAt: x.created_at,
      })),
    };
  }

  // ---------- Tier (by total spend) ----------
  @Get('tier')
  async tier(@Auth() a: UserAuth) {
    const [u, rows, lifetime] = await Promise.all([
      this.db.one(`SELECT tier, lifetime_spend_minor, locale FROM users WHERE id = $1`, [a.userId]),
      loadTierRows(this.db),
      lifetimePoints(this.db, a.userId),
    ]);
    const spend = Number(u?.lifetime_spend_minor ?? 0);
    const { current, next } = tierProgress(rows, u?.tier ?? 'SILVER', spend);
    const code = current?.code ?? u?.tier ?? 'SILVER';
    const idx = rows.findIndex((x) => x.code === code);
    const stats = await this.db.one(
      `SELECT
         (SELECT count(DISTINCT business_id)::int FROM visits WHERE user_id = $1 AND voided_by_tx_id IS NULL) AS shops,
         (SELECT count(*)::int FROM visits WHERE user_id = $1 AND type = 'REDEEM' AND voided_by_tx_id IS NULL) AS redeems,
         (SELECT count(*)::int FROM ledger_transactions WHERE user_id = $1 AND type = 'PREPOINT_CLAIM') AS claims,
         (SELECT count(*)::int FROM users WHERE referred_by = $1) AS invited,
         (SELECT count(*)::int FROM offer_bookings WHERE user_id = $1 AND status = 'REDEEMED') AS offers,
         (SELECT count(*)::int FROM business_ratings WHERE user_id = $1) AS ratings`,
      [a.userId],
    );
    const ach = (key: string, done: boolean, progress: number, goal: number, ar: string, en: string) => ({
      key,
      done,
      progress: Math.min(progress, goal),
      goal,
      title: { ar, en },
    });
    return {
      tier: code,
      lifetimeSpendMinor: spend,
      tiers: rows.map((x) => ({
        code: x.code,
        name: tierName(x, u?.locale),
        minSpendMinor: x.minSpendMinor,
        bonusPoints: x.bonusPoints,
        color: x.color,
        perks: x.perks,
      })),
      next: next
        ? { code: next.code, name: tierName(next, u?.locale), minSpendMinor: next.minSpendMinor, remainingMinor: Math.max(0, next.minSpendMinor - spend) }
        : null,
      // Older builds.
      lifetimePoints: lifetime,
      currentMin: current?.minSpendMinor ?? 0,
      benefits: {
        previous: (idx > 0 ? rows.slice(0, idx) : []).flatMap((x) => BENEFITS[x.code] ?? []),
        current: BENEFITS[code] ?? [],
        next: next ? (BENEFITS[next.code] ?? []) : [],
      },
      achievements: [
        ach('FIRST_POINTS', lifetime > 0, lifetime > 0 ? 1 : 0, 1, 'أول نقاط', 'First points'),
        ach('FIVE_SHOPS', stats.shops >= 5, stats.shops, 5, 'زرت ٥ محلات', 'Visited 5 shops'),
        ach('FIRST_REDEEM', stats.redeems > 0, stats.redeems, 1, 'أول صرف نقاط', 'First redemption'),
        ach('PREPOINTS', stats.claims > 0, stats.claims, 1, 'جمعت نقاط مسبقة', 'Collected Pre-Points'),
        ach('FIRST_OFFER', stats.offers > 0, stats.offers, 1, 'استعملت عرض', 'Used an offer'),
        ach('INVITE', stats.invited > 0, stats.invited, 1, 'دعيت صاحب', 'Invited a friend'),
        ach('RATER', stats.ratings >= 3, stats.ratings, 3, 'قيّمت ٣ محلات', 'Rated 3 shops'),
      ],
    };
  }

  // ---------- Transfers ----------
  private async findRecipient(to: string) {
    const raw = to.trim().toUpperCase();
    if (/^[A-Z0-9]{5,10}$/.test(raw) && /[A-Z]/.test(raw)) {
      const u = await this.db.one(`SELECT id, name, phone_last4 FROM users WHERE referral_code = $1 AND status = 'ACTIVE'`, [raw]);
      if (u) return u;
    }
    let e164: string;
    try {
      e164 = this.crypto.normalizePhone(to);
    } catch {
      return null;
    }
    return this.db.one(`SELECT id, name, phone_last4 FROM users WHERE phone_hash = $1 AND status = 'ACTIVE'`, [
      this.crypto.phoneHash(e164),
    ]);
  }

  private static shortName(name: string | null) {
    return shortName(name);
  }

  /** Shows who will receive the points before sending (first name and last initial only). */
  @Get('transfer/recipient')
  async recipient(@Auth() a: UserAuth, @Query() q: unknown) {
    const f = parse(zRecipient, q);
    const u = await this.findRecipient(f.to);
    if (!u || u.id === a.userId) throw new AppError(404, 'RECIPIENT_NOT_FOUND', 'No Mukafaah member with this number or code');
    return { name: EngageController.shortName(u.name), phoneLast4: u.phone_last4 };
  }

  @Post('transfer')
  @HttpCode(200)
  async transfer(@Auth() a: UserAuth, @Body() body: unknown, @IdemKey() key: string) {
    const b = parse(zTransfer, body);
    const rules = { ...TRANSFER_DEFAULTS, ...(await getSetting<Partial<TransferRules>>(this.db, 'transfer', {})) };
    if (b.points < rules.minPoints) throw new AppError(400, 'TRANSFER_TOO_SMALL', `Send at least ${rules.minPoints} points`);
    const to = await this.findRecipient(b.to);
    if (!to || to.id === a.userId) throw new AppError(404, 'RECIPIENT_NOT_FOUND', 'No Mukafaah member with this number or code');
    const idem = `transfer:${a.userId}:${key}`;
    return this.db.tx(async (c) => {
      const prior = await this.ledger.existing(c, idem);
      if (prior) return { transactionId: prior, replayed: true };
      const prog = (await c.query(`SELECT p.*, b.name AS business_name FROM programs p LEFT JOIN businesses b ON b.id = p.owner_business_id WHERE p.id = $1 AND p.status = 'ACTIVE'`, [b.programId])).rows[0];
      if (!prog) throw Errors.notFound('Program');
      if (!prog.allow_transfer) throw new AppError(403, 'TRANSFER_DISABLED', 'This shop does not allow sending its points');
      const myTier = (await c.query(`SELECT tier FROM users WHERE id = $1`, [a.userId])).rows[0]?.tier ?? 'SILVER';
      const order = (await loadTierRows(c, false)).map((t) => t.code);
      const need = order.indexOf(rules.minTier);
      if (need > 0 && order.indexOf(myTier) < need) {
        throw new AppError(403, 'TIER_REQUIRED', `Sending points unlocks at ${rules.minTier}`);
      }
      const day = (
        await c.query(
          `SELECT count(*)::int AS n, COALESCE(SUM(points), 0) AS s FROM point_transfers
            WHERE from_user_id = $1 AND created_at > now() - interval '24 hours'`,
          [a.userId],
        )
      ).rows[0];
      if (day.n >= rules.dailyMaxCount || Number(day.s) + b.points > rules.dailyMaxPoints) {
        throw new AppError(429, 'TRANSFER_DAILY_LIMIT', 'Daily sending limit reached');
      }
      const from = await this.ledger.account(c, prog.id, 'CUSTOMER', a.userId);
      const dest = await this.ledger.account(c, prog.id, 'CUSTOMER', to.id);
      const txId = await this.ledger.post(c, {
        type: 'TRANSFER',
        programId: prog.id,
        idempotencyKey: idem,
        userId: a.userId,
        businessId: prog.owner_business_id ?? null,
        reason: b.note ?? null,
        entries: [
          { accountId: from, amount: -b.points },
          { accountId: dest, amount: b.points },
        ],
      });
      await c.query(
        `INSERT INTO point_transfers(program_id, from_user_id, to_user_id, points, note, ledger_tx_id) VALUES ($1,$2,$3,$4,$5,$6)`,
        [prog.id, a.userId, to.id, b.points, b.note ?? null, txId],
      );
      const me = (await c.query(`SELECT name FROM users WHERE id = $1`, [a.userId])).rows[0];
      const who = EngageController.shortName(me?.name ?? null) ?? '';
      const shop = prog.business_name ?? prog.name;
      await notify(c, to.id, 'TRANSFER_IN', {
        ar: { title: `وصلك ${fmtPts(b.points)} نقطة`, body: `${who} بعتلك نقاط ${shop}${b.note ? `: ${b.note}` : ''}` },
        en: { title: `You received ${fmtPts(b.points)} points`, body: `${who} sent you ${shop} points${b.note ? `: ${b.note}` : ''}` },
      });
      await audit(c, { actorType: 'USER', actorId: a.userId, action: 'points.transfer', entityId: txId, data: { points: b.points, to: to.id } });
      const bal = (await c.query(`SELECT balance FROM account_balances WHERE account_id = $1`, [from])).rows[0];
      return { transactionId: txId, newBalance: Number(bal.balance), recipient: EngageController.shortName(to.name), replayed: false };
    });
  }

  // ---------- Referral ----------
  @Get('referral')
  async referral(@Auth() a: UserAuth) {
    const u = await this.db.one(
      `SELECT u.referral_code, u.referred_by, u.created_at, r.name AS referrer_name,
              (SELECT count(*)::int FROM users x WHERE x.referred_by = u.id) AS invited
         FROM users u LEFT JOIN users r ON r.id = u.referred_by WHERE u.id = $1`,
      [a.userId],
    );
    const windowDays = Number((await getSetting<{ windowDays?: number }>(this.db, 'referral', {})).windowDays ?? 14);
    const canEnter = !u.referred_by && Date.now() - new Date(u.created_at).getTime() < windowDays * 86_400_000;
    return {
      code: u.referral_code,
      invitedCount: u.invited,
      referredBy: u.referred_by ? EngageController.shortName(u.referrer_name) : null,
      canEnterCode: canEnter,
    };
  }

  /** A new member enters the code of the friend who invited them (once, within 14 days of joining). */
  @Post('referral')
  @HttpCode(200)
  async useReferral(@Auth() a: UserAuth, @Body() body: unknown) {
    const b = parse(zReferral, body);
    return this.db.tx(async (c) => ({ ok: true, referredBy: await applyReferral(c, this.ledger, a.userId, b.code) }));
  }

  /** Checks an invite code while the member types it at sign-up (does not use it). */
  @Get('referral/check')
  async checkReferral(@Auth() a: UserAuth, @Query() q: unknown) {
    const parsed = zReferral.safeParse({ code: (q as { code?: unknown } | null)?.code });
    if (!parsed.success) return { valid: false, referrer: null };
    const ref = await this.db.one(`SELECT id, name FROM users WHERE referral_code = $1 AND status = 'ACTIVE'`, [parsed.data.code]);
    if (!ref || ref.id === a.userId) return { valid: false, referrer: null };
    return { valid: true, referrer: shortName(ref.name) };
  }

  // ---------- Notifications ----------
  @Get('notifications')
  async notifications(@Auth() a: UserAuth) {
    const r = await this.db.query(
      `SELECT id, kind, title, body, data, read_at, created_at FROM notifications WHERE user_id = $1 ORDER BY created_at DESC LIMIT 100`,
      [a.userId],
    );
    return r.rows.map((x) => ({
      id: x.id,
      kind: x.kind,
      title: x.title,
      body: x.body ?? null,
      data: x.data ?? null,
      read: !!x.read_at,
      createdAt: x.created_at,
    }));
  }

  @Post('notifications/read-all')
  @HttpCode(200)
  async readAll(@Auth() a: UserAuth) {
    await this.db.query(`UPDATE notifications SET read_at = now() WHERE user_id = $1 AND read_at IS NULL`, [a.userId]);
    return { ok: true };
  }
}

@Module({ controllers: [EngageController] })
export class EngageModule {}
