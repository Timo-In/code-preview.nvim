local M = {}

-- Resolve the absolute path to the plugin's bin/ directory.
-- We use debug.getinfo so this works regardless of where the plugin is installed.
-- Resolve plugin root from this file's location
local function plugin_root()
  local src = debug.getinfo(1, "S").source
  -- src is "@/absolute/path/to/lua/code-preview/backends/claudecode.lua"
  local lua_file = src:sub(2)                            -- strip leading "@"
  local lua_dir  = vim.fn.fnamemodify(lua_file, ":h")    -- .../lua/code-preview/backends
  -- Go up three levels: backends/ → code-preview/ → lua/ → plugin root
  return vim.fn.fnamemodify(lua_dir, ":h:h:h")
end

-- Path to shared utilities (bin/)
local function bin_dir()
  return plugin_root() .. "/bin"
end

local platform = require("code-preview.platform")

-- Markers identifying our hook entries. "hook-entry" is the current stem
-- (bin/hook-entry.{sh,ps1}); "code-preview" / "claude-preview" match older
-- installs (the per-backend code-preview-diff shim, and the legacy name) so
-- uninstall still cleans them up after an upgrade.
local HOOK_MARKERS = { "hook-entry", "code-preview", "claude-preview" }

local function is_our_command(cmd)
  cmd = tostring(cmd or "")
  for _, m in ipairs(HOOK_MARKERS) do
    if cmd:find(m, 1, true) then return true end
  end
  return false
end

-- Tools whose proposals we intercept. On Windows, Claude Code exposes a
-- distinct `PowerShell` tool alongside `Bash` and routes shell file ops
-- (Remove-Item / Move-Item / Set-Content …) through it — observed with the
-- Haiku model, which deletes via `Remove-Item`. Without `PowerShell` in the
-- matcher the PreToolUse hook never fires for those proposals, so a shell
-- delete/write never marks neo-tree (issue #46 follow-up). The normaliser
-- folds `PowerShell` into the canonical `Bash` path; here we just make sure
-- the hook fires. Harmless on Unix (no such tool is ever emitted there).
local TOOL_MATCHER = "Edit|Write|MultiEdit|Bash|PowerShell"

local function settings_path(scope)
  if scope == "global" then
    return vim.fn.expand("~/.claude/settings.json")
  end
  return vim.fn.getcwd() .. "/.claude/settings.local.json"
end

local function read_settings(path)
  local f = io.open(path, "r")
  if not f then return {} end
  local raw = f:read("*a")
  f:close()
  if raw == "" then return {} end
  local ok, data = pcall(vim.json.decode, raw)
  return ok and data or {}
end

local function write_settings(path, data)
  -- Ensure parent directory exists
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = assert(io.open(path, "w"), "Cannot write to " .. path)
  f:write(vim.json.encode(data))
  f:close()
end

-- Remove entries matching either the current or legacy hook marker.
-- This lets users who installed with the old name uninstall after upgrading.
local function remove_ours(list)
  local filtered = {}
  for _, entry in ipairs(list or {}) do
    local cmd = ""
    if entry.hooks and entry.hooks[1] then
      cmd = tostring(entry.hooks[1].command or "")
    end
    if not is_our_command(cmd) then
      table.insert(filtered, entry)
    end
  end
  return filtered
end

--- True iff target scope has our hook installed.
--- @param scope string? "global"|"local"|nil
--- @return boolean
function M.is_installed(scope)
  if scope then
    local path = settings_path(scope)
    local f = io.open(path, "r")
    if not f then return false end
    local content = f:read("*a") or ""
    f:close()
    return is_our_command(content)
  end
  return M.is_installed("local") or M.is_installed("global")
end

--- Install Claude Code hooks into target scope ("global" or "local").
--- Defaults to "global" so hooks work seamlessly across all projects.
--- @param scope string? "global"|"local"
function M.install(scope)
  scope = (scope == "local") and "local" or "global"
  -- One generic shim per OS, parameterized by backend + event (ADR-0008).
  local hook = bin_dir() .. "/hook-entry" .. platform.script_ext()

  if vim.fn.filereadable(hook) == 0 then
    vim.notify("[code-preview] hook script not found: " .. hook, vim.log.levels.ERROR)
    return
  end
  platform.make_executable(hook)

  local path = settings_path(scope)
  local data = read_settings(path)

  -- Initialise missing structure
  data.hooks = data.hooks or {}
  data.hooks.PreToolUse  = data.hooks.PreToolUse  or {}
  data.hooks.PostToolUse = data.hooks.PostToolUse or {}

  data.hooks.PreToolUse  = remove_ours(data.hooks.PreToolUse)
  data.hooks.PostToolUse = remove_ours(data.hooks.PostToolUse)

  -- The command invokes the shim with the backend + event; on Windows
  -- platform.hook_command wraps it in `powershell -File …`. See ADR-0007/0008.
  table.insert(data.hooks.PreToolUse, {
    matcher = TOOL_MATCHER,
    hooks   = { { type = "command", command = platform.hook_command(hook, "claudecode pre") } },
  })
  table.insert(data.hooks.PostToolUse, {
    matcher = TOOL_MATCHER,
    hooks   = { { type = "command", command = platform.hook_command(hook, "claudecode post") } },
  })

  write_settings(path, data)
  vim.notify(string.format("[code-preview] Claude Code hooks installed (%s) → %s", scope, path), vim.log.levels.INFO)
end

--- Report whether the Claude Code hooks are wired up.
--- @return { state: "installed (global)"|"installed (local)"|"installed (local+global)"|"missing", warnings: string[]? }
function M.install_state()
  local local_ok = M.is_installed("local")
  local global_ok = M.is_installed("global")

  if not local_ok and not global_ok then
    return { state = "missing" }
  end

  local scope_desc = (local_ok and global_ok and "local+global")
    or (local_ok and "local")
    or "global"

  return { state = "installed (" .. scope_desc .. ")" }
end

--- Uninstall Claude Code hooks from target scope ("global", "local", or both if nil).
--- @param scope string? "global"|"local"|nil
function M.uninstall(scope)
  scope = (scope == "global" or scope == "local") and scope or nil
  local scopes_to_clean = scope and { scope } or { "local", "global" }
  for _, s in ipairs(scopes_to_clean) do
    local path = settings_path(s)
    if vim.fn.filereadable(path) == 1 then
      local data = read_settings(path)
      if data.hooks then
        data.hooks.PreToolUse  = remove_ours(data.hooks.PreToolUse or {})
        data.hooks.PostToolUse = remove_ours(data.hooks.PostToolUse or {})
        write_settings(path, data)
        vim.notify(string.format("[code-preview] Claude Code hooks uninstalled (%s) from %s", s, path), vim.log.levels.INFO)
      end
    end
  end
end

return M
