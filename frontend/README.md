# MindFlow client

See the root [README](../README.md) for setup, API_URL, platform commands, SQLite assets and verification. Never clear an account database with pending outbox entries.

Developer guide: [Run Flutter Web and test in a browser before using an emulator](../docs/developer_browser_testing.md). Browser integration uses `flutter drive` with `test_driver/integration_test.dart`; native-only test files under `test/` cannot all run on Chrome.

For remote development, run Flutter with `-d web-server` on the server and open
the app on your workstation through the [SSH tunnel procedure](../docs/developer_browser_testing.md#3-run-the-app-through-an-ssh-tunnel).
It includes API/Web forwarding, health checks and alternate workstation ports.
