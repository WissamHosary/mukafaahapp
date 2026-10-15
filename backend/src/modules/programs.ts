import { Body, Controller, Get, Module, Param, Patch, Post, Put } from '@nestjs/common';
import { z } from 'zod';
import { audit } from '../platform/audit.js';
import { Auth, ClientIp, RequireAdmin, RequireOwner, type AdminAuth, type OwnerAuth } from '../platform/auth.js';
import { Db, type Tx } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zUuid } from '../platform/validation.js';
import { earnPercent, mediaUrl } from './shared.js';

/**
 * Shared and Network points groups.
 *
 *  - Shared:  shops in the group earn into the same points, and the customer
 *             can spend all of them at any shop in the group (buy at A, spend at B).
 *  - Network: the same, but each shop decides how much it takes per visit:
 *             a % of the customer's balance and/or a number of points.
 *
 * A shop earns into one program at a time (its own In-Store program, or one
 * group). Points already earned in its own program stay usable there.
 */

const zCaps = {
  maxPercent: z.number().int().min(1).max(100).optional(),
  /** null removes the points limit. */
  maxPoints: z.number().int().min(1).max(10_000_000).nullable().optional(),
};
const zNewProgram = z.strictObject({
  type: z.enum(['SHARED', 'NETWORK']),
  name: z.string().trim().min(2).max(60),
  description: z.string().trim().max(300).nullable().optional(),
  earnPercent: z.number().int().min(0).max(100),
});
const zProgramPatch = z.strictObject({
  name: z.string().trim().min(2).max(60).optional(),
  description: z.string().trim().max(300).nullable().optional(),
  earnPercent: z.number().int().min(0).max(100).optional(),
  active: z.boolean().optional(),
});
const zMember = z.strictObject({ active: z.boolean().optional(), ...zCaps });
const zOwnerCaps = z.strictObject(zCaps);

/** Most points a customer with [balance] may spend here, given the shop's caps. */
export function capFor(balance: number, maxPercent: number, maxPoints: number | null): number {
  const byPercent = Math.floor((balance * maxPercent) / 100);
  return maxPoints == null ? byPercent : Math.min(byPercent, maxPoints);
}

/** Moves a shop into a group, or back to its own program (groupId null). */
export async function setShopGroup(c: Tx, businessId: string, groupId: string | null) {
  const own = (await c.query(`SELECT id FROM programs WHERE owner_business_id = $1 AND type = 'IN_STORE'`, [businessId])).rows[0];
  // Leave the group it earns in now (if any).
  await c.query(
    `UPDATE program_members pm SET active = false, updated_at = now()
       FROM programs p WHERE p.id = pm.program_id AND pm.business_id = $1 AND p.type IN ('SHARED','NETWORK') AND pm.active
        AND ($2::uuid IS NULL OR p.id <> $2)`,
    [businessId, groupId],
  );
  if (groupId) {
    await c.query(
      `INSERT INTO program_members(program_id, business_id, can_earn, can_redeem, active) VALUES ($1,$2,true,true,true)
       ON CONFLICT (program_id, business_id) DO UPDATE SET active = true, can_earn = true, can_redeem = true, updated_at = now()`,
      [groupId, businessId],
    );
  }
  await c.query(`UPDATE businesses SET earning_program_id = $2 WHERE id = $1`, [businessId, groupId ?? own?.id ?? null]);
}

function programJson(p: any, members: any[]) {
  return {
    id: p.id,
    type: p.type,
    name: p.name,
    description: p.description ?? null,
    active: p.status === 'ACTIVE',
    earnPercent: earnPercent(Number(p.earn_points_per_unit), Number(p.redeem_points_per_unit)),
    outstandingPoints: Number(p.outstanding ?? 0),
    members: members.map((m) => ({
      shopId: m.business_id,
      name: m.name,
      category: m.category,
      city: m.city ?? null,
      logoUrl: mediaUrl(m.logo_media_id),
      maxPercent: Number(m.redeem_max_percent),
      maxPoints: m.redeem_max_points == null ? null : Number(m.redeem_max_points),
      joinedAt: m.joined_at,
    })),
  };
}

@Controller('v1/admin')
@RequireAdmin()
export class AdminProgramsController {
  constructor(private readonly db: Db) {}

  private async load(id?: string) {
    const ps = await this.db.query(
      `SELECT p.*, COALESCE((SELECT SUM(ab.balance) FROM ledger_accounts a JOIN account_balances ab ON ab.account_id = a.id
                              WHERE a.program_id = p.id AND a.owner_type = 'CUSTOMER'), 0) AS outstanding
         FROM programs p WHERE p.type IN ('SHARED','NETWORK') AND ($1::uuid IS NULL OR p.id = $1) ORDER BY p.created_at`,
      [id ?? null],
    );
    const ms = await this.db.query(
      `SELECT pm.*, b.name, b.category, b.city, b.logo_media_id FROM program_members pm
         JOIN businesses b ON b.id = pm.business_id
        WHERE pm.active AND pm.program_id = ANY($1::uuid[]) ORDER BY b.name`,
      [ps.rows.map((p) => p.id)],
    );
    return ps.rows.map((p) => programJson(p, ms.rows.filter((m) => m.program_id === p.id)));
  }

  @Get('programs')
  async list() {
    const [programs, shops] = await Promise.all([
      this.load(),
      this.db.query(
        `SELECT b.id, b.name, b.category, b.logo_media_id, p.type AS program_type, p.name AS program_name
           FROM businesses b JOIN programs p ON p.id = b.earning_program_id WHERE b.status = 'ACTIVE' ORDER BY b.name`,
      ),
    ]);
    return {
      programs,
      // To pick shops to add: where each shop earns now.
      shops: shops.rows.map((s) => ({
        id: s.id,
        name: s.name,
        category: s.category,
        logoUrl: mediaUrl(s.logo_media_id),
        programType: s.program_type,
        programName: s.program_name,
      })),
    };
  }

  @Post('programs')
  async create(@Auth() a: AdminAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zNewProgram, body);
    const id = await this.db.tx(async (c) => {
      const p = (
        await c.query(
          `INSERT INTO programs(type, name, description, earn_points_per_unit, redeem_points_per_unit) VALUES ($1,$2,$3,$4,100) RETURNING id`,
          [b.type, b.name, b.description ?? null, b.earnPercent],
        )
      ).rows[0];
      await audit(c, { actorType: 'USER', actorId: a.userId, action: 'admin.program.create', entityId: p.id, data: b, ip });
      return p.id as string;
    });
    return (await this.load(id))[0];
  }

  @Patch('programs/:id')
  async patch(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const pid = parse(zUuid, id);
    const b = parse(zProgramPatch, body);
    await this.db.tx(async (c) => {
      const r = await c.query(
        `UPDATE programs SET name = COALESCE($2, name), description = CASE WHEN $3::boolean THEN $4 ELSE description END,
                earn_points_per_unit = COALESCE($5, earn_points_per_unit),
                status = CASE WHEN $6::boolean IS NULL THEN status WHEN $6 THEN 'ACTIVE' ELSE 'PAUSED' END
          WHERE id = $1 AND type IN ('SHARED','NETWORK')`,
        [pid, b.name ?? null, b.description !== undefined, b.description ?? null, b.earnPercent ?? null, b.active ?? null],
      );
      if (!r.rowCount) throw Errors.notFound('Program');
      await audit(c, { actorType: 'USER', actorId: a.userId, action: 'admin.program.update', entityId: pid, data: b, ip });
    });
    return (await this.load(pid))[0];
  }

  /** Adds a shop to the group (it earns there from now on), removes it, or changes its caps. */
  @Put('programs/:id/members/:shopId')
  async member(@Auth() a: AdminAuth, @Param('id') id: string, @Param('shopId') shopId: string, @Body() body: unknown, @ClientIp() ip: string) {
    const pid = parse(zUuid, id);
    const bid = parse(zUuid, shopId);
    const b = parse(zMember, body);
    await this.db.tx(async (c) => {
      const p = (await c.query(`SELECT type FROM programs WHERE id = $1 AND type IN ('SHARED','NETWORK') FOR UPDATE`, [pid])).rows[0];
      if (!p) throw Errors.notFound('Program');
      const shop = (await c.query(`SELECT id FROM businesses WHERE id = $1 FOR UPDATE`, [bid])).rows[0];
      if (!shop) throw Errors.notFound('Shop');
      if (b.active === false) {
        await setShopGroup(c, bid, null);
      } else if (b.active === true) {
        await setShopGroup(c, bid, pid);
      }
      if (b.maxPercent !== undefined || b.maxPoints !== undefined) {
        if (p.type === 'SHARED' && ((b.maxPercent ?? 100) < 100 || b.maxPoints != null)) {
          throw new AppError(409, 'SHARED_NO_CAPS', 'Shared points are spent in full everywhere. Use a Network group for limits.');
        }
        await c.query(
          `UPDATE program_members SET redeem_max_percent = COALESCE($3, redeem_max_percent),
                  redeem_max_points = CASE WHEN $4::boolean THEN $5 ELSE redeem_max_points END, updated_at = now()
            WHERE program_id = $1 AND business_id = $2`,
          [pid, bid, b.maxPercent ?? null, b.maxPoints !== undefined, b.maxPoints ?? null],
        );
      }
      await audit(c, { actorType: 'USER', actorId: a.userId, businessId: bid, action: 'admin.program.member', entityId: pid, data: b, ip });
    });
    return (await this.load(pid))[0];
  }
}

/** The shop owner sees the group they're in and sets their own Network limits. */
@Controller('v1/business/manage')
@RequireOwner()
export class OwnerProgramController {
  constructor(private readonly db: Db) {}

  @Get('points-group')
  async get(@Auth() a: OwnerAuth) {
    const r = await this.db.one(
      `SELECT p.id, p.type, p.name, p.description, p.earn_points_per_unit, p.redeem_points_per_unit, pm.redeem_max_percent, pm.redeem_max_points,
              (SELECT count(*)::int FROM program_members x WHERE x.program_id = p.id AND x.active) AS shops
         FROM businesses b JOIN programs p ON p.id = b.earning_program_id
         JOIN program_members pm ON pm.program_id = p.id AND pm.business_id = b.id
        WHERE b.id = $1`,
      [a.businessId],
    );
    if (!r) throw Errors.notFound('Program');
    return {
      id: r.id,
      type: r.type,
      name: r.name,
      description: r.description ?? null,
      shops: r.shops,
      earnPercent: earnPercent(Number(r.earn_points_per_unit), Number(r.redeem_points_per_unit)),
      maxPercent: Number(r.redeem_max_percent),
      maxPoints: r.redeem_max_points == null ? null : Number(r.redeem_max_points),
      canSetLimits: r.type === 'NETWORK',
    };
  }

  /** Network shops only: how much of a customer's balance they take per visit. */
  @Put('points-group/limits')
  async limits(@Auth() a: OwnerAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zOwnerCaps, body);
    await this.db.tx(async (c) => {
      const r = (
        await c.query(
          `SELECT p.id, p.type FROM businesses b JOIN programs p ON p.id = b.earning_program_id WHERE b.id = $1`,
          [a.businessId],
        )
      ).rows[0];
      if (!r || r.type !== 'NETWORK') throw new AppError(409, 'NOT_NETWORK', 'Limits are only for Network groups');
      await c.query(
        `UPDATE program_members SET redeem_max_percent = COALESCE($3, redeem_max_percent),
                redeem_max_points = CASE WHEN $4::boolean THEN $5 ELSE redeem_max_points END, updated_at = now()
          WHERE program_id = $1 AND business_id = $2`,
        [r.id, a.businessId, b.maxPercent ?? null, b.maxPoints !== undefined, b.maxPoints ?? null],
      );
      await audit(c, { actorType: 'OWNER', actorId: a.userId, businessId: a.businessId, action: 'program.limits', data: b, ip });
    });
    return this.get(a);
  }
}

@Module({ controllers: [AdminProgramsController, OwnerProgramController] })
export class ProgramsModule {}
