#!/bin/bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
[ "$#" = 2 ] || { echo "Usage: $0 App.app output.dmg" >&2; exit 64; }
APP="$1"
OUT="$2"
PYTHON="${SOURIS_INSTALLER_PYTHON:-$ROOT/.local/dmg-tools/bin/python}"
[ -x "$PYTHON" ] || {
  echo "Create .local/dmg-tools with python3 -m venv, then install scripts/installer/requirements.txt" >&2
  exit 1
}
NAME="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["name"])' "$HERE/config.json")"
SUBTITLE="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["subtitle"])' "$HERE/config.json")"
mkdir -p "$(dirname "$OUT")"
ART="$(mktemp -d "$(dirname "$OUT")/.installer-art-XXXXXX")"
trap 'rm -rf "$ART"' EXIT
for SCALE in 1 2; do
  SUFFIX=""
  [ "$SCALE" = 1 ] || SUFFIX="@${SCALE}x"
  nice -n 10 swift "$HERE/render.swift" --name "$NAME" --subtitle "$SUBTITLE" \
    --output "$ART/background$SUFFIX.png" --scale "$SCALE"
done
"$PYTHON" "$HERE/build.py" "$APP" "$ART/background.png" "$OUT"
hdiutil verify "$OUT"
"$PYTHON" "$HERE/check.py" "$OUT"
