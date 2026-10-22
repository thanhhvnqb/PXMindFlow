#!/usr/bin/env bash
set -euo pipefail

# Resolve this checkout instead of relying on the caller's working directory.
project_root="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_root/frontend"
printf 'Serving MindFlow from %s\n' "$PWD"
exec python3 "$project_root/scripts/watch_flutter_web.py" -d web-server --web-hostname 127.0.0.1 \
  --web-port "${WEB_PORT:-8080}" \
  --dart-define="API_URL=${API_URL:-http://localhost:8000/api/v1}"
