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

local HOOK_NAMESPACE = "code-preview"
local TOOL_MATCHER   = "replace_file_content|multi_replace_file_content|write_to_file|run_command"

local HOOK_MARKERS = {
  "hook-entry",
  "code-preview",
}

local function is_our_command(cmd)
  cmd = tostring(cmd or "")
  for _, m in ipairs(HOOK_MARKERS) do
    if cmd:find(m, 1, true) then return true end
  end
  return false
end

local function global_hooks_path()
  local override = vim.env.CODE_PREVIEW_AGY_GLOBAL_HOOKS
  if override and override ~= "" then
    return override
  end
  local config_dir = vim.env.AGY_CONFIG_DIR
  if config_dir and config_dir ~= "" then
    return config_dir .. "/hooks.json"
  end
  return vim.fn.expand("~/.gemini/config/hooks.json")
end

local function local_hooks_path()
  local cwd = vim.fn.getcwd()
  local singular = cwd .. "/.agent/hooks.json"
  local plural   = cwd .. "/.agents/hooks.json"
  if vim.fn.filereadable(singular) == 1 and vim.fn.filereadable(plural) == 0 then
    return singular
  end
  return plural
end

local function hooks_path(scope)
  if scope == "global" then
    return global_hooks_path()
  end
  return local_hooks_path()
end

-- Parse JSON file. Returns:
--   ok=true,  data=<table>       — file present and parsed
--   ok=true,  data={}            — file missing or empty (treat as fresh)
--   ok=false, err=<string>       — file present but invalid JSON
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
  if not ok or type(data) ~= "table" then
    return false, tostring(data)
  end
  return true, data
end

local function write_json(path, data)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local f = assert(io.open(path, "w"), "Cannot write to " .. path)
  -- Empty table encodes as `[]` in vim.json.encode unless we emit `{}` explicitly.
  if vim.tbl_isempty(data) then
    f:write("{}\n")
  else
    f:write((vim.json.encode(data):gsub("\\/", "/")))
  end
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

local function ensure_executable(path)
  if vim.fn.filereadable(path) == 0 then
    vim.notify("[code-preview] script not found: " .. path, vim.log.levels.ERROR)
    return false
  end
  platform.make_executable(path)
  return true
end

--- Install Antigravity (agy) hooks into target scope ("global" or "local").
--- Defaults to "global" (~/.gemini/config/hooks.json) or "local" (.agents/hooks.json).
--- Merges non-destructively under the top-level "code-preview" named hook key.
--- @param scope string? "global"|"local"
function M.install(scope)
  scope = (scope == "local") and "local" or "global"
  local hook = hook_script()
  if not ensure_executable(hook) then return end

  local target_hooks = hooks_path(scope)
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
  local block = type(data[HOOK_NAMESPACE]) == "table" and data[HOOK_NAMESPACE] or {}
  block.PreToolUse  = remove_ours(block.PreToolUse)
  block.PostToolUse = remove_ours(block.PostToolUse)

  table.insert(block.PreToolUse, {
    matcher = TOOL_MATCHER,
    hooks   = { { type = "command", command = platform.hook_command(hook, "agy pre") } },
  })
  table.insert(block.PostToolUse, {
    matcher = TOOL_MATCHER,
    hooks   = { { type = "command", command = platform.hook_command(hook, "agy post") } },
  })

  data[HOOK_NAMESPACE] = block
  write_json(target_hooks, data)
  vim.notify(string.format("[code-preview] AGY hooks installed (%s) → %s", scope, target_hooks), vim.log.levels.INFO)
end

--- Uninstall Antigravity (agy) hooks from target scope ("global", "local", or both if nil).
--- Surgically removes only our hook entries while preserving all other named hooks.
--- @param scope string? "global"|"local"|nil
function M.uninstall(scope)
  scope = (scope == "global" or scope == "local") and scope or nil
  local scopes_to_clean = scope and { scope } or { "local", "global" }
  for _, s in ipairs(scopes_to_clean) do
    local path = hooks_path(s)
    if vim.fn.filereadable(path) == 1 then
      local ok, data_or_err = read_json(path)
      if ok and type(data_or_err) == "table" then
        local data = data_or_err
        for name, block in pairs(data) do
          if type(block) == "table" then
            if type(block.PreToolUse) == "table" then
              block.PreToolUse = remove_ours(block.PreToolUse)
              if #block.PreToolUse == 0 then block.PreToolUse = nil end
            end
            if type(block.PostToolUse) == "table" then
              block.PostToolUse = remove_ours(block.PostToolUse)
              if #block.PostToolUse == 0 then block.PostToolUse = nil end
            end
            if name == HOOK_NAMESPACE then
              local has_events = false
              for k, v in pairs(block) do
                if k ~= "enabled" and type(v) == "table" and #v > 0 then
                  has_events = true
                  break
                end
              end
              if not has_events then
                data[name] = nil
              end
            end
          end
        end
        write_json(path, data)
        vim.notify(string.format("[code-preview] AGY hooks uninstalled (%s) from %s", s, path), vim.log.levels.INFO)
      end
    end
  end
end

--- True iff target scope's hooks.json contains an entry referencing our adapter.
--- @param scope string? "global"|"local"|nil
--- @return boolean
function M.is_installed(scope)
  if scope then
    local ok, data = read_json(hooks_path(scope))
    if not ok or type(data) ~= "table" then return false end
    for _, block in pairs(data) do
      if type(block) == "table" then
        for _, ev in ipairs({ "PreToolUse", "PostToolUse" }) do
          for _, entry in ipairs(block[ev] or {}) do
            for _, h in ipairs(entry.hooks or {}) do
              if is_our_command(h.command) then return true end
            end
          end
        end
      end
    end
    return false
  end
  return M.is_installed("local") or M.is_installed("global")
end

--- Report AGY install state. Checks both local and global installations.
--- @return { state: "installed (global)"|"installed (local)"|"installed (local+global)"|"missing", warnings: string[]? }
function M.install_state()
  local local_ok  = M.is_installed("local")
  local global_ok = M.is_installed("global")

  if not local_ok and not global_ok then
    return { state = "missing" }
  end

  local scope_desc = (local_ok and global_ok and "local+global")
    or (local_ok and "local")
    or "global"

  return {
    state = "installed (" .. scope_desc .. ")",
  }
end

return M
