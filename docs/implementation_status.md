# Implementation status — 2026-10-15

An executable incremental foundation is implemented; the full MVP and mandatory sync recovery matrix are not complete.

## Implemented

- Six generated platform runners, Riverpod/GoRouter adaptive shell, Material 3 teal identity, light/dark themes, desktop sidebar/mobile navigation, keyboard quick-add/search, EN/VI navigation and several forms; Material localization delegates installed.
- Account-isolated Drift SQLite databases; packaged WebAssembly/worker; degraded browser-storage indication; reactive FTS5 plus fallback.
- Task/list creation and editing; notes, priority, date-only deadlines, completion, All/Today/Upcoming/Completed filters, list selection and confirmed deletion. Matrix drag/drop and date calendar reuse canonical task rows.
- Basic UTC daily habits/check-ins with deterministic identities and persisted history count. Configurable focus/break sessions, pause/resume/finish, persisted history, monotonic foreground clock and bounded UTC recovery.
- Dockerized FastAPI/PostgreSQL, three Alembic migrations, Argon2 passwords, short access JWTs, rotated/revocable hashed refresh tokens, CORS allowlist and shared auth request throttling. Full dependency locks.
- Local/outbox transaction; frozen idempotent retries; authenticated per-account version checks and durable commit-ordered changes; paginated tombstone pull; transactional cursor; preserved pending edits; persistent conflict queue with Keep mine/Keep server/Review differences. Later edits during attention remain intact.
- Unit/widget/API/real HTTP client integration tests, isolated test script, platform persistence smoke-test source, six-platform CI configuration, architecture/schema/protocol/design/feature docs and README runbook.

## Verified

See testing.md for commands and coverage. Backend: nine API tests; fresh migrations and schema check; locked Docker image; Ruff. Real Drift-to-Docker API integration: one test passed. Flutter analysis and Web compilation passed. The final local suite passed 16 tests (plus one default HTTP test skipped and separately executed successfully). Native platform builds and platform smoke tests remain unverified.

## Priority remaining

1. Replace generic typed envelope/JSON payload records with dedicated Drift/PostgreSQL domain tables and ownership-aware relationship FKs, devices, normalized tag joins and reminders. Organization now validates JSON references transactionally: populated Spaces/Projects/tags require archive, and Task subtree deletion queues descendants before parents.
2. Complete sync lifecycle: common-base snapshots and field diffs, revoked devices, reliable reconnect detection, durable refresh recovery after lost refresh response, full recovery/fault-injection matrix, expired cursor/bootstrap contract and safe tombstone retention. No tombstone cleanup is enabled.
3. Recurrence rules, stable occurrence completion/exception records and timezone/DST tests. Recurrence is unavailable rather than silently cloning tasks. Calendar day/week/month task grid, dated quick-create and timed deadlines.
4. Habit schedule/target editing, IANA user timezone selection, local-day DST/travel behavior, streak/progress/history views. Current habits deliberately label their UTC-day limitation.
5. Focus daily totals, linked tasks, preference persistence, automatic break cycles, richer statistics and background notification handling. Cold-start recovery after changed system clocks remains bounded approximation.
6. Full ARB-based EN/VI coverage (many strings still English), bulk task move/scheduling, advanced search filters, accessibility audit, original launcher icons, packaging, performance/load testing and platform runtime smoke tests.
7. Production HTTPS/reverse-proxy configuration, per-account auth abuse limits, refresh-family reuse policy, uniform structured errors, auth-counter cleanup, signing and secrets/deployment operations. This development foundation is not ready for public production deployment.

Browser durability is not guaranteed. Configuration of six CI builds is not a claim that those builds passed. Existing user modifications to AGENTS.md and .agents were preserved.

## Task organization increment — 2026-10-15

Added Inbox, exact priority filtering, deterministic priority/date/title/newest sorting, visible result count and selection mode with select-all, complete/reopen and confirmed bulk tombstone deletion. Repository bulk writes preserve current payloads and atomically queue every mutation. English/Vietnamese labels and compact wrapping follow MindFlow's existing original teal design. Task query/repository tests and the shell workflow cover the added behavior. Full MVP gaps above remain open.


## Space/Project organization — 2026-10-17

Implemented compatible List → Space rename; Project lifecycle; Task placement in
Inbox, a Space or Project; recursive parent-derived subtasks; direct/effective
tags with source inspection; Space/Project/Tag archive and restore; task and
search filters including archived tags. Migration v3/0003 adds indexes without
rewriting records, sync history or pending operations. Dedicated domain relation
FKs remain future work for the JSON-envelope foundation.

Latest verification details are in testing.md; older counts above are historical.
