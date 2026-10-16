#!/usr/bin/env bash
# nvim-socket.sh — Discovers the running Neovim's RPC socket path.
#
# Usage:
#   source bin/nvim-socket.sh [project_cwd]
#   echo "$NVIM_SOCKET"
#
# If project_cwd is provided, only returns a Neovim instance that identifies
# itself as belonging to that project. No match means no RPC target.
#
# Sets NVIM_SOCKET to the path of a valid, responsive Neovim socket.

_NVIM_SOCKET_CWD="${1:-${PWD:-}}"
_NVIM_TARGET_FILE="${2:-}"

# Check if a process (or its parent TUI process) is stopped/suspended (STAT contains T)
_is_pid_suspended() {
  local pid=$1
  local state ppid pstate
  state="$(ps -o state= -p "$pid" 2>/dev/null || true)"
  if [[ "$state" =~ T ]]; then
    return 0
  fi
  ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ' || true)"
  if [[ -n "$ppid" && "$ppid" -gt 1 ]]; then
    pstate="$(ps -o state= -p "$ppid" 2>/dev/null || true)"
    if [[ "$pstate" =~ T ]]; then
      return 0
    fi
  fi
  return 1
}

# Get the cwd of a process by PID (macOS + Linux compatible)
_get_pid_cwd() {
  local pid=$1
  if [[ -d "/proc/$pid/cwd" ]]; then
    readlink "/proc/$pid/cwd" 2>/dev/null || true
  else
    lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | grep '^n/' | head -1 | cut -c2- || true
  fi
}

# A responsive socket is not necessarily an eligible hook target: it may be a
# GUI/headless Neovim or an instance for a different project. Project values are
# passed as luaeval arguments, never interpolated into Lua source.
_is_hook_target() {
  local socket=$1
  local project_cwd="${2:-}"
  local target_file="${3:-}"
  local enabled
  if [[ -n "$project_cwd" ]]; then
    local args
    args="$(jq -cn --arg cwd "$project_cwd" --arg target "$target_file" \
      '[$cwd, $target]' 2>/dev/null || true)"
    [[ -n "$args" ]] || return 1
    enabled="$(nvim --server "$socket" --remote-expr \
      "luaeval(\"(function() local h=require('code-preview.hook_target'); return h.is_enabled() and h.matches_project(_A[1], _A[2]) and 1 or 0 end)()\", $args)" \
      2>/dev/null || true)"
  else
    enabled="$(nvim --server "$socket" --remote-expr \
      "luaeval(\"require('code-preview.hook_target').is_enabled() and 1 or 0\")" \
      2>/dev/null || true)"
  fi
  [[ "$enabled" == "1" ]]
}

find_nvim_socket() {
  # Disable errexit locally — this function is often sourced from scripts
  # that use set -euo pipefail, and we don't want dead processes or empty
  # globs to abort execution.
  local _oldopts
  _oldopts="$(set +o)"  # save all current set options
  set +e +o pipefail

  local project_cwd="${1:-${PWD:-}}"
  local target_file="${2:-}"
  local result=""

  # 1. Check explicit env var first — verify the socket is actually responsive
  if [[ -n "${NVIM_LISTEN_ADDRESS:-}" ]] && [[ -S "$NVIM_LISTEN_ADDRESS" ]]; then
    if _is_hook_target "$NVIM_LISTEN_ADDRESS" "$project_cwd" "$target_file"; then
      result="$NVIM_LISTEN_ADDRESS"
      eval "$_oldopts"
      echo "$result"
      return 0
    fi
  fi

  # Collect all live sockets as "pid:socket_path" entries
  local live_sockets=()
  local socket pid

  # 2a. Pidfile discovery — each running nvim that called code-preview.setup()
  # registers itself at ${XDG_STATE_HOME:-$HOME/.local/state}/code-preview/sockets/<pid>.
  # File contents: line 1 = socket path, line 2 = cwd.
  local _state_home="${XDG_STATE_HOME:-$HOME/.local/state}"
  local _pidfile_dir="$_state_home/code-preview/sockets"
  if [[ -d "$_pidfile_dir" ]]; then
    local pidfile pf_socket pf_cwd
    for pidfile in "$_pidfile_dir"/*; do
      [[ -f "$pidfile" ]] || continue
      pid="$(basename "$pidfile")"
      [[ "$pid" =~ ^[0-9]+$ ]] || continue
      _is_pid_suspended "$pid" && continue
      { IFS= read -r pf_socket; IFS= read -r pf_cwd; } < "$pidfile" || continue
      [[ -n "$pf_socket" && -S "$pf_socket" ]] || continue

      # Validate socket is responsive — self-heals stale pidfiles from crashed
      # nvim where the PID may even have been recycled.
      if ! _is_hook_target "$pf_socket" "$project_cwd" "$target_file"; then
        continue
      fi

      live_sockets+=("$pid:$pf_socket")
    done
  fi

  # 2. Scan macOS /var/folders paths
  local _glob_out
  _glob_out="$(compgen -G '/var/folders/*/*/T/nvim.*/*/nvim.*.0' 2>/dev/null)" || true
  if [[ -n "$_glob_out" ]]; then
    while IFS= read -r socket; do
      if [[ -S "$socket" ]]; then
        pid=$(basename "$socket" | sed 's/^nvim\.\([0-9]*\)\.0$/\1/')
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && ! _is_pid_suspended "$pid"; then
          if _is_hook_target "$socket" "$project_cwd" "$target_file"; then
            live_sockets+=("$pid:$socket")
          fi
        fi
      fi
    done <<< "$_glob_out"
  fi

  # Neovim's socket filename uses $NVIM_APPNAME (defaulting to "nvim") as the
  # prefix in both /tmp directory names and XDG_RUNTIME_DIR socket files. Used
  # by steps 3 and 4 below.
  local _appname="${NVIM_APPNAME:-nvim}"

  # 3. Scan /tmp paths (Linux and some macOS setups)
  local _tmp_glob_out
  _tmp_glob_out="$(compgen -G "/tmp/${_appname}.*/0" 2>/dev/null)" || true
  if [[ -n "$_tmp_glob_out" ]]; then
    while IFS= read -r socket; do
      if [[ -S "$socket" ]]; then
        pid=$(echo "$socket" | grep -oE "${_appname}\\.[0-9]+" | grep -oE '[0-9]+')
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && ! _is_pid_suspended "$pid"; then
          if _is_hook_target "$socket" "$project_cwd" "$target_file"; then
            live_sockets+=("$pid:$socket")
          fi
        fi
      fi
    done <<< "$_tmp_glob_out"
  fi

  # 4. Scan XDG_RUNTIME_DIR paths (NixOS, systemd-based distros)
  local _xdg_dir="${XDG_RUNTIME_DIR:-}"
  if [[ -z "$_xdg_dir" ]]; then
    _xdg_dir="/run/user/$(id -u)"
  fi
  local _xdg_glob_out
  _xdg_glob_out="$(compgen -G "$_xdg_dir/${_appname}.*.0" 2>/dev/null)" || true
  if [[ -n "$_xdg_glob_out" ]]; then
    while IFS= read -r socket; do
      if [[ -S "$socket" ]]; then
        pid=$(echo "$socket" | grep -oE "${_appname}\\.[0-9]+" | grep -oE '[0-9]+')
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null && ! _is_pid_suspended "$pid"; then
          if _is_hook_target "$socket" "$project_cwd" "$target_file"; then
            live_sockets+=("$pid:$socket")
          fi
        fi
      fi
    done <<< "$_xdg_glob_out"
  fi

  if [[ ${#live_sockets[@]} -eq 0 ]]; then
    eval "$_oldopts"
    return 1
  fi

  # Sort unique sockets by PID descending (newest instance first)
  local sorted_sockets=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && sorted_sockets+=("$line")
  done < <(printf '%s\n' "${live_sockets[@]}" | sort -u -t: -k1,1nr)

  # 5. Collect sockets whose cwd matches project_cwd
  local cwd_matching_sockets=()
  if [[ -n "$project_cwd" ]]; then
    local entry nvim_cwd
    for entry in "${sorted_sockets[@]}"; do
      pid="${entry%%:*}"
      socket="${entry#*:}"
      nvim_cwd="$(_get_pid_cwd "$pid")"
      if [[ -n "$nvim_cwd" ]] && [[ "$project_cwd" == "$nvim_cwd" || "$project_cwd" == "$nvim_cwd/"* ]]; then
        cwd_matching_sockets+=("$socket")
      fi
    done
  fi

  # 6. Target buffer affinity: if target_file is given, prefer the instance that already has it open
  local candidate_sockets=()
  if [[ ${#cwd_matching_sockets[@]} -gt 0 ]]; then
    candidate_sockets=("${cwd_matching_sockets[@]}")
  else
    for entry in "${sorted_sockets[@]}"; do
      candidate_sockets+=("${entry#*:}")
    done
  fi

  if [[ -n "$target_file" ]]; then
    local target_expr
    target_expr="$(jq -Rn --arg target "$target_file" '$target' 2>/dev/null || true)"
    for socket in "${candidate_sockets[@]}"; do
      if [[ -n "$target_expr" ]] &&
          nvim --server "$socket" --remote-expr "bufexists($target_expr)" 2>/dev/null | grep -q '^1$'; then
        result="$socket"
        break
      fi
    done
  fi

  # 7. Fallback to the newest project-matching socket. All live candidates
  # were already checked by hook_target.matches_project above.
  if [[ -z "$result" && ${#candidate_sockets[@]} -gt 0 ]]; then
    result="${candidate_sockets[0]}"
  fi

  eval "$_oldopts"
  echo "$result"
  return 0
}

NVIM_SOCKET="$(find_nvim_socket "$_NVIM_SOCKET_CWD" "$_NVIM_TARGET_FILE")" || true
export NVIM_SOCKET
