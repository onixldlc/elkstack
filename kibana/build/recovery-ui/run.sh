#!/usr/bin/env sh
# ---------------------------------------------------------------------------
# run.sh — serve the Cluster Recovery Console with the bundled node server
# (main.js). No python, no npm. Set PORT to change the port (default 8080).
#
#   ./run.sh            # serve source on http://localhost:8080
#   PORT=9000 ./run.sh  # different port
#   ./run.sh dist       # serve the built dist/ folder instead of the source
# ---------------------------------------------------------------------------
set -e

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
PORT="${PORT:-8080}"
NODE_BIN="$(command -v node || echo /usr/share/kibana/node/bin/node)"

if [ ! -x "$NODE_BIN" ] && ! command -v node >/dev/null 2>&1; then
  echo "ERROR: need node to serve files (main.js)." >&2
  exit 1
fi

# Optional positional arg = directory to serve (e.g. dist), relative to here.
[ -n "$1" ] && ROOT="$ROOT_DIR/$1"

echo "──────────────────────────────────────────────────────────────"
echo "  Cluster Recovery Console"
echo "  serving: ${ROOT:-$ROOT_DIR}"
echo "  open:    http://localhost:$PORT/"
echo "  stop:    Ctrl-C"
echo "──────────────────────────────────────────────────────────────"

cd "$ROOT_DIR"
export PORT
[ -n "$ROOT" ] && export ROOT
exec "$NODE_BIN" main.js
