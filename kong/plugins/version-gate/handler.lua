local VersionGateHandler = {
  PRIORITY = 850,
  VERSION = "0.1.0",
}

local constants = require("kong.plugins.version-gate.constants")
local ctx = require("kong.plugins.version-gate.ctx")
local decision_engine = require("kong.plugins.version-gate.decision_engine")
local enforcement = require("kong.plugins.version-gate.enforcement")
local observability = require("kong.plugins.version-gate.observability")
local policy = require("kong.plugins.version-gate.policy")
local version_extractor = require("kong.plugins.version-gate.version_extractor")

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
  local service = kong.router.get_service()
  if service ~= nil then
    return service.id
  end

  return nil
end

local function emit_violation_warning(decision_ctx)
  if decision_ctx.decision ~= constants.DECISION_VIOLATION then
    return
  end

  kong.log.warn(
    "[version-gate] violation detected",
    " reason=", tostring(decision_ctx.reason),
    " request_id=", tostring(decision_ctx.request_id),
    " route_id=", tostring(decision_ctx.route_id),
    " service_id=", tostring(decision_ctx.service_id),
    " expected_version=", tostring(decision_ctx.expected_version),
    " actual_version=", tostring(decision_ctx.actual_version),
    " started_at=", tostring(decision_ctx.started_at),
    " latency_ms=", tostring(decision_ctx.latency_ms)
  )
end

local function should_warn_violation(decision_ctx, policy)
  if decision_ctx.decision ~= constants.DECISION_VIOLATION then
    return false
  end

  local reason = decision_ctx.reason
  if reason == nil then
    return true
  end

  local enforce_on_reason = policy and policy.enforce_on_reason
  if type(enforce_on_reason) ~= "table" then
    return reason == constants.REASON_INVARIANT_VIOLATION
  end

  for i = 1, #enforce_on_reason do
    if enforce_on_reason[i] == reason then
      return true
    end
  end

  return false
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

function VersionGateHandler:access(conf)
  if not is_enabled(conf) then
    return
  end

  local plugin_ctx = kong.ctx.plugin or {}
  kong.ctx.plugin = plugin_ctx
  local started_at = now_ms()
  local route_id = get_route_id()
  local service_id = get_service_id()
  local resolved_policy = policy.resolve_policy(conf, route_id, service_id)
  plugin_ctx.policy = resolved_policy

  ctx.init_request_state(plugin_ctx, {
    policy_id = resolved_policy.id,
    mode = resolved_policy.mode,
    phase = "access",
    request_id = kong.request.get_id(),
    route_id = route_id,
    service_id = service_id,
    started_at = started_at,
  })

  local expected_header = kong.request.get_header(conf.expected_header_name)
  local expected_version, expected_parse_reason = version_extractor.get_expected_version(expected_header)
  ctx.set_expected(plugin_ctx, expected_header, expected_version, expected_parse_reason)
end

function VersionGateHandler:header_filter(conf)
  if not is_enabled(conf) then
    return
  end

  local plugin_ctx = kong.ctx.plugin or {}
  plugin_ctx.phase = "header_filter"
  local expected_version = plugin_ctx.expected_version
  local expected_parse_reason = plugin_ctx.expected_parse_reason

  local actual_header = kong.response.get_header(conf.actual_header_name)
  local actual_version, actual_parse_reason = version_extractor.get_actual_version(actual_header)
  ctx.set_actual(plugin_ctx, actual_header, actual_version, actual_parse_reason)

  local decision, reason = decision_engine.classify(
    expected_version,
    actual_version,
    expected_parse_reason,
    actual_parse_reason,
    plugin_ctx.policy
  )
  ctx.set_decision(plugin_ctx, decision, reason)

  local decision_ctx = ctx.snapshot(plugin_ctx)
  local enforcement_result = enforcement.handle(conf, decision_ctx, plugin_ctx.policy)
  if should_warn_violation(decision_ctx, plugin_ctx.policy) then
    emit_violation_warning(decision_ctx)
  end
  return apply_enforcement_result(enforcement_result)
end

function VersionGateHandler:log(conf)
  if not is_enabled(conf) then
    return
  end

  local plugin_ctx = kong.ctx.plugin or {}
  plugin_ctx.phase = "log"

  if plugin_ctx.started_at ~= nil then
    ctx.set_latency(plugin_ctx, now_ms() - plugin_ctx.started_at)
  end

  local emit_conf = {}
  for k, v in pairs(conf or {}) do
    emit_conf[k] = v
  end

  if plugin_ctx.policy ~= nil and type(plugin_ctx.policy.emit_sample_rate) == "number" then
    emit_conf.emit_sample_rate = plugin_ctx.policy.emit_sample_rate
  end

  observability.emit(emit_conf, ctx.snapshot(plugin_ctx), {
    warn = function(...) kong.log.warn(...) end,
    notice = function(...) kong.log.notice(...) end,
  })
end

return VersionGateHandler
