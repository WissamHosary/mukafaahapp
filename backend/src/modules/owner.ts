import { Body, Controller, Get, HttpCode, Module, Param, Patch, Post, Put, Query } from '@nestjs/common';
import { randomBytes } from 'node:crypto';
import { hash } from '@node-rs/argon2';
import { z } from 'zod';
import { audit } from '../platform/audit.js';
import { Auth, ClientIp, RequireOwner, RequireUser, type OwnerAuth, type UserAuth } from '../platform/auth.js';
import { CryptoService } from '../platform/crypto.js';
import { Db, type Tx } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zUuid } from '../platform/validation.js';
import { LedgerService } from './ledger.js';
import { addSpend } from './mukafaah.js';
import { getSetting, listAlerts } from './shared.js';


const zOnboard = z.strictObject({
  businessName: z.string().trim().min(2).max(80),
  category: z.string().regex(/^[A-Z0-9_]{2,40}$/).default('OTHER'),
  branchName: z.string().trim().min(1).max(80).default('Main branch'),
  earnPointsPerUnit: z.number().int().min(0).max(10000).default(10),
  redeemPointsPerUnit: z.number().int().min(1).max(100000).default(100),
  whatsapp: z.string().max(20).optional(),
});
/** The owner sets the shop's loyalty %: points back as % of each bill (100 points = $1). */
const zProgram = z.strictObject({
  earnPercent: z.number().int().min(0).max(100).optional(),
  // Older app builds send points per unit directly.
  earnPointsPerUnit: z.number().int().min(0).max(10000).optional(),
  redeemPointsPerUnit: z.number().int().min(1).max(100000).optional(),
  minBillMinor: z.number().int().min(0).max(1_000_000_000).optional(),
});

/** Creates a shop with its main branch and In-Store program (used by Mukafaah Manager). */
export async function createShop(
  c: Tx,
  o: { ownerUserId: string; name: string; category: string; branchName: string; earnPercent: number; addedBy?: string },
) {
  const exists = await c.query(`SELECT 1 FROM businesses WHERE owner_user_id = $1`, [o.ownerUserId]);
  if (exists.rowCount) throw Errors.conflict('BUSINESS_EXISTS', 'This phone already owns a shop');
  const biz = (
    await c.query(`INSERT INTO businesses(owner_user_id, name, category, added_by) VALUES ($1,$2,$3,$4) RETURNING id`, [
      o.ownerUserId,
      o.name,
      o.category,
      o.addedBy ?? null,
    ])
  ).rows[0];
  await c.query(`INSERT INTO branches(business_id, name) VALUES ($1,$2)`, [biz.id, o.branchName]);
  const prog = (
    await c.query(
      `INSERT INTO programs(type, name, owner_business_id, earn_points_per_unit, redeem_points_per_unit)
       VALUES ('IN_STORE', $1, $2, $3, 100) RETURNING id`,
      [o.name, biz.id, o.earnPercent],
    )
  ).rows[0];
  await c.query(`INSERT INTO program_members(program_id, business_id) VALUES ($1,$2)`, [prog.id, biz.id]);
  await c.query(`UPDATE businesses SET earning_program_id = $2 WHERE id = $1`, [biz.id, prog.id]);
  return biz.id as string;
}
const zStaff = z.strictObject({
  name: z.string().trim().min(1).max(60),
  branchId: zUuid,
  pin: z.string().regex(/^\d{4,6}$/),
});
const zStaffPatch = z.strictObject({
  active: z.boolean().optional(),
  pin: z.string().regex(/^\d{4,6}$/).optional(),
  maxBillMinor: z.number().int().min(0).max(1_000_000_000).optional(),
  maxPointsTx: z.number().int().min(0).max(100_000_000).optional(),
  maxPointsDay: z.number().int().min(0).max(1_000_000_000).optional(),
  maxPrepointsDayPerPhone: z.number().int().min(0).max(100_000_000).optional(),
  canRedeem: z.boolean().optional(),
  voidWindowMin: z.number().int().min(0).max(1440).optional(),
});
const zBranch = z.strictObject({ name: z.string().trim().min(1).max(80) });
const zPairing = z.strictObject({ branchId: zUuid });
const zFilter = z.object({
  from: z.iso.date().optional(),
  to: z.iso.date().optional(),
  branchId: zUuid.optional(),
  staffId: zUuid.optional(),
  programId: zUuid.optional(),
});
const zReverse = z.strictObject({ reason: z.string().trim().min(3).max(200) });
const zAfter = z.object({ after: z.coerce.number().int().min(0).optional() });

@Controller('v1/business/onboarding')
export class OnboardingController {
  constructor(private readonly db: Db) {}

  /** Shops are added by Mukafaah in Mukafaah Manager; owners can't sign up themselves. */
  @Post()
  @RequireUser()
  async onboard(@Body() body: unknown) {
    parse(zOnboard, body);
    throw new AppError(403, 'ADDED_BY_MUKAFAAH', 'Shops are added by Mukafaah. Contact us to join.');
  }
}

@Controller('v1/business/manage')
@RequireOwner()
export class OwnerController {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
    private readonly ledger: LedgerService,
  ) {}

  @Get('me')
  async me(@Auth() a: OwnerAuth) {
    const biz = await this.db.one(
      `SELECT b.id, b.name, b.category, b.currency, b.time_zone, b.whatsapp,
              p.id AS program_id, p.type AS program_type, p.name AS program_name,
              p.earn_points_per_unit, p.redeem_points_per_unit, p.min_bill_minor
         FROM businesses b JOIN programs p ON p.id = b.earning_program_id
        WHERE b.id = $1`,
      [a.businessId],
    );
    const branches = await this.db.query(`SELECT id, name FROM branches WHERE business_id = $1 ORDER BY created_at`, [
      a.businessId,
    ]);
    const memberships = await this.db.query(
      `SELECT p.id, p.type, p.name, pm.can_earn, pm.can_redeem, pm.active
         FROM program_members pm JOIN programs p ON p.id = pm.program_id
        WHERE pm.business_id = $1 ORDER BY p.type`,
      [a.businessId],
    );
    return {
      id: biz.id,
      name: biz.name,
      category: biz.category,
      currency: biz.currency,
      timeZone: biz.time_zone,
      whatsapp: biz.whatsapp,
      earningProgram: {
        id: biz.program_id,
        type: biz.program_type,
        name: biz.program_name,
        earnPointsPerUnit: biz.earn_points_per_unit,
        redeemPointsPerUnit: biz.redeem_points_per_unit,
        minBillMinor: Number(biz.min_bill_minor),
      },
      branches: branches.rows,
      programs: memberships.rows,
    };
  }

  /** The shop sets its loyalty % here; Mukafaah Manager can also change it. */
  @Put('program')
  async updateProgram(@Auth() a: OwnerAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zProgram, body);
    const earn = b.earnPercent ?? b.earnPointsPerUnit;
    const redeem = b.earnPercent !== undefined ? 100 : b.redeemPointsPerUnit;
    await this.db.tx(async (c) => {
      // In a Shared or Network group the % is the group's, set by Mukafaah.
      const g = (await c.query(`SELECT p.type, p.name FROM businesses x JOIN programs p ON p.id = x.earning_program_id WHERE x.id = $1`, [a.businessId])).rows[0];
      if (g && g.type !== 'IN_STORE') throw new AppError(409, 'IN_GROUP', `Your shop earns with the ${g.name} group. Mukafaah sets its %.`);
      await c.query(
        `UPDATE programs SET earn_points_per_unit = COALESCE($2, earn_points_per_unit),
                             redeem_points_per_unit = COALESCE($3, redeem_points_per_unit),
                             min_bill_minor = COALESCE($4, min_bill_minor)
          WHERE id = (SELECT earning_program_id FROM businesses WHERE id = $1)`,
        [a.businessId, earn ?? null, redeem ?? null, b.minBillMinor ?? null],
      );
      await audit(c, { actorType: 'OWNER', actorId: a.userId, businessId: a.businessId, action: 'program.update', data: b, ip });
    });
    return { ok: true };
  }

  /**
   * Lets the signed-in owner use Collect and Redeem on their own phone: issues a
   * counter session for the shop's "owner" counter (no PIN, never listed to cashiers).
   */
  @Post('counter')
  @HttpCode(200)
  async counter(@Auth() a: OwnerAuth, @ClientIp() ip: string) {
    return this.db.tx(async (c) => {
      const biz = (await c.query(`SELECT b.name, u.name AS owner_name FROM businesses b JOIN users u ON u.id = b.owner_user_id WHERE b.id = $1`, [a.businessId])).rows[0];
      const branch = (await c.query(`SELECT id, name FROM branches WHERE business_id = $1 ORDER BY created_at LIMIT 1`, [a.businessId])).rows[0];
      let staff = (await c.query(`SELECT * FROM staff WHERE business_id = $1 AND role = 'OWNER' LIMIT 1`, [a.businessId])).rows[0];
      if (!staff) {
        staff = (
          await c.query(
            `INSERT INTO staff(business_id, branch_id, name, role, pin_hash, max_bill_minor, max_points_tx, max_points_day, can_redeem)
             VALUES ($1,$2,$3,'OWNER',$4, 100000000, 100000000, 1000000000, true) RETURNING *`,
            [a.businessId, branch.id, biz.owner_name || 'Owner', 'no-pin:' + randomBytes(24).toString('hex')],
          )
        ).rows[0];
      } else if (!staff.active) {
        throw new AppError(403, 'COUNTER_DISABLED', 'The owner counter is turned off for this shop');
      }
      let device = (await c.query(`SELECT id FROM devices WHERE business_id = $1 AND label = 'Owner app' AND status = 'ACTIVE' LIMIT 1`, [a.businessId])).rows[0];
      if (!device) {
        device = (
          await c.query(`INSERT INTO devices(business_id, branch_id, label, secret_hash) VALUES ($1,$2,'Owner app',$3) RETURNING id`, [
            a.businessId,
            staff.branch_id,
            this.crypto.sha256(randomBytes(32).toString('hex')),
          ])
        ).rows[0];
      }
      const { token } = await this.crypto.sign('staff', staff.id, { bid: a.businessId, brid: staff.branch_id, dev: device.id, role: 'OWNER' }, '12h');
      await audit(c, { actorType: 'OWNER', actorId: a.userId, businessId: a.businessId, action: 'owner.counter', ip });
      return {
        accessToken: token,
        staff: { id: staff.id, name: staff.name, canRedeem: true },
        businessName: biz.name,
        branchName: branch.name,
      };
    });
  }

  @Post('branches')
  async addBranch(@Auth() a: OwnerAuth, @Body() body: unknown) {
    const b = parse(zBranch, body);
    const r = await this.db.one(`INSERT INTO branches(business_id, name) VALUES ($1,$2) RETURNING id, name`, [
      a.businessId,
      b.name,
    ]);
    return r;
  }

  // ---------- Staff ----------
  @Get('staff')
  async staff(@Auth() a: OwnerAuth) {
    const r = await this.db.query(
      `SELECT s.id, s.name, s.active, s.branch_id, br.name AS branch_name, s.max_bill_minor, s.max_points_tx,
              s.max_points_day, s.max_prepoints_day_per_phone, s.can_redeem, s.void_window_min
         FROM staff s JOIN branches br ON br.id = s.branch_id
        WHERE s.business_id = $1 AND s.role = 'CASHIER' ORDER BY s.created_at`,
      [a.businessId],
    );
    return r.rows.map((s) => ({
      id: s.id,
      name: s.name,
      active: s.active,
      branchId: s.branch_id,
      branchName: s.branch_name,
      limits: {
        maxBillMinor: Number(s.max_bill_minor),
        maxPointsTx: Number(s.max_points_tx),
        maxPointsDay: Number(s.max_points_day),
        maxPrepointsDayPerPhone: Number(s.max_prepoints_day_per_phone),
        canRedeem: s.can_redeem,
        voidWindowMin: s.void_window_min,
      },
    }));
  }

  @Post('staff')
  async addStaff(@Auth() a: OwnerAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zStaff, body);
    const branch = await this.db.one(`SELECT id FROM branches WHERE id = $1 AND business_id = $2`, [b.branchId, a.businessId]);
    if (!branch) throw Errors.notFound('Branch');
    const pinHash = await hash(b.pin);
    return this.db.tx(async (c) => {
      const s = (
        await c.query(`INSERT INTO staff(business_id, branch_id, name, pin_hash) VALUES ($1,$2,$3,$4) RETURNING id`, [
          a.businessId,
          b.branchId,
          b.name,
          pinHash,
        ])
      ).rows[0];
      await audit(c, { actorType: 'OWNER', actorId: a.userId, businessId: a.businessId, action: 'staff.create', entityId: s.id, ip });
      return { id: s.id };
    });
  }

  @Patch('staff/:id')
  async patchStaff(@Auth() a: OwnerAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zStaffPatch, body);
    const pinHash = b.pin ? await hash(b.pin) : null;
    await this.db.tx(async (c) => {
      const r = await c.query(
        `UPDATE staff SET
            active = COALESCE($3, active),
            pin_hash = COALESCE($4, pin_hash),
            pin_failures = CASE WHEN $4::text IS NULL THEN pin_failures ELSE 0 END,
            locked_until = CASE WHEN $4::text IS NULL THEN locked_until ELSE NULL END,
            max_bill_minor = COALESCE($5, max_bill_minor),
            max_points_tx = COALESCE($6, max_points_tx),
            max_points_day = COALESCE($7, max_points_day),
            max_prepoints_day_per_phone = COALESCE($8, max_prepoints_day_per_phone),
            can_redeem = COALESCE($9, can_redeem),
            void_window_min = COALESCE($10, void_window_min)
          WHERE id = $1 AND business_id = $2`,
        [
          parse(zUuid, id),
          a.businessId,
          b.active ?? null,
          pinHash,
          b.maxBillMinor ?? null,
          b.maxPointsTx ?? null,
          b.maxPointsDay ?? null,
          b.maxPrepointsDayPerPhone ?? null,
          b.canRedeem ?? null,
          b.voidWindowMin ?? null,
        ],
      );
      if (!r.rowCount) throw Errors.notFound('Staff');
      const { pin: _pin, ...safe } = b;
      await audit(c, { actorType: 'OWNER', actorId: a.userId, businessId: a.businessId, action: 'staff.update', entityId: id, data: { ...safe, pinChanged: !!b.pin }, ip });
    });
    return { ok: true };
  }

  // ---------- Counter devices ----------
  /** One-time code a counter device enters to pair with a branch (valid 10 minutes). */
  @Post('pairing-codes')
  async pairingCode(@Auth() a: OwnerAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zPairing, body);
    const branch = await this.db.one(`SELECT id, name FROM branches WHERE id = $1 AND business_id = $2`, [b.branchId, a.businessId]);
    if (!branch) throw Errors.notFound('Branch');
    const code = this.crypto.randomCode(8);
    await this.db.tx(async (c) => {
      await c.query(
        `INSERT INTO pairing_codes(code_hash, business_id, branch_id, expires_at) VALUES ($1,$2,$3, now() + interval '10 minutes')`,
        [this.crypto.sha256(code), a.businessId, b.branchId],
      );
      await audit(c, { actorType: 'OWNER', actorId: a.userId, businessId: a.businessId, action: 'device.pairing_code', ip });
    });
    return { code, branchName: branch.name, expiresInSec: 600 };
  }

  @Get('devices')
  async devices(@Auth() a: OwnerAuth) {
    const r = await this.db.query(
      `SELECT d.id, d.label, d.status, d.last_seen_at, br.name AS branch_name
         FROM devices d JOIN branches br ON br.id = d.branch_id
        WHERE d.business_id = $1 ORDER BY d.created_at DESC`,
      [a.businessId],
    );
    return r.rows;
  }

  @Post('devices/:id/revoke')
  @HttpCode(200)
  async revokeDevice(@Auth() a: OwnerAuth, @Param('id') id: string, @ClientIp() ip: string) {
    await this.db.tx(async (c) => {
      const r = await c.query(`UPDATE devices SET status = 'REVOKED' WHERE id = $1 AND business_id = $2`, [parse(zUuid, id), a.businessId]);
      if (!r.rowCount) throw Errors.notFound('Device');
      await audit(c, { actorType: 'OWNER', actorId: a.userId, businessId: a.businessId, action: 'device.revoke', entityId: id, ip });
    });
    return { ok: true };
  }

  // ---------- Live alerts (new bookings, orders, approvals, ratings) ----------
  @Get('alerts')
  async alerts(@Auth() a: OwnerAuth, @Query() q: unknown) {
    const f = parse(zAfter, q);
    return listAlerts(this.db, a.businessId, f.after);
  }

  // ---------- Analytics ----------
  @Get('dashboard')
  async dashboard(@Auth() a: OwnerAuth, @Query() query: unknown) {
    const f = parse(zFilter, query);
    const biz = await this.db.one(`SELECT time_zone, currency FROM businesses WHERE id = $1`, [a.businessId]);
    const today = (await this.db.one(`SELECT (now() AT TIME ZONE $1)::date::text AS d`, [biz.time_zone])).d as string;
    const from = f.from ?? today;
    const to = f.to ?? today;
    const where = `v.business_id = $1 AND v.local_date BETWEEN $2 AND $3 AND v.voided_by_tx_id IS NULL
                   AND ($4::uuid IS NULL OR v.branch_id = $4) AND ($5::uuid IS NULL OR v.staff_id = $5)
                   AND ($6::uuid IS NULL OR v.program_id = $6)`;
    const params = [a.businessId, from, to, f.branchId ?? null, f.staffId ?? null, f.programId ?? null];

    const totals = await this.db.one(
      `SELECT
         COALESCE(SUM(v.bill_minor) FILTER (WHERE v.type IN ('EARN','PREPOINT_EARN')),0) AS bills_minor,
         count(*) FILTER (WHERE v.type IN ('EARN','PREPOINT_EARN'))::int AS earn_transactions,
         count(*) FILTER (WHERE v.type = 'REDEEM')::int AS redeem_transactions,
         COALESCE(SUM(v.points) FILTER (WHERE v.type IN ('EARN','PREPOINT_EARN')),0) AS points_issued,
         COALESCE(SUM(v.points) FILTER (WHERE v.type = 'PREPOINT_EARN'),0) AS prepoints_issued,
         COALESCE(SUM(v.points) FILTER (WHERE v.type = 'REDEEM'),0) AS points_redeemed,
         count(DISTINCT COALESCE(v.user_id, v.pending_holder_id))::int AS customers
       FROM visits v WHERE ${where}`,
      params,
    );
    const newVsReturning = await this.db.one(
      `WITH firsts AS (
         SELECT COALESCE(user_id, pending_holder_id) AS cid, min(local_date) AS first_date
           FROM visits WHERE business_id = $1 AND voided_by_tx_id IS NULL GROUP BY 1)
       SELECT count(*) FILTER (WHERE f.first_date >= $2)::int AS new_customers,
              count(*) FILTER (WHERE f.first_date < $2)::int AS returning_customers
         FROM (SELECT DISTINCT COALESCE(v.user_id, v.pending_holder_id) AS cid FROM visits v WHERE ${where}) s
         JOIN firsts f ON f.cid = s.cid`,
      params,
    );
    const byCashier = await this.db.query(
      `SELECT s.id, s.name,
              COALESCE(SUM(v.bill_minor) FILTER (WHERE v.type IN ('EARN','PREPOINT_EARN')),0) AS bills_minor,
              count(*)::int AS transactions,
              COALESCE(SUM(v.points) FILTER (WHERE v.type IN ('EARN','PREPOINT_EARN')),0) AS points_issued,
              COALESCE(SUM(v.points) FILTER (WHERE v.type = 'REDEEM'),0) AS points_redeemed
         FROM visits v JOIN staff s ON s.id = v.staff_id
        WHERE ${where}
        GROUP BY s.id ORDER BY bills_minor DESC`,
      params,
    );
    const byBranch = await this.db.query(
      `SELECT br.id, br.name, count(*)::int AS transactions,
              COALESCE(SUM(v.bill_minor) FILTER (WHERE v.type IN ('EARN','PREPOINT_EARN')),0) AS bills_minor
         FROM visits v JOIN branches br ON br.id = v.branch_id
        WHERE ${where} GROUP BY br.id ORDER BY bills_minor DESC`,
      params,
    );
    const daily = await this.db.query(
      `SELECT v.local_date::text AS date, count(*)::int AS transactions,
              COALESCE(SUM(v.points) FILTER (WHERE v.type IN ('EARN','PREPOINT_EARN')),0) AS points_issued
         FROM visits v WHERE ${where} GROUP BY 1 ORDER BY 1`,
      params,
    );
    const extras = await this.db.one(
      `SELECT
         (SELECT count(*)::int FROM offer_bookings WHERE business_id = $1 AND status = 'REQUESTED') AS pending_bookings,
         (SELECT count(*)::int FROM offer_bookings WHERE business_id = $1 AND status = 'ACCEPTED') AS accepted_bookings,
         (SELECT count(*)::int FROM offer_bookings k JOIN businesses b ON b.id = k.business_id
            WHERE k.business_id = $1 AND k.status = 'REDEEMED'
              AND (k.redeemed_at AT TIME ZONE b.time_zone)::date BETWEEN $2 AND $3) AS offers_used,
         (SELECT count(*)::int FROM reward_redemptions r JOIN businesses b ON b.id = r.business_id
            WHERE r.business_id = $1 AND (r.created_at AT TIME ZONE b.time_zone)::date BETWEEN $2 AND $3) AS rewards_redeemed,
         (SELECT count(*)::int FROM whatsapp_orders w JOIN businesses b ON b.id = w.business_id
            WHERE w.business_id = $1 AND (w.created_at AT TIME ZONE b.time_zone)::date BETWEEN $2 AND $3) AS whatsapp_orders,
         (SELECT COALESCE(avg(stars), 0)::float FROM business_ratings WHERE business_id = $1) AS rating,
         (SELECT count(*)::int FROM business_ratings WHERE business_id = $1) AS rating_count`,
      [a.businessId, from, to],
    );
    return {
      from,
      to,
      currency: biz.currency,
      engagement: {
        pendingBookings: extras?.pending_bookings ?? 0,
        acceptedBookings: extras?.accepted_bookings ?? 0,
        offersUsed: extras?.offers_used ?? 0,
        rewardsRedeemed: extras?.rewards_redeemed ?? 0,
        whatsappOrders: extras?.whatsapp_orders ?? 0,
        rating: Math.round(Number(extras?.rating ?? 0) * 10) / 10,
        ratingCount: extras?.rating_count ?? 0,
      },
      totals: {
        billsMinor: Number(totals.bills_minor),
        earnTransactions: totals.earn_transactions,
        redeemTransactions: totals.redeem_transactions,
        pointsIssued: Number(totals.points_issued),
        prepointsIssued: Number(totals.prepoints_issued),
        pointsRedeemed: Number(totals.points_redeemed),
        customers: totals.customers,
        newCustomers: newVsReturning?.new_customers ?? 0,
        returningCustomers: newVsReturning?.returning_customers ?? 0,
      },
      byCashier: byCashier.rows.map((r) => ({
        staffId: r.id,
        name: r.name,
        billsMinor: Number(r.bills_minor),
        transactions: r.transactions,
        pointsIssued: Number(r.points_issued),
        pointsRedeemed: Number(r.points_redeemed),
      })),
      byBranch: byBranch.rows.map((r) => ({ branchId: r.id, name: r.name, transactions: r.transactions, billsMinor: Number(r.bills_minor) })),
      daily: daily.rows.map((r) => ({ date: r.date, transactions: r.transactions, pointsIssued: Number(r.points_issued) })),
    };
  }

  @Get('transactions')
  async transactions(@Auth() a: OwnerAuth, @Query() query: unknown) {
    const f = parse(zFilter, query);
    const r = await this.db.query(
      `SELECT v.id AS visit_id, v.ledger_tx_id, v.type, v.bill_minor, v.points, v.created_at, v.voided_by_tx_id, v.invoice_no, v.ref_type,
              s.name AS staff_name, br.name AS branch_name,
              COALESCE(u.phone_last4, h.phone_last4) AS phone_last4, u.name AS customer_name,
              (v.user_id IS NULL) AS is_prepoint
         FROM visits v
         LEFT JOIN staff s ON s.id = v.staff_id
         JOIN branches br ON br.id = v.branch_id
         LEFT JOIN users u ON u.id = v.user_id
         LEFT JOIN pending_holders h ON h.id = v.pending_holder_id
        WHERE v.business_id = $1
          AND ($2::date IS NULL OR v.local_date >= $2) AND ($3::date IS NULL OR v.local_date <= $3)
          AND ($4::uuid IS NULL OR v.branch_id = $4) AND ($5::uuid IS NULL OR v.staff_id = $5)
          AND ($6::uuid IS NULL OR v.program_id = $6)
        ORDER BY v.created_at DESC LIMIT 200`,
      [a.businessId, f.from ?? null, f.to ?? null, f.branchId ?? null, f.staffId ?? null, f.programId ?? null],
    );
    return r.rows.map((x) => ({
      visitId: x.visit_id,
      transactionId: x.ledger_tx_id,
      type: x.type,
      billMinor: Number(x.bill_minor),
      points: Number(x.points),
      createdAt: x.created_at,
      voided: !!x.voided_by_tx_id,
      staffName: x.staff_name,
      branchName: x.branch_name,
      customer: x.customer_name ?? (x.phone_last4 ? `•••• ${x.phone_last4}` : null),
      isPrePoints: x.is_prepoint,
      invoiceNo: x.invoice_no ?? null,
      refType: x.ref_type ?? null,
    }));
  }

  /** Owner reversal of any bill (reason required, audited). */
  @Post('transactions/:id/reverse')
  @HttpCode(200)
  async reverse(@Auth() a: OwnerAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zReverse, body);
    const txId = parse(zUuid, id);
    return this.db.tx(async (c) => {
      const v = (await c.query(`SELECT * FROM visits WHERE ledger_tx_id = $1 AND business_id = $2 FOR UPDATE`, [txId, a.businessId])).rows[0];
      if (!v) throw Errors.notFound('Transaction');
      if (v.voided_by_tx_id) throw new AppError(409, 'ALREADY_REVERSED');
      const rev = await this.ledger.reverse(c, txId, 'REVERSAL', {
        idempotencyKey: `reverse:${txId}`,
        businessId: a.businessId,
        branchId: v.branch_id,
        reason: b.reason,
      });
      await c.query(`UPDATE visits SET voided_by_tx_id = $2 WHERE id = $1`, [v.id, rev]);
      // A reversed bill no longer counts toward the member's tier.
      if (v.type === 'EARN' && v.user_id) await addSpend(c, this.ledger, v.user_id, -Number(v.bill_minor));
      await audit(c, { actorType: 'OWNER', actorId: a.userId, businessId: a.businessId, action: 'ledger.reverse', entityId: txId, data: { reason: b.reason }, ip });
      return { reversalTransactionId: rev };
    });
  }
}

@Module({ controllers: [OnboardingController, OwnerController] })
export class OwnerModule {}
