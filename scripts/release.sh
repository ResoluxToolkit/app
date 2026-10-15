#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

front_cmd() {
    if command -v pnpm >/dev/null 2>&1; then
        pnpm run build
    elif command -v npm >/dev/null 2>&1; then
        npm run build
    elif [ -x "$HOME/.local/bin/mise" ]; then
        "$HOME/.local/bin/mise" exec -- pnpm run build
    else
        echo "pnpm/npm/mise não encontrado para o frontend." >&2
        return 1
    fi
}

(cd ../frontend && front_cmd)
swift build --package-path Features/Resolume -c release --product ResoluxServer

exec env RESOLUX_FRONT_DIST="$PWD/../frontend/dist" \
    RESOLUX_BIND="0.0.0.0" \
    ./Features/Resolume/.build/release/ResoluxServer
