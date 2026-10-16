local plugin = require("code-preview")

describe("previewd lifecycle", function()
  local original
  local paths
  local starts
  local stops

  before_each(function()
    original = {
      executable = vim.fn.executable,
      jobstart = vim.fn.jobstart,
      jobstop = vim.fn.jobstop,
      jobwait = vim.fn.jobwait,
      notify = vim.notify,
      listen = vim.env.NVIM_LISTEN_ADDRESS,
    }
    paths = {}
    starts = {}
    stops = {}
    vim.env.NVIM_LISTEN_ADDRESS = "/tmp/code-preview-test.sock"
    vim.fn.executable = function() return 1 end
    vim.fn.jobstart = function(cmd)
      table.insert(starts, cmd)
      return 100 + #starts
    end
    vim.fn.jobstop = function(job)
      table.insert(stops, job)
      return 1
    end
    vim.fn.jobwait = function() return { -1 } end
    vim.notify = function() end
    plugin.daemon_job = nil
    plugin.daemon_target = nil
    plugin.daemon_worktree = nil
  end)

  after_each(function()
    plugin.daemon_job = nil
    plugin.daemon_target = nil
    plugin.daemon_worktree = nil
    vim.fn.executable = original.executable
    vim.fn.jobstart = original.jobstart
    vim.fn.jobstop = original.jobstop
    vim.fn.jobwait = original.jobwait
    vim.notify = original.notify
    vim.env.NVIM_LISTEN_ADDRESS = original.listen
    for _, path in ipairs(paths) do vim.fn.delete(path, "rf") end
  end)

  local function make_project()
    local path = vim.fn.tempname()
    vim.fn.mkdir(path .. "/.git", "p")
    table.insert(paths, path)
    return path
  end

  it("reuses one daemon for the same target and restarts for another", function()
    local first = make_project()
    local second = make_project()

    plugin.ensure_daemon(first)
    plugin.ensure_daemon(first)
    plugin.ensure_daemon(second)

    assert.equals(2, #starts)
    assert.same({ 101 }, stops)
    assert.equals(require("code-preview.project").normalize(second), plugin.daemon_target)

    local second_cmd = starts[2]
    assert.equals("--worktree", second_cmd[4])
    assert.equals(require("code-preview.project").root(second), second_cmd[5])
  end)
end)
