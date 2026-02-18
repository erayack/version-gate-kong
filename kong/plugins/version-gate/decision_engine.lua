local constants = require("kong.plugins.version-gate.constants")
local invariant = require("kong.plugins.version-gate.invariant")

local _M = {}

function _M.classify(expected_version, actual_version, expected_parse_reason, actual_parse_reason, policy)
  -- Policy-aware decision controls are introduced as an explicit boundary in Tier 1.
  -- Current behavior remains fail-open and reason-based.
  local _ = policy

  if expected_parse_reason ~= nil then
    return constants.DECISION_ALLOW, constants.REASON_PARSE_ERROR_EXPECTED
  end

  if actual_parse_reason ~= nil then
    return constants.DECISION_ALLOW, constants.REASON_PARSE_ERROR_ACTUAL
  end

  if expected_version == nil then
    return constants.DECISION_ALLOW, constants.REASON_MISSING_EXPECTED
  end

  if actual_version == nil then
    return constants.DECISION_ALLOW, constants.REASON_MISSING_ACTUAL
  end

  expected_version = tostring(expected_version)
  actual_version = tostring(actual_version)

  if invariant.is_violation(expected_version, actual_version) then
    return constants.DECISION_VIOLATION, constants.REASON_INVARIANT_VIOLATION
  end

  return constants.DECISION_ALLOW, constants.REASON_INVARIANT_OK
end

return _M
