local VersionGateHandler = {
  PRIORITY = 850,
  VERSION = "0.1.0",
}

local constants = require("kong.plugins.version-gate.constants")
local ctx = require("kong.plugins.version-gate.ctx")
local decision_engine = require("kong.plugins.version-gate.decision_engine")
local enforcement = require("kong.plugins.version-gate.enforcement")
local invariant = require("kong.plugins.version-gate.invariant")
local observability = require("kong.plugins.version-gate.observability")
local policy = require("kong.plugins.version-gate.policy")
local state_store = require("kong.plugins.version-gate.state_store")
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

local function should_apply_state_suppression(conf)
  local suppression_window_ms = tonumber(conf and conf.state_suppression_window_ms)
  if suppression_window_ms == nil or suppression_window_ms <= 0 then
    return false, nil
  end

  return true, suppression_window_ms
end

local function maybe_suppress_violation(conf, plugin_ctx, decision, reason, expected_version, now_ts_ms)
  if decision ~= constants.DECISION_VIOLATION or reason ~= constants.REASON_INVARIANT_VIOLATION then
    return decision, reason
  end

  local should_suppress, suppression_window_ms = should_apply_state_suppression(conf)
  if not should_suppress then
    return decision, reason
  end

  local store = plugin_ctx.state_store
  local subject_key = plugin_ctx.state_subject_key
  if store == nil or subject_key == nil or expected_version == nil then
    return decision, reason
  end

  local last_seen_version, last_seen_ts_ms = store:get_last_seen(subject_key)
  plugin_ctx.last_seen_version = last_seen_version
  plugin_ctx.last_seen_ts_ms = last_seen_ts_ms

  if type(last_seen_version) ~= "string" or type(last_seen_ts_ms) ~= "number" then
    return decision, reason
  end

  if invariant.is_violation(expected_version, last_seen_version) then
    return decision, reason
  end

  if (now_ts_ms - last_seen_ts_ms) > suppression_window_ms then
    return decision, reason
  end

  plugin_ctx.state_suppressed = true
  return constants.DECISION_ALLOW, constants.REASON_INVARIANT_OK
end

local function persist_last_seen(conf, plugin_ctx, actual_version, now_ts_ms)
  local should_persist, _ = should_apply_state_suppression(conf)
  if not should_persist then
    return
  end

  if type(actual_version) ~= "string" then
    return
  end

  local store = plugin_ctx.state_store
  local subject_key = plugin_ctx.state_subject_key
  if store == nil or subject_key == nil then
    return
  end

  plugin_ctx.state_store_write_ok = store:set_last_seen(subject_key, actual_version, now_ts_ms) == true
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
  plugin_ctx.state_store = state_store.new(conf)
  plugin_ctx.state_subject_key = get_state_subject_key(conf, route_id, service_id)

  ctx.init_request_state(plugin_ctx, {
    policy_id = resolved_policy.id,
    mode = resolved_policy.mode,
    phase = "access",
    request_id = get_request_id(),
    route_id = route_id,
    service_id = service_id,
    started_at = started_at,
  })

  local request_ctx = {
    request = kong.request,
    kong_ctx = kong.ctx,
    ngx_ctx = ngx and ngx.ctx or nil,
  }
  local expected_raw = version_extractor.get_expected_raw(conf, request_ctx)
  local expected_version, expected_parse_reason =
    version_extractor.parse_version(expected_raw, constants.REASON_PARSE_ERROR_EXPECTED)
  ctx.set_expected(plugin_ctx, expected_raw, expected_version, expected_parse_reason)
end

function VersionGateHandler:header_filter(conf)
  if not is_enabled(conf) then
    return
  end

  local plugin_ctx = kong.ctx.plugin or {}
  plugin_ctx.phase = "header_filter"
  local expected_version = plugin_ctx.expected_version
  local expected_parse_reason = plugin_ctx.expected_parse_reason
  if plugin_ctx.state_store == nil then
    plugin_ctx.state_store = state_store.new(conf)
  end
  if plugin_ctx.state_subject_key == nil then
    plugin_ctx.state_subject_key = get_state_subject_key(conf, plugin_ctx.route_id, plugin_ctx.service_id)
  end

  local response_ctx = {
    request = kong.request,
    response = kong.response,
    kong_ctx = kong.ctx,
    ngx_ctx = ngx and ngx.ctx or nil,
  }
  local actual_raw = version_extractor.get_actual_raw(conf, response_ctx)
  local actual_version, actual_parse_reason =
    version_extractor.parse_version(actual_raw, constants.REASON_PARSE_ERROR_ACTUAL)
  ctx.set_actual(plugin_ctx, actual_raw, actual_version, actual_parse_reason)

  local now_ts_ms = now_ms()
  local decision, reason = decision_engine.classify(
    expected_version,
    actual_version,
    expected_parse_reason,
    actual_parse_reason,
    plugin_ctx.policy
  )
  decision, reason = maybe_suppress_violation(
    conf,
    plugin_ctx,
    decision,
    reason,
    expected_version,
    now_ts_ms
  )
  ctx.set_decision(plugin_ctx, decision, reason)
  persist_last_seen(conf, plugin_ctx, actual_version, now_ts_ms)

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
