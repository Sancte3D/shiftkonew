#!/usr/bin/env bash
set -euo pipefail

echo "== Shift K.O. Pd setup =="

OS_NAME="$(uname -s)"
echo "Detected OS: ${OS_NAME}"

PD_DOCS_DIR="${HOME}/Documents/Pd"
EXTERNALS_DIR="${PD_DOCS_DIR}/externals"
ELSE_DIR="${EXTERNALS_DIR}/else"

mkdir -p "${EXTERNALS_DIR}"

echo "Pd externals directory:"
echo "  ${EXTERNALS_DIR}"

if [ -d "${ELSE_DIR}" ]; then
  echo
  echo "OK: ELSE already present at:"
  echo "  ${ELSE_DIR}"
else
  echo
  echo "ELSE not found yet."
  echo "Install it in Pd:"
  echo "  Help -> Find externals -> search 'else' -> Install"
fi

echo
echo "Next:"
echo "  1) Start Pure Data"
echo "  2) Open shiftko-main.pd"
echo "  3) Enable DSP (Media -> Audio On)"
