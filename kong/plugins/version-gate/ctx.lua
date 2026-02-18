local constants = require("kong.plugins.version-gate.constants")

local ctx = {}

local function ensure_plugin_ctx(plugin_ctx)
  return plugin_ctx or {}
end

---@class DecisionContext
---@field expected_version number|nil
---@field actual_version number|nil
---@field decision string
---@field reason string
---@field request_id string|nil
---@field route_id string|nil
---@field service_id string|nil
---@field started_at number
---@field latency_ms number|nil

---Initializes request-scoped decision state.
---@param plugin_ctx table|nil
---@param meta table|nil
function ctx.init_request_state(plugin_ctx, meta)
  plugin_ctx = ensure_plugin_ctx(plugin_ctx)
  meta = meta or {}

  plugin_ctx.expected_version = nil
  plugin_ctx.actual_version = nil
  plugin_ctx.decision = constants.DECISION_ALLOW
  plugin_ctx.reason = constants.REASON_INVARIANT_OK
  plugin_ctx.request_id = meta.request_id
  plugin_ctx.route_id = meta.route_id
  plugin_ctx.service_id = meta.service_id
  plugin_ctx.started_at = meta.started_at
  plugin_ctx.latency_ms = nil
end

---Sets expected version from parsed value.
---@param plugin_ctx table|nil
---@param parsed number|nil
function ctx.set_expected(plugin_ctx, parsed)
  plugin_ctx = ensure_plugin_ctx(plugin_ctx)
  plugin_ctx.expected_version = parsed
end

---Sets actual version from parsed value.
---@param plugin_ctx table|nil
---@param parsed number|nil
function ctx.set_actual(plugin_ctx, parsed)
  plugin_ctx = ensure_plugin_ctx(plugin_ctx)
  plugin_ctx.actual_version = parsed
end

---Sets decision and reason for the current request.
---@param plugin_ctx table|nil
---@param decision string
---@param reason string
function ctx.set_decision(plugin_ctx, decision, reason)
  plugin_ctx = ensure_plugin_ctx(plugin_ctx)
  plugin_ctx.decision = decision
  plugin_ctx.reason = reason
end

---@param plugin_ctx table|nil
---@param latency_ms number|nil
function ctx.set_latency(plugin_ctx, latency_ms)
  plugin_ctx = ensure_plugin_ctx(plugin_ctx)
  plugin_ctx.latency_ms = latency_ms
end

---Returns a stable snapshot of the decision context.
---@param plugin_ctx table|nil
---@return DecisionContext
function ctx.snapshot(plugin_ctx)
  plugin_ctx = ensure_plugin_ctx(plugin_ctx)

  return {
    expected_version = plugin_ctx.expected_version,
    actual_version = plugin_ctx.actual_version,
    decision = plugin_ctx.decision,
    reason = plugin_ctx.reason,
    request_id = plugin_ctx.request_id,
    route_id = plugin_ctx.route_id,
    service_id = plugin_ctx.service_id,
    started_at = plugin_ctx.started_at,
    latency_ms = plugin_ctx.latency_ms,
  }
end

return ctx
