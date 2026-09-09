#!/bin/zsh
set -euo pipefail

projectRoot="${0:A:h:h}"
cd "$projectRoot"
swift run -c release -- --benchmark-window-catalog
