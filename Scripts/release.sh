#!/bin/bash
# Builds the zip that gets attached to a GitHub release, and its release notes.
# Usage: Scripts/release.sh
#   → dist/NotchHover-<version>.zip, its SHA-256, and dist/NotchHover-<version>-notes.md
#
# The version comes from Resources/Info.plist, so bump CFBundleShortVersionString there
# first, and give it a section in CHANGELOG.md — the notes are built from that section,
# and the script stops if it is missing. Note that build-app.sh quits a running copy.
#
# Then: gh release create v<version> dist/NotchHover-<version>.zip \
#         --title "NotchHover <version>" --notes-file dist/NotchHover-<version>-notes.md

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PROJECT_ROOT/Resources/Info.plist")"

# The changelog section for this version: from its heading to the next one.
SECTION="$(awk -v v="$VERSION" '
    /^## \[/ { if (found) exit; if (index($0, "## [" v "]") == 1) { found = 1; next } }
    found && /^\[[^]]+\]: / { exit }
    found { print }
' "$PROJECT_ROOT/CHANGELOG.md")"
if [ -z "$(echo "$SECTION" | tr -d '[:space:]')" ]; then
    echo "CHANGELOG.md has no section for $VERSION — write it first." >&2
    exit 1
fi

"$PROJECT_ROOT/Scripts/build-app.sh" release >/dev/null

mkdir -p "$PROJECT_ROOT/dist"
ZIP="$PROJECT_ROOT/dist/NotchHover-$VERSION.zip"
rm -f "$ZIP"

# ditto, not zip: it keeps the bundle's symlinks and extended attributes intact, which
# the code signature depends on.
ditto -c -k --sequesterRsrc --keepParent "$PROJECT_ROOT/build/NotchHover.app" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

NOTES="$PROJECT_ROOT/dist/NotchHover-$VERSION-notes.md"
cat > "$NOTES" <<NOTES_END
$(echo "$SECTION" | sed -e 's/^### /## /')

## Install

Download **NotchHover-$VERSION.zip**, unzip it, and drag **NotchHover.app** to **Applications**, replacing any older copy. macOS blocks the first launch because the app isn't notarized yet — open **System Settings → Privacy & Security** and click **Open Anyway**, or run:

\`\`\`bash
xattr -dr com.apple.quarantine /Applications/NotchHover.app
\`\`\`

Builds aren't signed with a Developer ID yet, so macOS may ask again for permissions you had already granted.

**Requires** macOS 14 or later on Apple silicon. Every change is listed in [CHANGELOG.md](https://github.com/BelalElrashidy/NotchHover/blob/main/CHANGELOG.md).

**SHA-256** \`$SHA\`
NOTES_END

echo "Built $ZIP"
echo "$SHA  $ZIP"
echo "Notes in $NOTES"
