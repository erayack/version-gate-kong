local constants = require("kong.plugins.version-gate.constants")
local decision_engine = require("kong.plugins.version-gate.decision_engine")
local enforcement = require("kong.plugins.version-gate.enforcement")
local observability = require("kong.plugins.version-gate.observability")
local policy = require("kong.plugins.version-gate.policy")
local state_store = require("kong.plugins.version-gate.state_store")
local state_suppression = require("kong.plugins.version-gate.state_suppression")
local version_extractor = require("kong.plugins.version-gate.version_extractor")

local _M = {}

local function state_suppression_enabled(conf)
  local window_ms = tonumber(conf and conf.state_suppression_window_ms)
  return window_ms ~= nil and window_ms > 0
end

local function should_warn_violation(decision_ctx, resolved_policy)
  if decision_ctx.decision ~= constants.DECISION_VIOLATION then
    return false
  end

  local reason = decision_ctx.reason
  if reason == nil then
    return true
  end

  local enforce_on_reason = resolved_policy and resolved_policy.enforce_on_reason
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

local function emit_violation_warning(decision_ctx, runtime)
  if decision_ctx.decision ~= constants.DECISION_VIOLATION then
    return
  end

  runtime.warn(
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

function _M.access(conf, plugin_ctx, runtime)
  runtime = runtime or {}
  local resolved_policy = policy.resolve_policy(conf, runtime.route_id, runtime.service_id)
  plugin_ctx.policy = resolved_policy
  local suppression_enabled = state_suppression_enabled(conf)
  if suppression_enabled then
    plugin_ctx.state_store = state_store.new(conf)
    plugin_ctx.state_subject_key = runtime.state_subject_key
  else
    plugin_ctx.state_store = nil
    plugin_ctx.state_subject_key = nil
  end

  plugin_ctx.expected_version = nil
  plugin_ctx.actual_version = nil
  plugin_ctx.expected_version_raw = nil
  plugin_ctx.actual_version_raw = nil
  plugin_ctx.expected_parse_reason = nil
  plugin_ctx.decision = constants.DECISION_ALLOW
  plugin_ctx.reason = constants.REASON_INVARIANT_OK
  plugin_ctx.policy_id = resolved_policy.id
  plugin_ctx.mode = resolved_policy.mode
  plugin_ctx.phase = "access"
  plugin_ctx.request_id = runtime.request_id
  plugin_ctx.route_id = runtime.route_id
  plugin_ctx.service_id = runtime.service_id
  plugin_ctx.started_at = runtime.now_ms
  plugin_ctx.latency_ms = nil

  local expected_raw = version_extractor.get_expected_raw(conf, runtime.request_ctx)
  local expected_version, expected_parse_reason =
    version_extractor.parse_version(expected_raw, constants.REASON_PARSE_ERROR_EXPECTED)
  plugin_ctx.expected_version_raw = expected_raw
  plugin_ctx.expected_version = expected_version
  plugin_ctx.expected_parse_reason = expected_parse_reason
end

function _M.header_filter(conf, plugin_ctx, runtime)
  runtime = runtime or {}
  plugin_ctx.phase = "header_filter"
  local expected_version = plugin_ctx.expected_version
  local expected_parse_reason = plugin_ctx.expected_parse_reason
  local suppression_enabled = state_suppression_enabled(conf)
  if suppression_enabled then
    if plugin_ctx.state_store == nil then
      plugin_ctx.state_store = state_store.new(conf)
    end
    if plugin_ctx.state_subject_key == nil then
      plugin_ctx.state_subject_key = runtime.state_subject_key
    end
  end

  local actual_raw = version_extractor.get_actual_raw(conf, runtime.response_ctx)
  local actual_version, actual_parse_reason =
    version_extractor.parse_version(actual_raw, constants.REASON_PARSE_ERROR_ACTUAL)
  plugin_ctx.actual_version_raw = actual_raw
  plugin_ctx.actual_version = actual_version

  local decision, reason = decision_engine.classify(
    expected_version,
    actual_version,
    expected_parse_reason,
    actual_parse_reason,
    plugin_ctx.policy
  )
  if suppression_enabled then
    local suppression_result = state_suppression.apply({
      conf = conf,
      store = plugin_ctx.state_store,
      subject_key = plugin_ctx.state_subject_key,
      decision = decision,
      reason = reason,
      expected_version = expected_version,
      actual_version = actual_version,
      now_ts_ms = runtime.now_ms,
    })
    decision = suppression_result.decision
    reason = suppression_result.reason
    plugin_ctx.last_seen_version = suppression_result.last_seen_version
    plugin_ctx.last_seen_ts_ms = suppression_result.last_seen_ts_ms
    plugin_ctx.state_suppressed = suppression_result.state_suppressed
    plugin_ctx.state_store_write_ok = suppression_result.state_store_write_ok
  end
  plugin_ctx.decision = decision
  plugin_ctx.reason = reason

  if decision == constants.DECISION_VIOLATION then
    local enforcement_result = enforcement.handle(plugin_ctx, plugin_ctx.policy)
    if should_warn_violation(plugin_ctx, plugin_ctx.policy) then
      emit_violation_warning(plugin_ctx, runtime)
    end
    return enforcement_result
  end

  return nil
end

function _M.log(conf, plugin_ctx, runtime)
  runtime = runtime or {}
  plugin_ctx.phase = "log"

  if plugin_ctx.started_at ~= nil then
    plugin_ctx.latency_ms = runtime.now_ms - plugin_ctx.started_at
  end

  observability.emit(plugin_ctx.policy or policy.resolve_policy(conf), plugin_ctx, runtime)
end

return _M
