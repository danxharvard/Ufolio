#!/bin/bash
# Signs rules/youtube-ads.js so installed copies of Ufolio will use it (they refuse it otherwise).
# Bump the "Version:" number on its first line first: Ufolio only takes a newer copy.
#   ./scripts/sign-youtube-ads.sh   → writes rules/youtube-ads.js.sig
set -euo pipefail
cd "$(dirname "$0")/.."
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
printf 'ufolio-youtube-ads\n' > "$TMP"
cat rules/youtube-ads.js >> "$TMP"
HUSH_UPDATE_KEY="$(cat ~/.hush-update-signing-key)" swift scripts/sign-update.swift "$TMP" > rules/youtube-ads.js.sig
echo "Signed rules/youtube-ads.js (version $(grep -o 'Version: [0-9]*' rules/youtube-ads.js | head -1 | cut -d' ' -f2))"
