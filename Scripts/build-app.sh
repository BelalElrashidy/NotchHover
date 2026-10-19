#!/bin/bash
# Builds NotchHover.app from the SwiftPM target.
# Usage: Scripts/build-app.sh [debug|release] [--run]

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="release"
SHOULD_RUN="no"
SHOULD_INSTALL="no"

for argument in "$@"; do
    case "$argument" in
        debug|release) CONFIGURATION="$argument" ;;
        --run) SHOULD_RUN="yes" ;;
        --install) SHOULD_INSTALL="yes" ;;
        *) echo "Unknown argument: $argument" >&2; exit 1 ;;
    esac
done

APP_BUNDLE="$PROJECT_ROOT/build/NotchHover.app"
CONTENTS="$APP_BUNDLE/Contents"

cd "$PROJECT_ROOT"
swift build -c "$CONFIGURATION"
BINARY="$(swift build -c "$CONFIGURATION" --show-bin-path)/NotchHover"

# A running copy holds the old binary open, and TCC keys off the bundle path.
pkill -x NotchHover 2>/dev/null || true

rm -rf "$APP_BUNDLE"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources"

cp "$BINARY" "$CONTENTS/MacOS/NotchHover"
cp "$PROJECT_ROOT/Resources/Info.plist" "$CONTENTS/Info.plist"
# The Capstone. AppIcon.icon carries separate light, dark and tinted appearances;
# actool compiles it into Assets.car for macOS 26 and a fallback AppIcon.icns for older
# systems. A plain .icns alone would make macOS fake Dark mode by darkening the tile.
xcrun actool "$PROJECT_ROOT/Resources/AppIcon.icon" \
    --compile "$CONTENTS/Resources" \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --app-icon AppIcon \
    --output-partial-info-plist "$PROJECT_ROOT/build/AppIcon-partial.plist" >/dev/null
cp "$PROJECT_ROOT/Resources/MenuBarIcon.png" "$PROJECT_ROOT/Resources/MenuBarIcon@2x.png" "$CONTENTS/Resources/"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# The Share menu's "NotchHover": a small app extension, built outside SwiftPM — which
# has no extension targets — and signed before the app that contains it.
SHARE_SOURCE="$PROJECT_ROOT/Extensions/Share"
SHARE_BUNDLE="$CONTENTS/PlugIns/NotchHoverShare.appex"
mkdir -p "$SHARE_BUNDLE/Contents/MacOS"
OPTIMIZE="-Onone"; [ "$CONFIGURATION" = "release" ] && OPTIMIZE="-O"
xcrun swiftc $OPTIMIZE -module-name NotchHoverShare -parse-as-library -application-extension \
    -target "$(uname -m)-apple-macos14.0" -sdk "$(xcrun --show-sdk-path)" \
    -Xlinker -e -Xlinker _NSExtensionMain \
    "$SHARE_SOURCE/ShareViewController.swift" -o "$SHARE_BUNDLE/Contents/MacOS/NotchHoverShare"
cp "$SHARE_SOURCE/Info.plist" "$SHARE_BUNDLE/Contents/Info.plist"
# Same version as the app it ships in.
for key in CFBundleShortVersionString CFBundleVersion; do
    value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$CONTENTS/Info.plist")"
    /usr/libexec/PlistBuddy -c "Set :$key $value" "$SHARE_BUNDLE/Contents/Info.plist"
done
codesign --force --sign - --entitlements "$SHARE_SOURCE/Share.entitlements" \
    --identifier com.notchhover.NotchHover.Share "$SHARE_BUNDLE"

codesign --force --sign - --identifier com.notchhover.NotchHover "$APP_BUNDLE"

echo "Built $APP_BUNDLE ($CONFIGURATION)"

INSTALLED_APP="/Applications/NotchHover.app"

if [ "$SHOULD_INSTALL" = "yes" ]; then
    rm -rf "$INSTALLED_APP"
    cp -R "$APP_BUNDLE" "$INSTALLED_APP"
    # Re-sign in place: macOS ties permissions to the installed copy, not the build one.
    codesign --force --sign - --identifier com.notchhover.NotchHover "$INSTALLED_APP"
    echo "Installed $INSTALLED_APP"
fi

if [ "$SHOULD_RUN" = "yes" ]; then
    if [ "$SHOULD_INSTALL" = "yes" ]; then
        open "$INSTALLED_APP"
    else
        open "$APP_BUNDLE"
    fi
    echo "Launched NotchHover — rest the pointer on the notch."
fi
