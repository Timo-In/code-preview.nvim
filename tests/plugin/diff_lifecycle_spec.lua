-- diff_lifecycle_spec.lua — Tests for the diff module lifecycle

local diff = require("code-preview.diff")
local changes = require("code-preview.changes")

-- Helper: write a temp file with content and return the path
local function tmp_file(name, content)
	local path = vim.fn.tempname() .. "_" .. name
	local f = io.open(path, "w")
	f:write(content)
	f:close()
	return path
end

describe("diff lifecycle", function()
	before_each(function()
		changes.clear_all()
    diff.close_diff_and_clear()
    vim.cmd("silent! tabonly")
  end)

  after_each(function()
    diff.close_diff_and_clear()
    vim.cmd("silent! tabonly")
	end)

	it("show_diff opens a diff tab", function()
		local orig = tmp_file("orig.txt", "line one\nline two\nline three")
		local prop = tmp_file("prop.txt", "line one\nline TWO\nline three\nline four")

		diff.show_diff(orig, prop, "test.txt")
		assert.is_true(diff.is_open())

		os.remove(orig)
		os.remove(prop)
	end)

	it("close_diff closes the tab", function()
		local orig = tmp_file("orig2.txt", "hello")
		local prop = tmp_file("prop2.txt", "world")

		diff.show_diff(orig, prop, "test2.txt")
		assert.is_true(diff.is_open())

		diff.close_diff()
		assert.is_false(diff.is_open())

		os.remove(orig)
		os.remove(prop)
	end)

  it("show_diff keeps different file previews active", function()
		local orig1 = tmp_file("a_orig.txt", "aaa")
		local prop1 = tmp_file("a_prop.txt", "bbb")
		local orig2 = tmp_file("b_orig.txt", "ccc")
		local prop2 = tmp_file("b_prop.txt", "ddd")

		diff.show_diff(orig1, prop1, "a.txt")
		assert.is_true(diff.is_open())

		diff.show_diff(orig2, prop2, "b.txt")
		assert.is_true(diff.is_open())

		os.remove(orig1)
		os.remove(prop1)
		os.remove(orig2)
		os.remove(prop2)
	end)

	it("is_open returns false with no active diff", function()
		diff.close_diff()
		assert.is_false(diff.is_open())
	end)

	it("close_diff_and_clear clears changes too", function()
		local orig = tmp_file("clear_orig.txt", "x")
		local prop = tmp_file("clear_prop.txt", "y")

		changes.set("/tmp/some_file.lua", "modified")
		diff.show_diff(orig, prop, "clear.txt")

		assert.equals(1, vim.tbl_count(changes.get_all()))

		diff.close_diff_and_clear()

		assert.is_false(diff.is_open())
		assert.equals(0, vim.tbl_count(changes.get_all()))

		os.remove(orig)
		os.remove(prop)
	end)

	it("is_open with file_path only matches the tagged file", function()
		local orig = tmp_file("tag_orig.txt", "aaa")
		local prop = tmp_file("tag_prop.txt", "bbb")

		-- Pass abs_file_path as 4th arg to tag the diff
		diff.show_diff(orig, prop, "tag.txt", "/abs/path/tag.txt")

		assert.is_true(diff.is_open())                   -- no arg: any diff is open
		assert.is_true(diff.is_open("/abs/path/tag.txt")) -- matching file
		assert.is_false(diff.is_open("/abs/path/other.txt")) -- different file

		diff.close_diff()
		os.remove(orig)
		os.remove(prop)
	end)

	it("show_diff opens multiple tabs for different files simultaneously", function()
		local orig1 = tmp_file("q_orig1.txt", "file1 original")
		local prop1 = tmp_file("q_prop1.txt", "file1 proposed")
		local orig2 = tmp_file("q_orig2.txt", "file2 original")
		local prop2 = tmp_file("q_prop2.txt", "file2 proposed")

		-- Open diff for file1
		diff.show_diff(orig1, prop1, "file1.txt", "/abs/file1.txt")
		assert.is_true(diff.is_open("/abs/file1.txt"))

		-- Show diff for file2 while file1 is open — both should be active
		diff.show_diff(orig2, prop2, "file2.txt", "/abs/file2.txt")
		assert.is_true(diff.is_open("/abs/file1.txt")) -- file1 still open
		assert.is_true(diff.is_open("/abs/file2.txt")) -- file2 also open

		-- Close file1's diff — file2 should remain
		diff.close_for_file("/abs/file1.txt")
		assert.is_false(diff.is_open("/abs/file1.txt"))
		assert.is_true(diff.is_open("/abs/file2.txt"))

		-- Close file2
		diff.close_for_file("/abs/file2.txt")
		assert.is_false(diff.is_open())

		os.remove(orig1)
		os.remove(prop1)
		os.remove(orig2)
		os.remove(prop2)
	end)

  it("close_for_file clears preview state without closing the real file tab", function()
		local orig = tmp_file("stale_orig.txt", "before")
		local prop = tmp_file("stale_prop.txt", "after")

		diff.show_diff(orig, prop, "stale.txt", "/abs/stale.txt")
		assert.is_true(diff.is_open("/abs/stale.txt"))

		-- Record the tab handle before closing
		local tab_before = nil
		for _, entry in pairs(diff._active_diffs()) do
			tab_before = entry.tab
		end
		assert.is_not_nil(tab_before)

		diff.close_for_file("/abs/stale.txt")

		-- The diff must be gone from the active set
		assert.is_false(diff.is_open("/abs/stale.txt"))

    assert.is_true(vim.api.nvim_tabpage_is_valid(tab_before))

		os.remove(orig)
		os.remove(prop)
	end)

	it("show_diff with action=delete marks the file as deleted in the changes registry", function()
		local orig = tmp_file("del_orig.txt", "to be removed\n")
		local prop = tmp_file("del_prop.txt", "")

		-- abs_file_path must point to a real on-disk file — `mark_change_and_reveal`
		-- only honors the delete hint for files that currently exist.
		local abs = tmp_file("del_abs.txt", "to be removed\n")

		diff.show_diff(orig, prop, "deleted.txt", abs, "delete")
		assert.equals("deleted", changes.get(abs))

		diff.close_for_file(abs)
		os.remove(orig)
		os.remove(prop)
		os.remove(abs)
	end)

	it("show_diff without action does NOT mark a truncation-to-empty as deleted", function()
		-- Regression guard: a legitimate "edit file down to zero bytes" must
		-- show as modified, not deleted.
		local orig = tmp_file("trunc_orig.txt", "stub content\n")
		local prop = tmp_file("trunc_prop.txt", "")
		local abs = tmp_file("trunc_abs.txt", "stub content\n")

		diff.show_diff(orig, prop, "trunc.txt", abs)
		assert.equals("modified", changes.get(abs))

		diff.close_for_file(abs)
		os.remove(orig)
		os.remove(prop)
		os.remove(abs)
	end)

	it("close_diff_and_clear closes all active diffs", function()
		local orig1 = tmp_file("drain_orig1.txt", "aaa")
		local prop1 = tmp_file("drain_prop1.txt", "bbb")
		local orig2 = tmp_file("drain_orig2.txt", "ccc")
		local prop2 = tmp_file("drain_prop2.txt", "ddd")

		diff.show_diff(orig1, prop1, "drain1.txt", "/abs/drain1.txt")
		diff.show_diff(orig2, prop2, "drain2.txt", "/abs/drain2.txt")

		assert.is_true(diff.is_open("/abs/drain1.txt"))
		assert.is_true(diff.is_open("/abs/drain2.txt"))

		-- close_diff_and_clear should close both diffs
		diff.close_diff_and_clear()
		assert.is_false(diff.is_open())

		os.remove(orig1)
		os.remove(prop1)
		os.remove(orig2)
		os.remove(prop2)
	end)
end)

describe("single-buffer preview mode", function()
	before_each(function()
		changes.clear_all()
		diff.close_diff_and_clear()
    vim.cmd("silent! tabonly")
  end)

  after_each(function()
    diff.close_diff_and_clear()
    vim.cmd("silent! tabonly")
	end)

	it("opens an unseen real file in a dedicated single-window tab", function()
		local real = tmp_file("single_real.txt", "line1\nline2")
		local orig = tmp_file("single_orig.txt", "line1\nline2")
		local prop = tmp_file("single_prop.txt", "line1\nchanged")

		local tabs_before = #vim.api.nvim_list_tabpages()

		diff.show_diff(orig, prop, real, real, nil, "opencode")

		assert.is_true(diff.is_open())
		assert.equals(tabs_before + 1, #vim.api.nvim_list_tabpages())
		assert.equals(1, #vim.api.nvim_tabpage_list_wins(vim.api.nvim_get_current_tabpage()))
    assert.equals(
      require("code-preview.project").normalize(real),
      require("code-preview.project").normalize(vim.api.nvim_buf_get_name(0))
    )
    assert.is_false(vim.bo[vim.api.nvim_get_current_buf()].swapfile)
		assert.same({ "line1", "changed" }, vim.api.nvim_buf_get_lines(0, 0, -1, false))

		diff.close_diff()
		os.remove(real)
		os.remove(orig)
		os.remove(prop)
	end)

	it("reuses a target that is already visible", function()
		local real = tmp_file("visible_real.txt", "alpha\nbeta")
		local orig = tmp_file("visible_orig.txt", "alpha\nbeta")
		local prop = tmp_file("visible_prop.txt", "alpha\ngamma")

		vim.cmd("edit " .. vim.fn.fnameescape(real))

		local tabs_before = #vim.api.nvim_list_tabpages()

		diff.show_diff(orig, prop, real, real, nil, "codex")

		assert.is_true(diff.is_open())
		assert.equals(tabs_before, #vim.api.nvim_list_tabpages())
    assert.equals(
      require("code-preview.project").normalize(real),
      require("code-preview.project").normalize(vim.api.nvim_buf_get_name(0))
    )

		diff.close_diff_and_clear()
		os.remove(real)
		os.remove(orig)
		os.remove(prop)
	end)

	it("opens different unseen files in different tabs", function()
		local real_a = tmp_file("multi_a.txt", "a")
		local real_b = tmp_file("multi_b.txt", "b")
		local orig_a = tmp_file("multi_orig_a.txt", "a")
		local orig_b = tmp_file("multi_orig_b.txt", "b")
		local prop_a = tmp_file("multi_prop_a.txt", "aa")
		local prop_b = tmp_file("multi_prop_b.txt", "bb")

		local tabs_before = #vim.api.nvim_list_tabpages()

		diff.show_diff(orig_a, prop_a, real_a, real_a, nil, "opencode")
		diff.show_diff(orig_b, prop_b, real_b, real_b, nil, "opencode")

		assert.is_true(diff.is_open(real_a))
		assert.is_true(diff.is_open(real_b))
		assert.equals(tabs_before + 2, #vim.api.nvim_list_tabpages())

		diff.close_diff_and_clear()
		for _, path in ipairs({ real_a, real_b, orig_a, orig_b, prop_a, prop_b }) do
			os.remove(path)
		end
	end)
end)
