local project = require("code-preview.project")

local function make_dir()
  local path = vim.fn.tempname()
  vim.fn.mkdir(path, "p")
  return path
end

describe("project identity", function()
  local paths
  local original_cwd

  before_each(function()
    paths = {}
    original_cwd = vim.fn.getcwd()
  end)

  after_each(function()
    vim.cmd("cd " .. vim.fn.fnameescape(original_cwd))
    for _, path in ipairs(paths) do
      vim.fn.delete(path, "rf")
    end
  end)

  it("uses path boundaries for containment", function()
    local root = make_dir()
    paths = { root, root .. "-other" }
    vim.fn.mkdir(root .. "/src", "p")
    vim.fn.mkdir(root .. "-other", "p")

    assert.is_true(project.contains(root, root .. "/src/main.lua"))
    assert.is_false(project.contains(root, root .. "-other/main.lua"))
  end)

  it("matches directories in the same git worktree", function()
    local root = make_dir()
    paths = { root }
    vim.fn.mkdir(root .. "/.git", "p")
    vim.fn.mkdir(root .. "/src/nested", "p")

    assert.is_true(project.same(root, root .. "/src/nested"))
  end)

  it("separates nested git worktrees", function()
    local root = make_dir()
    paths = { root }
    vim.fn.mkdir(root .. "/.git", "p")
    vim.fn.mkdir(root .. "/vendor/child/.git", "p")

    assert.is_false(project.same(root, root .. "/vendor/child"))
  end)

  it("rejects a target outside the routed project", function()
    local root = make_dir()
    local outside = make_dir()
    paths = { root, outside }
    vim.fn.mkdir(root .. "/.git", "p")
    vim.cmd("cd " .. vim.fn.fnameescape(root))

    assert.is_false(project.matches_current(root, outside .. "/escape.lua"))
  end)
end)
