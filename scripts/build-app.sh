#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
BUILD_DIR="$PROJECT_ROOT/build"
APP_DIR="$BUILD_DIR/AltTab.app"

cd "$PROJECT_ROOT"
swift build -c release

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_ROOT/.build/release/AltTab" "$APP_DIR/Contents/MacOS/AltTab"
cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/AltTab"

codesign --force --deep --sign - "$APP_DIR" >/dev/null
printf 'Created %s\n' "$APP_DIR"
