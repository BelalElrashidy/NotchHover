#!/bin/bash
# Fast feedback without launching: compile, then run both self-tests.
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

swift build -c release
"$PROJECT_ROOT/Scripts/build-app.sh" release >/dev/null

PREVIEW_DIR="${1:-$PROJECT_ROOT/build/previews}"
mkdir -p "$PREVIEW_DIR"

echo "== panel previews =="
./build/NotchHover.app/Contents/MacOS/NotchHover --render-preview "$PREVIEW_DIR" | tail -3

echo "== settings self-test =="
./build/NotchHover.app/Contents/MacOS/NotchHover --settings-selftest 2>&1 >/dev/null &
PID=$!
sleep 12
kill -9 $PID 2>/dev/null || true

echo
echo "Previews in $PREVIEW_DIR"
