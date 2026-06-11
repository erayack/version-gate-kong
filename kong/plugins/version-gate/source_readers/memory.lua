local _M = {}

local function table_lookup_case_sensitive_or_lower(tbl, key)
  if type(tbl) ~= "table" or type(key) ~= "string" or key == "" then
    return nil
  end

  local value = tbl[key]
  if value ~= nil then
    return value
  end

  return tbl[key:lower()]
end

local function read_jwt_claim_from_token(token, claim_name)
  if type(token) ~= "table" then
    return nil
  end

  local claims = token.claims or token.payload
  if type(claims) ~= "table" then
    return nil
  end

  return claims[claim_name]
end

function _M.new(values)
  values = values or {}

  return {
    read_request_header = function(_, name)
      return table_lookup_case_sensitive_or_lower(values.request_headers or values.headers, name)
    end,

    read_response_header = function(_, name)
      return table_lookup_case_sensitive_or_lower(values.response_headers, name)
    end,

    read_request_query = function(_, name)
      return table_lookup_case_sensitive_or_lower(values.query or values.request_query, name)
    end,

    read_request_cookie = function(_, name)
      return table_lookup_case_sensitive_or_lower(values.cookies or values.request_cookies, name)
    end,

    read_request_jwt_claim = function(_, name)
      local direct_claims = values.jwt_claims
      if type(direct_claims) == "table" and direct_claims[name] ~= nil then
        return direct_claims[name]
      end

      return read_jwt_claim_from_token(values.authenticated_jwt_token or values.jwt_token, name)
    end,
  }
end

return _M
