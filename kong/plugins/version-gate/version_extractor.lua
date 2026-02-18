local constants = require("kong.plugins.version-gate.constants")

local _M = {}

local STRATEGY_HEADER = "header"
local STRATEGY_QUERY = "query"
local STRATEGY_JWT_CLAIM = "jwt_claim"
local STRATEGY_COOKIE = "cookie"

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

local function read_request_header(request_ctx, header_name)
  if type(request_ctx) == "table" then
    local from_headers = table_lookup_case_sensitive_or_lower(request_ctx.headers, header_name)
    if from_headers ~= nil then
      return from_headers
    end

    if type(request_ctx.get_header) == "function" then
      return request_ctx.get_header(header_name)
    end

    if type(request_ctx.request) == "table" and type(request_ctx.request.get_header) == "function" then
      return request_ctx.request.get_header(header_name)
    end
  end

  if kong ~= nil and kong.request ~= nil and type(kong.request.get_header) == "function" then
    return kong.request.get_header(header_name)
  end

  return nil
end

local function read_response_header(response_ctx, header_name)
  if type(response_ctx) == "table" then
    local from_headers = table_lookup_case_sensitive_or_lower(response_ctx.headers, header_name)
    if from_headers ~= nil then
      return from_headers
    end

    if type(response_ctx.get_header) == "function" then
      return response_ctx.get_header(header_name)
    end

    if type(response_ctx.response) == "table" and type(response_ctx.response.get_header) == "function" then
      return response_ctx.response.get_header(header_name)
    end
  end

  if kong ~= nil and kong.response ~= nil and type(kong.response.get_header) == "function" then
    return kong.response.get_header(header_name)
  end

  return nil
end

local function read_request_query(request_ctx, param_name)
  if type(request_ctx) == "table" then
    local from_query = table_lookup_case_sensitive_or_lower(request_ctx.query, param_name)
    if from_query ~= nil then
      return from_query
    end

    if type(request_ctx.get_query_arg) == "function" then
      return request_ctx.get_query_arg(param_name)
    end

    if type(request_ctx.request) == "table" and type(request_ctx.request.get_query_arg) == "function" then
      return request_ctx.request.get_query_arg(param_name)
    end
  end

  if kong ~= nil and kong.request ~= nil and type(kong.request.get_query_arg) == "function" then
    return kong.request.get_query_arg(param_name)
  end

  return nil
end

local function read_request_cookie(request_ctx, cookie_name)
  if type(request_ctx) == "table" then
    local from_cookies = table_lookup_case_sensitive_or_lower(request_ctx.cookies, cookie_name)
    if from_cookies ~= nil then
      return from_cookies
    end

    if type(request_ctx.get_cookie) == "function" then
      return request_ctx.get_cookie(cookie_name)
    end

    if type(request_ctx.request) == "table" and type(request_ctx.request.get_cookie) == "function" then
      return request_ctx.request.get_cookie(cookie_name)
    end
  end

  if kong ~= nil and kong.request ~= nil and type(kong.request.get_cookie) == "function" then
    return kong.request.get_cookie(cookie_name)
  end

  return nil
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

local function read_request_jwt_claim(request_ctx, claim_name)
  if type(request_ctx) == "table" then
    local direct_claims = request_ctx.jwt_claims
    if type(direct_claims) == "table" and direct_claims[claim_name] ~= nil then
      return direct_claims[claim_name]
    end

    local token = request_ctx.authenticated_jwt_token or request_ctx.jwt_token
    local claim_from_token = read_jwt_claim_from_token(token, claim_name)
    if claim_from_token ~= nil then
      return claim_from_token
    end

    local kong_ctx = request_ctx.kong_ctx
    if type(kong_ctx) == "table" and type(kong_ctx.shared) == "table" then
      local claim_from_shared = read_jwt_claim_from_token(kong_ctx.shared.authenticated_jwt_token, claim_name)
      if claim_from_shared ~= nil then
        return claim_from_shared
      end
    end

    local ngx_ctx = request_ctx.ngx_ctx
    if type(ngx_ctx) == "table" then
      local claim_from_ngx = read_jwt_claim_from_token(ngx_ctx.authenticated_jwt_token, claim_name)
      if claim_from_ngx ~= nil then
        return claim_from_ngx
      end
    end
  end

  if kong ~= nil and kong.ctx ~= nil and type(kong.ctx.shared) == "table" then
    local claim_from_shared = read_jwt_claim_from_token(kong.ctx.shared.authenticated_jwt_token, claim_name)
    if claim_from_shared ~= nil then
      return claim_from_shared
    end
  end

  if ngx ~= nil and type(ngx.ctx) == "table" then
    local claim_from_ngx = read_jwt_claim_from_token(ngx.ctx.authenticated_jwt_token, claim_name)
    if claim_from_ngx ~= nil then
      return claim_from_ngx
    end
  end

  return nil
end

local function get_expected_raw(conf, request_ctx)
  local strategy = conf.expected_source_strategy or STRATEGY_HEADER

  if strategy == STRATEGY_QUERY then
    return read_request_query(request_ctx, conf.expected_query_param_name)
  end

  if strategy == STRATEGY_JWT_CLAIM then
    return read_request_jwt_claim(request_ctx, conf.expected_jwt_claim_name)
  end

  if strategy == STRATEGY_COOKIE then
    return read_request_cookie(request_ctx, conf.expected_cookie_name)
  end

  return read_request_header(request_ctx, conf.expected_header_name)
end

local function get_actual_raw(conf, response_ctx)
  local strategy = conf.actual_source_strategy or STRATEGY_HEADER

  if strategy == STRATEGY_QUERY then
    return read_request_query(response_ctx, conf.actual_query_param_name)
  end

  if strategy == STRATEGY_JWT_CLAIM then
    return read_request_jwt_claim(response_ctx, conf.actual_jwt_claim_name)
  end

  if strategy == STRATEGY_COOKIE then
    return read_request_cookie(response_ctx, conf.actual_cookie_name)
  end

  return read_response_header(response_ctx, conf.actual_header_name)
end

function _M.get_expected_raw(conf, request_ctx)
  return get_expected_raw(conf or {}, request_ctx)
end

function _M.get_actual_raw(conf, response_ctx)
  return get_actual_raw(conf or {}, response_ctx)
end

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

function _M.get_expected_version(conf, request_ctx)
  local raw_expected = _M.get_expected_raw(conf, request_ctx)
  return _M.parse_version(raw_expected, constants.REASON_PARSE_ERROR_EXPECTED)
end

function _M.get_actual_version(conf, response_ctx)
  local raw_actual = _M.get_actual_raw(conf, response_ctx)
  return _M.parse_version(raw_actual, constants.REASON_PARSE_ERROR_ACTUAL)
end

return _M
