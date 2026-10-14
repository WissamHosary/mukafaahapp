import {
  CanActivate,
  createParamDecorator,
  ExecutionContext,
  Injectable,
  SetMetadata,
  UseGuards,
  applyDecorators,
} from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { CryptoService } from './crypto.js';
import { Db } from './db.js';
import { AppError, Errors } from './errors.js';

export interface UserAuth {
  kind: 'user';
  userId: string;
  sessionId: string;
}
export interface StaffAuth {
  kind: 'staff';
  staffId: string;
  businessId: string;
  branchId: string;
  deviceId: string;
}
export interface OwnerAuth {
  kind: 'owner';
  userId: string;
  businessId: string;
}
export type AdminRole = 'OWNER' | 'ADMIN' | 'EDITOR' | 'SHOP';
export interface AdminAuth {
  kind: 'admin';
  userId: string;
  role: AdminRole;
  /** Shops a SHOP account may manage (empty for the other roles, who see every shop). */
  shopIds: string[];
}
export type AuthContext = UserAuth | StaffAuth | OwnerAuth | AdminAuth;

const KIND = 'auth:kind';
type Kind = 'user' | 'owner' | 'staff' | 'admin';
const ADMIN_SCOPE = 'auth:adminScope';

/**
 * Which Mukafaah Manager roles may call a route.
 * - FULL: OWNER and ADMIN only (accounts, tiers, Mukafaah Points economics).
 * - CONTENT: OWNER, ADMIN and EDITOR (the default when a route declares nothing).
 * - SHOP: every role; SHOP accounts are then limited to their own shops by the
 *   handler (see assertShopScope / scopedShopId).
 */
export type AdminScopeLevel = 'FULL' | 'CONTENT' | 'SHOP';
export const AdminScope = (level: AdminScopeLevel) => SetMetadata(ADMIN_SCOPE, level);

export const forbiddenScope = () => new AppError(403, 'FORBIDDEN_SCOPE', 'Your Manager account cannot do this');

/** Central role check for Manager routes (also used by handlers for finer rules). */
export function allowAdmin(role: AdminRole, level: AdminScopeLevel): boolean {
  if (level === 'SHOP') return true;
  if (level === 'CONTENT') return role === 'OWNER' || role === 'ADMIN' || role === 'EDITOR';
  return role === 'OWNER' || role === 'ADMIN';
}

/** A SHOP account may only touch the shops it was given. */
export function assertShopScope(a: AdminAuth, businessId: string) {
  if (a.role === 'SHOP' && !a.shopIds.includes(businessId)) throw forbiddenScope();
}

function bearer(req: { headers: Record<string, string | string[] | undefined> }) {
  const h = req.headers['authorization'];
  const v = Array.isArray(h) ? h[0] : h;
  if (!v || !v.startsWith('Bearer ')) throw Errors.unauthorized();
  return v.slice(7);
}

/**
 * One guard for all three audiences. The route declares which kind of caller it
 * accepts; a cashier token can never satisfy an owner or customer route.
 */
@Injectable()
export class AuthGuard implements CanActivate {
  constructor(
    private readonly reflector: Reflector,
    private readonly crypto: CryptoService,
    private readonly db: Db,
  ) {}

  async canActivate(ctx: ExecutionContext): Promise<boolean> {
    const kind = this.reflector.get<Kind>(KIND, ctx.getHandler()) ?? this.reflector.get<Kind>(KIND, ctx.getClass());
    if (!kind) return true;
    const req = ctx.switchToHttp().getRequest();
    const token = bearer(req);

    if (kind === 'staff') {
      const p = await this.crypto.verify('staff', token);
      const row = await this.db.one(
        `SELECT s.active AS staff_active, d.status AS device_status
           FROM staff s JOIN devices d ON d.id = $2
          WHERE s.id = $1 AND d.business_id = s.business_id`,
        [p.sub, p['dev']],
      );
      if (!row || !row.staff_active || row.device_status !== 'ACTIVE') throw Errors.unauthorized();
      req.auth = {
        kind: 'staff',
        staffId: String(p.sub),
        businessId: String(p['bid']),
        branchId: String(p['brid']),
        deviceId: String(p['dev']),
      } satisfies StaffAuth;
      return true;
    }

    const p = await this.crypto.verify('user', token);
    const session = await this.db.one(
      `SELECT s.revoked_at, u.status FROM sessions s JOIN users u ON u.id = s.user_id WHERE s.id = $1 AND s.user_id = $2`,
      [p['sid'], p.sub],
    );
    if (!session || session.revoked_at || session.status !== 'ACTIVE') throw Errors.unauthorized();

    if (kind === 'user') {
      req.auth = { kind: 'user', userId: String(p.sub), sessionId: String(p['sid']) } satisfies UserAuth;
      return true;
    }
    if (kind === 'admin') {
      const adm = await this.db.one(`SELECT role FROM admins WHERE user_id = $1 AND active`, [p.sub]);
      if (!adm) throw new AppError(403, 'NOT_ADMIN', 'Mukafaah Manager access only');
      const role = adm.role as AdminRole;
      const level =
        this.reflector.get<AdminScopeLevel>(ADMIN_SCOPE, ctx.getHandler()) ??
        this.reflector.get<AdminScopeLevel>(ADMIN_SCOPE, ctx.getClass()) ??
        'CONTENT';
      if (!allowAdmin(role, level)) throw forbiddenScope();
      let shopIds: string[] = [];
      if (role === 'SHOP') {
        const r = await this.db.query(
          `SELECT s.business_id FROM admin_shops s JOIN businesses b ON b.id = s.business_id WHERE s.user_id = $1 ORDER BY b.name`,
          [p.sub],
        );
        shopIds = r.rows.map((x) => String(x.business_id));
      }
      req.auth = { kind: 'admin', userId: String(p.sub), role, shopIds } satisfies AdminAuth;
      return true;
    }
    // owner: the signed-in user must own a business
    const biz = await this.db.one(`SELECT id FROM businesses WHERE owner_user_id = $1 AND status = 'ACTIVE'`, [p.sub]);
    if (!biz) throw Errors.conflict('NO_BUSINESS', 'This account has no business yet');
    req.auth = { kind: 'owner', userId: String(p.sub), businessId: biz.id } satisfies OwnerAuth;
    return true;
  }
}

export const RequireUser = () => applyDecorators(SetMetadata(KIND, 'user'), UseGuards(AuthGuard));
export const RequireOwner = () => applyDecorators(SetMetadata(KIND, 'owner'), UseGuards(AuthGuard));
export const RequireAdmin = () => applyDecorators(SetMetadata(KIND, 'admin'), UseGuards(AuthGuard));
export const RequireStaff = () => applyDecorators(SetMetadata(KIND, 'staff'), UseGuards(AuthGuard));

export const Auth = createParamDecorator((_: unknown, ctx: ExecutionContext) => ctx.switchToHttp().getRequest().auth);

export const ClientIp = createParamDecorator((_: unknown, ctx: ExecutionContext): string => {
  const req = ctx.switchToHttp().getRequest();
  return String(req.ip ?? '');
});

/** Idempotency-Key header when the client sent one (null otherwise). */
export const OptionalIdemKey = createParamDecorator((_: unknown, ctx: ExecutionContext): string | null => {
  const req = ctx.switchToHttp().getRequest();
  const v = req.headers['idempotency-key'];
  const key = Array.isArray(v) ? v[0] : v;
  if (!key || typeof key !== 'string') return null;
  if (key.length < 8 || key.length > 100) throw Errors.validation({ 'Idempotency-Key': ['INVALID'] });
  return key;
});

export const IdemKey = createParamDecorator((_: unknown, ctx: ExecutionContext): string => {
  const req = ctx.switchToHttp().getRequest();
  const v = req.headers['idempotency-key'];
  const key = Array.isArray(v) ? v[0] : v;
  if (!key || typeof key !== 'string' || key.length < 8 || key.length > 100) {
    throw Errors.validation({ 'Idempotency-Key': ['REQUIRED'] });
  }
  return key;
});
