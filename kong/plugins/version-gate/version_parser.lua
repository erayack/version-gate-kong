local _M = {}

function _M.parse(raw, parse_error_reason)
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

return _M
