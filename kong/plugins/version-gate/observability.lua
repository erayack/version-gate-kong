local constants = require("kong.plugins.version-gate.constants")

local _M = {}

---Serializes an event table into logfmt-style key=value pairs.
---@param event table
---@return string
local function serialize_event(event)
  local parts = {}
  for k, v in pairs(event) do
    parts[#parts + 1] = tostring(k) .. "=" .. tostring(v)
  end
  return table.concat(parts, " ")
end

---Builds a standardized observability event payload.
---@param decision_ctx table|nil
---@return table
function _M.build_event(decision_ctx)
  decision_ctx = decision_ctx or {}

  return {
    plugin = "version-gate",
    decision = decision_ctx.decision,
    reason = decision_ctx.reason,
    expected_version = decision_ctx.expected_version,
    actual_version = decision_ctx.actual_version,
    route_id = decision_ctx.route_id,
    service_id = decision_ctx.service_id,
    request_id = decision_ctx.request_id,
    started_at = decision_ctx.started_at,
    latency_ms = decision_ctx.latency_ms,
  }
end

---Emits the observability event at a severity derived from decision.
---@param conf table|nil
---@param decision_ctx table|nil
---@param emitters table|nil
---@return nil
function _M.emit(conf, decision_ctx, emitters)
  emitters = emitters or {}
  local event = _M.build_event(decision_ctx)
  local emit_warn = emitters.warn
  local emit_notice = emitters.notice

  local serialized = " " .. serialize_event(event)

  if event.decision == constants.DECISION_VIOLATION and emit_warn ~= nil then
    emit_warn("[version-gate] decision", serialized)
    return nil
  end

  if emit_notice ~= nil then
    emit_notice("[version-gate] decision", serialized)
  end

  return nil
end

return _M
