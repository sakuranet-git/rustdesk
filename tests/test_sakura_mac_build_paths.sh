#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_PY="$ROOT/build.py"

grep -Fq 'Build/Products/Release/SAKURA-Remote.app/Contents/MacOS/' "$BUILD_PY"

if grep -Fq 'Build/Products/Release/RustDesk.app' "$BUILD_PY"; then
  echo "NG: Flutter macOS build still references RustDesk.app" >&2
  exit 1
fi

echo "OK: Flutter macOS build uses SAKURA-Remote.app"
