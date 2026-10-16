-- ============================================================================
-- code-preview.nvim: In-Place Renderer (Extmarks & Virtual Lines)
-- ============================================================================

local M = {}

M.NS_DIFF  = vim.api.nvim_create_namespace("code_preview_in_place_diff")
M.NS_SIGNS = vim.api.nvim_create_namespace("code_preview_in_place_signs")
M.NS       = M.NS_DIFF -- Backwards compatibility

-- Last content explicitly saved by the user, keyed by canonical file path.
-- This prevents a delayed daemon event for the same write from restoring marks
-- immediately after BufWritePost cleared them.
local accepted_hashes = {}
local linger_timers = {}

local function normalize_path(path)
  if not path or path == "" then return "" end
  return vim.fs.normalize(vim.uv.fs_realpath(path) or vim.fn.fnamemodify(path, ":p"))
end

local function lines_hash(lines)
  return vim.fn.sha256(table.concat(lines or {}, "\n"))
end

--- Cancel a pending background fade before rendering or clearing newer marks.
---@param bufnr integer
function M.cancel_linger(bufnr)
  local timer_id = linger_timers[bufnr]
  if timer_id then
    pcall(vim.fn.timer_stop, timer_id)
    linger_timers[bufnr] = nil
  end
end

--- Fade diff backgrounds after a delay unless a newer render supersedes it.
---@param bufnr integer
---@param delay_ms integer
---@return integer timer_id
function M.schedule_clear_diff(bufnr, delay_ms)
  M.cancel_linger(bufnr)
  local timer_id
  timer_id = vim.fn.timer_start(delay_ms, function()
    if linger_timers[bufnr] ~= timer_id then return end
    linger_timers[bufnr] = nil
    M.clear_diff(bufnr)
  end)
  linger_timers[bufnr] = timer_id
  return timer_id
end

--- Return whether a daemon payload matches the last user-saved content.
---@param file_path string
---@param lines string[]
---@return boolean
function M.is_accepted(file_path, lines)
  local key = normalize_path(file_path)
  return key ~= "" and accepted_hashes[key] == lines_hash(lines)
end

--- Ensure preview marks can always be dismissed after any render source.
--- The autocmds stay active because the Go daemon may render the same buffer
--- again after an earlier edit or save cleared its previous marks.
---@param bufnr integer
local function ensure_cleanup(bufnr)
  local group = vim.api.nvim_create_augroup("CodePreviewInPlace_" .. bufnr, { clear = true })
  local buffer_key = normalize_path(vim.api.nvim_buf_get_name(bufnr))
  vim.api.nvim_create_autocmd({ "InsertEnter", "BufWritePost" }, {
    group = group,
    buffer = bufnr,
    callback = function(event)
      if event.event == "BufWritePost" then
        local path = vim.api.nvim_buf_get_name(bufnr)
        local key = normalize_path(path)
        if key ~= "" then
          accepted_hashes[key] = lines_hash(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
        end
      end
      M.clear(bufnr)
    end,
  })
  vim.api.nvim_create_autocmd("BufDelete", {
    group = group,
    buffer = bufnr,
    once = true,
    callback = function()
      M.cancel_linger(bufnr)
      if buffer_key ~= "" then accepted_hashes[buffer_key] = nil end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

-- Setup highlight groups with fresh, modern diff aesthetic (GitHub Dark & VSCode style)
function M.setup_highlights()
  local defs = {
    -- Clean translucent light-green/blue diff backgrounds
    CodePreviewAdd           = { bg = "#204632", fg = "NONE" },
    CodePreviewChange        = { bg = "#1e3a38", fg = "NONE" },
    -- VSCode-style soft red background for deleted lines
    CodePreviewDeleteLine    = { bg = "#3c1f1e", fg = "#f87171" },
    CodePreviewDeleteVirtual = { bg = "#3c1f1e", fg = "#f87171" },

    -- Line-number sign column indicators (clean vertical bar ▎)
    CodePreviewSignAdd    = { fg = "#42be7c", bold = true },
    CodePreviewSignChange = { fg = "#38bdf8", bold = true },
    CodePreviewSignDelete = { fg = "#f87171", bold = true },
  }
  for hl, val in pairs(defs) do
    vim.api.nvim_set_hl(0, hl, val)
  end
end

--- Clear background colors and virtual lines (Phase 1 linger fade)
---@param bufnr integer
function M.clear_diff(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.NS_DIFF, 0, -1)
  end
end

--- Clear sign column markers (Phase 2 user action fade)
---@param bufnr integer
function M.clear_signs(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.NS_SIGNS, 0, -1)
  end
end

--- Clear all preview extmarks (both background and signs) in a buffer
---@param bufnr integer
function M.clear(bufnr)
  M.cancel_linger(bufnr)
  if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
    vim.api.nvim_buf_clear_namespace(bufnr, M.NS_DIFF, 0, -1)
    vim.api.nvim_buf_clear_namespace(bufnr, M.NS_SIGNS, 0, -1)
  end
end

--- Clear preview extmarks in all active buffers
function M.clear_all()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    M.clear(b)
  end
end

--- Render net changes (Baseline -> Current) in-place
---@param bufnr integer
---@param changes table Array of hunk objects:
---   { type = "add"|"change", start_line = int, end_line = int, deleted_lines = string[] }
---   { type = "delete", at_line = int, deleted_lines = string[] }
function M.render(bufnr, changes)
  if not bufnr or not vim.api.nvim_buf_is_valid(bufnr) then return end

  ensure_cleanup(bufnr)
  M.setup_highlights()
  -- Clear previous marks for this buffer first
  M.clear(bufnr)

  local line_count = vim.api.nvim_buf_line_count(bufnr)

  for _, item in ipairs(changes or {}) do
    if item.type == "add" or item.type == "change" then
      local is_add = (item.type == "add")
      local hl_group = is_add and "CodePreviewAdd" or "CodePreviewChange"
      local sign_hl  = is_add and "CodePreviewSignAdd" or "CodePreviewSignChange"
      local s_line = math.max(0, (item.start_line or 1) - 1)
      local e_line = math.min(line_count, item.end_line or (s_line + 1))

      -- Plan B: When a line is changed, show deleted old lines with red background directly above it
      if not is_add and item.deleted_lines and #item.deleted_lines > 0 then
        local virt_lines = {}
        for _, dline in ipairs(item.deleted_lines) do
          table.insert(virt_lines, { { "  - " .. dline, "CodePreviewDeleteLine" } })
        end
        pcall(vim.api.nvim_buf_set_extmark, bufnr, M.NS_DIFF, s_line, 0, {
          virt_lines       = virt_lines,
          virt_lines_above = true,
          priority         = 200,
        })
      end

      -- Render new/replacement lines
      for l = s_line, e_line - 1 do
        -- 1. Background highlight on NS_DIFF
        pcall(vim.api.nvim_buf_set_extmark, bufnr, M.NS_DIFF, l, 0, {
          line_hl_group = hl_group,
          priority      = 200,
        })
        -- 2. Sign column indicator on NS_SIGNS (Blue for change, Green for add)
        pcall(vim.api.nvim_buf_set_extmark, bufnr, M.NS_SIGNS, l, 0, {
          sign_text     = "▎",
          sign_hl_group = sign_hl,
          priority      = 200,
        })
      end
    elseif item.type == "delete" then
      local at_line = math.min(line_count - 1, math.max(0, (item.at_line or 1) - 1))
      local virt_lines = {}
      for _, dline in ipairs(item.deleted_lines or {}) do
        table.insert(virt_lines, { { "  - " .. dline, "CodePreviewDeleteLine" } })
      end
      if #virt_lines > 0 then
        -- 1. Virtual deleted lines on NS_DIFF (red background)
        pcall(vim.api.nvim_buf_set_extmark, bufnr, M.NS_DIFF, at_line, 0, {
          virt_lines       = virt_lines,
          virt_lines_above = true,
          priority         = 200,
        })
        -- 2. Sign column indicator on NS_SIGNS (Red bar for delete)
        pcall(vim.api.nvim_buf_set_extmark, bufnr, M.NS_SIGNS, at_line, 0, {
          sign_text     = "▎",
          sign_hl_group = "CodePreviewSignDelete",
          priority      = 200,
        })
      end
    end
  end
end

return M
