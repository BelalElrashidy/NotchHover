#!/bin/bash
# Dev loop: rebuild, install, relaunch, and follow the app's log.
# Usage: Scripts/dev.sh [--no-log]

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$PROJECT_ROOT/Scripts/build-app.sh" release --install --run

[ "${1:-}" = "--no-log" ] && exit 0

echo
echo "Following the log — ctrl-C to stop."
log stream --predicate 'subsystem == "com.notchhover.NotchHover"' --style compact
