import { Body, Controller, Delete, Get, HttpCode, Module, Param, Patch, Post, Put, Query } from '@nestjs/common';
import { z } from 'zod';
import { audit } from '../platform/audit.js';
import { Auth, ClientIp, RequireOwner, type OwnerAuth } from '../platform/auth.js';
import { Db } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zUuid } from '../platform/validation.js';
import { saveImage } from './media.js';
import { bookingJson, earnPercent, mediaUrl, notify, productJson } from './shared.js';

const zDate = z.iso.date();
const zImage = z.string().min(20).max(4_500_000);

const zProfile = z.strictObject({
  name: z.string().trim().min(2).max(80).optional(),
  description: z.string().trim().max(600).nullable().optional(),
  category: z.string().regex(/^[A-Z0-9_]{2,40}$/).optional(),
  whatsapp: z.string().trim().regex(/^\+?[0-9 ]{7,20}$/).nullable().optional(),
  instagram: z.string().trim().max(60).nullable().optional(),
  address: z.string().trim().max(160).nullable().optional(),
  city: z.string().trim().max(60).nullable().optional(),
  lat: z.number().min(-90).max(90).nullable().optional(),
  lng: z.number().min(-180).max(180).nullable().optional(),
  listed: z.boolean().optional(),
  allowTransfer: z.boolean().optional(),
  facebook: z.string().trim().max(120).nullable().optional(),
  tiktok: z.string().trim().max(60).nullable().optional(),
  website: z.string().trim().max(200).regex(/^https?:\/\/\S+$/, 'Start the website with https://').nullable().optional(),
  phone: z.string().trim().regex(/^\+?[0-9 ]{7,20}$/).nullable().optional(),
  hours: z.string().trim().max(120).nullable().optional(),
  /** 7 days, Monday first: null = closed that day. */
  openingHours: z
    .array(z.strictObject({ open: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/), close: z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/) }).nullable())
    .length(7)
    .nullable()
    .optional(),
  temporarilyClosed: z.boolean().optional(),
  // Online store hand-over (edited in Mukafaah Manager).
  storePickup: z.boolean().optional(),
  storeDelivery: z.boolean().optional(),
  deliveryFeeMinor: z.number().int().min(0).max(100000).optional(),
  freeDeliveryOverMinor: z.number().int().min(0).max(10000000).nullable().optional(),
  minOrderMinor: z.number().int().min(0).max(10000000).optional(),
  deliveryNote: z.string().trim().max(120).nullable().optional(),
});
const zBanner = z.strictObject({ dataBase64: z.string().min(20).max(4_500_000), caption: z.string().trim().max(80).nullable().optional() });
const zBannerOrder = z.strictObject({ ids: z.array(zUuid).max(10) });
const MAX_BANNERS = 10;
const zUpload = z.strictObject({ purpose: z.enum(['logo', 'cover', 'item']), dataBase64: zImage });

const offerFields = {
  title: z.string().trim().min(2).max(90),
  description: z.string().trim().max(600).nullable().optional(),
  terms: z.string().trim().max(600).nullable().optional(),
  imageId: zUuid.nullable().optional(),
  kind: z.enum(['DEAL', 'DISCOUNT', 'FREE_ITEM', 'SERVICE']),
  discountPercent: z.number().int().min(1).max(100).nullable().optional(),
  pointsCost: z.number().int().min(0).max(10_000_000),
  savingMinor: z.number().int().min(0).max(100_000_000),
  requiresBooking: z.boolean(),
  maxPerCustomer: z.number().int().min(1).max(100),
  totalLimit: z.number().int().min(1).max(1_000_000).nullable().optional(),
  validFrom: zDate.optional(),
  validTo: zDate.nullable().optional(),
};
const zOffer = z.strictObject({
  ...offerFields,
  kind: offerFields.kind.default('DEAL'),
  pointsCost: offerFields.pointsCost.default(0),
  savingMinor: offerFields.savingMinor.default(0),
  requiresBooking: offerFields.requiresBooking.default(true),
  maxPerCustomer: offerFields.maxPerCustomer.default(1),
});
const zOfferPatch = z
  .strictObject(offerFields)
  .partial()
  .extend({ status: z.enum(['ACTIVE', 'PAUSED', 'ARCHIVED']).optional() });

const rewardFields = {
  title: z.string().trim().min(2).max(90),
  description: z.string().trim().max(600).nullable().optional(),
  imageId: zUuid.nullable().optional(),
  pointsCost: z.number().int().min(1).max(10_000_000),
  valueMinor: z.number().int().min(0).max(100_000_000),
  stock: z.number().int().min(0).max(1_000_000).nullable().optional(),
  status: z.enum(['ACTIVE', 'PAUSED', 'ARCHIVED']).optional(),
};
const zReward = z.strictObject({ ...rewardFields, valueMinor: rewardFields.valueMinor.default(0) });
const zRewardPatch = z.strictObject(rewardFields).partial();

const productFields = {
  name: z.string().trim().min(1).max(90),
  description: z.string().trim().max(400).nullable().optional(),
  priceMinor: z.number().int().min(0).max(100_000_000),
  imageId: zUuid.nullable().optional(),
  available: z.boolean(),
  sort: z.number().int().min(0).max(10000),
};
const zProduct = z.strictObject({
  ...productFields,
  available: productFields.available.default(true),
  sort: productFields.sort.default(0),
});
const zProductPatch = z.strictObject(productFields).partial().extend({ archived: z.boolean().optional() });

const zBookings = z.object({ status: z.enum(['REQUESTED', 'ACCEPTED', 'HISTORY']).default('REQUESTED') });
const zDecline = z.strictObject({ reason: z.string().trim().min(2).max(200).optional() });

/** Fields an owner may set on a row; undefined means "leave as is", null clears. */
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

@Controller('v1/business/manage')
@RequireOwner()
export class MerchantController {
  constructor(private readonly db: Db) {}

  // ---------- Shop profile ----------
  @Get('profile')
  async profile(@Auth() a: OwnerAuth) {
    const b = await this.db.one(
      `SELECT b.*, p.earn_points_per_unit, p.redeem_points_per_unit, p.allow_transfer, p.type AS program_type
         FROM businesses b JOIN programs p ON p.id = b.earning_program_id WHERE b.id = $1`,
      [a.businessId],
    );
    return {
      id: b.id,
      name: b.name,
      description: b.description ?? null,
      category: b.category,
      whatsapp: b.whatsapp ?? null,
      instagram: b.instagram ?? null,
      address: b.address ?? null,
      city: b.city ?? null,
      lat: b.lat ?? null,
      lng: b.lng ?? null,
      facebook: b.facebook ?? null,
      tiktok: b.tiktok ?? null,
      website: b.website ?? null,
      phone: b.phone ?? null,
      hours: b.hours ?? null,
      openingHours: b.opening_hours ?? null,
      temporarilyClosed: !!b.temporarily_closed,
      storePickup: b.store_pickup !== false,
      storeDelivery: b.store_delivery !== false,
      deliveryFeeMinor: Number(b.delivery_fee_minor ?? 0),
      freeDeliveryOverMinor: b.free_delivery_over_minor == null ? null : Number(b.free_delivery_over_minor),
      minOrderMinor: Number(b.min_order_minor ?? 0),
      deliveryNote: b.delivery_note ?? null,
      banners: (
        await this.db.query(`SELECT id, media_id, caption FROM business_banners WHERE business_id = $1 ORDER BY sort, created_at`, [b.id])
      ).rows.map((x) => ({ id: x.id, url: mediaUrl(x.media_id), caption: x.caption ?? null })),
      listed: b.listed,
      featured: b.featured,
      logoUrl: mediaUrl(b.logo_media_id),
      coverUrl: mediaUrl(b.cover_media_id),
      programType: b.program_type,
      earnPercent: earnPercent(Number(b.earn_points_per_unit), Number(b.redeem_points_per_unit)),
      pointsPerDollar: Number(b.redeem_points_per_unit),
      allowTransfer: b.allow_transfer,
    };
  }

  @Patch('profile')
  async updateProfile(@Auth() a: OwnerAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zProfile, body);
    await this.db.tx(async (c) => {
      const s = setClause(
        {
          name: b.name,
          description: b.description,
          category: b.category,
          whatsapp: b.whatsapp,
          instagram: b.instagram,
          address: b.address,
          city: b.city,
          lat: b.lat,
          lng: b.lng,
          listed: b.listed,
          facebook: b.facebook,
          tiktok: b.tiktok?.replace(/^@/, ''),
          website: b.website,
          phone: b.phone,
          hours: b.hours,
          opening_hours: b.openingHours === undefined ? undefined : b.openingHours === null ? null : JSON.stringify(b.openingHours),
          temporarily_closed: b.temporarilyClosed,
          store_pickup: b.storePickup,
          store_delivery: b.storeDelivery,
          delivery_fee_minor: b.deliveryFeeMinor,
          free_delivery_over_minor: b.freeDeliveryOverMinor,
          min_order_minor: b.minOrderMinor,
          delivery_note: b.deliveryNote,
        },
        2,
      );
      if (s.vals.length) await c.query(`UPDATE businesses SET ${s.sql} WHERE id = $1`, [a.businessId, ...s.vals]);
      // The points-back % ("deduction factor") is set by Mukafaah Manager only.
      if (b.allowTransfer !== undefined) {
        await c.query(`UPDATE programs SET allow_transfer = $2 WHERE owner_business_id = $1 AND type = 'IN_STORE'`, [
          a.businessId,
          b.allowTransfer,
        ]);
      }
      if (b.name) {
        await c.query(`UPDATE programs SET name = $2 WHERE owner_business_id = $1 AND type = 'IN_STORE'`, [a.businessId, b.name]);
      }
      await audit(c, { actorType: 'OWNER', actorId: a.userId, businessId: a.businessId, action: 'business.profile', data: b, ip });
    });
    return this.profile(a);
  }

  // ---------- Banners: pictures that slide at the top of the shop page ----------
  @Post('banners')
  async addBanner(@Auth() a: OwnerAuth, @Body() body: unknown) {
    const b = parse(zBanner, body);
    return this.db.tx(async (c) => {
      const n = (await c.query(`SELECT count(*)::int AS n FROM business_banners WHERE business_id = $1`, [a.businessId])).rows[0].n;
      if (n >= MAX_BANNERS) throw new AppError(409, 'BANNERS_FULL', `Up to ${MAX_BANNERS} banners`);
      const mediaId = await saveImage(c, a.businessId, b.dataBase64);
      const row = (
        await c.query(
          `INSERT INTO business_banners(business_id, media_id, caption, sort) VALUES ($1,$2,$3,$4) RETURNING id`,
          [a.businessId, mediaId, b.caption ?? null, n],
        )
      ).rows[0];
      return { id: row.id, url: mediaUrl(mediaId), caption: b.caption ?? null };
    });
  }

  @Delete('banners/:bannerId')
  async deleteBanner(@Auth() a: OwnerAuth, @Param('bannerId') id: string) {
    const r = await this.db.query(`DELETE FROM business_banners WHERE id = $1 AND business_id = $2`, [parse(zUuid, id), a.businessId]);
    if (!r.rowCount) throw Errors.notFound('Banner');
    return { ok: true };
  }

  @Put('banners/order')
  async orderBanners(@Auth() a: OwnerAuth, @Body() body: unknown) {
    const b = parse(zBannerOrder, body);
    await this.db.tx(async (c) => {
      for (const [i, id] of b.ids.entries()) {
        await c.query(`UPDATE business_banners SET sort = $3 WHERE id = $1 AND business_id = $2`, [id, a.businessId, i]);
      }
    });
    return { ok: true };
  }

  /** Upload an image. Logo and cover are applied to the shop right away. */
  @Post('media')
  async upload(@Auth() a: OwnerAuth, @Body() body: unknown) {
    const b = parse(zUpload, body);
    return this.db.tx(async (c) => {
      const id = await saveImage(c, a.businessId, b.dataBase64);
      if (b.purpose === 'logo') await c.query(`UPDATE businesses SET logo_media_id = $2 WHERE id = $1`, [a.businessId, id]);
      if (b.purpose === 'cover') await c.query(`UPDATE businesses SET cover_media_id = $2 WHERE id = $1`, [a.businessId, id]);
      return { id, url: mediaUrl(id) };
    });
  }

  private async ownMedia(id: string | null | undefined, businessId: string) {
    if (!id) return;
    const m = await this.db.one(`SELECT 1 FROM media WHERE id = $1 AND owner_business_id = $2`, [id, businessId]);
    if (!m) throw Errors.notFound('Image');
  }

  // ---------- Offers ----------
  @Get('offers')
  async offers(@Auth() a: OwnerAuth) {
    const r = await this.db.query(
      `SELECT o.*, o.valid_from::text AS vf, o.valid_to::text AS vt,
              (SELECT count(*)::int FROM offer_bookings k WHERE k.offer_id = o.id AND k.status = 'REQUESTED') AS requested,
              (SELECT count(*)::int FROM offer_bookings k WHERE k.offer_id = o.id AND k.status = 'ACCEPTED') AS accepted,
              (SELECT count(*)::int FROM offer_bookings k WHERE k.offer_id = o.id AND k.status = 'REDEEMED') AS redeemed
         FROM offers o WHERE o.business_id = $1 AND o.status <> 'ARCHIVED' ORDER BY o.created_at DESC`,
      [a.businessId],
    );
    return r.rows.map((o) => ({
      id: o.id,
      title: o.title,
      description: o.description ?? null,
      terms: o.terms ?? null,
      imageId: o.media_id ?? null,
      imageUrl: mediaUrl(o.media_id),
      kind: o.kind,
      discountPercent: o.discount_percent ?? null,
      pointsCost: Number(o.points_cost),
      savingMinor: Number(o.saving_minor),
      requiresBooking: o.requires_booking,
      maxPerCustomer: o.max_per_customer,
      totalLimit: o.total_limit ?? null,
      validFrom: o.vf,
      validTo: o.vt ?? null,
      status: o.status,
      hiddenByAdmin: !!o.hidden_by_admin,
      stats: { requested: o.requested, accepted: o.accepted, redeemed: o.redeemed },
    }));
  }

  @Post('offers')
  async createOffer(@Auth() a: OwnerAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zOffer, body);
    await this.ownMedia(b.imageId, a.businessId);
    return this.db.tx(async (c) => {
      const r = await c.query(
        `INSERT INTO offers(business_id, title, description, terms, media_id, kind, discount_percent, points_cost, saving_minor,
                            requires_booking, max_per_customer, total_limit, valid_from, valid_to)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,COALESCE($13::date, current_date),$14) RETURNING id`,
        [
          a.businessId,
          b.title,
          b.description ?? null,
          b.terms ?? null,
          b.imageId ?? null,
          b.kind,
          b.discountPercent ?? null,
          b.pointsCost,
          b.savingMinor,
          b.requiresBooking,
          b.maxPerCustomer,
          b.totalLimit ?? null,
          b.validFrom ?? null,
          b.validTo ?? null,
        ],
      );
      await audit(c, { actorType: 'OWNER', actorId: a.userId, businessId: a.businessId, action: 'offer.create', entityId: r.rows[0].id, ip });
      return { id: r.rows[0].id };
    });
  }

  @Patch('offers/:id')
  async patchOffer(@Auth() a: OwnerAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const oid = parse(zUuid, id);
    const b = parse(zOfferPatch, body);
    await this.ownMedia(b.imageId, a.businessId);
    const s = setClause(
      {
        title: b.title,
        description: b.description,
        terms: b.terms,
        media_id: b.imageId,
        kind: b.kind,
        discount_percent: b.discountPercent,
        points_cost: b.pointsCost,
        saving_minor: b.savingMinor,
        requires_booking: b.requiresBooking,
        max_per_customer: b.maxPerCustomer,
        total_limit: b.totalLimit,
        valid_from: b.validFrom,
        valid_to: b.validTo,
        status: b.status,
      },
      3,
    );
    if (!s.vals.length) return { ok: true };
    await this.db.tx(async (c) => {
      const r = await c.query(`UPDATE offers SET ${s.sql}, updated_at = now() WHERE id = $1 AND business_id = $2`, [oid, a.businessId, ...s.vals]);
      if (!r.rowCount) throw Errors.notFound('Offer');
      await audit(c, { actorType: 'OWNER', actorId: a.userId, businessId: a.businessId, action: 'offer.update', entityId: oid, ip });
    });
    return { ok: true };
  }

  // ---------- Bookings inbox ----------
  @Get('bookings')
  async bookings(@Auth() a: OwnerAuth, @Query() q: unknown) {
    const f = parse(zBookings, q);
    const statuses = f.status === 'HISTORY' ? ['DECLINED', 'CANCELLED', 'REDEEMED', 'EXPIRED'] : [f.status];
    const r = await this.db.query(
      `SELECT k.*, o.title AS offer_title, o.media_id AS offer_media, o.points_cost,
              u.name AS customer_name, u.phone_last4 AS customer_last4
         FROM offer_bookings k JOIN offers o ON o.id = k.offer_id JOIN users u ON u.id = k.user_id
        WHERE k.business_id = $1 AND k.status = ANY($2::text[])
        ORDER BY ${f.status === 'HISTORY' ? 'k.updated_at DESC' : 'COALESCE(k.requested_for, k.created_at) ASC'}
        LIMIT 200`,
      [a.businessId, statuses],
    );
    return r.rows.map(bookingJson);
  }

  @Get('bookings/summary')
  async bookingSummary(@Auth() a: OwnerAuth) {
    const r = await this.db.one(
      `SELECT count(*) FILTER (WHERE status = 'REQUESTED')::int AS requested,
              count(*) FILTER (WHERE status = 'ACCEPTED')::int AS accepted
         FROM offer_bookings WHERE business_id = $1`,
      [a.businessId],
    );
    return { requested: r?.requested ?? 0, accepted: r?.accepted ?? 0 };
  }

  @Post('bookings/:id/accept')
  @HttpCode(200)
  async accept(@Auth() a: OwnerAuth, @Param('id') id: string, @ClientIp() ip: string) {
    return this.decide(a, parse(zUuid, id), 'ACCEPTED', null, ip);
  }

  @Post('bookings/:id/decline')
  @HttpCode(200)
  async decline(@Auth() a: OwnerAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zDecline, body);
    return this.decide(a, parse(zUuid, id), 'DECLINED', b.reason ?? null, ip);
  }

  private async decide(a: OwnerAuth, id: string, status: 'ACCEPTED' | 'DECLINED', reason: string | null, ip: string) {
    return this.db.tx(async (c) => {
      const k = (
        await c.query(
          `UPDATE offer_bookings SET status = $3, decided_at = now(), decline_reason = $4, updated_at = now()
            WHERE id = $1 AND business_id = $2 AND status = 'REQUESTED'
            RETURNING *`,
          [id, a.businessId, status, reason],
        )
      ).rows[0];
      if (!k) throw new AppError(409, 'BOOKING_NOT_PENDING', 'This booking was already handled');
      const info = (
        await c.query(`SELECT o.title, b.name FROM offers o JOIN businesses b ON b.id = o.business_id WHERE o.id = $1`, [k.offer_id])
      ).rows[0];
      if (status === 'ACCEPTED') {
        await notify(
          c,
          k.user_id,
          'BOOKING_ACCEPTED',
          {
            ar: { title: 'انقبل حجزك', body: `${info.name}: ${info.title}. رمز الحجز ${k.code}` },
            en: { title: 'Booking accepted', body: `${info.name}: ${info.title}. Booking code ${k.code}` },
          },
          { bookingId: k.id },
        );
      } else {
        await notify(
          c,
          k.user_id,
          'BOOKING_DECLINED',
          {
            ar: { title: 'ما انقبل الحجز', body: `${info.name}: ${info.title}${reason ? ` (${reason})` : ''}` },
            en: { title: 'Booking declined', body: `${info.name}: ${info.title}${reason ? ` (${reason})` : ''}` },
          },
          { bookingId: k.id },
        );
      }
      await audit(c, { actorType: 'OWNER', actorId: a.userId, businessId: a.businessId, action: `booking.${status.toLowerCase()}`, entityId: id, ip });
      return { ok: true, status };
    });
  }

  // ---------- Rewards ----------
  @Get('rewards')
  async rewards(@Auth() a: OwnerAuth) {
    const r = await this.db.query(
      `SELECT w.*, (SELECT count(*)::int FROM reward_redemptions rr WHERE rr.reward_id = w.id) AS redeemed
         FROM rewards w WHERE w.business_id = $1 AND w.status <> 'ARCHIVED' ORDER BY w.points_cost`,
      [a.businessId],
    );
    return r.rows.map((w) => ({
      id: w.id,
      title: w.title,
      description: w.description ?? null,
      imageId: w.media_id ?? null,
      imageUrl: mediaUrl(w.media_id),
      pointsCost: Number(w.points_cost),
      valueMinor: Number(w.value_minor),
      stock: w.stock ?? null,
      status: w.status,
      redeemed: w.redeemed,
    }));
  }

  @Post('rewards')
  async createReward(@Auth() a: OwnerAuth, @Body() body: unknown) {
    const b = parse(zReward, body);
    await this.ownMedia(b.imageId, a.businessId);
    const r = await this.db.one(
      `INSERT INTO rewards(business_id, title, description, media_id, points_cost, value_minor, stock, status)
       VALUES ($1,$2,$3,$4,$5,$6,$7,COALESCE($8,'ACTIVE')) RETURNING id`,
      [a.businessId, b.title, b.description ?? null, b.imageId ?? null, b.pointsCost, b.valueMinor, b.stock ?? null, b.status ?? null],
    );
    return { id: r.id };
  }

  @Patch('rewards/:id')
  async patchReward(@Auth() a: OwnerAuth, @Param('id') id: string, @Body() body: unknown) {
    const b = parse(zRewardPatch, body);
    await this.ownMedia(b.imageId, a.businessId);
    const s = setClause(
      {
        title: b.title,
        description: b.description,
        media_id: b.imageId,
        points_cost: b.pointsCost,
        value_minor: b.valueMinor,
        stock: b.stock,
        status: b.status,
      },
      3,
    );
    if (!s.vals.length) return { ok: true };
    const r = await this.db.query(`UPDATE rewards SET ${s.sql}, updated_at = now() WHERE id = $1 AND business_id = $2`, [
      parse(zUuid, id),
      a.businessId,
      ...s.vals,
    ]);
    if (!r.rowCount) throw Errors.notFound('Reward');
    return { ok: true };
  }

  // ---------- Products (for WhatsApp orders) ----------
  @Get('products')
  async products(@Auth() a: OwnerAuth) {
    const r = await this.db.query(`SELECT * FROM products WHERE business_id = $1 AND NOT archived ORDER BY sort, created_at`, [
      a.businessId,
    ]);
    return r.rows.map((p) => ({ ...productJson(p), imageId: p.media_id ?? null }));
  }

  @Post('products')
  async createProduct(@Auth() a: OwnerAuth, @Body() body: unknown) {
    const b = parse(zProduct, body);
    await this.ownMedia(b.imageId, a.businessId);
    const r = await this.db.one(
      `INSERT INTO products(business_id, name, description, price_minor, media_id, available, sort)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id`,
      [a.businessId, b.name, b.description ?? null, b.priceMinor, b.imageId ?? null, b.available, b.sort],
    );
    return { id: r.id };
  }

  @Patch('products/:id')
  async patchProduct(@Auth() a: OwnerAuth, @Param('id') id: string, @Body() body: unknown) {
    const b = parse(zProductPatch, body);
    await this.ownMedia(b.imageId, a.businessId);
    const s = setClause(
      {
        name: b.name,
        description: b.description,
        price_minor: b.priceMinor,
        media_id: b.imageId,
        available: b.available,
        sort: b.sort,
        archived: b.archived,
      },
      3,
    );
    if (!s.vals.length) return { ok: true };
    const r = await this.db.query(`UPDATE products SET ${s.sql} WHERE id = $1 AND business_id = $2`, [
      parse(zUuid, id),
      a.businessId,
      ...s.vals,
    ]);
    if (!r.rowCount) throw Errors.notFound('Product');
    return { ok: true };
  }

  /** WhatsApp orders customers sent from the app (for the owner's records). */
  @Get('orders')
  async orders(@Auth() a: OwnerAuth) {
    const r = await this.db.query(
      `SELECT w.id, w.items, w.total_minor, w.note, w.created_at, u.name, u.phone_last4
         FROM whatsapp_orders w JOIN users u ON u.id = w.user_id
        WHERE w.business_id = $1 ORDER BY w.created_at DESC LIMIT 100`,
      [a.businessId],
    );
    return r.rows.map((x) => ({
      id: x.id,
      items: x.items,
      totalMinor: Number(x.total_minor),
      note: x.note ?? null,
      createdAt: x.created_at,
      customer: x.name ?? `•••• ${x.phone_last4}`,
    }));
  }
}

@Module({ controllers: [MerchantController] })
export class MerchantModule {}
