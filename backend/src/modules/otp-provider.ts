import { Logger } from '@nestjs/common';
import { config } from '../config.js';
import { AppError } from '../platform/errors.js';

/**
 * Every code provider sits behind this interface so the channel can change
 * without touching authentication code.
 */
export interface OtpProvider {
  readonly name: string;
  /** Shown to the customer: where to look for the code. */
  readonly channel: 'WHATSAPP' | 'SMS';
  send(e164: string, code: string, locale: 'ar' | 'en'): Promise<void>;
}

export const OTP_PROVIDER = Symbol('OTP_PROVIDER');

/** Development provider: logs a masked number only. Never used in production. */
export class ConsoleOtpProvider implements OtpProvider {
  readonly name = 'console';
  readonly channel = 'WHATSAPP' as const;
  private readonly log = new Logger('OTP');
  async send(e164: string, code: string): Promise<void> {
    this.log.log(`OTP for ${e164.slice(0, 5)}****${e164.slice(-2)}: ${code}`);
  }
}

/**
 * Sends the code on WhatsApp with the WhatsApp Business Cloud API, using an
 * approved Authentication template (body "{{1}} is your verification code"
 * plus the copy-code button). The template name is WHATSAPP_OTP_TEMPLATE, with
 * an Arabic and an English version.
 */
export class WhatsAppOtpProvider implements OtpProvider {
  readonly name = 'whatsapp';
  readonly channel = 'WHATSAPP' as const;
  private readonly log = new Logger('OTP');

  async send(e164: string, code: string, locale: 'ar' | 'en'): Promise<void> {
    const url = `https://graph.facebook.com/${config.WHATSAPP_API_VERSION}/${config.WHATSAPP_PHONE_NUMBER_ID}/messages`;
    const body = {
      messaging_product: 'whatsapp',
      to: e164.replace(/^\+/, ''),
      type: 'template',
      template: {
        name: config.WHATSAPP_OTP_TEMPLATE,
        language: { code: locale === 'ar' ? 'ar' : 'en' },
        components: [
          { type: 'body', parameters: [{ type: 'text', text: code }] },
          { type: 'button', sub_type: 'url', index: '0', parameters: [{ type: 'text', text: code }] },
        ],
      },
    };
    const res = await fetch(url, {
      method: 'POST',
      headers: { authorization: `Bearer ${config.WHATSAPP_TOKEN}`, 'content-type': 'application/json' },
      body: JSON.stringify(body),
      signal: AbortSignal.timeout(10_000),
    }).catch(() => null);
    if (!res || !res.ok) {
      const detail = res ? await res.text().catch(() => '') : 'no response';
      this.log.error(`WhatsApp send failed (${res?.status ?? '-'}): ${detail.slice(0, 300)}`);
      throw new AppError(502, 'OTP_SEND_FAILED', 'Could not send the code on WhatsApp. Try again.');
    }
  }
}

export function otpProviderFactory(): OtpProvider {
  return config.OTP_PROVIDER === 'whatsapp' ? new WhatsAppOtpProvider() : new ConsoleOtpProvider();
}
