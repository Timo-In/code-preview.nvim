-- Project identity and containment helpers shared by hook routing and previewd.

local M = {}

local is_windows = package.config:sub(1, 1) == "\\"

local function comparable(path)
  local value = path:gsub("\\", "/")
  if is_windows then value = value:lower() end
  local stripped = value:gsub("/+$", "")
  return stripped == "" and "/" or stripped
end

--- Return an absolute, canonical path when possible.
---@param path string?
---@param base string?
---@return string?
function M.normalize(path, base)
  if type(path) ~= "string" or path == "" then return nil end
  local value = vim.fn.expand(path)
  if not require("code-preview.platform").is_absolute(value) and base and base ~= "" then
    value = base .. "/" .. value
  end
  value = vim.fs.normalize(vim.fn.resolve(vim.fn.fnamemodify(value, ":p")))
  local uv = vim.uv or vim.loop
  local real = uv.fs_realpath(value)
  if real then return real end

  -- Canonicalize the nearest existing ancestor so nonexistent targets still
  -- compare correctly on platforms that expose alternate path spellings.
  local current = value
  local missing = {}
  while current and current ~= "" do
    table.insert(missing, 1, vim.fs.basename(current))
    local parent = vim.fs.dirname(current)
    if not parent or parent == current then break end
    current = parent
    real = uv.fs_realpath(current)
    if real then
      return vim.fs.normalize(real .. "/" .. table.concat(missing, "/"))
    end
  end

  return value
end

--- Return whether path is root itself or one of its descendants.
---@param root string?
---@param path string?
---@return boolean
function M.contains(root, path)
  root = M.normalize(root)
  path = M.normalize(path)
  if not root or not path then return false end
  local lhs, rhs = comparable(root), comparable(path)
  if lhs == "/" then return rhs:sub(1, 1) == "/" end
  return rhs == lhs or rhs:sub(1, #lhs + 1) == lhs .. "/"
end

local function git_root(path)
  local normalized = M.normalize(path)
  if not normalized then return nil end
  local stat = (vim.uv or vim.loop).fs_stat(normalized)
  local start = stat and stat.type == "directory" and normalized
    or vim.fn.fnamemodify(normalized, ":h")
  local root = vim.fs.root(start, { ".git" })
  return root and M.normalize(root) or nil
end

--- Return the stable identity used for a project/worktree.
---@param path string?
---@return string?
function M.root(path)
  return git_root(path) or M.normalize(path)
end

--- Return whether two working directories identify the same project.
---@param left string?
---@param right string?
---@return boolean
function M.same(left, right)
  local left_path, right_path = M.normalize(left), M.normalize(right)
  if not left_path or not right_path then return false end

  local left_git, right_git = git_root(left_path), git_root(right_path)
  if left_git or right_git then
    return left_git ~= nil and right_git ~= nil
      and comparable(left_git) == comparable(right_git)
  end

  return M.contains(left_path, right_path) or M.contains(right_path, left_path)
end

--- Validate a hook project and optional target against this Neovim instance.
---@param project_cwd string?
---@param target_file string?
---@return boolean
function M.matches_current(project_cwd, target_file)
  if not M.same(vim.fn.getcwd(), project_cwd) then return false end
  if not target_file or target_file == "" then return true end

  local project_root = M.root(project_cwd)
  local target = M.normalize(target_file, project_cwd)
  return M.contains(project_root, target)
end

return M
