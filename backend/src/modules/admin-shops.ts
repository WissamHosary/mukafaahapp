import { Body, Controller, Delete, Get, HttpCode, Module, Param, Patch, Post, Put, Query } from '@nestjs/common';
import { z } from 'zod';
import { audit } from '../platform/audit.js';
import { AdminScope, Auth, ClientIp, RequireAdmin, assertShopScope, forbiddenScope, type AdminAuth, type OwnerAuth } from '../platform/auth.js';
import { CryptoService } from '../platform/crypto.js';
import { Db } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zUuid } from '../platform/validation.js';
import { createOwnerLogin, createWorker, zPassword, zUsername, zWorker } from './logins.js';
import { LedgerService } from './ledger.js';
import { MerchantController } from './merchant.js';
import { OwnerController, createShop } from './owner.js';
import { earnPercent, getSetting, prettyPhone } from './shared.js';
import { StoreOwnerController } from './store.js';

/*
 * Mukafaah Manager works on any shop the way the shop's owner would: the same
 * rules, validation and audit trail, with the shop chosen in the URL. These
 * routes reuse the owner endpoints so nothing behaves differently here.
 */

const zNewShop = z.strictObject({
  name: z.string().trim().min(2).max(80),
  category: z.string().trim().toUpperCase().regex(/^[A-Z0-9_]{2,40}$/),
  ownerPhone: z.string().min(6).max(20),
  ownerName: z.string().trim().min(1).max(60).optional(),
  branchName: z.string().trim().min(1).max(80).default('Main branch'),
  earnPercent: z.number().int().min(0).max(100).optional(),
  description: z.string().trim().max(600).optional(),
  whatsapp: z.string().trim().regex(/^\+?[0-9 ]{7,20}$/).optional(),
  instagram: z.string().trim().max(60).optional(),
  address: z.string().trim().max(160).optional(),
  city: z.string().trim().max(60).optional(),
  lat: z.number().min(-90).max(90).optional(),
  lng: z.number().min(-180).max(180).optional(),
  /** Also give the owner a Manager account limited to this shop. */
  managerAccess: z.boolean().optional(),
  // v0.8: everything set up in one go from Mukafaah Manager.
  logoMediaId: zUuid.nullable().optional(),
  coverMediaId: zUuid.nullable().optional(),
  storeEnabled: z.boolean().optional(),
  featured: z.boolean().optional(),
  /** The owner's username and password for Mukafaah Business. */
  ownerUsername: zUsername.optional(),
  ownerPassword: zPassword.optional(),
  /** Workers for the counter, each with their own username and password. */
  workers: z.array(zWorker.omit({ branchId: true })).max(50).default([]),
});
const zMonth = z.object({
  month: z.string().regex(/^\d{4}-(0[1-9]|1[0-2])$/).optional(),
  shopId: zUuid.optional(),
});

@Controller('v1/admin')
@RequireAdmin()
// Shop accounts may use these routes for their own shops only (checked in as()).
@AdminScope('SHOP')
export class AdminShopsController {
  private readonly merchant: MerchantController;
  private readonly owner: OwnerController;
  private readonly store: StoreOwnerController;

  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
    ledger: LedgerService,
  ) {
    this.merchant = new MerchantController(db);
    this.owner = new OwnerController(db, crypto, ledger);
    this.store = new StoreOwnerController(db);
  }

  /** Acts as the owner of shop [id] (after checking the shop exists). */
  private async as(a: AdminAuth, id: string): Promise<OwnerAuth> {
    const bid = parse(zUuid, id);
    assertShopScope(a, bid);
    const b = await this.db.one(`SELECT owner_user_id FROM businesses WHERE id = $1`, [bid]);
    if (!b) throw Errors.notFound('Shop');
    return { kind: 'owner', userId: a.userId, businessId: bid };
  }

  // ---------- Add a shop ----------
  @Post('shops')
  async createShop(@Auth() a: AdminAuth, @Body() body: unknown, @ClientIp() ip: string) {
    if (a.role === 'SHOP') throw forbiddenScope();
    const b = parse(zNewShop, body);
    const cat = await this.db.one(`SELECT 1 FROM categories WHERE key = $1`, [b.category]);
    if (!cat) throw Errors.validation({ category: ['UNKNOWN'] });
    const e164 = this.crypto.normalizePhone(b.ownerPhone);
    const ph = this.crypto.phoneHash(e164);
    const defaults = await getSetting<{ earnPercent?: number }>(this.db, 'defaults', {});
    const earn = b.earnPercent ?? Number(defaults.earnPercent ?? 10);
    const id = await this.db.tx(async (c) => {
      let user = (await c.query(`SELECT id, name FROM users WHERE phone_hash = $1`, [ph])).rows[0];
      if (!user) {
        user = (
          await c.query(`INSERT INTO users(phone_hash, phone_enc, phone_last4, name) VALUES ($1,$2,$3,$4) RETURNING id, name`, [
            ph,
            this.crypto.encrypt(e164),
            e164.slice(-4),
            b.ownerName ?? null,
          ])
        ).rows[0];
      } else if (!user.name && b.ownerName) {
        await c.query(`UPDATE users SET name = $2 WHERE id = $1`, [user.id, b.ownerName]);
      }
      const bid = await createShop(c, { ownerUserId: user.id, name: b.name, category: b.category, branchName: b.branchName, earnPercent: earn, addedBy: a.userId });
      await c.query(
        `UPDATE businesses SET description = $2, whatsapp = $3, instagram = $4, address = $5, city = $6, lat = $7, lng = $8 WHERE id = $1`,
        [bid, b.description ?? null, b.whatsapp ?? null, b.instagram ?? null, b.address ?? null, b.city ?? null, b.lat ?? null, b.lng ?? null],
      );
      await c.query(
        `UPDATE businesses SET logo_media_id = COALESCE($2, logo_media_id), cover_media_id = COALESCE($3, cover_media_id),
                store_enabled = COALESCE($4, store_enabled), featured = COALESCE($5, featured) WHERE id = $1`,
        [bid, b.logoMediaId ?? null, b.coverMediaId ?? null, b.storeEnabled ?? null, b.featured ?? null],
      );
      if (b.ownerUsername) {
        if (!b.ownerPassword) throw Errors.validation({ ownerPassword: ['REQUIRED'] });
        await createOwnerLogin(c, { businessId: bid, userId: user.id, username: b.ownerUsername, password: b.ownerPassword, by: a.userId });
      }
      const names = new Set<string>([b.ownerUsername ?? '']);
      for (const w of b.workers) {
        if (names.has(w.username)) throw new AppError(409, 'USERNAME_TAKEN', 'This username is already used', { username: w.username });
        names.add(w.username);
        await createWorker(c, { businessId: bid, name: w.name, username: w.username, password: w.password, canRedeem: w.canRedeem, by: a.userId });
      }
      if (b.managerAccess) {
        await c.query(`INSERT INTO admins(user_id, role) VALUES ($1, 'SHOP') ON CONFLICT (user_id) DO NOTHING`, [user.id]);
        const role = (await c.query(`SELECT role FROM admins WHERE user_id = $1`, [user.id])).rows[0]?.role;
        if (role === 'SHOP') await c.query(`INSERT INTO admin_shops(user_id, business_id) VALUES ($1,$2) ON CONFLICT DO NOTHING`, [user.id, bid]);
      }
      await audit(c, { actorType: 'USER', actorId: a.userId, businessId: bid, action: 'admin.shop.create', entityId: bid, data: { name: b.name, ownerLast4: e164.slice(-4) }, ip });
      return bid;
    });
    return { id };
  }

  // ---------- One shop: everything the owner could do ----------
  @Get('shops/:id')
  async shop(@Auth() a: AdminAuth, @Param('id') id: string) {
    const o = await this.as(a, id);
    const [profile, me, owner] = await Promise.all([
      this.merchant.profile(o),
      this.owner.me(o),
      this.db.one(
        `SELECT u.name, u.phone_last4, u.phone_enc, b.status, b.created_at, b.store_enabled, b.admin_note, b.featured_sort
           FROM businesses b JOIN users u ON u.id = b.owner_user_id WHERE b.id = $1`,
        [o.businessId],
      ),
    ]);
    return {
      ...profile,
      status: owner?.status,
      createdAt: owner?.created_at,
      storeEnabled: !!owner?.store_enabled,
      adminNote: owner?.admin_note ?? null,
      featuredSort: owner?.featured_sort ?? 0,
      owner: { name: owner?.name ?? null, phone: owner?.phone_enc ? prettyPhone(this.crypto.decrypt(owner.phone_enc)) : '' },
      branches: me.branches,
      minBillMinor: me.earningProgram.minBillMinor,
    };
  }

  @Patch('shops/:id/profile')
  async profile(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    return this.merchant.updateProfile(await this.as(a, id), body, ip);
  }

  @Post('shops/:id/banners')
  async addBanner(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown) {
    return this.merchant.addBanner(await this.as(a, id), body);
  }

  @Delete('shops/:id/banners/:bannerId')
  async deleteBanner(@Auth() a: AdminAuth, @Param('id') id: string, @Param('bannerId') bannerId: string) {
    return this.merchant.deleteBanner(await this.as(a, id), bannerId);
  }

  @Put('shops/:id/banners/order')
  async orderBanners(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown) {
    return this.merchant.orderBanners(await this.as(a, id), body);
  }

  /** Customer reviews of this shop; Mukafaah can hide one that breaks the rules. */
  @Get('shops/:id/reviews')
  async reviews(@Auth() a: AdminAuth, @Param('id') id: string) {
    const o = await this.as(a, id);
    const r = await this.db.query(
      `SELECT r.user_id, r.stars, r.comment, r.hidden, r.updated_at, u.name
         FROM business_ratings r JOIN users u ON u.id = r.user_id
        WHERE r.business_id = $1 ORDER BY r.updated_at DESC LIMIT 300`,
      [o.businessId],
    );
    return r.rows.map((x) => ({
      userId: x.user_id,
      name: x.name ?? null,
      stars: Number(x.stars),
      comment: x.comment ?? null,
      hidden: !!x.hidden,
      at: x.updated_at,
    }));
  }

  @Patch('shops/:id/reviews/:userId')
  async hideReview(@Auth() a: AdminAuth, @Param('id') id: string, @Param('userId') userId: string, @Body() body: unknown, @ClientIp() ip: string) {
    const o = await this.as(a, id);
    const b = parse(z.strictObject({ hidden: z.boolean() }), body);
    const r = await this.db.query(`UPDATE business_ratings SET hidden = $3 WHERE business_id = $1 AND user_id = $2`, [
      o.businessId,
      parse(zUuid, userId),
      b.hidden,
    ]);
    if (!r.rowCount) throw Errors.notFound('Review');
    await this.db.tx((c) =>
      audit(c, { actorType: 'USER', actorId: a.userId, businessId: o.businessId, action: b.hidden ? 'admin.review.hide' : 'admin.review.show', ip }),
    );
    return { ok: true };
  }

  /** purpose: logo | cover (applied right away) or item (for offers, rewards, products). */
  @Post('shops/:id/media')
  async media(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown) {
    return this.merchant.upload(await this.as(a, id), body);
  }

  @Get('shops/:id/offers')
  async offers(@Auth() a: AdminAuth, @Param('id') id: string) {
    return this.merchant.offers(await this.as(a, id));
  }
  @Post('shops/:id/offers')
  async createOffer(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    return this.merchant.createOffer(await this.as(a, id), body, ip);
  }
  @Patch('shops/:id/offers/:oid')
  async patchOffer(@Auth() a: AdminAuth, @Param('id') id: string, @Param('oid') oid: string, @Body() body: unknown, @ClientIp() ip: string) {
    return this.merchant.patchOffer(await this.as(a, id), oid, body, ip);
  }

  @Get('shops/:id/rewards')
  async rewards(@Auth() a: AdminAuth, @Param('id') id: string) {
    return this.merchant.rewards(await this.as(a, id));
  }
  @Post('shops/:id/rewards')
  async createReward(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown) {
    return this.merchant.createReward(await this.as(a, id), body);
  }
  @Patch('shops/:id/rewards/:rid')
  async patchReward(@Auth() a: AdminAuth, @Param('id') id: string, @Param('rid') rid: string, @Body() body: unknown) {
    return this.merchant.patchReward(await this.as(a, id), rid, body);
  }

  @Get('shops/:id/bookings')
  async bookings(@Auth() a: AdminAuth, @Param('id') id: string, @Query() q: unknown) {
    return this.merchant.bookings(await this.as(a, id), q);
  }

  // Store
  @Get('shops/:id/store')
  async storeInfo(@Auth() a: AdminAuth, @Param('id') id: string) {
    return this.store.store(await this.as(a, id));
  }
  @Put('shops/:id/store')
  async setStore(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    return this.store.setStore(await this.as(a, id), body, ip);
  }
  @Post('shops/:id/store/categories')
  async createStoreCategory(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown) {
    return this.store.createCategory(await this.as(a, id), body);
  }
  @Patch('shops/:id/store/categories/:cid')
  async patchStoreCategory(@Auth() a: AdminAuth, @Param('id') id: string, @Param('cid') cid: string, @Body() body: unknown) {
    return this.store.patchCategory(await this.as(a, id), cid, body);
  }
  @Delete('shops/:id/store/categories/:cid')
  async deleteStoreCategory(@Auth() a: AdminAuth, @Param('id') id: string, @Param('cid') cid: string) {
    return this.store.deleteCategory(await this.as(a, id), cid);
  }
  @Get('shops/:id/store/products/:pid')
  async storeProduct(@Auth() a: AdminAuth, @Param('id') id: string, @Param('pid') pid: string) {
    return this.store.product(await this.as(a, id), pid);
  }
  @Post('shops/:id/store/products')
  async createStoreProduct(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown) {
    return this.store.createProduct(await this.as(a, id), body);
  }
  @Patch('shops/:id/store/products/:pid')
  async patchStoreProduct(@Auth() a: AdminAuth, @Param('id') id: string, @Param('pid') pid: string, @Body() body: unknown) {
    return this.store.patchProduct(await this.as(a, id), pid, body);
  }
  @Get('shops/:id/orders')
  async orders(@Auth() a: AdminAuth, @Param('id') id: string) {
    return this.store.orders(await this.as(a, id));
  }
  @Post('shops/:id/orders/:oid/status')
  @HttpCode(200)
  async orderStatus(@Auth() a: AdminAuth, @Param('id') id: string, @Param('oid') oid: string, @Body() body: unknown, @ClientIp() ip: string) {
    return this.store.orderStatus(await this.as(a, id), oid, body, ip);
  }

  // Cashiers, branches, counter devices
  @Get('shops/:id/staff')
  async staff(@Auth() a: AdminAuth, @Param('id') id: string) {
    const o = await this.as(a, id);
    const [staff, devices, me] = await Promise.all([this.owner.staff(o), this.owner.devices(o), this.owner.me(o)]);
    return { staff, devices, branches: me.branches };
  }
  @Post('shops/:id/staff')
  async addStaff(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    return this.owner.addStaff(await this.as(a, id), body, ip);
  }
  @Patch('shops/:id/staff/:sid')
  async patchStaff(@Auth() a: AdminAuth, @Param('id') id: string, @Param('sid') sid: string, @Body() body: unknown, @ClientIp() ip: string) {
    return this.owner.patchStaff(await this.as(a, id), sid, body, ip);
  }
  @Post('shops/:id/branches')
  async addBranch(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown) {
    return this.owner.addBranch(await this.as(a, id), body);
  }
  @Post('shops/:id/pairing-codes')
  async pairing(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    return this.owner.pairingCode(await this.as(a, id), body, ip);
  }
  @Post('shops/:id/devices/:did/revoke')
  @HttpCode(200)
  async revoke(@Auth() a: AdminAuth, @Param('id') id: string, @Param('did') did: string, @ClientIp() ip: string) {
    return this.owner.revokeDevice(await this.as(a, id), did, ip);
  }
  @Get('shops/:id/bills')
  async bills(@Auth() a: AdminAuth, @Param('id') id: string, @Query() q: unknown) {
    return this.owner.transactions(await this.as(a, id), q);
  }

  // =====================================================================
  // Monthly report (whole network, or one shop with ?shopId=)
  // =====================================================================
  @Get('reports/monthly')
  async monthly(@Auth() a: AdminAuth, @Query() q: unknown) {
    const f = parse(zMonth, q);
    if (a.role === 'SHOP') {
      // Shop accounts only ever see one of their own shops.
      if (f.shopId) assertShopScope(a, f.shopId);
      else if (a.shopIds[0]) f.shopId = a.shopIds[0];
      else throw forbiddenScope();
    }
    const tz = 'Asia/Beirut';
    const now = await this.db.one(`SELECT to_char(now() AT TIME ZONE $1, 'YYYY-MM') AS m`, [tz]);
    const month = f.month ?? (now?.m as string);
    const [y, m] = month.split('-').map(Number);
    const from = `${month}-01`;
    const next = m === 12 ? `${y + 1}-01-01` : `${y}-${String(m + 1).padStart(2, '0')}-01`;
    const prevFrom = m === 1 ? `${y - 1}-12-01` : `${y}-${String(m - 1).padStart(2, '0')}-01`;
    const shop = f.shopId ?? null;

    const kpis = async (a: string, b: string) => {
      const r = await this.db.one(
        `SELECT
           (SELECT count(*)::int FROM users u WHERE (u.created_at AT TIME ZONE $3)::date >= $1::date AND (u.created_at AT TIME ZONE $3)::date < $2::date
              AND ($4::uuid IS NULL OR EXISTS (SELECT 1 FROM visits v WHERE v.user_id = u.id AND v.business_id = $4))) AS new_customers,
           (SELECT count(DISTINCT COALESCE(v.user_id, v.pending_holder_id))::int FROM visits v
             WHERE v.local_date >= $1::date AND v.local_date < $2::date AND v.voided_by_tx_id IS NULL AND ($4::uuid IS NULL OR v.business_id = $4)) AS active_customers,
           (SELECT count(*)::int FROM visits v WHERE v.type IN ('EARN','PREPOINT_EARN') AND v.local_date >= $1::date AND v.local_date < $2::date
              AND v.voided_by_tx_id IS NULL AND ($4::uuid IS NULL OR v.business_id = $4)) AS bills,
           (SELECT COALESCE(SUM(v.bill_minor), 0) FROM visits v WHERE v.type IN ('EARN','PREPOINT_EARN') AND v.local_date >= $1::date AND v.local_date < $2::date
              AND v.voided_by_tx_id IS NULL AND ($4::uuid IS NULL OR v.business_id = $4)) AS bills_minor,
           (SELECT COALESCE(SUM(v.points), 0) FROM visits v WHERE v.type IN ('EARN','PREPOINT_EARN') AND v.local_date >= $1::date AND v.local_date < $2::date
              AND v.voided_by_tx_id IS NULL AND ($4::uuid IS NULL OR v.business_id = $4)) AS points_issued,
           (SELECT COALESCE(SUM(v.points), 0) FROM visits v WHERE v.type = 'PREPOINT_EARN' AND v.local_date >= $1::date AND v.local_date < $2::date
              AND v.voided_by_tx_id IS NULL AND ($4::uuid IS NULL OR v.business_id = $4)) AS prepoints_issued,
           (SELECT COALESCE(SUM(v.points), 0) FROM visits v WHERE v.type = 'REDEEM' AND v.local_date >= $1::date AND v.local_date < $2::date
              AND v.voided_by_tx_id IS NULL AND ($4::uuid IS NULL OR v.business_id = $4)) AS points_redeemed,
           (SELECT count(*)::int FROM visits v WHERE v.type = 'REDEEM' AND v.local_date >= $1::date AND v.local_date < $2::date
              AND v.voided_by_tx_id IS NULL AND ($4::uuid IS NULL OR v.business_id = $4)) AS redemptions,
           (SELECT count(*)::int FROM reward_redemptions r WHERE (r.created_at AT TIME ZONE $3)::date >= $1::date AND (r.created_at AT TIME ZONE $3)::date < $2::date
              AND ($4::uuid IS NULL OR r.business_id = $4)) AS rewards_redeemed,
           (SELECT count(*)::int FROM offer_bookings k WHERE k.status = 'REDEEMED' AND (k.redeemed_at AT TIME ZONE $3)::date >= $1::date AND (k.redeemed_at AT TIME ZONE $3)::date < $2::date
              AND ($4::uuid IS NULL OR k.business_id = $4)) AS bookings_used,
           (SELECT count(*)::int FROM visits v WHERE v.ref_type = 'OFFER' AND v.local_date >= $1::date AND v.local_date < $2::date
              AND v.voided_by_tx_id IS NULL AND ($4::uuid IS NULL OR v.business_id = $4)) AS walkin_offers_used,
           (SELECT count(*)::int FROM offer_bookings k WHERE (k.created_at AT TIME ZONE $3)::date >= $1::date AND (k.created_at AT TIME ZONE $3)::date < $2::date
              AND ($4::uuid IS NULL OR k.business_id = $4)) AS bookings_requested,
           (SELECT count(*)::int FROM offer_bookings k WHERE k.status IN ('ACCEPTED','REDEEMED') AND (k.created_at AT TIME ZONE $3)::date >= $1::date AND (k.created_at AT TIME ZONE $3)::date < $2::date
              AND ($4::uuid IS NULL OR k.business_id = $4)) AS bookings_accepted,
           (SELECT count(*)::int FROM whatsapp_orders w WHERE (w.created_at AT TIME ZONE $3)::date >= $1::date AND (w.created_at AT TIME ZONE $3)::date < $2::date
              AND ($4::uuid IS NULL OR w.business_id = $4)) AS orders,
           (SELECT COALESCE(SUM(w.total_minor), 0) FROM whatsapp_orders w WHERE w.status <> 'CANCELLED' AND (w.created_at AT TIME ZONE $3)::date >= $1::date AND (w.created_at AT TIME ZONE $3)::date < $2::date
              AND ($4::uuid IS NULL OR w.business_id = $4)) AS orders_minor,
           (SELECT count(*)::int FROM whatsapp_orders w WHERE w.status = 'COMPLETED' AND (w.created_at AT TIME ZONE $3)::date >= $1::date AND (w.created_at AT TIME ZONE $3)::date < $2::date
              AND ($4::uuid IS NULL OR w.business_id = $4)) AS orders_completed,
           (SELECT count(*)::int FROM businesses b WHERE (b.created_at AT TIME ZONE $3)::date >= $1::date AND (b.created_at AT TIME ZONE $3)::date < $2::date
              AND ($4::uuid IS NULL OR b.id = $4)) AS new_shops`,
        [a, b, tz, shop],
      );
      const out: Record<string, number> = {};
      for (const [k, v] of Object.entries(r ?? {})) out[k.replace(/_([a-z])/g, (_, ch: string) => ch.toUpperCase())] = Number(v);
      out.avgBillMinor = out.bills ? Math.round(out.billsMinor / out.bills) : 0;
      return out;
    };

    const [cur, prev, daily, hours, byCat, shops, cashiers, totals, tiers] = await Promise.all([
      kpis(from, next),
      kpis(prevFrom, from),
      this.db.query(
        `SELECT d::date::text AS date,
                COALESCE((SELECT count(*) FROM visits v WHERE v.local_date = d::date AND v.type IN ('EARN','PREPOINT_EARN') AND v.voided_by_tx_id IS NULL AND ($3::uuid IS NULL OR v.business_id = $3)), 0)::int AS bills,
                COALESCE((SELECT SUM(v.bill_minor) FROM visits v WHERE v.local_date = d::date AND v.type IN ('EARN','PREPOINT_EARN') AND v.voided_by_tx_id IS NULL AND ($3::uuid IS NULL OR v.business_id = $3)), 0) AS bills_minor,
                COALESCE((SELECT SUM(v.points) FROM visits v WHERE v.local_date = d::date AND v.type IN ('EARN','PREPOINT_EARN') AND v.voided_by_tx_id IS NULL AND ($3::uuid IS NULL OR v.business_id = $3)), 0) AS issued,
                COALESCE((SELECT SUM(v.points) FROM visits v WHERE v.local_date = d::date AND v.type = 'REDEEM' AND v.voided_by_tx_id IS NULL AND ($3::uuid IS NULL OR v.business_id = $3)), 0) AS redeemed,
                COALESCE((SELECT count(*) FROM users u WHERE (u.created_at AT TIME ZONE 'Asia/Beirut')::date = d::date AND $3::uuid IS NULL), 0)::int AS new_customers,
                COALESCE((SELECT count(*) FROM whatsapp_orders w WHERE (w.created_at AT TIME ZONE 'Asia/Beirut')::date = d::date AND ($3::uuid IS NULL OR w.business_id = $3)), 0)::int AS orders
           FROM generate_series($1::date, $2::date - 1, interval '1 day') d ORDER BY d`,
        [from, next, shop],
      ),
      this.db.query(
        `SELECT extract(hour FROM v.created_at AT TIME ZONE 'Asia/Beirut')::int AS h, extract(isodow FROM v.created_at AT TIME ZONE 'Asia/Beirut')::int AS dow, count(*)::int AS n
           FROM visits v WHERE v.type IN ('EARN','PREPOINT_EARN') AND v.local_date >= $1::date AND v.local_date < $2::date AND v.voided_by_tx_id IS NULL
            AND ($3::uuid IS NULL OR v.business_id = $3)
          GROUP BY 1, 2`,
        [from, next, shop],
      ),
      this.db.query(
        `SELECT c.key, c.name_en, count(v.*)::int AS bills, COALESCE(SUM(v.bill_minor), 0) AS bills_minor, COALESCE(SUM(v.points), 0) AS issued
           FROM visits v JOIN businesses b ON b.id = v.business_id JOIN categories c ON c.key = b.category
          WHERE v.type IN ('EARN','PREPOINT_EARN') AND v.local_date >= $1::date AND v.local_date < $2::date AND v.voided_by_tx_id IS NULL
            AND ($3::uuid IS NULL OR v.business_id = $3)
          GROUP BY c.key, c.name_en ORDER BY bills_minor DESC`,
        [from, next, shop],
      ),
      this.db.query(
        `SELECT b.id, b.name, b.category, p.earn_points_per_unit, p.redeem_points_per_unit, b.status,
                count(v.*) FILTER (WHERE v.type IN ('EARN','PREPOINT_EARN'))::int AS bills,
                COALESCE(SUM(v.bill_minor) FILTER (WHERE v.type IN ('EARN','PREPOINT_EARN')), 0) AS bills_minor,
                COALESCE(SUM(v.points) FILTER (WHERE v.type IN ('EARN','PREPOINT_EARN')), 0) AS issued,
                COALESCE(SUM(v.points) FILTER (WHERE v.type = 'REDEEM'), 0) AS redeemed,
                count(DISTINCT COALESCE(v.user_id, v.pending_holder_id))::int AS customers,
                (SELECT count(*)::int FROM whatsapp_orders w WHERE w.business_id = b.id AND (w.created_at AT TIME ZONE 'Asia/Beirut')::date >= $1::date AND (w.created_at AT TIME ZONE 'Asia/Beirut')::date < $2::date) AS orders,
                (SELECT COALESCE(SUM(w.total_minor), 0) FROM whatsapp_orders w WHERE w.business_id = b.id AND w.status <> 'CANCELLED' AND (w.created_at AT TIME ZONE 'Asia/Beirut')::date >= $1::date AND (w.created_at AT TIME ZONE 'Asia/Beirut')::date < $2::date) AS orders_minor,
                (SELECT count(*)::int FROM offer_bookings k WHERE k.business_id = b.id AND k.status = 'REDEEMED' AND (k.redeemed_at AT TIME ZONE 'Asia/Beirut')::date >= $1::date AND (k.redeemed_at AT TIME ZONE 'Asia/Beirut')::date < $2::date) AS offers_used,
                (SELECT count(*)::int FROM reward_redemptions r WHERE r.business_id = b.id AND (r.created_at AT TIME ZONE 'Asia/Beirut')::date >= $1::date AND (r.created_at AT TIME ZONE 'Asia/Beirut')::date < $2::date) AS rewards_redeemed,
                (SELECT ROUND(AVG(br.stars)::numeric, 1) FROM business_ratings br WHERE br.business_id = b.id) AS rating
           FROM businesses b JOIN programs p ON p.id = b.earning_program_id
           LEFT JOIN visits v ON v.business_id = b.id AND v.local_date >= $1::date AND v.local_date < $2::date AND v.voided_by_tx_id IS NULL
          WHERE ($3::uuid IS NULL OR b.id = $3)
          GROUP BY b.id, p.id ORDER BY bills_minor DESC, b.name LIMIT 500`,
        [from, next, shop],
      ),
      this.db.query(
        `SELECT s.name, s.role, b.name AS shop, count(*)::int AS bills, COALESCE(SUM(v.bill_minor), 0) AS bills_minor, COALESCE(SUM(v.points), 0) AS issued
           FROM visits v JOIN staff s ON s.id = v.staff_id JOIN businesses b ON b.id = v.business_id
          WHERE v.type IN ('EARN','PREPOINT_EARN') AND v.local_date >= $1::date AND v.local_date < $2::date AND v.voided_by_tx_id IS NULL
            AND ($3::uuid IS NULL OR v.business_id = $3)
          GROUP BY s.id, b.id ORDER BY bills DESC LIMIT 15`,
        [from, next, shop],
      ),
      this.db.one(
        `SELECT (SELECT count(*)::int FROM users) AS customers,
                (SELECT count(*)::int FROM businesses WHERE status = 'ACTIVE') AS shops,
                (SELECT COALESCE(SUM(ab.balance), 0) FROM ledger_accounts la JOIN account_balances ab ON ab.account_id = la.id
                  WHERE la.owner_type IN ('CUSTOMER','PENDING') AND ($1::uuid IS NULL OR la.program_id = (SELECT earning_program_id FROM businesses WHERE id = $1))) AS outstanding`,
        [shop],
      ),
      this.db.query(
        `SELECT 1 AS unused`,
      ),
    ]);
    // Tiers follow total spend (users.tier); for one shop, count that shop's customers.
    void tiers;
    const tierRows = await this.db.query(
      `SELECT u.tier, count(*)::int AS n FROM users u
        WHERE $1::uuid IS NULL OR EXISTS (SELECT 1 FROM visits v WHERE v.user_id = u.id AND v.business_id = $1)
        GROUP BY u.tier`,
      [shop],
    );
    const tierCount: Record<string, number> = { SILVER: 0, GOLD: 0, PLATINUM: 0 };
    for (const r of tierRows.rows) tierCount[String(r.tier)] = Number(r.n);
    const heat: number[][] = Array.from({ length: 7 }, () => Array(24).fill(0));
    for (const r of hours.rows) heat[Number(r.dow) - 1][Number(r.h)] = Number(r.n);
    const pct = (e: number, r: number) => (r === 0 ? 0 : Math.round((e * 100) / r));

    return {
      month,
      prevMonth: prevFrom.slice(0, 7),
      shopId: shop,
      kpis: cur,
      prev,
      // Platform-wide totals are Mukafaah's numbers; shop accounts get their own shop's view.
      totals: {
        customers: a.role === 'SHOP' ? Number(cur.activeCustomers ?? 0) : Number(totals?.customers ?? 0),
        activeShops: a.role === 'SHOP' ? 1 : Number(totals?.shops ?? 0),
        outstandingPoints: a.role === 'SHOP' ? 0 : Number(totals?.outstanding ?? 0),
      },
      daily: daily.rows.map((d) => ({
        date: d.date,
        bills: Number(d.bills),
        billsMinor: Number(d.bills_minor),
        pointsIssued: Number(d.issued),
        pointsRedeemed: Number(d.redeemed),
        newCustomers: Number(d.new_customers),
        orders: Number(d.orders),
      })),
      heatmap: heat,
      categories: byCat.rows.map((c) => ({ key: c.key, name: c.name_en, bills: c.bills, billsMinor: Number(c.bills_minor), pointsIssued: Number(c.issued) })),
      shops: shops.rows.map((s) => ({
        id: s.id,
        name: s.name,
        category: s.category,
        status: s.status,
        earnPercent: earnPercent(Number(s.earn_points_per_unit), Number(s.redeem_points_per_unit)),
        bills: s.bills,
        billsMinor: Number(s.bills_minor),
        pointsIssued: Number(s.issued),
        pointsRedeemed: Number(s.redeemed),
        redeemRate: pct(Number(s.redeemed), Number(s.issued)),
        customers: s.customers,
        orders: s.orders,
        ordersMinor: Number(s.orders_minor),
        offersUsed: s.offers_used,
        rewardsRedeemed: s.rewards_redeemed,
        rating: s.rating == null ? null : Number(s.rating),
      })),
      cashiers: cashiers.rows.map((c) => ({
        name: c.role === 'OWNER' ? `${c.name} (owner)` : c.name,
        shop: c.shop,
        bills: c.bills,
        billsMinor: Number(c.bills_minor),
        pointsIssued: Number(c.issued),
      })),
      tiers: tierCount,
    };
  }
}

@Module({ controllers: [AdminShopsController] })
export class AdminShopsModule {}
