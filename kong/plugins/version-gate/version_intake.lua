local constants = require("kong.plugins.version-gate.constants")
local version_parser = require("kong.plugins.version-gate.version_parser")

local _M = {}

local STRATEGY_HEADER = "header"
local STRATEGY_QUERY = "query"
local STRATEGY_JWT_CLAIM = "jwt_claim"
local STRATEGY_COOKIE = "cookie"

local function read_raw(reader, strategy, name, header_scope)
  if strategy == STRATEGY_QUERY then
    return reader:read_request_query(name)
  end

  if strategy == STRATEGY_JWT_CLAIM then
    return reader:read_request_jwt_claim(name)
  end

  if strategy == STRATEGY_COOKIE then
    return reader:read_request_cookie(name)
  end

  if header_scope == "response" then
    return reader:read_response_header(name)
  end

  return reader:read_request_header(name)
end

function _M.read_expected_raw(conf, reader)
  conf = conf or {}
  local strategy = conf.expected_source_strategy or STRATEGY_HEADER

  if strategy == STRATEGY_QUERY then
    return read_raw(reader, strategy, conf.expected_query_param_name)
  end

  if strategy == STRATEGY_JWT_CLAIM then
    return read_raw(reader, strategy, conf.expected_jwt_claim_name)
  end

  if strategy == STRATEGY_COOKIE then
    return read_raw(reader, strategy, conf.expected_cookie_name)
  end

  return read_raw(reader, STRATEGY_HEADER, conf.expected_header_name, "request")
end

function _M.read_actual_raw(conf, reader)
  conf = conf or {}
  local strategy = conf.actual_source_strategy or STRATEGY_HEADER

  if strategy == STRATEGY_QUERY then
    return read_raw(reader, strategy, conf.actual_query_param_name)
  end

  if strategy == STRATEGY_JWT_CLAIM then
    return read_raw(reader, strategy, conf.actual_jwt_claim_name)
  end

  if strategy == STRATEGY_COOKIE then
    return read_raw(reader, strategy, conf.actual_cookie_name)
  end

  return read_raw(reader, STRATEGY_HEADER, conf.actual_header_name, "response")
end

function _M.read_expected(conf, reader)
  local raw = _M.read_expected_raw(conf, reader)
  local version, err = version_parser.parse(raw, constants.REASON_PARSE_ERROR_EXPECTED)

  return version, err, raw
end

function _M.read_actual(conf, reader)
  local raw = _M.read_actual_raw(conf, reader)
  local version, err = version_parser.parse(raw, constants.REASON_PARSE_ERROR_ACTUAL)

  return version, err, raw
end

return _M
