import { Body, Controller, Delete, Get, HttpCode, Module, Param, Patch, Post, Put } from '@nestjs/common';
import { randomInt } from 'node:crypto';
import { z } from 'zod';
import { audit } from '../platform/audit.js';
import { Auth, ClientIp, RequireOwner, RequireUser, type OwnerAuth, type UserAuth } from '../platform/auth.js';
import { CryptoService } from '../platform/crypto.js';
import { Db, type Tx } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zUuid } from '../platform/validation.js';
import { alertBusiness, mediaUrl, notify, prettyPhone } from './shared.js';

/*
 * Optional online store for each shop. Catalog, variants and cart only:
 * there is no online payment. Orders are sent to the shop on WhatsApp and the
 * shop confirms them in the business app (stock is taken when confirmed).
 */

const MAX_OPTIONS = 3;
const MAX_VALUES = 20;
const MAX_VARIANTS = 100;
const MAX_IMAGES = 8;

const zMoney = z.number().int().min(0).max(100_000_000);
const zOption = z.strictObject({
  name: z.string().trim().min(1).max(30),
  values: z.array(z.string().trim().min(1).max(30)).min(1).max(MAX_VALUES),
});
const zVariant = z.strictObject({
  id: zUuid.optional(),
  optionValues: z.array(z.string().trim().min(1).max(30)).max(MAX_OPTIONS),
  priceMinor: zMoney,
  compareAtMinor: zMoney.nullable().optional(),
  stock: z.number().int().min(0).max(1_000_000).nullable().optional(),
  sku: z.string().trim().max(60).nullable().optional(),
  imageId: zUuid.nullable().optional(),
  active: z.boolean().default(true),
});
const productFields = {
  name: z.string().trim().min(1).max(90),
  description: z.string().trim().max(2000).nullable().optional(),
  categoryId: zUuid.nullable().optional(),
  priceMinor: zMoney,
  compareAtMinor: zMoney.nullable().optional(),
  imageIds: z.array(zUuid).max(MAX_IMAGES),
  trackStock: z.boolean(),
  stock: z.number().int().min(0).max(1_000_000).nullable().optional(),
  options: z.array(zOption).max(MAX_OPTIONS),
  variants: z.array(zVariant).max(MAX_VARIANTS),
  available: z.boolean(),
  featured: z.boolean(),
  sort: z.number().int().min(0).max(10000),
};
const zProduct = z.strictObject({
  ...productFields,
  imageIds: productFields.imageIds.default([]),
  trackStock: productFields.trackStock.default(false),
  options: productFields.options.default([]),
  variants: productFields.variants.default([]),
  available: productFields.available.default(true),
  featured: productFields.featured.default(false),
  sort: productFields.sort.default(0),
});
const zProductPatch = z.strictObject(productFields).partial().extend({ archived: z.boolean().optional() });
const zStore = z.strictObject({ enabled: z.boolean() });
const zCategory = z.strictObject({
  name: z.string().trim().min(1).max(40),
  sort: z.number().int().min(0).max(10000).optional(),
  /** Picture for the category tile (an uploaded image). */
  imageId: zUuid.nullable().optional(),
});
const zCategoryPatch = z.strictObject({
  name: z.string().trim().min(1).max(40).optional(),
  imageId: zUuid.nullable().optional(),
  sort: z.number().int().min(0).max(10000).optional(),
  active: z.boolean().optional(),
});
const zOrderStatus = z.strictObject({ status: z.enum(['CONFIRMED', 'READY', 'COMPLETED', 'CANCELLED']) });
/** One line of plain text: no line breaks or control characters, so nobody can rewrite the WhatsApp message. */
const zLine = (min: number, max: number) =>
  z
    .string()
    .transform((v) => v.replace(/[\u0000-\u001f\u007f\u2028\u2029]+/g, ' ').replace(/\s+/g, ' ').trim())
    .pipe(z.string().min(min).max(max));
const zOrder = z.strictObject({
  items: z
    .array(z.strictObject({ productId: zUuid, variantId: zUuid.optional(), qty: z.number().int().min(1).max(99) }))
    .min(1)
    .max(50),
  fulfilment: z.enum(['PICKUP', 'DELIVERY']).default('PICKUP'),
  /** Older apps send one address line. */
  address: zLine(0, 300).optional(),
  note: zLine(0, 300).optional(),
  contact: z
    .strictObject({
      name: zLine(2, 60),
      phone: z.string().trim().regex(/^\+?[0-9 ]{7,20}$/),
    })
    .optional(),
  delivery: z
    .strictObject({
      area: zLine(2, 80),
      street: zLine(2, 120),
      building: zLine(0, 80).optional(),
      landmark: zLine(0, 120).optional(),
      lat: z.number().min(-90).max(90).optional(),
      lng: z.number().min(-180).max(180).optional(),
    })
    .optional(),
});
/** Limits that stop fake or spam orders. */
const ORDER_MAX_OPEN_PER_SHOP = 3;
const ORDER_MAX_PER_DAY = 10;
const ORDER_MAX_TOTAL_MINOR = 500_000;

type Option = z.infer<typeof zOption>;
type VariantIn = z.infer<typeof zVariant>;

/** How the shop hands orders over (set in Mukafaah Manager). */
export function fulfilmentJson(b: any) {
  return {
    pickup: b.store_pickup !== false,
    delivery: b.store_delivery !== false,
    deliveryFeeMinor: Number(b.delivery_fee_minor ?? 0),
    freeDeliveryOverMinor: b.free_delivery_over_minor == null ? null : Number(b.free_delivery_over_minor),
    minOrderMinor: Number(b.min_order_minor ?? 0),
    note: b.delivery_note ?? null,
  };
}

/** Delivery fee for an order of [subtotal]: free above the shop's threshold. */
export function deliveryFee(f: ReturnType<typeof fulfilmentJson>, subtotal: number) {
  if (f.freeDeliveryOverMinor != null && subtotal >= f.freeDeliveryOverMinor) return 0;
  return f.deliveryFeeMinor;
}

const money = (m: number) => `$${(m / 100).toFixed(2).replace(/\.00$/, '')}`;
const orderCode = () => Array.from({ length: 5 }, () => 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'[randomInt(32)]).join('');

/** Checks that every variant matches the options exactly once. */
function checkVariants(options: Option[], variants: VariantIn[]) {
  const names = new Set<string>();
  for (const o of options) {
    const k = o.name.toLowerCase();
    if (names.has(k)) throw Errors.validation({ options: ['DUPLICATE_OPTION'] });
    names.add(k);
    if (new Set(o.values.map((v) => v.toLowerCase())).size !== o.values.length) throw Errors.validation({ options: ['DUPLICATE_VALUE'] });
  }
  if (!options.length && variants.length) throw Errors.validation({ variants: ['NO_OPTIONS'] });
  if (options.length && !variants.length) throw Errors.validation({ variants: ['REQUIRED'] });
  const seen = new Set<string>();
  for (const v of variants) {
    if (v.optionValues.length !== options.length) throw Errors.validation({ variants: ['OPTION_COUNT'] });
    v.optionValues.forEach((val, i) => {
      if (!options[i].values.includes(val)) throw Errors.validation({ variants: ['UNKNOWN_VALUE'] });
    });
    const key = v.optionValues.join('\u0000').toLowerCase();
    if (seen.has(key)) throw Errors.validation({ variants: ['DUPLICATE_VARIANT'] });
    seen.add(key);
  }
}

function variantJson(v: any) {
  return {
    id: v.id,
    optionValues: v.option_values as string[],
    priceMinor: Number(v.price_minor),
    compareAtMinor: v.compare_at_minor == null ? null : Number(v.compare_at_minor),
    stock: v.stock ?? null,
    inStock: v.stock == null || v.stock > 0,
    sku: v.sku ?? null,
    imageId: v.media_id ?? null,
    imageUrl: mediaUrl(v.media_id),
    active: v.active,
  };
}

/** Product as the customer and the owner see it. Pass its variants for the full view. */
function productJson(p: any, variants?: any[]) {
  const vs = (variants ?? []).filter((v) => v.active);
  const prices = vs.length ? vs.map((v) => Number(v.price_minor)) : [Number(p.price_minor)];
  const images: string[] = (p.image_ids ?? []).length ? p.image_ids : p.media_id ? [p.media_id] : [];
  const productInStock = !p.track_stock || (p.stock ?? 0) > 0;
  return {
    id: p.id,
    name: p.name,
    description: p.description ?? null,
    categoryId: p.category_id ?? null,
    priceMinor: Math.min(...prices),
    maxPriceMinor: Math.max(...prices),
    compareAtMinor: p.compare_at_minor == null ? null : Number(p.compare_at_minor),
    imageIds: images,
    imageUrls: images.map((id) => mediaUrl(id)),
    imageUrl: mediaUrl(images[0]),
    trackStock: !!p.track_stock,
    stock: p.stock ?? null,
    options: p.options ?? [],
    hasVariants: (p.options ?? []).length > 0,
    inStock: variants ? (vs.length ? vs.some((v) => v.stock == null || v.stock > 0) : productInStock) : p.in_stock ?? productInStock,
    available: !!p.available,
    featured: !!p.featured,
    sort: Number(p.sort ?? 0),
    ...(variants ? { variants: variants.map(variantJson) } : {}),
  };
}

/** Product list query: one row per product with a precomputed price range and stock flag. */
export const PRODUCT_LIST = `
  SELECT p.*,
         COALESCE((SELECT min(v.price_minor) FROM product_variants v WHERE v.product_id = p.id AND v.active), p.price_minor) AS min_price,
         COALESCE((SELECT max(v.price_minor) FROM product_variants v WHERE v.product_id = p.id AND v.active), p.price_minor) AS max_price,
         CASE WHEN jsonb_array_length(p.options) > 0
              THEN EXISTS (SELECT 1 FROM product_variants v WHERE v.product_id = p.id AND v.active AND (v.stock IS NULL OR v.stock > 0))
              ELSE (NOT p.track_stock OR COALESCE(p.stock, 0) > 0) END AS in_stock
    FROM products p`;

export function listJson(p: any) {
  const j = productJson(p);
  return { ...j, priceMinor: Number(p.min_price), maxPriceMinor: Number(p.max_price), inStock: !!p.in_stock };
}

async function saveVariants(c: Tx, productId: string, variants: VariantIn[]) {
  const existing = (await c.query(`SELECT id FROM product_variants WHERE product_id = $1`, [productId])).rows.map((r) => r.id as string);
  const kept = new Set<string>();
  for (let i = 0; i < variants.length; i++) {
    const v = variants[i];
    const vals = [v.optionValues, v.priceMinor, v.compareAtMinor ?? null, v.stock ?? null, v.sku ?? null, v.imageId ?? null, v.active, i];
    if (v.id && existing.includes(v.id)) {
      kept.add(v.id);
      await c.query(
        `UPDATE product_variants SET option_values = $2, price_minor = $3, compare_at_minor = $4, stock = $5, sku = $6, media_id = $7, active = $8, sort = $9
          WHERE id = $1`,
        [v.id, ...vals],
      );
    } else {
      await c.query(
        `INSERT INTO product_variants(product_id, option_values, price_minor, compare_at_minor, stock, sku, media_id, active, sort)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)`,
        [productId, ...vals],
      );
    }
  }
  // Variants removed in the editor are switched off (past orders may refer to them).
  const gone = existing.filter((id) => !kept.has(id));
  if (gone.length) await c.query(`UPDATE product_variants SET active = false WHERE id = ANY($1::uuid[])`, [gone]);
}

// =====================================================================
// Shop owner: manage the store
// =====================================================================
@Controller('v1/business/manage/store')
@RequireOwner()
export class StoreOwnerController {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
  ) {}

  private async ownMedia(ids: (string | null | undefined)[], businessId: string) {
    const list = [...new Set(ids.filter((x): x is string => !!x))];
    if (!list.length) return;
    const r = await this.db.query(`SELECT id FROM media WHERE id = ANY($1::uuid[]) AND owner_business_id = $2`, [list, businessId]);
    if (r.rowCount !== list.length) throw Errors.notFound('Image');
  }

  private async ownCategory(id: string | null | undefined, businessId: string) {
    if (!id) return;
    const r = await this.db.one(`SELECT 1 FROM store_categories WHERE id = $1 AND business_id = $2`, [id, businessId]);
    if (!r) throw Errors.notFound('Category');
  }

  @Get()
  async store(@Auth() a: OwnerAuth) {
    const [b, cats, prods, orders] = await Promise.all([
      this.db.one(`SELECT store_enabled, whatsapp FROM businesses WHERE id = $1`, [a.businessId]),
      this.db.query(
        `SELECT c.*, (SELECT count(*)::int FROM products p WHERE p.category_id = c.id AND NOT p.archived) AS products
           FROM store_categories c WHERE c.business_id = $1 AND c.active ORDER BY c.sort, c.created_at`,
        [a.businessId],
      ),
      this.db.query(`${PRODUCT_LIST} WHERE p.business_id = $1 AND NOT p.archived ORDER BY p.sort, p.created_at`, [a.businessId]),
      this.db.one(`SELECT count(*)::int AS n FROM whatsapp_orders WHERE business_id = $1 AND status = 'NEW'`, [a.businessId]),
    ]);
    return {
      enabled: !!b?.store_enabled,
      hasWhatsapp: !!b?.whatsapp,
      newOrders: orders?.n ?? 0,
      categories: cats.rows.map((c) => ({ id: c.id, name: c.name, sort: c.sort, products: c.products, imageId: c.media_id ?? null, imageUrl: mediaUrl(c.media_id) })),
      products: prods.rows.map(listJson),
    };
  }

  @Put()
  async setStore(@Auth() a: OwnerAuth, @Body() body: unknown, @ClientIp() ip: string) {
    const b = parse(zStore, body);
    await this.db.tx(async (c) => {
      await c.query(`UPDATE businesses SET store_enabled = $2 WHERE id = $1`, [a.businessId, b.enabled]);
      await audit(c, { actorType: 'USER', actorId: a.userId, businessId: a.businessId, action: b.enabled ? 'store.enable' : 'store.disable', ip });
    });
    return { ok: true };
  }

  // ---------- Categories ----------
  @Post('categories')
  async createCategory(@Auth() a: OwnerAuth, @Body() body: unknown) {
    const b = parse(zCategory, body);
    const n = await this.db.one(`SELECT count(*)::int AS n FROM store_categories WHERE business_id = $1 AND active`, [a.businessId]);
    if ((n?.n ?? 0) >= 50) throw new AppError(409, 'LIMIT_REACHED', 'Up to 50 categories');
    if (b.imageId) await this.ownMedia([b.imageId], a.businessId);
    const r = await this.db.one(
      `INSERT INTO store_categories(business_id, name, sort, media_id) VALUES ($1,$2,$3,$4) RETURNING id`,
      [a.businessId, b.name, b.sort ?? (n?.n ?? 0) * 10, b.imageId ?? null],
    );
    return { id: r.id };
  }

  @Patch('categories/:id')
  async patchCategory(@Auth() a: OwnerAuth, @Param('id') id: string, @Body() body: unknown) {
    const b = parse(zCategoryPatch, body);
    if (b.imageId) await this.ownMedia([b.imageId], a.businessId);
    const r = await this.db.query(
      `UPDATE store_categories SET name = COALESCE($3, name), sort = COALESCE($4, sort), active = COALESCE($5, active),
              media_id = CASE WHEN $6::boolean THEN $7::uuid ELSE media_id END
        WHERE id = $1 AND business_id = $2`,
      [parse(zUuid, id), a.businessId, b.name ?? null, b.sort ?? null, b.active ?? null, b.imageId !== undefined, b.imageId ?? null],
    );
    if (!r.rowCount) throw Errors.notFound('Category');
    if (b.active === false) await this.db.query(`UPDATE products SET category_id = NULL WHERE category_id = $1`, [id]);
    return { ok: true };
  }

  @Delete('categories/:id')
  async deleteCategory(@Auth() a: OwnerAuth, @Param('id') id: string) {
    return this.patchCategory(a, id, { active: false });
  }

  // ---------- Products ----------
  @Get('products/:id')
  async product(@Auth() a: OwnerAuth, @Param('id') id: string) {
    const pid = parse(zUuid, id);
    const p = await this.db.one(`SELECT * FROM products WHERE id = $1 AND business_id = $2 AND NOT archived`, [pid, a.businessId]);
    if (!p) throw Errors.notFound('Product');
    const v = await this.db.query(`SELECT * FROM product_variants WHERE product_id = $1 AND active ORDER BY sort`, [pid]);
    return productJson(p, v.rows);
  }

  @Post('products')
  async createProduct(@Auth() a: OwnerAuth, @Body() body: unknown) {
    const b = parse(zProduct, body);
    checkVariants(b.options, b.variants);
    await this.ownCategory(b.categoryId, a.businessId);
    await this.ownMedia([...b.imageIds, ...b.variants.map((v) => v.imageId)], a.businessId);
    const count = await this.db.one(`SELECT count(*)::int AS n FROM products WHERE business_id = $1 AND NOT archived`, [a.businessId]);
    if ((count?.n ?? 0) >= 500) throw new AppError(409, 'LIMIT_REACHED', 'Up to 500 products');
    return this.db.tx(async (c) => {
      const r = await c.query(
        `INSERT INTO products(business_id, name, description, category_id, price_minor, compare_at_minor, media_id, image_ids,
                              track_stock, stock, options, available, featured, sort)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8::uuid[],$9,$10,$11,$12,$13,$14) RETURNING id`,
        [
          a.businessId,
          b.name,
          b.description ?? null,
          b.categoryId ?? null,
          b.priceMinor,
          b.compareAtMinor ?? null,
          b.imageIds[0] ?? null,
          b.imageIds,
          b.trackStock,
          b.trackStock ? (b.stock ?? 0) : null,
          JSON.stringify(b.options),
          b.available,
          b.featured,
          b.sort,
        ],
      );
      const id = r.rows[0].id as string;
      if (b.variants.length) await saveVariants(c, id, b.variants);
      return { id };
    });
  }

  @Patch('products/:id')
  async patchProduct(@Auth() a: OwnerAuth, @Param('id') id: string, @Body() body: unknown) {
    const pid = parse(zUuid, id);
    const b = parse(zProductPatch, body);
    const cur = await this.db.one(`SELECT options FROM products WHERE id = $1 AND business_id = $2 AND NOT archived`, [pid, a.businessId]);
    if (!cur) throw Errors.notFound('Product');
    if (b.options !== undefined || b.variants !== undefined) {
      if (b.options === undefined || b.variants === undefined) throw Errors.validation({ variants: ['SEND_OPTIONS_AND_VARIANTS'] });
      checkVariants(b.options, b.variants);
    }
    await this.ownCategory(b.categoryId, a.businessId);
    await this.ownMedia([...(b.imageIds ?? []), ...(b.variants ?? []).map((v) => v.imageId)], a.businessId);
    await this.db.tx(async (c) => {
      const map: Record<string, unknown> = {
        name: b.name,
        description: b.description,
        category_id: b.categoryId,
        price_minor: b.priceMinor,
        compare_at_minor: b.compareAtMinor,
        track_stock: b.trackStock,
        stock: b.trackStock === false ? null : b.stock,
        available: b.available,
        featured: b.featured,
        sort: b.sort,
        archived: b.archived,
      };
      const cols: string[] = [];
      const vals: unknown[] = [pid];
      for (const [k, v] of Object.entries(map)) {
        if (v === undefined) continue;
        vals.push(v);
        cols.push(`${k} = $${vals.length}`);
      }
      if (b.imageIds !== undefined) {
        vals.push(b.imageIds);
        cols.push(`image_ids = $${vals.length}::uuid[]`);
        vals.push(b.imageIds[0] ?? null);
        cols.push(`media_id = $${vals.length}`);
      }
      if (b.options !== undefined) {
        vals.push(JSON.stringify(b.options));
        cols.push(`options = $${vals.length}`);
      }
      cols.push('updated_at = now()');
      await c.query(`UPDATE products SET ${cols.join(', ')} WHERE id = $1`, vals);
      if (b.variants !== undefined) await saveVariants(c, pid, b.variants);
    });
    return { ok: true };
  }

  // ---------- Orders ----------
  @Get('orders')
  async orders(@Auth() a: OwnerAuth) {
    const r = await this.db.query(
      `SELECT w.*, u.name, u.phone_last4, u.phone_enc FROM whatsapp_orders w JOIN users u ON u.id = w.user_id
        WHERE w.business_id = $1 ORDER BY (w.status = 'NEW') DESC, w.created_at DESC LIMIT 200`,
      [a.businessId],
    );
    return r.rows.map((x) => ({
      id: x.id,
      code: x.code ?? null,
      status: x.status,
      fulfilment: x.fulfilment,
      address: x.address ?? null,
      items: x.items,
      totalMinor: Number(x.total_minor),
      note: x.note ?? null,
      createdAt: x.created_at,
      customer: x.name ?? `•••• ${x.phone_last4}`,
      // Who to call and where to go.
      contactName: x.contact_name ?? null,
      contactPhone: x.contact_phone ?? null,
      customerPhone: x.phone_enc ? prettyPhone(this.crypto.decrypt(x.phone_enc)) : null,
      mapUrl: x.lat != null && x.lng != null ? `https://maps.google.com/?q=${Number(x.lat).toFixed(6)},${Number(x.lng).toFixed(6)}` : null,
    }));
  }

  /** Confirming takes tracked stock; cancelling a confirmed order puts it back. */
  @Post('orders/:id/status')
  @HttpCode(200)
  async orderStatus(@Auth() a: OwnerAuth, @Param('id') id: string, @Body() body: unknown, @ClientIp() ip: string) {
    const oid = parse(zUuid, id);
    const b = parse(zOrderStatus, body);
    return this.db.tx(async (c) => {
      const o = (await c.query(`SELECT * FROM whatsapp_orders WHERE id = $1 AND business_id = $2 FOR UPDATE`, [oid, a.businessId])).rows[0];
      if (!o) throw Errors.notFound('Order');
      const allowed: Record<string, string[]> = {
        NEW: ['CONFIRMED', 'CANCELLED'],
        CONFIRMED: ['READY', 'COMPLETED', 'CANCELLED'],
        READY: ['COMPLETED', 'CANCELLED'],
        COMPLETED: [],
        CANCELLED: [],
      };
      if (!allowed[o.status].includes(b.status)) throw new AppError(409, 'BAD_STATUS', `Can't go from ${o.status} to ${b.status}`);
      const items = (o.items ?? []) as { productId?: string; variantId?: string | null; qty: number }[];
      let stockTaken = o.stock_taken as boolean;
      const sign = b.status === 'CONFIRMED' && !stockTaken ? -1 : b.status === 'CANCELLED' && stockTaken ? 1 : 0;
      if (sign !== 0) {
        for (const it of items) {
          if (it.variantId) {
            await c.query(`UPDATE product_variants SET stock = GREATEST(stock + $2, 0) WHERE id = $1 AND stock IS NOT NULL`, [it.variantId, sign * it.qty]);
          } else if (it.productId) {
            await c.query(`UPDATE products SET stock = GREATEST(stock + $2, 0) WHERE id = $1 AND track_stock AND stock IS NOT NULL`, [it.productId, sign * it.qty]);
          }
        }
        stockTaken = sign < 0;
      }
      await c.query(`UPDATE whatsapp_orders SET status = $2, stock_taken = $3, updated_at = now() WHERE id = $1`, [oid, b.status, stockTaken]);
      const biz = (await c.query(`SELECT name FROM businesses WHERE id = $1`, [a.businessId])).rows[0];
      const label: Record<string, [string, string]> = {
        CONFIRMED: ['Order confirmed', 'تم تأكيد طلبك'],
        READY: ['Order ready', 'طلبك جاهز'],
        COMPLETED: ['Order completed', 'تم تسليم الطلب'],
        CANCELLED: ['Order cancelled', 'تم إلغاء الطلب'],
      };
      const body = `${biz?.name ?? ''} · #${o.code ?? ''}`;
      await notify(c, o.user_id, 'ORDER', { en: { title: label[b.status][0], body }, ar: { title: label[b.status][1], body } }, { orderId: oid, shopId: a.businessId });
      await audit(c, { actorType: 'USER', actorId: a.userId, businessId: a.businessId, action: `order.${b.status.toLowerCase()}`, entityId: oid, ip });
      return { ok: true, status: b.status };
    });
  }
}

// =====================================================================
// Customer: browse a shop's store and send an order
// =====================================================================
@Controller('v1/customer/shops')
@RequireUser()
export class StoreCustomerController {
  constructor(
    private readonly db: Db,
    private readonly crypto: CryptoService,
  ) {}

  private async openStore(shopId: string) {
    const b = await this.db.one(
      `SELECT id, name, whatsapp, store_enabled, store_pickup, store_delivery, delivery_fee_minor, free_delivery_over_minor,
              min_order_minor, delivery_note, logo_media_id
         FROM businesses WHERE id = $1 AND status = 'ACTIVE' AND listed`,
      [shopId],
    );
    if (!b) throw Errors.notFound('Shop');
    if (!b.store_enabled) throw new AppError(404, 'STORE_CLOSED', 'This shop has no online store');
    return b;
  }

  @Get(':id/store')
  async store(@Param('id') id: string) {
    const bid = parse(zUuid, id);
    const b = await this.openStore(bid);
    const [cats, prods] = await Promise.all([
      this.db.query(`SELECT id, name, media_id FROM store_categories WHERE business_id = $1 AND active ORDER BY sort, created_at`, [bid]),
      this.db.query(`${PRODUCT_LIST} WHERE p.business_id = $1 AND NOT p.archived AND p.available ORDER BY p.featured DESC, p.sort, p.created_at`, [bid]),
    ]);
    const products = prods.rows.map(listJson);
    const used = new Set(products.map((p) => p.categoryId).filter(Boolean));
    return {
      shopName: b.name,
      logoUrl: mediaUrl(b.logo_media_id),
      canOrder: !!b.whatsapp,
      fulfilment: fulfilmentJson(b),
      categories: cats.rows.filter((c) => used.has(c.id)).map((c) => ({ id: c.id, name: c.name, imageUrl: mediaUrl(c.media_id) })),
      products,
    };
  }

  @Get(':id/products/:pid')
  async product(@Param('id') id: string, @Param('pid') pid: string) {
    const bid = parse(zUuid, id);
    await this.openStore(bid);
    const p = await this.db.one(`SELECT * FROM products WHERE id = $1 AND business_id = $2 AND NOT archived AND available`, [parse(zUuid, pid), bid]);
    if (!p) throw Errors.notFound('Product');
    const v = await this.db.query(`SELECT * FROM product_variants WHERE product_id = $1 AND active ORDER BY sort`, [p.id]);
    return productJson(p, v.rows);
  }

  /**
   * Builds the WhatsApp order from server prices and stock. No payment happens
   * in the app: the customer sends the message and the shop confirms it.
   */
  @Post(':id/order')
  @HttpCode(200)
  async order(@Auth() a: UserAuth, @Param('id') id: string, @Body() body: unknown) {
    const bid = parse(zUuid, id);
    const b = parse(zOrder, body);
    const biz = await this.openStore(bid);
    if (!biz.whatsapp) throw new AppError(409, 'NO_WHATSAPP', 'This shop has no WhatsApp number yet');
    const ful = fulfilmentJson(biz);
    if (b.fulfilment === 'DELIVERY' && !ful.delivery) throw new AppError(409, 'NO_DELIVERY', 'This shop does not deliver. Choose pickup.');
    if (b.fulfilment === 'PICKUP' && !ful.pickup) throw new AppError(409, 'NO_PICKUP', 'This shop only delivers.');
    if (b.fulfilment === 'DELIVERY' && !b.address && !b.delivery) throw Errors.validation({ address: ['REQUIRED'] });
    if (b.fulfilment === 'DELIVERY' && b.delivery && !b.contact) throw Errors.validation({ contact: ['REQUIRED'] });
    // Spam guard: a few open orders per shop and a daily cap per member.
    const recent = await this.db.one(
      `SELECT count(*) FILTER (WHERE business_id = $2 AND status = 'NEW')::int AS open,
              count(*) FILTER (WHERE created_at > now() - interval '1 day')::int AS day
         FROM whatsapp_orders WHERE user_id = $1 AND created_at > now() - interval '7 days'`,
      [a.userId, bid],
    );
    if ((recent?.open ?? 0) >= ORDER_MAX_OPEN_PER_SHOP) {
      throw new AppError(429, 'ORDER_OPEN_LIMIT', 'You already have orders waiting at this shop. Wait for them to be confirmed.');
    }
    if ((recent?.day ?? 0) >= ORDER_MAX_PER_DAY) throw Errors.tooMany('ORDER_DAY_LIMIT');

    const pids = [...new Set(b.items.map((i) => i.productId))];
    const vids = [...new Set(b.items.map((i) => i.variantId).filter((x): x is string => !!x))];
    const [prods, vars] = await Promise.all([
      this.db.query(`SELECT * FROM products WHERE business_id = $1 AND id = ANY($2::uuid[]) AND available AND NOT archived`, [bid, pids]),
      vids.length
        ? this.db.query(`SELECT * FROM product_variants WHERE id = ANY($1::uuid[]) AND active`, [vids])
        : Promise.resolve({ rows: [] as any[] }),
    ]);
    const pById = new Map(prods.rows.map((r) => [r.id, r]));
    const vById = new Map(vars.rows.map((r) => [r.id, r]));
    const lines: { productId: string; variantId: string | null; name: string; variant: string | null; qty: number; priceMinor: number }[] = [];
    let total = 0;
    for (const it of b.items) {
      const p = pById.get(it.productId);
      if (!p) throw new AppError(409, 'PRODUCT_UNAVAILABLE', 'An item is no longer available');
      const hasOptions = (p.options ?? []).length > 0;
      let price = Number(p.price_minor);
      let variant: string | null = null;
      if (hasOptions) {
        const v = it.variantId ? vById.get(it.variantId) : undefined;
        if (!v || v.product_id !== p.id) throw new AppError(409, 'CHOOSE_OPTIONS', 'Choose the options for every item');
        if (v.stock != null && v.stock < it.qty) throw new AppError(409, 'OUT_OF_STOCK', `${p.name}: only ${v.stock} left`);
        price = Number(v.price_minor);
        variant = (v.option_values as string[]).join(' / ');
      } else if (p.track_stock && (p.stock ?? 0) < it.qty) {
        throw new AppError(409, 'OUT_OF_STOCK', `${p.name}: only ${p.stock ?? 0} left`);
      }
      lines.push({ productId: p.id, variantId: hasOptions ? (it.variantId ?? null) : null, name: p.name, variant, qty: it.qty, priceMinor: price });
      total += price * it.qty;
    }
    if (total > ORDER_MAX_TOTAL_MINOR) throw new AppError(409, 'ORDER_TOO_LARGE', `Orders above ${money(ORDER_MAX_TOTAL_MINOR)} are arranged with the shop directly`);
    if (total < ful.minOrderMinor) throw new AppError(409, 'ORDER_TOO_SMALL', `The minimum order is ${money(ful.minOrderMinor)}`);
    const subtotal = total;
    const fee = b.fulfilment === 'DELIVERY' ? deliveryFee(ful, subtotal) : 0;
    total = subtotal + fee;
    const d = b.fulfilment === 'DELIVERY' ? b.delivery : undefined;
    const address = d ? [d.area, d.street, d.building, d.landmark].filter(Boolean).join(', ') : b.fulfilment === 'DELIVERY' ? (b.address ?? null) : null;
    const mapUrl = d?.lat != null && d?.lng != null ? `https://maps.google.com/?q=${d.lat.toFixed(6)},${d.lng.toFixed(6)}` : null;

    const user = await this.db.one(`SELECT name, phone_last4, phone_enc, locale FROM users WHERE id = $1`, [a.userId]);
    // The member's own number, checked with a WhatsApp code when they joined.
    const verified = user?.phone_enc ? prettyPhone(this.crypto.decrypt(user.phone_enc)) : null;
    const ar = user?.locale !== 'en';
    const code = orderCode();
    const text = [
      ar ? `طلب جديد من مكافأة #${code}` : `New Mukafaah order #${code}`,
      biz.name,
      '',
      ...lines.map((l) => `• ${l.qty} × ${l.name}${l.variant ? ` (${l.variant})` : ''} — ${money(l.priceMinor * l.qty)}`),
      '',
      ...(b.fulfilment === 'DELIVERY'
        ? [`${ar ? 'المنتجات' : 'Items'}: ${money(subtotal)}`, `${ar ? 'التوصيل' : 'Delivery'}: ${fee ? money(fee) : ar ? 'مجاني' : 'Free'}`]
        : []),
      `${ar ? 'المجموع' : 'Total'}: ${money(total)}`,
      b.fulfilment === 'DELIVERY' ? (ar ? 'توصيل' : 'Delivery') : ar ? 'استلام من المحل' : 'Pickup from the shop',
      ...(b.fulfilment === 'DELIVERY' && address ? [`${ar ? 'العنوان' : 'Address'}: ${address}`] : []),
      ...(mapUrl ? [`${ar ? 'الموقع' : 'Location'}: ${mapUrl}`] : []),
      ...(b.note ? [`${ar ? 'ملاحظة' : 'Note'}: ${b.note}`] : []),
      '',
      `${ar ? 'الاسم' : 'Name'}: ${b.contact?.name ?? user?.name ?? ''}`,
      ...(b.contact?.phone ? [`${ar ? 'رقم التواصل' : 'Contact phone'}: ${b.contact.phone}`] : []),
      `${ar ? 'رقم مكافأة (موثّق)' : 'Mukafaah number (verified)'}: ${verified ?? `•••• ${user?.phone_last4 ?? ''}`}`,
      '',
      ar ? `تأكد من الطلب #${code} بتطبيق مكافأة للأعمال قبل التحضير.` : `Check order #${code} in Mukafaah Business before preparing it.`,
      ar ? 'الدفع عند الاستلام. ما في دفع مسبق.' : 'Pay on delivery or pickup. No payment in advance.',
    ].join('\n');

    const r = await this.db.tx(async (c) => {
      const row = (
        await c.query(
          `INSERT INTO whatsapp_orders(business_id, user_id, items, total_minor, note, code, fulfilment, address,
                                       contact_name, contact_phone, area, street, building, landmark, lat, lng, delivery_fee_minor)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17) RETURNING id`,
          [
            bid, a.userId, JSON.stringify(lines), total, b.note ?? null, code, b.fulfilment, address,
            b.contact?.name ?? null, b.contact?.phone ?? null, d?.area ?? null, d?.street ?? null, d?.building ?? null,
            d?.landmark ?? null, d?.lat ?? null, d?.lng ?? null, fee,
          ],
        )
      ).rows[0];
      const who = user?.name || `•••• ${user?.phone_last4 ?? ''}`;
      const items = lines.reduce((n, l) => n + l.qty, 0);
      await alertBusiness(
        c,
        bid,
        'ORDER',
        {
          ar: { title: `طلب جديد #${code}`, body: `${who} · ${items} · ${money(total)}` },
          en: { title: `New order #${code}`, body: `${who} · ${items} item${items === 1 ? '' : 's'} · ${money(total)}` },
        },
        row.id,
      );
      return row;
    });
    const phone = String(biz.whatsapp).replace(/\D/g, '');
    return { orderId: r.id, code, totalMinor: total, subtotalMinor: subtotal, deliveryFeeMinor: fee, text, whatsappUrl: `https://wa.me/${phone}?text=${encodeURIComponent(text)}` };
  }
}

@Module({ controllers: [StoreOwnerController, StoreCustomerController] })
export class StoreModule {}
