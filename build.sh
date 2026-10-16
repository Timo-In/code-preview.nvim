#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUTPUT_PATH="$SCRIPT_DIR/bin/previewd"

if ! command -v go >/dev/null 2>&1; then
  echo "Error: Go is required to build previewd." >&2
  exit 1
fi

mkdir -p "$SCRIPT_DIR/bin"

echo "Building previewd..."
(
  cd "$SCRIPT_DIR"
  go build -trimpath -o "$OUTPUT_PATH" ./cmd/previewd
)
echo "Built $OUTPUT_PATH"
