-- pre_tool_handle_spec.lua — Smoke tests for the in-process orchestrator.
--
-- These exercise the happy paths and pin a few high-value invariants:
--   - Bash proposals mutate the changes registry but never open previews
--   - claudecode backend emits a permissionDecision JSON envelope
--   - other backends emit empty stdout
--   - unknown tool_name is a no-op (no crash)
--
-- Edit / Write / MultiEdit / ApplyPatch side effects bottom out in
-- diff.show_diff, which we don't drive UI for in tests — we only assert that
-- handle() does not raise.

local pre_tool = require("code-preview.pre_tool")
local changes  = require("code-preview.changes")

local function payload(tool_name, tool_input, cwd)
  return { tool_name = tool_name, cwd = cwd or "/proj", tool_input = tool_input }
end

describe("pre_tool.handle (Bash)", function()
  before_each(function() changes.clear_all() end)

  it("rm command marks file as deleted", function()
    local p = "/proj/gone.txt"
    pre_tool.handle(payload("Bash", { command = "rm gone.txt" }), "claudecode")
    assert.equals("deleted", changes.get(p))
  end)

  it("redirect to new file marks bash_created", function()
    local p = "/tmp/code-preview-test-" .. tostring(vim.loop.hrtime()) .. ".out"
    pre_tool.handle(payload("Bash", { command = "echo x > " .. p }), "claudecode")
    assert.equals("bash_created", changes.get(p))
  end)

  it("shell write to an existing file marks bash_modified", function()
    -- Portable across OSes: use the OS temp dir (no hardcoded /tmp) so the file
    -- can actually be created on disk on Windows too. Drive the same shell-write
    -- the agent would: a redirect on Unix, and a PowerShell Set-Content on
    -- Windows (Claude Code's PowerShell tool, folded onto Bash by the
    -- normaliser). Both route through handle_bash → shell_detect.
    local dir = vim.fn.fnamemodify(vim.fn.tempname(), ":h")
    -- Join with the native separator: the changes registry keys on
    -- fnamemodify(":p"), which does not flip separators on Windows, so a mixed
    -- path here would not match the detector's canonical backslash output.
    local sep = (vim.fn.has("win32") == 1) and "\\" or "/"
    local p = dir .. sep .. "code-preview-test-existing-" .. tostring(vim.loop.hrtime()) .. ".txt"
    local fh = assert(io.open(p, "w")); fh:write("hi"); fh:close()
    local cmd = (vim.fn.has("win32") == 1)
      and ('Set-Content -Path "' .. p .. '" -Value "x"')
      or  ("echo x > " .. p)
    pre_tool.handle(payload("Bash", { command = cmd }), "claudecode")
    assert.equals("bash_modified", changes.get(p))
    os.remove(p)
  end)

  it("read-only command leaves registry empty", function()
    pre_tool.handle(payload("Bash", { command = "ls -la" }), "claudecode")
    assert.equals(0, vim.tbl_count(changes.get_all()))
  end)

  it("rm and write in one command both register", function()
    pre_tool.handle(payload("Bash", { command = "rm old.txt && echo x > new.txt" }), "claudecode")
    assert.equals("deleted",      changes.get("/proj/old.txt"))
    assert.equals("bash_created", changes.get("/proj/new.txt"))
  end)
end)

describe("pre_tool.handle (emitter output)", function()
  it("claudecode emits permissionDecision JSON for Edit", function()
    local out = pre_tool.handle(
      payload("Edit", { file_path = "/tmp/x", old_string = "a", new_string = "b" }),
      "claudecode")
    assert.is_truthy(out:match("permissionDecision"))
    assert.is_truthy(out:match("PreToolUse"))
  end)

  it("claudecode emits nothing for Bash", function()
    local out = pre_tool.handle(payload("Bash", { command = "ls" }), "claudecode")
    assert.equals("", out)
  end)

  it("claudecode emits nothing for unknown tool", function()
    local out = pre_tool.handle(payload("Read", { file_path = "/tmp/x" }), "claudecode")
    assert.equals("", out)
  end)

  it("opencode emits empty stdout", function()
    local raw = { tool = "edit", cwd = "/proj", args = { filePath = "/tmp/x" } }
    local out = pre_tool.handle(raw, "opencode")
    assert.equals("", out)
  end)

  it("unknown backend emits empty stdout", function()
    local out = pre_tool.handle(payload("Edit", { file_path = "/tmp/x" }), "future-agent")
    assert.equals("", out)
  end)
end)

describe("pre_tool.handle (robustness)", function()
  before_each(function() changes.clear_all() end)

  it("unknown tool_name does not raise", function()
    assert.has_no.errors(function()
      pre_tool.handle(payload("UnknownTool", {}), "claudecode")
    end)
  end)

  it("missing tool_input does not raise", function()
    assert.has_no.errors(function()
      pre_tool.handle({ tool_name = "Bash", cwd = "/proj" }, "claudecode")
    end)
  end)

  it("rejects a routed request from another project", function()
    local other = vim.fn.tempname()
    vim.fn.mkdir(other, "p")
    pre_tool.handle(payload("Bash", { command = "rm should-not-register.txt" }), "claudecode", other)
    assert.equals(0, vim.tbl_count(changes.get_all()))
    vim.fn.delete(other, "rf")
  end)
end)

describe("pre_tool tempfile cleanup", function()
  it("preserves fresh files from other Neovim instances and removes stale files", function()
    local dir = vim.fn.has("win32") == 1
      and (os.getenv("TMP") or os.getenv("TEMP") or vim.fs.dirname(vim.fn.tempname()))
      or (os.getenv("TMPDIR") or "/tmp")
    dir = dir:gsub("\\", "/"):gsub("/$", "")
    local suffix = tostring(vim.uv.hrtime())
    local fresh = dir .. "/code-preview-diff-original-fresh-" .. suffix
    local stale = dir .. "/code-preview-diff-proposed-stale-" .. suffix
    vim.fn.writefile({ "fresh" }, fresh)
    vim.fn.writefile({ "stale" }, stale)
    local old = os.time() - (8 * 24 * 60 * 60)
    assert.is_true(vim.uv.fs_utime(stale, old, old))

    pre_tool.sweep_leftover_tempfiles()

    assert.equals(1, vim.fn.filereadable(fresh))
    assert.equals(0, vim.fn.filereadable(stale))
    pcall(vim.uv.fs_unlink, fresh)
    pcall(vim.uv.fs_unlink, stale)
  end)
end)
