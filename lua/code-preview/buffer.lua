-- ============================================================================
-- code-preview.nvim: Buffer Manager (In-place buffer reuse & dirty protection)
-- ============================================================================

local M = {}

local log = require("code-preview.log")

--- Normalize absolute file path
---@param path string
---@return string
function M.normalize_path(path)
  if not path or path == "" then return "" end
  local real = vim.uv.fs_realpath(path)
  local p = real or vim.fn.fnamemodify(path, ":p")
  return vim.fs.normalize(p)
end

--- Check if a buffer has unsaved user modifications
---@param bufnr integer
---@return boolean
function M.is_dirty(bufnr)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false
  end
  return vim.bo[bufnr].modified
end

--- Find existing buffer for normalized file path
---@param norm_path string
---@return integer? bufnr
function M.find_buffer(norm_path)
  if not norm_path or norm_path == "" then return nil end
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(b) then
      local name = vim.api.nvim_buf_get_name(b)
      if name ~= "" and M.normalize_path(name) == norm_path then
        return b
      end
    end
  end
  return nil
end

--- Locate an active window currently displaying the given buffer
---@param bufnr integer
---@return integer? winid
function M.find_window_for_buf(bufnr)
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      return win
    end
  end
  return nil
end

--- Get or open a buffer without replacing an unrelated visible file.
--- A target that is not already visible gets its own tabpage.
---@param file_path string
---@return integer? bufnr, integer? winid, boolean created_tab
function M.get_or_open_buffer(file_path)
  local norm_path = M.normalize_path(file_path)
  if norm_path == "" then return nil, nil end

  local bufnr = M.find_buffer(norm_path)
  if not bufnr then
    -- Buffer does not exist yet; load file into buffer
    bufnr = vim.fn.bufadd(norm_path)
    -- Preview-owned buffers must survive editor crashes without leaving a swap
    -- file that prevents the next Neovim instance from reopening the target.
    -- Existing user buffers keep their original swapfile setting.
    vim.bo[bufnr].swapfile = false
    vim.fn.bufload(bufnr)
    vim.bo[bufnr].buflisted = true
    local ft = vim.filetype.match({ filename = norm_path, buf = bufnr })
    if ft and ft ~= "" then
      vim.bo[bufnr].filetype = ft
    end
  end

  local winid = M.find_window_for_buf(bufnr)
  local created_tab = false
  if not winid then
    vim.cmd("tabnew")
    created_tab = true
    winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
  end

  return bufnr, winid, created_tab
end

--- Safely reload buffer lines from disk or content array with dirty guard
---@param bufnr integer
---@param new_lines string[]
---@return boolean success, string? err_msg
function M.safe_reload(bufnr, new_lines)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then
    return false, "Invalid buffer"
  end

  if M.is_dirty(bufnr) then
    local path = vim.api.nvim_buf_get_name(bufnr)
    log.warn(string.format("Conflict: Buffer %d (%s) is dirty; skipping auto reload", bufnr, path))
    vim.notify(
      string.format("[code-preview] Buffer is modified by user. Auto-reload paused for %s",
        vim.fn.fnamemodify(path, ":t")),
      vim.log.levels.WARN,
      { title = "code-preview conflict" }
    )
    return false, "Buffer is dirty"
  end

  -- Atomic update of buffer lines
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, new_lines)
  -- Mark clean since this matches disk state
  vim.bo[bufnr].modified = false
  return true, nil
end

return M
