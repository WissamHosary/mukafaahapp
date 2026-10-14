import { Body, Controller, Get, HttpCode, Module, Param, Post, Query, Res } from '@nestjs/common';
import { verify as verifyPin } from '@node-rs/argon2';
import { z } from 'zod';
import { audit } from '../platform/audit.js';
import { Auth, ClientIp, IdemKey, OptionalIdemKey, RequireStaff, type StaffAuth } from '../platform/auth.js';
import { CryptoService } from '../platform/crypto.js';
import { Db, type Queryable, type Tx } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zMinor, zPoints, zUuid } from '../platform/validation.js';
import { QR_PREFIX } from './customer.js';
import { LedgerService } from './ledger.js';
import { addSpend, grantRule, mukafaahBalance } from './mukafaah.js';
import { RedeemModule, RedeemService, type CounterCtx } from './redeem.js';
import { MEMBER_QR_PREFIX, bookingJson, fmtPts, listAlerts, mediaUrl, notify, pointsValueMinor } from './shared.js';

const STAFF_TOKEN_TTL = '12h';
const PIN_MAX_FAILURES = 5;

const zPair = z.strictObject({ code: z.string().trim().toUpperCase().regex(/^[A-Z0-9]{8}$/), label: z.string().trim().min(1).max(60) });
const zDevice = z.strictObject({ deviceId: zUuid, deviceSecret: z.string().min(20).max(100) });
const zLogin = z.strictObject({ deviceId: zUuid, deviceSecret: z.string().min(20).max(100), staffId: zUuid, pin: z.string().regex(/^\d{4,6}$/) });
const zTarget = z
  .strictObject({ phone: z.string().min(6).max(20).optional(), qr: z.string().min(10).max(2000).optional() })
  .refine((v) => !!v.phone !== !!v.qr, { message: 'Provide phone or qr' });
const zEarn = z
  .strictObject({
    phone: z.string().min(6).max(20).optional(),
    qr: z.string().min(10).max(2000).optional(),
    billMinor: zMinor,
    /** The shop's own invoice / receipt number, kept with the bill. */
    invoiceNo: z.string().trim().max(40).optional(),
  })
  .refine((v) => !!v.phone !== !!v.qr, { message: 'Provide phone or qr' });
const zPreview = z.strictObject({ billMinor: zMinor });
// Spending: the customer is identified by their QR (or by the id a lookup returned).
const zRedeem = z
  .strictObject({ qr: z.string().min(10).max(2000).optional(), userId: zUuid.optional(), programId: zUuid, points: zPoints })
  .refine((v) => !!v.qr !== !!v.userId, { message: 'Provide qr or userId' });
const zQrOnly = z
  .strictObject({ qr: z.string().min(10).max(2000).optional(), userId: zUuid.optional() })
  .refine((v) => !!v.qr !== !!v.userId, { message: 'Provide qr or userId' });
const zMukafaah = z.strictObject({ userId: zUuid, points: zPoints, billMinor: zMinor.optional() });
const zAfter = z.object({ after: z.coerce.number().int().min(0).optional() });

type Target =
  | { kind: 'user'; userId: string; viaQr: boolean; qrJti?: string; name: string | null; last4: string }
  | { kind: 'pending'; holderId: string | null; phoneE164: string; last4: string };

@Controller('v1/business/cashier')
export class CashierController {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
    private readonly ledger: LedgerService,
    private readonly redeemer: RedeemService,
  ) {}

  // ---------- Device pairing and sign-in (no staff token yet) ----------
  @Post('pair')
  @HttpCode(200)
  async pair(@Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zPair, body);
    return this.db.tx(async (c) => {
      const pc = (
        await c.query(
          `SELECT * FROM pairing_codes WHERE code_hash = $1 AND used_at IS NULL AND expires_at > now() FOR UPDATE`,
          [this.crypto.sha256(b.code)],
        )
      ).rows[0];
      if (!pc) throw new AppError(400, 'PAIRING_CODE_INVALID', 'Code is wrong or expired');
      const secret = this.crypto.randomToken(32);
      const d = (
        await c.query(
          `INSERT INTO devices(business_id, branch_id, label, secret_hash) VALUES ($1,$2,$3,$4) RETURNING id`,
          [pc.business_id, pc.branch_id, b.label, this.crypto.sha256(secret)],
        )
      ).rows[0];
      await c.query(`UPDATE pairing_codes SET used_at = now() WHERE code_hash = $1`, [pc.code_hash]);
      await audit(c, { actorType: 'SYSTEM', businessId: pc.business_id, action: 'device.paired', entityId: d.id, ip });
      const info = (
        await c.query(
          `SELECT b.name AS business_name, br.name AS branch_name FROM businesses b JOIN branches br ON br.id = $2 WHERE b.id = $1`,
          [pc.business_id, pc.branch_id],
        )
      ).rows[0];
      return { deviceId: d.id, deviceSecret: secret, businessName: info.business_name, branchName: info.branch_name };
    });
  }

  private async device(deviceId: string, secret: string) {
    const d = await this.db.one(
      `SELECT d.*, b.name AS business_name, br.name AS branch_name
         FROM devices d JOIN businesses b ON b.id = d.business_id JOIN branches br ON br.id = d.branch_id
        WHERE d.id = $1`,
      [deviceId],
    );
    if (!d || d.status !== 'ACTIVE' || !this.crypto.safeEqual(this.crypto.sha256(secret), d.secret_hash)) {
      throw new AppError(401, 'DEVICE_NOT_PAIRED', 'This device is not paired');
    }
    return d;
  }

  @Post('device/staff')
  @HttpCode(200)
  async staffList(@Body() body: unknown) {
    const b = parse(zDevice, body);
    const d = await this.device(b.deviceId, b.deviceSecret);
    await this.db.query(`UPDATE devices SET last_seen_at = now() WHERE id = $1`, [d.id]);
    const r = await this.db.query(`SELECT id, name FROM staff WHERE branch_id = $1 AND active AND role = 'CASHIER' ORDER BY name`, [d.branch_id]);
    return { businessName: d.business_name, branchName: d.branch_name, staff: r.rows };
  }

  @Post('login')
  @HttpCode(200)
  async login(@Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zLogin, body);
    const d = await this.device(b.deviceId, b.deviceSecret);
    const s = await this.db.one(`SELECT * FROM staff WHERE id = $1 AND branch_id = $2 AND active AND role = 'CASHIER'`, [b.staffId, d.branch_id]);
    if (!s) throw Errors.unauthorized();
    if (s.locked_until && new Date(s.locked_until) > new Date()) throw new AppError(423, 'STAFF_LOCKED', 'Too many wrong PINs');
    const ok = await verifyPin(s.pin_hash, b.pin);
    if (!ok) {
      const fails = s.pin_failures + 1;
      await this.db.query(
        `UPDATE staff SET pin_failures = $2::int, locked_until = CASE WHEN $2::int >= $3::int THEN now() + interval '15 minutes' ELSE locked_until END WHERE id = $1`,
        [s.id, fails, PIN_MAX_FAILURES],
      );
      throw new AppError(401, 'PIN_INVALID', 'Wrong PIN');
    }
    await this.db.query(`UPDATE staff SET pin_failures = 0, locked_until = NULL WHERE id = $1`, [s.id]);
    const { token } = await this.crypto.sign(
      'staff',
      s.id,
      { bid: s.business_id, brid: s.branch_id, dev: d.id, role: 'CASHIER' },
      STAFF_TOKEN_TTL,
    );
    await this.db.tx((c) => audit(c, { actorType: 'STAFF', actorId: s.id, businessId: s.business_id, action: 'staff.login', ip }));
    return {
      accessToken: token,
      staff: { id: s.id, name: s.name, canRedeem: s.can_redeem },
      businessName: d.business_name,
      branchName: d.branch_name,
    };
  }

  // ---------- Counter operations (staff token) ----------
  private async resolve(c: Queryable, input: { phone?: string; qr?: string }): Promise<Target> {
    if (input.qr) {
      // v0.7 fixed member QR: MKF2:<memberCode>. It never changes.
      if (input.qr.startsWith(MEMBER_QR_PREFIX)) {
        const code = input.qr.slice(MEMBER_QR_PREFIX.length).trim().toUpperCase();
        const u = (await c.query(`SELECT id, name, phone_last4, status FROM users WHERE member_code = $1`, [code])).rows[0];
        if (!u || u.status !== 'ACTIVE') throw new AppError(400, 'QR_INVALID', 'Not a Mukafaah QR');
        return { kind: 'user', userId: u.id, viaQr: true, name: u.name, last4: u.phone_last4 };
      }
      // Older app builds: short-lived signed token.
      if (!input.qr.startsWith(QR_PREFIX)) throw new AppError(400, 'QR_INVALID', 'Not a Mukafaah QR');
      const p = await this.crypto.verify('qr', input.qr.slice(QR_PREFIX.length)).catch(() => {
        throw new AppError(400, 'QR_EXPIRED', 'QR expired, ask the customer to refresh it');
      });
      const u = (await c.query(`SELECT id, name, phone_last4, status FROM users WHERE id = $1`, [p.sub])).rows[0];
      if (!u || u.status !== 'ACTIVE') throw new AppError(400, 'QR_INVALID');
      return { kind: 'user', userId: u.id, viaQr: true, qrJti: String(p.jti), name: u.name, last4: u.phone_last4 };
    }
    const e164 = this.crypto.normalizePhone(input.phone!);
    const ph = this.crypto.phoneHash(e164);
    const u = (await c.query(`SELECT id, name, phone_last4, status FROM users WHERE phone_hash = $1`, [ph])).rows[0];
    if (u) {
      if (u.status !== 'ACTIVE') throw Errors.forbidden();
      return { kind: 'user', userId: u.id, viaQr: false, name: u.name, last4: u.phone_last4 };
    }
    const h = (await c.query(`SELECT id FROM pending_holders WHERE phone_hash = $1`, [ph])).rows[0];
    return { kind: 'pending', holderId: h?.id ?? null, phoneE164: e164, last4: e164.slice(-4) };
  }

  /** The member who spends points: from their QR, or the id a lookup returned. */
  private async member(c: Queryable, input: { qr?: string; userId?: string }) {
    if (input.userId) {
      const u = (await c.query(`SELECT id, name, phone_last4, status, locale FROM users WHERE id = $1`, [input.userId])).rows[0];
      if (!u || u.status !== 'ACTIVE') throw new AppError(404, 'CUSTOMER_NOT_FOUND', 'Customer not found');
      return { userId: String(u.id), locale: String(u.locale) };
    }
    const t = await this.resolve(c, { qr: input.qr });
    if (t.kind !== 'user') throw new AppError(400, 'QR_INVALID');
    const u = (await c.query(`SELECT locale FROM users WHERE id = $1`, [t.userId])).rows[0];
    return { userId: t.userId, locale: String(u?.locale ?? 'ar') };
  }

  private ctx(a: StaffAuth): CounterCtx {
    return { businessId: a.businessId, branchId: a.branchId, staffId: a.staffId, deviceId: a.deviceId };
  }

  /** 202 while the customer approves in the app; 200 when it was done right away. */
  private send(reply: any, out: { pending: boolean; body: unknown }) {
    return reply.status(out.pending ? 202 : 200).send(out.body);
  }

  /** Balances visible to this business only: programs it is an active member of. */
  private async scopedView(businessId: string, t: Target) {
    const ownerType = t.kind === 'user' ? 'CUSTOMER' : 'PENDING';
    const ownerId = t.kind === 'user' ? t.userId : t.holderId;
    const r = await this.db.query(
      `SELECT p.id, p.type, p.name, p.redeem_points_per_unit, pm.can_redeem,
              COALESCE((SELECT ab.balance FROM ledger_accounts a JOIN account_balances ab ON ab.account_id = a.id
                         WHERE a.program_id = p.id AND a.owner_type = $2 AND a.owner_id = $3::uuid), 0) AS balance
         FROM program_members pm JOIN programs p ON p.id = pm.program_id
        WHERE pm.business_id = $1 AND pm.active AND p.status = 'ACTIVE'
        ORDER BY p.type`,
      [businessId, ownerType, ownerId],
    );
    // Name is only shown when the customer presented their QR or has visited this business before.
    let displayName: string | null = null;
    if (t.kind === 'user') {
      const known =
        t.viaQr ||
        !!(await this.db.one(`SELECT 1 FROM visits WHERE business_id = $1 AND user_id = $2 LIMIT 1`, [businessId, t.userId]));
      displayName = known ? t.name : null;
    }
    const programs = r.rows.map((x) => ({
      programId: x.id,
      type: x.type,
      name: x.name,
      balance: Number(x.balance),
      canRedeemHere: x.can_redeem,
      pointsPerUnitDiscount: x.redeem_points_per_unit,
    }));
    let bookings: ReturnType<typeof bookingJson>[] = [];
    let walkInOffers: Record<string, unknown>[] = [];
    let rewards: Record<string, unknown>[] = [];
    let mukafaahPoints = 0;
    const biz = await this.db.one(`SELECT earning_program_id, friends_enabled, friends_max_points FROM businesses WHERE id = $1`, [businessId]);
    if (t.kind === 'user') {
      const earning = biz?.earning_program_id;
      const balHere = programs.find((p) => p.programId === earning)?.balance ?? 0;
      const [bk, wo, rw, mk] = await Promise.all([
        this.db.query(
          `SELECT k.*, o.title AS offer_title, o.media_id AS offer_media, o.points_cost
             FROM offer_bookings k JOIN offers o ON o.id = k.offer_id
            WHERE k.business_id = $1 AND k.user_id = $2 AND k.status = 'ACCEPTED'
            ORDER BY COALESCE(k.requested_for, k.created_at)`,
          [businessId, t.userId],
        ),
        this.db.query(
          `SELECT o.id, o.title, o.description, o.media_id, o.points_cost, o.max_per_customer,
                  (SELECT count(*)::int FROM offer_bookings k WHERE k.offer_id = o.id AND k.user_id = $2 AND k.status = 'REDEEMED') AS used
             FROM offers o
            WHERE o.business_id = $1 AND o.status = 'ACTIVE' AND NOT o.hidden_by_admin AND NOT o.requires_booking
              AND o.valid_from <= current_date AND (o.valid_to IS NULL OR o.valid_to >= current_date)
            ORDER BY o.created_at DESC`,
          [businessId, t.userId],
        ),
        this.db.query(
          `SELECT id, title, description, media_id, points_cost, stock FROM rewards
            WHERE business_id = $1 AND status = 'ACTIVE' AND (stock IS NULL OR stock > 0) ORDER BY points_cost`,
          [businessId],
        ),
        mukafaahBalance(this.db, t.userId),
      ]);
      mukafaahPoints = mk;
      bookings = bk.rows.map(bookingJson);
      walkInOffers = wo.rows.map((o) => ({
        id: o.id,
        title: o.title,
        description: o.description ?? null,
        imageUrl: mediaUrl(o.media_id),
        pointsCost: Number(o.points_cost),
        canUse: o.used < o.max_per_customer && balHere >= Number(o.points_cost),
        usedUp: o.used >= o.max_per_customer,
      }));
      rewards = rw.rows.map((w) => ({
        id: w.id,
        title: w.title,
        description: w.description ?? null,
        imageUrl: mediaUrl(w.media_id),
        pointsCost: Number(w.points_cost),
        stock: w.stock ?? null,
        canAfford: balHere >= Number(w.points_cost),
      }));
    }
    return {
      bookings,
      walkInOffers,
      rewards,
      status: t.kind === 'user' ? 'MEMBER' : 'NOT_ON_APP',
      // Members only: used by spend requests (mukafaah/redeem takes it).
      userId: t.kind === 'user' ? t.userId : null,
      displayName,
      phoneLast4: t.last4,
      presentedQr: t.kind === 'user' && t.viaQr,
      programs,
      prePointsHere: t.kind === 'pending' ? programs.reduce((s, p) => s + p.balance, 0) : 0,
      mukafaahPoints,
      friends: { enabled: !!biz?.friends_enabled, maxPoints: Number(biz?.friends_max_points ?? 0) },
    };
  }

  @Post('lookup')
  @HttpCode(200)
  @RequireStaff()
  async lookup(@Auth() a: StaffAuth, @Body() body: unknown) {
    const b = parse(zTarget, body);
    const t = await this.resolve(this.db, b);
    return this.scopedView(a.businessId, t);
  }

  private async earningProgram(c: Tx, businessId: string) {
    const r = await c.query(
      `SELECT p.*, b.time_zone, b.currency
         FROM businesses b
         JOIN programs p ON p.id = b.earning_program_id
         JOIN program_members pm ON pm.program_id = p.id AND pm.business_id = b.id AND pm.active AND pm.can_earn
        WHERE b.id = $1
        FOR SHARE OF pm`,
      [businessId],
    );
    if (!r.rows[0]) throw new AppError(409, 'NO_EARNING_PROGRAM', 'Earning is not enabled for this business');
    return r.rows[0];
  }

  private points(billMinor: number, prog: { earn_points_per_unit: number; min_bill_minor: number }) {
    if (billMinor < Number(prog.min_bill_minor)) return 0;
    return Math.floor((billMinor * prog.earn_points_per_unit) / 100);
  }

  @Post('earn/preview')
  @HttpCode(200)
  @RequireStaff()
  async preview(@Auth() a: StaffAuth, @Body() body: unknown) {
    const b = parse(zPreview, body);
    return this.db.tx(async (c) => {
      const prog = await this.earningProgram(c, a.businessId);
      return { points: this.points(b.billMinor, prog), programId: prog.id, programName: prog.name, programType: prog.type };
    });
  }

  /** Earning needs no approval from the customer. */
  @Post('earn')
  @HttpCode(200)
  @RequireStaff()
  async earn(@Auth() a: StaffAuth, @Body() body: unknown, @IdemKey() key: string, @ClientIp() ip: string) {
    const b = parse(zEarn, body);
    const idem = `earn:${a.staffId}:${key}`;
    return this.db.tx(async (c) => {
      const prior = await this.ledger.existing(c, idem);
      if (prior) return this.earnResult(c, prior, true);

      const staff = (await c.query(`SELECT * FROM staff WHERE id = $1 FOR UPDATE`, [a.staffId])).rows[0];
      const prog = await this.earningProgram(c, a.businessId);
      if (b.billMinor > Number(staff.max_bill_minor)) throw new AppError(403, 'STAFF_LIMIT_BILL', 'Bill is above your limit');
      const pts = this.points(b.billMinor, prog);
      if (pts <= 0) throw new AppError(400, 'NO_POINTS', 'This bill earns no points');
      if (pts > Number(staff.max_points_tx)) throw new AppError(403, 'STAFF_LIMIT_TX', 'Points are above your per-bill limit');
      const today = (await c.query(`SELECT (now() AT TIME ZONE $1)::date::text AS d`, [prog.time_zone])).rows[0].d;
      const used = (
        await c.query(
          `SELECT COALESCE(SUM(points),0) AS s FROM visits WHERE staff_id = $1 AND local_date = $2 AND type <> 'REDEEM' AND voided_by_tx_id IS NULL`,
          [a.staffId, today],
        )
      ).rows[0].s;
      if (Number(used) + pts > Number(staff.max_points_day)) throw new AppError(403, 'STAFF_LIMIT_DAY', 'Daily points limit reached');

      const t = await this.resolve(c, b);
      const issued = await this.ledger.account(c, prog.id, 'BUSINESS_ISSUED', a.businessId);
      let toAccount: string;
      let type: 'EARN' | 'PREPOINT_EARN';
      let userId: string | null = null;
      let holderId: string | null = null;
      if (t.kind === 'user') {
        type = 'EARN';
        userId = t.userId;
        toAccount = await this.ledger.account(c, prog.id, 'CUSTOMER', t.userId);
      } else {
        type = 'PREPOINT_EARN';
        const ph = this.crypto.phoneHash(t.phoneE164);
        await c.query(
          `INSERT INTO pending_holders(phone_hash, phone_enc, phone_last4) VALUES ($1,$2,$3) ON CONFLICT (phone_hash) DO NOTHING`,
          [ph, this.crypto.encrypt(t.phoneE164), t.last4],
        );
        holderId = (await c.query(`SELECT id FROM pending_holders WHERE phone_hash = $1`, [ph])).rows[0].id;
        const todayForPhone = (
          await c.query(
            `SELECT COALESCE(SUM(points),0) AS s FROM visits WHERE business_id = $1 AND pending_holder_id = $2 AND local_date = $3 AND voided_by_tx_id IS NULL`,
            [a.businessId, holderId, today],
          )
        ).rows[0].s;
        if (Number(todayForPhone) + pts > Number(staff.max_prepoints_day_per_phone)) {
          throw new AppError(403, 'PREPOINTS_LIMIT_PHONE', 'Daily Pre-Points limit for this number reached');
        }
        toAccount = await this.ledger.account(c, prog.id, 'PENDING', holderId!);
      }
      const txId = await this.ledger.post(c, {
        type,
        programId: prog.id,
        idempotencyKey: idem,
        businessId: a.businessId,
        branchId: a.branchId,
        staffId: a.staffId,
        deviceId: a.deviceId,
        userId,
        pendingHolderId: holderId,
        entries: [
          { accountId: issued, amount: -pts },
          { accountId: toAccount, amount: pts },
        ],
      });
      await c.query(
        `INSERT INTO visits(business_id, branch_id, staff_id, device_id, user_id, pending_holder_id, program_id, type,
                            bill_minor, currency, points, ledger_tx_id, local_date, invoice_no)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14)`,
        [a.businessId, a.branchId, a.staffId, a.deviceId, userId, holderId, prog.id, type, b.billMinor, prog.currency, pts, txId, today, b.invoiceNo || null],
      );
      await audit(c, { actorType: 'STAFF', actorId: a.staffId, businessId: a.businessId, action: `points.${type.toLowerCase()}`, entityId: txId, data: { points: pts, billMinor: b.billMinor }, ip });
      if (userId) {
        const bn = (await c.query(`SELECT name FROM businesses WHERE id = $1`, [a.businessId])).rows[0]?.name ?? '';
        await notify(c, userId, 'EARN', {
          ar: { title: `ربحت ${fmtPts(pts)} نقطة`, body: `من ${bn}` },
          en: { title: `You earned ${fmtPts(pts)} points`, body: `At ${bn}` },
        }, { transactionId: txId });
        // Mukafaah Points for the first bill anywhere, and the tier by total spend.
        await grantRule(c, this.ledger, 'FIRST_BILL', userId);
        await addSpend(c, this.ledger, userId, b.billMinor);
      }
      return this.earnResult(c, txId, false);
    });
  }

  private async earnResult(c: Tx, txId: string, replay: boolean) {
    const r = (
      await c.query(
        `SELECT v.type, v.points, v.bill_minor, v.currency, e.account_id, ab.balance
           FROM visits v
           JOIN ledger_entries e ON e.transaction_id = v.ledger_tx_id AND e.amount > 0
           JOIN account_balances ab ON ab.account_id = e.account_id
          WHERE v.ledger_tx_id = $1`,
        [txId],
      )
    ).rows[0];
    return {
      transactionId: txId,
      type: r.type,
      points: Number(r.points),
      billMinor: Number(r.bill_minor),
      currency: r.currency,
      newBalance: Number(r.balance),
      replayed: replay,
    };
  }

  // ---------- Spending points: the customer approves in the app ----------
  /** Points discount. Returns 202 with a request the customer approves. */
  @Post('redeem')
  @RequireStaff()
  async redeem(@Auth() a: StaffAuth, @Body() body: unknown, @IdemKey() key: string, @Res() reply: any) {
    const b = parse(zRedeem, body);
    const out = await this.db.tx(async (c) => {
      const m = await this.member(c, b);
      const prog = await this.redeemer.spendProgram(c, a.businessId, b.programId);
      const en = m.locale === 'en';
      return this.redeemer.createRequest(c, this.ctx(a), {
        userId: m.userId,
        kind: 'POINTS',
        title: en ? `Discount with ${fmtPts(b.points)} points` : `خصم بـ ${fmtPts(b.points)} نقطة`,
        points: b.points,
        valueMinor: pointsValueMinor(b.points, Number(prog.redeem_points_per_unit)),
        payload: { programId: prog.id },
        idemKey: `redeem:${a.staffId}:${key}`,
      });
    });
    return this.send(reply, { pending: true, body: out });
  }

  /** Completes a booking the shop already accepted (approval needed when it costs points). */
  @Post('bookings/:id/redeem')
  @RequireStaff()
  async redeemBooking(@Auth() a: StaffAuth, @Param('id') id: string, @Body() body: unknown, @IdemKey() key: string, @Res() reply: any) {
    const bid = parse(zUuid, id);
    const b = parse(zQrOnly, body);
    const out = await this.db.tx(async (c) => {
      const k = (
        await c.query(
          `SELECT k.*, o.points_cost, o.title, o.saving_minor AS offer_saving FROM offer_bookings k JOIN offers o ON o.id = k.offer_id
            WHERE k.id = $1 AND k.business_id = $2`,
          [bid, a.businessId],
        )
      ).rows[0];
      if (!k) throw Errors.notFound('Booking');
      if (k.status === 'REDEEMED') return { pending: false, body: { ok: true, replayed: true, booking: bookingJson(k) } };
      if (k.status !== 'ACCEPTED') throw new AppError(409, 'BOOKING_NOT_ACCEPTED', 'This booking is not accepted');
      const m = await this.member(c, b);
      if (m.userId !== k.user_id) throw new AppError(403, 'BOOKING_OTHER_CUSTOMER', 'This booking belongs to another customer');
      const cost = Number(k.points_cost);
      if (cost <= 0) {
        const r = await this.redeemer.executeBooking(c, this.redeemer.free(this.ctx(a), m.userId, `booking:${bid}:${key}`), bid, 0);
        return { pending: false, body: r };
      }
      const req = await this.redeemer.createRequest(c, this.ctx(a), {
        userId: m.userId,
        kind: 'BOOKING',
        title: k.title,
        points: cost,
        valueMinor: Number(k.saving_minor ?? k.offer_saving ?? 0),
        payload: { bookingId: bid },
        idemKey: `booking:${bid}:${key}`,
      });
      return { pending: true, body: req };
    });
    return this.send(reply, out);
  }

  /** Applies a walk-in offer (no booking needed); approval needed when it costs points. */
  @Post('offers/:id/apply')
  @RequireStaff()
  async applyOffer(@Auth() a: StaffAuth, @Param('id') id: string, @Body() body: unknown, @IdemKey() key: string, @Res() reply: any) {
    const oid = parse(zUuid, id);
    const b = parse(zQrOnly, body);
    const out = await this.db.tx(async (c) => {
      const o = (
        await c.query(
          `SELECT * FROM offers WHERE id = $1 AND business_id = $2 AND status = 'ACTIVE' AND NOT hidden_by_admin AND NOT requires_booking
              AND valid_from <= current_date AND (valid_to IS NULL OR valid_to >= current_date)`,
          [oid, a.businessId],
        )
      ).rows[0];
      if (!o) throw new AppError(404, 'OFFER_UNAVAILABLE', 'This offer is not available');
      const m = await this.member(c, b);
      const cost = Number(o.points_cost);
      if (cost <= 0) {
        const r = await this.redeemer.executeOffer(c, this.redeemer.free(this.ctx(a), m.userId, `offer:${oid}:${a.staffId}:${key}`), oid, 0);
        return { pending: false, body: r };
      }
      const req = await this.redeemer.createRequest(c, this.ctx(a), {
        userId: m.userId,
        kind: 'OFFER',
        title: o.title,
        points: cost,
        valueMinor: Number(o.saving_minor),
        payload: { offerId: oid },
        idemKey: `offer:${oid}:${a.staffId}:${key}`,
      });
      return { pending: true, body: req };
    });
    return this.send(reply, out);
  }

  /** Customer spends points on a reward from this shop's catalog (approval needed). */
  @Post('rewards/:id/redeem')
  @RequireStaff()
  async redeemReward(@Auth() a: StaffAuth, @Param('id') id: string, @Body() body: unknown, @IdemKey() key: string, @Res() reply: any) {
    const rid = parse(zUuid, id);
    const b = parse(zQrOnly, body);
    const out = await this.db.tx(async (c) => {
      const w = (await c.query(`SELECT * FROM rewards WHERE id = $1 AND business_id = $2 AND status = 'ACTIVE'`, [rid, a.businessId])).rows[0];
      if (!w) throw new AppError(404, 'REWARD_UNAVAILABLE', 'This reward is not available');
      const m = await this.member(c, b);
      const prog = await this.redeemer.spendProgram(c, a.businessId, null);
      const cost = Number(w.points_cost);
      return this.redeemer.createRequest(c, this.ctx(a), {
        userId: m.userId,
        kind: 'REWARD',
        title: w.title,
        points: cost,
        valueMinor: Number(w.value_minor) || pointsValueMinor(cost, Number(prog.redeem_points_per_unit)),
        payload: { rewardId: rid },
        idemKey: `reward:${rid}:${a.staffId}:${key}`,
      });
    });
    return this.send(reply, { pending: true, body: out });
  }

  /** Mukafaah Points at a Mukafaah Friends shop (approval needed). */
  @Post('mukafaah/redeem')
  @RequireStaff()
  async redeemMukafaah(@Auth() a: StaffAuth, @Body() body: unknown, @OptionalIdemKey() key: string | null, @Res() reply: any) {
    const b = parse(zMukafaah, body);
    const out = await this.db.tx(async (c) => {
      await this.redeemer.checkMukafaah(c, a.businessId, b.points);
      const m = await this.member(c, { userId: b.userId });
      const en = m.locale === 'en';
      return this.redeemer.createRequest(c, this.ctx(a), {
        userId: m.userId,
        kind: 'MUKAFAAH',
        title: en ? `${fmtPts(b.points)} Mukafaah Points` : `${fmtPts(b.points)} نقطة مكافأة`,
        points: b.points,
        valueMinor: pointsValueMinor(b.points, 100),
        payload: { billMinor: b.billMinor ?? null },
        idemKey: key ? `mukafaah:${a.staffId}:${key}` : null,
      });
    });
    return this.send(reply, { pending: true, body: out });
  }

  @Get('redeem-requests/:id')
  @RequireStaff()
  async requestStatus(@Auth() a: StaffAuth, @Param('id') id: string) {
    return this.redeemer.statusForBusiness(this.db, a.businessId, parse(zUuid, id));
  }

  @Post('redeem-requests/:id/cancel')
  @HttpCode(200)
  @RequireStaff()
  async cancelRequest(@Auth() a: StaffAuth, @Param('id') id: string, @ClientIp() ip: string) {
    const rid = parse(zUuid, id);
    return this.db.tx(async (c) => {
      const r = await this.redeemer.cancel(c, a.businessId, rid);
      await audit(c, { actorType: 'STAFF', actorId: a.staffId, businessId: a.businessId, action: 'redeem.cancel', entityId: rid, ip });
      return r;
    });
  }

  /** New bookings, orders, approvals and ratings for the shop (the app polls this). */
  @Get('alerts')
  @RequireStaff()
  async alerts(@Auth() a: StaffAuth, @Query() q: unknown) {
    const f = parse(zAfter, q);
    return listAlerts(this.db, a.businessId, f.after);
  }

  @Get('shift')
  @RequireStaff()
  async shift(@Auth() a: StaffAuth) {
    const r = await this.db.query(
      `SELECT v.ledger_tx_id, v.type, v.bill_minor, v.points, v.currency, v.created_at, v.voided_by_tx_id,
              COALESCE(u.phone_last4, h.phone_last4) AS last4,
              s.void_window_min,
              (v.created_at > now() - make_interval(mins => s.void_window_min)) AS can_void
         FROM visits v
         JOIN staff s ON s.id = v.staff_id
         LEFT JOIN users u ON u.id = v.user_id
         LEFT JOIN pending_holders h ON h.id = v.pending_holder_id
        WHERE v.staff_id = $1 AND v.created_at > now() - interval '16 hours'
        ORDER BY v.created_at DESC LIMIT 100`,
      [a.staffId],
    );
    return r.rows.map((x) => ({
      transactionId: x.ledger_tx_id,
      type: x.type,
      billMinor: Number(x.bill_minor),
      points: Number(x.points),
      currency: x.currency,
      createdAt: x.created_at,
      phoneLast4: x.last4,
      voided: !!x.voided_by_tx_id,
      canVoid: !x.voided_by_tx_id && x.can_void,
    }));
  }

  @Post('transactions/:id/void')
  @HttpCode(200)
  @RequireStaff()
  async void(@Auth() a: StaffAuth, @Param('id') id: string, @ClientIp() ip: string) {
    const txId = parse(zUuid, id);
    return this.db.tx(async (c) => {
      const v = (
        await c.query(
          `SELECT v.*, s.void_window_min FROM visits v JOIN staff s ON s.id = v.staff_id
            WHERE v.ledger_tx_id = $1 AND v.staff_id = $2 FOR UPDATE OF v`,
          [txId, a.staffId],
        )
      ).rows[0];
      if (!v) throw Errors.notFound('Transaction');
      if (v.voided_by_tx_id) throw new AppError(409, 'ALREADY_REVERSED');
      if (Date.now() - new Date(v.created_at).getTime() > v.void_window_min * 60_000) {
        throw new AppError(403, 'VOID_WINDOW_PASSED', 'Ask the owner to reverse this transaction');
      }
      const rev = await this.ledger.reverse(c, txId, 'VOID', {
        idempotencyKey: `void:${txId}`,
        businessId: a.businessId,
        branchId: a.branchId,
        staffId: a.staffId,
        deviceId: a.deviceId,
        reason: 'Cashier void',
      });
      await c.query(`UPDATE visits SET voided_by_tx_id = $2 WHERE id = $1`, [v.id, rev]);
      // A voided bill no longer counts toward the member's tier.
      if (v.type === 'EARN' && v.user_id) await addSpend(c, this.ledger, v.user_id, -Number(v.bill_minor));
      await audit(c, { actorType: 'STAFF', actorId: a.staffId, businessId: a.businessId, action: 'ledger.void', entityId: txId, ip });
      return { ok: true };
    });
  }
}

@Module({ imports: [RedeemModule], controllers: [CashierController] })
export class CashierModule {}
