local constants = require("kong.plugins.version-gate.constants")

local _M = {}

function _M.parse_version(raw)
  if raw == nil then
    return nil, nil
  end

  local value = tostring(raw)
  if not value:match("^%d+$") then
    return nil, constants.REASON_PARSE_ERROR
  end

  local parsed = tonumber(value)
  if parsed == nil then
    return nil, constants.REASON_PARSE_ERROR
  end

  return parsed, nil
end

function _M.get_expected_version(raw_expected)
  return _M.parse_version(raw_expected)
end

function _M.get_actual_version(raw_actual)
  return _M.parse_version(raw_actual)
end

return _M
