#!/usr/bin/env bash
# test_install.sh — Antigravity (AGY) hook install/uninstall tests

# ── Setup ────────────────────────────────────────────────────────

setup_test_project
start_nvim

# Isolate global hooks path so tests never touch real ~/.gemini/config/hooks.json
GLOBAL_AGY_HOOKS="$TEST_PROJECT_DIR/isolated_global_hooks.json"
nvim_exec "vim.env.CODE_PREVIEW_AGY_GLOBAL_HOOKS = '$GLOBAL_AGY_HOOKS'"
nvim_exec "vim.cmd('cd $TEST_PROJECT_DIR')"

# ── Test: Install AGY hooks (local) ──────────────────────────────

test_install_agy_hooks() {
  rm -rf "$TEST_PROJECT_DIR/.agents"
  nvim_exec "require('code-preview.backends.agy').install('local')"
  sleep 0.2

  local hooks_file="$TEST_PROJECT_DIR/.agents/hooks.json"
  assert_file_exists "$hooks_file" ".agents/hooks.json should be created" || return 1

  local content
  content="$(cat "$hooks_file")"

  assert_contains "$content" '"code-preview"' "should use top-level code-preview named hook" || return 1
  assert_contains "$content" "PreToolUse" "should have PreToolUse hook" || return 1
  assert_contains "$content" "PostToolUse" "should have PostToolUse hook" || return 1
  assert_contains "$content" "hook-entry.sh" "should reference the generic hook-entry shim" || return 1
  assert_contains "$content" "agy pre" "PreToolUse should pass agy pre" || return 1
  assert_contains "$content" "agy post" "PostToolUse should pass agy post" || return 1
  assert_contains "$content" "replace_file_content|multi_replace_file_content|write_to_file|run_command" "should match AGY editing/command tools" || return 1

  local state
  state="$(nvim_eval "require('code-preview.backends.agy').install_state().state")"
  assert_eq "installed (local)" "$state" "install_state should report installed (local)" || return 1
}

# ── Test: Uninstall AGY hooks removes our block cleanly ──────────

test_uninstall_agy_hooks() {
  nvim_exec "require('code-preview.backends.agy').install('local')"
  sleep 0.2

  nvim_exec "require('code-preview.backends.agy').uninstall('local')"
  sleep 0.2

  local hooks_file="$TEST_PROJECT_DIR/.agents/hooks.json"
  assert_file_exists "$hooks_file" "hooks.json should still exist" || return 1

  local content
  content="$(cat "$hooks_file")"
  assert_not_contains "$content" "hook-entry.sh" "hook-entry shim should be removed" || return 1

  local state
  state="$(nvim_eval "require('code-preview.backends.agy').install_state().state")"
  assert_eq "missing" "$state" "install_state should report missing after uninstall" || return 1
}

# ── Test: Install is idempotent (no duplicate hooks) ─────────────

test_install_idempotent() {
  nvim_exec "require('code-preview.backends.agy').install('local')"
  nvim_exec "require('code-preview.backends.agy').install('local')"
  sleep 0.2

  local hooks_file="$TEST_PROJECT_DIR/.agents/hooks.json"
  local content
  content="$(cat "$hooks_file")"

  local count
  count="$(echo "$content" | grep -o "agy pre" | wc -l | tr -d ' ')"
  assert_eq "1" "$count" "should have exactly one PreToolUse hook entry" || return 1
}

# ── Test: Merge & uninstall preserve existing third-party hooks ──

test_merge_and_uninstall_preserve_other_hooks() {
  mkdir -p "$TEST_PROJECT_DIR/.agents"
  cat > "$TEST_PROJECT_DIR/.agents/hooks.json" <<'JSON'
{
  "lint-checker": {
    "PostToolUse": [
      {
        "matcher": "run_command",
        "hooks": [{ "type": "command", "command": "./scripts/lint.sh" }]
      }
    ]
  },
  "safety-gate": {
    "enabled": false,
    "PreToolUse": [
      {
        "matcher": "run_command",
        "hooks": [{ "type": "command", "command": "./scripts/safety-check.sh" }]
      }
    ]
  }
}
JSON

  # 1. Install should merge without clobbering lint-checker or safety-gate
  nvim_exec "require('code-preview.backends.agy').install('local')"
  sleep 0.2

  local content_after_install
  content_after_install="$(cat "$TEST_PROJECT_DIR/.agents/hooks.json")"

  assert_contains "$content_after_install" "lint-checker" "lint-checker should be preserved after install" || return 1
  assert_contains "$content_after_install" "./scripts/lint.sh" "lint.sh command should be preserved after install" || return 1
  assert_contains "$content_after_install" "safety-gate" "safety-gate should be preserved after install" || return 1
  assert_contains "$content_after_install" "./scripts/safety-check.sh" "safety-check.sh should be preserved after install" || return 1
  assert_contains "$content_after_install" "agy pre" "our pre hook should be added" || return 1

  # 2. Uninstall should remove ONLY code-preview while keeping lint-checker and safety-gate intact
  nvim_exec "require('code-preview.backends.agy').uninstall('local')"
  sleep 0.2

  local content_after_uninstall
  content_after_uninstall="$(cat "$TEST_PROJECT_DIR/.agents/hooks.json")"

  assert_not_contains "$content_after_uninstall" "hook-entry.sh" "our hook should be removed on uninstall" || return 1
  assert_not_contains "$content_after_uninstall" '"code-preview"' "empty code-preview block should be removed" || return 1
  assert_contains "$content_after_uninstall" "lint-checker" "lint-checker should still be preserved after uninstall" || return 1
  assert_contains "$content_after_uninstall" "./scripts/lint.sh" "lint.sh command should still be preserved after uninstall" || return 1
  assert_contains "$content_after_uninstall" "safety-gate" "safety-gate should still be preserved after uninstall" || return 1
  assert_contains "$content_after_uninstall" "./scripts/safety-check.sh" "safety-check.sh should still be preserved after uninstall" || return 1
}

# ── Test: Invalid JSON is not overwritten ────────────────────────

test_refuses_corrupt_json() {
  mkdir -p "$TEST_PROJECT_DIR/.agents"
  printf '{ broken json' > "$TEST_PROJECT_DIR/.agents/hooks.json"

  nvim_exec "require('code-preview.backends.agy').install('local')"
  sleep 0.2

  local content
  content="$(cat "$TEST_PROJECT_DIR/.agents/hooks.json")"
  assert_eq "{ broken json" "$content" "corrupted hooks.json must not be overwritten" || return 1
  rm -f "$TEST_PROJECT_DIR/.agents/hooks.json"
}

# ── Run all tests ────────────────────────────────────────────────

run_test "AGY: install writes .agents/hooks.json" test_install_agy_hooks
run_test "AGY: uninstall removes code-preview entries" test_uninstall_agy_hooks
run_test "AGY: install is idempotent" test_install_idempotent
run_test "AGY: merge and uninstall preserve third-party hooks" test_merge_and_uninstall_preserve_other_hooks
run_test "AGY: install refuses to overwrite corrupted JSON" test_refuses_corrupt_json

# ── Teardown ─────────────────────────────────────────────────────

stop_nvim
cleanup_test_project
