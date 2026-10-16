local diff = require("code-preview.diff")
local in_place = require("code-preview.in_place")
local renderer = require("code-preview.renderer")
local buffer_mgr = require("code-preview.buffer")
local plugin = require("code-preview")

local function write_temp(name, lines)
  local path = vim.fn.tempname() .. "_" .. name
  vim.fn.writefile(lines, path)
  return path
end

describe("in-place cold-buffer lifecycle", function()
  local saved_config
  local paths
  local preview_buf
  local saved_worktree

  before_each(function()
    saved_config = vim.deepcopy(plugin.config)
    saved_worktree = plugin.daemon_worktree
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
    end
    vim.cmd("silent! tabonly")
    preview_buf = nil
    for _, path in ipairs(paths) do
      os.remove(path)
    end
    plugin.config = saved_config
    plugin.daemon_worktree = saved_worktree
  end)

  it("keeps hook extmarks and target line after the daemon baseline event", function()
    local original = {}
    local proposed = {}
    for i = 1, 30 do
      original[i] = "line " .. i
      proposed[i] = original[i]
    end
    proposed[24] = "line 24 changed by agent"

    local real = write_temp("cold.lua", original)
    local orig = write_temp("orig.lua", original)
    local prop = write_temp("prop.lua", proposed)
    paths = { real, orig, prop }

    assert.is_nil(buffer_mgr.find_buffer(buffer_mgr.normalize_path(real)))
    diff.show_diff(orig, prop, real, real, nil, "opencode")

    preview_buf = assert(buffer_mgr.find_buffer(buffer_mgr.normalize_path(real)))
    local win = assert(buffer_mgr.find_window_for_buf(preview_buf))
    local marks_before = vim.api.nvim_buf_get_extmarks(preview_buf, renderer.NS_DIFF, 0, -1, {})
    assert.is_true(#marks_before > 0)
    assert.equals(24, vim.api.nvim_win_get_cursor(win)[1])

    in_place.on_diff_update(vim.json.encode({
      path = real,
      lines = proposed,
      changes = {},
      target_line = 1,
      revision = 1,
    }))

    local marks_after = vim.api.nvim_buf_get_extmarks(preview_buf, renderer.NS_DIFF, 0, -1, {})
    assert.equals(#marks_before, #marks_after)
    assert.equals(24, vim.api.nvim_win_get_cursor(win)[1])
  end)

  it("does not open a file for a baseline-only daemon event", function()
    local real = write_temp("unseen.lua", { "return true" })
    paths = { real }

    in_place.on_diff_update(vim.json.encode({
      path = real,
      lines = { "return true" },
      changes = {},
      target_line = 1,
      revision = 1,
    }))

    assert.is_nil(buffer_mgr.find_buffer(buffer_mgr.normalize_path(real)))
  end)

  it("does not open a file outside the active daemon worktree", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local real = write_temp("outside.lua", { "return false" })
    paths = { real, root }
    plugin.daemon_worktree = root

    in_place.on_diff_update(vim.json.encode({
      worktree_root = root,
      path = real,
      lines = { "return true" },
      changes = { { type = "change", start_line = 1, end_line = 1 } },
      target_line = 1,
      revision = 2,
    }))

    assert.is_nil(buffer_mgr.find_buffer(buffer_mgr.normalize_path(real)))
  end)

  it("accepts an update inside the active daemon worktree", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local real = root .. "/inside.lua"
    vim.fn.writefile({ "return false" }, real)
    paths = { real, root }
    plugin.daemon_worktree = root

    in_place.on_diff_update(vim.json.encode({
      worktree_root = root,
      path = real,
      lines = { "return true" },
      changes = { { type = "change", start_line = 1, end_line = 1 } },
      target_line = 1,
      revision = 2,
    }))

    preview_buf = assert(buffer_mgr.find_buffer(buffer_mgr.normalize_path(real)))
    assert.same({ "return true" }, vim.api.nvim_buf_get_lines(preview_buf, 0, -1, false))
  end)

  it("clears daemon-rendered marks whenever the buffer is saved", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local real = root .. "/save.lua"
    vim.fn.writefile({ "before" }, real)
    paths = { real, root }
    plugin.daemon_worktree = root

    in_place.on_diff_update(vim.json.encode({
      worktree_root = root,
      path = real,
      lines = { "after" },
      changes = { { type = "change", start_line = 1, end_line = 2, deleted_lines = { "before" } } },
      target_line = 1,
      revision = 2,
    }))

    preview_buf = assert(buffer_mgr.find_buffer(buffer_mgr.normalize_path(real)))
    assert.is_true(#vim.api.nvim_buf_get_extmarks(preview_buf, renderer.NS_DIFF, 0, -1, {}) > 0)

    vim.api.nvim_buf_call(preview_buf, function() vim.cmd("write") end)

    assert.equals(0, #vim.api.nvim_buf_get_extmarks(preview_buf, renderer.NS_DIFF, 0, -1, {}))
    assert.equals(0, #vim.api.nvim_buf_get_extmarks(preview_buf, renderer.NS_SIGNS, 0, -1, {}))

    -- A delayed fsnotify/RPC event for the write must not restore the marks.
    in_place.on_diff_update(vim.json.encode({
      worktree_root = root,
      path = real,
      lines = { "after" },
      changes = { { type = "change", start_line = 1, end_line = 2, deleted_lines = { "before" } } },
      target_line = 1,
      revision = 3,
    }))
    assert.equals(0, #vim.api.nvim_buf_get_extmarks(preview_buf, renderer.NS_DIFF, 0, -1, {}))
    assert.equals(0, #vim.api.nvim_buf_get_extmarks(preview_buf, renderer.NS_SIGNS, 0, -1, {}))
  end)

  it("re-arms save cleanup after an earlier user action and daemon re-render", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local real = root .. "/rerender.lua"
    vim.fn.writefile({ "one" }, real)
    paths = { real, root }
    plugin.daemon_worktree = root

    local function update(line, revision)
      in_place.on_diff_update(vim.json.encode({
        worktree_root = root,
        path = real,
        lines = { line },
        changes = { { type = "change", start_line = 1, end_line = 2, deleted_lines = { "one" } } },
        target_line = 1,
        revision = revision,
      }))
    end

    update("two", 2)
    preview_buf = assert(buffer_mgr.find_buffer(buffer_mgr.normalize_path(real)))
    vim.api.nvim_buf_call(preview_buf, function() vim.cmd("doautocmd InsertEnter") end)
    update("three", 3)
    assert.is_true(#vim.api.nvim_buf_get_extmarks(preview_buf, renderer.NS_DIFF, 0, -1, {}) > 0)

    vim.api.nvim_buf_call(preview_buf, function() vim.cmd("write") end)

    assert.equals(0, #vim.api.nvim_buf_get_extmarks(preview_buf, renderer.NS_DIFF, 0, -1, {}))
    assert.equals(0, #vim.api.nvim_buf_get_extmarks(preview_buf, renderer.NS_SIGNS, 0, -1, {}))
  end)

  it("opens different daemon-updated files in separate tabs", function()
    local root = vim.fn.tempname()
    vim.fn.mkdir(root, "p")
    local real_a = root .. "/a.lua"
    local real_b = root .. "/b.lua"
    vim.fn.writefile({ "a" }, real_a)
    vim.fn.writefile({ "b" }, real_b)
    paths = { real_a, real_b, root }
    plugin.daemon_worktree = root
    local tabs_before = #vim.api.nvim_list_tabpages()

    for index, path in ipairs({ real_a, real_b }) do
      in_place.on_diff_update(vim.json.encode({
        worktree_root = root,
        path = path,
        lines = { "changed " .. index },
        changes = { { type = "change", start_line = 1, end_line = 2 } },
        target_line = 1,
        revision = 2,
      }))
    end

    assert.equals(tabs_before + 2, #vim.api.nvim_list_tabpages())
    local buf_a = assert(buffer_mgr.find_buffer(buffer_mgr.normalize_path(real_a)))
    local buf_b = assert(buffer_mgr.find_buffer(buffer_mgr.normalize_path(real_b)))
    assert.is_not_nil(buffer_mgr.find_window_for_buf(buf_a))
    assert.is_not_nil(buffer_mgr.find_window_for_buf(buf_b))
  end)
end)
