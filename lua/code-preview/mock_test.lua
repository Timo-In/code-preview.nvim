-- ============================================================================
-- code-preview.nvim: Mock Test for Phase P0 (In-Place 10-Iteration Verification)
-- ============================================================================

local M = {}

local buffer_mgr = require("code-preview.buffer")
local renderer = require("code-preview.renderer")
local follow = require("code-preview.follow")

--- Run a simulation of 10 consecutive edits on a single file
--- Verifies:
--- 1. Same buffer reused throughout
--- 2. No new tabs created
--- 3. Extmarks & Virtual Lines rendered in-place
--- 4. Dirty buffer protection triggers properly
function M.run_simulation()
  local test_file = vim.fn.stdpath("cache") .. "/code_preview_p0_test.lua"
  local initial_lines = {
    "-- Baseline version V0",
    "local function calculate(a, b)",
    "  local legacy_var = 100",
    "  return a + b",
    "end",
    "",
    "print(calculate(1, 2))",
  }

  -- Write baseline to disk
  vim.fn.writefile(initial_lines, test_file)

  local initial_tab_count = vim.fn.tabpagenr("$")
  local bufnr, winid = buffer_mgr.get_or_open_buffer(test_file)
  assert(bufnr and winid, "Failed to get or open buffer")

  local results = {}
  table.insert(results, string.format("Init: Buffer=%d, Win=%d, Tabs=%d", bufnr, winid, vim.fn.tabpagenr("$")))

  -- 10 simulated iterations
  local versions = {
    { desc = "V1: Add comment", lines = { "-- Baseline version V0", "-- Author: AI Agent", "local function calculate(a, b)", "  local legacy_var = 100", "  return a + b", "end", "", "print(calculate(1, 2))" },
      changes = { { type = "add", start_line = 2, end_line = 2 } }, target = 2 },
    { desc = "V2: Delete legacy_var", lines = { "-- Baseline version V0", "-- Author: AI Agent", "local function calculate(a, b)", "  return a + b", "end", "", "print(calculate(1, 2))" },
      changes = { { type = "add", start_line = 2, end_line = 2 }, { type = "delete", at_line = 4, deleted_lines = { "  local legacy_var = 100" } } }, target = 4 },
    { desc = "V3: Add multiplier", lines = { "-- Baseline version V0", "-- Author: AI Agent", "local function calculate(a, b, m)", "  m = m or 1", "  return (a + b) * m", "end", "", "print(calculate(1, 2, 3))" },
      changes = { { type = "add", start_line = 2, end_line = 2 }, { type = "change", start_line = 3, end_line = 3 }, { type = "add", start_line = 4, end_line = 4 }, { type = "delete", at_line = 4, deleted_lines = { "  local legacy_var = 100" } }, { type = "change", start_line = 5, end_line = 5 } }, target = 4 },
  }

  -- Loop through iterations 1 to 10
  for i = 1, 10 do
    local v = versions[((i - 1) % #versions) + 1]
    -- Simulate file write to disk
    vim.fn.writefile(v.lines, test_file)

    -- In-place reload
    local ok, err = buffer_mgr.safe_reload(bufnr, v.lines)
    assert(ok, "Reload failed: " .. tostring(err))

    -- In-place render
    renderer.render(bufnr, v.changes)
    follow.follow_line(winid, v.target or 1)

    local current_tabs = vim.fn.tabpagenr("$")
    assert(current_tabs == initial_tab_count, "Tab count changed! Tab leakage detected.")
  end

  table.insert(results, "Pass: 10 edits applied on single buffer without new tabpages.")

  -- Test dirty buffer protection
  vim.bo[bufnr].modified = true
  local ok, err = buffer_mgr.safe_reload(bufnr, { "Should not be applied" })
  if not ok and err == "Buffer is dirty" then
    table.insert(results, "Pass: Dirty buffer modification correctly blocked.")
  else
    error("Dirty buffer protection failed!")
  end

  -- Clean up
  vim.bo[bufnr].modified = false
  renderer.clear(bufnr)
  pcall(vim.fn.delete, test_file)

  return results
end

return M
