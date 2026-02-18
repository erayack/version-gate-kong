local constants = require("kong.plugins.version-gate.constants")
local decision_engine = require("kong.plugins.version-gate.decision_engine")

describe("decision_engine.classify", function()
  it("returns expected parse-error reason when expected parse fails", function()
    local decision, reason = decision_engine.classify(nil, "1", constants.REASON_PARSE_ERROR_EXPECTED, nil, {})

    assert.equals(constants.DECISION_ALLOW, decision)
    assert.equals(constants.REASON_PARSE_ERROR_EXPECTED, reason)
  end)

  it("returns actual parse-error reason when actual parse fails", function()
    local decision, reason = decision_engine.classify("1", nil, nil, constants.REASON_PARSE_ERROR_ACTUAL, {})

    assert.equals(constants.DECISION_ALLOW, decision)
    assert.equals(constants.REASON_PARSE_ERROR_ACTUAL, reason)
  end)

  it("classifies violations using precision-safe string versions", function()
    local decision, reason = decision_engine.classify("9007199254740994", "9007199254740993", nil, nil, {})

    assert.equals(constants.DECISION_VIOLATION, decision)
    assert.equals(constants.REASON_INVARIANT_VIOLATION, reason)
  end)
end)
