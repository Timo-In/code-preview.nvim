local plugin = require("code-preview")
local pre_tool = require("code-preview.pre_tool")
local post_tool = require("code-preview.post_tool")
local diff = require("code-preview.diff")
local renderer = require("code-preview.renderer")
local buffer_mgr = require("code-preview.buffer")

describe("backend single-buffer preview lifecycle", function()
  local saved_config
  local saved_ensure_daemon
  local paths

  before_each(function()
    saved_config = vim.deepcopy(plugin.config)
    saved_ensure_daemon = plugin.ensure_daemon
    plugin.ensure_daemon = function() end
    plugin.config = vim.tbl_deep_extend("force", plugin.config, {
      diff = { linger_ms = 0 },
      neo_tree = { enabled = false, reveal = false },
    })
    paths = {}
  end)

  after_each(function()
    diff.close_diff_and_clear()
    for _, path in ipairs(paths) do
      local bufnr = buffer_mgr.find_buffer(buffer_mgr.normalize_path(path))
      if bufnr and vim.api.nvim_buf_is_valid(bufnr) then
        pcall(vim.api.nvim_buf_delete, bufnr, { force = true })
      end
      os.remove(path)
    end
    vim.cmd("silent! tabonly")
    plugin.config = saved_config
    plugin.ensure_daemon = saved_ensure_daemon
  end)

  local cases = {
    {
      name = "OpenCode",
      backend = "opencode",
      payload = function(path)
        return { tool = "write", cwd = vim.fn.fnamemodify(path, ":h"), args = {
          filePath = path,
          content = "changed",
        } }
      end,
    },
    {
      name = "Codex",
      backend = "codex",
      payload = function(path)
        return { tool_name = "Write", cwd = vim.fn.fnamemodify(path, ":h"), tool_input = {
          file_path = path,
          content = "changed",
        } }
      end,
    },
    {
      name = "Claude Code",
      backend = "claudecode",
      payload = function(path)
        return { tool_name = "Write", cwd = vim.fn.fnamemodify(path, ":h"), tool_input = {
          file_path = path,
          content = "changed",
        } }
      end,
    },
  }

  for _, case in ipairs(cases) do
    it("clears " .. case.name .. " preview marks on save", function()
      local path = vim.fn.tempname() .. ".lua"
      vim.fn.writefile({ "original" }, path)
      paths = { path }

      pre_tool.handle(case.payload(path), case.backend)

      local bufnr = assert(buffer_mgr.find_buffer(buffer_mgr.normalize_path(path)))
      assert.same({ "changed" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
      assert.is_true(#vim.api.nvim_buf_get_extmarks(bufnr, renderer.NS_DIFF, 0, -1, {}) > 0)

      vim.api.nvim_buf_call(bufnr, function() vim.cmd("write") end)

      assert.equals(0, #vim.api.nvim_buf_get_extmarks(bufnr, renderer.NS_DIFF, 0, -1, {}))
      assert.equals(0, #vim.api.nvim_buf_get_extmarks(bufnr, renderer.NS_SIGNS, 0, -1, {}))
    end)
  end

  it("keeps sequential OpenCode files in separate tabs after each post hook", function()
    plugin.config.diff.auto_close = true
    local path_a = vim.fn.tempname() .. "_a.lua"
    local path_b = vim.fn.tempname() .. "_b.lua"
    vim.fn.writefile({ "a" }, path_a)
    vim.fn.writefile({ "b" }, path_b)
    paths = { path_a, path_b }
    local tabs_before = #vim.api.nvim_list_tabpages()

    local function payload(path, content)
      return {
        tool = "write",
        cwd = vim.fn.fnamemodify(path, ":h"),
        args = { filePath = path, content = content },
      }
    end

    pre_tool.handle(payload(path_a, "changed a"), "opencode")
    post_tool.handle(payload(path_a, nil), "opencode")
    pre_tool.handle(payload(path_b, "changed b"), "opencode")
    post_tool.handle(payload(path_b, nil), "opencode")

    assert.equals(tabs_before + 2, #vim.api.nvim_list_tabpages())
    assert.is_not_nil(buffer_mgr.find_window_for_buf(
      assert(buffer_mgr.find_buffer(buffer_mgr.normalize_path(path_a)))))
    assert.is_not_nil(buffer_mgr.find_window_for_buf(
      assert(buffer_mgr.find_buffer(buffer_mgr.normalize_path(path_b)))))
  end)

  it("does not let an older linger timer clear a newer preview", function()
    plugin.config.diff.auto_close = true
    plugin.config.diff.linger_ms = 20
    local path = vim.fn.tempname() .. "_linger.lua"
    vim.fn.writefile({ "original" }, path)
    paths = { path }

    local function payload(content)
      return {
        tool = "write",
        cwd = vim.fn.fnamemodify(path, ":h"),
        args = { filePath = path, content = content },
      }
    end

    pre_tool.handle(payload("first change"), "opencode")
    post_tool.handle(payload(nil), "opencode")
    pre_tool.handle(payload("second change"), "opencode")

    local bufnr = assert(buffer_mgr.find_buffer(buffer_mgr.normalize_path(path)))
    vim.wait(60)
    assert.is_true(#vim.api.nvim_buf_get_extmarks(bufnr, renderer.NS_DIFF, 0, -1, {}) > 0)
  end)
end)
