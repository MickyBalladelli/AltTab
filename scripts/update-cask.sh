#!/bin/zsh
set -euo pipefail

if [[ $# -lt 2 ]]; then
  print -u2 "usage: update-cask.sh VERSION SHA256 [CASK_PATH]"
  exit 64
fi

VERSION="$1"
SHA256="$2"
CASK_PATH="${3:-${0:A:h:h}/Casks/alt-tab.rb}"

if [[ ! -f "$CASK_PATH" ]]; then
  print -u2 "cask not found: $CASK_PATH"
  exit 66
fi

perl -0pi -e "s/version \"[^\"]+\"/version \"$VERSION\"/; s/sha256 (?:\"[^\"]+\"|:no_check)/sha256 \"$SHA256\"/" "$CASK_PATH"
