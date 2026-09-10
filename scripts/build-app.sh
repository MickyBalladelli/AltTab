#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
BUILD_DIR="$PROJECT_ROOT/build"
APP_DIR="$BUILD_DIR/AltTab.app"
TRASH_DIR="$PROJECT_ROOT/Trash"
VERSION="${ALT_TAB_VERSION:-0.1.0}"
BUILD_NUMBER="${ALT_TAB_BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}"
SIGNING_IDENTITY="${ALT_TAB_SIGNING_IDENTITY:-}"

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(security find-identity -v -p codesigning \
    | sed -n 's/.*"\(Apple Development:.*\)"/\1/p' \
    | head -n 1)"
fi

if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="-"
fi

cd "$PROJECT_ROOT"
swift build -c release
swift scripts/generate-icon.swift

if [[ -e "$APP_DIR" ]]; then
  mkdir -p "$TRASH_DIR"
  mv "$APP_DIR" "$TRASH_DIR/AltTab.app.$(date +%Y%m%d%H%M%S)"
fi
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_ROOT/.build/release/AltTab" "$APP_DIR/Contents/MacOS/AltTab"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$PROJECT_ROOT/Resources/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_DIR/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/AltTab"

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  codesign --force --deep --sign - "$APP_DIR" >/dev/null
else
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_DIR" >/dev/null
fi
codesign --verify --deep --strict "$APP_DIR"
printf 'Created %s (%s, build %s, signer %s)\n' "$APP_DIR" "$VERSION" "$BUILD_NUMBER" "$SIGNING_IDENTITY"
