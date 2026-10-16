#!/usr/bin/env bash
# test_stale_socket.sh — Tests stale socket recovery
#
# Verifies that when Neovim is killed and restarted, the hook scripts
# can still find the new instance and deliver diffs.

# ── Setup ────────────────────────────────────────────────────────

setup_test_project

# ── Test: Hook works after Neovim restart ────────────────────────

test_stale_socket_recovery() {
  # Start the first Neovim instance on a scanner-compatible socket path. The
  # hook still has to rediscover it by filesystem scan because scan mode clears
  # NVIM_LISTEN_ADDRESS before invoking the hook.
  start_nvim_on_socket "$TEST_PROJECT_DIR"
  local first_socket="$TEST_SOCKET"
  local first_pid="$NVIM_PID"

  local test_file
  test_file="$(create_test_file "src/recover.lua" 'local old = true')"

  # Verify first instance works
  local payload
  payload=$(cat <<EOF
{
  "tool_name": "Edit",
  "cwd": "$TEST_PROJECT_DIR",
  "tool_input": {
    "file_path": "$test_file",
    "old_string": "local old = true",
    "new_string": "local old = false"
  }
}
EOF
)

  run_pretool_hook "$payload" scan >/dev/null
  sleep 0.5
  local is_open
  is_open="$(nvim_eval "require('code-preview.diff').is_open()")"
  assert_eq "true" "$is_open" "diff should open on first instance" || return 1

  run_posttool_hook "$payload" scan >/dev/null
  sleep 0.3

  local daemon_pid
  daemon_pid="$(nvim_eval "vim.fn.jobpid(require('code-preview').daemon_job)")"
  if [[ ! "$daemon_pid" =~ ^[0-9]+$ ]] || (( daemon_pid <= 0 )); then
    echo "  FAIL: previewd should be running before Neovim crashes" >&2
    return 1
  fi

  # Kill Neovim without cleaning the socket, simulating a stale socket entry.
  crash_nvim
  assert_file_exists "$first_socket" "old socket should remain on disk after crash" || return 1
  if kill -0 "$first_pid" 2>/dev/null; then
    echo "  FAIL: stale Neovim PID should be dead" >&2
    return 1
  fi

  local tries=0
  while kill -0 "$daemon_pid" 2>/dev/null && (( tries < 30 )); do
    sleep 0.1
    tries=$((tries + 1))
  done
  if kill -0 "$daemon_pid" 2>/dev/null; then
    echo "  FAIL: previewd should exit after Neovim RPC disconnects" >&2
    kill "$daemon_pid" 2>/dev/null || true
    return 1
  fi

  # Start a fresh Neovim instance. Each launch uses a PID-derived socket path,
  # so the new socket will differ from the crashed one.
  start_nvim_on_socket "$TEST_PROJECT_DIR"
  local second_socket="$TEST_SOCKET"
  if [[ "$first_socket" == "$second_socket" ]]; then
    echo "  FAIL: restart should use a different socket path" >&2
    return 1
  fi

  # The hook should rediscover the live socket by scanning, not by trusting a
  # fixed environment variable.
  local payload2
  payload2=$(cat <<EOF
{
  "tool_name": "Edit",
  "cwd": "$TEST_PROJECT_DIR",
  "tool_input": {
    "file_path": "$test_file",
    "old_string": "local old = true",
    "new_string": "local new = true"
  }
}
EOF
)

  run_pretool_hook "$payload2" scan >/dev/null
  sleep 0.5

  local is_open2
  is_open2="$(nvim_eval "require('code-preview.diff').is_open()")"
  assert_eq "true" "$is_open2" "diff should open on second (restarted) instance" || return 1

  run_posttool_hook "$payload2" scan >/dev/null
  sleep 0.3
}

# ── Test: Hook refuses a live Neovim from another project ──

test_no_matching_project_nvim_graceful() {
  # Keep one responsive Neovim available, but register it for TEST_PROJECT_DIR.
  # A hook from another project must abstain instead of using that live socket.
  stop_nvim
  start_nvim_on_socket "$TEST_PROJECT_DIR"
  local unrelated_cwd="/tmp/nonexistent-project-$$"
  reset_test_state

  local hook_tmpdir
  hook_tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/claude-test-no-nvim-tmp.XXXXXX")"

  local payload
  payload=$(cat <<EOF
{
  "tool_name": "Edit",
  "cwd": "$unrelated_cwd",
  "tool_input": {
    "file_path": "$unrelated_cwd/src/noserver.lua",
    "old_string": "hi",
    "new_string": "bye"
  }
}
EOF
)

  local selected
  selected="$({
    NVIM_LISTEN_ADDRESS="$TEST_SOCKET" bash -c '
      source "$1" "$2" "$3"
      printf "%s" "${NVIM_SOCKET:-}"
    ' _ "$REPO_ROOT/bin/nvim-socket.sh" "$unrelated_cwd" "$unrelated_cwd/src/noserver.lua"
  } 2>/dev/null)"
  assert_eq "" "$selected" "explicit socket from another project must be rejected" || return 1

  # Scan mode must also abstain and leave the unrelated Neovim untouched.
  local exit_code=0
  echo "$payload" | \
    NVIM_LISTEN_ADDRESS= \
    TMPDIR="$hook_tmpdir" \
    bash "$REPO_ROOT/bin/hook-entry.sh" claudecode pre >/dev/null 2>&1 || exit_code=$?

  # The hook exits 0 on non-crash paths, including when it cannot identify a
  # project-specific nvim instance.
  assert_eq "0" "$exit_code" "hook must exit 0 without a guaranteed project nvim match" || return 1

  local is_open
  is_open="$(nvim_eval "require('code-preview.diff').is_open()")"
  assert_eq "false" "$is_open" "unrelated Neovim must not open a preview" || return 1

  # Per ADR-0005 (issue #47 phase 3), the hook abstains entirely when no
  # Neovim is reachable: no proposed file is computed, no stdout, exit 0.
  # The pre-phase-3 bash core also wrote a proposed temp file in this case
  # as a side effect of spawning `nvim --headless -l apply-edit.lua`; we
  # no longer do that. Claude Code falls back to its native flow as if the
  # plugin weren't installed.
  rm -rf "$hook_tmpdir"
}

# ── Run all tests ────────────────────────────────────────────────

run_test "Hook works after Neovim restart (stale socket)" test_stale_socket_recovery
run_test "Hook refuses a live Neovim from another project" test_no_matching_project_nvim_graceful

# ── Teardown ─────────────────────────────────────────────────────

stop_nvim
cleanup_test_project
