#!/usr/bin/env sh
# ---------------------------------------------------------------------------
# build.sh — produce a self-contained dist/ for deployment. No Node, no npm.
#
# What it does:
#   1. Copies the app (HTML, css/, js/, components/) into dist/, with the
#      console as dist/index.html so the folder serves directly.
#   2. Vendors React, ReactDOM and Babel into dist/vendor/ (downloaded once
#      with curl/wget) and rewrites the CDN <script> tags to those local
#      copies — so the deployed page has ZERO external dependencies.
#
# Run it again any time; it rebuilds dist/ from scratch.
# Serve the result with the bundled node server: ./run.sh dist
# ---------------------------------------------------------------------------
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
DIST="$ROOT/dist"
SRC_HTML="$ROOT/Cluster Recovery Console.html"

REACT_VER="18.3.1"
BABEL_VER="7.29.0"

echo "› cleaning dist/"
rm -rf "$DIST"
mkdir -p "$DIST/vendor"

echo "› copying app files"
cp "$SRC_HTML" "$DIST/index.html"
cp -R "$ROOT/css" "$DIST/css"
cp -R "$ROOT/js" "$DIST/js"
cp -R "$ROOT/components" "$DIST/components"

# --- download helper -------------------------------------------------------
fetch() {
  url="$1"; out="$2"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o "$out"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO "$out" "$url"
  else
    echo "ERROR: need curl or wget to vendor libraries." >&2
    exit 1
  fi
}

echo "› vendoring React / ReactDOM / Babel (one-time download)"
fetch "https://unpkg.com/react@${REACT_VER}/umd/react.development.js"        "$DIST/vendor/react.js"
fetch "https://unpkg.com/react-dom@${REACT_VER}/umd/react-dom.development.js" "$DIST/vendor/react-dom.js"
fetch "https://unpkg.com/@babel/standalone@${BABEL_VER}/babel.min.js"         "$DIST/vendor/babel.min.js"

echo "› rewriting CDN script tags to local vendor/"
# sed -i.bak works on both GNU and BSD/macOS sed
sed -i.bak \
  -e "s#https://unpkg.com/react@${REACT_VER}/umd/react.development.js#vendor/react.js#" \
  -e "s#https://unpkg.com/react-dom@${REACT_VER}/umd/react-dom.development.js#vendor/react-dom.js#" \
  -e "s#https://unpkg.com/@babel/standalone@${BABEL_VER}/babel.min.js#vendor/babel.min.js#" \
  "$DIST/index.html"
rm -f "$DIST/index.html.bak"

echo ""
echo "✓ build complete → $DIST"
echo "  • node deploy   : ./run.sh dist   (or: ROOT=dist node main.js)"
echo "  • static deploy : point any static server / nginx at dist/"
