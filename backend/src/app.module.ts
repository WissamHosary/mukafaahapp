import { Controller, Get, Module } from '@nestjs/common';
import { CryptoModule } from './platform/crypto.js';
import { Db, DbModule } from './platform/db.js';
import { AuthModule } from './modules/auth.js';
import { CashierModule } from './modules/cashier.js';
import { CustomerModule } from './modules/customer.js';
import { LedgerModule } from './modules/ledger.js';
import { OwnerModule } from './modules/owner.js';
import { AdminModule } from './modules/admin.js';
import { AdminWebModule } from './modules/admin-web.js';
import { AdminShopsModule } from './modules/admin-shops.js';
import { CatalogModule } from './modules/catalog.js';
import { EngageModule } from './modules/engage.js';
import { MediaModule } from './modules/media.js';
import { MerchantModule } from './modules/merchant.js';
import { StoreModule } from './modules/store.js';
import { RedeemModule } from './modules/redeem.js';
import { MukafaahModule } from './modules/mukafaah.js';

@Controller('health')
class HealthController {
  constructor(private readonly db: Db) {}

  @Get()
  async health() {
    await this.db.query('SELECT 1');
    return { status: 'ok', service: 'mukafaah-api', version: '0.7.0' };
  }
}

@Module({
  imports: [
    DbModule,
    CryptoModule,
    LedgerModule,
    AuthModule,
    CustomerModule,
    CatalogModule,
    EngageModule,
    MediaModule,
    OwnerModule,
    MerchantModule,
    StoreModule,
    RedeemModule,
    MukafaahModule,
    CashierModule,
    AdminModule,
    AdminShopsModule,
    AdminWebModule,
  ],
  controllers: [HealthController],
})
export class AppModule {}
