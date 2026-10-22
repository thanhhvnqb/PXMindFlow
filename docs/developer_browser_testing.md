# Run and test MindFlow in a browser before using an emulator

Checked against the source on 2026-10-14. Commands use Bash and run from the repository root unless a step specifies `cd frontend`. Flutter Web shares the app’s Dart code. Browser responsive mode helps verify mobile layouts, but does not verify Android/iOS plugins, permissions, lifecycle behavior, or native SQLite.

For the current remote-server workflow, use the [SSH tunnel instructions](../README.md#remote-server-development-and-ssh-tunnel-testing). Run the `web-server` command in section 3 on the server and open the forwarded URL on your workstation. Chrome/ChromeDriver requirements below apply to browser automation, or to running the Chrome device on a machine with Chrome.

## 1. Tools

- Flutter 3.47.7 / Dart 3.13.5 (the CI versions; `pubspec.yaml` requires Dart ^3.13.5 and Flutter >=3.47.7).
- Docker Engine/Desktop and Compose v2; Python 3 for the backend test script.
- Chrome, plus a compatible ChromeDriver version for browser integration tests.

```bash
flutter --version
flutter doctor -v
flutter devices
docker compose version
```

If Flutter does not detect Chrome, set `CHROME_EXECUTABLE` to the installed Chrome executable. Android SDK/emulator tooling is unnecessary for Web. Do not upgrade dependencies solely to dismiss newer-version notices.

## 2. Start the API and PostgreSQL

If `.env` does not exist, copy `.env.example` to `.env`; preserve any existing file. Set `POSTGRES_PASSWORD` to a random hexadecimal string and `JWT_SECRET` to at least 32 random characters. Keep `.env` out of Git. Use:

```dotenv
CORS_ORIGINS=["http://localhost:8080","http://127.0.0.1:8080"]
```

```bash
docker compose -p pxmindflow up --build -d
docker compose -p pxmindflow exec api alembic upgrade head
docker compose -p pxmindflow ps
curl --fail http://localhost:8000/health
```

Expect `{"status":"ok"}` from health. API documentation: http://localhost:8000/docs. Health confirms that the HTTP server responds; migrations and account registration verify database access. Development Compose does not run migrations automatically. Its PostgreSQL healthcheck uses TCP so the temporary Unix-socket server used during initialization cannot prematurely signal readiness to the API.

If you previously ran Compose without `-p`, check `docker compose ls` and reuse the existing project to retain access to its volume. Changing the project name creates a separate database. Do not run two projects bound to port 8000 simultaneously.

## 3. Run the app through an SSH tunnel

Run in a persistent terminal on the **server**, from `frontend/`:

```bash
cd frontend
flutter pub get
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080 \
  --dart-define=API_URL=http://localhost:8000/api/v1
```

In a terminal on your **workstation**, replace `user@server` with your SSH destination and keep this command running:

```bash
ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 \
  -o ServerAliveCountMax=3 \
  -L 127.0.0.1:8000:127.0.0.1:8000 \
  -L 127.0.0.1:8080:127.0.0.1:8080 user@server
```

Add `-p <ssh-port>` if SSH uses a nonstandard port. The left port in each
forward is on the workstation; the destination `127.0.0.1` is on the server.
No PostgreSQL or ChromeDriver forwarding is needed for manual testing.

On the **workstation**, verify both forwards before testing:

```bash
curl --fail http://127.0.0.1:8000/health
curl --fail --output /dev/null http://127.0.0.1:8080/
```

Open `http://localhost:8080` in your workstation browser, select **New here? Create an account**, and use a test email address with a password of at least 12 characters. The first sign-in requires the API. `API_URL` is read at compile time; stop and restart the run when changing it. This is a public API URL and must contain no secrets.

Keep the same origin (`http://localhost:8080`) and browser profile when checking persistence after reload. `localhost` and `127.0.0.1`, or different ports, have separate storage and CORS origins. `flutter run -d chrome` may use a temporary debug profile; closing and reopening a debug session does not establish that persistent data was lost.

For local development on a machine with Chrome, you can instead run from `frontend/`:

```bash
flutter run -d chrome --web-hostname localhost --web-port 8080 \
  --dart-define=API_URL=http://localhost:8000/api/v1
```

This opens Chrome on the machine running Flutter. Use `web-server` for the remote
server workflow; it needs no server-side Chrome. Debugging support for
`web-server` is more limited than for the Chrome device.

### Alternate workstation ports

If workstation ports 8000/8080 are occupied, keep the server ports unchanged:

```bash
ssh -N -o ExitOnForwardFailure=yes \
  -L 127.0.0.1:18000:127.0.0.1:8000 \
  -L 127.0.0.1:18088:127.0.0.1:8080 user@server
```

Set `CORS_ORIGINS=["http://localhost:18088"]` in the server's `.env`, then run
`docker compose -p pxmindflow up -d api` from the repository root to recreate
the API environment. Restart Flutter on the server with:

```bash
flutter run -d web-server --web-hostname 127.0.0.1 --web-port 8080 \
  --dart-define=API_URL=http://localhost:18000/api/v1
```

Open `http://localhost:18088` on the workstation; health is at
`http://localhost:18000/health`. The compiled API URL uses the **workstation**
API port. Changing the browser origin creates separate browser storage; use the
original origin to access its existing pending edits. Restore CORS and API_URL
when returning to the default ports.

## 4. Run automated checks before browser testing

From `frontend/`:

```bash
flutter analyze
flutter test
flutter build web --dart-define=API_URL=http://localhost:8000/api/v1
```

`flutter test` runs unit, widget, and local sync tests in the Flutter test runner. The HTTP test is skipped unless `TEST_API_URL` is provided. A successful Web build confirms compilation, not browser storage behavior. Sync/HTTP tests use `drift/native.dart`; do not run the entire suite with `flutter test --platform chrome`.

To inspect the built artifact in a regular browser, first stop any development server using port 8080, then run from `frontend/`:

```bash
python3 -m http.server 8080 --bind 127.0.0.1 --directory build/web
```

Open **http://localhost:8080** to match the configured CORS origin. In Network tools, verify that `sqlite3.wasm` and `drift_worker.dart.js` return 200 and that WASM uses the `application/wasm` MIME type. This build still uses the local API and is not a deployment configuration. Do not assume the app can load from a closed state without a network connection: the repository does not guarantee offline caching of the entire app shell.

## 5. Run the Chrome integration smoke test

The existing test creates a task through the UI, closes and reopens the database, and checks that the task and one outbox entry remain. It uses actual SQLite/WASM on Web and bypasses login/API access. It does not verify a full browser reload, secure storage, or HTTP sync. Each run retains a separate smoke database with a UUID and leaves account data untouched.

Terminal A:

Run both automation terminals on the server with Chrome and ChromeDriver
installed. The manual workstation tunnel does not provide a browser to these
commands. If those tools are unavailable, report browser automation as unrun.

```bash
chromedriver --version
chromedriver --port=4444
```

Terminal B, from `frontend/`:

```bash
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/local_task_smoke_test.dart \
  -d chrome
```

For headless execution, replace `-d chrome` with `-d web-server --browser-name=chrome`. This smoke test needs no API. The driver at `frontend/test_driver/integration_test.dart` follows the [official Flutter instructions](https://docs.flutter.dev/testing/integration-tests#test-in-a-web-browser).

## 6. Manual browser test checklist

1. Register/sign in. Create a list and tasks with notes, priority, and due dates; edit and complete tasks. Check Today/Upcoming/Completed against the entered data.
2. Open Matrix/Calendar/Search and confirm they reflect the same tasks. Drag a task to another quadrant, verify its state in Tasks, and search by title/notes.
3. Create a habit/check-in. Run Focus, pause/resume, and reload. Habits currently use UTC days; timezone/DST behavior, full streak support, recurrence, and reminders are not ready for acceptance testing.
4. Wait until pending reaches 0. Stop **only the API** from a repository-root terminal with `docker compose -p pxmindflow stop api`, or block port 8000 requests in DevTools. Create, edit, and delete different test tasks. The UI should update immediately, pending should exceed 0, and status must not show synced.
5. Reload the same tab/origin while the frontend server remains available. Confirm unsynced tasks remain. Do not enable Offline for the whole page and expect the app shell to reload from the development server.
6. Run `docker compose -p pxmindflow start api` and trigger sync. Pending should reach 0. Open a second browser profile, sign in to the same account, and verify the data.
7. Let both profiles receive a synced task. Stop the API and edit that task differently in each profile. Restart the API and sync each profile in turn. Expect attention/conflict; try Review differences / Keep mine / Keep server. Local edits must not disappear silently.
8. Sign out with pending changes and check the confirmation to retain data. Sign back in to the same account to sync. Another account must not see the previous account’s data.
9. Use DevTools responsive mode at 360px and desktop widths. Check text scaling/zoom, keyboard input, EN/VI, and light/dark themes. This verifies Web layouts; native tests are still required.

Do not clear site storage or databases while operations are pending. Record private-mode restrictions, browser eviction, and degraded-storage warnings. Web persistence is not guaranteed in every environment.

## 7. Backend and real client–API tests

From the repository root, the backend suite uses isolated PostgreSQL, fresh migrations, and `alembic check`:

```bash
scripts/test_backend.sh
```

The real HTTP client test runs in the native Flutter test runner, not a browser. Use a separate test project and run the following in the same Bash terminal from the repository root:

```bash
export TEST_DB_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
export TEST_JWT_SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
docker compose -p mindflow_client_test -f docker-compose.test.yml build tests
docker compose -p mindflow_client_test -f docker-compose.test.yml --profile client-integration up -d db api
curl --fail http://127.0.0.1:18080/health
# If the API is not ready, inspect its logs and retry health before continuing.
cd frontend
flutter test test/api_integration_test.dart \
  --dart-define=TEST_API_URL=http://127.0.0.1:18080/api/v1
cd ..
docker compose -p mindflow_client_test -f docker-compose.test.yml --profile client-integration down
unset TEST_DB_PASSWORD TEST_JWT_SECRET
```

Build the `tests` service first: the test `api` service specifies an `image` but no `build`. Never point pytest at the development database. Test Compose does not configure CORS for the browser UI; use development Compose from step 2 for UI testing.

## 8. Move to an emulator after Web checks pass

```bash
flutter doctor -v
flutter emulators
flutter emulators --launch <emulator-id>
flutter devices
cd frontend
flutter run -d <android-device-id> \
  --dart-define=API_URL=http://10.0.2.2:8000/api/v1
flutter test integration_test/local_task_smoke_test.dart -d <android-device-id>
```

Commands before `cd frontend` run from the repository root. Stop the interactive `flutter run` session before running the smoke test. `10.0.2.2` is the host alias in the standard Android Emulator; `localhost` inside the emulator refers to the emulator itself. Android currently has no explicit cleartext HTTP allowance. If logs report blocked cleartext traffic, configure a debug-only exception or use HTTPS before acceptance testing. Browser success does not verify Android HTTP access. Do not allow cleartext broadly for release. iOS Simulator requires macOS/Xcode and suitable HTTPS/ATS configuration.

Repeat task/offline/restart/sync tests on the emulator, and check back navigation, keyboard behavior, background/resume, secure storage, and native SQLite. Windows/macOS/Linux/iOS/Android each require their own toolchains; Web success does not replace native smoke tests.

## 9. Troubleshooting

| Symptom | Check |
| --- | --- |
| SSH reports address already in use | A workstation forwarding port is occupied; use the alternate-port procedure above |
| SSH reports channel open failed / connection refused | Check API/Flutter on the server with `curl --fail http://127.0.0.1:8000/health` and `curl --fail --output /dev/null http://127.0.0.1:8080/`; SSH can start even when a destination service is down |
| Server health works but workstation health fails | Keep the SSH session running; verify the SSH destination and forwarded ports on the workstation |
| Login fails | Health, migration, `docker compose -p pxmindflow logs --tail=100 api`, password length of at least 12 characters |
| CORS error / registration OPTIONS returns 400 | Development allows `http://localhost:8080` and `http://127.0.0.1:8080`. Other ports require their exact browser origin in `CORS_ORIGINS`; after editing `.env`, run `docker compose -p pxmindflow up -d api` to recreate the service environment. A restart alone does not load changed environment values. |
| Generic storage error after login | Updated code declares account scope for all repository-dependent Riverpod providers. Restart the Web server from the intended checkout and reload the same origin. For an actual startup failure, use Retry storage and Diagnostic details; preserve site data. |
| Storage appears empty after reload | Same origin/profile/account? In-memory warning? WASM/worker responses contain the actual files rather than HTML? |
| Chrome missing from devices | Chrome installation, `CHROME_EXECUTABLE`, `flutter doctor -v` |
| Driver session fails | Compatible ChromeDriver/Chrome versions, port 4444 available, driver started first |
| Pending count does not decrease | API/auth/conflict indicator, manual sync, logs; preserve SQLite/outbox |
| Web builds but fails at runtime | Console + Network, secure context localhost/HTTPS, storage restrictions, asset MIME |

Stop the development environment with `docker compose -p pxmindflow down` when needed; preserve volumes. Do not use `down -v` or prune commands to troubleshoot.

### Startup diagnostics and checkout selection

Run `scripts/run_web.sh` from the intended checkout; it resolves and prints that checkout's frontend directory. Keep only one Web server on port 8080. A server launched from another worktree will keep serving that worktree, even after edits in this one. On Linux, inspect the Flutter process working directory with `readlink /proc/<pid>/cwd`. Restart the intended checkout and reload the same browser origin without clearing site data.

The HTML shell displays loading progress before Flutter's first frame and offers a reload button after 30 seconds or a startup error. `flutter_bootstrap.js` loads CanvasKit from the same server (`canvaskit/`) instead of requiring access to Google's renderer CDN. Debug compilation and the initial download may take time; wait for Flutter to print “is being served” before opening the browser. If the app still does not render, inspect Console and Network and preserve browser storage.

### Automatic hot reload

Both `bash scripts/run_web.sh` and `bash frontend/run_web.sh` start the same
checkout-aware Web launcher with automatic hot reload. Python 3 (standard library
only) watches Dart files under `frontend/lib`, debounces saves, and requests
Flutter hot reload through its PID-file signal handler. Keep the browser connected
to the running debug app through the SSH tunnel. Terminal `r` / `R` remain
available for manual reload / restart. Stop with Ctrl+C.

Changes to dependencies, Web bootstrap files, or assets require a manual restart;
changes that Flutter cannot hot reload may also require `R`. `WEB_PORT` and
`API_URL` overrides remain supported. This launcher targets the Linux development
server; workstation browser/tunnel behavior must be verified separately.
