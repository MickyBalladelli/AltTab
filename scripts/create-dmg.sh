#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
BUILD_DIR="$PROJECT_ROOT/build"
APP_DIR="$BUILD_DIR/AltTab.app"
STAGE_DIR="$BUILD_DIR/dmg-staging"
DMG_PATH="$BUILD_DIR/AltTab.dmg"
TRASH_DIR="$PROJECT_ROOT/Trash"
VERSION="${ALT_TAB_VERSION:-0.1.0}"
BUILD_NUMBER="${ALT_TAB_BUILD_NUMBER:-$(date +%Y%m%d%H%M%S)}"
SIGNING_IDENTITY="${ALT_TAB_SIGNING_IDENTITY:--}"

cd "$PROJECT_ROOT"
ALT_TAB_VERSION="$VERSION" \
ALT_TAB_BUILD_NUMBER="$BUILD_NUMBER" \
ALT_TAB_SIGNING_IDENTITY="$SIGNING_IDENTITY" \
"$PROJECT_ROOT/scripts/build-app.sh"

if [[ -e "$STAGE_DIR" ]]; then
  mkdir -p "$TRASH_DIR"
  mv "$STAGE_DIR" "$TRASH_DIR/dmg-staging.$(date +%Y%m%d%H%M%S)"
fi
if [[ -e "$DMG_PATH" ]]; then
  mkdir -p "$TRASH_DIR"
  mv "$DMG_PATH" "$TRASH_DIR/AltTab.dmg.$(date +%Y%m%d%H%M%S)"
fi

mkdir -p "$STAGE_DIR"
cp -R "$APP_DIR" "$STAGE_DIR/AltTab.app"
ln -s /Applications "$STAGE_DIR/Applications"

hdiutil create \
  -volname "AltTab $VERSION" \
  -srcfolder "$STAGE_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

mkdir -p "$TRASH_DIR"
mv "$STAGE_DIR" "$TRASH_DIR/dmg-staging.$(date +%Y%m%d%H%M%S)"
shasum -a 256 "$DMG_PATH" | tee "$DMG_PATH.sha256"
printf 'Created %s\n' "$DMG_PATH"
