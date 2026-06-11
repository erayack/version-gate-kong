local VersionGateHandler = {
  PRIORITY = 850,
  VERSION = "0.1.0",
}

local constants = require("kong.plugins.version-gate.constants")
local request_coordinator = require("kong.plugins.version-gate.request_coordinator")

local function is_enabled(conf)
  return conf == nil or conf.enabled ~= false
end

local function now_ms()
  return math.floor(ngx.now() * 1000)
end

local function get_route_id()
  local route = kong.router.get_route()
  if route ~= nil then
    return route.id
  end

  return nil
end

local function get_service_id()
  local service = nil

  if kong.client ~= nil and kong.client.get_service ~= nil then
    service = kong.client.get_service()
  elseif kong.router ~= nil and kong.router.get_service ~= nil then
    service = kong.router.get_service()
  end

  if service ~= nil then
    return service.id
  end

  return nil
end

local function get_request_id()
  if kong.request ~= nil and kong.request.get_id ~= nil then
    return kong.request.get_id()
  end

  return nil
end

local function get_state_subject_key(conf, route_id, service_id)
  conf = conf or {}
  local request = kong.request
  local state_subject_header_name = conf.state_subject_header_name

  if
    type(state_subject_header_name) == "string"
    and state_subject_header_name ~= ""
    and request ~= nil
    and request.get_header ~= nil
  then
    local subject_header = request.get_header(state_subject_header_name)
    if type(subject_header) == "string" and subject_header ~= "" then
      return "subject:" .. subject_header
    end
  end

  local method = "-"
  local path = "-"

  if request ~= nil and request.get_method ~= nil then
    method = request.get_method() or method
  end

  if request ~= nil and request.get_path ~= nil then
    path = request.get_path() or path
  end

  local route_fragment = route_id or "-"
  local service_fragment = service_id or "-"
  return table.concat({
    "route:" .. route_fragment,
    "service:" .. service_fragment,
    "method:" .. method,
    "path:" .. path,
  }, "|")
end

local function apply_enforcement_result(result)
  if type(result) ~= "table" then
    return nil
  end

  local response = kong.response
  if type(result.headers) == "table" and response ~= nil and response.set_header ~= nil then
    for k, v in pairs(result.headers) do
      response.set_header(k, v)
    end
  end

  if result.action == constants.ACTION_REJECT and response ~= nil and response.exit ~= nil then
    return response.exit(result.status or 409, result.body, result.headers)
  end

  return nil
end

local function get_plugin_ctx()
  local plugin_ctx = kong.ctx.plugin or {}
  kong.ctx.plugin = plugin_ctx
  return plugin_ctx
end

local function build_access_runtime(conf, started_at)
  local route_id = get_route_id()
  local service_id = get_service_id()
  return {
    now_ms = started_at,
    request_id = get_request_id(),
    route_id = route_id,
    service_id = service_id,
    state_subject_key = get_state_subject_key(conf, route_id, service_id),
    request_ctx = {
      request = kong.request,
      kong_ctx = kong.ctx,
      ngx_ctx = ngx and ngx.ctx or nil,
    },
  }
end

local function build_response_runtime(conf, plugin_ctx)
  return {
    now_ms = now_ms(),
    state_subject_key = get_state_subject_key(conf, plugin_ctx.route_id, plugin_ctx.service_id),
    response_ctx = {
      request = kong.request,
      response = kong.response,
      kong_ctx = kong.ctx,
      ngx_ctx = ngx and ngx.ctx or nil,
    },
    warn = function(...) kong.log.warn(...) end,
  }
end

local function build_log_runtime()
  return {
    now_ms = now_ms(),
    warn = function(...) kong.log.warn(...) end,
    notice = function(...) kong.log.notice(...) end,
  }
end

function VersionGateHandler:access(conf)
  if not is_enabled(conf) then
    return
  end

  local plugin_ctx = get_plugin_ctx()
  request_coordinator.access(conf, plugin_ctx, build_access_runtime(conf, now_ms()))
end

function VersionGateHandler:header_filter(conf)
  if not is_enabled(conf) then
    return
  end

  local plugin_ctx = get_plugin_ctx()
  local enforcement_result = request_coordinator.header_filter(conf, plugin_ctx, build_response_runtime(conf, plugin_ctx))
  return apply_enforcement_result(enforcement_result)
end

function VersionGateHandler:log(conf)
  if not is_enabled(conf) then
    return
  end

  local plugin_ctx = get_plugin_ctx()
  request_coordinator.log(conf, plugin_ctx, build_log_runtime())
end

return VersionGateHandler
