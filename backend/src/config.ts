import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'staging', 'production']).default('development'),
  PORT: z.coerce.number().int().default(3000),
  DATABASE_URL: z.string().min(1),
  KEYS_DIR: z.string().default('/app/keys'),
  // In development the OTP code is also returned in the API response so the
  // apps can be tested without an SMS provider. Never enabled in production.
  OTP_DEV_ECHO: z
    .string()
    .default('false')
    .transform((v) => v === 'true'),
  OTP_PROVIDER: z.enum(['console']).default('console'),
  OTP_ALLOWED_COUNTRIES: z.string().default('LB'),
  DEFAULT_PHONE_REGION: z.string().default('LB'),
  // Comma-separated browser origins allowed to call the API (web test builds).
  CORS_ORIGINS: z.string().default(''),
  // Phones that become Mukafaah Manager admins when they sign in (comma separated).
  ADMIN_PHONES: z.string().default(''),
  // Only trust X-Forwarded-For when running behind our own load balancer.
  TRUST_PROXY: z
    .string()
    .default('false')
    .transform((v) => v === 'true'),
});

export type AppConfig = z.infer<typeof schema>;

export function loadConfig(): AppConfig {
  const parsed = schema.safeParse(process.env);
  if (!parsed.success) {
    console.error('Invalid configuration', z.treeifyError(parsed.error));
    process.exit(1);
  }
  const cfg = parsed.data;
  if (cfg.NODE_ENV === 'production' && cfg.OTP_DEV_ECHO) {
    console.error('OTP_DEV_ECHO must be false in production');
    process.exit(1);
  }
  return cfg;
}

export const config = loadConfig();
