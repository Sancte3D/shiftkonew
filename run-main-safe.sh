#!/usr/bin/env bash
set -euo pipefail

PD_BIN="/Users/mrmouse/Desktop/Pd-0.56-2.app/Contents/Resources/bin/pd"
PATCH="/Users/mrmouse/Developer/shiftkonew/shiftko-main.pd"

# Safe audio start:
# - noadc: no input device required
# - audiooutdev 2: Mac mini speakers (from listdev)
# - audiobuf 50: larger buffer to avoid dropouts
# - blocksize 256: more stable scheduling on busy systems
exec "$PD_BIN" -noadc -audiooutdev 2 -audiobuf 50 -blocksize 256 -open "$PATCH"
