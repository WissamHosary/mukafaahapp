import { z } from 'zod';
import { Errors } from './errors.js';

/** Parse and validate an untrusted body/query with a zod schema (unknown keys rejected). */
export function parse<T extends z.ZodType>(schema: T, input: unknown): z.infer<T> {
  const r = schema.safeParse(input ?? {});
  if (!r.success) throw Errors.validation(z.flattenError(r.error));
  return r.data;
}

export const zMinor = z.number().int().nonnegative().max(1_000_000_000);
export const zPoints = z.number().int().positive().max(100_000_000);
export const zUuid = z.uuid();
