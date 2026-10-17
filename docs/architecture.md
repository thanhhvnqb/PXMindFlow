# Architecture

Audit: repository initially contained only AGENTS.md, README.md and agent skills, with user edits. Flutter 3.44.1 / Dart 3.12.1 and Docker are available. No prior application was replaced.

Current SDK baseline (2026-10-17): Flutter 3.47.7 stable with bundled Dart 3.13.5. The app SDK constraints and all six CI build targets use this baseline. Historical audit versions above are retained for context.

Feature-first Flutter with Riverpod providers and GoRouter navigation. Presentation calls a local repository, never SQL or REST. Drift SQLite is the only domain source of truth. Each authenticated UUID has its own named database, retained at logout. Authentication tokens use platform secure storage. Web secure storage and SQLite durability depend on browser support; HTTPS is required in deployment.

FastAPI routers delegate to services and repositories. PostgreSQL holds tenant-keyed records, idempotency results and ordered changes. An account row lock serializes push transactions, including sequence publication. Different accounts proceed independently. This is a correctness-first foundation, not a throughput claim.

Initial implementation uses typed Drift envelope/outbox/conflict/state tables and JSON payload domain records. PostgreSQL has equivalent JSONB records. Dedicated domain tables, relationship constraints, device lifecycle, recurrence and complete production security remain future migrations. Do not mistake the foundation for the complete approved MVP schema.

Six Flutter platform runners are scaffolded; builds must be verified individually. No remote infrastructure or unrelated legacy modules are introduced.

Dependencies: frontend/pubspec.lock and backend/requirements.lock pin the resolved dependency graph. Backend requirements.txt records direct requirements; container installs the lock. SDK flutter_localizations pins intl 0.20.2. Six-platform CI configuration is provided but has not run during this session.

Account repository overrides live in a nested ProviderScope. The repository is explicitly scoped (`dependencies: []`) and every repository-dependent stream declares that dependency, so domain data, pending counts, conflicts and search resolve inside the account container. Opening verifies local records before sync starts; failures display diagnostic details and allow reopening the same database without resetting its outbox.
