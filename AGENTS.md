# AGENTS.md — MindFlow App

> Read this file in full before making any changes to the project.

---

## 1. Project Overview

**MindFlow** — mobile app for mental wellness and personal productivity.

**Stack:** Flutter (iOS/Android) · FastAPI (Python) · PostgreSQL · Redis · Celery · FCM · Docker

| Module | Description | Status |
|---|---|---|
| **Quote** | Motivational quotes on morning schedule or custom time slots | ✅ Active |
| **Meditation** | Guided breathing exercises and meditation sessions | ✅ Active |
| **Flow / Pomodoro** | Focus timer with work/break cycle alerts | ✅ Active |
| **Music** | Real-time AI-generated white noise mixer | ✅ Active |
| **Video** | Curated lifestyle & mindfulness video library | ✅ Active |

> The backend is developed and run entirely via Docker. Do not run backend services directly on the host.

---

## 2. Repository Structure

```
mindflow/
├── CLAUDE.md
├── docker-compose.yml          ← Full dev stack (api, worker, beat, db, redis)
├── docker-compose.prod.yml
├── .env.example
├── frontend/                   ← Flutter app
│   └── lib/
│       ├── core/               ← Theme, router, DI, constants
│       ├── features/           ← quote/ meditation/ flow/ music/ video/
│       └── shared/             ← Shared widgets & utilities
├── backend/                    ← FastAPI app
│   ├── app/
│   │   ├── core/               ← Config, DB, auth, middleware
│   │   ├── features/           ← quote/ meditation/ flow/ music/ video/
│   │   └── shared/             ← Utils, base schemas
│   ├── alembic/
│   ├── tests/
│   └── Dockerfile
└── docs/
    ├── shared/                 ← database.md · api_conventions.md · notifications.md · docker.md · state_management.md
    ├── quote/spec.md
    ├── meditation/spec.md
    ├── flow/spec.md
    ├── music/spec.md
    └── video/spec.md
```

Each feature folder (both frontend and backend) follows the same internal structure:
- **Backend:** `router.py` · `service.py` · `repository.py` · `models.py` · `schemas.py`
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

- ❌ Run backend services outside Docker
- ❌ Hard-code secrets or credentials anywhere
- ❌ Skip reading docs before modifying a module
- ❌ Leave docs outdated or contradicting current code
- ❌ Rename an endpoint or DB column without a migration
- ❌ Delete an Alembic migration already applied
- ❌ Change the Docker Compose service topology without developer approval

---

## 4. Docker

```bash
docker compose up --build          # Start full dev stack
docker compose up -d               # Start in background
docker compose logs -f api         # Tail API logs
docker compose exec api bash       # Shell into API container
docker compose exec api alembic upgrade head   # Run migrations
docker compose exec api pytest     # Run backend tests
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

---

## 5. Coding Standards

**Python:** `snake_case` files/vars/functions · `PascalCase` classes · `UPPER_SNAKE_CASE` constants
**Dart:** `snake_case.dart` files · `PascalCase` classes · `camelCase` variables/methods
**Flutter libs:** Riverpod v2 · GoRouter · Dio (with auth + error interceptors) · `flutter_localizations` (en, vi)
**Python libs:** FastAPI (async) · SQLAlchemy 2.x async · Pydantic v2 · python-jose · Celery + Redis

**API conventions:**
- Base URL: `/api/v1/` · Auth: `Authorization: Bearer <token>` · Datetime: ISO 8601 UTC
- Success: `{ "success": true, "data": {}, "error": null, "meta": {} }`
- Error: `{ "success": false, "data": null, "error": { "code": "...", "message": "..." } }`

---

## 6. Feature Development Workflow

1. Create/update `docs/<module>/spec.md` with full specification
2. Write Alembic migration if DB schema changes
3. Implement backend: `models` → `schemas` → `repository` → `service` → `router`
4. Write backend tests (`tests/features/<module>/`)
5. Implement Flutter: models → datasources → repositories → usecases → providers → UI
6. Update `docs/shared/database.md` and `docs/<module>/spec.md` to reflect actual implementation
