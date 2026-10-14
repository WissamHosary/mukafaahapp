import { Controller, Get, Module, Param, Res } from '@nestjs/common';
import type { Tx } from '../platform/db.js';
import { Db } from '../platform/db.js';
import { AppError, Errors } from '../platform/errors.js';
import { parse, zUuid } from '../platform/validation.js';

const MAX_BYTES = 3 * 1024 * 1024;

/** Checks the file really is the image type it claims to be. */
function sniff(buf: Buffer): 'image/jpeg' | 'image/png' | 'image/webp' | null {
  if (buf.length > 3 && buf[0] === 0xff && buf[1] === 0xd8 && buf[2] === 0xff) return 'image/jpeg';
  if (buf.length > 8 && buf.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) return 'image/png';
  if (buf.length > 12 && buf.subarray(0, 4).toString('ascii') === 'RIFF' && buf.subarray(8, 12).toString('ascii') === 'WEBP') {
    return 'image/webp';
  }
  return null;
}

/** Stores an uploaded image for a business and returns its id. */
export async function saveImage(c: Tx, businessId: string | null, base64: string): Promise<string> {
  const clean = base64.replace(/^data:[^;]+;base64,/, '');
  const buf = Buffer.from(clean, 'base64');
  if (buf.length === 0 || buf.length > MAX_BYTES) throw new AppError(413, 'IMAGE_TOO_LARGE', 'Images must be under 3 MB');
  const type = sniff(buf);
  if (!type) throw new AppError(415, 'IMAGE_TYPE', 'Use a JPG, PNG or WebP image');
  const r = await c.query(
    `INSERT INTO media(owner_business_id, content_type, bytes, size) VALUES ($1,$2,$3,$4) RETURNING id`,
    [businessId, type, buf, buf.length],
  );
  return r.rows[0].id;
}

/** Public image download. Images never change once stored, so they cache forever. */
@Controller('v1/media')
export class MediaController {
  constructor(private readonly db: Db) {}

  @Get(':id')
  async get(@Param('id') id: string, @Res() reply: any) {
    const m = await this.db.one(`SELECT content_type, bytes FROM media WHERE id = $1`, [parse(zUuid, id)]);
    if (!m) throw Errors.notFound('Image');
    reply
      .header('content-type', m.content_type)
      .header('cache-control', 'public, max-age=31536000, immutable')
      .header('cross-origin-resource-policy', 'cross-origin')
      .send(m.bytes);
  }
}

@Module({ controllers: [MediaController] })
export class MediaModule {}
