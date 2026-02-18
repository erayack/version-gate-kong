local constants = require("kong.plugins.version-gate.constants")
local enforcement = require("kong.plugins.version-gate.enforcement")

describe("enforcement.handle", function()
  it("emits warning for violations in tier-0 modes", function()
    local modes = { "shadow", "annotate", "reject" }

    for _, mode in ipairs(modes) do
      local called = false
      local message
      local decision_ctx

      enforcement.handle(
        { mode = mode },
        { decision = constants.DECISION_VIOLATION, mode = mode },
        function(msg, ctx)
          called = true
          message = msg
          decision_ctx = ctx
        end
      )

      assert.is_true(called)
      assert.equals("[version-gate] violation detected", message)
      assert.equals(constants.DECISION_VIOLATION, decision_ctx.decision)
    end
  end)

  it("falls back to deprecated log_only=true compatibility", function()
    local called = false

    enforcement.handle(
      { log_only = true },
      { decision = constants.DECISION_VIOLATION },
      function()
        called = true
      end
    )

    assert.is_true(called)
  end)

  it("does not emit warning for allow decisions", function()
    local called = false

    enforcement.handle(
      { mode = "shadow" },
      { decision = constants.DECISION_ALLOW, mode = "shadow" },
      function()
        called = true
      end
    )

    assert.is_false(called)
  end)
end)
