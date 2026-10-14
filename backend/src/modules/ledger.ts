import { Global, Injectable, Module } from '@nestjs/common';
import { pgCode, type Tx } from '../platform/db.js';
import { AppError } from '../platform/errors.js';

export type OwnerType = 'CUSTOMER' | 'PENDING' | 'BUSINESS_ISSUED' | 'BUSINESS_REDEEMED';
export type TxType = 'EARN' | 'PREPOINT_EARN' | 'PREPOINT_CLAIM' | 'REDEEM' | 'VOID' | 'REVERSAL' | 'ADJUSTMENT' | 'TRANSFER' | 'GRANT';

export interface PostingInput {
  type: TxType;
  programId: string;
  idempotencyKey: string;
  entries: { accountId: string; amount: number }[];
  businessId?: string | null;
  branchId?: string | null;
  staffId?: string | null;
  deviceId?: string | null;
  userId?: string | null;
  pendingHolderId?: string | null;
  reversesTxId?: string | null;
  reason?: string | null;
}

/**
 * The only code that writes ledger tables. Every posting is double-entry
 * (entries sum to zero, also enforced by a DB trigger), idempotent by key,
 * and locks balance rows in a fixed order to avoid deadlocks.
 */
@Injectable()
export class LedgerService {
  async account(c: Tx, programId: string, ownerType: OwnerType, ownerId: string): Promise<string> {
    const ins = await c.query(
      `INSERT INTO ledger_accounts(program_id, owner_type, owner_id) VALUES ($1,$2,$3)
       ON CONFLICT (program_id, owner_type, owner_id) DO NOTHING RETURNING id`,
      [programId, ownerType, ownerId],
    );
    let id: string;
    if (ins.rows[0]) {
      id = ins.rows[0].id;
      await c.query(
        `INSERT INTO account_balances(account_id, balance, allow_negative) VALUES ($1, 0, $2) ON CONFLICT DO NOTHING`,
        [id, ownerType === 'BUSINESS_ISSUED'],
      );
    } else {
      const r = await c.query(
        `SELECT id FROM ledger_accounts WHERE program_id=$1 AND owner_type=$2 AND owner_id=$3`,
        [programId, ownerType, ownerId],
      );
      id = r.rows[0].id;
    }
    return id;
  }

  async balance(c: Tx, accountId: string): Promise<number> {
    const r = await c.query(`SELECT balance FROM account_balances WHERE account_id = $1`, [accountId]);
    return r.rows[0]?.balance ?? 0;
  }

  /** Returns the existing transaction id when the idempotency key was already used. */
  async existing(c: Tx, idempotencyKey: string): Promise<string | undefined> {
    const r = await c.query(`SELECT id FROM ledger_transactions WHERE idempotency_key = $1`, [idempotencyKey]);
    return r.rows[0]?.id;
  }

  async post(c: Tx, p: PostingInput): Promise<string> {
    const sum = p.entries.reduce((s, e) => s + e.amount, 0);
    if (sum !== 0 || p.entries.length < 2 || p.entries.some((e) => !Number.isSafeInteger(e.amount) || e.amount === 0)) {
      throw new AppError(500, 'LEDGER_UNBALANCED');
    }
    const ids = [...new Set(p.entries.map((e) => e.accountId))].sort();
    await c.query(
      `SELECT account_id FROM account_balances WHERE account_id = ANY($1::uuid[]) ORDER BY account_id FOR UPDATE`,
      [ids],
    );
    await c.query('SAVEPOINT ledger_post');
    try {
      const tx = await c.query(
        `INSERT INTO ledger_transactions
           (type, program_id, idempotency_key, business_id, branch_id, staff_id, device_id,
            user_id, pending_holder_id, reverses_tx_id, reason)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11) RETURNING id`,
        [
          p.type,
          p.programId,
          p.idempotencyKey,
          p.businessId ?? null,
          p.branchId ?? null,
          p.staffId ?? null,
          p.deviceId ?? null,
          p.userId ?? null,
          p.pendingHolderId ?? null,
          p.reversesTxId ?? null,
          p.reason ?? null,
        ],
      );
      const txId: string = tx.rows[0].id;
      for (const e of p.entries) {
        await c.query(`INSERT INTO ledger_entries(transaction_id, account_id, amount) VALUES ($1,$2,$3)`, [
          txId,
          e.accountId,
          e.amount,
        ]);
        await c.query(
          `UPDATE account_balances SET balance = balance + $2, version = version + 1 WHERE account_id = $1`,
          [e.accountId, e.amount],
        );
      }
      await c.query('RELEASE SAVEPOINT ledger_post');
      return txId;
    } catch (e) {
      await c.query('ROLLBACK TO SAVEPOINT ledger_post');
      const code = pgCode(e);
      if (code === '23514') throw new AppError(409, 'INSUFFICIENT_BALANCE', 'Not enough points');
      if (code === '23505') throw new AppError(409, 'DUPLICATE_REQUEST', 'Request already processed');
      throw e;
    }
  }

  /** Posts the exact opposite of an earlier transaction. */
  async reverse(
    c: Tx,
    originalTxId: string,
    type: 'VOID' | 'REVERSAL',
    meta: Omit<PostingInput, 'type' | 'entries' | 'programId' | 'reversesTxId'>,
  ): Promise<string> {
    const orig = await c.query(`SELECT * FROM ledger_transactions WHERE id = $1`, [originalTxId]);
    if (!orig.rows[0]) throw new AppError(404, 'NOT_FOUND', 'Transaction not found');
    const already = await c.query(`SELECT id FROM ledger_transactions WHERE reverses_tx_id = $1`, [originalTxId]);
    if (already.rows[0]) throw new AppError(409, 'ALREADY_REVERSED', 'Transaction already reversed');
    const entries = await c.query(`SELECT account_id, amount FROM ledger_entries WHERE transaction_id = $1`, [originalTxId]);
    return this.post(c, {
      ...meta,
      type,
      programId: orig.rows[0].program_id,
      reversesTxId: originalTxId,
      userId: orig.rows[0].user_id,
      pendingHolderId: orig.rows[0].pending_holder_id,
      entries: entries.rows.map((r) => ({ accountId: r.account_id, amount: -Number(r.amount) })),
    });
  }
}

@Global()
@Module({ providers: [LedgerService], exports: [LedgerService] })
export class LedgerModule {}
