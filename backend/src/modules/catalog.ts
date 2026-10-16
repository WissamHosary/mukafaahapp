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
  sort: z.enum(['popular', 'rating', 'name', 'name_desc', 'newest', 'points', 'nearest', 'friends']).default('popular'),
  featured: z.enum(['true', 'false']).transform((v) => v === 'true').optional(),
  /** Only shops that accept Mukafaah Points. */
  friends: z.enum(['true', 'false']).transform((v) => v === 'true').optional(),
  limit: z.coerce.number().int().min(1).max(200).default(100),
  // For "nearest": the member's location.
  lat: z.coerce.number().min(-90).max(90).optional(),
  lng: z.coerce.number().min(-180).max(180).optional(),
});
const zOffers = z.object({
  category: z.string().regex(/^[A-Z0-9_]{2,40}$/).optional(),
  businessId: zUuid.optional(),
  limit: z.coerce.number().int().min(1).max(100).default(60),
  // The member's location: when given, places near them come first.
  lat: z.coerce.number().min(-90).max(90).optional(),
  lng: z.coerce.number().min(-180).max(180).optional(),
});
const zHome = z.object({
  lat: z.coerce.number().min(-90).max(90).optional(),
  lng: z.coerce.number().min(-180).max(180).optional(),
});

/** Within this distance a place counts as "near you". */
const NEAR_KM = 5;

/** Straight-line distance in km, or null when either point is unknown. */
function distanceKm(lat1?: number | null, lng1?: number | null, lat2?: number | null, lng2?: number | null): number | null {
  if (lat1 == null || lng1 == null || lat2 == null || lng2 == null) return null;
  const rad = Math.PI / 180;
  const a =
    Math.sin(((lat2 - lat1) * rad) / 2) ** 2 + Math.cos(lat1 * rad) * Math.cos(lat2 * rad) * Math.sin(((lng2 - lng1) * rad) / 2) ** 2;
  return Math.round(12742 * Math.asin(Math.sqrt(a)) * 10) / 10;
}

/**
 * Adds distanceKm and isNear to each item, then puts places near the member
 * first (closest first) and keeps the original order for the rest.
 */
function nearFirst<T extends { distanceKm?: number | null }>(items: Array<T & { _lat?: number | null; _lng?: number | null }>, lat?: number, lng?: number) {
  const out = items.map((x, i) => {
    const { _lat, _lng, ...rest } = x;
    const d = distanceKm(lat, lng, _lat, _lng);
    return { item: { ...rest, distanceKm: d, isNear: d != null && d <= NEAR_KM }, i, d };
  });
  out.sort((a, b) => {
    const an = a.d != null && a.d <= NEAR_KM;
    const bn = b.d != null && b.d <= NEAR_KM;
    if (an !== bn) return an ? -1 : 1;
    if (an && bn) return (a.d as number) - (b.d as number);
    return a.i - b.i;
  });
  return out.map((x) => x.item);
}
// Stars only. Older app versions may still send a comment; it is ignored.
const zRating = z.strictObject({ stars: z.number().int().min(1).max(5), comment: z.string().trim().max(500).optional() });

const LIVE_OFFER = `o.status = 'ACTIVE' AND NOT o.hidden_by_admin AND o.valid_from <= current_date AND (o.valid_to IS NULL OR o.valid_to >= current_date)`;

/** "Lara Haddad" becomes "Lara H." on public reviews. */
function reviewerName(name: string | null): string {
  const parts = String(name ?? '').trim().split(/\s+/).filter(Boolean);
  if (!parts.length) return 'Mukafaah member';
  return parts.length > 1 ? `${parts[0]} ${parts[parts.length - 1][0].toUpperCase()}.` : parts[0];
}

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
      name_desc: 'b.name DESC',
      // Rough distance is enough to order by; shops without a pin go last.
      nearest:
        f.lat != null && f.lng != null
          ? `(b.lat IS NULL), power(b.lat - $7::float8, 2) + power((b.lng - $8::float8) * cos(radians($7::float8)), 2), b.name`
          : 'b.featured DESC, popularity DESC, b.name',
      friends: 'b.friends_enabled DESC, popularity DESC, b.name',
    }[f.sort];
    const near = f.sort === 'nearest' && f.lat != null && f.lng != null;
    const r = await this.db.query(
      `SELECT ${SHOP_CARD_SELECT}
         FROM businesses b ${SHOP_CARD_JOINS}
        WHERE b.status = 'ACTIVE' AND b.listed
          AND ($2::text IS NULL OR b.name ILIKE '%' || $2 || '%' OR b.city ILIKE '%' || $2 || '%')
          AND ($3::text IS NULL OR b.category = $3)
          AND ($4::text IS NULL OR p.type = $4)
          AND ($5::boolean IS NULL OR b.featured = $5)
          AND (NOT $9::boolean OR b.friends_enabled)
          AND ($7::float8 IS NULL OR $8::float8 IS NOT NULL OR true)
        ORDER BY ${order}
        LIMIT $6`,
      [userId, f.q || null, f.category ?? null, f.type ?? null, f.featured ?? null, f.limit, near ? f.lat : null, near ? f.lng : null, f.friends === true],
    );
    return r.rows.map(shopCard);
  }

  /**
   * Everything the home screen needs in one request. Banners, categories and
   * the order of sections come from Mukafaah Manager.
   */
  @Get('home')
  async home(@Auth() a: UserAuth, @Query() q: unknown) {
    const at = parse(zHome, q ?? {});
    const [user, shops, offers, recent, pre, unread, totals, mukafaahPoints, banners, cats, blocks, tiers, support, layout] = await Promise.all([
      this.db.one(`SELECT name, referral_code, tier, lifetime_spend_minor FROM users WHERE id = $1`, [a.userId]),
      this.shops(a.userId, { sort: 'popular', limit: 200 }),
      this.db.query(
        `SELECT ${OFFER_SELECT}, b.lat AS b_lat, b.lng AS b_lng FROM offers o JOIN businesses b ON b.id = o.business_id AND b.status = 'ACTIVE' AND b.listed
          WHERE ${LIVE_OFFER} ORDER BY o.created_at DESC LIMIT 100`,
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
    const offerList = offers.rows.map((o) => ({ ...offerJson(o), distanceKm: distanceKm(at.lat, at.lng, o.b_lat, o.b_lng) }));
    const offerById = new Map(offerList.map((o) => [o.id, o]));
    const withDistance = shops.map((s) => ({ ...s, distanceKm: distanceKm(at.lat, at.lng, s.lat, s.lng) }));
    const byId = new Map(withDistance.map((s) => [s.id, s]));
    /** Nearest first when we know where the member is, otherwise the popularity order. */
    const nearest = (list: typeof withDistance) =>
      at.lat == null ? list : [...list].sort((x, y) => (x.distanceKm ?? 1e9) - (y.distanceKm ?? 1e9));
    const picked = <T,>(ids: string[], map: Map<string, T>) => ids.map((id) => map.get(id)).filter((x): x is T => !!x);
    const out: any[] = [];
    const shown = new Set<string>();
    let rewardList: any[] | undefined;
    for (const b of blocks.rows) {
      const base = {
        id: b.id,
        type: b.type,
        titleEn: b.title_en ?? null,
        titleAr: b.title_ar ?? null,
        categoryKey: b.category_key ?? null,
        layout: b.layout ?? (b.type === 'DISCOVER_SHOPS' ? 'GRID' : b.type === 'FEATURED_SHOPS' ? 'CAROUSEL' : 'ROW'),
      };
      const max = Number(b.max_items);
      const isPicked = b.pick_mode === 'PICKED';
      if (b.type === 'CATEGORIES') {
        if (categories.length) out.push(base);
      } else if (b.type === 'FEATURED_SHOPS') {
        const list = (isPicked ? picked(b.shop_ids, byId) : withDistance.filter((s) => s.featured)).slice(0, max);
        list.forEach((s) => shown.add(s.id));
        if (list.length) out.push({ ...base, shops: list });
      } else if (b.type === 'DISCOVER_SHOPS') {
        // Automatic: shops not already shown above, nearest first.
        const list = (isPicked ? picked(b.shop_ids, byId) : nearest(withDistance.filter((s) => !shown.has(s.id)))).slice(0, max);
        if (list.length) out.push({ ...base, shops: list });
      } else if (b.type === 'NEW_OFFERS') {
        const list = (isPicked ? picked(b.offer_ids, offerById) : offerList).slice(0, max);
        if (list.length) out.push({ ...base, offers: list });
      } else if (b.type === 'CATEGORY_SHOPS') {
        const list = withDistance.filter((s) => s.category === b.category_key).slice(0, max);
        const c = catByKey.get(b.category_key);
        if (list.length) out.push({ ...base, titleEn: base.titleEn ?? c?.name_en, titleAr: base.titleAr ?? c?.name_ar, shops: list });
      } else if (b.type === 'PICKED_SHOPS') {
        const list = picked(b.shop_ids, byId).slice(0, max);
        if (list.length) out.push({ ...base, shops: list });
      } else if (b.type === 'REWARDS') {
        rewardList ??= await this.rewards(a, { lat: at.lat, lng: at.lng });
        const list = isPicked
          ? picked(b.reward_ids, new Map(rewardList.map((r) => [r.id, r])))
          : rewardList;
        if (list.length) out.push({ ...base, rewards: list.slice(0, max) });
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
      featured: withDistance.filter((s) => s.featured).slice(0, 12),
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
      `SELECT ${SHOP_CARD_SELECT}, b.instagram, b.facebook, b.tiktok, b.website, b.phone, b.hours, b.store_enabled
         FROM businesses b ${SHOP_CARD_JOINS}
        WHERE b.id = $2 AND b.status = 'ACTIVE'`,
      [a.userId, bid],
    );
    if (!r) throw Errors.notFound('Shop');
    const card = shopCard(r);
    const [offers, rewards, products, mine, branches, bookings, banners, reviews, stars] = await Promise.all([
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
      this.db.query(`SELECT media_id, caption FROM business_banners WHERE business_id = $1 ORDER BY sort, created_at LIMIT 10`, [bid]),
      this.db.query(
        `SELECT r.stars, r.comment, r.updated_at, u.name, r.user_id = $2 AS mine
           FROM business_ratings r JOIN users u ON u.id = r.user_id
          WHERE r.business_id = $1 AND NOT r.hidden
          ORDER BY r.updated_at DESC LIMIT 20`,
        [bid, a.userId],
      ),
      this.db.query(
        `SELECT stars, count(*)::int AS n FROM business_ratings WHERE business_id = $1 AND NOT hidden GROUP BY stars`,
        [bid],
      ),
    ]);
    // One review per member, after a real visit or a completed order (no fake reviews).
    // Shared / Network: which group, how many shops, and this shop's limit.
    const group =
      card.programType === 'SHARED' || card.programType === 'NETWORK'
        ? await this.db.one(
            `SELECT p.name, p.type, pm.redeem_max_percent, pm.redeem_max_points,
                    (SELECT count(*)::int FROM program_members x JOIN businesses xb ON xb.id = x.business_id
                      WHERE x.program_id = p.id AND x.active AND xb.status = 'ACTIVE') AS shops
               FROM programs p JOIN program_members pm ON pm.program_id = p.id AND pm.business_id = $2 WHERE p.id = $1`,
            [card.programId, bid],
          )
        : null;
    const visited = await this.db.one(
      `SELECT 1 WHERE EXISTS (SELECT 1 FROM visits WHERE business_id = $1 AND user_id = $2)
          OR EXISTS (SELECT 1 FROM whatsapp_orders WHERE business_id = $1 AND user_id = $2 AND status = 'COMPLETED')`,
      [bid, a.userId],
    );
    const openBooking = new Map(bookings.rows.map((x) => [x.offer_id, x.status]));
    return {
      ...card,
      instagram: r.instagram ?? null,
      social: {
        instagram: r.instagram ?? null,
        facebook: r.facebook ?? null,
        tiktok: r.tiktok ?? null,
        website: r.website ?? null,
        whatsapp: r.whatsapp ?? null,
        phone: r.phone ?? null,
      },
      hours: r.hours ?? null,
      /** 7 days, Monday first: null = closed, else {open, close}. */
      openingHours: r.opening_hours ?? null,
      banners: banners.rows.map((x) => ({ url: mediaUrl(x.media_id), caption: x.caption ?? null })),
      reviews: reviews.rows.map((x) => ({
        name: reviewerName(x.name),
        stars: Number(x.stars),
        comment: null, // ratings are stars only
        at: x.updated_at,
        mine: !!x.mine,
      })),
      // How many reviews gave 1 to 5 stars.
      starCounts: [1, 2, 3, 4, 5].map((n) => Number(stars.rows.find((x) => Number(x.stars) === n)?.n ?? 0)),
      group: group
        ? {
            name: group.name,
            type: group.type,
            shops: group.shops,
            maxPercent: Number(group.redeem_max_percent),
            maxPoints: group.redeem_max_points == null ? null : Number(group.redeem_max_points),
          }
        : null,
      storeEnabled: !!r.store_enabled,
      branches: branches.rows.map((x) => x.name),
      offers: offers.rows.map((o) => ({ ...offerJson(o), myOpenBooking: openBooking.get(o.id) ?? null })),
      rewards: rewards.rows.map((w) => rewardJson(w, card.myPoints)),
      // A preview of the store; the full store is GET shops/:id/store.
      products: products.rows.map(listJson),
      myRating: mine ? { stars: mine.stars, comment: null } : null,
      canRate: !!visited,
    };
  }

  /** Customers can rate a shop after at least one visit. */
  @Put('shops/:id/rating')
  async rate(@Auth() a: UserAuth, @Param('id') id: string, @Body() body: unknown) {
    const bid = parse(zUuid, id);
    const b = parse(zRating, body);
    const visited = await this.db.one(
      `SELECT 1 WHERE EXISTS (SELECT 1 FROM visits WHERE business_id = $1 AND user_id = $2)
          OR EXISTS (SELECT 1 FROM whatsapp_orders WHERE business_id = $1 AND user_id = $2 AND status = 'COMPLETED')`,
      [bid, a.userId],
    );
    if (!visited) throw new AppError(403, 'RATE_AFTER_VISIT', 'You can rate a shop after your first visit');
    await this.db.tx(async (c) => {
      await c.query(
        // Stars only: a customer can't write text, so there is nothing to moderate.
        `INSERT INTO business_ratings(business_id, user_id, stars, comment) VALUES ($1,$2,$3,NULL)
         ON CONFLICT (business_id, user_id) DO UPDATE SET stars = EXCLUDED.stars, comment = NULL, updated_at = now()`,
        [bid, a.userId, b.stars],
      );
      const stars = '★'.repeat(b.stars);
      await alertBusiness(
        c,
        bid,
        'RATING',
        { ar: { title: `تقييم جديد ${stars}` }, en: { title: `New rating ${stars}` } },
        null,
      );
    });
    return { ok: true };
  }

  @Get('offers')
  async offers(@Query() q: unknown) {
    const f = parse(zOffers, q);
    const r = await this.db.query(
      `SELECT ${OFFER_SELECT}, b.lat AS b_lat, b.lng AS b_lng FROM offers o JOIN businesses b ON b.id = o.business_id AND b.status = 'ACTIVE'
        WHERE ${LIVE_OFFER} AND ($1::text IS NULL OR b.category = $1) AND ($2::uuid IS NULL OR o.business_id = $2)
        ORDER BY o.created_at DESC LIMIT $3`,
      [f.category ?? null, f.businessId ?? null, f.limit],
    );
    // Near the member first, then every other offer in Mukafaah.
    return nearFirst(r.rows.map((o) => ({ ...offerJson(o), _lat: o.b_lat, _lng: o.b_lng })), f.lat, f.lng);
  }

  /** Rewards from every shop, with what the customer can already afford. */
  @Get('rewards')
  async rewards(@Auth() a: UserAuth, @Query() q: unknown) {
    const f = parse(zOffers, q);
    const r = await this.db.query(
      `SELECT ${REWARD_SELECT}, b.lat AS b_lat, b.lng AS b_lng,
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
    return nearFirst(r.rows.map((x) => ({ ...rewardJson(x, Number(x.my_points)), _lat: x.b_lat, _lng: x.b_lng })), f.lat, f.lng);
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
