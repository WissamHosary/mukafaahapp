import { Body, Controller, Delete, Get, HttpCode, Module, Param, Patch, Post, Put, Query } from '@nestjs/common';
import { z } from 'zod';
import { audit } from '../platform/audit.js';
import {
  AdminScope,
  Auth,
  ClientIp,
  RequireAdmin,
  assertShopScope,
  forbiddenScope,
  type AdminAuth,
  type AdminRole,
} from '../platform/auth.js';
import { CryptoService } from '../platform/crypto.js';
import { Db, type Tx } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zUuid } from '../platform/validation.js';
import { saveImage } from './media.js';
import { clearSettingsCache, earnPercent, loadTierRows, mediaUrl } from './shared.js';

const zKey = z.string().trim().toUpperCase().regex(/^[A-Z0-9_]{2,40}$/);
const zQ = z.object({ q: z.string().trim().max(60).optional(), status: z.string().max(20).optional() });

const zShopPatch = z.strictObject({
  name: z.string().trim().min(2).max(80).optional(),
  category: zKey.optional(),
  /** Points back as % of each bill ("deduction factor"). Admin only. */
  earnPercent: z.number().int().min(0).max(100).optional(),
  featured: z.boolean().optional(),
  featuredSort: z.number().int().min(0).max(10000).optional(),
  listed: z.boolean().optional(),
  status: z.enum(['ACTIVE', 'SUSPENDED']).optional(),
  adminNote: z.string().trim().max(500).nullable().optional(),
});

const zColor = z.string().trim().regex(/^#[0-9A-Fa-f]{6}$/);
const catFields = {
  nameEn: z.string().trim().min(1).max(60),
  nameAr: z.string().trim().min(1).max(60),
  emoji: z.string().trim().max(16).nullable().optional(),
  iconId: zUuid.nullable().optional(),
  /** v0.7 name for iconId (null clears the icon). */
  iconMediaId: zUuid.nullable().optional(),
  color: zColor.nullable().optional(),
  sort: z.number().int().min(0).max(100000),
  active: z.boolean(),
};
const zCategory = z.strictObject({ key: zKey, ...catFields, sort: catFields.sort.default(500), active: catFields.active.default(true) });
const zCategoryPatch = z.strictObject(catFields).partial();

const bannerFields = {
  titleEn: z.string().trim().max(80).nullable().optional(),
  titleAr: z.string().trim().max(80).nullable().optional(),
  subtitleEn: z.string().trim().max(160).nullable().optional(),
  subtitleAr: z.string().trim().max(160).nullable().optional(),
  imageId: zUuid.nullable().optional(),
  /** v0.7 name for imageId. */
  mediaId: zUuid.nullable().optional(),
  style: z.enum(['PURPLE', 'YELLOW', 'IMAGE']),
  actionType: z.enum(['NONE', 'SHOP', 'CATEGORY', 'OFFERS', 'URL']),
  actionValue: z.string().trim().max(300).nullable().optional(),
  startsAt: z.iso.datetime({ offset: true }).nullable().optional(),
  endsAt: z.iso.datetime({ offset: true }).nullable().optional(),
  sort: z.number().int().min(0).max(100000),
  active: z.boolean(),
};
const zBanner = z.strictObject({
  ...bannerFields,
  style: bannerFields.style.default('PURPLE'),
  actionType: bannerFields.actionType.default('NONE'),
  sort: bannerFields.sort.default(500),
  active: bannerFields.active.default(true),
});
const zBannerPatch = z.strictObject(bannerFields).partial();

const sectionFields = {
  type: z.enum(['CATEGORIES', 'FEATURED_SHOPS', 'DISCOVER_SHOPS', 'NEW_OFFERS', 'CATEGORY_SHOPS', 'PICKED_SHOPS', 'REWARDS', 'RECENT_ACTIVITY']),
  layout: z.enum(['CAROUSEL', 'GRID', 'ROW']).nullable().optional(),
  pickMode: z.enum(['AUTO', 'PICKED']),
  offerIds: z.array(zUuid).max(50),
  rewardIds: z.array(zUuid).max(50),
  titleEn: z.string().trim().max(60).nullable().optional(),
  titleAr: z.string().trim().max(60).nullable().optional(),
  categoryKey: zKey.nullable().optional(),
  shopIds: z.array(zUuid).max(50),
  maxItems: z.number().int().min(1).max(50),
  sort: z.number().int().min(0).max(100000),
  active: z.boolean(),
};
const zSection = z.strictObject({
  ...sectionFields,
  shopIds: sectionFields.shopIds.default([]),
  offerIds: sectionFields.offerIds.default([]),
  rewardIds: sectionFields.rewardIds.default([]),
  pickMode: sectionFields.pickMode.default('AUTO'),
  maxItems: sectionFields.maxItems.default(12),
  sort: sectionFields.sort.default(500),
  active: sectionFields.active.default(true),
});
const zSectionPatch = z.strictObject(sectionFields).partial();

const zReorder = z.strictObject({ type: z.enum(['banners', 'sections', 'categories']), ids: z.array(z.string().max(60)).min(1).max(200) });
const zOfferPatch = z.strictObject({ hidden: z.boolean() });
const zUpload = z.strictObject({ dataBase64: z.string().min(20).max(4_500_000) });
const zAdmin = z.strictObject({ phone: z.string().min(6).max(20), role: z.enum(['ADMIN', 'EDITOR']).default('ADMIN') });
const zAccount = z.strictObject({
  phone: z.string().min(6).max(20),
  name: z.string().trim().min(1).max(60),
  role: z.enum(['ADMIN', 'EDITOR', 'SHOP']),
  shopIds: z.array(zUuid).max(200).optional(),
});
const zAccountPatch = z.strictObject({
  name: z.string().trim().min(1).max(60).optional(),
  role: z.enum(['OWNER', 'ADMIN', 'EDITOR', 'SHOP']).optional(),
  active: z.boolean().optional(),
  shopIds: z.array(zUuid).max(200).optional(),
});
const zTierIn = z.strictObject({
  code: z.string().trim().toUpperCase().regex(/^[A-Z_]{2,20}$/),
  name: z.string().trim().min(1).max(40),
  nameAr: z.string().trim().min(1).max(40).optional(),
  minSpendMinor: z.number().int().min(0).max(2_000_000_000),
  bonusPoints: z.number().int().min(0).max(100000),
  color: zColor.nullable().optional(),
  perks: z.string().trim().max(1000).nullable().optional(),
  active: z.boolean().default(true),
});
const zTiers = z
  .strictObject({ tiers: z.array(zTierIn).min(1).max(20) })
  .refine((v) => new Set(v.tiers.map((t) => t.code)).size === v.tiers.length, { message: 'Tier codes must be unique', path: ['tiers'] })
  .refine((v) => v.tiers[0].minSpendMinor === 0, { message: 'The first tier must start at 0', path: ['tiers'] })
  .refine((v) => v.tiers.every((t, i) => i === 0 || t.minSpendMinor > v.tiers[i - 1].minSpendMinor), {
    message: 'Minimum spend must strictly increase',
    path: ['tiers'],
  });
const BANNER_LAYOUT = z.enum(['UNO', 'DUO', 'TRIO']);

const SETTING_SCHEMAS: Record<string, z.ZodType> = {
  tiers: z.strictObject({ GOLD: z.number().int().min(1).max(10_000_000), PLATINUM: z.number().int().min(2).max(100_000_000) }).refine((v) => v.PLATINUM > v.GOLD, 'PLATINUM must be above GOLD'),
  transfer: z.strictObject({
    minPoints: z.number().int().min(1).max(100000),
    dailyMaxPoints: z.number().int().min(1).max(10_000_000),
    dailyMaxCount: z.number().int().min(1).max(1000),
    minTier: z.enum(['SILVER', 'GOLD', 'PLATINUM']),
  }),
  referral: z.strictObject({ windowDays: z.number().int().min(0).max(365) }),
  support: z.strictObject({ whatsapp: z.string().regex(/^\+?[0-9 ]{7,20}$/).nullable(), instagram: z.string().max(60).nullable() }),
  defaults: z.strictObject({ earnPercent: z.number().int().min(0).max(100) }),
  // "DUO", or { "layout": "DUO" } / { "value": "DUO" }; stored as the plain string.
  'home.bannerLayout': z
    .union([BANNER_LAYOUT, z.strictObject({ layout: BANNER_LAYOUT }), z.strictObject({ value: BANNER_LAYOUT })])
    .transform((v) => (typeof v === 'string' ? v : 'layout' in v ? v.layout : v.value)),
};
/** Settings only OWNER/ADMIN may change. */
const FULL_SETTINGS = new Set(['tiers', 'transfer', 'referral', 'defaults']);

/** Fields set on a row; undefined = leave as is, null clears. */
function setClause(map: Record<string, unknown>, startAt: number) {
  const cols: string[] = [];
  const vals: unknown[] = [];
  for (const [col, v] of Object.entries(map)) {
    if (v === undefined) continue;
    vals.push(v);
    cols.push(`${col} = $${startAt + vals.length - 1}`);
  }
  return { sql: cols.join(', '), vals };
}

const bannerJson = (b: any) => ({
  id: b.id,
  titleEn: b.title_en,
  titleAr: b.title_ar,
  subtitleEn: b.subtitle_en,
  subtitleAr: b.subtitle_ar,
  imageId: b.media_id,
  mediaId: b.media_id,
  imageUrl: mediaUrl(b.media_id),
  style: b.style,
  actionType: b.action_type,
  actionValue: b.action_value,
  startsAt: b.starts_at,
  endsAt: b.ends_at,
  sort: b.sort,
  active: b.active,
});
const categoryJson = (c: any) => ({
  key: c.key,
  nameEn: c.name_en,
  nameAr: c.name_ar,
  emoji: c.emoji,
  iconId: c.icon_media_id,
  iconMediaId: c.icon_media_id,
  iconUrl: mediaUrl(c.icon_media_id),
  color: c.color ?? null,
  sort: c.sort,
  active: c.active,
  shops: Number(c.shops ?? 0),
});
const sectionJson = (s: any) => ({
  id: s.id,
  type: s.type,
  titleEn: s.title_en,
  titleAr: s.title_ar,
  categoryKey: s.category_key,
  shopIds: s.shop_ids ?? [],
  offerIds: s.offer_ids ?? [],
  rewardIds: s.reward_ids ?? [],
  layout: s.layout ?? null,
  pickMode: s.pick_mode ?? 'AUTO',
  maxItems: s.max_items,
  sort: s.sort,
  active: s.active,
});

/** Mukafaah Manager: content, shops and settings for the whole platform. */
@Controller('v1/admin')
@RequireAdmin()
export class AdminController {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
  ) {}

  private log(a: AdminAuth, action: string, entityId?: string, data?: Record<string, unknown>, ip?: string) {
    return this.db.tx((c) => audit(c, { actorType: 'USER', actorId: a.userId, action: `admin.${action}`, entityId, data, ip }));
  }

  @Get('me')
  @AdminScope('SHOP')
  async me(@Auth() a: AdminAuth) {
    const u = await this.db.one(`SELECT name, phone_last4 FROM users WHERE id = $1`, [a.userId]);
    const shops =
      a.role === 'SHOP'
        ? (await this.db.query(`SELECT id, name FROM businesses WHERE id = ANY($1::uuid[]) ORDER BY name`, [a.shopIds])).rows.map((x) => ({ id: x.id, name: x.name }))
        : [];
    return { userId: a.userId, name: u?.name ?? null, phoneLast4: u?.phone_last4 ?? null, role: a.role, shops };
  }

  // ---------- Overview ----------
  @Get('overview')
  async overview() {
    const r = await this.db.one(
      `SELECT
         (SELECT count(*)::int FROM businesses) AS shops,
         (SELECT count(*)::int FROM businesses WHERE status = 'ACTIVE' AND listed) AS live_shops,
         (SELECT count(*)::int FROM users) AS users,
         (SELECT count(*)::int FROM users WHERE created_at > now() - interval '7 days') AS new_users_7d,
         (SELECT COALESCE(SUM(points), 0) FROM visits WHERE type IN ('EARN','PREPOINT_EARN') AND voided_by_tx_id IS NULL AND created_at > now() - interval '30 days') AS issued_30d,
         (SELECT COALESCE(SUM(points), 0) FROM visits WHERE type = 'REDEEM' AND voided_by_tx_id IS NULL AND created_at > now() - interval '30 days') AS redeemed_30d,
         (SELECT COALESCE(SUM(bill_minor), 0) FROM visits WHERE type IN ('EARN','PREPOINT_EARN') AND voided_by_tx_id IS NULL AND created_at > now() - interval '30 days') AS bills_30d,
         (SELECT count(*)::int FROM offers WHERE status = 'ACTIVE' AND NOT hidden_by_admin) AS live_offers,
         (SELECT count(*)::int FROM offer_bookings WHERE status = 'REQUESTED') AS pending_bookings,
         (SELECT count(*)::int FROM whatsapp_orders WHERE created_at > now() - interval '30 days') AS orders_30d`,
    );
    const top = await this.db.query(
      `SELECT b.id, b.name, count(v.*)::int AS visits, COALESCE(SUM(v.bill_minor), 0) AS bills
         FROM businesses b LEFT JOIN visits v ON v.business_id = b.id AND v.created_at > now() - interval '30 days' AND v.voided_by_tx_id IS NULL
        GROUP BY b.id ORDER BY visits DESC, b.name LIMIT 8`,
    );
    return {
      shops: r.shops,
      liveShops: r.live_shops,
      users: r.users,
      newUsers7d: r.new_users_7d,
      issued30d: Number(r.issued_30d),
      redeemed30d: Number(r.redeemed_30d),
      bills30dMinor: Number(r.bills_30d),
      liveOffers: r.live_offers,
      pendingBookings: r.pending_bookings,
      orders30d: r.orders_30d,
      topShops: top.rows.map((x) => ({ id: x.id, name: x.name, visits: x.visits, billsMinor: Number(x.bills) })),
    };
  }

  // ---------- Shops ----------
  @Get('shops')
  @AdminScope('SHOP')
  async shops(@Auth() a: AdminAuth, @Query() q: unknown) {
    const f = parse(zQ, q);
    const r = await this.db.query(
      `SELECT b.*, p.earn_points_per_unit, p.redeem_points_per_unit, p.type AS program_type, u.phone_last4 AS owner_last4, u.name AS owner_name,
              (SELECT count(*)::int FROM visits v WHERE v.business_id = b.id AND v.created_at > now() - interval '30 days') AS visits_30d,
              (SELECT count(*)::int FROM offers o WHERE o.business_id = b.id AND o.status = 'ACTIVE') AS offers
         FROM businesses b JOIN programs p ON p.id = b.earning_program_id JOIN users u ON u.id = b.owner_user_id
        WHERE ($1::text IS NULL OR b.name ILIKE '%' || $1 || '%' OR b.city ILIKE '%' || $1 || '%')
          AND ($2::text IS NULL OR b.status = $2)
          AND ($3::uuid[] IS NULL OR b.id = ANY($3::uuid[]))
        ORDER BY b.featured DESC, b.featured_sort, b.created_at DESC LIMIT 500`,
      [f.q || null, f.status || null, a.role === 'SHOP' ? a.shopIds : null],
    );
    return r.rows.map((b) => ({
      id: b.id,
      name: b.name,
      category: b.category,
      city: b.city,
      status: b.status,
      listed: b.listed,
      featured: b.featured,
      featuredSort: b.featured_sort,
      programType: b.program_type,
      earnPercent: earnPercent(Number(b.earn_points_per_unit), Number(b.redeem_points_per_unit)),
      logoUrl: mediaUrl(b.logo_media_id),
      coverUrl: mediaUrl(b.cover_media_id),
      owner: b.owner_name ?? `•••• ${b.owner_last4}`,
      whatsapp: !!b.whatsapp,
      storeEnabled: !!b.store_enabled,
      friendsEnabled: !!b.friends_enabled,
      friendsMaxPoints: Number(b.friends_max_points ?? 0),
      visits30d: b.visits_30d,
      offers: b.offers,
      adminNote: b.admin_note ?? null,
      createdAt: b.created_at,
    }));
  }

  @Patch('shops/:id')
  @AdminScope('SHOP')
  async patchShop(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const bid = parse(zUuid, id);
    const b = parse(zShopPatch, body);
    assertShopScope(a, bid);
    // Shop accounts may rename their shop and set the points %, nothing that is Mukafaah's call.
    if (a.role === 'SHOP' && [b.category, b.featured, b.featuredSort, b.listed, b.status, b.adminNote].some((v) => v !== undefined)) {
      throw forbiddenScope();
    }
    await this.db.tx(async (c) => {
      const s = setClause(
        {
          name: b.name,
          category: b.category,
          featured: b.featured,
          featured_sort: b.featuredSort,
          listed: b.listed,
          status: b.status,
          admin_note: b.adminNote,
        },
        2,
      );
      if (s.vals.length) {
        const r = await c.query(`UPDATE businesses SET ${s.sql} WHERE id = $1`, [bid, ...s.vals]);
        if (!r.rowCount) throw Errors.notFound('Shop');
      }
      if (b.earnPercent !== undefined) {
        // 100 points = $1 off, so earning N points per $1 gives back exactly N% of the bill.
        const earn = b.earnPercent;
        await c.query(
          `UPDATE programs SET earn_points_per_unit = $2, redeem_points_per_unit = 100
            WHERE id = (SELECT earning_program_id FROM businesses WHERE id = $1)`,
          [bid, earn],
        );
      }
      if (b.name) await c.query(`UPDATE programs SET name = $2 WHERE owner_business_id = $1 AND type = 'IN_STORE'`, [bid, b.name]);
      await audit(c, { actorType: 'USER', actorId: a.userId, businessId: bid, action: 'admin.shop.update', entityId: bid, data: b, ip });
    });
    return { ok: true };
  }

  // ---------- Categories ----------
  @Get('categories')
  async categories() {
    const r = await this.db.query(
      `SELECT c.*, (SELECT count(*)::int FROM businesses b WHERE b.category = c.key) AS shops FROM categories c ORDER BY c.sort, c.name_en`,
    );
    return r.rows.map(categoryJson);
  }

  @Post('categories')
  async createCategory(@Auth() a: AdminAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zCategory, body);
    const exists = await this.db.one(`SELECT 1 FROM categories WHERE key = $1`, [b.key]);
    if (exists) throw new AppError(409, 'CATEGORY_EXISTS', 'A category with this key already exists');
    await this.db.query(
      `INSERT INTO categories(key, name_en, name_ar, emoji, icon_media_id, color, sort, active) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
      [b.key, b.nameEn, b.nameAr, b.emoji ?? null, (b.iconMediaId !== undefined ? b.iconMediaId : b.iconId) ?? null, b.color ?? null, b.sort, b.active],
    );
    await this.log(a, 'category.create', b.key, b, ip);
    return { key: b.key };
  }

  @Patch('categories/:key')
  async patchCategory(@Auth() a: AdminAuth, @Param('key') key: string, @Body() body: unknown, @ClientIp() ip: string) {
    const k = parse(zKey, key);
    const b = parse(zCategoryPatch, body);
    const icon = b.iconMediaId !== undefined ? b.iconMediaId : b.iconId;
    const s = setClause({ name_en: b.nameEn, name_ar: b.nameAr, emoji: b.emoji, icon_media_id: icon, color: b.color, sort: b.sort, active: b.active }, 2);
    if (s.vals.length) {
      const r = await this.db.query(`UPDATE categories SET ${s.sql} WHERE key = $1`, [k, ...s.vals]);
      if (!r.rowCount) throw Errors.notFound('Category');
    }
    await this.log(a, 'category.update', k, b, ip);
    return { ok: true };
  }

  /** Removes a category. Shops in it must be moved to another category first. */
  @Delete('categories/:key')
  async deleteCategory(@Auth() a: AdminAuth, @Param('key') key: string, @ClientIp() ip: string) {
    const k = parse(zKey, key);
    await this.db.tx(async (c) => {
      const used = (await c.query(`SELECT count(*)::int AS n FROM businesses WHERE category = $1`, [k])).rows[0].n;
      if (used) throw new AppError(409, 'CATEGORY_IN_USE', `Move its ${used} shop${used === 1 ? '' : 's'} to another category first`, { shops: used });
      await c.query(`DELETE FROM home_sections WHERE category_key = $1`, [k]);
      const r = await c.query(`DELETE FROM categories WHERE key = $1`, [k]);
      if (!r.rowCount) throw Errors.notFound('Category');
    });
    await this.log(a, 'category.delete', k, undefined, ip);
    return { ok: true };
  }

  // ---------- Banners ----------
  @Get('banners')
  async banners() {
    const r = await this.db.query(`SELECT * FROM banners ORDER BY sort, created_at`);
    return r.rows.map(bannerJson);
  }

  @Post('banners')
  async createBanner(@Auth() a: AdminAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zBanner, body);
    const r = await this.db.one(
      `INSERT INTO banners(title_en, title_ar, subtitle_en, subtitle_ar, media_id, style, action_type, action_value, starts_at, ends_at, sort, active)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12) RETURNING id`,
      [
        b.titleEn ?? null,
        b.titleAr ?? null,
        b.subtitleEn ?? null,
        b.subtitleAr ?? null,
        (b.mediaId !== undefined ? b.mediaId : b.imageId) ?? null,
        b.style,
        b.actionType,
        b.actionValue ?? null,
        b.startsAt ?? null,
        b.endsAt ?? null,
        b.sort,
        b.active,
      ],
    );
    await this.log(a, 'banner.create', r.id, undefined, ip);
    return { id: r.id };
  }

  @Patch('banners/:id')
  async patchBanner(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const bid = parse(zUuid, id);
    const b = parse(zBannerPatch, body);
    const s = setClause(
      {
        title_en: b.titleEn,
        title_ar: b.titleAr,
        subtitle_en: b.subtitleEn,
        subtitle_ar: b.subtitleAr,
        media_id: b.mediaId !== undefined ? b.mediaId : b.imageId,
        style: b.style,
        action_type: b.actionType,
        action_value: b.actionValue,
        starts_at: b.startsAt,
        ends_at: b.endsAt,
        sort: b.sort,
        active: b.active,
      },
      2,
    );
    if (s.vals.length) {
      const r = await this.db.query(`UPDATE banners SET ${s.sql}, updated_at = now() WHERE id = $1`, [bid, ...s.vals]);
      if (!r.rowCount) throw Errors.notFound('Banner');
    }
    await this.log(a, 'banner.update', bid, undefined, ip);
    return { ok: true };
  }

  @Delete('banners/:id')
  async deleteBanner(@Auth() a: AdminAuth, @Param('id') id: string, @ClientIp() ip: string) {
    const bid = parse(zUuid, id);
    const r = await this.db.query(`DELETE FROM banners WHERE id = $1`, [bid]);
    if (!r.rowCount) throw Errors.notFound('Banner');
    await this.log(a, 'banner.delete', bid, undefined, ip);
    return { ok: true };
  }

  // ---------- Home sections ----------
  @Get('sections')
  async sections() {
    const r = await this.db.query(`SELECT * FROM home_sections ORDER BY sort, created_at`);
    return r.rows.map(sectionJson);
  }

  @Post('sections')
  async createSection(@Auth() a: AdminAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zSection, body);
    if (b.type === 'CATEGORY_SHOPS' && !b.categoryKey) throw Errors.validation({ categoryKey: ['REQUIRED'] });
    const r = await this.db.one(
      `INSERT INTO home_sections(type, title_en, title_ar, category_key, shop_ids, max_items, sort, active, layout, pick_mode, offer_ids, reward_ids)
       VALUES ($1,$2,$3,$4,$5::uuid[],$6,$7,$8,$9,$10,$11::uuid[],$12::uuid[]) RETURNING id`,
      [
        b.type, b.titleEn ?? null, b.titleAr ?? null, b.categoryKey ?? null, b.shopIds, b.maxItems, b.sort, b.active,
        b.layout ?? null, b.pickMode, b.offerIds, b.rewardIds,
      ],
    );
    await this.log(a, 'section.create', r.id, undefined, ip);
    return { id: r.id };
  }

  @Patch('sections/:id')
  async patchSection(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const sid = parse(zUuid, id);
    const b = parse(zSectionPatch, body);
    const s = setClause(
      {
        type: b.type,
        title_en: b.titleEn,
        title_ar: b.titleAr,
        category_key: b.categoryKey,
        shop_ids: b.shopIds,
        offer_ids: b.offerIds,
        reward_ids: b.rewardIds,
        layout: b.layout,
        pick_mode: b.pickMode,
        max_items: b.maxItems,
        sort: b.sort,
        active: b.active,
      },
      2,
    );
    if (s.vals.length) {
      const r = await this.db.query(`UPDATE home_sections SET ${s.sql} WHERE id = $1`, [sid, ...s.vals]);
      if (!r.rowCount) throw Errors.notFound('Section');
    }
    await this.log(a, 'section.update', sid, undefined, ip);
    return { ok: true };
  }

  @Delete('sections/:id')
  async deleteSection(@Auth() a: AdminAuth, @Param('id') id: string, @ClientIp() ip: string) {
    const sid = parse(zUuid, id);
    const r = await this.db.query(`DELETE FROM home_sections WHERE id = $1`, [sid]);
    if (!r.rowCount) throw Errors.notFound('Section');
    await this.log(a, 'section.delete', sid, undefined, ip);
    return { ok: true };
  }

  /** Saves a new order for banners, sections or categories (ids in display order). */
  @Post('reorder')
  @HttpCode(200)
  async reorder(@Auth() a: AdminAuth, @Body() body: unknown) {
    const b = parse(zReorder, body);
    const table = { banners: 'banners', sections: 'home_sections', categories: 'categories' }[b.type];
    const col = b.type === 'categories' ? 'key' : 'id';
    await this.db.tx(async (c) => {
      for (let i = 0; i < b.ids.length; i++) {
        await c.query(`UPDATE ${table} SET sort = $2 WHERE ${col}::text = $1`, [b.ids[i], (i + 1) * 10]);
      }
      await audit(c, { actorType: 'USER', actorId: a.userId, action: `admin.${b.type}.reorder` });
    });
    return { ok: true };
  }

  // ---------- Offers moderation ----------
  @Get('offers')
  async offers(@Query() q: unknown) {
    const f = parse(zQ, q);
    const r = await this.db.query(
      `SELECT o.*, o.valid_to::text AS vt, b.name AS business_name,
              (SELECT count(*)::int FROM offer_bookings k WHERE k.offer_id = o.id) AS bookings
         FROM offers o JOIN businesses b ON b.id = o.business_id
        WHERE o.status <> 'ARCHIVED' AND ($1::text IS NULL OR o.title ILIKE '%' || $1 || '%' OR b.name ILIKE '%' || $1 || '%')
        ORDER BY o.created_at DESC LIMIT 300`,
      [f.q || null],
    );
    return r.rows.map((o) => ({
      id: o.id,
      title: o.title,
      businessName: o.business_name,
      imageUrl: mediaUrl(o.media_id),
      kind: o.kind,
      pointsCost: Number(o.points_cost),
      requiresBooking: o.requires_booking,
      status: o.status,
      hidden: o.hidden_by_admin,
      validTo: o.vt ?? null,
      bookings: o.bookings,
    }));
  }

  /** Live rewards from every shop (for picking what "Rewards for you" shows). */
  @Get('rewards')
  async allRewards(@Query() q: unknown) {
    const f = parse(zQ, q);
    const r = await this.db.query(
      `SELECT w.id, w.title, w.points_cost, w.status, b.name AS business_name
         FROM rewards w JOIN businesses b ON b.id = w.business_id
        WHERE w.status <> 'ARCHIVED' AND ($1::text IS NULL OR w.title ILIKE '%' || $1 || '%' OR b.name ILIKE '%' || $1 || '%')
        ORDER BY b.name, w.points_cost LIMIT 300`,
      [f.q || null],
    );
    return r.rows.map((w) => ({ id: w.id, title: w.title, businessName: w.business_name, pointsCost: Number(w.points_cost), status: w.status }));
  }

  @Patch('offers/:id')
  async patchOffer(@Auth() a: AdminAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const oid = parse(zUuid, id);
    const b = parse(zOfferPatch, body);
    const r = await this.db.query(`UPDATE offers SET hidden_by_admin = $2, updated_at = now() WHERE id = $1`, [oid, b.hidden]);
    if (!r.rowCount) throw Errors.notFound('Offer');
    await this.log(a, b.hidden ? 'offer.hide' : 'offer.show', oid, undefined, ip);
    return { ok: true };
  }

  // ---------- Customers (read only, masked) ----------
  @Get('customers')
  async customers(@Query() q: unknown) {
    const f = parse(zQ, q);
    const r = await this.db.query(
      `SELECT u.id, u.name, u.phone_last4, u.email, u.created_at, u.referral_code, u.tier, u.lifetime_spend_minor,
              COALESCE((SELECT SUM(ab.balance) FROM ledger_accounts a JOIN account_balances ab ON ab.account_id = a.id
                         JOIN programs p ON p.id = a.program_id
                         WHERE a.owner_type = 'CUSTOMER' AND a.owner_id = u.id AND p.type <> 'PLATFORM'), 0) AS balance,
              COALESCE((SELECT SUM(ab.balance) FROM ledger_accounts a JOIN account_balances ab ON ab.account_id = a.id
                         JOIN programs p ON p.id = a.program_id
                         WHERE a.owner_type = 'CUSTOMER' AND a.owner_id = u.id AND p.type = 'PLATFORM'), 0) AS mukafaah,
              (SELECT count(*)::int FROM visits v WHERE v.user_id = u.id) AS visits
         FROM users u
        WHERE ($1::text IS NULL OR u.name ILIKE '%' || $1 || '%' OR u.phone_last4 = $1 OR u.referral_code = upper($1))
        ORDER BY u.created_at DESC LIMIT 200`,
      [f.q || null],
    );
    return r.rows.map((u) => ({
      id: u.id,
      name: u.name,
      // Google members may have no phone: show their masked Gmail instead.
      phone: u.phone_last4 ? `•••• ${u.phone_last4}` : u.email ? u.email.replace(/^(.).*(@.*)$/, '$1•••$2') : '',
      referralCode: u.referral_code,
      balance: Number(u.balance),
      mukafaahPoints: Number(u.mukafaah),
      lifetimeSpendMinor: Number(u.lifetime_spend_minor),
      tier: u.tier,
      visits: u.visits,
      createdAt: u.created_at,
    }));
  }

  // ---------- Settings ----------
  @Get('settings')
  async settings() {
    const r = await this.db.query(`SELECT key, value, updated_at FROM app_settings ORDER BY key`);
    return Object.fromEntries(r.rows.map((x) => [x.key, x.value]));
  }

  @Put('settings/:key')
  async putSetting(@Auth() a: AdminAuth, @Param('key') key: string, @Body() body: unknown, @ClientIp() ip: string) {
    const schema = SETTING_SCHEMAS[key];
    if (!schema) throw Errors.notFound('Setting');
    if (FULL_SETTINGS.has(key) && a.role !== 'OWNER' && a.role !== 'ADMIN') throw forbiddenScope();
    const value = parse(schema, body);
    await this.db.query(
      `INSERT INTO app_settings(key, value, updated_by, updated_at) VALUES ($1,$2,$3, now())
       ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_by = EXCLUDED.updated_by, updated_at = now()`,
      [key, JSON.stringify(value), a.userId],
    );
    clearSettingsCache();
    await this.log(a, 'settings.update', key, { value }, ip);
    return { ok: true };
  }

  // ---------- Images ----------
  @Post('media')
  @AdminScope('SHOP')
  async upload(@Body() body: unknown) {
    const b = parse(zUpload, body);
    return this.db.tx(async (c) => {
      const id = await saveImage(c, null, b.dataBase64);
      return { id, url: mediaUrl(id) };
    });
  }

  // ---------- Admin team ----------
  @Get('admins')
  async admins() {
    const r = await this.db.query(
      `SELECT a.user_id, a.role, a.active, u.name, u.phone_last4 FROM admins a JOIN users u ON u.id = a.user_id ORDER BY a.created_at`,
    );
    return r.rows.map((x) => ({ userId: x.user_id, role: x.role, active: x.active, name: x.name, phone: `•••• ${x.phone_last4}` }));
  }

  /** Owners add other admins; the person signs in once with that phone first. */
  @Post('admins')
  async addAdmin(@Auth() a: AdminAuth, @Body() body: unknown, @ClientIp() ip: string) {
    if (a.role !== 'OWNER') throw Errors.forbidden();
    const b = parse(zAdmin, body);
    const e164 = this.crypto.normalizePhone(b.phone, false);
    const u = await this.db.one(`SELECT id FROM users WHERE phone_hash = $1`, [this.crypto.phoneHash(e164)]);
    if (!u) throw new AppError(404, 'USER_NOT_FOUND', 'Ask them to sign in to the Mukafaah app once with this number');
    await this.db.query(
      `INSERT INTO admins(user_id, role) VALUES ($1,$2) ON CONFLICT (user_id) DO UPDATE SET role = EXCLUDED.role, active = true`,
      [u.id, b.role],
    );
    await this.log(a, 'admin.add', u.id, { role: b.role }, ip);
    return { ok: true };
  }

  // ---------- Manager accounts (only Mukafaah creates them) ----------
  private async accountRows(userId?: string) {
    const r = await this.db.query(
      `SELECT a.user_id, a.role, a.active, a.created_at, u.name, u.phone_last4,
              COALESCE((SELECT json_agg(json_build_object('id', b.id, 'name', b.name) ORDER BY b.name)
                          FROM admin_shops s JOIN businesses b ON b.id = s.business_id WHERE s.user_id = a.user_id), '[]') AS shops
         FROM admins a JOIN users u ON u.id = a.user_id
        WHERE ($1::uuid IS NULL OR a.user_id = $1)
        ORDER BY a.created_at`,
      [userId ?? null],
    );
    return r.rows.map((x) => ({
      userId: x.user_id,
      name: x.name ?? null,
      phoneLast4: x.phone_last4,
      role: x.role as AdminRole,
      active: x.active,
      shops: x.shops,
      createdAt: x.created_at,
    }));
  }

  @Get('accounts')
  @AdminScope('FULL')
  async accounts() {
    return { accounts: await this.accountRows() };
  }

  @Post('accounts')
  @AdminScope('FULL')
  async createAccount(@Auth() a: AdminAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zAccount, body);
    const shopIds = b.role === 'SHOP' ? [...new Set(b.shopIds ?? [])] : [];
    if (b.role === 'SHOP' && !shopIds.length) throw Errors.validation({ shopIds: ['REQUIRED'] });
    const e164 = this.crypto.normalizePhone(b.phone, false);
    const ph = this.crypto.phoneHash(e164);
    const userId = await this.db.tx(async (c) => {
      if (shopIds.length) {
        const n = (await c.query(`SELECT count(*)::int AS n FROM businesses WHERE id = ANY($1::uuid[])`, [shopIds])).rows[0].n;
        if (n !== shopIds.length) throw Errors.validation({ shopIds: ['UNKNOWN'] });
      }
      let u = (await c.query(`SELECT id FROM users WHERE phone_hash = $1`, [ph])).rows[0];
      if (!u) {
        u = (
          await c.query(`INSERT INTO users(phone_hash, phone_enc, phone_last4, name) VALUES ($1,$2,$3,$4) RETURNING id`, [
            ph,
            this.crypto.encrypt(e164),
            e164.slice(-4),
            b.name,
          ])
        ).rows[0];
      } else {
        await c.query(`UPDATE users SET name = COALESCE(name, $2) WHERE id = $1`, [u.id, b.name]);
      }
      const existing = (await c.query(`SELECT role FROM admins WHERE user_id = $1`, [u.id])).rows[0];
      if (existing) throw new AppError(409, 'ACCOUNT_EXISTS', 'This number already has a Manager account');
      await c.query(`INSERT INTO admins(user_id, role) VALUES ($1,$2)`, [u.id, b.role]);
      for (const sid of shopIds) await c.query(`INSERT INTO admin_shops(user_id, business_id) VALUES ($1,$2)`, [u.id, sid]);
      await audit(c, { actorType: 'USER', actorId: a.userId, action: 'admin.account.create', entityId: u.id, data: { role: b.role, shopIds }, ip });
      return String(u.id);
    });
    return (await this.accountRows(userId))[0];
  }

  @Patch('accounts/:userId')
  @AdminScope('FULL')
  async patchAccount(@Auth() a: AdminAuth, @Param('userId') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const uid = parse(zUuid, id);
    const b = parse(zAccountPatch, body);
    await this.db.tx(async (c) => {
      const cur = (await c.query(`SELECT role FROM admins WHERE user_id = $1 FOR UPDATE`, [uid])).rows[0];
      if (!cur) throw Errors.notFound('Account');
      // Only an owner may create, change or switch off an owner.
      if ((cur.role === 'OWNER' || b.role === 'OWNER') && a.role !== 'OWNER') throw forbiddenScope();
      if (uid === a.userId && (b.active === false || (b.role && b.role !== cur.role))) {
        throw new AppError(409, 'SELF_CHANGE', 'You cannot switch off or change your own account');
      }
      const role = b.role ?? cur.role;
      if (b.role !== undefined || b.active !== undefined) {
        await c.query(`UPDATE admins SET role = $2, active = COALESCE($3, active) WHERE user_id = $1`, [uid, role, b.active ?? null]);
      }
      if (b.name !== undefined) await c.query(`UPDATE users SET name = $2 WHERE id = $1`, [uid, b.name]);
      if (role !== 'SHOP') await c.query(`DELETE FROM admin_shops WHERE user_id = $1`, [uid]);
      else if (b.shopIds !== undefined) {
        const ids = [...new Set(b.shopIds)];
        if (!ids.length) throw Errors.validation({ shopIds: ['REQUIRED'] });
        await c.query(`DELETE FROM admin_shops WHERE user_id = $1`, [uid]);
        for (const sid of ids) await c.query(`INSERT INTO admin_shops(user_id, business_id) VALUES ($1,$2)`, [uid, sid]);
      }
      await audit(c, { actorType: 'USER', actorId: a.userId, action: 'admin.account.update', entityId: uid, data: b, ip });
    });
    return (await this.accountRows(uid))[0];
  }

  // ---------- Tiers (by total spend) ----------
  @Get('tiers')
  async tiers() {
    const rows = await loadTierRows(this.db, false);
    const counts = await this.db.query(`SELECT tier, count(*)::int AS n FROM users GROUP BY tier`);
    const n = Object.fromEntries(counts.rows.map((x) => [x.tier, x.n]));
    return {
      tiers: rows.map((t) => ({
        code: t.code,
        name: t.nameEn,
        nameAr: t.nameAr,
        minSpendMinor: t.minSpendMinor,
        bonusPoints: t.bonusPoints,
        color: t.color,
        perks: t.perks,
        active: t.active,
        customers: n[t.code] ?? 0,
      })),
    };
  }

  @Put('tiers')
  @AdminScope('FULL')
  async putTiers(@Auth() a: AdminAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zTiers, body);
    await this.db.tx(async (c) => {
      const codes = b.tiers.map((t) => t.code);
      await c.query(`UPDATE tiers SET active = false WHERE NOT (code = ANY($1::text[]))`, [codes]);
      for (const [i, t] of b.tiers.entries()) {
        await c.query(
          `INSERT INTO tiers(code, name_en, name_ar, min_spend_minor, bonus_points, color, perks_en, sort, active)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
           ON CONFLICT (code) DO UPDATE SET name_en = EXCLUDED.name_en, name_ar = EXCLUDED.name_ar, min_spend_minor = EXCLUDED.min_spend_minor,
             bonus_points = EXCLUDED.bonus_points, color = EXCLUDED.color, perks_en = EXCLUDED.perks_en, sort = EXCLUDED.sort, active = EXCLUDED.active`,
          [t.code, t.name, t.nameAr ?? t.name, t.minSpendMinor, t.bonusPoints, t.color ?? null, t.perks ?? null, (i + 1) * 10, t.active],
        );
      }
      // Re-place customers by spend. Bonuses are only granted when a bill moves someone up.
      await c.query(
        `UPDATE users u SET tier = COALESCE(
           (SELECT t.code FROM tiers t WHERE t.active AND t.min_spend_minor <= u.lifetime_spend_minor ORDER BY t.min_spend_minor DESC LIMIT 1), $1)`,
        [codes[0]],
      );
      await audit(c, { actorType: 'USER', actorId: a.userId, action: 'admin.tiers.update', data: { codes }, ip });
    });
    return this.tiers();
  }
}

@Module({ controllers: [AdminController] })
export class AdminModule {}
