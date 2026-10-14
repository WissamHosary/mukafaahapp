import { randomUUID } from 'node:crypto';
import { Controller, Get, Global, HttpCode, Injectable, Module, Param, Post } from '@nestjs/common';
import { audit } from '../platform/audit.js';
import { Auth, RequireUser, type UserAuth } from '../platform/auth.js';
import { Db, type Queryable, type Tx } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zUuid } from '../platform/validation.js';
import { LedgerService } from './ledger.js';
import { mukafaahProgramId } from './mukafaah.js';
import { alertBusiness, bookingCode, bookingJson, fmtPts, mediaUrl, notify, pointsValueMinor } from './shared.js';

/*
 * Spending points needs the customer's approval in the app. The cashier's
 * spend endpoints validate and create a redeem request; the customer approves
 * it and the original ledger posting runs then (same transaction, balance
 * checked again). Ledger idempotency keys come from the request id, so an
 * approval can never post twice.
 */

export type RedeemKind = 'POINTS' | 'OFFER' | 'REWARD' | 'BOOKING' | 'MUKAFAAH';
export const REQUEST_TTL_SEC = 120;

/** Where the spend happens (from the cashier's token). */
export interface CounterCtx {
  businessId: string;
  branchId: string | null;
  staffId: string | null;
  deviceId: string | null;
}
interface SpendCtx extends CounterCtx {
  userId: string;
  /** Ledger idempotency key for the REDEEM posting. */
  idem: string;
  requestId: string | null;
}

type RefType = 'REWARD' | 'OFFER' | 'MUKAFAAH';

const isExpired = (row: any) => row.status === 'PENDING' && new Date(row.expires_at).getTime() <= Date.now();
export const requestStatus = (row: any): string => (isExpired(row) ? 'EXPIRED' : row.status);

@Injectable()
export class RedeemService {
  constructor(private readonly ledger: LedgerService) {}

  // ---------- Checks shared by "create request" and "execute" ----------
  async assertStaffCanRedeem(c: Tx, staffId: string | null) {
    if (!staffId) return;
    const s = (await c.query(`SELECT can_redeem, active FROM staff WHERE id = $1`, [staffId])).rows[0];
    if (!s?.can_redeem || !s.active) throw new AppError(403, 'REDEEM_NOT_ALLOWED', 'You are not allowed to redeem');
  }

  /** The program points are spent from: [programId] when given (must be accepted here), else the shop's own. */
  async spendProgram(c: Tx, businessId: string, programId: string | null) {
    const prog = programId
      ? (
          await c.query(
            `SELECT p.*, b.time_zone, b.currency FROM programs p
               JOIN program_members pm ON pm.program_id = p.id AND pm.business_id = $2 AND pm.active AND pm.can_redeem
               JOIN businesses b ON b.id = $2
              WHERE p.id = $1 AND p.status = 'ACTIVE' FOR SHARE OF pm`,
            [programId, businessId],
          )
        ).rows[0]
      : (
          await c.query(
            `SELECT p.*, b.time_zone, b.currency FROM businesses b JOIN programs p ON p.id = b.earning_program_id
              JOIN program_members pm ON pm.program_id = p.id AND pm.business_id = b.id AND pm.active AND pm.can_redeem
             WHERE b.id = $1`,
            [businessId],
          )
        ).rows[0];
    if (!prog) throw new AppError(403, 'NOT_ACCEPTED_HERE', 'These points cannot be used at this business');
    return prog;
  }

  /** Mukafaah Points at a Friends shop. */
  async mukafaahProgram(c: Tx, businessId: string) {
    const prog = await mukafaahProgramId(c);
    const r = (
      await c.query(
        `SELECT p.*, b.time_zone, b.currency, b.friends_enabled, b.friends_max_points
           FROM programs p JOIN businesses b ON b.id = $2 WHERE p.id = $1`,
        [prog, businessId],
      )
    ).rows[0];
    if (!r) throw new AppError(500, 'NO_PLATFORM_PROGRAM');
    return r;
  }

  async balance(c: Tx, programId: string, userId: string): Promise<number> {
    const r = await c.query(
      `SELECT ab.balance FROM ledger_accounts a JOIN account_balances ab ON ab.account_id = a.id
        WHERE a.program_id = $1 AND a.owner_type = 'CUSTOMER' AND a.owner_id = $2`,
      [programId, userId],
    );
    return Number(r.rows[0]?.balance ?? 0);
  }

  async assertBalance(c: Tx, programId: string, userId: string, points: number) {
    if ((await this.balance(c, programId, userId)) < points) throw new AppError(409, 'INSUFFICIENT_BALANCE', 'Not enough points');
  }

  /** Posts the REDEEM (customer -> shop's redeemed account) and records the visit. */
  private async post(c: Tx, ctx: SpendCtx, prog: any, points: number, ref: { type: RefType; id: string | null } | null) {
    const wallet = await this.ledger.account(c, prog.id, 'CUSTOMER', ctx.userId);
    const redeemed = await this.ledger.account(c, prog.id, 'BUSINESS_REDEEMED', ctx.businessId);
    const txId = await this.ledger.post(c, {
      type: 'REDEEM',
      programId: prog.id,
      idempotencyKey: ctx.idem,
      businessId: ctx.businessId,
      branchId: ctx.branchId,
      staffId: ctx.staffId,
      deviceId: ctx.deviceId,
      userId: ctx.userId,
      reason: ref?.type ?? null,
      entries: [
        { accountId: wallet, amount: -points },
        { accountId: redeemed, amount: points },
      ],
    });
    const today = (await c.query(`SELECT (now() AT TIME ZONE $1)::date::text AS d`, [prog.time_zone])).rows[0].d;
    await c.query(
      `INSERT INTO visits(business_id, branch_id, staff_id, device_id, user_id, program_id, type, bill_minor, currency, points,
                          ledger_tx_id, local_date, ref_type, ref_id)
       VALUES ($1,$2,$3,$4,$5,$6,'REDEEM',0,$7,$8,$9,$10,$11,$12)`,
      [ctx.businessId, ctx.branchId, ctx.staffId, ctx.deviceId, ctx.userId, prog.id, prog.currency, points, txId, today, ref?.type ?? null, ref?.id ?? null],
    );
    const bal = (await c.query(`SELECT balance FROM account_balances WHERE account_id = $1`, [wallet])).rows[0];
    return { txId, newBalance: Number(bal.balance), redeemPerUnit: Number(prog.redeem_points_per_unit), currency: String(prog.currency) };
  }

  private async shopName(c: Tx, businessId: string): Promise<string> {
    return (await c.query(`SELECT name FROM businesses WHERE id = $1`, [businessId])).rows[0]?.name ?? '';
  }

  // ---------- Executors (the original counter operations) ----------
  async executePoints(c: Tx, ctx: SpendCtx, points: number, programId: string) {
    await this.assertStaffCanRedeem(c, ctx.staffId);
    const prog = await this.spendProgram(c, ctx.businessId, programId);
    const r = await this.post(c, ctx, prog, points, null);
    await audit(c, { actorType: 'STAFF', actorId: ctx.staffId, businessId: ctx.businessId, action: 'points.redeem', entityId: r.txId, data: { points, requestId: ctx.requestId } });
    await notify(c, ctx.userId, 'REDEEM', {
      ar: { title: `صرفت ${fmtPts(points)} نقطة`, body: prog.name },
      en: { title: `You used ${fmtPts(points)} points`, body: prog.name },
    });
    return {
      transactionId: r.txId,
      points,
      discountMinor: Math.floor((points * 100) / r.redeemPerUnit),
      currency: r.currency,
      newBalance: r.newBalance,
      replayed: false,
    };
  }

  async executeOffer(c: Tx, ctx: SpendCtx, offerId: string, cost: number) {
    const o = (
      await c.query(
        `SELECT * FROM offers WHERE id = $1 AND business_id = $2 AND status = 'ACTIVE' AND NOT hidden_by_admin AND NOT requires_booking
            AND valid_from <= current_date AND (valid_to IS NULL OR valid_to >= current_date) FOR UPDATE`,
        [offerId, ctx.businessId],
      )
    ).rows[0];
    if (!o) throw new AppError(404, 'OFFER_UNAVAILABLE', 'This offer is not available');
    const used = (
      await c.query(`SELECT count(*)::int AS n FROM offer_bookings WHERE offer_id = $1 AND user_id = $2 AND status = 'REDEEMED'`, [offerId, ctx.userId])
    ).rows[0].n;
    if (used >= o.max_per_customer) throw new AppError(409, 'OFFER_LIMIT_REACHED', 'The customer already used this offer');
    if (o.total_limit) {
      const all = (await c.query(`SELECT count(*)::int AS n FROM offer_bookings WHERE offer_id = $1 AND status = 'REDEEMED'`, [offerId])).rows[0].n;
      if (all >= o.total_limit) throw new AppError(409, 'OFFER_SOLD_OUT', 'This offer has run out');
    }
    let txId: string | null = null;
    let newBalance: number | null = null;
    if (cost > 0) {
      await this.assertStaffCanRedeem(c, ctx.staffId);
      const prog = await this.spendProgram(c, ctx.businessId, null);
      const r = await this.post(c, ctx, prog, cost, { type: 'OFFER', id: offerId });
      txId = r.txId;
      newBalance = r.newBalance;
    }
    let recorded = false;
    for (let i = 0; i < 6 && !recorded; i++) {
      const ins = await c.query(
        `INSERT INTO offer_bookings(offer_id, business_id, user_id, status, code, decided_at, redeemed_at, redeemed_staff_id, redeem_tx_id, saving_minor)
         VALUES ($1,$2,$3,'REDEEMED',$4, now(), now(), $5, $6, $7)
         ON CONFLICT (business_id, code) DO NOTHING RETURNING id`,
        [offerId, ctx.businessId, ctx.userId, bookingCode(), ctx.staffId, txId, o.saving_minor],
      );
      recorded = !!ins.rowCount;
    }
    if (!recorded) throw new AppError(500, 'BOOKING_CODE');
    await notify(c, ctx.userId, 'OFFER_USED', {
      ar: { title: 'استعملت العرض', body: o.title },
      en: { title: 'Offer used', body: o.title },
    });
    await audit(c, { actorType: 'STAFF', actorId: ctx.staffId, businessId: ctx.businessId, action: 'offer.apply', entityId: offerId, data: { requestId: ctx.requestId } });
    return { ok: true, title: o.title as string, pointsSpent: cost, newBalance, transactionId: txId };
  }

  async executeReward(c: Tx, ctx: SpendCtx, rewardId: string, cost: number) {
    const w = (
      await c.query(`SELECT * FROM rewards WHERE id = $1 AND business_id = $2 AND status = 'ACTIVE' FOR UPDATE`, [rewardId, ctx.businessId])
    ).rows[0];
    if (!w) throw new AppError(404, 'REWARD_UNAVAILABLE', 'This reward is not available');
    if (w.stock !== null && w.stock <= 0) throw new AppError(409, 'REWARD_OUT_OF_STOCK', 'This reward is out of stock');
    await this.assertStaffCanRedeem(c, ctx.staffId);
    const prog = await this.spendProgram(c, ctx.businessId, null);
    const r = await this.post(c, ctx, prog, cost, { type: 'REWARD', id: rewardId });
    await c.query(
      `INSERT INTO reward_redemptions(reward_id, business_id, user_id, staff_id, ledger_tx_id, points, value_minor)
       VALUES ($1,$2,$3,$4,$5,$6,$7)`,
      [rewardId, ctx.businessId, ctx.userId, ctx.staffId, r.txId, cost, Number(w.value_minor) || pointsValueMinor(cost, r.redeemPerUnit)],
    );
    if (w.stock !== null) await c.query(`UPDATE rewards SET stock = stock - 1, updated_at = now() WHERE id = $1`, [rewardId]);
    await notify(c, ctx.userId, 'REWARD', {
      ar: { title: 'استلمت مكافأتك', body: `${w.title} مقابل ${fmtPts(cost)} نقطة` },
      en: { title: 'Reward redeemed', body: `${w.title} for ${fmtPts(cost)} points` },
    });
    await audit(c, { actorType: 'STAFF', actorId: ctx.staffId, businessId: ctx.businessId, action: 'reward.redeem', entityId: r.txId, data: { rewardId, points: cost, requestId: ctx.requestId } });
    return { ok: true, replayed: false, title: w.title as string, pointsSpent: cost, newBalance: r.newBalance, transactionId: r.txId };
  }

  async executeBooking(c: Tx, ctx: SpendCtx, bookingId: string, cost: number) {
    const k = (
      await c.query(
        `SELECT k.*, o.points_cost, o.title FROM offer_bookings k JOIN offers o ON o.id = k.offer_id
          WHERE k.id = $1 AND k.business_id = $2 FOR UPDATE OF k`,
        [bookingId, ctx.businessId],
      )
    ).rows[0];
    if (!k) throw Errors.notFound('Booking');
    if (k.user_id !== ctx.userId) throw new AppError(403, 'BOOKING_OTHER_CUSTOMER', 'This booking belongs to another customer');
    if (k.status === 'REDEEMED') return { ok: true, replayed: true, newBalance: null as number | null, booking: bookingJson(k) };
    if (k.status !== 'ACCEPTED') throw new AppError(409, 'BOOKING_NOT_ACCEPTED', 'This booking is not accepted');
    let txId: string | null = null;
    let newBalance: number | null = null;
    if (cost > 0) {
      await this.assertStaffCanRedeem(c, ctx.staffId);
      const prog = await this.spendProgram(c, ctx.businessId, null);
      const r = await this.post(c, ctx, prog, cost, { type: 'OFFER', id: k.offer_id });
      txId = r.txId;
      newBalance = r.newBalance;
    }
    const upd = (
      await c.query(
        `UPDATE offer_bookings SET status = 'REDEEMED', redeemed_at = now(), redeemed_staff_id = $2, redeem_tx_id = $3, updated_at = now()
          WHERE id = $1 RETURNING *`,
        [bookingId, ctx.staffId, txId],
      )
    ).rows[0];
    await notify(c, k.user_id, 'OFFER_USED', {
      ar: { title: 'استعملت العرض', body: k.title },
      en: { title: 'Offer used', body: k.title },
    });
    await audit(c, { actorType: 'STAFF', actorId: ctx.staffId, businessId: ctx.businessId, action: 'booking.redeem', entityId: bookingId, data: { requestId: ctx.requestId } });
    return { ok: true, replayed: false, newBalance, booking: bookingJson({ ...upd, offer_title: k.title, points_cost: k.points_cost }) };
  }

  /** Validates a Mukafaah Points spend at this shop (Friends only, per-bill limit). */
  async checkMukafaah(c: Tx, businessId: string, points: number) {
    const prog = await this.mukafaahProgram(c, businessId);
    if (!prog.friends_enabled) throw new AppError(403, 'NOT_A_FRIEND', 'This shop does not accept Mukafaah Points');
    if (points > Number(prog.friends_max_points)) {
      throw new AppError(400, 'OVER_LIMIT', `At most ${fmtPts(Number(prog.friends_max_points))} Mukafaah Points per bill here`, {
        maxPoints: Number(prog.friends_max_points),
      });
    }
    return prog;
  }

  async executeMukafaah(c: Tx, ctx: SpendCtx, points: number, billMinor: number | null) {
    await this.assertStaffCanRedeem(c, ctx.staffId);
    const prog = await this.checkMukafaah(c, ctx.businessId, points);
    const r = await this.post(c, ctx, prog, points, { type: 'MUKAFAAH', id: null });
    const shop = await this.shopName(c, ctx.businessId);
    await audit(c, { actorType: 'STAFF', actorId: ctx.staffId, businessId: ctx.businessId, action: 'mukafaah.redeem', entityId: r.txId, data: { points, billMinor, requestId: ctx.requestId } });
    await notify(c, ctx.userId, 'REDEEM', {
      ar: { title: `صرفت ${fmtPts(points)} نقطة مكافأة`, body: shop },
      en: { title: `You used ${fmtPts(points)} Mukafaah Points`, body: shop },
    });
    return {
      transactionId: r.txId,
      points,
      discountMinor: pointsValueMinor(points, r.redeemPerUnit),
      currency: r.currency,
      newBalance: r.newBalance,
      billMinor,
      replayed: false,
    };
  }

  /** Runs a free counter action right away (no points spent, no approval needed). */
  free(ctx: CounterCtx, userId: string, idem: string): SpendCtx {
    return { ...ctx, userId, idem, requestId: null };
  }

  // ---------- Requests ----------
  /**
   * Creates a request the customer approves in the app. It is checked first by
   * running the real operation and rolling it back, so the cashier gets the
   * same errors as before (balance, limits, offer rules).
   */
  async createRequest(
    c: Tx,
    ctx: CounterCtx,
    r: { userId: string; kind: RedeemKind; title: string; points: number; valueMinor: number; payload: Record<string, unknown>; idemKey: string | null },
  ) {
    if (r.idemKey) {
      const prior = (await c.query(`SELECT * FROM redeem_requests WHERE idem_key = $1`, [r.idemKey])).rows[0];
      if (prior) return this.requestJson(prior, ctx.businessId);
    }
    await c.query('SAVEPOINT redeem_check');
    try {
      await this.execute(c, {
        id: `check-${randomUUID()}`,
        user_id: r.userId,
        business_id: ctx.businessId,
        branch_id: ctx.branchId,
        staff_id: ctx.staffId,
        device_id: ctx.deviceId,
        kind: r.kind,
        points: r.points,
        payload: r.payload,
      });
    } finally {
      await c.query('ROLLBACK TO SAVEPOINT redeem_check');
    }
    let row = (
      await c.query(
        `INSERT INTO redeem_requests(user_id, business_id, branch_id, staff_id, device_id, kind, title, points, value_minor, payload, idem_key, expires_at)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11, now() + make_interval(secs => $12))
         ON CONFLICT (idem_key) DO NOTHING RETURNING *`,
        [
          r.userId,
          ctx.businessId,
          ctx.branchId,
          ctx.staffId,
          ctx.deviceId,
          r.kind,
          r.title,
          r.points,
          Math.min(Math.max(0, Math.round(r.valueMinor)), 2_000_000_000),
          JSON.stringify(r.payload),
          r.idemKey,
          REQUEST_TTL_SEC,
        ],
      )
    ).rows[0];
    if (!row) {
      // A parallel retry with the same Idempotency-Key made it first.
      row = (await c.query(`SELECT * FROM redeem_requests WHERE idem_key = $1`, [r.idemKey])).rows[0];
      return this.requestJson(row, ctx.businessId);
    }
    const shop = await this.shopName(c, ctx.businessId);
    await notify(
      c,
      r.userId,
      'REDEEM_REQUEST',
      {
        ar: { title: 'وافق على صرف النقاط', body: `${shop}: ${r.title} (${fmtPts(r.points)} نقطة)` },
        en: { title: 'Approve your points', body: `${shop}: ${r.title} (${fmtPts(r.points)} points)` },
      },
      { requestId: row.id, kind: r.kind, points: r.points, shopId: ctx.businessId },
    );
    return this.requestJson(row, ctx.businessId);
  }

  private requestJson(row: any, businessId: string) {
    if (!row || row.business_id !== businessId) throw new AppError(409, 'DUPLICATE_REQUEST', 'Request already processed');
    return { requestId: row.id as string, status: requestStatus(row), expiresAt: row.expires_at, title: row.title as string, points: Number(row.points) };
  }

  /** Runs the posting the request stands for. Throws AppError when it can't be done. */
  async execute(c: Tx, row: any): Promise<Record<string, unknown>> {
    const ctx: SpendCtx = {
      userId: row.user_id,
      businessId: row.business_id,
      branchId: row.branch_id,
      staffId: row.staff_id,
      deviceId: row.device_id,
      idem: `redeem-request:${row.id}`,
      requestId: row.id,
    };
    const points = Number(row.points);
    const p = (row.payload ?? {}) as Record<string, any>;
    switch (row.kind as RedeemKind) {
      case 'POINTS':
        return this.executePoints(c, ctx, points, String(p.programId));
      case 'OFFER':
        return this.executeOffer(c, ctx, String(p.offerId), points);
      case 'REWARD':
        return this.executeReward(c, ctx, String(p.rewardId), points);
      case 'BOOKING':
        return this.executeBooking(c, ctx, String(p.bookingId), points);
      case 'MUKAFAAH':
        return this.executeMukafaah(c, ctx, points, p.billMinor == null ? null : Number(p.billMinor));
      default:
        throw new AppError(500, 'UNKNOWN_REQUEST_KIND');
    }
  }

  /** What the cashier sees while waiting for the customer. */
  async statusForBusiness(c: Queryable, businessId: string, id: string) {
    const row = (await c.query(`SELECT * FROM redeem_requests WHERE id = $1 AND business_id = $2`, [id, businessId])).rows[0];
    if (!row) throw Errors.notFound('Request');
    return {
      id: row.id as string,
      status: requestStatus(row),
      kind: row.kind as string,
      title: row.title as string,
      points: Number(row.points),
      expiresAt: row.expires_at,
      ...(row.result ? { result: row.result } : {}),
      ...(row.error ? { error: row.error as string } : {}),
    };
  }

  async cancel(c: Tx, businessId: string, id: string) {
    const r = await c.query(
      `UPDATE redeem_requests SET status = 'DECLINED', error = 'CANCELLED', decided_at = now()
        WHERE id = $1 AND business_id = $2 AND status = 'PENDING' RETURNING id`,
      [id, businessId],
    );
    if (!r.rowCount) {
      const row = (await c.query(`SELECT status, expires_at FROM redeem_requests WHERE id = $1 AND business_id = $2`, [id, businessId])).rows[0];
      if (!row) throw Errors.notFound('Request');
      throw new AppError(409, 'REQUEST_NOT_PENDING', 'This request was already handled');
    }
    return { ok: true, id, status: 'DECLINED', error: 'CANCELLED' };
  }

  async approve(c: Tx, userId: string, id: string) {
    const row = (await c.query(`SELECT * FROM redeem_requests WHERE id = $1 AND user_id = $2 FOR UPDATE`, [id, userId])).rows[0];
    if (!row) throw Errors.notFound('Request');
    if (row.status !== 'PENDING') {
      return { status: row.status as string, ...(row.result ? { result: row.result } : {}), ...(row.error ? { error: row.error as string } : {}) };
    }
    if (isExpired(row)) {
      await c.query(`UPDATE redeem_requests SET status = 'EXPIRED', error = 'EXPIRED', decided_at = now() WHERE id = $1`, [id]);
      return { status: 'EXPIRED', error: 'EXPIRED' };
    }
    await c.query('SAVEPOINT redeem_exec');
    let result: Record<string, unknown>;
    try {
      result = await this.execute(c, row);
      await c.query('RELEASE SAVEPOINT redeem_exec');
    } catch (e) {
      await c.query('ROLLBACK TO SAVEPOINT redeem_exec');
      if (!(e instanceof AppError)) throw e;
      await c.query(`UPDATE redeem_requests SET status = 'FAILED', error = $2, decided_at = now() WHERE id = $1`, [id, e.code]);
      return { status: 'FAILED', error: e.code };
    }
    await c.query(`UPDATE redeem_requests SET status = 'APPROVED', result = $2, decided_at = now() WHERE id = $1`, [id, JSON.stringify(result)]);
    const who = await this.customerLabel(c, userId);
    await alertBusiness(
      c,
      row.business_id,
      'REDEEM_APPROVED',
      {
        ar: { title: `وافق الزبون: ${row.title}`, body: `${who} · ${fmtPts(Number(row.points))} نقطة` },
        en: { title: `Approved: ${row.title}`, body: `${who} · ${fmtPts(Number(row.points))} points` },
      },
      row.id,
    );
    await audit(c, { actorType: 'USER', actorId: userId, businessId: row.business_id, action: 'redeem.approve', entityId: row.id });
    return { status: 'APPROVED', result };
  }

  async decline(c: Tx, userId: string, id: string) {
    const row = (await c.query(`SELECT * FROM redeem_requests WHERE id = $1 AND user_id = $2 FOR UPDATE`, [id, userId])).rows[0];
    if (!row) throw Errors.notFound('Request');
    if (row.status !== 'PENDING') return { status: row.status as string, ...(row.error ? { error: row.error as string } : {}) };
    if (isExpired(row)) {
      await c.query(`UPDATE redeem_requests SET status = 'EXPIRED', error = 'EXPIRED', decided_at = now() WHERE id = $1`, [id]);
      return { status: 'EXPIRED', error: 'EXPIRED' };
    }
    await c.query(`UPDATE redeem_requests SET status = 'DECLINED', error = 'DECLINED', decided_at = now() WHERE id = $1`, [id]);
    const who = await this.customerLabel(c, userId);
    await alertBusiness(
      c,
      row.business_id,
      'REDEEM_DECLINED',
      {
        ar: { title: `رفض الزبون: ${row.title}`, body: `${who} · ${fmtPts(Number(row.points))} نقطة` },
        en: { title: `Declined: ${row.title}`, body: `${who} · ${fmtPts(Number(row.points))} points` },
      },
      row.id,
    );
    await audit(c, { actorType: 'USER', actorId: userId, businessId: row.business_id, action: 'redeem.decline', entityId: row.id });
    return { status: 'DECLINED', error: 'DECLINED' };
  }

  private async customerLabel(c: Tx, userId: string) {
    const u = (await c.query(`SELECT name, phone_last4 FROM users WHERE id = $1`, [userId])).rows[0];
    return u?.name || `•••• ${u?.phone_last4 ?? ''}`;
  }
}

/** Customer side: requests waiting for approval, approve, decline. */
@Controller('v1/customer/redeem-requests')
@RequireUser()
export class CustomerRedeemController {
  constructor(
    private readonly db: Db,
    private readonly redeem: RedeemService,
  ) {}

  @Get('pending')
  async pending(@Auth() a: UserAuth) {
    const r = await this.db.query(
      `SELECT q.id, q.kind, q.title, q.points, q.value_minor, q.expires_at, b.id AS shop_id, b.name AS shop_name, b.logo_media_id
         FROM redeem_requests q JOIN businesses b ON b.id = q.business_id
        WHERE q.user_id = $1 AND q.status = 'PENDING' AND q.expires_at > now()
        ORDER BY q.created_at DESC LIMIT 20`,
      [a.userId],
    );
    return {
      requests: r.rows.map((x) => ({
        id: x.id,
        kind: x.kind,
        title: x.title,
        points: Number(x.points),
        valueMinor: Number(x.value_minor),
        shop: { id: x.shop_id, name: x.shop_name, logoUrl: mediaUrl(x.logo_media_id) },
        expiresAt: x.expires_at,
      })),
    };
  }

  @Post(':id/approve')
  @HttpCode(200)
  async approve(@Auth() a: UserAuth, @Param('id') id: string) {
    const rid = parse(zUuid, id);
    return this.db.tx((c) => this.redeem.approve(c, a.userId, rid));
  }

  @Post(':id/decline')
  @HttpCode(200)
  async decline(@Auth() a: UserAuth, @Param('id') id: string) {
    const rid = parse(zUuid, id);
    return this.db.tx((c) => this.redeem.decline(c, a.userId, rid));
  }
}

@Global()
@Module({ providers: [RedeemService], exports: [RedeemService], controllers: [CustomerRedeemController] })
export class RedeemModule {}
