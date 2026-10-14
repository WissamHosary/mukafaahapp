import { Body, Controller, Get, Module, Param, Put, Query } from '@nestjs/common';
import { z } from 'zod';
import { Auth, RequireUser, type UserAuth } from '../platform/auth.js';
import { Db } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zUuid } from '../platform/validation.js';
import {
  OFFER_SELECT,
  REWARD_SELECT,
  SHOP_CARD_JOINS,
  SHOP_CARD_SELECT,
  lifetimePoints,
  offerJson,
  pointsValueMinor,
  productJson,
  rewardJson,
  shopCard,
  alertBusiness,
  getSetting,
  loadTierRows,
  mediaUrl,
  tierProgress,
} from './shared.js';
import { mukafaahBalance } from './mukafaah.js';

const BANNER_LAYOUTS = ['UNO', 'DUO', 'TRIO'] as const;

/** Category JSON shared by home, /customer/categories and the public list. */
const categoryJson = (c: any) => ({
  key: c.key,
  nameEn: c.name_en,
  nameAr: c.name_ar,
  emoji: c.emoji ?? null,
  iconUrl: mediaUrl(c.icon_media_id),
  color: c.color ?? null,
});
import { PRODUCT_LIST, listJson } from './store.js';

const zShops = z.object({
  q: z.string().trim().max(60).optional(),
  category: z.string().regex(/^[A-Z0-9_]{2,40}$/).optional(),
  type: z.enum(['IN_STORE', 'SHARED', 'NETWORK']).optional(),
  sort: z.enum(['popular', 'rating', 'name', 'newest', 'points']).default('popular'),
  featured: z.enum(['true', 'false']).transform((v) => v === 'true').optional(),
  limit: z.coerce.number().int().min(1).max(200).default(100),
});
const zOffers = z.object({
  category: z.string().regex(/^[A-Z0-9_]{2,40}$/).optional(),
  businessId: zUuid.optional(),
  limit: z.coerce.number().int().min(1).max(100).default(60),
});
const zRating = z.strictObject({ stars: z.number().int().min(1).max(5), comment: z.string().trim().max(500).optional() });

const LIVE_OFFER = `o.status = 'ACTIVE' AND NOT o.hidden_by_admin AND o.valid_from <= current_date AND (o.valid_to IS NULL OR o.valid_to >= current_date)`;

@Controller('v1/customer')
@RequireUser()
export class CatalogController {
  constructor(private readonly db: Db) {}

  private async shops(userId: string, f: z.infer<typeof zShops>) {
    const order = {
      popular: 'b.featured DESC, b.featured_sort, popularity DESC, rating DESC, b.name',
      rating: 'rating DESC, rating_count DESC, b.name',
      name: 'b.name',
      newest: 'b.created_at DESC',
      points: 'my_points DESC, popularity DESC',
    }[f.sort];
    const r = await this.db.query(
      `SELECT ${SHOP_CARD_SELECT}
         FROM businesses b ${SHOP_CARD_JOINS}
        WHERE b.status = 'ACTIVE' AND b.listed
          AND ($2::text IS NULL OR b.name ILIKE '%' || $2 || '%' OR b.city ILIKE '%' || $2 || '%')
          AND ($3::text IS NULL OR b.category = $3)
          AND ($4::text IS NULL OR p.type = $4)
          AND ($5::boolean IS NULL OR b.featured = $5)
        ORDER BY ${order}
        LIMIT $6`,
      [userId, f.q || null, f.category ?? null, f.type ?? null, f.featured ?? null, f.limit],
    );
    return r.rows.map(shopCard);
  }

  /**
   * Everything the home screen needs in one request. Banners, categories and
   * the order of sections come from Mukafaah Manager.
   */
  @Get('home')
  async home(@Auth() a: UserAuth) {
    const [user, shops, offers, recent, pre, unread, totals, mukafaahPoints, banners, cats, blocks, tiers, support, layout] = await Promise.all([
      this.db.one(`SELECT name, referral_code, tier, lifetime_spend_minor FROM users WHERE id = $1`, [a.userId]),
      this.shops(a.userId, { sort: 'popular', limit: 200 }),
      this.db.query(
        `SELECT ${OFFER_SELECT} FROM offers o JOIN businesses b ON b.id = o.business_id AND b.status = 'ACTIVE' AND b.listed
          WHERE ${LIVE_OFFER} ORDER BY o.created_at DESC LIMIT 20`,
      ),
      this.recent(a.userId, 5),
      this.db.one(
        `SELECT COALESCE(SUM(ab.balance), 0) AS s
           FROM users u JOIN pending_holders h ON h.phone_hash = u.phone_hash
           JOIN ledger_accounts la ON la.owner_type = 'PENDING' AND la.owner_id = h.id
           JOIN account_balances ab ON ab.account_id = la.id
          WHERE u.id = $1`,
        [a.userId],
      ),
      this.db.one(`SELECT count(*)::int AS n FROM notifications WHERE user_id = $1 AND read_at IS NULL`, [a.userId]),
      this.totals(a.userId),
      mukafaahBalance(this.db, a.userId),
      this.db.query(
        `SELECT * FROM banners WHERE active AND (starts_at IS NULL OR starts_at <= now()) AND (ends_at IS NULL OR ends_at > now())
          ORDER BY sort, created_at`,
      ),
      this.db.query(`SELECT * FROM categories WHERE active ORDER BY sort, name_en`),
      this.db.query(`SELECT * FROM home_sections WHERE active ORDER BY sort, created_at`),
      loadTierRows(this.db),
      getSetting<{ whatsapp?: string | null; instagram?: string | null }>(this.db, 'support', {}),
      getSetting<string>(this.db, 'home.bannerLayout', 'UNO'),
    ]);
    const counts: Record<string, number> = {};
    for (const s of shops) counts[s.category] = (counts[s.category] ?? 0) + 1;
    const categories = cats.rows
      .filter((c) => counts[c.key])
      .map((c) => ({ ...categoryJson(c), count: counts[c.key] }));
    const catByKey = new Map(cats.rows.map((c) => [c.key, c]));
    const offerList = offers.rows.map(offerJson);
    const byId = new Map(shops.map((s) => [s.id, s]));
    const out: any[] = [];
    let rewardList: any[] | undefined;
    for (const b of blocks.rows) {
      const base = { id: b.id, type: b.type, titleEn: b.title_en ?? null, titleAr: b.title_ar ?? null, categoryKey: b.category_key ?? null };
      const max = Number(b.max_items);
      if (b.type === 'CATEGORIES') {
        if (categories.length) out.push(base);
      } else if (b.type === 'FEATURED_SHOPS') {
        const list = shops.filter((s) => s.featured).slice(0, max);
        if (list.length) out.push({ ...base, shops: list });
      } else if (b.type === 'NEW_OFFERS') {
        const list = offerList.slice(0, max);
        if (list.length) out.push({ ...base, offers: list });
      } else if (b.type === 'CATEGORY_SHOPS') {
        const list = shops.filter((s) => s.category === b.category_key).slice(0, max);
        const c = catByKey.get(b.category_key);
        if (list.length) out.push({ ...base, titleEn: base.titleEn ?? c?.name_en, titleAr: base.titleAr ?? c?.name_ar, shops: list });
      } else if (b.type === 'PICKED_SHOPS') {
        const list = (b.shop_ids as string[]).map((id) => byId.get(id)).filter(Boolean).slice(0, max);
        if (list.length) out.push({ ...base, shops: list });
      } else if (b.type === 'REWARDS') {
        rewardList ??= await this.rewards(a, {});
        const list = rewardList.slice(0, max);
        if (list.length) out.push({ ...base, rewards: list });
      } else if (b.type === 'RECENT_ACTIVITY') {
        if (recent.length) out.push(base);
      } else {
        out.push(base);
      }
    }
    const spend = Number(user?.lifetime_spend_minor ?? 0);
    const tp = tierProgress(tiers, user?.tier ?? 'SILVER', spend);
    return {
      name: user?.name ?? null,
      referralCode: user?.referral_code ?? null,
      tier: tp.current?.code ?? user?.tier ?? 'SILVER',
      // For the progress bar on the points card (amounts are total spend in cents).
      tierProgress: {
        lifetime: spend,
        currentMin: tp.current?.minSpendMinor ?? 0,
        nextTier: tp.next?.code ?? null,
        nextMin: tp.next?.minSpendMinor ?? null,
      },
      balancePoints: totals.balance,
      mukafaahPoints,
      bannerLayout: (BANNER_LAYOUTS as readonly string[]).includes(layout) ? layout : 'UNO',
      totalSavingMinor: totals.savingMinor,
      pendingPrePoints: Number(pre?.s ?? 0),
      unreadNotifications: unread?.n ?? 0,
      banners: banners.rows.map((b) => ({
        id: b.id,
        titleEn: b.title_en ?? null,
        titleAr: b.title_ar ?? null,
        subtitleEn: b.subtitle_en ?? null,
        subtitleAr: b.subtitle_ar ?? null,
        imageUrl: mediaUrl(b.media_id),
        style: b.style,
        actionType: b.action_type,
        actionValue: b.action_value ?? null,
      })),
      categories,
      blocks: out,
      support: { whatsapp: support.whatsapp ?? null, instagram: support.instagram ?? null },
      // Simple lists kept for older app builds.
      featured: shops.filter((s) => s.featured).slice(0, 12),
      sections: categories.map((c) => ({ category: c.key, shops: shops.filter((s) => s.category === c.key).slice(0, 12) })),
      offers: offerList.slice(0, 10),
      recent,
    };
  }

  /** Active categories with names and icons (for filters). */
  @Get('categories')
  async categories() {
    const r = await this.db.query(`SELECT * FROM categories WHERE active ORDER BY sort, name_en`);
    return r.rows.map(categoryJson);
  }

  /** Total balance and how much the customer saved with points, rewards and offers. */
  private async totals(userId: string) {
    const bal = await this.db.one(
      `SELECT COALESCE(SUM(ab.balance), 0) AS s FROM ledger_accounts a JOIN account_balances ab ON ab.account_id = a.id
         JOIN programs p ON p.id = a.program_id AND p.type <> 'PLATFORM'
        WHERE a.owner_type = 'CUSTOMER' AND a.owner_id = $1`,
      [userId],
    );
    const red = await this.db.query(
      `SELECT v.points, v.ref_type, p.redeem_points_per_unit, rr.value_minor AS reward_value
         FROM visits v JOIN programs p ON p.id = v.program_id
         LEFT JOIN reward_redemptions rr ON rr.ledger_tx_id = v.ledger_tx_id
        WHERE v.user_id = $1 AND v.type = 'REDEEM' AND v.voided_by_tx_id IS NULL`,
      [userId],
    );
    let saving = 0;
    for (const r of red.rows) {
      if (r.ref_type === 'OFFER') continue; // counted from the booking's saving below
      const rewardValue = Number(r.reward_value ?? 0);
      saving += rewardValue > 0 ? rewardValue : pointsValueMinor(Number(r.points), Number(r.redeem_points_per_unit));
    }
    const off = await this.db.one(
      `SELECT COALESCE(SUM(saving_minor), 0) AS s FROM offer_bookings WHERE user_id = $1 AND status = 'REDEEMED'`,
      [userId],
    );
    saving += Number(off?.s ?? 0);
    return { balance: Number(bal?.s ?? 0), savingMinor: saving };
  }

  private async recent(userId: string, limit: number) {
    const r = await this.db.query(
      `SELECT t.id, t.type, t.created_at, e.amount, b.name AS business_name, b.logo_media_id
         FROM ledger_entries e
         JOIN ledger_accounts a ON a.id = e.account_id AND a.owner_type = 'CUSTOMER' AND a.owner_id = $1
         JOIN ledger_transactions t ON t.id = e.transaction_id
         LEFT JOIN businesses b ON b.id = t.business_id
        ORDER BY e.id DESC LIMIT $2`,
      [userId, limit],
    );
    return r.rows.map((x) => ({
      id: x.id,
      type: x.type,
      points: Number(x.amount),
      businessName: x.business_name ?? null,
      businessLogoUrl: x.logo_media_id ? `/v1/media/${x.logo_media_id}` : null,
      createdAt: x.created_at,
    }));
  }

  @Get('shops')
  async list(@Auth() a: UserAuth, @Query() q: unknown) {
    const f = parse(zShops, q);
    const shops = await this.shops(a.userId, f);
    return { total: shops.length, shops };
  }

  @Get('shops/:id')
  async shop(@Auth() a: UserAuth, @Param('id') id: string) {
    const bid = parse(zUuid, id);
    const r = await this.db.one(
      `SELECT ${SHOP_CARD_SELECT}, b.instagram, b.store_enabled FROM businesses b ${SHOP_CARD_JOINS}
        WHERE b.id = $2 AND b.status = 'ACTIVE'`,
      [a.userId, bid],
    );
    if (!r) throw Errors.notFound('Shop');
    const card = shopCard(r);
    const [offers, rewards, products, mine, branches, bookings] = await Promise.all([
      this.db.query(
        `SELECT ${OFFER_SELECT} FROM offers o JOIN businesses b ON b.id = o.business_id
          WHERE o.business_id = $1 AND ${LIVE_OFFER} ORDER BY o.created_at DESC`,
        [bid],
      ),
      this.db.query(
        `SELECT ${REWARD_SELECT} FROM rewards w JOIN businesses b ON b.id = w.business_id JOIN programs p ON p.id = b.earning_program_id
          WHERE w.business_id = $1 AND w.status = 'ACTIVE' AND (w.stock IS NULL OR w.stock > 0) ORDER BY w.points_cost`,
        [bid],
      ),
      this.db.query(
        `${PRODUCT_LIST} JOIN businesses sb ON sb.id = p.business_id AND sb.store_enabled
          WHERE p.business_id = $1 AND NOT p.archived AND p.available ORDER BY p.featured DESC, p.sort, p.created_at LIMIT 12`,
        [bid],
      ),
      this.db.one(`SELECT stars, comment FROM business_ratings WHERE business_id = $1 AND user_id = $2`, [bid, a.userId]),
      this.db.query(`SELECT name FROM branches WHERE business_id = $1 ORDER BY created_at`, [bid]),
      this.db.query(
        `SELECT offer_id, status FROM offer_bookings WHERE business_id = $1 AND user_id = $2 AND status IN ('REQUESTED','ACCEPTED')`,
        [bid, a.userId],
      ),
    ]);
    const visited = await this.db.one(`SELECT 1 FROM visits WHERE business_id = $1 AND user_id = $2 LIMIT 1`, [bid, a.userId]);
    const openBooking = new Map(bookings.rows.map((x) => [x.offer_id, x.status]));
    return {
      ...card,
      instagram: r.instagram ?? null,
      storeEnabled: !!r.store_enabled,
      branches: branches.rows.map((x) => x.name),
      offers: offers.rows.map((o) => ({ ...offerJson(o), myOpenBooking: openBooking.get(o.id) ?? null })),
      rewards: rewards.rows.map((w) => rewardJson(w, card.myPoints)),
      // A preview of the store; the full store is GET shops/:id/store.
      products: products.rows.map(listJson),
      myRating: mine ? { stars: mine.stars, comment: mine.comment ?? null } : null,
      canRate: !!visited,
    };
  }

  /** Customers can rate a shop after at least one visit. */
  @Put('shops/:id/rating')
  async rate(@Auth() a: UserAuth, @Param('id') id: string, @Body() body: unknown) {
    const bid = parse(zUuid, id);
    const b = parse(zRating, body);
    const visited = await this.db.one(`SELECT 1 FROM visits WHERE business_id = $1 AND user_id = $2 LIMIT 1`, [bid, a.userId]);
    if (!visited) throw new AppError(403, 'RATE_AFTER_VISIT', 'You can rate a shop after your first visit');
    await this.db.tx(async (c) => {
      await c.query(
        `INSERT INTO business_ratings(business_id, user_id, stars, comment) VALUES ($1,$2,$3,$4)
         ON CONFLICT (business_id, user_id) DO UPDATE SET stars = EXCLUDED.stars, comment = EXCLUDED.comment, updated_at = now()`,
        [bid, a.userId, b.stars, b.comment ?? null],
      );
      const stars = '★'.repeat(b.stars);
      await alertBusiness(
        c,
        bid,
        'RATING',
        { ar: { title: `تقييم جديد ${stars}`, body: b.comment || undefined }, en: { title: `New rating ${stars}`, body: b.comment || undefined } },
        null,
      );
    });
    return { ok: true };
  }

  @Get('offers')
  async offers(@Query() q: unknown) {
    const f = parse(zOffers, q);
    const r = await this.db.query(
      `SELECT ${OFFER_SELECT} FROM offers o JOIN businesses b ON b.id = o.business_id AND b.status = 'ACTIVE'
        WHERE ${LIVE_OFFER} AND ($1::text IS NULL OR b.category = $1) AND ($2::uuid IS NULL OR o.business_id = $2)
        ORDER BY o.created_at DESC LIMIT $3`,
      [f.category ?? null, f.businessId ?? null, f.limit],
    );
    return r.rows.map(offerJson);
  }

  /** Rewards from every shop, with what the customer can already afford. */
  @Get('rewards')
  async rewards(@Auth() a: UserAuth, @Query() q: unknown) {
    const f = parse(zOffers, q);
    const r = await this.db.query(
      `SELECT ${REWARD_SELECT},
              COALESCE((SELECT ab.balance FROM ledger_accounts la JOIN account_balances ab ON ab.account_id = la.id
                         WHERE la.program_id = p.id AND la.owner_type = 'CUSTOMER' AND la.owner_id = $1), 0) AS my_points
         FROM rewards w JOIN businesses b ON b.id = w.business_id AND b.status = 'ACTIVE'
         JOIN programs p ON p.id = b.earning_program_id
        WHERE w.status = 'ACTIVE' AND (w.stock IS NULL OR w.stock > 0)
          AND ($2::text IS NULL OR b.category = $2) AND ($3::uuid IS NULL OR w.business_id = $3)
        ORDER BY (COALESCE((SELECT ab.balance FROM ledger_accounts la JOIN account_balances ab ON ab.account_id = la.id
                             WHERE la.program_id = p.id AND la.owner_type = 'CUSTOMER' AND la.owner_id = $1), 0) >= w.points_cost) DESC,
                 w.points_cost
        LIMIT $4`,
      [a.userId, f.category ?? null, f.businessId ?? null, f.limit],
    );
    return r.rows.map((x) => rewardJson(x, Number(x.my_points)));
  }
}

/** Category names and icons are not private: the business app needs them before sign-up finishes. */
@Controller('v1/public')
export class PublicCatalogController {
  constructor(private readonly db: Db) {}

  @Get('categories')
  async categories() {
    const r = await this.db.query(`SELECT * FROM categories WHERE active ORDER BY sort, name_en`);
    return r.rows.map(categoryJson);
  }
}

@Module({ controllers: [CatalogController, PublicCatalogController] })
export class CatalogModule {}
