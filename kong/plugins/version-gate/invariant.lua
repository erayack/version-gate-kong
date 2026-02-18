local _M = {}

function _M.is_violation(expected_version, actual_version)
  local expected_length = #expected_version
  local actual_length = #actual_version

  if actual_length ~= expected_length then
    return actual_length < expected_length
  end

  return actual_version < expected_version
end

return _M
