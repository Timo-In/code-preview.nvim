local follow = require("code-preview.follow")

describe("preview viewport following", function()
  local saved_is_user_busy

  before_each(function()
    saved_is_user_busy = follow.is_user_busy
    vim.cmd("only")
    vim.cmd("enew!")
  end)

  after_each(function()
    follow.is_user_busy = saved_is_user_busy
    vim.cmd("only")
    vim.cmd("enew!")
  end)

  it("moves a background target without changing the active busy window", function()
    local active_win = vim.api.nvim_get_current_win()
    vim.cmd("rightbelow vnew")
    local target_win = vim.api.nvim_get_current_win()
    local target_buf = vim.api.nvim_get_current_buf()
    local lines = {}
    for i = 1, 30 do lines[i] = "line " .. i end
    vim.api.nvim_buf_set_lines(target_buf, 0, -1, false, lines)
    vim.api.nvim_set_current_win(active_win)

    follow.is_user_busy = function() return true end
    follow.follow_line(target_win, 24)

    assert.equals(active_win, vim.api.nvim_get_current_win())
    assert.equals(24, vim.api.nvim_win_get_cursor(target_win)[1])
  end)

  it("does not move the active window while the user is busy", function()
    local win = vim.api.nvim_get_current_win()
    vim.api.nvim_buf_set_lines(0, 0, -1, false, { "one", "two", "three" })
    follow.is_user_busy = function() return true end

    follow.follow_line(win, 3)

    assert.equals(1, vim.api.nvim_win_get_cursor(win)[1])
  end)
end)
