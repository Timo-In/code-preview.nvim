local hook_target = require("code-preview.hook_target")
local plugin = require("code-preview")

describe("hook target eligibility", function()
  local saved_config
  local saved_has_terminal_ui

  before_each(function()
    saved_config = vim.deepcopy(plugin.config)
    saved_has_terminal_ui = hook_target.has_terminal_ui
  end)

  after_each(function()
    plugin.config = saved_config
    hook_target.has_terminal_ui = saved_has_terminal_ui
  end)

  it("requires an attached non-GUI UI for terminal classification", function()
    assert.is_false(hook_target.is_terminal({}, false))
    assert.is_true(hook_target.is_terminal({ { chan = 1 } }, false))
    assert.is_false(hook_target.is_terminal({ { chan = 1 } }, true))
  end)

  it("preserves existing behavior when terminal_only is disabled", function()
    plugin.config.hooks = { terminal_only = false }
    hook_target.has_terminal_ui = function() return false end
    assert.is_true(hook_target.is_enabled())
  end)

  it("rejects non-terminal clients when terminal_only is enabled", function()
    plugin.config.hooks = { terminal_only = true }
    hook_target.has_terminal_ui = function() return false end
    assert.is_false(hook_target.is_enabled())

    hook_target.has_terminal_ui = function() return true end
    assert.is_true(hook_target.is_enabled())
  end)

  it("makes hook RPC dispatch a no-op for an ineligible client", function()
    plugin.config.hooks = { terminal_only = true }
    hook_target.has_terminal_ui = function() return false end
    assert.equals("", require("code-preview.rpc").dispatch(
      "code-preview.pre_tool", "handle", "/path/that/must/not/be-read"))
  end)
end)
