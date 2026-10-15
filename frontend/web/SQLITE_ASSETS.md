# SQLite browser assets

sqlite3.wasm and drift_worker.dart.js were downloaded from the official Drift
2.35.0 release (compatible with locked Drift 2.35.2 within this minor series):
https://github.com/simolus3/drift/releases/tag/drift-2.35.0

The upstream asset drift_worker.js is named drift_worker.dart.js locally.
Serve WASM as application/wasm. See https://drift.simonbinder.eu/platforms/web/.
Browser runtime persistence has not been smoke-tested on this host (no Chrome).
