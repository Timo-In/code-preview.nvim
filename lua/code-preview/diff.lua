local M = {}

local log = require("code-preview.log")

-- Active diffs keyed by absolute file path.
-- Each entry tracks one real file buffer rendered with extmarks.
local active_diffs = {}

-- Update neo-tree indicator + reveal for a file that's about to be previewed.
-- `action` is an optional hint from callers that know the operation type
-- (e.g. ApplyPatch passes "delete" for `*** Delete File:` directives). We
-- only emit "deleted" when explicitly told — inferring it from an empty
-- proposed file would misclassify legitimate truncations to zero bytes.
local function mark_change_and_reveal(abs_file_path, action)
  if not abs_file_path or abs_file_path == "" then
    return
  end

  local status
  if action == "delete" then
    status = "deleted"
  elseif vim.uv.fs_stat(abs_file_path) then
    status = "modified"
  else
    status = "created"
  end
  log.debug(log.fmt("mark_change_and_reveal: %s → %s", abs_file_path, status))
  pcall(function() require("code-preview.changes").set(abs_file_path, status) end)
  pcall(function() require("code-preview.neo_tree").refresh() end)

  local cfg = require("code-preview").config
  if not (cfg and cfg.neo_tree and cfg.neo_tree.reveal ~= false) then
    return
  end

  local reveal_dir = nil
  if cfg.neo_tree.reveal_root == "git" then
    local parent = vim.fn.fnamemodify(abs_file_path, ":h")
    -- List-form (no shell): avoids the POSIX-only `2>/dev/null` redirect, which
    -- misbehaves under Windows cmd. `shell_error` still gates the result, so a
    -- non-repo parent (git's stderr + non-zero exit) simply leaves reveal_dir nil.
    local git_out = vim.fn.systemlist({ "git", "-C", parent, "rev-parse", "--show-toplevel" })
    if vim.v.shell_error == 0 and git_out[1] and git_out[1] ~= "" then
      reveal_dir = git_out[1]
    end
  end

  local reveal_target = abs_file_path
  if status == "created" then
    local parent = vim.fn.fnamemodify(abs_file_path, ":h")
    while parent ~= "/" and vim.fn.isdirectory(parent) == 0 do
      parent = vim.fn.fnamemodify(parent, ":h")
    end
    local siblings = vim.fn.glob(parent .. "/*", false, true)
    reveal_target = siblings[1] or parent
  end

  vim.defer_fn(function()
    pcall(function()
      require("code-preview.neo_tree").reveal(reveal_target, reveal_dir)
    end)
  end, 300)
end

local function read_file_lines(path)
  local lines = {}
  local f = io.open(path, "r")
  if f then
    for line in f:lines() do
      table.insert(lines, line)
    end
    f:close()
  end
  return lines
end

-- Force the terminal to repaint after an RPC-driven tab/window change.
--
-- show_diff runs inside a `nvim --remote-expr` call from the hook shim, so the
-- new diff tab exists in Neovim's state immediately but the TUI isn't repainted
-- until the event loop next wakes. A deferred `redraw!` covers most hosts.
--
-- The Windows legacy console (cmd.exe / conhost) is the exception: it does NOT
-- flush a timer-driven `redraw!` issued from an idle --remote-expr, so the diff
-- only paints on the next event (the user's next edit) — neo-tree, which forces
-- its own redraw, updates meanwhile, producing the "marking shows but diff
-- doesn't" symptom. nvim__redraw({flush=true}) pushes the grid to the UI on the
-- spot, and the <Ignore> feedkeys nudge wakes the input loop so conhost delivers
-- it. Both are pcall'd: __redraw is 0.10+ and semi-private. The win32 guard keeps
-- every other platform on the exact prior behaviour.
local function force_redraw()
  vim.fn.timer_start(10, function()
    vim.cmd("redraw!")
    if vim.fn.has("win32") == 1 then
      pcall(vim.api.nvim__redraw, { flush = true })
      pcall(vim.api.nvim_feedkeys,
        vim.api.nvim_replace_termcodes("<Ignore>", true, false, true), "n", false)
    end
  end)
end

--- Count how many active diffs are currently open.
local function active_count()
  local n = 0
  for _ in pairs(active_diffs) do n = n + 1 end
  return n
end

function M.is_open(file_path)
  if file_path and file_path ~= "" then
    local entry = active_diffs[file_path]
    if entry and entry.tab and vim.api.nvim_tabpage_is_valid(entry.tab) then
      return true
    end
    return false
  end
  -- No file_path: return true if ANY diff is open
  return active_count() > 0
end

local function show_in_place_diff(original_path, proposed_path, real_file_path, abs_file_path)
  local buffer_mgr = require("code-preview.buffer")
  local renderer   = require("code-preview.renderer")
  local follow     = require("code-preview.follow")

  local target_file = abs_file_path or real_file_path

  local bufnr, winid, created_tab = buffer_mgr.get_or_open_buffer(target_file)
  if not bufnr then
    if created_tab then pcall(vim.cmd, "tabclose") end
    return nil
  end

  local orig_lines = read_file_lines(original_path)
  local prop_lines = read_file_lines(proposed_path)

  local orig_text = table.concat(orig_lines, "\n")
  local prop_text = table.concat(prop_lines, "\n")
  local raw_diff = vim.diff(orig_text, prop_text, { result_type = "indices" }) or {}

  local changes = {}
  local first_target_line = nil
  for _, d in ipairs(raw_diff) do
    local s1, count1, s2, count2 = d[1], d[2], d[3], d[4]
    if first_target_line == nil then
      first_target_line = (s2 > 0) and s2 or (s1 > 0 and s1 or 1)
    end
    if count1 > 0 and count2 > 0 then
      local del_lines = {}
      for idx = s1, s1 + count1 - 1 do
        table.insert(del_lines, orig_lines[idx] or "")
      end
      table.insert(changes, {
        type = "change",
        start_line = s2,
        end_line = s2 + count2,
        at_line = s2,
        deleted_lines = del_lines,
      })
    elseif count2 > 0 then
      table.insert(changes, {
        type = "add",
        start_line = s2,
        end_line = s2 + count2,
      })
    elseif count1 > 0 then
      local del_lines = {}
      for idx = s1, s1 + count1 - 1 do
        table.insert(del_lines, orig_lines[idx] or "")
      end
      table.insert(changes, {
        type = "delete",
        at_line = s2 > 0 and s2 or 1,
        deleted_lines = del_lines,
      })
    end
  end
  if not first_target_line then first_target_line = 1 end

  buffer_mgr.safe_reload(bufnr, prop_lines)
  renderer.render(bufnr, changes)
  if winid then
    follow.follow_line(winid, first_target_line)
  end

  local cur_tab = vim.api.nvim_get_current_tabpage()
  return {
    bufnr = bufnr,
    win = winid,
    tab = cur_tab,
    created_tab = created_tab,
    real_path = target_file,
    timer_id = nil,
  }
end

function M.show_diff(original_path, proposed_path, real_file_path, abs_file_path, action, backend)
  local file_key = abs_file_path or real_file_path
  log.info(log.fmt("show_diff: file=%s mode=in_place backend=%s active=%d",
    file_key or "nil",
    backend or "nil",
    active_count()))

  -- If a diff for this SAME file is already open, close it first (re-edit)
  if file_key and active_diffs[file_key] then
    log.debug(log.fmt("show_diff: re-edit detected, closing existing diff for %s", file_key))
    M.close_for_file(file_key)
  end

  -- Set the neo-tree indicator + reveal
  mark_change_and_reveal(abs_file_path, action)

  active_diffs[file_key] = show_in_place_diff(
    original_path, proposed_path, real_file_path, abs_file_path)
  force_redraw()
end

--- Finish the preview for one file.
---@param file_path string
---@param immediate boolean? clear all marks immediately for a manual close
function M.close_for_file(file_path, immediate)
  local entry = active_diffs[file_path]
  if not entry then
    log.debug(log.fmt("close_for_file: no active diff for %s, skipping", file_path))
    return
  end

  log.info(log.fmt("close_for_file: closing diff for %s (remaining=%d)", file_path, active_count() - 1))

  -- Clear the matching change indicator without disturbing concurrent previews.
  pcall(function() require("code-preview.changes").clear(file_path) end)

  local cfg = require("code-preview").config
  local linger_ms = (cfg and cfg.diff and cfg.diff.linger_ms)
  if linger_ms == nil then linger_ms = 1500 end

  local bufnr = entry.bufnr
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    local renderer = require("code-preview.renderer")
    if immediate or linger_ms <= 0 then
      pcall(renderer.clear, bufnr)
    else
      -- Fade backgrounds and virtual lines, then keep signs until the user
      -- edits or saves. renderer.render() owns the persistent cleanup hooks.
      entry.timer_id = renderer.schedule_clear_diff(bufnr, linger_ms)
    end
  end
  active_diffs[file_path] = nil
end

--- Close the preview on the current tab, or the first active preview.
function M.close_diff()
  -- Find which active diff is on the current tab
  local current_tab = vim.api.nvim_get_current_tabpage()
  for file_path, entry in pairs(active_diffs) do
    if entry.tab == current_tab then
      local is_created = entry.created_tab
      M.close_for_file(file_path, true)
      if is_created and vim.api.nvim_tabpage_is_valid(current_tab) then
        pcall(vim.cmd, "tabclose")
      end
      return
    end
  end
  -- Fallback: close the first one found
  for file_path, entry in pairs(active_diffs) do
    local is_created = entry.created_tab
    local tab = entry.tab
    M.close_for_file(file_path, true)
    if is_created and tab and vim.api.nvim_tabpage_is_valid(tab) then
      pcall(vim.cmd, "tabclose")
    end
    return
  end
end

-- Close ALL diffs and clear neo-tree indicators (for manual close via <leader>dq)
function M.close_diff_and_clear()
  log.info(log.fmt("close_diff_and_clear: closing all diffs (count=%d)", active_count()))
  -- Collect keys first to avoid modifying table during iteration
  local files = {}
  for file_path, _ in pairs(active_diffs) do
    files[#files + 1] = file_path
  end
  for _, file_path in ipairs(files) do
    M.close_for_file(file_path, true)
  end
  pcall(function() require("code-preview.renderer").clear_all() end)
  pcall(function() require("code-preview.changes").clear_all() end)
  pcall(function() require("code-preview.neo_tree").refresh() end)
end

--- Expose active_diffs for testing (read-only copy).
function M._active_diffs()
  local copy = {}
  for k, v in pairs(active_diffs) do
    copy[k] = {
      tab = v.tab,
      bufnr = v.bufnr,
      created_tab = v.created_tab,
    }
  end
  return copy
end

return M
