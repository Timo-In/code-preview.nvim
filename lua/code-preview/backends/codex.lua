local M = {}

-- Resolve plugin root from this file's location
local function plugin_root()
  local src = debug.getinfo(1, "S").source
  local lua_file = src:sub(2)
  local lua_dir = vim.fn.fnamemodify(lua_file, ":h")
  -- Go up three levels: backends/ → code-preview/ → lua/ → plugin root
  return vim.fn.fnamemodify(lua_dir, ":h:h:h")
end

local platform = require("code-preview.platform")

local function bin_dir()     return plugin_root() .. "/bin" end
local function hook_script() return bin_dir() .. "/hook-entry" .. platform.script_ext() end

local function global_codex_dir()
  local codex_home = vim.env.CODEX_HOME
  if codex_home and codex_home ~= "" then
    return codex_home
  end
  return vim.fn.expand("~/.codex")
end

local function codex_dir(scope)
  if scope == "global" then
    return global_codex_dir()
  end
  return vim.fn.getcwd() .. "/.codex"
end

local function hooks_path(scope)   return codex_dir(scope) .. "/hooks.json" end
local function config_path(scope)  return codex_dir(scope) .. "/config.toml" end

-- Markers we use to identify our hook entries when merging with user-authored
-- hooks. The Codex docs allow multiple hooks per event, so we cooperate rather
-- than overwrite. "hook-entry" is the current generic shim (ADR-0008); the
-- code-preview-diff / code-close-diff stems match older per-backend installs so
-- uninstall still cleans them up after an upgrade. Matched as substrings, so
-- they work across OSes and slash styles.
local HOOK_MARKERS = {
  "hook-entry",
  "code-preview-diff",
  "code-close-diff",
}

local function is_our_command(cmd)
  cmd = tostring(cmd or "")
  for _, m in ipairs(HOOK_MARKERS) do
    if cmd:find(m, 1, true) then return true end
  end
  return false
end

-- Parse JSON file. Returns:
--   ok=true,  data=<table>       — file present and parsed
--   ok=true,  data={}            — file missing or empty (treat as fresh)
--   ok=false, err=<string>       — file present but invalid JSON
-- Distinguishing "missing" from "invalid" matters for install: a corrupted
-- hooks.json should NOT be silently overwritten (data loss).
local function read_json(path)
  if vim.fn.filereadable(path) == 0 then
    return true, {}
  end
  local f = io.open(path, "r")
  if not f then
    return true, {}
  end
  local raw = f:read("*a") or ""
  f:close()
  if raw == "" then return true, {} end
  local ok, data = pcall(vim.json.decode, raw)
  if not ok then
    return false, tostring(data)
  end
  return true, data or {}
end

local function write_json(path, data)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = assert(io.open(path, "w"), "Cannot write to " .. path)
  f:write(vim.json.encode(data))
  f:close()
end

-- Filter out hook entries whose command contains our marker, so install is
-- idempotent and uninstall doesn't touch user-authored entries.
local function remove_ours(list)
  local filtered = {}
  for _, entry in ipairs(list or {}) do
    local keep = true
    for _, h in ipairs(entry.hooks or {}) do
      if is_our_command(h.command) then
        keep = false
        break
      end
    end
    if keep then table.insert(filtered, entry) end
  end
  return filtered
end

-- Per-file probe for the Codex hooks feature flag. Returns one of:
--   "enabled"  — file explicitly sets `hooks` (or legacy `codex_hooks`) to true
--   "disabled" — file explicitly sets the same to false
--   nil        — file is missing or expresses no opinion (use default)
-- Modern Codex enables hooks by default and accepts either `hooks` (canonical)
-- or `codex_hooks` (deprecated alias) under [features]. We match either.
local function file_flag_state(path)
  if vim.fn.filereadable(path) == 0 then return nil end
  local f = io.open(path, "r")
  if not f then return nil end
  local content = f:read("*a") or ""
  f:close()
  -- Loose match — handles whitespace & quotes but not deeply parsed; users
  -- with exotic TOML are responsible for it. Order matters only for the
  -- explicit-false detection: we surface disabled iff no enabling line exists.
  if content:match("hooks%s*=%s*true") or content:match("codex_hooks%s*=%s*true") then
    return "enabled"
  end
  if content:match("hooks%s*=%s*false") or content:match("codex_hooks%s*=%s*false") then
    return "disabled"
  end
  return nil
end

local function global_config_path()
  -- Test-only override: lets tests redirect the global path away from the
  -- user's real ~/.codex/config.toml. Production callers don't set this.
  local override = vim.env.CODE_PREVIEW_CODEX_GLOBAL_CONFIG
  if override and override ~= "" then return override end
  -- Codex resolves its global config dir from $CODEX_HOME (default ~/.codex).
  -- Honour it so users who relocate their Codex home — more common on Windows
  -- (issue #46) — get the right path. expand("~") already resolves the
  -- platform home, so the fallback works on Windows too.
  local codex_home = vim.env.CODEX_HOME
  if codex_home and codex_home ~= "" then
    return codex_home .. "/config.toml"
  end
  return vim.fn.expand("~/.codex/config.toml")
end

--- Resolve the effective state of Codex's `hooks` feature flag.
--- Project-local config wins over the global config; in the absence of any
--- explicit setting, Codex defaults to enabled, so we do too.
--- @param scope string? "global"|"local"
--- @return "enabled"|"disabled"
local function feature_flag_state(scope)
  if scope == "global" then
    local g_state = file_flag_state(global_config_path())
    if g_state ~= nil then return g_state end
    return "enabled"
  end
  local local_state = file_flag_state(config_path("local"))
  if local_state ~= nil then return local_state end
  local global_state = file_flag_state(global_config_path())
  if global_state ~= nil then return global_state end
  return "enabled"
end

local function ensure_executable(path)
  if vim.fn.filereadable(path) == 0 then
    vim.notify("[code-preview] script not found: " .. path, vim.log.levels.ERROR)
    return false
  end
  platform.make_executable(path)  -- chmod +x on Unix; no-op on Windows
  return true
end

--- Install Codex hooks into target scope ("global" or "local").
--- Defaults to "global" so hooks work seamlessly across all projects.
--- @param scope string? "global"|"local"
function M.install(scope)
  scope = (scope == "local") and "local" or "global"
  local hook = hook_script()
  if not ensure_executable(hook) then return end

  local target_dir = codex_dir(scope)
  local target_hooks = hooks_path(scope)
  vim.fn.mkdir(target_dir, "p")

  -- Merge with existing hooks rather than overwrite, since the user may have
  -- their own entries (logging, prompt scrubbing, etc.) and Codex supports
  -- stacking multiple hooks per event. Bail if the existing file is invalid
  -- JSON — overwriting would silently destroy whatever the user had.
  local ok, data_or_err = read_json(target_hooks)
  if not ok then
    vim.notify(
      "[code-preview] Refusing to install: " .. target_hooks
        .. " is not valid JSON (" .. data_or_err .. "). Fix or delete it, then retry.",
      vim.log.levels.ERROR
    )
    return
  end
  local data = data_or_err
  data.hooks              = data.hooks or {}
  data.hooks.PreToolUse   = remove_ours(data.hooks.PreToolUse)
  data.hooks.PostToolUse  = remove_ours(data.hooks.PostToolUse)

  table.insert(data.hooks.PreToolUse, {
    matcher = "",
    hooks   = { { type = "command", command = platform.hook_command(hook, "codex pre") } },
  })
  table.insert(data.hooks.PostToolUse, {
    matcher = "",
    hooks   = { { type = "command", command = platform.hook_command(hook, "codex post") } },
  })

  write_json(target_hooks, data)
  vim.notify(string.format("[code-preview] Codex hooks installed (%s) → %s", scope, target_hooks), vim.log.levels.INFO)

  -- Modern Codex enables hooks by default — no config.toml entry needed. We
  -- only nudge the user if they've *explicitly* opted out via `hooks = false`
  -- (or the legacy `codex_hooks = false`) under `[features]`.
  if feature_flag_state(scope) == "disabled" then
    vim.notify(
      "[code-preview] Codex hooks are disabled in your config: `[features] hooks = false` (or `codex_hooks = false`) is set in "
        .. config_path(scope) .. " or " .. global_config_path()
        .. ". Remove the line, or set `hooks = true`, before running Codex.",
      vim.log.levels.WARN
    )
  end
end

--- Uninstall Codex hooks from target scope ("global", "local", or both if nil).
--- @param scope string? "global"|"local"|nil
function M.uninstall(scope)
  scope = (scope == "global" or scope == "local") and scope or nil
  local scopes_to_clean = scope and { scope } or { "local", "global" }
  for _, s in ipairs(scopes_to_clean) do
    local path = hooks_path(s)
    if vim.fn.filereadable(path) == 1 then
      local ok, data_or_err = read_json(path)
      if ok and data_or_err.hooks then
        local data = data_or_err
        data.hooks.PreToolUse  = remove_ours(data.hooks.PreToolUse)
        data.hooks.PostToolUse = remove_ours(data.hooks.PostToolUse)
        write_json(path, data)
        vim.notify(string.format("[code-preview] Codex hooks uninstalled (%s) from %s", s, path), vim.log.levels.INFO)
      end
    end
  end
end

-- Exposed so :CodePreviewStatus can report whether the feature flag is set
-- without duplicating the parser.
function M.feature_flag_state(scope) return feature_flag_state(scope) end

--- Report Codex install state. Checks both local and global installations.
--- @return { state: "installed (global)"|"installed (local)"|"installed (local+global)"|"missing", warnings: string[]? }
function M.install_state()
  local local_ok = M.is_installed("local")
  local global_ok = M.is_installed("global")

  if not local_ok and not global_ok then
    return { state = "missing" }
  end

  local warnings = {}
  if feature_flag_state() == "disabled" then
    table.insert(warnings, "hooks explicitly disabled in config.toml (`[features] hooks = false`)")
  end

  local scope_desc = (local_ok and global_ok and "local+global")
    or (local_ok and "local")
    or "global"

  return {
    state = "installed (" .. scope_desc .. ")",
    warnings = #warnings > 0 and warnings or nil,
  }
end

--- True iff target scope's hooks.json contains an entry referencing our adapter.
--- If scope is nil, returns true if either local or global is installed.
--- @param scope string? "global"|"local"|nil
--- @return boolean
function M.is_installed(scope)
  if scope then
    local ok, data = read_json(hooks_path(scope))
    if not ok or not data.hooks then return false end
    for _, ev in ipairs({ "PreToolUse", "PostToolUse" }) do
      for _, entry in ipairs(data.hooks[ev] or {}) do
        for _, h in ipairs(entry.hooks or {}) do
          if is_our_command(h.command) then return true end
        end
      end
    end
    return false
  end
  return M.is_installed("local") or M.is_installed("global")
end

return M
