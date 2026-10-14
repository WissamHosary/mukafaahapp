import { Controller, Get, Module, Param, Res } from '@nestjs/common';
import { readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { Errors } from '../platform/errors.js';

const DIR = join(dirname(fileURLToPath(import.meta.url)), '..', '..', 'admin');
const FILES: Record<string, string> = {
  'index.html': 'text/html; charset=utf-8',
  'app.js': 'text/javascript; charset=utf-8',
  'styles.css': 'text/css; charset=utf-8',
  'logo.png': 'image/png',
};

/** Serves the Mukafaah Manager web dashboard at /admin (static files, no build step). */
@Controller('admin')
export class AdminWebController {
  private async send(reply: any, name: string) {
    const type = FILES[name];
    if (!type) throw Errors.notFound('Page');
    const body = await readFile(join(DIR, name));
    reply
      .header('content-type', type)
      .header('cache-control', 'no-cache')
      .header('x-frame-options', 'DENY')
      .header(
        'content-security-policy',
        "default-src 'self'; img-src 'self' data: blob:; style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; script-src 'self'; connect-src 'self'; frame-ancestors 'none'",
      )
      .send(body);
  }

  @Get()
  index(@Res() reply: any) {
    return this.send(reply, 'index.html');
  }

  @Get(':file')
  file(@Param('file') file: string, @Res() reply: any) {
    return this.send(reply, file);
  }
}

/** Opening the server address on its own (http://localhost:3000) goes to the Manager. */
@Controller()
export class RootRedirectController {
  @Get()
  root(@Res() reply: any) {
    reply.redirect('/admin', 302);
  }
}

@Module({ controllers: [AdminWebController, RootRedirectController] })
export class AdminWebModule {}
