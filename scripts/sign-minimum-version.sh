#!/bin/bash
# Signs rules/minimum-version.json, which tells installed copies the oldest version still allowed.
# Copies below it get a warning banner for three days from "since", then an update screen.
# Raise "issued" every time (copies ignore a file older than one they've seen).
#
#   {"issued": 2026120101, "stable": "0.51.8", "beta": "0.52.0-beta.8", "since": "2026-12-01T09:00:00Z"}
#
#   ./scripts/sign-minimum-version.sh [file]   → writes <file>.sig (default rules/minimum-version.json)
set -euo pipefail
cd "$(dirname "$0")/.."
FILE="${1:-rules/minimum-version.json}"
python3 -c "import json,sys; d=json.load(open('$FILE')); [d[k] for k in ('issued','stable','beta','since')]" \
  || { echo "minimum-version.json needs issued, stable, beta and since" >&2; exit 1; }
TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT
printf 'ufolio-minimum-version\n' > "$TMP"
cat "$FILE" >> "$TMP"
HUSH_UPDATE_KEY="$(cat ~/.hush-update-signing-key)" swift scripts/sign-update.swift "$TMP" > "$FILE.sig"
echo "Signed $FILE"
