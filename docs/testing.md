# Verification

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
