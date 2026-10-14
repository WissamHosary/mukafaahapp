import { Global, Inject, Injectable, Logger, Module, OnModuleDestroy } from '@nestjs/common';
import { readdir, readFile } from 'node:fs/promises';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import pg from 'pg';
import type { PoolClient } from 'pg';
import { config } from '../config.js';

// bigint columns come back as strings by default; points fit safely in JS numbers.
pg.types.setTypeParser(20, (v: string) => Number(v));
// date columns as plain 'YYYY-MM-DD' strings.
pg.types.setTypeParser(1082, (v: string) => v);

export const PG_POOL = Symbol('PG_POOL');
export type Tx = PoolClient;
/** Anything that can run a query: the pool wrapper or a transaction client. */
export interface Queryable {
  query(sql: string, params?: unknown[]): Promise<{ rows: any[]; rowCount: number | null }>;
}

@Injectable()
export class Db implements OnModuleDestroy {
  private readonly log = new Logger('Db');
  constructor(@Inject(PG_POOL) private readonly pool: pg.Pool) {}

  query<T extends pg.QueryResultRow = any>(sql: string, params: unknown[] = []) {
    return this.pool.query<T>(sql, params);
  }

  async one<T extends pg.QueryResultRow = any>(sql: string, params: unknown[] = []): Promise<T | undefined> {
    const r = await this.pool.query<T>(sql, params);
    return r.rows[0];
  }

  /** Run fn inside a transaction; rolls back on any error. */
  async tx<T>(fn: (c: Tx) => Promise<T>): Promise<T> {
    const c = await this.pool.connect();
    try {
      await c.query('BEGIN');
      const out = await fn(c);
      await c.query('COMMIT');
      return out;
    } catch (e) {
      await c.query('ROLLBACK').catch(() => undefined);
      throw e;
    } finally {
      c.release();
    }
  }

  async migrate() {
    const here = dirname(fileURLToPath(import.meta.url));
    const dir = join(here, '..', '..', 'sql');
    const files = (await readdir(dir)).filter((f) => f.endsWith('.sql')).sort();
    await this.pool.query(
      'CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())',
    );
    for (const f of files) {
      const done = await this.pool.query('SELECT 1 FROM schema_migrations WHERE name = $1', [f]);
      if (done.rowCount) continue;
      const sql = await readFile(join(dir, f), 'utf8');
      await this.tx(async (c) => {
        await c.query(sql);
        await c.query('INSERT INTO schema_migrations(name) VALUES ($1) ON CONFLICT DO NOTHING', [f]);
      });
      this.log.log(`Applied migration ${f}`);
    }
  }

  async onModuleDestroy() {
    await this.pool.end();
  }
}

@Global()
@Module({
  providers: [
    {
      provide: PG_POOL,
      useFactory: () => new pg.Pool({ connectionString: config.DATABASE_URL, max: 20 }),
    },
    Db,
  ],
  exports: [Db],
})
export class DbModule {}

/** Postgres error helpers. */
export const pgCode = (e: unknown): string | undefined =>
  typeof e === 'object' && e !== null && 'code' in e ? String((e as { code: unknown }).code) : undefined;
