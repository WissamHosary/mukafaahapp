import { randomInt } from 'node:crypto';
import { pgCode, type Queryable } from '../platform/db.js';
import { AppError } from '../platform/errors.js';

/** Shop categories, in the order the apps show them. */
export const CATEGORIES = [
  'RESTAURANTS_CAFES',
  'FOOD_DRINKS',
  'FASHION',
  'ELECTRONICS',
  'FITNESS',
  'BEAUTY_WELLNESS',
  'ENTERTAINMENT',
  'GIFTS',
  'RETAIL',
  'SERVICES',
  'OTHER',
] as const;
export type Category = (typeof CATEGORIES)[number];

/** Public URL path of a stored image (the apps prefix it with the API address). */
export const mediaUrl = (id: string | null | undefined) => (id ? `/v1/media/${id}` : null);

/** Percent of the bill given back as points ("deduction factor"). 1 point = 1/redeem of $1. */
export const earnPercent = (earnPerUnit: number, redeemPerUnit: number) =>
  redeemPerUnit > 0 ? Math.round(((earnPerUnit * 100) / redeemPerUnit) * 10) / 10 : 0;

/** Value of points in minor units (cents) for a program. */
export const pointsValueMinor = (points: number, redeemPerUnit: number) =>
  redeemPerUnit > 0 ? Math.floor((points * 100) / redeemPerUnit) : 0;

/**
 * Columns for a shop card. Expects aliases: b = businesses, p = earning program.
 * $1 must be the viewing user's id (or null) so "my points here" can be shown.
 */
export const SHOP_CARD_SELECT = `
  b.id, b.name, b.category, b.featured, b.address, b.city, b.lat, b.lng, b.whatsapp,
  b.logo_media_id, b.cover_media_id, b.description,
  p.id AS program_id, p.type AS program_type, p.earn_points_per_unit, p.redeem_points_per_unit,
  COALESCE(r.avg, 0) AS rating, COALESCE(r.cnt, 0) AS rating_count,
  COALESCE(bal.balance, 0) AS my_points,
  COALESCE(oc.cnt, 0) AS offers_count,
  COALESCE(pop.cnt, 0) AS popularity`;

export const SHOP_CARD_JOINS = `
  JOIN programs p ON p.id = b.earning_program_id AND p.status = 'ACTIVE'
  LEFT JOIN LATERAL (SELECT avg(stars)::float AS avg, count(*)::int AS cnt
                       FROM business_ratings WHERE business_id = b.id) r ON true
  LEFT JOIN LATERAL (SELECT ab.balance FROM ledger_accounts a
                       JOIN account_balances ab ON ab.account_id = a.id
                      WHERE a.program_id = p.id AND a.owner_type = 'CUSTOMER' AND a.owner_id = $1::uuid) bal ON true
  LEFT JOIN LATERAL (SELECT count(*)::int AS cnt FROM offers o
                      WHERE o.business_id = b.id AND o.status = 'ACTIVE' AND NOT o.hidden_by_admin
                        AND o.valid_from <= current_date AND (o.valid_to IS NULL OR o.valid_to >= current_date)) oc ON true
  LEFT JOIN LATERAL (SELECT count(*)::int AS cnt FROM visits v
                      WHERE v.business_id = b.id AND v.created_at > now() - interval '30 days') pop ON true`;

export function shopCard(r: any) {
  return {
    id: r.id,
    name: r.name,
    category: r.category,
    description: r.description ?? null,
    featured: !!r.featured,
    programId: r.program_id,
    programType: r.program_type,
    earnPercent: earnPercent(Number(r.earn_points_per_unit), Number(r.redeem_points_per_unit)),
    pointsPerDollar: Number(r.redeem_points_per_unit),
    rating: Math.round(Number(r.rating) * 10) / 10,
    ratingCount: Number(r.rating_count),
    myPoints: Number(r.my_points),
    offersCount: Number(r.offers_count),
    address: r.address ?? null,
    city: r.city ?? null,
    lat: r.lat === null || r.lat === undefined ? null : Number(r.lat),
    lng: r.lng === null || r.lng === undefined ? null : Number(r.lng),
    logoUrl: mediaUrl(r.logo_media_id),
    coverUrl: mediaUrl(r.cover_media_id),
    hasWhatsapp: !!r.whatsapp,
  };
}

/** Offer columns; expects o = offers, b = businesses. */
export const OFFER_SELECT = `
  o.id, o.business_id, o.title, o.description, o.terms, o.media_id, o.kind, o.discount_percent,
  o.points_cost, o.saving_minor, o.requires_booking, o.max_per_customer, o.total_limit,
  o.valid_from::text AS valid_from, o.valid_to::text AS valid_to, o.status, o.created_at,
  b.name AS business_name, b.category AS business_category, b.logo_media_id AS business_logo`;

export function offerJson(r: any) {
  return {
    id: r.id,
    businessId: r.business_id,
    businessName: r.business_name,
    businessCategory: r.business_category,
    businessLogoUrl: mediaUrl(r.business_logo),
    title: r.title,
    description: r.description ?? null,
    terms: r.terms ?? null,
    imageUrl: mediaUrl(r.media_id),
    kind: r.kind,
    discountPercent: r.discount_percent ?? null,
    pointsCost: Number(r.points_cost),
    savingMinor: Number(r.saving_minor),
    requiresBooking: !!r.requires_booking,
    maxPerCustomer: Number(r.max_per_customer),
    totalLimit: r.total_limit ?? null,
    validFrom: r.valid_from,
    validTo: r.valid_to ?? null,
    status: r.status,
    hiddenByAdmin: !!r.hidden_by_admin,
  };
}

/** Reward columns; expects w = rewards, b = businesses, p = earning program. */
export const REWARD_SELECT = `
  w.id, w.business_id, w.title, w.description, w.media_id, w.points_cost, w.value_minor, w.stock, w.status,
  b.name AS business_name, b.category AS business_category, b.logo_media_id AS business_logo,
  p.id AS program_id`;

export function rewardJson(r: any, myPoints?: number) {
  return {
    id: r.id,
    businessId: r.business_id,
    businessName: r.business_name,
    businessCategory: r.business_category,
    businessLogoUrl: mediaUrl(r.business_logo),
    programId: r.program_id,
    title: r.title,
    description: r.description ?? null,
    imageUrl: mediaUrl(r.media_id),
    pointsCost: Number(r.points_cost),
    valueMinor: Number(r.value_minor),
    stock: r.stock ?? null,
    status: r.status,
    ...(myPoints === undefined ? {} : { myPoints, canAfford: myPoints >= Number(r.points_cost) }),
  };
}

export function productJson(r: any) {
  return {
    id: r.id,
    name: r.name,
    description: r.description ?? null,
    priceMinor: Number(r.price_minor),
    imageUrl: mediaUrl(r.media_id),
    available: !!r.available,
    sort: Number(r.sort ?? 0),
  };
}

export function bookingJson(r: any) {
  return {
    id: r.id,
    offerId: r.offer_id,
    businessId: r.business_id,
    status: r.status,
    code: r.code,
    requestedFor: r.requested_for ?? null,
    partySize: r.party_size ?? null,
    note: r.note ?? null,
    declineReason: r.decline_reason ?? null,
    createdAt: r.created_at,
    decidedAt: r.decided_at ?? null,
    redeemedAt: r.redeemed_at ?? null,
    offerTitle: r.offer_title ?? null,
    offerImageUrl: mediaUrl(r.offer_media),
    pointsCost: r.points_cost === undefined ? null : Number(r.points_cost),
    businessName: r.business_name ?? null,
    businessLogoUrl: mediaUrl(r.business_logo),
    customerName: r.customer_name ?? null,
    customerLast4: r.customer_last4 ?? null,
  };
}

/** Six-character booking code without look-alike letters. */
export function bookingCode() {
  const abc = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let s = '';
  for (let i = 0; i < 6; i++) s += abc[Math.floor(Math.random() * abc.length)];
  return s;
}

// ---------- Tiers (thresholds come from Manager settings) ----------
export type Tier = { key: 'SILVER' | 'GOLD' | 'PLATINUM'; min: number };
export const DEFAULT_TIERS: Tier[] = [
  { key: 'SILVER', min: 0 },
  { key: 'GOLD', min: 2500 },
  { key: 'PLATINUM', min: 10000 },
];

/** Reads one app setting (JSON) with a short in-memory cache. */
const settingsCache = new Map<string, { at: number; value: any }>();
export async function getSetting<T = any>(c: Queryable, key: string, fallback: T): Promise<T> {
  const hit = settingsCache.get(key);
  if (hit && Date.now() - hit.at < 15_000) return hit.value as T;
  const r = await c.query(`SELECT value FROM app_settings WHERE key = $1`, [key]);
  const value = r.rows[0]?.value ?? fallback;
  settingsCache.set(key, { at: Date.now(), value });
  return value as T;
}
export const clearSettingsCache = () => settingsCache.clear();

export async function loadTiers(c: Queryable): Promise<Tier[]> {
  const t = await getSetting<{ GOLD?: number; PLATINUM?: number }>(c, 'tiers', {});
  return [
    { key: 'SILVER', min: 0 },
    { key: 'GOLD', min: Number(t.GOLD ?? 2500) },
    { key: 'PLATINUM', min: Number(t.PLATINUM ?? 10000) },
  ];
}

export function tierFor(lifetime: number, tiers: Tier[] = DEFAULT_TIERS) {
  let current = tiers[0];
  for (const t of tiers) if (lifetime >= t.min) current = t;
  const idx = tiers.findIndex((t) => t.key === current.key);
  const next = tiers[idx + 1] ?? null;
  return { tier: current.key, min: current.min, next: next ? { tier: next.key, min: next.min } : null };
}

/** Points the customer has earned in total (not reduced by spending). */
export async function lifetimePoints(c: Queryable, userId: string): Promise<number> {
  const r = await c.query(
    `SELECT COALESCE(SUM(e.amount), 0) AS s
       FROM ledger_entries e
       JOIN ledger_accounts a ON a.id = e.account_id AND a.owner_type = 'CUSTOMER' AND a.owner_id = $1
       JOIN ledger_transactions t ON t.id = e.transaction_id
      WHERE t.type IN ('EARN','PREPOINT_CLAIM') AND e.amount > 0`,
    [userId],
  );
  return Number(r.rows[0]?.s ?? 0);
}

// ---------- Tiers by total spend (v0.7, table tiers) ----------
export type TierRow = {
  code: string;
  nameEn: string;
  nameAr: string;
  minSpendMinor: number;
  bonusPoints: number;
  color: string | null;
  perks: string | null;
  sort: number;
  active: boolean;
};

export async function loadTierRows(c: Queryable, activeOnly = true): Promise<TierRow[]> {
  const r = await c.query(
    `SELECT code, name_en, name_ar, min_spend_minor, bonus_points, color, perks_en, sort, active
       FROM tiers WHERE ($1::boolean = false OR active) ORDER BY min_spend_minor, sort`,
    [activeOnly],
  );
  return r.rows.map((t) => ({
    code: t.code,
    nameEn: t.name_en,
    nameAr: t.name_ar,
    minSpendMinor: Number(t.min_spend_minor),
    bonusPoints: Number(t.bonus_points),
    color: t.color ?? null,
    perks: t.perks_en ?? null,
    sort: Number(t.sort),
    active: !!t.active,
  }));
}

/** Highest tier whose minimum the spend reaches (rows sorted by minimum). */
export function tierForSpend(rows: TierRow[], spendMinor: number): TierRow | null {
  let cur: TierRow | null = null;
  for (const t of rows) if (spendMinor >= t.minSpendMinor) cur = t;
  return cur;
}

/** The customer's tier, the tier after it and progress, for the apps. */
export function tierProgress(rows: TierRow[], tierCode: string, spendMinor: number) {
  const idx = rows.findIndex((t) => t.code === tierCode);
  const cur = idx >= 0 ? rows[idx] : tierForSpend(rows, spendMinor);
  const curIdx = cur ? rows.indexOf(cur) : -1;
  const next = rows.slice(curIdx + 1).find((t) => t.minSpendMinor > spendMinor) ?? null;
  return { current: cur, next };
}

export const tierName = (t: TierRow, locale: string | null | undefined) => (locale === 'en' ? t.nameEn : t.nameAr);

// ---------- Fixed member QR (v0.7) ----------
export const MEMBER_QR_PREFIX = 'MKF2:';
const MEMBER_ABC = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

/** The customer's permanent 12-character member code, created on first use. */
export async function memberCode(c: Queryable, userId: string): Promise<string> {
  for (let i = 0; i < 8; i++) {
    const r = await c.query(`SELECT member_code FROM users WHERE id = $1`, [userId]);
    if (!r.rows[0]) throw new AppError(404, 'NOT_FOUND', 'User not found');
    if (r.rows[0].member_code) return String(r.rows[0].member_code);
    let code = '';
    for (let k = 0; k < 12; k++) code += MEMBER_ABC[randomInt(0, MEMBER_ABC.length)];
    try {
      await c.query(`UPDATE users SET member_code = $2 WHERE id = $1 AND member_code IS NULL`, [userId, code]);
    } catch (e) {
      if (pgCode(e) !== '23505') throw e;
    }
  }
  throw new AppError(500, 'MEMBER_CODE', 'Could not create a member code');
}

// ---------- Business alerts (live popup + sound in the Business app) ----------
export type AlertKind = 'BOOKING' | 'ORDER' | 'REDEEM_APPROVED' | 'REDEEM_DECLINED' | 'RATING' | 'OFFER_USED';

/** Saves an alert for a shop, in the shop owner's language. */
export async function alertBusiness(
  c: Queryable,
  businessId: string,
  kind: AlertKind,
  text: { ar: Text; en: Text },
  refId?: string | null,
) {
  const o = await c.query(`SELECT u.locale FROM businesses b JOIN users u ON u.id = b.owner_user_id WHERE b.id = $1`, [businessId]);
  const t = o.rows[0]?.locale === 'en' ? text.en : text.ar;
  await c.query(`INSERT INTO business_alerts(business_id, kind, title, body, ref_id) VALUES ($1,$2,$3,$4,$5)`, [
    businessId,
    kind,
    t.title,
    t.body ?? null,
    refId ?? null,
  ]);
}

/**
 * Alerts newer than [after] (oldest first, at most 50). Without [after] the app
 * only learns the latest id, so it starts from "now".
 */
export async function listAlerts(c: Queryable, businessId: string, after: number | undefined) {
  if (after === undefined) {
    const r = await c.query(`SELECT COALESCE(MAX(id), 0) AS id FROM business_alerts WHERE business_id = $1`, [businessId]);
    return { alerts: [] as Record<string, unknown>[], cursor: Number(r.rows[0]?.id ?? 0) };
  }
  const r = await c.query(
    `SELECT id, kind, title, body, ref_id, created_at FROM business_alerts
      WHERE business_id = $1 AND id > $2 ORDER BY id LIMIT 50`,
    [businessId, after],
  );
  const alerts = r.rows.map((x) => ({
    id: Number(x.id),
    kind: x.kind,
    title: x.title,
    body: x.body ?? null,
    refId: x.ref_id ?? null,
    createdAt: x.created_at,
  }));
  return { alerts, cursor: alerts.length ? alerts[alerts.length - 1].id : after };
}

export const fmtMoney = (minor: number) => `$${(minor / 100).toFixed(2)}`;

// ---------- Notifications ----------
type Text = { title: string; body?: string };

/** Saves an in-app notification in the customer's language. */
export async function notify(
  c: Queryable,
  userId: string,
  kind: string,
  text: { ar: Text; en: Text },
  data?: Record<string, unknown>,
) {
  const u = await c.query(`SELECT locale FROM users WHERE id = $1`, [userId]);
  const t = u.rows[0]?.locale === 'en' ? text.en : text.ar;
  await c.query(`INSERT INTO notifications(user_id, kind, title, body, data) VALUES ($1,$2,$3,$4,$5)`, [
    userId,
    kind,
    t.title,
    t.body ?? null,
    data ? JSON.stringify(data) : null,
  ]);
}

export const fmtPts = (n: number) => Math.round(n).toLocaleString('en-US');
