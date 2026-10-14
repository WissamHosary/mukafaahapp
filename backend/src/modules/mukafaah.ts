import { randomUUID } from 'node:crypto';
import { Body, Controller, Get, HttpCode, Module, Param, Patch, Post } from '@nestjs/common';
import { z } from 'zod';
import { audit } from '../platform/audit.js';
import { AdminScope, Auth, ClientIp, OptionalIdemKey, RequireAdmin, RequireUser, type AdminAuth, type UserAuth } from '../platform/auth.js';
import { CryptoService } from '../platform/crypto.js';
import { Db, type Queryable, type Tx } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zUuid } from '../platform/validation.js';
import { LedgerService } from './ledger.js';
import { fmtPts, getSetting, loadTierRows, mediaUrl, notify, tierForSpend } from './shared.js';

/*
 * Mukafaah Points: the company's own points. Mukafaah gives them (sign-up,
 * referrals, first bill, tier bonuses, manual grants) and customers spend
 * them at "Mukafaah Friends" shops. Spent points are credited to the shop's
 * BUSINESS_REDEEMED account so Mukafaah knows what it owes each shop.
 */

/** Id of the platform program ("Mukafaah Points"). */
export async function mukafaahProgramId(c: Queryable): Promise<string> {
  const v = await getSetting<string | null>(c, 'mukafaah.programId', null);
  if (v) return String(v);
  const r = await c.query(`SELECT id FROM programs WHERE type = 'PLATFORM' ORDER BY created_at LIMIT 1`);
  if (!r.rows[0]) throw new AppError(500, 'NO_PLATFORM_PROGRAM', 'Mukafaah Points are not set up');
  return String(r.rows[0].id);
}

/** Customer's Mukafaah Points balance. */
export async function mukafaahBalance(c: Queryable, userId: string): Promise<number> {
  const prog = await mukafaahProgramId(c);
  const r = await c.query(
    `SELECT ab.balance FROM ledger_accounts a JOIN account_balances ab ON ab.account_id = a.id
      WHERE a.program_id = $1 AND a.owner_type = 'CUSTOMER' AND a.owner_id = $2`,
    [prog, userId],
  );
  return Number(r.rows[0]?.balance ?? 0);
}

/**
 * Gives Mukafaah Points (ledger type GRANT). Idempotent by key: a key already
 * used returns null and nothing is posted.
 */
export async function grantMukafaah(
  c: Tx,
  ledger: LedgerService,
  g: { userId: string; points: number; idempotencyKey: string; reason: string },
): Promise<string | null> {
  if (!Number.isSafeInteger(g.points) || g.points <= 0) return null;
  if (await ledger.existing(c, g.idempotencyKey)) return null;
  const prog = await mukafaahProgramId(c);
  const issued = await ledger.account(c, prog, 'BUSINESS_ISSUED', prog);
  const wallet = await ledger.account(c, prog, 'CUSTOMER', g.userId);
  try {
    return await ledger.post(c, {
      type: 'GRANT',
      programId: prog,
      idempotencyKey: g.idempotencyKey,
      userId: g.userId,
      reason: g.reason,
      entries: [
        { accountId: issued, amount: -g.points },
        { accountId: wallet, amount: g.points },
      ],
    });
  } catch (e) {
    // A parallel request granted it first.
    if (e instanceof AppError && e.code === 'DUPLICATE_REQUEST') return null;
    throw e;
  }
}

export type RuleCode = 'SIGNUP' | 'REFERRAL' | 'FIRST_BILL';

/**
 * Grants a rule's points once. [onceFor] is who the grant is unique for
 * (defaults to the receiving user; REFERRAL is once per invited friend).
 */
export async function grantRule(c: Tx, ledger: LedgerService, code: RuleCode, userId: string, onceFor?: string) {
  const rule = (await c.query(`SELECT code, title_en, title_ar, points FROM mukafaah_rules WHERE code = $1 AND active`, [code])).rows[0];
  if (!rule || Number(rule.points) <= 0) return null;
  const points = Number(rule.points);
  const txId = await grantMukafaah(c, ledger, {
    userId,
    points,
    idempotencyKey: `mkf:rule:${code}:${onceFor ?? userId}`,
    reason: `rule:${code}`,
  });
  if (txId) {
    await notify(
      c,
      userId,
      'MUKAFAAH',
      {
        ar: { title: `حصلت على ${fmtPts(points)} نقطة مكافأة`, body: rule.title_ar },
        en: { title: `You got ${fmtPts(points)} Mukafaah Points`, body: rule.title_en },
      },
      { transactionId: txId, rule: code },
    );
  }
  return txId;
}

/**
 * Adds (or, for a void, removes) a member's spend and moves their tier. Going
 * up a tier gives that tier's bonus once (Mukafaah Points) and a notification.
 */
export async function addSpend(c: Tx, ledger: LedgerService, userId: string, deltaMinor: number) {
  if (!deltaMinor) return;
  const u = (
    await c.query(
      `UPDATE users SET lifetime_spend_minor = GREATEST(0, lifetime_spend_minor + $2::bigint) WHERE id = $1
       RETURNING lifetime_spend_minor, tier`,
      [userId, deltaMinor],
    )
  ).rows[0];
  if (!u) return;
  const rows = await loadTierRows(c);
  const target = tierForSpend(rows, Number(u.lifetime_spend_minor));
  if (!target || target.code === u.tier) return;
  await c.query(`UPDATE users SET tier = $2 WHERE id = $1`, [userId, target.code]);
  const curIdx = rows.findIndex((t) => t.code === u.tier);
  const tgtIdx = rows.indexOf(target);
  if (tgtIdx <= curIdx) return; // moved down after a void: no bonus taken back
  let bonus = 0;
  for (const t of rows.slice(curIdx + 1, tgtIdx + 1)) {
    const tx = await grantMukafaah(c, ledger, {
      userId,
      points: t.bonusPoints,
      idempotencyKey: `mkf:tier:${t.code}:${userId}`,
      reason: `tier:${t.code}`,
    });
    if (tx) bonus += t.bonusPoints;
  }
  await notify(
    c,
    userId,
    'TIER_UP',
    {
      ar: { title: `وصلت للمستوى ${target.nameAr}`, body: bonus ? `هدية ${fmtPts(bonus)} نقطة مكافأة` : undefined },
      en: { title: `You reached ${target.nameEn}`, body: bonus ? `Bonus: ${fmtPts(bonus)} Mukafaah Points` : undefined },
    },
    { tier: target.code },
  );
}

/** Human title of a Mukafaah Points history row. */
function historyTitle(x: any, en: boolean): string {
  const reason: string = x.reason ?? '';
  if (x.type === 'GRANT') {
    if (reason.startsWith('rule:')) return (en ? x.rule_en : x.rule_ar) ?? reason.slice(5);
    if (reason.startsWith('tier:')) {
      const name = (en ? x.tier_en : x.tier_ar) ?? reason.slice(5);
      return en ? `Reached ${name}` : `وصلت للمستوى ${name}`;
    }
    if (reason.startsWith('admin:')) return reason.slice(6) || (en ? 'Gift from Mukafaah' : 'هدية من مكافأة');
    return en ? 'Gift from Mukafaah' : 'هدية من مكافأة';
  }
  if (x.type === 'REDEEM') return en ? `Used at ${x.business_name ?? 'a shop'}` : `استعملتها عند ${x.business_name ?? 'محل'}`;
  if (x.type === 'VOID' || x.type === 'REVERSAL') return en ? 'Refunded' : 'مسترجعة';
  return x.type;
}

@Controller('v1/customer')
@RequireUser()
export class CustomerMukafaahController {
  constructor(private readonly db: Db) {}

  @Get('mukafaah')
  async mukafaah(@Auth() a: UserAuth) {
    const prog = await mukafaahProgramId(this.db);
    const [u, balance, rules, friends, hist] = await Promise.all([
      this.db.one(`SELECT locale FROM users WHERE id = $1`, [a.userId]),
      mukafaahBalance(this.db, a.userId),
      this.db.query(`SELECT code, title_en, title_ar, points FROM mukafaah_rules WHERE active ORDER BY sort, code`),
      this.db.query(
        `SELECT id, name, logo_media_id, category, friends_max_points FROM businesses
          WHERE friends_enabled AND status = 'ACTIVE' AND listed ORDER BY name`,
      ),
      this.db.query(
        `SELECT t.id, t.type, t.reason, t.created_at, e.amount, b.name AS business_name,
                r.title_en AS rule_en, r.title_ar AS rule_ar, tr.name_en AS tier_en, tr.name_ar AS tier_ar
           FROM ledger_entries e
           JOIN ledger_accounts la ON la.id = e.account_id AND la.owner_type = 'CUSTOMER' AND la.owner_id = $2 AND la.program_id = $1
           JOIN ledger_transactions t ON t.id = e.transaction_id
           LEFT JOIN businesses b ON b.id = t.business_id
           LEFT JOIN mukafaah_rules r ON t.reason = 'rule:' || r.code
           LEFT JOIN tiers tr ON t.reason = 'tier:' || tr.code
          ORDER BY e.id DESC LIMIT 50`,
        [prog, a.userId],
      ),
    ]);
    const en = u?.locale === 'en';
    return {
      balance,
      rules: rules.rows.map((r) => ({ code: r.code, title: en ? r.title_en : r.title_ar, points: Number(r.points) })),
      friends: friends.rows.map((b) => ({
        id: b.id,
        name: b.name,
        logoUrl: mediaUrl(b.logo_media_id),
        category: b.category,
        maxPoints: Number(b.friends_max_points),
      })),
      history: hist.rows.map((x) => ({
        id: x.id,
        type: x.type,
        points: Number(x.amount),
        title: historyTitle(x, en),
        createdAt: x.created_at,
      })),
    };
  }
}

const zRulePatch = z.strictObject({
  title: z.string().trim().min(1).max(120).optional(),
  titleAr: z.string().trim().min(1).max(120).optional(),
  points: z.number().int().min(0).max(100000).optional(),
  active: z.boolean().optional(),
});
const zGrant = z.strictObject({
  phone: z.string().min(6).max(20),
  points: z.number().int().min(1).max(100000),
  reason: z.string().trim().min(1).max(200),
});
const zFriends = z.strictObject({ enabled: z.boolean(), maxPoints: z.number().int().min(0).max(100000) });

const ruleJson = (r: any) => ({
  code: r.code,
  title: r.title_en,
  titleEn: r.title_en,
  titleAr: r.title_ar,
  points: Number(r.points),
  active: !!r.active,
  sort: Number(r.sort),
});

/** Mukafaah Manager: Mukafaah Points rules, totals, grants and Friends shops. */
@Controller('v1/admin')
@RequireAdmin()
export class AdminMukafaahController {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
    private readonly ledger: LedgerService,
  ) {}

  @Get('mukafaah')
  async overview() {
    const prog = await mukafaahProgramId(this.db);
    const [rules, totals, friends] = await Promise.all([
      this.db.query(`SELECT * FROM mukafaah_rules ORDER BY sort, code`),
      this.db.one(
        `SELECT
           (SELECT COALESCE(SUM(e.amount), 0) FROM ledger_entries e
              JOIN ledger_transactions t ON t.id = e.transaction_id AND t.type = 'GRANT'
              JOIN ledger_accounts la ON la.id = e.account_id AND la.program_id = $1 AND la.owner_type = 'CUSTOMER') AS issued,
           (SELECT COALESCE(SUM(ab.balance), 0) FROM ledger_accounts la JOIN account_balances ab ON ab.account_id = la.id
             WHERE la.program_id = $1 AND la.owner_type = 'BUSINESS_REDEEMED') AS redeemed,
           (SELECT COALESCE(SUM(ab.balance), 0) FROM ledger_accounts la JOIN account_balances ab ON ab.account_id = la.id
             WHERE la.program_id = $1 AND la.owner_type = 'CUSTOMER') AS outstanding`,
        [prog],
      ),
      this.db.query(
        `SELECT b.id, b.name, b.friends_enabled, b.friends_max_points, COALESCE(ab.balance, 0) AS redeemed
           FROM businesses b
           LEFT JOIN ledger_accounts la ON la.program_id = $1 AND la.owner_type = 'BUSINESS_REDEEMED' AND la.owner_id = b.id
           LEFT JOIN account_balances ab ON ab.account_id = la.id
          WHERE b.friends_enabled OR COALESCE(ab.balance, 0) <> 0
          ORDER BY b.friends_enabled DESC, b.name`,
        [prog],
      ),
    ]);
    return {
      rules: rules.rows.map(ruleJson),
      totals: {
        issued: Number(totals?.issued ?? 0),
        redeemed: Number(totals?.redeemed ?? 0),
        outstanding: Number(totals?.outstanding ?? 0),
      },
      friends: friends.rows.map((b) => ({
        id: b.id,
        name: b.name,
        friendsEnabled: !!b.friends_enabled,
        maxPoints: Number(b.friends_max_points),
        redeemedPoints: Number(b.redeemed),
      })),
    };
  }

  @Patch('mukafaah/rules/:code')
  @AdminScope('FULL')
  async patchRule(@Auth() a: AdminAuth, @Param('code') code: string, @Body() body: unknown, @ClientIp() ip: string) {
    const k = parse(z.string().trim().toUpperCase().regex(/^[A-Z_]{2,30}$/), code);
    const b = parse(zRulePatch, body);
    return this.db.tx(async (c) => {
      const r = (
        await c.query(
          `UPDATE mukafaah_rules SET title_en = COALESCE($2, title_en), title_ar = COALESCE($3, title_ar),
                  points = COALESCE($4, points), active = COALESCE($5, active)
            WHERE code = $1 RETURNING *`,
          [k, b.title ?? null, b.titleAr ?? null, b.points ?? null, b.active ?? null],
        )
      ).rows[0];
      if (!r) throw Errors.notFound('Rule');
      await audit(c, { actorType: 'USER', actorId: a.userId, action: 'admin.mukafaah.rule', entityId: k, data: b, ip });
      return ruleJson(r);
    });
  }

  /** Gives Mukafaah Points to one customer (by phone). */
  @Post('mukafaah/grant')
  @HttpCode(200)
  @AdminScope('FULL')
  async grant(@Auth() a: AdminAuth, @Body() body: unknown, @OptionalIdemKey() key: string | null, @ClientIp() ip: string) {
    const b = parse(zGrant, body);
    const e164 = this.crypto.normalizePhone(b.phone, false);
    const u = await this.db.one(`SELECT id FROM users WHERE phone_hash = $1`, [this.crypto.phoneHash(e164)]);
    if (!u) throw new AppError(404, 'USER_NOT_FOUND', 'No Mukafaah member with this number');
    return this.db.tx(async (c) => {
      const idem = `mkf:admin:${a.userId}:${key ?? randomUUID()}`;
      const txId = await grantMukafaah(c, this.ledger, { userId: u.id, points: b.points, idempotencyKey: idem, reason: `admin:${b.reason}` });
      if (txId) {
        await notify(
          c,
          u.id,
          'MUKAFAAH',
          {
            ar: { title: `حصلت على ${fmtPts(b.points)} نقطة مكافأة`, body: b.reason },
            en: { title: `You got ${fmtPts(b.points)} Mukafaah Points`, body: b.reason },
          },
          { transactionId: txId },
        );
        await audit(c, { actorType: 'USER', actorId: a.userId, action: 'admin.mukafaah.grant', entityId: txId, data: { userId: u.id, points: b.points, reason: b.reason }, ip });
      }
      return { ok: true, transactionId: txId ?? (await this.ledger.existing(c, idem)) ?? null, replayed: !txId, balance: await mukafaahBalance(c, u.id) };
    });
  }

  /** Turns Mukafaah Friends on for a shop (it then accepts Mukafaah Points, up to maxPoints per bill). */
  @Patch('shops/:id/friends')
  async friends(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const bid = parse(zUuid, id);
    const b = parse(zFriends, body);
    return this.db.tx(async (c) => {
      const r = await c.query(`UPDATE businesses SET friends_enabled = $2, friends_max_points = $3 WHERE id = $1`, [bid, b.enabled, b.maxPoints]);
      if (!r.rowCount) throw Errors.notFound('Shop');
      await audit(c, { actorType: 'USER', actorId: a.userId, businessId: bid, action: 'admin.shop.friends', entityId: bid, data: b, ip });
      return { ok: true, friendsEnabled: b.enabled, maxPoints: b.maxPoints };
    });
  }
}

@Module({ controllers: [CustomerMukafaahController, AdminMukafaahController] })
export class MukafaahModule {}

