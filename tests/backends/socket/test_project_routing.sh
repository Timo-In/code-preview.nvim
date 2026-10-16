#!/usr/bin/env bash
# test_project_routing.sh — Socket discovery stays within the hook project.

setup_test_project
PROJECT_A="$TEST_PROJECT_DIR"
PROJECT_B="$(mktemp -d /tmp/code-preview-test-project-b.XXXXXX)"
PROJECT_B="$(cd "$PROJECT_B" && pwd -P)"

start_nvim_on_socket "$PROJECT_A"
SOCKET_A="$TEST_SOCKET"
PID_A="$NVIM_PID"

start_nvim_on_socket "$PROJECT_B"
SOCKET_B="$TEST_SOCKET"
PID_B="$NVIM_PID"

find_for_project() {
  local project_cwd="$1"
  local target_file="$2"
  NVIM_LISTEN_ADDRESS= bash -c '
    source "$1" "$2" "$3"
    printf "%s" "${NVIM_SOCKET:-}"
  ' _ "$REPO_ROOT/bin/nvim-socket.sh" "$project_cwd" "$target_file" 2>/dev/null
}

test_routes_each_project_to_its_own_instance() {
  local selected_a selected_b
  selected_a="$(find_for_project "$PROJECT_A" "$PROJECT_A/src/a.lua")"
  selected_b="$(find_for_project "$PROJECT_B" "$PROJECT_B/src/b.lua")"

  assert_eq "$SOCKET_A" "$selected_a" "project A must select the project A Neovim" || return 1
  assert_eq "$SOCKET_B" "$selected_b" "project B must select the project B Neovim" || return 1
}

test_abstains_without_a_matching_instance() {
  local unrelated selected
  unrelated="/tmp/code-preview-unrelated-$$"
  selected="$(find_for_project "$unrelated" "$unrelated/src/missing.lua")"
  assert_eq "" "$selected" "socket discovery must abstain without a project match"
}

run_test "two projects route to their own Neovim instances" test_routes_each_project_to_its_own_instance
run_test "socket discovery abstains without a project match" test_abstains_without_a_matching_instance

for socket in "$SOCKET_A" "$SOCKET_B"; do
  nvim --server "$socket" --remote-expr "execute('qall!')" >/dev/null 2>&1 || true
done
for pid in "$PID_A" "$PID_B"; do
  if kill -0 "$pid" 2>/dev/null; then kill -9 "$pid" 2>/dev/null || true; fi
done
rm -f "$SOCKET_A" "$SOCKET_B"
rm -rf "$PROJECT_A" "$PROJECT_B"
TEST_PROJECT_DIR=""
TEST_SOCKET=""
NVIM_PID=""
