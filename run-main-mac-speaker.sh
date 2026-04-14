#!/usr/bin/env bash
set -euo pipefail

PD_BIN="/Users/mrmouse/Desktop/Pd-0.56-2.app/Contents/Resources/bin/pd"
PATCH_DIR="/Users/mrmouse/Developer/shiftkonew"

# Device index 2 from your listdev output: Mac mini speakers
exec "$PD_BIN" -noadc -audiooutdev 2 -open "$PATCH_DIR/shiftko-main.pd"
