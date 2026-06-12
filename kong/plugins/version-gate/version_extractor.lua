local kong_source_reader = require("kong.plugins.version-gate.source_readers.kong")
local version_intake = require("kong.plugins.version-gate.version_intake")
local version_parser = require("kong.plugins.version-gate.version_parser")

local _M = {}

local function default_reader(ctx)
  return kong_source_reader.new(ctx)
end

local function direct_request_header(ctx, name)
  if type(ctx) ~= "table" or type(name) ~= "string" or name == "" then
    return nil
  end

  local request = ctx.request
  if type(request) == "table" and type(request.get_header) == "function" then
    return request.get_header(name)
  end

  return nil
end

local function direct_response_header(ctx, name)
  if type(ctx) ~= "table" or type(name) ~= "string" or name == "" then
    return nil
  end

  local response = ctx.response
  if type(response) == "table" and type(response.get_header) == "function" then
    return response.get_header(name)
  end

  return nil
end

function _M.get_expected_raw(conf, request_ctx)
  conf = conf or {}
  if (conf.expected_source_strategy or "header") == "header" then
    local direct = direct_request_header(request_ctx, conf.expected_header_name)
    if direct ~= nil then
      return direct
    end
  end

  return version_intake.read_expected_raw(conf, default_reader(request_ctx))
end

function _M.get_actual_raw(conf, response_ctx)
  conf = conf or {}
  if (conf.actual_source_strategy or "header") == "header" then
    local direct = direct_response_header(response_ctx, conf.actual_header_name)
    if direct ~= nil then
      return direct
    end
  end

  return version_intake.read_actual_raw(conf, default_reader(response_ctx))
end

function _M.parse_version(raw, parse_error_reason)
  return version_parser.parse(raw, parse_error_reason)
end

function _M.get_expected_version(conf, request_ctx)
  return version_intake.read_expected(conf or {}, default_reader(request_ctx))
end

function _M.get_actual_version(conf, response_ctx)
  return version_intake.read_actual(conf or {}, default_reader(response_ctx))
end

return _M
