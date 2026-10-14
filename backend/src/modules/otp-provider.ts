import { Logger } from '@nestjs/common';

/**
 * Every SMS provider sits behind this interface so a Lebanese provider can be
 * chosen later without touching authentication code.
 */
export interface OtpProvider {
  readonly name: string;
  send(e164: string, code: string, locale: 'ar' | 'en'): Promise<void>;
}

export const OTP_PROVIDER = Symbol('OTP_PROVIDER');

/** Development provider: logs a masked number only. Never used in production. */
export class ConsoleOtpProvider implements OtpProvider {
  readonly name = 'console';
  private readonly log = new Logger('OTP');
  async send(e164: string, code: string): Promise<void> {
    this.log.log(`OTP for ${e164.slice(0, 5)}****${e164.slice(-2)}: ${code}`);
  }
}
