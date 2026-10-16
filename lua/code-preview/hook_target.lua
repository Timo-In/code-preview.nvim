-- hook_target.lua — Determines whether agent hooks may target this Neovim.

local M = {}

--- Classify attached UIs without relying on GUI-specific global variables.
---@param uis table[]
---@param gui_running boolean
---@return boolean
function M.is_terminal(uis, gui_running)
  return type(uis) == "table" and #uis > 0 and not gui_running
end

--- Return true when an attached terminal UI is available.
---@return boolean
function M.has_terminal_ui()
  return M.is_terminal(vim.api.nvim_list_uis(), vim.fn.has("gui_running") == 1)
end

--- Return whether agent-hook RPCs may target this Neovim instance.
---@return boolean
function M.is_enabled()
  local cfg = require("code-preview").config or {}
  local hooks = cfg.hooks or {}
  if hooks.terminal_only ~= true then
    return true
  end
  return M.has_terminal_ui()
end

--- Return whether a hook payload belongs to this Neovim's current project.
---@param project_cwd string?
---@param target_file string?
---@return boolean
function M.matches_project(project_cwd, target_file)
  return require("code-preview.project").matches_current(project_cwd, target_file)
end

return M
