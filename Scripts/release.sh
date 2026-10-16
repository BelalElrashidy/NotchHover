#!/bin/bash
# Builds the zip that gets attached to a GitHub release.
# Usage: Scripts/release.sh   → dist/NotchHover-<version>.zip, plus its SHA-256
#
# The version comes from Resources/Info.plist, so bump CFBundleShortVersionString
# there first. Note that build-app.sh quits a running copy of NotchHover.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_ROOT/Resources/Info.plist")"

"$PROJECT_ROOT/Scripts/build-app.sh" release >/dev/null

mkdir -p "$PROJECT_ROOT/dist"
ZIP="$PROJECT_ROOT/dist/NotchHover-$VERSION.zip"
rm -f "$ZIP"

# ditto, not zip: it keeps the bundle's symlinks and extended attributes intact, which
# the code signature depends on.
ditto -c -k --sequesterRsrc --keepParent "$PROJECT_ROOT/build/NotchHover.app" "$ZIP"

echo "Built $ZIP"
shasum -a 256 "$ZIP"
