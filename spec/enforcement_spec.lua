local constants = require("kong.plugins.version-gate.constants")
local enforcement = require("kong.plugins.version-gate.enforcement")

describe("enforcement.handle", function()
  it("returns none action for shadow mode violations", function()
    local result = enforcement.handle(
      { mode = "shadow" },
      { decision = constants.DECISION_VIOLATION, reason = constants.REASON_INVARIANT_VIOLATION }
    )

    assert.equals(constants.ACTION_NONE, result.action)
    assert.is_nil(result.status)
    assert.is_nil(result.body)
    assert.is_nil(result.headers)
  end)

  it("returns annotate action with headers", function()
    local result = enforcement.handle(
      { mode = "annotate" },
      { decision = constants.DECISION_VIOLATION, reason = constants.REASON_INVARIANT_VIOLATION }
    )

    assert.equals(constants.ACTION_ANNOTATE, result.action)
    assert.is_not_nil(result.headers)
    assert.equals(constants.DECISION_VIOLATION, result.headers[constants.HEADER_DECISION])
    assert.equals(constants.REASON_INVARIANT_VIOLATION, result.headers[constants.HEADER_REASON])
    assert.equals("annotate", result.headers[constants.HEADER_MODE])
  end)

  it("returns reject action with defaults", function()
    local result = enforcement.handle(
      { mode = "reject" },
      { decision = constants.DECISION_VIOLATION, reason = constants.REASON_INVARIANT_VIOLATION }
    )

    assert.equals(constants.ACTION_REJECT, result.action)
    assert.equals(409, result.status)
    assert.is_table(result.body)
    assert.equals("version gate violation", result.body.message)
    assert.equals("reject", result.headers[constants.HEADER_MODE])
  end)

  it("uses policy override reject status when provided", function()
    local result = enforcement.handle(
      { mode = "reject" },
      { decision = constants.DECISION_VIOLATION, reason = constants.REASON_INVARIANT_VIOLATION },
      { reject_status_code = 451 }
    )

    assert.equals(constants.ACTION_REJECT, result.action)
    assert.equals(451, result.status)
  end)

  it("uses config reject status when policy override is absent", function()
    local result = enforcement.handle(
      { mode = "reject", reject_status_code = 429 },
      { decision = constants.DECISION_VIOLATION, reason = constants.REASON_INVARIANT_VIOLATION }
    )

    assert.equals(constants.ACTION_REJECT, result.action)
    assert.equals(429, result.status)
  end)

  it("uses configured reject body template", function()
    local result = enforcement.handle(
      { mode = "reject", reject_body_template = "minimal" },
      { decision = constants.DECISION_VIOLATION, reason = constants.REASON_INVARIANT_VIOLATION }
    )

    assert.equals(constants.ACTION_REJECT, result.action)
    assert.is_table(result.body)
    assert.equals("version gate violation", result.body.error)
    assert.equals(constants.REASON_INVARIANT_VIOLATION, result.body.reason)
    assert.is_nil(result.body.decision)
  end)

  it("uses policy reject body template override over config", function()
    local result = enforcement.handle(
      { mode = "reject", reject_body_template = "default" },
      { decision = constants.DECISION_VIOLATION, reason = constants.REASON_INVARIANT_VIOLATION },
      { reject_body_template = "minimal" }
    )

    assert.equals(constants.ACTION_REJECT, result.action)
    assert.equals("version gate violation", result.body.error)
    assert.is_nil(result.body.decision)
  end)

  it("falls back to default reject body template when configured template is invalid", function()
    local result = enforcement.handle(
      { mode = "reject", reject_body_template = "not-a-template" },
      { decision = constants.DECISION_VIOLATION, reason = constants.REASON_INVARIANT_VIOLATION }
    )

    assert.equals(constants.ACTION_REJECT, result.action)
    assert.equals("version gate violation", result.body.message)
    assert.equals(constants.DECISION_VIOLATION, result.body.decision)
    assert.equals(constants.REASON_INVARIANT_VIOLATION, result.body.reason)
  end)

  it("falls back to deprecated log_only=true compatibility", function()
    local result = enforcement.handle(
      { log_only = true },
      { decision = constants.DECISION_VIOLATION, reason = constants.REASON_INVARIANT_VIOLATION }
    )

    assert.equals(constants.ACTION_NONE, result.action)
  end)

  it("returns none for allow decisions", function()
    local result = enforcement.handle(
      { mode = "reject" },
      { decision = constants.DECISION_ALLOW, reason = constants.REASON_INVARIANT_OK }
    )

    assert.equals(constants.ACTION_NONE, result.action)
  end)

  it("returns none when reason is not configured for enforcement", function()
    local result = enforcement.handle(
      { mode = "reject" },
      { decision = constants.DECISION_VIOLATION, reason = constants.REASON_MISSING_ACTUAL },
      { enforce_on_reason = { constants.REASON_INVARIANT_VIOLATION } }
    )

    assert.equals(constants.ACTION_NONE, result.action)
  end)
end)
