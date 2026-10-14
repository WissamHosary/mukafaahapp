# Deployment

**Now (v0.1):** local Docker stack for testing; APKs signed with the debug key; dev builds allow http on the LAN.

**Before any public release (planned, in order):**
1. Staging on AWS (me-central-1 or me-south-1): ECS Fargate API, RDS PostgreSQL 18 Multi-AZ, ElastiCache Valkey, S3 + CloudFront, WAF, Secrets Manager/KMS — defined in OpenTofu under `infra/` (to be written; nothing deployed yet).
2. HTTPS only; remove cleartext; real SMS provider; `OTP_DEV_ECHO=false`.
3. Release signing keys (Play App Signing, Apple certificates), store listings, privacy policy, account deletion flow.
4. iOS builds need macOS (a Mac or a macOS CI runner).
5. External penetration test before launch.
