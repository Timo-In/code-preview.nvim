-- pre_tool/init.lua — In-process orchestration for PreToolUse hooks.
--
-- The per-backend hook-entry shim passes the raw decoded hook JSON plus the
-- backend name; handle() does normalisation, tool dispatch, side effects
-- (changes registry, neo-tree refresh, diff.show_diff), and returns the
-- per-backend stdout bytes.
--
-- See docs/adr/0005-core-handler-runs-in-process.md.

local M = {}

local normalisers = require("code-preview.pre_tool.normalisers")
local emitters    = require("code-preview.pre_tool.emitters")
local shell_detect = require("code-preview.pre_tool.shell_detect")

local apply_edit       = require("code-preview.apply.edit")
local apply_multi_edit = require("code-preview.apply.multi_edit")
local apply_patch      = require("code-preview.apply.patch")

local changes  = require("code-preview.changes")
local neo_tree = require("code-preview.neo_tree")
local diff     = require("code-preview.diff")
local log      = require("code-preview.log")

-- ── Tempfile helpers ─────────────────────────────────────────────
-- The historical bash flow used $$ to namespace /tmp/claude-diff-* tempfiles.
-- In-process Lua uses hrtime + a monotonic counter so multiple proposals in
-- the same Neovim never collide. Tempfile prefix is now code-preview-* (see #60).

local _counter = 0
local TEMPFILE_MAX_AGE_SECONDS = 7 * 24 * 60 * 60
local function next_id()
  _counter = _counter + 1
  return string.format("%d-%d", vim.loop.hrtime(), _counter)
end

local function tmpdir()
  -- Windows has no /tmp, and $TMPDIR is usually unset there (it's a POSIX
  -- convention); a normal user nvim would otherwise fall through to "/tmp",
  -- which resolves to a nonexistent C:\tmp and makes every diff tempfile write
  -- fail. Use the standard Windows temp vars, falling back to nvim's own temp
  -- dir, and forward-slash it so it composes cleanly with the "/code-preview-*"
  -- suffixes below (issue #46). The Unix branch is left byte-identical — the
  -- macOS path and the shell E2E suite depend on $TMPDIR/"/tmp" exactly.
  if vim.fn.has("win32") == 1 then
    local dir = os.getenv("TMP") or os.getenv("TEMP")
      or vim.fn.fnamemodify(vim.fn.tempname(), ":h")
    return (dir:gsub("\\", "/"))
  end
  return os.getenv("TMPDIR") or "/tmp"
end

-- One-time startup sweep of stale proposal tempfiles.
--
-- Multiple Neovim instances share the system temp directory, so a startup
-- sweep must never remove another live instance's fresh proposal. Keep recent
-- files and only evict entries old enough to be abandoned.
--
-- The old claude-* patterns are matched transitionally so leftover tempfiles
-- from prior nvim sessions (pre-#60) still get cleaned up. Drop the old
-- patterns one release after this bridge ships, once users on the prior
-- version have had a chance to upgrade.
function M.sweep_leftover_tempfiles()
  local dir = tmpdir()
  local fd = vim.loop.fs_scandir(dir)
  if not fd then return end
  local cutoff = os.time() - TEMPFILE_MAX_AGE_SECONDS
  while true do
    local name = vim.loop.fs_scandir_next(fd)
    if not name then break end
    if name:match("^code%-preview%-diff%-original%-") or
       name:match("^code%-preview%-diff%-proposed%-") or
       name:match("^code%-preview%-patch%-") or
       -- transitional; drop in v1.2
       name:match("^claude%-diff%-original%-") or
       name:match("^claude%-diff%-proposed%-") or
       name:match("^claude%-patch%-") then
      local path = dir .. "/" .. name
      local stat = vim.loop.fs_stat(path)
      local modified = stat and stat.mtime and stat.mtime.sec
      if modified and modified < cutoff then
        pcall(vim.loop.fs_unlink, path)
      end
    end
  end
end

local function write_file(path, content)
  local fh = assert(io.open(path, "w"))
  fh:write(content or "")
  fh:close()
end

local function copy_or_empty(src_path, dst_path)
  local fh = io.open(src_path, "r")
  if fh then
    local content = fh:read("*a")
    fh:close()
    write_file(dst_path, content)
  else
    write_file(dst_path, "")
  end
end

-- ── In-process hook context (replaces hook_context RPC) ──────────

local function file_visible(file_path)
  if not file_path or file_path == "" then return false end
  local target = vim.uv.fs_realpath(file_path) or vim.fn.fnamemodify(file_path, ":p")
  for _, w in ipairs(vim.api.nvim_list_wins()) do
    local b = vim.api.nvim_win_get_buf(w)
    local raw = vim.api.nvim_buf_get_name(b)
    if raw ~= "" then
      local name = vim.uv.fs_realpath(raw) or vim.fn.fnamemodify(raw, ":p")
      if name == target then return true end
    end
  end
  return false
end

local function should_show(cfg, file_path)
  if not (cfg.diff and cfg.diff.visible_only) then return true end
  return file_visible(file_path)
end

-- ── Per-tool handlers ───────────────────────────────────────────

-- Label shown on the diff tab: the file path relative to the agent's cwd, or the
-- absolute path when the file isn't under cwd. The prefix test is
-- separator-insensitive so a backslashed Windows file_path still matches a
-- (possibly forward-slashed) cwd prefix — otherwise the relative-ization
-- silently fails on Windows and the tab falls back to the full absolute path.
-- The relative result is sliced from the ORIGINAL file_path, so it keeps its
-- native separators. Byte-identical on Unix, where the fold is skipped (a
-- backslash is a legal Unix filename character, not a separator).
local function display_path(file_path, cwd)
  if not cwd or cwd == "" then return file_path end
  local n = #cwd
  local fp, cw = file_path, cwd
  if package.config:sub(1, 1) == "\\" then
    fp = fp:gsub("\\", "/")
    cw = cw:gsub("\\", "/")
  end
  if fp:sub(1, n + 1) == cw .. "/" then
    return file_path:sub(n + 2)
  end
  return file_path
end
M.display_path = display_path  -- exposed for testing

-- Compute the orig/proposed tempfile pair for a single-file tool and hand off
-- to diff.show_diff (or skip when visible_only excludes the file). The only
-- per-tool variation is how `proposed_content` is computed, so each handler
-- below is a one-liner around this helper.
local function present_single_file(file_path, proposed_content, input, cfg, backend)
  local id = next_id()
  local orig = tmpdir() .. "/code-preview-diff-original-" .. id
  local prop = tmpdir() .. "/code-preview-diff-proposed-" .. id

  copy_or_empty(file_path, orig)
  write_file(prop, proposed_content)

  if not should_show(cfg, file_path) then
    log.info(log.fmt("pre_tool: skipping diff for %s (visible_only)", file_path))
    return
  end

  diff.show_diff(orig, prop, display_path(file_path, input.cwd), file_path, nil, backend)
  vim.notify(string.format("[code-preview] Reviewing %s (<leader>aq to close)", display_path(file_path, input.cwd)), vim.log.levels.INFO, { title = "code-preview" })
end

local function handle_edit(input, cfg, backend)
  local fp = input.tool_input.file_path
  local content = apply_edit.apply(
    fp,
    input.tool_input.old_string or "",
    input.tool_input.new_string or "",
    input.tool_input.replace_all == true
  )
  present_single_file(fp, content, input, cfg, backend)
end

local function handle_write(input, cfg, backend)
  local fp = input.tool_input.file_path
  present_single_file(fp, input.tool_input.content or "", input, cfg, backend)
end

local function handle_multi_edit(input, cfg, backend)
  local fp = input.tool_input.file_path
  local content = apply_multi_edit.apply(fp, input.tool_input.edits or {})
  present_single_file(fp, content, input, cfg, backend)
end

--- Parse Heredoc writes: cat << 'EOF' > file
local function parse_heredoc(cmd)
  local lines = vim.split(cmd, "\n")
  if #lines < 2 then return nil end
  local first = vim.trim(lines[1])
  local raw_delim, op, target = first:match("^cat%s+<<[%s%-]*([^%s>]+)%s*(>>?)%s*(.+)$")
  if not raw_delim then
    op, target, raw_delim = first:match("^cat%s*(>>?)%s*([^<]+)%s*<<[%s%-]*([^%s>]+)$")
  end
  if not raw_delim or not target then return nil end

  local delim = raw_delim:gsub("['\"]", ""):gsub("\\", "")
  target = vim.trim(target):gsub("['\"]", "")

  local body_lines = {}
  local found_delim = false
  for i = 2, #lines do
    local line = lines[i]
    if vim.trim(line) == delim then
      found_delim = true
      break
    end
    table.insert(body_lines, line)
  end

  if found_delim then
    return target, table.concat(body_lines, "\n") .. "\n", (op == ">>")
  end
  return nil
end

--- Parse echo "..." > file or printf "..." > file
local function parse_echo_or_printf(cmd)
  local verb, body, op, target = cmd:match("^%s*(echo)%s+[\"'](.-)[\"']%s*(>>?)%s*(.+)%s*$")
  if not verb then
    verb, body, op, target = cmd:match("^%s*(printf)%s+[\"'](.-)[\"']%s*(>>?)%s*(.+)%s*$")
  end
  if verb and body and target then
    target = vim.trim(target):gsub("['\"]", "")
    if verb == "echo" then
      body = body .. "\n"
    else
      body = body:gsub("\\n", "\n"):gsub("\\t", "\t")
    end
    return target, body, (op == ">>")
  end
  return nil
end

--- Shadow simulation for sed -i
local function simulate_sed(cmd, cwd)
  if not cmd:match("^%s*sed%s+%-i") then return nil end
  local parts = vim.split(cmd, "%s+")
  local target_token = parts[#parts]
  if not target_token or target_token == "" then return nil end
  target_token = target_token:gsub("['\"]", "")
  local target_path = (target_token:sub(1, 1) == "/" or target_token:sub(1, 2) == "~/")
    and vim.fn.expand(target_token)
    or (cwd .. "/" .. target_token)

  if vim.fn.filereadable(target_path) ~= 1 then return nil end

  local shadow = vim.fn.tempname() .. "_" .. vim.fn.fnamemodify(target_path, ":t")
  local uv = vim.uv or vim.loop
  uv.fs_copyfile(target_path, shadow)

  local shadow_cmd = cmd:gsub(vim.pesc(parts[#parts]) .. "%s*$", vim.fn.shellescape(shadow))
  local _ = vim.fn.system(shadow_cmd)
  if vim.v.shell_error == 0 and vim.fn.filereadable(shadow) == 1 then
    local lines = vim.fn.readfile(shadow)
    local content = table.concat(lines, "\n")
    if #lines > 0 then content = content .. "\n" end
    os.remove(shadow)
    return target_path, content
  end
  if vim.fn.filereadable(shadow) == 1 then os.remove(shadow) end
  return nil
end

local function handle_bash(input, cfg, backend)
  local cmd = input.tool_input.command or ""
  local cwd = input.cwd or ""
  local detected = shell_detect.detect(cmd, cwd)

  local touched = false

  -- rm first (rm wins for reveal precedence).
  for _, p in ipairs(detected.rm_paths) do
    changes.set(p, "deleted")
    touched = true
  end

  for _, p in ipairs(detected.write_paths) do
    local status = vim.uv.fs_stat(p) and "bash_modified" or "bash_created"
    changes.set(p, status)
    touched = true
  end

  if touched then
    log.info(log.fmt("pre_tool: bash rm=%d write=%d",
      #detected.rm_paths, #detected.write_paths))
    neo_tree.refresh()
    -- Reveal: rm beats write.
    local target = detected.rm_paths[1] or detected.write_paths[1]
    if target then
      neo_tree.reveal_deferred(target, 300)
    end
  end

  -- Tier 2 enhancement: Extract content diff for deterministic shell writes
  local preview_target, proposed_content
  local h_target, h_body, h_append = parse_heredoc(cmd)
  if h_target and h_body then
    preview_target = shell_detect.resolve_path(h_target, cwd)
    if h_append and vim.fn.filereadable(preview_target) == 1 then
      local orig = table.concat(vim.fn.readfile(preview_target), "\n") .. "\n"
      proposed_content = orig .. h_body
    else
      proposed_content = h_body
    end
  else
    local e_target, e_body, e_append = parse_echo_or_printf(cmd)
    if e_target and e_body then
      preview_target = shell_detect.resolve_path(e_target, cwd)
      if e_append and vim.fn.filereadable(preview_target) == 1 then
        local orig = table.concat(vim.fn.readfile(preview_target), "\n") .. "\n"
        proposed_content = orig .. e_body
      else
        proposed_content = e_body
      end
    else
      preview_target, proposed_content = simulate_sed(cmd, cwd)
    end
  end

  if preview_target and proposed_content then
    log.info(log.fmt("pre_tool: bash Tier 2 diff preview generated for %s", preview_target))
    present_single_file(preview_target, proposed_content, input, cfg, backend)
    -- diff.show_diff marks previews as modified/created. Preserve the Bash
    -- origin prefix so the post-hook only clears this proposal's own marker.
    changes.set(preview_target, vim.uv.fs_stat(preview_target) and "bash_modified" or "bash_created")
    return true
  end
  return false
end

local function handle_apply_patch(input, cfg, backend)
  local patch_text = input.tool_input and input.tool_input.patch_text
  if not patch_text or patch_text == "" then
    log.info("pre_tool: ApplyPatch with empty patch_text")
    return
  end

  local id = next_id()
  local outdir = tmpdir() .. "/code-preview-patch-out-" .. id
  vim.fn.mkdir(outdir, "p")

  local files = apply_patch.parse(patch_text, input.cwd or "")

  local function write_lines(path, lines)
    local fh = assert(io.open(path, "w"))
    for i, line in ipairs(lines) do
      fh:write(line)
      if i < #lines then fh:write("\n") end
    end
    if #lines > 0 then fh:write("\n") end
    fh:close()
  end

  for i, file in ipairs(files) do
    local tag = string.format("%02d", i)
    local orig = outdir .. "/" .. tag .. "-orig"
    local prop = outdir .. "/" .. tag .. "-prop"
    write_lines(orig, file.orig)
    write_lines(prop, file.prop)

    if should_show(cfg, file.path) then
      log.info(log.fmt("pre_tool: ApplyPatch send %s action=%s", file.rel_path, file.action))
      -- Label from the resolved absolute path, not file.rel_path: rel_path is
      -- whatever the model wrote in the `*** Update File:` directive, and some
      -- codex models (e.g. GPT 5.3) write an absolute path there, which would
      -- render the tab as `D:\...` instead of a cwd-relative label.
      diff.show_diff(orig, prop, display_path(file.path, input.cwd), file.path, file.action, backend)
      if #files <= 1 then
        vim.notify(string.format("[code-preview] Reviewing patch for %s (<leader>aq to close)", display_path(file.path, input.cwd)), vim.log.levels.INFO, { title = "code-preview" })
      end
    else
      log.info(log.fmt("pre_tool: ApplyPatch skip %s (visible_only)", file.rel_path))
    end
  end

  if #files > 1 then
    vim.notify(
      string.format("[code-preview] AI edited %d files across tabs (use gt/gT to navigate)", #files),
      vim.log.levels.INFO,
      { title = "code-preview" }
    )
  end
end

local dispatchers = {
  Edit       = handle_edit,
  Write      = handle_write,
  MultiEdit  = handle_multi_edit,
  Bash       = handle_bash,
  ApplyPatch = handle_apply_patch,
}

-- ── Public entry ─────────────────────────────────────────────────

--- Handle a normalised PreToolUse hook.
--- @param raw table  decoded hook payload (per-backend shape)
--- @param backend string  CODE_PREVIEW_BACKEND value
--- @param routed_cwd string?  project asserted by the hook-entry resolver
--- @return string  bytes the hook-entry shim should print to stdout
function M.handle(raw, backend, routed_cwd)
  local cfg = require("code-preview").config or {}
  local input = normalisers.normalise(raw, backend)
  local tool_name = input and input.tool_name

  if routed_cwd then
    local target_file = input and input.tool_input and input.tool_input.file_path or nil
    if not require("code-preview.hook_target").matches_project(routed_cwd, target_file) then
      log.warn(log.fmt("pre_tool: rejected cross-project route cwd=%s target=%s",
        tostring(routed_cwd), tostring(target_file)))
      return ""
    end
  end

  -- Auto-start Go preview daemon on demand for the current target/worktree
  pcall(function()
    local target = input and input.cwd or nil
    if not target or target == "" then
      local file_path = input and input.tool_input and input.tool_input.file_path or nil
      target = file_path and (vim.fs.root(file_path, { ".git" }) or file_path) or vim.fn.getcwd()
    end
    require("code-preview").ensure_daemon(target)
  end)

  log.info(log.fmt("pre_tool: tool=%s backend=%s", tostring(tool_name), tostring(backend)))

  local fn = dispatchers[tool_name]
  local has_preview = false
  if fn then
    local ok, res = pcall(fn, input, cfg, backend)
    if not ok then
      log.error("pre_tool: dispatch failed: " .. tostring(res))
    else
      if tool_name == "Bash" and res == true then
        has_preview = true
      end
    end
  end

  return emitters.emit(backend, {
    tool_name = tool_name,
    has_preview = has_preview,
    defer_claude_permissions = cfg.diff and cfg.diff.defer_claude_permissions or false,
  })
end

return M
