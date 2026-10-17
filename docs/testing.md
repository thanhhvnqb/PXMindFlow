# Verification

## Stable SDK alignment, 2026-10-17

- Google release feeds confirm Flutter 3.47.7 stable and Dart 3.13.5 are the newest stable releases. The host already has this exact Flutter revision and bundled Dart; no shared SDK installation changes were needed.
- Updated application SDK minimums, both CI SDK pins (including all six platform build jobs), README and browser prerequisites. Retained pre-existing lockfile package changes; dependency resolution only raised the lockfile SDK minimums.
- `flutter pub get` succeeded; `flutter analyze` found no issues; `flutter test` passed 26 tests, with the external HTTP test skipped without `TEST_API_URL`. Drift emitted multiple-database debug warnings during sync tests.
- `flutter build web --dart-define=API_URL=http://localhost:8000/api/v1` passed, including the WASM compatibility dry run.
- `flutter doctor` confirms the Android toolchain is available; Chrome and Linux build tools are missing. Native builds (Android, iOS, Windows, macOS, Linux), platform integration smoke tests, workstation browser/tunnel and hosted CI were not run. Backend and migrations were unchanged and their checks were not rerun for this SDK-only change.

## Account provider scope repair, 2026-10-15

- Reproduced the screenshot's generic storage error in an app-level widget test with a task saved before login. The underlying exception was `Bad state: Account repository required`: dependent providers resolved from the root container rather than the nested account override.
- Declared repository scoping and dependencies for items, pending count, conflicts and search. The regression fails before this provider fix and passes afterward.
- Added storage readiness before sync, a recoverable storage error page with diagnostic details, and same-account retry without clearing data. Regression verifies an unsent task/outbox survive a failed opening and retry.
- `flutter analyze`: no issues. `flutter test`: 20 passed, one real HTTP test skipped without TEST_API_URL.
- Separate headless Chromium 143 browser probes using the actual AppDatabase saved and reopened a unique SQLite database with both shared IndexedDB and OPFS locks (cross-origin isolated server). These verify SQLite/WASM runtime behavior, not end-to-end login or the workstation SSH tunnel. Browser tools and extracted runtime libraries were confined to ignored frontend/.dart_tool; no system packages installed.
- No backend/schema changes. The backend's nine tests and migration checks passed earlier in this work session.
- Final `flutter build web --dart-define=API_URL=http://localhost:8000/api/v1`: passed including WASM dry run. Restarted the loopback Web development server on port 8080 from /home/thanh/pxmindflow-lumpfish/frontend; HTTP GET returned 200. Workstation browser reload remains unverified.

## Task organization refinement, 2026-10-15

- `flutter analyze`: no issues. `flutter test`: 19 passed; one real HTTP integration test skipped without TEST_API_URL.
- Extended shell workflow verifies selection, bulk reopening and Inbox; targeted widget rerun passed both tests. All six views still fit 360px at 1.3 text scale.
- New query tests cover Inbox, overdue Today, Upcoming, Completed, priority/list intersection and undated-last sorting. SQLite bulk tests verify preserving notes, deduplicated selection, one outbox mutation per task, tombstones and skipping deleted records.
- `flutter build web --dart-define=API_URL=http://localhost:8000/api/v1`: passed, including WASM dry run.
- `scripts/test_backend.sh`: isolated migrations, Alembic schema check and all nine backend tests passed; test containers/network removed. Development database was untouched.
- `git diff --check`: passed. No schema/API changes. Browser/tunnel, platform integration smoke tests and Android/iOS/Windows/macOS/Linux builds were not run.

## Login navigation repair, 2026-10-15

- API logs confirmed successful login and pull responses while the login page remained visible. Router refresh alone did not rebuild the route content after account state changed. The route now listens directly to app state changes, updating the login/task shell and shell status.
- Added a widget regression test that submits the real login form with injected authentication and in-memory SQLite; it failed before the route fix and passed afterward.
- `flutter analyze`: no issues. `flutter test`: 17 passed, one HTTP integration test skipped because TEST_API_URL was not set.
- `flutter build web --dart-define=API_URL=http://localhost:8000/api/v1`: passed, including the WASM dry run.
- Workstation browser/tunnel and native platform runtimes were not exercised for this repair. Restart the running Flutter web session to load the changed Dart code before browser verification.

## API startup and remote development recheck, 2026-10-15

- Existing development project: `pxmindflow`. Its API image had command
  `["python3"]`, causing an immediate successful exit instead of serving HTTP.
  Rebuilt/recreated using `docker compose -p pxmindflow up --build -d api`;
  the container now runs the Dockerfile's Uvicorn command. No source fix or
  database volume reset was required.
- Development `alembic upgrade head` and `alembic check` succeeded;
  `http://127.0.0.1:8000/health` returned `{"status":"ok"}`.
- `scripts/test_backend.sh`: fresh isolated PostgreSQL migrations, schema check,
  and all 9 backend tests passed. Test containers/network were removed by the script.
- AGENTS.md, README.md and the browser runbook document remote-server development
  and workstation browser access via SSH forwarding for ports 8000/8080.
- Workstation SSH tunnel/browser behavior and Flutter/platform checks were not run
  during this API image/documentation repair.

## Recheck, 2026-10-14

Developer instructions: [Browser testing before using an emulator](developer_browser_testing.md).

- Flutter 3.44.1 / Dart 3.12.1.
- `flutter analyze`: no issues; `flutter test`: 16 passed, one HTTP test skipped without TEST_API_URL.
- `flutter build web`: passed, including WASM dry run. This is compilation, not a browser runtime result.
- Added `frontend/test_driver/integration_test.dart` for the existing platform persistence smoke test using ChromeDriver / `flutter drive`.
- Chrome/Chromium not found on this host; browser integration and native emulator checks remain unrun. Driver addition checked separately with analyzer.
- `scripts/test_backend.sh`: first run exposed a PostgreSQL startup race (Unix-socket healthcheck passed during temporary init server, then TCP migration failed). Both Compose files now check TCP readiness. Rerun passed fresh migrations, `alembic check` and all nine API tests; isolated test containers/network were stopped and removed by the script.

## Previous verification, 2026-10-13

Commands run:

- flutter analyze: no issues.
- flutter test: 16 tests passed (local persistence/sync, Focus clock and widget tests); HTTP integration is skipped in the default suite unless TEST_API_URL is provided.
- flutter test test/api_integration_test.dart --dart-define=TEST_API_URL=http://127.0.0.1:18080/api/v1: passed against real containerized FastAPI/PostgreSQL.
- flutter build web: passed; sqlite3.wasm and drift_worker.dart.js are included.
- scripts/test_backend.sh: locked Docker image build, fresh PostgreSQL, alembic upgrade head, alembic check and nine API tests passed.
- ruff check backend and ruff format --check backend: passed.
- flutter doctor -v: recorded platform limitations below.

Platform runners and six-platform CI matrix exist. CI itself has not run. Web compiled but browser runtime/persistence was not exercised: Chrome absent. Android build unavailable without resolving Java 26/Gradle mismatch and unaccepted SDK licenses. Linux missing clang/cmake/ninja/pkg-config (also needs GTK/libsecret). Windows requires Windows; iOS/macOS require macOS/Xcode/signing. None of these five native targets was built or runtime-tested on this host.

integration_test/local_task_smoke_test.dart tests actual platform SQLite reopen and unsent outbox persistence. It is provided but unrun because this host has no usable platform/browser runtime toolchain. The separately executed native Flutter test runner does verify real SQLite and real HTTP API synchronization.

Coverage: atomic rollback; disk reopen while offline; queued create/edit/delete dependency versions; lost ACK and frozen replay; concurrent sync serialization; nonmonotonic page rollback; two-device same-field and different-field edits; explicit conflict resolution, later local edits during attention; edit/delete race; operation reuse fingerprint; paginated commit sequence; account/relationship isolation; refresh rotation/revocation; strict payload validation; habit duplicate identities; FTS update/tombstone exclusion; monotonic Focus/restart/pause semantics; desktop task workflow; six views at 360px with 1.3 text scale.

Missing required matrix cases: recurring occurrence completion, tombstone cleanup/stale-device resync after expiration (cleanup disabled), device revocation, crash injection at every transaction boundary, full concurrent push/pull/page-overlap combinations, browser eviction, timezone/DST habits. Therefore synchronization is a tested foundation, not the completed mandatory recovery matrix.

Tests deliberately open separate database executors to simulate devices; Drift emits a debug warning about multiple instances. They do not share an executor or account file. No tests or diagnostics are disabled.

Task workspace regression checks cover the persistent rail at 500 px on desktop, three-column availability at 1400 px, the organization drawer, local task creation/completion and bulk reopening, and all six mobile views at 360 px with 1.3x text. `flutter analyze` and `flutter test` pass (20 tests, one API integration test skipped without TEST_API_URL). Native platform builds and workstation SSH-tunnel manual testing were not performed for this layout change.

The Web release build also passes with `flutter build web --dart-define=API_URL=http://localhost:8000/api/v1`. Additional widget assertions verify selecting task details and finding account/sync actions in the mobile drawer.

Web startup regression (2026-10-15): headless Chromium against the loopback debug server in this checkout rendered the Sign in screen, removed the loading overlay after the first frame, and reloaded successfully. Blocking `www.gstatic.com` still rendered the app with CanvasKit JS/WASM loaded from port 8080. Blocking local CanvasKit instead displayed the retry action. This uses a fresh automation profile and does not establish that an existing workstation profile or its SSH tunnel was tested. Browser tooling and shared libraries were installed/extracted only in the ignored project-local `.browser-check/` directory.

## Browser storage warning correction, 2026-10-17

- Removed the false warning for shared IndexedDB caused by treating every missing optional browser API as degraded persistence. Selected unsafe IndexedDB and in-memory modes retain specific, actionable warnings. Existing database names, data and outbox are unchanged.
- Added regression coverage for all five Drift storage modes.
- `flutter analyze`: passed. `flutter test`: 23 passed, one API integration test skipped without TEST_API_URL. `git diff --check`: passed.
- No backend/schema changes; backend checks and native builds were not rerun. Workstation browser/SSH tunnel verification was not performed.
- `flutter build web --dart-define=API_URL=http://localhost:8000/api/v1`: passed, including WASM dry run.

### Task entry controls (2026-10-17)

`flutter analyze` passes. The frontend suite passes (23 tests, one API integration test skipped without `TEST_API_URL`); the added task-controls widget test also passes. It exercises date/priority selection, failed-write draft retention and successful retry. The shell widget test now creates a canonical task through inline Enter submission and verifies its outbox plus completion/bulk flows. No backend or schema changes were made; backend tests/migration checks were not rerun for this UI increment. Manual workstation tunnel testing and native platform builds are not verified in this increment.

Web release compilation also passes with `flutter build web --dart-define=API_URL=http://localhost:8000/api/v1` (including the SDK's Wasm compatibility dry run). This is compilation evidence, not browser persistence or workstation tunnel verification.

### Timed tasks and direct details editing (2026-10-17)

`flutter analyze` passes; `flutter test` passes 26 tests (one external API integration test skipped without `TEST_API_URL`). Tests cover selecting time as UTC, removing time without removing its day, draft retention/retry and editing notes directly into the SQLite/outbox flow. `flutter build web --no-wasm-dry-run --dart-define=API_URL=http://localhost:8000/api/v1` passes. The Linux integration smoke test was attempted but cannot build because CMake is absent; no system packages were installed. Android/iOS/Windows/macOS builds and manual workstation browser/tunnel tests were not performed.

`scripts/test_backend.sh` passes all 11 PostgreSQL API tests, including timed-task push/pull, removal of time and rejection of non-UTC/naive timestamps. Alembic upgrade and schema check pass (`No new upgrade operations detected`). Tests use the script's disposable isolated Compose project; the existing `pxmindflow` development database is untouched.

## Space/Project organization verification — 2026-10-17

- `cd frontend && flutter analyze`: no issues.
- `cd frontend && flutter test`: 36 passed, one optional real-HTTP API test
  skipped because its endpoint was not configured for this run.
- `scripts/test_backend.sh`: 13 passed in isolated PostgreSQL containers;
  `alembic upgrade head` and `alembic check` passed. Includes v0003 migration
  with legacy rows in a transactionally rolled-back schema.
- `ruff check backend/app backend/tests` and `git diff --check`: passed.
- `cd frontend && flutter build web`: passed (compilation; not browser runtime).
- `flutter test integration_test/local_task_smoke_test.dart -d linux`: attempted,
  blocked before application launch because CMake is absent. No system tools
  were installed. Chrome/ChromeDriver are absent; browser automation and manual
  workstation SSH-tunnel testing were not performed. Android, iOS, Windows and
  macOS builds were not verified on this host.

New tests cover effective tags and direct bindings, Space/Project/parent moves,
four nested subtask levels and detaching a branch, archive/restore independent
of project status, archived-tag discovery, offline full-text organization search,
invalid references and cycles, tenant isolation, subtree tombstone ordering,
dependency-ordered sync after lost ACK, and v2→v3 record/outbox preservation,
including sent operation IDs and payload bytes. UI tests verify direct/inherited
tag separation, archive suggestions, placement fields and required Project Space.
The full MVP fault-injection matrix remains outside this increment's coverage.

## Validation-rejection recovery — 2026-10-17

The running development API predated project_id/due_at and rejected new-client
payloads. Its existing pxmindflow service was rebuilt from this checkout using
the original Compose configuration/environment plus a build-context-only override;
its PostgreSQL volume was retained and additive migration 0003 applied.

Regression coverage checks new task retries, acknowledged update retries after
an API upgrade, fresh operation identities, legacy invalid_payload conflicts,
retained local edits/versions and rejecting Keep server without a snapshot.
The API regression checks canonical snapshots on validation failures and cached
rejections followed by successful fresh retries. No browser-owned SQLite data
was accessed or cleared; the user must refresh their browser and retry its
existing rejected operation once the API/web server are updated.

Final recovery checks: Flutter analysis passed; 39 Flutter tests passed (one
optional HTTP test skipped); 14 isolated PostgreSQL tests and Alembic schema
check passed; Ruff and diff checks passed. Live API health returned ok, live
payload validation accepted project_id/parent_id/due_at, and Alembic reported
0003 (head). Browser interaction remains to be confirmed on the workstation.
