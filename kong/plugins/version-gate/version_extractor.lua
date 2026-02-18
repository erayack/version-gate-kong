local constants = require("kong.plugins.version-gate.constants")

local _M = {}

function _M.parse_version(raw, parse_error_reason)
  if raw == nil then
    return nil, nil
  end

  local value = tostring(raw)
  if not value:match("^%d+$") then
    return nil, parse_error_reason
  end

  local normalized = value:gsub("^0+", "")
  if normalized == "" then
    normalized = "0"
  end

  return normalized, nil
end

function _M.get_expected_version(raw_expected)
  return _M.parse_version(raw_expected, constants.REASON_PARSE_ERROR_EXPECTED)
end

function _M.get_actual_version(raw_actual)
  return _M.parse_version(raw_actual, constants.REASON_PARSE_ERROR_ACTUAL)
end

return _M
