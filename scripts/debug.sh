#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

export RESOLUX_BIND="127.0.0.1"
unset RESOLUX_FRONT_DIST
export RESOLUX_PUBLIC_URL="${RESOLUX_PUBLIC_URL:-https://mac.tail17794.ts.net:8443}"

front_cmd() {
    if command -v pnpm >/dev/null 2>&1; then
        pnpm run dev
    elif command -v npm >/dev/null 2>&1; then
        npm run dev
    elif [ -x "$HOME/.local/bin/mise" ]; then
        "$HOME/.local/bin/mise" exec -- pnpm run dev
    else
        echo "pnpm/npm/mise não encontrado para o frontend." >&2
        return 1
    fi
}

(cd ../frontend && front_cmd) &
front=$!
trap 'kill "$front" 2>/dev/null || true; wait "$front" 2>/dev/null || true' EXIT

swift run --package-path Features/Resolume ResoluxServer
