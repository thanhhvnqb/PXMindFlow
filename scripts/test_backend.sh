#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
export TEST_DB_PASSWORD="$(python3 -c 'import secrets; print(secrets.token_hex(24))')"
export TEST_JWT_SECRET="$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
# Unique isolated project; never connect to the normal development database.
test_project="mindflow_test_${RANDOM}_${RANDOM}"
trap 'docker compose -p "$test_project" -f docker-compose.test.yml down' EXIT
docker compose -p "$test_project" -f docker-compose.test.yml up --build --abort-on-container-exit --exit-code-from tests
