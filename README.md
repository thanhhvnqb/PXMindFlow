# MindFlow

**MindFlow** is a cross-platform, offline-first personal productivity application inspired by the useful workflows of TickTick, with an original interface and independent implementation. The goal is a clean, fast and accessible experience across **Android, iOS, Windows, macOS, Linux and Web**.

> **Project status:** Executable incremental foundation: Flutter client, Drift SQLite/WASM, Dockerized FastAPI/PostgreSQL, authentication, task/list CRUD, explicit sync conflicts, and basic implementations of the six views. This is not the complete MVP. See [implementation status](docs/implementation_status.md) for verified checks and remaining work.


## Remote server development and SSH tunnel testing

Development currently runs on a remote Linux server. Run backend containers,
Flutter commands and automated tests there. Test the UI in your workstation's
browser over an SSH tunnel; keep development ports bound to loopback.

Run on your **workstation**, replacing `user@server`, and keep the session open:

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:8000:127.0.0.1:8000 \
  -L 127.0.0.1:8080:127.0.0.1:8080 user@server
```

Run the quick-start below on the **server**. Then open
`http://localhost:8080` on your workstation. The API is available through the same
tunnel at `http://localhost:8000/health` and `http://localhost:8000/docs`.
Use `CORS_ORIGINS=["http://localhost:8080"]`; browser `localhost` reaches your
workstation's forwarded port. No server-side Chrome is needed for manual testing.
If forwarding fails because a local port is occupied, free it or change the local
ports together with CORS and the compiled `API_URL`.

See the [step-by-step tunnel runbook](docs/developer_browser_testing.md#3-run-the-app-through-an-ssh-tunnel)
for checks from the workstation, an alternate-port example and troubleshooting.
Manual tunnel testing and server-side browser automation are separate checks.

The existing Compose project is `pxmindflow`; reuse it to retain its database.
Check `docker compose ls -a` before changing project names. Startup must use
`up --build` after Dockerfile/source changes: an old image may still have
`python3` as its command and exit successfully without starting the API.
Inspect `docker compose -p pxmindflow ps -a` and logs when diagnosing startup.
Run `alembic upgrade head` after startup; `/health` alone does not check the schema.

## Current implementation quick-start

Developer runbook: [Run and test in a browser before using an emulator](docs/developer_browser_testing.md). Includes Chrome setup, SQLite/WASM smoke tests, offline/conflict checks, isolated backend tests and emulator handoff.

The source now lives in `frontend/` and `backend/`. Existing product requirements below still describe the full target scope.

```bash
test -f .env || cp .env.example .env
# Fill POSTGRES_PASSWORD with a random hexadecimal value and JWT_SECRET
# with at least 32 random characters. Do not commit .env.
docker compose -p pxmindflow up --build -d
docker compose -p pxmindflow exec api alembic upgrade head
cd frontend
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080 \
  --dart-define=API_URL=http://localhost:8000/api/v1
```

Create an account in the app (password minimum 12 characters). After signing in once, tasks and all normal domain edits are written to SQLite and remain available offline. The first sign-in requires the API. Tokens restore from platform secure storage; account databases and pending changes are retained on logout. Changing API_URL requires a new build/run. Android emulator development uses `http://10.0.2.2:8000/api/v1`; use HTTPS for release builds and Apple platforms. Configure CORS_ORIGINS to match the Web origin. Linux needs GTK and libsecret development/runtime packages; Apple signing/keychain setup needs testing on macOS.

```bash
# Client checks
cd frontend
flutter analyze
flutter test
flutter build web
# Platform storage smoke test, on a supported device:
flutter test integration_test/local_task_smoke_test.dart -d <device-id>

# Isolated PostgreSQL migration/API tests, from repository root:
scripts/test_backend.sh
```

For a real client/API integration test, follow the [isolated client/API instructions](docs/developer_browser_testing.md#7-backend-and-real-clientapi-tests). Build the `tests` image before starting the test `api` service, which has no build definition. This HTTP test uses native SQLite, not the browser runtime. Stop that test project after use; do not delete development database volumes.

Sync troubleshooting: inspect the visible pending count and attention indicator. Retry with the sync button. Resolve attention entries with Review differences, Keep mine or Keep server. A network failure preserves the outbox and retries with backoff. Check `docker compose logs api`, API_URL and CORS when connection fails. Never clear SQLite to resolve a sync problem while pending edits exist. No tombstone cleanup is currently enabled.

Platform commands: `flutter build apk`, `flutter build ios --simulator --no-codesign`, `flutter build windows`, `flutter build macos`, `flutter build linux`, `flutter build web`, each on a host with its required toolchain. The CI matrix configures these targets; configuration is not evidence of a successful CI run.

## Features

| Module | Planned capabilities |
| --- | --- |
| **Tasks** | Inbox, projects/lists, subtasks, notes, tags, priority, due dates, reminders, recurring tasks, Today/Upcoming/Completed, sorting and filtering |
| **Eisenhower Matrix** | Four urgency/importance quadrants; drag and drop; edits update the same underlying tasks |
| **Habit Tracker** | Habit schedules and goals, daily check-ins, streaks, progress and history |
| **Calendar** | Day/week/month views of scheduled tasks and recurring occurrences |
| **Pomodoro / Focus** | Configurable focus/break intervals, pause/resume, session history and statistics |
| **Search** | Local-first full-text task/list/note/habit search and filters |

These six modules make up the MVP. Collaboration, an AI assistant, subscriptions, streaming media, motivational quotes and meditation content are **not** in the initial scope.

## Design principles

- **One Flutter codebase, six targets:** adaptive navigation and layouts for touch, mouse and keyboard.
- **Offline-first:** normal edits save to local SQLite immediately and work without internet access.
- **Reliable multi-device sync:** queue operations locally, then synchronize via a secured API when connectivity returns.
- **No silent data loss:** conflicts are detected using server record versions, with explicit resolution when a safe automatic merge is impossible.
- **Original modern UI:** Material 3 foundations, custom design tokens, light/dark themes, responsive sidebar/rail/bottom navigation, sensible shortcuts and accessible controls.
- **Localization:** English and Vietnamese.

## Architecture

```text
Android / iOS / Windows / macOS / Linux / Web
                     |
               Flutter / Dart
    Riverpod · GoRouter · Dio · Drift
                     |
           Local SQLite database
        + transactional sync outbox
                     |
          HTTPS sync API (push/pull)
                     |
          FastAPI + SQLAlchemy
                     |
                PostgreSQL
       + versions + durable change log
```

**Client:** Flutter stable, Riverpod, GoRouter, Dio and Drift. Native platforms use SQLite; Web uses a supported SQLite/WASM setup with browser storage. Browser storage may be evicted or restricted (e.g. private browsing), so Web offline durability cannot be guaranteed in all environments.

**Server:** Python FastAPI, SQLAlchemy 2.x async, Pydantic, Alembic and PostgreSQL. Docker Compose runs the development API and database. The Flutter client never connects to PostgreSQL directly. Supabase, Go, Redis, Celery and Firebase are **not required** for the MVP.

**Scale:** The API is designed to be stateless and user-scoped, allowing horizontal scaling as usage grows. Serving thousands of users still requires load testing, connection-pool sizing, monitoring and suitable infrastructure; it is not guaranteed by the framework choice alone.

### Sync and conflict handling

1. Every user mutation is committed to **SQLite and a local outbox in one transaction**. UI updates immediately, including offline.
2. The sync worker sends pending operations with stable UUIDs, device IDs, operation IDs and a `base_version` to `/api/v1/sync/push`.
3. The server enforces user ownership, idempotency and optimistic concurrency. Accepted changes increment the authoritative record version and append to a durable change log in the same database transaction.
4. The client pulls authorized changes from `/api/v1/sync/pull` using a resumable cursor, applying each page atomically to local storage.
5. Conflicting edits are **never silently overwritten**. Only provably independent changes are eligible for automatic merge; otherwise the app offers **Keep mine / Keep server / Review differences**.
6. Deletes use tombstones; retries, lost acknowledgements, long offline periods, login/logout and resynchronization must be tested.

The sync model must not use client clocks or unconditional *last-write-wins* to resolve conflicting edits. Refer to `docs/sync_protocol.md` and [AGENTS.md](AGENTS.md) once implementation documentation is created.

## Proposed repository layout

```text
mindflow/
├── README.md
├── AGENTS.md                       # Required agent/developer conventions
├── CODEX_PROMPT.md                 # Optional implementation instruction
├── .env.example                    # Safe development configuration template
├── docker-compose.yml             # FastAPI and PostgreSQL
├── docker-compose.prod.yml        # Optional, when production deployment exists
├── frontend/
│   ├── lib/
│   │   ├── app/                   # App bootstrap, themes, routing, i18n
│   │   ├── core/                  # SQLite, sync, auth, networking, utilities
│   │   ├── features/
│   │   │   ├── tasks/
│   │   │   ├── matrix/
│   │   │   ├── habits/
│   │   │   ├── calendar/
│   │   │   ├── pomodoro/
│   │   │   └── search/
│   │   └── shared/
│   ├── test/
│   ├── integration_test/
│   └── web/                       # SQLite WASM/worker assets
├── backend/
│   ├── app/                       # API, auth, models, services, sync engine
│   ├── alembic/                   # PostgreSQL schema migrations
│   ├── tests/
│   └── Dockerfile
└── docs/
    ├── architecture.md
    ├── database.md
    ├── sync_protocol.md
    ├── api.md
    ├── ui_design.md
    ├── testing.md
    └── features/                 # Per-module specifications
```

This is the **target layout**, not a claim that all files already exist. The implementation agent should inspect existing files before creating or restructuring anything.

## Local development

The scaffold exists. Use the [browser-first developer runbook](docs/developer_browser_testing.md) for the complete current procedure. Commands below are a short reference.

### Requirements

- Flutter 3.47.7 stable (includes Dart 3.13.5), with the relevant platform toolchains installed (`flutter doctor`).
- Docker Engine / Docker Desktop and Docker Compose for the backend.
- A browser for the Web target; compatible desktop/mobile SDKs as applicable.
- macOS with Xcode to build iOS and macOS targets; Windows and Linux builds require their respective toolchains.

### Start the backend

From the repository root, create `.env` only if it does not already exist:

```bash
test -f .env || cp .env.example .env
# Edit .env with non-production development secrets.
docker compose -p pxmindflow up --build -d
docker compose -p pxmindflow exec api alembic upgrade head
docker compose -p pxmindflow logs -f api
# Separate test database, from another terminal:
scripts/test_backend.sh
```

Do not run the FastAPI backend directly on the host during local development. **Do not** run `docker compose down -v` without explicitly accepting database volume loss.

### Start Flutter

```bash
cd frontend
flutter pub get
flutter doctor
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080 \
  --dart-define=API_URL=http://localhost:8000/api/v1
```

Choose another device with `flutter devices`, then `flutter run -d <device-id>` for Android, iOS, Windows, macOS or Linux where supported. Configure the API base URL for each target; `localhost` from an Android emulator or physical device is not necessarily the Docker host. Web development may additionally require appropriate API CORS configuration and the SQLite WASM/worker assets.

### Checks

```bash
cd frontend
flutter analyze
flutter test
```

Run backend integration tests against a dedicated test database and verify migrations. Run platform-specific builds/smoke tests only where host tooling is available, and report any platform not yet verified.

## Implementation roadmap

1. Flutter app shell and adaptive design system; Docker/FastAPI/PostgreSQL; local Drift SQLite; authentication and account data isolation.
2. Working Tasks feature and a robust sync engine, including offline/outbox flows and two-device conflict tests.
3. Eisenhower Matrix and Calendar using canonical task data, then recurrence/reminders.
4. Habit Tracker and Pomodoro with persistent, synchronized history.
5. Offline Search, EN/VI localization, accessibility, cross-platform polish and packaging.

Each phase should produce working functionality and automated tests, not just design mockups. The sync test suite must cover simultaneous edits, edit/delete races, duplicate requests, retries after lost acknowledgements, crash recovery and stale devices.

## For coding agents

**Read [AGENTS.md](AGENTS.md) in full before any code changes.** It defines the canonical architecture, sync invariants, coding conventions, security boundaries, documentation obligations and test expectations. Keep implementation and docs consistent. An optional `CODEX_PROMPT.md` file may provide phased Codex instructions; it is not currently included in this repository.

## License

The previous README advertised an MIT license, but distribution rights should be confirmed against an actual `LICENSE` file before publishing a license badge or making license claims. MindFlow must use original code, naming, icons and UI assets, not TickTick's proprietary assets or pixel-identical designs.
