#!/usr/bin/env bash
# run_lua.sh — Run plenary busted tests for core plugin modules
#
# Usage:
#   ./tests/run_lua.sh              # run all Lua spec tests
#   ./tests/run_lua.sh changes      # run specs matching "changes"

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS_DIR="$REPO_ROOT/deps"

# ── Install plenary.nvim if missing ─────────────────────────────

if [[ ! -d "$DEPS_DIR/plenary.nvim" ]]; then
  echo "Installing plenary.nvim into deps/..."
  mkdir -p "$DEPS_DIR"
  git clone --depth 1 https://github.com/nvim-lua/plenary.nvim "$DEPS_DIR/plenary.nvim" 2>/dev/null
fi

# ── Run tests ───────────────────────────────────────────────────

FILTER="${1:-}"
TEST_DIR="$REPO_ROOT/tests/plugin"
SPECS=()

while IFS= read -r spec; do
  [[ -n "$spec" ]] && SPECS+=("$spec")
done < <(find "$TEST_DIR" -name "*${FILTER}*_spec.lua" -type f 2>/dev/null | sort)

if (( ${#SPECS[@]} == 0 )); then
  echo "No spec files matched filter: ${FILTER:-<all>}"
  exit 1
fi

echo "Running ${#SPECS[@]} plugin spec file(s) in isolated Neovim processes..."
for spec in "${SPECS[@]}"; do
  echo "Running: $(basename "$spec")"
  nvim --headless --clean \
    -u "$REPO_ROOT/tests/minimal_init.lua" \
    -c "lua require('plenary.busted').run([[$spec]])" 2>&1
done
