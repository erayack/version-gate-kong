local kong_source_reader = require("kong.plugins.version-gate.source_readers.kong")
local version_intake = require("kong.plugins.version-gate.version_intake")
local version_parser = require("kong.plugins.version-gate.version_parser")

local _M = {}

local function default_reader(ctx)
  return kong_source_reader.new(ctx)
end

function _M.get_expected_raw(conf, request_ctx)
  return version_intake.read_expected_raw(conf or {}, default_reader(request_ctx))
end

function _M.get_actual_raw(conf, response_ctx)
  return version_intake.read_actual_raw(conf or {}, default_reader(response_ctx))
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
