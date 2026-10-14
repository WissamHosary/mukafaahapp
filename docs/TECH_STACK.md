# Tech stack (pinned, verified 2026-10-14)

Flutter 3.47.7 / Dart 3.13 · material_ui 1.6 · flutter_riverpod 3.4 · go_router 18 · dio 5.11 · flutter_secure_storage 11.2 · shared_preferences 2.5 · qr 4.0 · skeletonizer 3.0 · mobile_scanner 7.4 · url_launcher 6.3 · package_info_plus 10.2 · very_good_analysis 11.

Node 24 LTS · NestJS 12.1.3 (Fastify 5) · @fastify/helmet 13.2 · zod 4.6 · jose 6.2 · @node-rs/argon2 2.2 · libphonenumber-js 1.13 · pg 8.23 · TypeScript 5.9.3 · PostgreSQL 18.

Full rationale, alternatives and rejected packages: "Phase 0 dependencies" tab of the architecture document.

Deliberate v0.1 simplifications (planned, not forgotten): SQL migrations via `pg` instead of Prisma; hand-written typed API client instead of generated; no Firebase/Sentry/PostHog until project keys exist; Valkey/BullMQ arrive with notifications and rollups.
