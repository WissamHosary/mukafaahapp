import type { Tx } from './db.js';

export async function audit(
  c: Tx,
  a: {
    actorType: 'USER' | 'OWNER' | 'STAFF' | 'SYSTEM';
    actorId?: string | null;
    businessId?: string | null;
    action: string;
    entity?: string;
    entityId?: string;
    data?: Record<string, unknown>;
    ip?: string;
  },
) {
  await c.query(
    `INSERT INTO audit_log(actor_type, actor_id, business_id, action, entity, entity_id, data, ip)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8)`,
    [
      a.actorType,
      a.actorId ?? null,
      a.businessId ?? null,
      a.action,
      a.entity ?? null,
      a.entityId ?? null,
      a.data ? JSON.stringify(a.data) : null,
      a.ip ?? null,
    ],
  );
}
