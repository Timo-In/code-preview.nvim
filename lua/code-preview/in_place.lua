-- ============================================================================
-- code-preview.nvim: In-Place Bridge (Receives Go Daemon RPC updates)
-- ============================================================================

local M = {}

local buffer_mgr = require("code-preview.buffer")
local renderer   = require("code-preview.renderer")
local follow     = require("code-preview.follow")
local log        = require("code-preview.log")

--- Handle in-place diff updates dispatched by Go Daemon via RPC
---@param json_payload string
function M.on_diff_update(json_payload)
  local ok, payload = pcall(vim.json.decode, json_payload)
  if not ok or type(payload) ~= "table" then
    log.error("[in_place] Failed to decode diff update payload: " .. tostring(payload))
    return
  end

  local file_path   = payload.path
  local lines       = payload.lines
  local changes     = payload.changes
  local target_line = payload.target_line or 1
  local revision    = payload.revision or 1

  -- The daemon cannot reconstruct a pre-write baseline when it first observes
  -- a file. Its revision-1 event therefore carries no changes and only records
  -- the current disk state as the baseline. Do not let that bookkeeping event
  -- erase a pre-hook preview or reset its viewport to line 1.
  if revision == 1 and #(changes or {}) == 0 then
    log.debug(string.format("[in_place] Ignoring baseline-only update for %s", tostring(file_path)))
    return
  end

  local worktree = payload.worktree_root
  local accepted = require("code-preview").daemon_worktree
  local project = require("code-preview.project")
  if not worktree or not accepted or not project.same(accepted, worktree)
      or not project.contains(accepted, file_path) then
    log.warn(string.format("[in_place] Rejected update outside active worktree: %s", tostring(file_path)))
    return
  end

  -- BufWritePost is the user's acceptance boundary. Ignore a delayed watcher
  -- event carrying the exact content that was just saved, otherwise it would
  -- restore marks immediately after the save autocmd cleared them.
  if renderer.is_accepted(file_path, lines) then
    M.clear_preview(file_path)
    log.debug(string.format("[in_place] Ignoring accepted update for %s", tostring(file_path)))
    return
  end

  -- 1. Reuse a visible target or open an unseen file in its own tab
  local bufnr, winid = buffer_mgr.get_or_open_buffer(file_path)
  if not bufnr then
    log.error("[in_place] Failed to get or open buffer for " .. tostring(file_path))
    return
  end

  -- 2. Safely reload buffer with dirty guard
  local reloaded, err = buffer_mgr.safe_reload(bufnr, lines)
  if not reloaded then
    -- Buffer is dirty or invalid, skip rendering to prevent desync
    log.warn(string.format("[in_place] Skip render on %s (rev=%d): %s", file_path, revision, tostring(err)))
    return
  end

  -- 3. Render net changes (Extmarks + Virtual Lines)
  renderer.render(bufnr, changes)

  -- 4. Follow viewport smoothly without stealing terminal or user input focus
  if winid then
    follow.follow_line(winid, target_line)
  end

  log.info(string.format("[in_place] Applied in-place diff on %s: rev=%d, changes=%d",
    vim.fn.fnamemodify(file_path, ":t"), revision, #(changes or {})))
end

--- Clear preview for file
---@param file_path string?
function M.clear_preview(file_path)
  if file_path and file_path ~= "" then
    local norm = buffer_mgr.normalize_path(file_path)
    local bufnr = buffer_mgr.find_buffer(norm)
    if bufnr then
      renderer.clear(bufnr)
    end
  else
    local cur_buf = vim.api.nvim_get_current_buf()
    renderer.clear(cur_buf)
  end
end

--- Clear all preview highlights across all buffers
function M.clear_all()
  renderer.clear_all()
end

return M
