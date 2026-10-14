import 'reflect-metadata';
import helmet from '@fastify/helmet';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { FastifyAdapter, type NestFastifyApplication } from '@nestjs/platform-fastify';
import { AppModule } from './app.module.js';
import { config } from './config.js';
import { Db } from './platform/db.js';
import { ProblemFilter } from './platform/errors.js';

async function bootstrap() {
  const app = await NestFactory.create<NestFastifyApplication>(
    AppModule,
    new FastifyAdapter({ trustProxy: config.TRUST_PROXY, bodyLimit: 5 * 1024 * 1024 }),
    { logger: ['log', 'warn', 'error'] },
  );
  await app.register(helmet as never, { contentSecurityPolicy: false });
  allowBrowserOrigins(app);
  app.useGlobalFilters(new ProblemFilter());
  app.enableShutdownHooks();

  await app.get(Db).migrate();

  await app.listen(config.PORT, '0.0.0.0');
  new Logger('Main').log(`Mukafaah API listening on :${config.PORT} (${config.NODE_ENV})`);
}

// Lets the web builds of the apps (opened in a browser for testing) call the
// API. Only origins listed in CORS_ORIGINS get CORS headers; mobile apps do
// not need this. No extra package: a single Fastify hook.
function allowBrowserOrigins(app: NestFastifyApplication) {
  const origins = new Set(
    config.CORS_ORIGINS.split(',')
      .map((o) => o.trim())
      .filter(Boolean),
  );
  if (origins.size === 0) return;
  const fastify = app.getHttpAdapter().getInstance();
  fastify.addHook('onRequest', async (req, reply) => {
    const origin = req.headers.origin;
    if (!origin || !origins.has(origin)) return;
    reply.header('Access-Control-Allow-Origin', origin);
    reply.header('Vary', 'Origin');
    if (req.method === 'OPTIONS') {
      const asked = req.headers['access-control-request-headers'];
      reply.header('Access-Control-Allow-Methods', 'GET,POST,PUT,PATCH,DELETE');
      reply.header('Access-Control-Allow-Headers', typeof asked === 'string' ? asked : 'content-type,authorization');
      reply.header('Access-Control-Max-Age', '600');
      reply.code(204).send();
      return reply;
    }
  });
  fastify.options('*', (_req, reply) => {
    reply.code(204).send();
  });
}

bootstrap().catch((e) => {
  console.error(e);
  process.exit(1);
});
