#!/usr/bin/env bash
# test_edit.sh — E2E tests for Antigravity (AGY) PreToolUse/PostToolUse hook lifecycle

# ── Setup ────────────────────────────────────────────────────────

setup_test_project
start_nvim
nvim_exec "require('code-preview').config.diff.auto_close = true"

run_agy_pre() {
  local json_payload="$1"
  printf '%s' "$json_payload" | NVIM_LISTEN_ADDRESS="$TEST_SOCKET" bash "$REPO_ROOT/bin/hook-entry.sh" agy pre 2>/dev/null
}

run_agy_post() {
  local json_payload="$1"
  printf '%s' "$json_payload" | NVIM_LISTEN_ADDRESS="$TEST_SOCKET" bash "$REPO_ROOT/bin/hook-entry.sh" agy post 2>/dev/null
}

# ── Test: replace_file_content opens diff and post closes it ─────

test_agy_replace_file_content() {
  reset_test_state
  local test_file
  test_file="$(create_test_file "src/hello.lua" 'print("hello world")')"

  local payload
  payload=$(cat <<EOF
{
  "conversationId": "conv-1",
  "workspacePaths": ["$TEST_PROJECT_DIR"],
  "stepIdx": 1,
  "toolCall": {
    "name": "replace_file_content",
    "args": {
      "TargetFile": "$test_file",
      "TargetContent": "hello world",
      "ReplacementContent": "hello agy",
      "AllowMultiple": false,
      "StartLine": 1,
      "EndLine": 1
    }
  }
}
EOF
)

  local output
  output="$(run_agy_pre "$payload")"

  local expected='{"decision":"ask","reason":"Diff preview sent to Neovim. Review before accepting."}'
  assert_eq "$expected" "$output" "AGY PreToolUse should return decision=ask" || return 1

  sleep 0.4

  local is_open
  is_open="$(nvim_eval "require('code-preview.diff').is_open()")"
  assert_eq "true" "$is_open" "diff should be open after replace_file_content PreToolUse" || return 1

  local change_status
  change_status="$(nvim_eval "require('code-preview.changes').get('$test_file')")"
  assert_eq "modified" "$change_status" "file should be marked as modified" || return 1

  local post_out
  post_out="$(run_agy_post "$payload")"
  assert_eq "{}" "$post_out" "AGY PostToolUse should return {}" || return 1

  sleep 0.4

  local is_open_after
  is_open_after="$(nvim_eval "require('code-preview.diff').is_open()")"
  assert_eq "false" "$is_open_after" "diff should be closed after PostToolUse" || return 1
}

# ── Test: multi_replace_file_content applies multiple chunks ─────

test_agy_multi_replace_file_content() {
  reset_test_state
  local test_file
  test_file="$(create_test_file "src/multi.lua" $'local a = 1\nlocal b = 2\nreturn a + b')"

  local payload
  payload=$(cat <<EOF
{
  "conversationId": "conv-2",
  "workspacePaths": ["$TEST_PROJECT_DIR"],
  "stepIdx": 2,
  "toolCall": {
    "name": "multi_replace_file_content",
    "args": {
      "TargetFile": "$test_file",
      "ReplacementChunks": [
        { "TargetContent": "local a = 1", "ReplacementContent": "local a = 10", "AllowMultiple": false },
        { "TargetContent": "local b = 2", "ReplacementContent": "local b = 20", "AllowMultiple": false }
      ]
    }
  }
}
EOF
)

  local output
  output="$(run_agy_pre "$payload")"
  local expected='{"decision":"ask","reason":"Diff preview sent to Neovim. Review before accepting."}'
  assert_eq "$expected" "$output" "AGY multi_replace_file_content should return decision=ask" || return 1

  sleep 0.4

  local proposed
  proposed="$(ls -1t "${TMPDIR:-/tmp}"/code-preview-diff-proposed-* 2>/dev/null | head -1)"
  assert_file_exists "$proposed" "proposed temp file should exist" || return 1
  local proposed_content
  proposed_content="$(cat "$proposed")"
  assert_contains "$proposed_content" "local a = 10" "proposed file should contain chunk 1" || return 1
  assert_contains "$proposed_content" "local b = 20" "proposed file should contain chunk 2" || return 1

  run_agy_post "$payload" >/dev/null
  sleep 0.3
}

# ── Test: write_to_file skips internal artifacts ─────────────────

test_agy_skips_artifact_write() {
  reset_test_state
  local payload
  payload=$(cat <<EOF
{
  "conversationId": "conv-3",
  "workspacePaths": ["$TEST_PROJECT_DIR"],
  "artifactDirectoryPath": "$TEST_PROJECT_DIR/.gemini_artifacts",
  "stepIdx": 3,
  "toolCall": {
    "name": "write_to_file",
    "args": {
      "TargetFile": "$TEST_PROJECT_DIR/.gemini_artifacts/plan.md",
      "CodeContent": "# Plan\n",
      "Overwrite": true,
      "ArtifactMetadata": {
        "Summary": "plan",
        "UserFacing": true,
        "RequestFeedback": true
      }
    }
  }
}
EOF
)

  local output
  output="$(run_agy_pre "$payload")"
  assert_eq '{"decision":"allow"}' "$output" "Artifact write_to_file should return decision=allow without gating" || return 1

  sleep 0.3
  local is_open
  is_open="$(nvim_eval "require('code-preview.diff').is_open()")"
  assert_eq "false" "$is_open" "diff should not open for internal artifact" || return 1
}

# ── Test: Abstain when Neovim is unreachable still emits valid JSON

test_agy_abstain_emits_valid_json() {
  local payload='{"workspacePaths":["/nonexistent/project"],"toolCall":{"name":"replace_file_content","args":{"TargetFile":"/nonexistent/project/a.lua","TargetContent":"a","ReplacementContent":"b"}}}'

  local pre_out
  pre_out="$(printf '%s' "$payload" | NVIM_LISTEN_ADDRESS="/tmp/nonexistent-nvim.sock" bash "$REPO_ROOT/bin/hook-entry.sh" agy pre 2>/dev/null)"
  assert_eq '{"decision":"allow"}' "$pre_out" "AGY pre abstain must return valid JSON allow" || return 1

  local post_out
  post_out="$(printf '%s' "$payload" | NVIM_LISTEN_ADDRESS="/tmp/nonexistent-nvim.sock" bash "$REPO_ROOT/bin/hook-entry.sh" agy post 2>/dev/null)"
  assert_eq '{}' "$post_out" "AGY post abstain must return valid JSON {}" || return 1
}

# ── Run all tests ────────────────────────────────────────────────

run_test "AGY: replace_file_content opens diff and post closes it" test_agy_replace_file_content
run_test "AGY: multi_replace_file_content applies chunks" test_agy_multi_replace_file_content
run_test "AGY: write_to_file skips internal artifacts" test_agy_skips_artifact_write
run_test "AGY: abstain emits valid JSON on pre and post" test_agy_abstain_emits_valid_json

# ── Teardown ─────────────────────────────────────────────────────

stop_nvim
cleanup_test_project
