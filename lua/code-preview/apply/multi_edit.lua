-- apply/multi_edit.lua — Apply a MultiEdit (sequential edits) to a file.
--
-- Pure function: reads the file, applies each edit in order with literal
-- (non-pattern) replacement, returns the resulting content as a string.
-- Edits that don't match are skipped silently (matches historical behaviour).

local M = {}

--- @param file_path string  absolute path to the file (may not exist)
--- @param edits table  list of {old_string, new_string}
--- @return string  the resulting file content
function M.apply(file_path, edits)
  local content = ""
  local fh = io.open(file_path, "r")
  if fh then
    content = fh:read("*a")
    fh:close()
  end

  for _, edit in ipairs(edits or {}) do
    local old = edit.old_string or ""
    local new = edit.new_string or ""
    if old == "" then
      content = new .. content
    elseif edit.replace_all then
      local parts = {}
      local search_start = 1
      while true do
        local s, e = string.find(content, old, search_start, true)
        if not s then
          table.insert(parts, content:sub(search_start))
          break
        end
        table.insert(parts, content:sub(search_start, s - 1))
        table.insert(parts, new)
        search_start = e + 1
      end
      content = table.concat(parts)
    else
      local s, e = string.find(content, old, 1, true)
      if s then
        content = content:sub(1, s - 1) .. new .. content:sub(e + 1)
      end
    end
  end

  return content
end

return M
