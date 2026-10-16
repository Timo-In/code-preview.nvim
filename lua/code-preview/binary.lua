local M = {}

local release_base = "https://github.com/Timo-In/code-preview.nvim/releases/latest/download"

local systems = {
  Darwin = "darwin",
  Linux = "linux",
  Windows_NT = "windows",
}

local architectures = {
  AMD64 = "amd64",
  amd64 = "amd64",
  x86_64 = "amd64",
  ARM64 = "arm64",
  aarch64 = "arm64",
  arm64 = "arm64",
}

local function executable_name(os_name)
  return os_name == "windows" and "previewd.exe" or "previewd"
end

---@param sysname string?
---@param machine string?
---@return string?, string?
function M.target(sysname, machine)
  local uname = vim.uv.os_uname()
  local os_name = systems[sysname or uname.sysname]
  local arch = architectures[machine or uname.machine]
  if not os_name or not arch then
    return nil, string.format(
      "unsupported platform: %s/%s",
      sysname or uname.sysname or "unknown",
      machine or uname.machine or "unknown"
    )
  end
  return os_name .. "-" .. arch
end

---@param sysname string?
---@param machine string?
---@return string?, string?
function M.asset_name(sysname, machine)
  local target, err = M.target(sysname, machine)
  if not target then return nil, err end
  local os_name = target:match("^([^-]+)")
  local suffix = os_name == "windows" and ".exe" or ""
  return "previewd-" .. target .. suffix
end

---@return string?, string?
function M.install_path()
  local target, err = M.target()
  if not target then return nil, err end
  local os_name = target:match("^([^-]+)")
  return vim.fs.normalize(vim.fn.stdpath("data") .. "/code-preview/bin/" .. executable_name(os_name))
end

---@param plugin_root string
---@return string?, string?
function M.resolve(plugin_root)
  local target, err = M.target()
  if not target then return nil, err end
  local os_name = target:match("^([^-]+)")
  local local_path = vim.fs.normalize(plugin_root .. "/bin/" .. executable_name(os_name))
  if vim.fn.executable(local_path) == 1 then return local_path end

  local installed_path = M.install_path()
  if installed_path and vim.fn.executable(installed_path) == 1 then return installed_path end
  return nil, "previewd is not installed; run :CodePreviewInstallBinary"
end

local function download(url, destination)
  local result = vim.system({
    "curl", "-fsSL", "--retry", "3", "--connect-timeout", "10",
    "-o", destination, url,
  }, { text = true }):wait()
  if result.code ~= 0 then
    local output = result.stderr ~= "" and result.stderr or result.stdout
    return nil, output ~= "" and output or "curl failed"
  end
  return true
end

local function verify_checksum(asset, binary_path, checksum_path)
  local checksums = io.open(checksum_path, "r")
  if not checksums then return nil, "failed to read checksums.txt" end
  local expected
  for line in checksums:lines() do
    local digest, name = line:match("^(%x+)%s+%*?(.+)$")
    if name == asset then
      expected = digest
      break
    end
  end
  checksums:close()
  if not expected then return nil, "checksum not found for " .. asset end

  local binary = io.open(binary_path, "rb")
  if not binary then return nil, "failed to read downloaded binary" end
  local actual = vim.fn.sha256(binary:read("*a"))
  binary:close()
  if actual ~= expected then return nil, "checksum mismatch for " .. asset end
  return true
end

---@return string?, string?
function M.install()
  if vim.fn.executable("curl") ~= 1 then
    return nil, "curl is required to download previewd"
  end

  local asset, asset_err = M.asset_name()
  if not asset then return nil, asset_err end
  local destination, path_err = M.install_path()
  if not destination then return nil, path_err end

  local directory = vim.fs.dirname(destination)
  vim.fn.mkdir(directory, "p")
  local temporary = destination .. ".tmp"
  local checksum_file = destination .. ".checksums.tmp"
  vim.fn.delete(temporary)
  vim.fn.delete(checksum_file)

  local ok, download_err = download(release_base .. "/" .. asset, temporary)
  if not ok then
    vim.fn.delete(temporary)
    return nil, "failed to download " .. asset .. ": " .. download_err
  end

  local checksum_ok, checksum_err = download(release_base .. "/checksums.txt", checksum_file)
  if not checksum_ok then
    vim.fn.delete(temporary)
    vim.fn.delete(checksum_file)
    return nil, "failed to download checksums.txt: " .. checksum_err
  end
  local verified, verify_err = verify_checksum(asset, temporary, checksum_file)
  vim.fn.delete(checksum_file)
  if not verified then
    vim.fn.delete(temporary)
    return nil, verify_err
  end

  local target = M.target()
  if target and not target:match("^windows%-") then
    local chmod_ok, chmod_err = vim.uv.fs_chmod(temporary, 493)
    if not chmod_ok then
      vim.fn.delete(temporary)
      return nil, "failed to make previewd executable: " .. tostring(chmod_err)
    end
  end

  local backup = destination .. ".old"
  vim.fn.delete(backup)
  local had_existing = vim.uv.fs_stat(destination) ~= nil
  if had_existing then
    local moved, move_err = vim.uv.fs_rename(destination, backup)
    if not moved then
      vim.fn.delete(temporary)
      return nil, "failed to replace existing previewd: " .. tostring(move_err)
    end
  end

  local renamed, rename_err = vim.uv.fs_rename(temporary, destination)
  if not renamed then
    if had_existing then vim.uv.fs_rename(backup, destination) end
    vim.fn.delete(temporary)
    return nil, "failed to install previewd: " .. tostring(rename_err)
  end
  vim.fn.delete(backup)
  return destination
end

return M
