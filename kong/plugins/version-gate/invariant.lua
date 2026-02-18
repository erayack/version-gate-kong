local _M = {}

function _M.is_violation(expected_version, actual_version)
  return actual_version < expected_version
end

return _M
