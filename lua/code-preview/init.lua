local M = {}

-- Module-level config, populated by setup()
M.config = {}

local default_config = {
  debug = false,  -- enable debug logging to stdpath("log")/code-preview.log
  hooks = {
    terminal_only = false, -- reject hook RPCs for headless/GUI Neovim instances
  },
  diff = {
    visible_only = false,  -- only show diffs for files open in a visible nvim window
    auto_close = false,    -- when false, keeps preview marks until closed with <leader>dq
    auto_closes = {},      -- override auto_close per backend: e.g. { claudecode = true, codex = false }
    linger_ms = 1500,      -- fade backgrounds after completion; signs remain until edit or save
    defer_claude_permissions = false,  -- when true, skip permissionDecision and let Claude Code's own settings decide
  },
  neo_tree = {
    enabled = true,
    -- reveal = false disables scroll-to-file in the tree. Change indicators
    -- (modified/created/deleted icons) still appear — to disable those too,
    -- set neo_tree.enabled = false.
    reveal = true,         -- reveal edited files in neo-tree
    reveal_root = "cwd",   -- "cwd" (default) or "git" (nearest git root)
    refresh_on_change = true,
    position = "right",
    symbols = {
      modified = "󰏫",
      created  = "󰎔",
      deleted  = "󰆴",
    },
    highlights = {
      modified = { fg = "#e8a838", bold = true },
      created  = { fg = "#56c8d8", bold = true },
      deleted  = { fg = "#e06c75", bold = true, strikethrough = true },
    },
  },
  keys = {
    -- Set any entry to false to skip that binding. Set `keys = false` to skip all.
    -- <Plug>(CodePreviewCloseAll) is always defined so users can map it themselves.
    close_all   = "<leader>dq", -- global; close diff and clear indicators
  },
}

local function deep_merge(base, override)
  local result = vim.deepcopy(base)
  for k, v in pairs(override) do
    if type(v) == "table" and type(result[k]) == "table" then
      result[k] = deep_merge(result[k], v)
    else
      result[k] = v
    end
  end
  return result
end

function M.setup(user_config)
  M.config = deep_merge(default_config, user_config or {})

  -- Initialise logging
  require("code-preview.log").init({ debug = M.config.debug })

  -- Self-register socket + cwd for hook-script discovery
  require("code-preview.pidfile").setup()

  -- Clear any leftover /tmp/code-preview-diff-* tempfiles from prior sessions
  -- (also matches the legacy /tmp/claude-diff-* prefix transitionally — see
  -- pre_tool.sweep_leftover_tempfiles).
  require("code-preview.pre_tool").sweep_leftover_tempfiles()

  -- ── New commands ──────────────────────────────────────────────

  local scope_opts = {
    nargs = "?",
    complete = function() return { "global", "local" } end,
  }

  vim.api.nvim_create_user_command("CodePreviewInstallClaudeCodeHooks", function(cmd_opts)
    local scope = cmd_opts.args ~= "" and cmd_opts.args or (M.config and M.config.default_scope) or "global"
    require("code-preview.backends.claudecode").install(scope)
  end, vim.tbl_extend("force", scope_opts, { desc = "Install code-preview PreToolUse/PostToolUse hooks for Claude Code [global|local]" }))

  vim.api.nvim_create_user_command("CodePreviewUninstallClaudeCodeHooks", function(cmd_opts)
    local scope = cmd_opts.args ~= "" and cmd_opts.args or nil
    require("code-preview.backends.claudecode").uninstall(scope)
  end, vim.tbl_extend("force", scope_opts, { desc = "Uninstall code-preview hooks for Claude Code [global|local]" }))

  vim.api.nvim_create_user_command("CodePreviewInstallOpenCodeHooks", function()
    require("code-preview.backends.opencode").install()
  end, { desc = "Install code-preview plugin for OpenCode" })

  vim.api.nvim_create_user_command("CodePreviewUninstallOpenCodeHooks", function()
    require("code-preview.backends.opencode").uninstall()
  end, { desc = "Uninstall code-preview plugin from OpenCode" })

  vim.api.nvim_create_user_command("CodePreviewInstallCopilotCliHooks", function()
    require("code-preview.backends.copilot").install()
  end, { desc = "Install code-preview hooks for GitHub Copilot CLI" })

  vim.api.nvim_create_user_command("CodePreviewUninstallCopilotCliHooks", function()
    require("code-preview.backends.copilot").uninstall()
  end, { desc = "Uninstall code-preview hooks for GitHub Copilot CLI" })

  vim.api.nvim_create_user_command("CodePreviewInstallCodexCliHooks", function(cmd_opts)
    local scope = cmd_opts.args ~= "" and cmd_opts.args or (M.config and M.config.default_scope) or "global"
    require("code-preview.backends.codex").install(scope)
  end, vim.tbl_extend("force", scope_opts, { desc = "Install code-preview hooks for OpenAI Codex CLI [global|local]" }))

  vim.api.nvim_create_user_command("CodePreviewUninstallCodexCliHooks", function(cmd_opts)
    local scope = cmd_opts.args ~= "" and cmd_opts.args or nil
    require("code-preview.backends.codex").uninstall(scope)
  end, vim.tbl_extend("force", scope_opts, { desc = "Uninstall code-preview hooks for OpenAI Codex CLI [global|local]" }))

  vim.api.nvim_create_user_command("CodePreviewInstallAgyHooks", function(cmd_opts)
    local scope = cmd_opts.args ~= "" and cmd_opts.args or (M.config and M.config.default_scope) or "global"
    require("code-preview.backends.agy").install(scope)
  end, vim.tbl_extend("force", scope_opts, { desc = "Install code-preview hooks for Antigravity (AGY) [global|local]" }))

  vim.api.nvim_create_user_command("CodePreviewUninstallAgyHooks", function(cmd_opts)
    local scope = cmd_opts.args ~= "" and cmd_opts.args or nil
    require("code-preview.backends.agy").uninstall(scope)
  end, vim.tbl_extend("force", scope_opts, { desc = "Uninstall code-preview hooks for Antigravity (AGY) [global|local]" }))

  vim.api.nvim_create_user_command("CodePreviewCloseDiff", function()
    require("code-preview.diff").close_diff_and_clear()
    require("code-preview.in_place").clear_preview()
  end, { desc = "Manually close code-preview diff and clear in-place preview" })

  vim.api.nvim_create_user_command("CodePreviewClear", function()
    require("code-preview.in_place").clear_preview()
  end, { desc = "Clear in-place preview marks on current buffer" })

  vim.api.nvim_create_user_command("CodePreviewClearAll", function()
    require("code-preview.in_place").clear_all()
    require("code-preview.diff").close_diff_and_clear()
  end, { desc = "Clear all in-place preview marks and diffs" })

  vim.api.nvim_create_user_command("CodePreviewStartDaemon", function(opts)
    local path = opts.args ~= "" and opts.args or vim.fn.getcwd()
    M.start_daemon(path)
  end, { nargs = "?", complete = "dir", desc = "Start Go previewd daemon for directory" })

  vim.api.nvim_create_user_command("CodePreviewStopDaemon", function()
    M.stop_daemon()
  end, { desc = "Stop Go previewd daemon" })

  vim.api.nvim_create_user_command("CodePreviewInstallBinary", function()
    local path, err = require("code-preview.binary").install()
    if path then
      vim.notify("[code-preview] Installed previewd at " .. path, vim.log.levels.INFO)
    else
      vim.notify("[code-preview] " .. err, vim.log.levels.ERROR)
    end
  end, { desc = "Download the previewd binary for this platform" })

  vim.api.nvim_create_user_command("CodePreviewMockTest", function()
    local res = require("code-preview.mock_test").run_simulation()
    vim.notify(table.concat(res, "\n"), vim.log.levels.INFO, { title = "code-preview mock test" })
  end, { desc = "Run in-place 10-iteration mock verification test" })

  vim.api.nvim_create_user_command("CodePreviewDemo", function()
    package.loaded["code-preview.renderer"] = nil
    local cur_buf = vim.api.nvim_get_current_buf()
    local renderer = require("code-preview.renderer")
    renderer.render(cur_buf, {
      { type = "add",    start_line = 1, end_line = 1 },
      { type = "change", start_line = 2, end_line = 2 },
      { type = "delete", at_line = 2, deleted_lines = { "  - local legacy_code = 'deleted'" } },
    })
    vim.notify("[code-preview] Visual demo applied: Green add, Cyan change, Gray delete. Press <leader>aq to clear.", vim.log.levels.INFO)
  end, { desc = "Show visual demo with fresh light-green and sign indicators" })

  vim.api.nvim_create_user_command("CodePreviewStatus", function()
    M.status()
  end, { desc = "Show code-preview status" })

  vim.api.nvim_create_user_command("CodePreviewToggleVisibleOnly", function()
    M.config.diff.visible_only = not M.config.diff.visible_only
    vim.notify(
      "code-preview: visible_only = " .. tostring(M.config.diff.visible_only),
      vim.log.levels.INFO,
      { title = "code-preview" }
    )
  end, { desc = "Toggle visible_only — show diffs only for open buffers vs all files" })

  -- Neo-tree integration (soft dependency)
  if M.config.neo_tree.enabled then
    require("code-preview.neo_tree").setup(M.config)
  end

  -- <Plug> mapping is always defined so users can bind it themselves
  -- regardless of the `keys` config (e.g. `keys = false` to disable defaults).
  vim.keymap.set("n", "<Plug>(CodePreviewCloseAll)", function()
    require("code-preview.diff").close_diff_and_clear()
  end, { desc = "Close code-preview diff" })

  if M.config.keys ~= false then
    local close_all = M.config.keys and M.config.keys.close_all
    if close_all then
      vim.keymap.set("n", close_all, "<Plug>(CodePreviewCloseAll)",
        { desc = "Close code-preview diff" })
    end
  end

  -- Auto-terminate daemon on editor exit
  local augroup = vim.api.nvim_create_augroup("CodePreviewDaemonLifecycle", { clear = true })
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = augroup,
    callback = function()
      M.stop_daemon()
    end,
    desc = "Stop code-preview Go daemon on exit",
  })
end

M.daemon_job = nil
M.daemon_target = nil
M.daemon_worktree = nil

--- Start Go previewd daemon
---@param watch_path string?
---@param debounce_ms integer?
function M.start_daemon(watch_path, debounce_ms)
  M.stop_daemon()

  local socket = vim.env.NVIM_LISTEN_ADDRESS or vim.v.servername
  if not socket or socket == "" then
    vim.notify("[code-preview] Neovim socket not found; cannot start daemon", vim.log.levels.ERROR)
    return
  end

  local this_source = debug.getinfo(1, "S").source:gsub("^@", "")
  local root = vim.fs.root(this_source, { ".git" }) or vim.fn.stdpath("config")
  local bin_path, bin_err = require("code-preview.binary").resolve(root)
  if not bin_path then
    vim.notify("[code-preview] " .. bin_err, vim.log.levels.ERROR)
    return
  end

  local project = require("code-preview.project")
  local target = project.normalize(watch_path or vim.fn.getcwd())
  local worktree = project.root(target)
  if not target or not worktree or not project.contains(worktree, target) then
    vim.notify("[code-preview] Invalid daemon target", vim.log.levels.ERROR)
    return
  end
  local debounce = debounce_ms or 80

  local cmd = {
    bin_path,
    "--socket", socket,
    "--worktree", worktree,
    "--path", target,
    "--debounce", tostring(debounce),
  }

  local job_id
  job_id = vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if data and #data > 0 and data[1] ~= "" then
        require("code-preview.log").debug("[daemon stdout] " .. table.concat(data, "\n"))
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 and data[1] ~= "" then
        require("code-preview.log").debug("[daemon stderr] " .. table.concat(data, "\n"))
      end
    end,
    on_exit = function(id, code)
      if M.daemon_job == id then
        M.daemon_job = nil
        M.daemon_target = nil
        M.daemon_worktree = nil
      end
      require("code-preview.log").info("[daemon] Exited with code " .. tostring(code))
    end,
  })
  M.daemon_job = job_id

  if M.daemon_job and M.daemon_job > 0 then
    M.daemon_target = target
    M.daemon_worktree = worktree
    vim.notify(string.format("[code-preview] Go Daemon started for %s (job=%d)", vim.fn.fnamemodify(target, ":~"), M.daemon_job), vim.log.levels.INFO)
  else
    vim.notify("[code-preview] Failed to start Go Daemon", vim.log.levels.ERROR)
  end
end

--- Stop Go previewd daemon
function M.stop_daemon()
  if M.daemon_job and M.daemon_job > 0 then
    pcall(vim.fn.jobstop, M.daemon_job)
    M.daemon_job = nil
  end
  M.daemon_target = nil
  M.daemon_worktree = nil
end

--- Ensure Go previewd daemon is running for target directory, start on-demand if missing
---@param target_path string?
---@param debounce_ms integer?
function M.ensure_daemon(target_path, debounce_ms)
  local target = require("code-preview.project").normalize(target_path or vim.fn.getcwd())
  local running = M.daemon_job and vim.fn.jobwait({ M.daemon_job }, 0)[1] == -1
  if not running or M.daemon_target ~= target then
    M.start_daemon(target, debounce_ms)
  end
end

--- Query hook context for the PreToolUse shell script.
--- Returns a JSON string with config + file visibility in a single RPC call.
--- @param file_path string absolute path of the file being edited
--- @return string JSON: { neo_tree_reveal, reveal_root, visible_only, file_visible }
function M.hook_context(file_path)
  local cfg = M.config
  local neo_tree_reveal = (cfg.neo_tree.enabled and cfg.neo_tree.reveal) and true or false
  local reveal_root = cfg.neo_tree.reveal_root or "cwd"
  local visible_only = cfg.diff.visible_only and true or false
  local defer_claude_permissions = cfg.diff.defer_claude_permissions and true or false

  local file_visible = false
  if visible_only and file_path ~= "" then
    -- fs_realpath returns the filesystem's canonical form, so case-insensitive
    -- volumes (e.g. default APFS) normalize automatically without per-OS logic.
    local target = vim.uv.fs_realpath(file_path) or vim.fn.fnamemodify(file_path, ":p")
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      local b = vim.api.nvim_win_get_buf(w)
      local raw = vim.api.nvim_buf_get_name(b)
      if raw ~= "" then
        local name = vim.uv.fs_realpath(raw) or vim.fn.fnamemodify(raw, ":p")
        if name == target then
          file_visible = true
          break
        end
      end
    end
  end

  local log = require("code-preview.log")

  return vim.json.encode({
    neo_tree_reveal = neo_tree_reveal,
    reveal_root = reveal_root,
    visible_only = visible_only,
    file_visible = file_visible,
    defer_claude_permissions = defer_claude_permissions,
    debug = log.is_enabled(),
    log_file = log.get_log_path() or "",
  })
end

function M.status()
  local lines = { "code-preview.nvim status", string.rep("─", 40) }

  -- Socket
  local socket = vim.env.NVIM_LISTEN_ADDRESS or ""
  if socket == "" then
    socket = vim.v.servername or ""
  end
  if socket ~= "" then
    table.insert(lines, "Neovim socket : " .. socket)
  else
    table.insert(lines, "Neovim socket : not found")
  end

  -- Pidfile (used by hook scripts for socket discovery)
  local pidfile = require("code-preview.pidfile").path()
  if vim.fn.filereadable(pidfile) == 1 then
    table.insert(lines, "Pidfile       : " .. pidfile)
  else
    table.insert(lines, "Pidfile       : not registered")
  end

  -- jq dependency
  local jq_ok = vim.fn.executable("jq") == 1
  table.insert(lines, "jq            : " .. (jq_ok and "found" or "MISSING"))

  -- Diff tab open?
  local diff = require("code-preview.diff")
  table.insert(lines, "Diff tab      : " .. (diff.is_open() and "open" or "closed"))

  -- Backends — each module exposes install_state() returning
  -- { state = "installed"|"missing", warnings = {...}? }. Rendering lives
  -- here; per-backend detection logic lives in the backend module.
  table.insert(lines, "")
  table.insert(lines, "Backends:")

  local BACKENDS = {
    { name = "claudecode", label = "Claude Code", install_cmd = ":CodePreviewInstallClaudeCodeHooks" },
    { name = "opencode",   label = "OpenCode   ", install_cmd = ":CodePreviewInstallOpenCodeHooks"   },
    { name = "copilot",    label = "Copilot CLI", install_cmd = ":CodePreviewInstallCopilotCliHooks" },
    { name = "codex",      label = "Codex CLI  ", install_cmd = ":CodePreviewInstallCodexCliHooks"   },
    { name = "agy",        label = "Antigravity", install_cmd = ":CodePreviewInstallAgyHooks"        },
  }

  for _, b in ipairs(BACKENDS) do
    local s = require("code-preview.backends." .. b.name).install_state()
    if s.state and s.state:match("^installed") then
      if s.warnings and #s.warnings > 0 then
        table.insert(lines, "  " .. b.label .. " : " .. s.state .. " BUT " .. table.concat(s.warnings, "; "))
      else
        table.insert(lines, "  " .. b.label .. " : " .. s.state)
      end
    else
      table.insert(lines, "  " .. b.label .. " : not installed  ->  " .. b.install_cmd .. " [global|local]")
    end
  end

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "code-preview" })
end

return M
