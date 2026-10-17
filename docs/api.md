# API

Health: GET /health. Auth: POST /api/v1/auth/register and login with email/password (12–128 characters); refresh with refresh_token rotates once; logout revokes refresh token. Access JWT expires in 15 minutes, refresh in 30 days. Configure a random JWT_SECRET of at least 32 characters. Passwords use Argon2. CORS is an explicit environment allowlist.

Sync push/pull require Bearer access token. Push results are applied/conflict/validation_failure; duplicate=true denotes replay. Pull cursor >=0, limit 1–500. FastAPI /docs exposes generated schema. Initial errors use FastAPI detail strings; uniform structured codes and device revocation are not yet production complete. Auth registration/login/refresh share a PostgreSQL-backed limit of 60 requests per source IP per minute, with Retry-After on 429. Tune proxy trust and add account-based abuse controls before public deployment.

Task sync payloads accept optional `due_at` (ISO 8601 UTC timestamp, e.g. `2026-10-17T07:00:00.000Z`) alongside `due_date`. Naive or non-UTC timestamps are rejected. Null removes the time; date-only tasks omit it or use null. Deploy the updated API before a client that sends this field; older APIs reject unknown payload fields. Date/time changes use the existing version checks, idempotency and conflict handling.
