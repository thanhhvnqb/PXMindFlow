# AGENTS.md — MindFlow (Offline-First Productivity)

> Read this entire file before making changes. This document is the standing contract for coding agents. If the repository differs, inspect it first and reconcile docs with actual code; do not delete user work.

## 1. Product and scope

**MindFlow** is a polished, fast, privacy-conscious, offline-first personal productivity app inspired by the usability of TickTick, but with its own identity, original visuals, and independently implemented code. Do not copy TickTick trademarks, icons, proprietary assets, text, or pixel-for-pixel layouts.

**Targets (one Flutter codebase):** Android, iOS, Windows, macOS, Linux, and Web. All six must be considered in architecture, routing, keyboard/mouse/touch input, persistence, and CI; distinguish actual verified builds from targets that cannot be built on the current host.

**Core MVP modules (all required):**

1. **Tasks:** Inbox, lists/projects, CRUD, subtasks, descriptions/notes, tags, priority, due date/time, reminders, recurrence, completion, Today/Upcoming/All/Completed views; filtering, sorting, drag-and-drop where applicable, and bulk actions.

2. **Eisenhower Matrix:** four urgent/important quadrants with drag/drop and quick editing; single canonical task record shared with task views.

3. **Habit Tracker:** habits, schedules/targets, daily check-ins, streaks, progress/history; correctly handle timezone and local calendar days.

4. **Calendar:** day/week/month views, tasks on dates, navigate/edit/create tasks, recurring task instances; avoid creating duplicate task data.

5. **Pomodoro / Focus:** configurable focus, short/long breaks, start/pause/resume/skip, persisted sessions and daily totals; timer based on monotonic/elapsed timestamps when available rather than assuming periodic callbacks fire on time.

6. **Search:** fast offline full-text search over authorized local tasks/lists/notes/habits, with filters and navigation to results.

**Out of scope for MVP:** collaboration, AI assistant, social feeds, media streaming, paid subscriptions, remote push infrastructure, and complex integrations. Do not recreate the old Quote/Meditation/Music/Video modules.

**Design requirements:** modern, tasteful, original UI; Material 3 foundations with custom tokens; light/dark themes, responsive layout (compact navigation on mobile; navigation rail/sidebar and multi-pane on large screens), accessible contrast, keyboard shortcuts, focus states, screen-reader semantics, animations without excessive motion, and `en`/`vi` localization. Avoid placeholder-only screens; major flows must work end-to-end.

**Default language:** English (`en`) is the default application language on all platforms, including first launch when no language preference has been saved. Vietnamese (`vi`) remains an optional localization selected by the user; do not automatically default to Vietnamese or another language based on the device/browser locale. Developer documentation and agent responses also default to English unless the user explicitly requests another language.

**Development language:** Use English by default for code identifiers, code comments, documentation, setup/testing instructions, logs and diagnostic messages, test descriptions, commit messages, pull requests, issue discussions, and agent/developer communication. Use another language only when explicitly requested or when writing localized product content such as Vietnamese translations.

## 2. Approved architecture and stack

- **Frontend:** Flutter stable, Dart; Riverpod (version compatible with the installed SDK), GoRouter, Dio, `flutter_localizations` + intl, `drift`/`drift_flutter` for reactive typed SQLite, secure credential storage where supported. Use package versions that are current and mutually compatible; pin them in the lockfile.

- **Local-first persistence:** SQLite is the sole client-side source of truth for domain reads and user writes. Use Drift on native and its SQLite/WASM backend on Web with packaged `sqlite3.wasm` and worker assets. Browser storage durability/availability varies (private mode, eviction, unsupported APIs); detect and communicate degraded persistence; do not claim Web offline persistence is guaranteed.

- **Backend:** **FastAPI (Python)** + Pydantic + SQLAlchemy async + Alembic + PostgreSQL, with REST endpoints for auth and synchronization. Keep backend stateless for horizontal scaling to thousands of users; add queues/caches only when a demonstrated requirement arises.

- **Deployment/dev:** Docker Compose for API and PostgreSQL; Dockerfile and `.env.example`. No Supabase requirement, no Redis/Celery by default. Backend processes run in containers during local development.

- **Architecture:** feature-first Flutter `data/`, `domain/`, `presentation/`; repositories abstract persistence/sync; no widgets making SQL or REST calls. Backend split into routers, services, persistence models, schema, and sync service.

- **Security:** user accounts and per-user tenant isolation, secure password hashing, short-lived access tokens and refresh-token rotation/revocation (or well-reviewed equivalent); HTTPS in deployment; never expose PostgreSQL credentials to Flutter; every API query and mutation must be scoped to authenticated user.

## 3. Repository layout

```text
mindflow/
├── AGENTS.md
├── README.md
├── .env.example
├── docker-compose.yml
├── docker-compose.prod.yml      # when deployment is implemented
├── frontend/
│  ├── lib/
│  │  ├── app/           # bootstrap, router, localization, themes
│  │  ├── core/           # db, sync, network, auth, time, widgets
│  │  ├── features/
│  │  │  ├── tasks/
│  │  │  ├── matrix/
│  │  │  ├── habits/
│  │  │  ├── calendar/
│  │  │  ├── pomodoro/
│  │  │  └── search/
│  │  └── shared/
│  ├── test/
│  ├── integration_test/
│  └── web/              # include SQLite WASM/worker assets
├── backend/
│  ├── app/
│  │  ├── core/           # config, auth, DB, security
│  │  ├── models/
│  │  ├── schemas/
│  │  ├── routers/
│  │  ├── services/         # includes sync engine
│  │  └── repositories/
│  ├── alembic/
│  ├── tests/
│  └── Dockerfile
└── docs/
  ├── architecture.md
  ├── database.md
  ├── sync_protocol.md
  ├── api.md
  ├── ui_design.md
  ├── testing.md
  └── features/           # tasks/matrix/habits/calendar/pomodoro/search
```

Adapt to an existing structure without needless destructive renames. Write missing docs before or alongside implementation.

## 4. Data model and invariants

- Use UUIDs generated **on the client** for syncable records, stable across devices. All owned records carry `user_id` (server authoritative), `id`, `created_at`, `updated_at`, `deleted_at` (nullable tombstone), and monotonically increasing **server `version`** per record. Client also tracks `base_version` and local dirty/pending state; don't trust a client-provided `user_id`.

- Minimum entities: `user`, `device`, `task_list`, `task`, `subtask` (or task parent relation), `tag`, `task_tag`, `habit`, `habit_checkin`, `focus_session`, plus `sync_change` server log and `sync_outbox` / `sync_state` client tables. Add `task_reminder` and recurrence specification as needed.

- Eisenhower quadrant is derived from canonical task `is_urgent` and `is_important` booleans (independent of priority unless explicitly mapped by the user).

- The calendar is a view onto tasks/due dates and generated recurring occurrences; never replicate tasks into a separate calendar source of truth.

- Persist timestamps as UTC instants; separately store IANA timezone and local date when semantics depend on a person's day (habits, due date without time, recurrence). Define daylight-saving and cross-timezone behavior in docs.

- Store recurrence as explicit rule metadata plus exception/occurrence completion data (rather than eagerly cloning infinite future tasks). Record completion per occurrence with a stable occurrence key.

- Make uniqueness, indexes, FK constraints and cascading behavior explicit; server enforces ownership on all joins and related records. Use FTS5 on compatible native SQLite; verify fallback/compatibility on web.

- No destructive overwrites or unsafe purges while unsent mutations exist. Tombstone retention and device resync recovery are specified in the sync protocol.

## 5. Offline-first sync: mandatory correctness protocol

**All normal user writes are local first.** Save the domain mutation AND corresponding outbox entry atomically in a single SQLite transaction; update UI immediately. A sync worker is the only layer that exchanges mutations with the server. Sync on app startup, reconnect, foreground/resume, and manually; use debouncing, batching and exponential backoff + jitter. Do not assume background jobs run reliably on every OS or on Web.

### Protocol

1. **Identity and ordering:** each mutation has unique `operation_id` (UUID), `device_id`, target `(entity_type, entity_id)`, operation type (`create/update/delete`), `base_version`, payload, and client-local order. Use an outbox and per-account sync cursor. Preserve dependency order (e.g. list before child task); sequence multiple pending edits to the same entity or coalesce safely, never drop an unacknowledged operation.

2. **Push:** authenticate `/api/v1/sync/push`. Server processes mutations transactionally with a unique `(user_id, operation_id)` idempotency constraint and returns per-operation `applied`, `duplicate`, `conflict` or validation failure, along with server versions and canonical records. Retrying the same operation must not apply it twice.

3. **Concurrency:** compare `base_version` with the current authoritative `version` in PostgreSQL using transactional locking or conditional updates. The server, not client timestamps, determines version ordering. If versions match, apply mutation, increment record version and append an ordered durable change-log item **in the same database transaction**. If they do not match, return conflict, never silently use last-write-wins for shared editable fields.

4. **Pull:** `/api/v1/sync/pull?cursor=...` returns authorized changes in **monotonic server sequence** order, paginated, including tombstones, plus next cursor. Advance the client cursor only after all changes in that page are committed in the same SQLite transaction. Distinguish empty page from missing/expired cursor; support full rebootstrap preserving outbox.

5. **Push/pull race:** serialize local sync for an account (and avoid overlapping cycles). Do not apply remote snapshots over entities with pending local edits. After push acknowledgement, reconcile canonical record with local pending operations; pull and rebase/retry as needed. Server change-log must be durable and yield a consistent cut for pagination; account for concurrent server commits when assigning publish order.

6. **Conflicts:** implement an explicit conflict queue with local, remote, and common-base versions if available. Safe auto-merges only when fields/operations are provably independent (e.g. disjoint fields with reliable base snapshots; distinct habit check-ins). Otherwise show user a conflict resolution UI: **Keep mine / Keep server / Review differences**. Resolving emits a new mutation against the latest server version. Never discard local changes without explicit action or verified safe merge.

7. **Deletes:** use tombstones, not immediate hard deletes. Concurrent edit-versus-delete is a visible conflict; no silent resurrection. Repeated delete operations are idempotent. Cleanup requires documented retention policy and a safe full-resync path for inactive devices.

8. **Multi-device/security:** authenticate every request, enforce ownership on each mutation and pull entry; forbid editing another user's records even via guessed UUIDs. Handle token expiry, logout/account switching, and per-account local DB isolation. On logout, do not silently destroy an unsynced outbox; display options to sync/retain/discard with confirmation.

9. **Recovery:** network timeouts after server commit, retry duplicates, app crashes between steps, bad clocks, partial batches, migrations, browser data eviction, and revoked devices must have documented behavior and integration tests.

**Required test matrix:** offline create/edit/delete then reconnect; two devices edit same field; two devices edit different fields; edit/delete race; repeat requests and lost ACK; crash after push before local ACK; out-of-order/overlapping pull pages; concurrent push/pull; offline recurring task completion; habit check-in duplicates; long-disconnected device after tombstone cleanup; isolation between two users. No sync feature is complete without passing automated tests for these cases.

## 6. UX and functionality acceptance criteria

- Launch directly into a useful task-focused shell. Navigation to Tasks, Matrix, Habits, Calendar, Focus, and Search is consistent across platforms.

- Quick-add task is always easily accessible; keyboard shortcuts and command/search entry points on desktop; gestures/touch targets on mobile.

- Tasks, matrix, calendar, and search reflect the same local DB updates without refresh. Optimistic writes remain visible while offline.

- Habit history and Pomodoro sessions persist across restart and sync across devices. Do not rely on an in-memory timer or transient screen state as the record of truth.

- Show clear sync status (offline / syncing / synced / attention required), pending-operation count, retry behavior, and actionable conflict indication; never mislabel an unsynced edit as synced.

- Empty/loading/error states, forms, validation, confirmation for destructive actions, visual polish, responsive breakpoints, and accessibility must be implemented, not merely mocked.

- Deliver small coherent vertical slices, with real local persistence, sync and tests for each slice, rather than building all UI mocks first.

## 7. Engineering conventions and agent behavior

- **Before coding:** inspect repository and existing code, read module docs and architecture/database/sync docs relevant to changes, state assumptions and implementation order. If documentation is missing, create it. Do not blindly replace files.

- **After changes:** update docs, migrations, tests and examples in the same change; report what is done, commands run, test results, limitations and next work.

- **Dart:** `snake_case.dart`, `PascalCase` types, `camelCase` members; immutable UI models where practical; Riverpod for state, GoRouter for routes, async cancellation/disposal safeguards.

- **Python:** format and lint consistently, type annotate service boundaries; SQLAlchemy 2.x async; Pydantic schemas; Alembic migrations; Pytest async integration tests.

- **SQL:** `snake_case` identifiers, parameterized queries, DB constraints and indexes; never edit or delete an already applied migration; create a new migration.

- **API:** prefix `/api/v1/`, typed and versioned request/response contracts, ISO 8601 UTC datetimes, structured error codes, pagination; sync conflicts are first-class results rather than generic 500s.

- **Secrets:** `.env` and OS secure storage, never checked-in credentials; redact personal data and auth tokens from logs. Add rate limits, CORS allowlist, input validation, and pagination bounds.

- **Verification:** run `flutter analyze`, `flutter test`, targeted Flutter integration tests, backend unit/integration tests and migration checks. Build/test each platform when host tooling is available; explicitly list untested targets (iOS/macOS usually need macOS). No fake 'all platforms passed' claims.

- **Never:** bypass SQLite for user-facing domain writes, talk directly from Flutter to PostgreSQL, use silent last-write-wins, hard-delete pending data, turn off tests for expediency, ship fake persistence, copy TickTick proprietary design/assets, hardcode secrets, or silently restructure Docker services.

## 7.1. Codex execution permissions and host Docker safety

These rules apply to Codex CLI in addition to the engineering conventions above. They are agent instructions, not an operating-system security boundary. Actual permissions are enforced by Codex configuration and the host OS.

### General execution policy

**Default behavior: execute autonomously whenever possible.** Do not request approval for commands that are permitted by the active sandbox and comply with the rules below.

- Treat the currently opened MindFlow repository as the authorized write workspace.
- **Read-only operations:** Run commands such as `ls`, `find`, `rg`, `grep`, `cat`, `head`, `git status`, `git diff`, and `git log` without requesting approval whenever permitted by the sandbox. Reading files outside the repository is allowed if normal OS permissions permit it.
- **Workspace operations:** Freely create, edit, move, and delete non-protected project files, install project-local dependencies, generate code, format, lint, build, and run tests.
- **Local development:** Run development servers, project-local tools, and non-destructive database migrations without unnecessary confirmation.
- **Network access:** Use network access for ordinary development tasks, including installing dependencies, accessing documentation, and downloading public development resources, when permitted by the sandbox.
- **Command execution:** Prefer running permitted commands directly rather than requesting elevated permissions. Split compound commands when doing so avoids unnecessary approval prompts.
- **Approval required:** Request explicit approval before writing outside the workspace, modifying system configuration or global packages, changing system services, or using `sudo`, `su`, `doas`, or equivalent privilege escalation.
- **Destructive operations:** Request approval before potentially irreversible actions affecting valuable data, including destructive Git operations, deleting databases, or removing persistent project volumes. Routine deletion of generated or temporary project files is permitted.
- **Security:** Do not access secrets unnecessarily, use external credentials without authorization, or transmit private host files to external services.
- **Denials:** Never circumvent rejected approval requests through alternative commands, tools, or privilege escalation.

### Docker host

The MindFlow development environment may use the host Docker daemon for backend services and PostgreSQL.

- **Autonomous operations:** Execute project-scoped `docker compose build`, `up`, `ps`, `logs`, `exec`, `run`, `restart`, and non-destructive `down` without requesting approval when permitted by the sandbox.
- **Project isolation:** Always use a distinct Compose project name, reuse the existing `pxmindflow` development project. Operate only on this project's containers, images, networks, and volumes.
- **Bind mounts:** Restrict bind mounts to paths within the repository. Never mount host system directories, the host home directory, the filesystem root, or the Docker socket into containers without explicit approval.
- **Container privileges:** Do not enable privileged containers, host PID/IPC namespaces, host networking, extra host devices, additional Linux capabilities, or relaxed security settings without explicit approval.
- **Destructive Docker operations:** Request approval before deleting persistent project volumes, resetting PostgreSQL, dropping databases, or performing destructive migrations.
- **Global Docker operations:** Never execute `docker system prune`, `docker volume prune`, or commands that modify resources belonging to other projects without explicit authorization.
- **Networking:** Prefer binding published development ports to `127.0.0.1` unless remote access is specifically requested.
- **Sandbox restrictions:** If a necessary Docker command is blocked by the sandbox, request approval for that specific command. Do not disable the sandbox or request persistent unrestricted access.

### Approval minimization

- Do not ask for confirmation when an operation is already authorized by these rules and permitted by the sandbox.
- Do not request elevated permissions merely to inspect files, check Git status, search source code, or read logs.
- Do not interpret read-only access outside the workspace as authorization to modify those files.
- Ask only when an operation crosses a defined permission boundary, requires elevated privileges, or risks irreversible loss of valuable data.
- When approval is required, explain the specific operation, affected resources, and reason briefly.

### Security limitation

Access to a rootful host Docker socket may bypass filesystem restrictions even with `workspace-write`. These instructions are behavioral safeguards, not enforced isolation. Use an isolated VM or a constrained Docker daemon if strict security boundaries are required.

## 8. Server development and SSH tunnel testing

Development currently runs on a remote Linux server. Run Docker, Flutter builds,
and automated tests on that server; open the browser on the developer workstation
through an SSH tunnel. Keep API and Web ports bound to loopback. Do not expose
PostgreSQL or development servers publicly to enable testing.

The existing development Compose project is `pxmindflow`. Reuse it to preserve
its database volume; inspect `docker compose ls -a` before choosing a project name.
Do not create a new `mindflow` project for an existing `pxmindflow` database.

On the workstation, keep this tunnel running (replace `user@server`):

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:8000:127.0.0.1:8000 \
  -L 127.0.0.1:8080:127.0.0.1:8080 user@server
```

On the server, run Flutter with `-d web-server --web-hostname 127.0.0.1
--web-port 8080 --dart-define=API_URL=http://localhost:8000/api/v1`.
Open `http://localhost:8080` on the workstation, using the configured CORS origin.
Browser `localhost` means the workstation and reaches the API via the tunnel.
Health: `http://localhost:8000/health`; Swagger: `http://localhost:8000/docs`.
If local ports are occupied, select alternate local forwarding ports and update
the browser origin, CORS and compiled API_URL consistently. Automated checks run
on the server do not prove that the workstation tunnel/browser has been tested.

Use [the browser runbook](docs/developer_browser_testing.md#3-run-the-app-through-an-ssh-tunnel)
for workstation health checks, alternate-port commands and tunnel troubleshooting.
For remote manual testing, prefer `web-server`; `-d chrome` opens a browser on
the machine running Flutter. Browser automation requires Chrome/ChromeDriver on
the automation host and must be reported separately from manual tunnel testing.

### Development commands (on the server)

```bash
# backend: run API and PostgreSQL in Docker
test -f .env || cp .env.example .env
docker compose -p pxmindflow up --build -d
docker compose -p pxmindflow logs -f api
docker compose -p pxmindflow exec api alembic upgrade head
scripts/test_backend.sh  # isolated database; never run pytest against development data
# Flutter: run on selected platform, separately from Docker
cd frontend
flutter pub get
flutter analyze
flutter test
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080 \
  --dart-define=API_URL=http://localhost:8000/api/v1
# flutter run -d windows | macos | linux | android | ios (on supported host)
```

Use a project-specific Compose project name, keep bind mounts inside the repository, and prefer localhost-only published ports. Avoid `docker compose down -v` unless the developer explicitly authorizes data loss. Do not copy production user data into developer environments.

## 9. Delivery order

1. Repository audit, architecture and UI design docs, Docker/PostgreSQL, Flutter shell/theme, SQLite/Drift web+native support, auth and account isolation.

2. Task CRUD + lists/tags/subtasks + robust sync protocol and multi-device tests (**the foundation**).

3. Eisenhower Matrix and Calendar (reuse task data, then recurrence/reminders).

4. Habits + check-in sync; Pomodoro + persisted session history.

5. Offline search, accessibility, responsive refinement, localization, packaging, platform smoke tests and performance validation.

At the end of each phase, make the app run, test critical paths, and document unresolved issues before extending scope. Prefer correct sync and full cross-platform support to optional bells and whistles.
