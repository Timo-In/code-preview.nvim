local binary = require("code-preview.binary")

describe("previewd binary", function()
  local original_executable
  local original_stdpath
  local original_system
  local temporary_paths

  before_each(function()
    original_executable = vim.fn.executable
    original_stdpath = vim.fn.stdpath
    original_system = vim.system
    temporary_paths = {}
  end)

  after_each(function()
    vim.fn.executable = original_executable
    vim.fn.stdpath = original_stdpath
    vim.system = original_system
    for _, path in ipairs(temporary_paths) do vim.fn.delete(path, "rf") end
  end)

  it("maps supported release targets", function()
    assert.equals("linux-amd64", binary.target("Linux", "x86_64"))
    assert.equals("linux-arm64", binary.target("Linux", "aarch64"))
    assert.equals("darwin-arm64", binary.target("Darwin", "arm64"))
    assert.equals("windows-amd64", binary.target("Windows_NT", "AMD64"))
  end)

  it("uses the executable suffix only on Windows", function()
    assert.equals("previewd-linux-amd64", binary.asset_name("Linux", "x86_64"))
    assert.equals("previewd-windows-arm64.exe", binary.asset_name("Windows_NT", "ARM64"))
  end)

  it("rejects unsupported targets", function()
    local target, err = binary.target("FreeBSD", "amd64")
    assert.is_nil(target)
    assert.matches("unsupported platform", err)
  end)

  it("prefers a locally built binary", function()
    vim.fn.stdpath = function() return "/test/data" end
    vim.fn.executable = function() return 1 end

    assert.equals("/plugin/bin/previewd", binary.resolve("/plugin"))
  end)

  it("falls back to the installed release binary", function()
    vim.fn.stdpath = function() return "/test/data" end
    vim.fn.executable = function(path)
      return path:find("/test/data/code%-preview/bin/previewd") and 1 or 0
    end

    assert.equals("/test/data/code-preview/bin/previewd", binary.resolve("/plugin"))
  end)

  it("downloads and verifies the release binary", function()
    local data_dir = vim.fn.tempname()
    table.insert(temporary_paths, data_dir)
    vim.fn.stdpath = function() return data_dir end
    vim.fn.executable = function(command) return command == "curl" and 1 or 0 end

    local asset = assert(binary.asset_name())
    local contents = "previewd-test-binary"
    vim.system = function(command)
      local destination = command[8]
      local url = command[9]
      local file = assert(io.open(destination, "wb"))
      if url:match("checksums%.txt$") then
        file:write(vim.fn.sha256(contents) .. "  " .. asset .. "\n")
      else
        file:write(contents)
      end
      file:close()
      return { wait = function() return { code = 0, stdout = "", stderr = "" } end }
    end

    local installed = assert(binary.install())
    local file = assert(io.open(installed, "rb"))
    assert.equals(contents, file:read("*a"))
    file:close()
    assert.equals(1, vim.fn.filereadable(installed))
  end)
end)
