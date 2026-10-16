#!/usr/bin/env bash
# test_terminal_only.sh — Socket discovery excludes headless/GUI hook targets.

setup_test_project
start_nvim

test_terminal_only_rejects_headless_target() {
  nvim_exec "require('code-preview').config.hooks.terminal_only = true"

  local verdict
  verdict="$({
    NVIM_LISTEN_ADDRESS="$TEST_SOCKET" bash -c '
      source "$1" "$2"
      if _is_hook_target "$3"; then
        printf "eligible"
      else
        printf "rejected"
      fi
    ' _ "$REPO_ROOT/bin/nvim-socket.sh" "$TEST_PROJECT_DIR" "$TEST_SOCKET"
  } 2>/dev/null)"

  assert_eq "rejected" "$verdict" "terminal_only should reject a headless Neovim socket"
}

run_test "terminal_only rejects a headless Neovim socket" test_terminal_only_rejects_headless_target

stop_nvim
cleanup_test_project
