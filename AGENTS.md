# AGENTS.md — MindFlow App

> Read this file in full before making any changes to the project.

---

## 1. Project Overview

**MindFlow** — mobile app for mental wellness and personal productivity.

**Stack:** Flutter (iOS/Android) · Backend: Supabase, Python (FastAPI), and/or Go (can be mixed/hybrid) · PostgreSQL · Redis · Celery · FCM · Docker

| Module | Description | Status |
|---|---|---|
| **Quote** | Motivational quotes on morning schedule or custom time slots | ✅ Active |
| **Meditation** | Guided breathing exercises and meditation sessions | ✅ Active |
| **Flow / Pomodoro** | Focus timer with work/break cycle alerts | ✅ Active |
| **Music** | Real-time AI-generated white noise mixer | ✅ Active |
| **Video** | Curated lifestyle & mindfulness video library | ✅ Active |

> The backend is developed and run entirely via Docker (for Python/Go) or local emulator (for Supabase). Do not run services directly on the host. The backend stack can be mixed (e.g., Supabase for DB/Auth, Go for high-performance APIs, and FastAPI for async workers/processing).

---

## 2. Repository Structure

```
mindflow/
├── AGENTS.md
├── docker-compose.yml          ← Full dev stack (api, worker, beat, db, redis)
├── docker-compose.prod.yml
├── .env.example
├── frontend/                   ← Flutter app
│   └── lib/
│       ├── core/               ← Theme, router, DI, constants
│       ├── features/           ← quote/ meditation/ flow/ music/ video/
│       └── shared/             ← Shared widgets & utilities
├── backend/                    ← Python (FastAPI) and/or Go backend (if used/mixed)
│   └── (structure depends on chosen stack)
├── supabase/                   ← Supabase config and migrations (if used/mixed)
└── docs/
    ├── shared/                 ← database.md · api_conventions.md · notifications.md · docker.md · state_management.md
    ├── quote/spec.md
    ├── meditation/spec.md
    ├── flow/spec.md
    ├── music/spec.md
    └── video/spec.md
```

### Backend Structure Options

#### Python (FastAPI):
```
backend/
├── app/
│   ├── core/                   ← Config, DB, auth, middleware
│   ├── features/               ← quote/ meditation/ flow/ music/ video/
│   └── shared/                 ← Utils, base schemas
├── alembic/                    ← Database migrations
├── tests/                      ← Backend tests
└── Dockerfile
```

#### Go (Clean Architecture):
```
backend/
├── cmd/                        ← Entrypoints (main.go)
├── pkg/
│   ├── core/                   ← Config, middleware, common DB client
│   └── features/               ← quote/ meditation/ flow/ music/ video/
├── migrations/                 ← Go migration scripts (e.g., goose, migrate)
├── tests/                      ← Integration/unit tests
└── Dockerfile
```

#### Supabase:
```
supabase/
├── migrations/                 ← SQL schema, triggers, and RLS policies
└── functions/                  ← Supabase Edge Functions (optional)
```

Each feature folder (both frontend and backend) follows the same internal structure depending on the stack:
- **Backend (Python/FastAPI):** `models.py` · `schemas.py` · `repository.py` · `service.py` · `router.py`
- **Backend (Go):** `models/` · `repository/` · `service/` · `handler/`
- **Backend (Supabase):** Managed via database schema/tables, RLS policies in migrations, and optional Edge Functions
- **Flutter:** `data/` (datasources, models, repositories) · `domain/` (entities, usecases) · `presentation/` (providers, screens, widgets)

---

## 3. Agent Rules

### Before touching any code — read the relevant doc

| Changing... | Read first |
|---|---|
| Quote module | `docs/quote/spec.md` |
| Meditation module | `docs/meditation/spec.md` |
| Flow module | `docs/flow/spec.md` |
| Music module | `docs/music/spec.md` |
| Video module | `docs/video/spec.md` |
| DB / models | `docs/shared/database.md` |
| API endpoints | `docs/shared/api_conventions.md` |
| Notifications | `docs/shared/notifications.md` |
| Docker / env | `docs/shared/docker.md` |
| Flutter state | `docs/shared/state_management.md` |

### After every meaningful change — update the docs

- New/renamed/removed endpoint → update `spec.md` + `api_conventions.md`
- DB schema change → update `database.md` + relevant `spec.md`
- Docker or env change → update `docker.md`
- New dependency → note it in the module's `spec.md`

> ⚠️ Docs are the single source of truth. Never leave code contradicting docs.

### Never do

- ❌ Run backend services outside Docker (Python/Go) or local emulator (Supabase)
- ❌ Hard-code secrets or credentials anywhere
- ❌ Skip reading docs before modifying a module
- ❌ Leave docs outdated or contradicting current code
- ❌ Rename an endpoint or DB column without a migration
- ❌ Delete a DB migration already applied (Alembic or Supabase SQL/Go migrations)
- ❌ Change the Docker Compose service topology without developer approval

---

## 4. Docker & local dev servers

### Docker (for Python/Go backends)
```bash
docker compose up --build          # Start full dev stack
docker compose up -d               # Start in background
docker compose logs -f api         # Tail API logs
docker compose exec api bash       # Shell into API container
docker compose exec api alembic upgrade head   # Run migrations (FastAPI)
docker compose exec api pytest     # Run backend tests (FastAPI)
docker compose down                # Stop all services
docker compose down -v             # Stop and wipe volumes
```

**Key `.env` variables** (copy from `.env.example`):
```env
DATABASE_URL=postgresql+asyncpg://mindflow:secret@db:5432/mindflow
REDIS_URL=redis://redis:6379/0
JWT_SECRET_KEY=change_me
FCM_SERVICE_ACCOUNT_PATH=/run/secrets/fcm-key.json
DEBUG=true
```
> Inside Docker Compose, use service names as hostnames (`db`, `redis`) — not `localhost`.

### Supabase CLI (for Supabase backend)

During development, Supabase runs locally using Docker (via the Supabase CLI). In production, the application connects directly to the hosted Supabase cloud service.
- **Syncing Data (Prod to Dev)**: Use the Supabase CLI and database tools to pull/synchronize production database data down to the local development environment for testing and debugging.
- **Syncing Schema (Dev to Prod)**: Use the Supabase CLI to deploy and push local database schema updates/migrations from development to production.

```bash
supabase start                     # Start Supabase local emulator (runs via Docker)
supabase stop                      # Stop Supabase emulator
supabase db reset                  # Reset local database and run migrations
supabase db pull                   # Pull database schema/changes from remote project
supabase db push                   # Deploy local migrations to remote (production) DB
```

---

## 5. Coding Standards

**Python:** `snake_case` files/vars/functions · `PascalCase` classes · `UPPER_SNAKE_CASE` constants
**Go:** `camelCase` for private packages/functions/fields · `PascalCase` for exported types/methods · short/lowercase single-word package names
**Dart:** `snake_case.dart` files · `PascalCase` classes · `camelCase` variables/methods
**SQL/Postgres:** `snake_case` for all table, column, trigger, and index names · Singular table names
**Flutter libs:** Riverpod v2 · GoRouter · Dio (with auth + error interceptors) · `flutter_localizations` (en, vi)
**Python libs:** FastAPI (async) · SQLAlchemy 2.x async · Pydantic v2 · python-jose · Celery + Redis
**Go libs:** gin/chi/fiber (router) · sqlx or GORM · pgx (driver)

**API conventions:**
- Base URL: `/api/v1/` or Supabase REST endpoints · Auth: `Authorization: Bearer <token>` · Datetime: ISO 8601 UTC
- Success: `{ "success": true, "data": {}, "error": null, "meta": {} }`
- Error: `{ "success": false, "data": null, "error": { "code": "...", "message": "..." } }`

---

## 6. Feature Development Workflow

1. Create/update `docs/<module>/spec.md` with full specification
2. Write database migrations (Alembic for Python, Goose/Golang-migrate for Go, or Supabase SQL migrations)
3. Implement backend:
   - **Python/FastAPI:** `models` → `schemas` → `repository` → `service` → `router`
   - **Go:** `models` → `repository` → `service` → `handler`
   - **Supabase:** Tables/schemas/constraints → RLS policies → Triggers/Functions → Edge Functions (if needed)
4. Write backend tests (`tests/features/<module>/` or package `_test.go`)
5. Implement Flutter: models → datasources → repositories → usecases → providers → UI
6. Update `docs/shared/database.md` and `docs/<module>/spec.md` to reflect actual implementation
