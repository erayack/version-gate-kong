local constants = require("kong.plugins.version-gate.constants")
local invariant = require("kong.plugins.version-gate.invariant")

local _M = {}

function _M.classify(expected_version, actual_version, parse_reason)
  if parse_reason ~= nil then
    return constants.DECISION_ALLOW, constants.REASON_PARSE_ERROR
  end

  if expected_version == nil then
    return constants.DECISION_ALLOW, constants.REASON_MISSING_EXPECTED
  end

  if actual_version == nil then
    return constants.DECISION_ALLOW, constants.REASON_MISSING_ACTUAL
  end

  if invariant.is_violation(expected_version, actual_version) then
    return constants.DECISION_VIOLATION, constants.REASON_INVARIANT_VIOLATION
  end

  return constants.DECISION_ALLOW, constants.REASON_INVARIANT_OK
end

return _M
