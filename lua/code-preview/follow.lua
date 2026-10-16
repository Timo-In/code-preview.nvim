-- ============================================================================
-- code-preview.nvim: Viewport & Focus Follower (with terminal guard)
-- ============================================================================

local M = {}

--- Check if Neovim is currently in an interactive/terminal state that should not be disturbed
---@return boolean
function M.is_user_busy()
  local cur_win = vim.api.nvim_get_current_win()
  local cur_buf = vim.api.nvim_win_get_buf(cur_win)
  local bt = vim.bo[cur_buf].buftype

  -- 1. In terminal window (user might be typing to AI agent)
  if bt == "terminal" then
    return true
  end

  -- 2. In insert, visual, or cmdline mode
  local mode = vim.api.nvim_get_mode().mode
  if mode:sub(1, 1) == "i" or mode:sub(1, 1) == "v" or mode:sub(1, 1) == "c" then
    return true
  end

  return false
end

--- Smoothly center window on target line without stealing focus from terminal
---@param winid integer
---@param target_line integer
function M.follow_line(winid, target_line)
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end
  -- Moving a background code window does not steal focus from the terminal.
  -- Keep the busy guard only when the target is the actively used window.
  if winid == vim.api.nvim_get_current_win() and M.is_user_busy() then return end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  local line_count = vim.api.nvim_buf_line_count(bufnr)
  local l = math.min(line_count, math.max(1, target_line))

  -- Set cursor in the target window and center viewport
  pcall(vim.api.nvim_win_set_cursor, winid, { l, 0 })
  pcall(vim.api.nvim_win_call, winid, function()
    vim.cmd("normal! zz")
  end)
end

return M
