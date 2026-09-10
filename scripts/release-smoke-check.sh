#!/bin/zsh
set -euo pipefail

PROJECT_ROOT="${0:A:h:h}"
DMG_PATH="${1:-$PROJECT_ROOT/build/AltTab.dmg}"
CASK_PATH="${2:-$PROJECT_ROOT/Casks/alt-tab.rb}"
VERSION="${3:-${ALT_TAB_VERSION:-}}"
REMOTE_CHECK="${4:-}"
TRASH_DIR="$PROJECT_ROOT/Trash"

if [[ -z "$VERSION" ]]; then
  print -u2 "usage: release-smoke-check.sh DMG_PATH CASK_PATH VERSION [--remote]"
  exit 64
fi
if [[ ! -f "$DMG_PATH" ]]; then
  print -u2 "DMG not found: $DMG_PATH"
  exit 66
fi
if [[ ! -f "$DMG_PATH.sha256" ]]; then
  print -u2 "checksum not found: $DMG_PATH.sha256"
  exit 66
fi
if [[ ! -f "$CASK_PATH" ]]; then
  print -u2 "cask not found: $CASK_PATH"
  exit 66
fi

CHECKSUM="$(awk 'NR == 1 { print $1 }' "$DMG_PATH.sha256")"
ACTUAL_CHECKSUM="$(shasum -a 256 "$DMG_PATH" | awk '{ print $1 }')"
[[ "$CHECKSUM" == "$ACTUAL_CHECKSUM" ]] || {
  print -u2 "checksum mismatch"
  exit 1
}

EXPECTED_URL="https://github.com/MickyBalladelli/AltTab/releases/download/v${VERSION}/AltTab.dmg"
rg -Fq "version \"${VERSION}\"" "$CASK_PATH" || {
  print -u2 "cask version does not match $VERSION"
  exit 1
}
if ! rg -Fq "$EXPECTED_URL" "$CASK_PATH" && ! rg -Fq 'https://github.com/MickyBalladelli/AltTab/releases/download/v#{version}/AltTab.dmg' "$CASK_PATH"; then
  print -u2 "cask URL does not match $EXPECTED_URL"
  exit 1
fi
rg -Fq 'app "AltTab.app"' "$CASK_PATH" || {
  print -u2 "cask app stanza is missing"
  exit 1
}
rg -Fq 'zap trash:' "$CASK_PATH" || {
  print -u2 "cask uninstall cleanup stanza is missing"
  exit 1
}
CASK_CHECKSUM="$(sed -n 's/^[[:space:]]*sha256 "\([0-9a-fA-F]*\)".*/\1/p' "$CASK_PATH" | head -1)"
[[ "$CASK_CHECKSUM" == "$CHECKSUM" ]] || {
  print -u2 "cask checksum does not match the DMG"
  exit 1
}

if [[ "$REMOTE_CHECK" == "--remote" ]]; then
  curl --fail --silent --show-error --location --head --retry 2 "$EXPECTED_URL" >/dev/null
fi

SMOKE_ROOT="$(mktemp -d -t alt-tab-release-smoke)"
MOUNT_POINT="$SMOKE_ROOT/mount"
INSTALL_ROOT="$SMOKE_ROOT/Applications"
MOUNTED=0

cleanup() {
  if [[ "$MOUNTED" == 1 ]]; then
    hdiutil detach "$MOUNT_POINT" >/dev/null 2>&1 || true
  fi
  if [[ -d "$SMOKE_ROOT" ]]; then
    mkdir -p "$TRASH_DIR"
    mv "$SMOKE_ROOT" "$TRASH_DIR/release-smoke.$(date +%Y%m%d%H%M%S)"
  fi
}
trap cleanup EXIT INT TERM

mkdir -p "$MOUNT_POINT" "$INSTALL_ROOT"
hdiutil attach -nobrowse -readonly -mountpoint "$MOUNT_POINT" "$DMG_PATH" >/dev/null
MOUNTED=1

APP_PATH="$MOUNT_POINT/AltTab.app"
[[ -d "$APP_PATH" ]] || {
  print -u2 "AltTab.app is missing from the DMG"
  exit 1
}
codesign --verify --deep --strict "$APP_PATH"
spctl --assess --type execute --context context:primary-signature "$APP_PATH"

cp -R "$APP_PATH" "$INSTALL_ROOT/AltTab.app"
[[ -x "$INSTALL_ROOT/AltTab.app/Contents/MacOS/AltTab" ]] || {
  print -u2 "installed app executable is missing"
  exit 1
}

UNINSTALL_TRASH="$TRASH_DIR/release-smoke-uninstall.$(date +%Y%m%d%H%M%S)"
mkdir -p "$UNINSTALL_TRASH"
mv "$INSTALL_ROOT/AltTab.app" "$UNINSTALL_TRASH/AltTab.app"
[[ ! -e "$INSTALL_ROOT/AltTab.app" ]] || {
  print -u2 "uninstall path left the app behind"
  exit 1
}

print "Release smoke checks passed for AltTab $VERSION"
