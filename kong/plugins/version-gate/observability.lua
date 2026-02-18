local constants = require("kong.plugins.version-gate.constants")

local _M = {}

local EVENT_FIELDS = {
  "event_version",
  "plugin",
  "policy_id",
  "mode",
  "phase",
  "decision",
  "reason",
  "expected_version",
  "actual_version",
  "expected_version_raw",
  "actual_version_raw",
  "request_id",
  "route_id",
  "service_id",
  "started_at",
  "latency_ms",
}

local function escape_logfmt_quoted(value)
  return value
    :gsub("\\", "\\\\")
    :gsub("\"", "\\\"")
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
    :gsub("\t", "\\t")
end

local function escape_json_quoted(value)
  return value
    :gsub("\\", "\\\\")
    :gsub("\"", "\\\"")
    :gsub("\b", "\\b")
    :gsub("\f", "\\f")
    :gsub("\n", "\\n")
    :gsub("\r", "\\r")
    :gsub("\t", "\\t")
end

local function normalize_value(value)
  if value == nil then
    return "null"
  end

  local string_value = tostring(value)

  if string_value == "" then
    return "\"\""
  end

  if string_value:match("[%s=\"]") ~= nil then
    return "\"" .. escape_logfmt_quoted(string_value) .. "\""
  end

  return string_value
end

local function should_emit(conf, random_fn)
  conf = conf or {}
  random_fn = random_fn or math.random

  local sample_rate = conf.emit_sample_rate
  if type(sample_rate) ~= "number" then
    sample_rate = 1
  end

  if sample_rate <= 0 then
    return false
  end

  if sample_rate >= 1 then
    return true
  end

  return random_fn() <= sample_rate
end

local function include_versions(conf)
  if conf == nil or conf.emit_include_versions == nil then
    return true
  end

  return conf.emit_include_versions == true
end

local function resolve_emit_format(conf)
  if conf ~= nil and conf.emit_format == "json" then
    return "json"
  end

  return "logfmt"
end

---Serializes an event table into logfmt-style key=value pairs.
---@param event table
---@return string
local function serialize_event(event)
  local parts = {}
  for i = 1, #EVENT_FIELDS do
    local field = EVENT_FIELDS[i]
    parts[#parts + 1] = field .. "=" .. normalize_value(event[field])
  end

  return table.concat(parts, " ")
end

---Serializes an event table to JSON with normalized fields.
---@param event table
---@return string|nil
local function serialize_event_json(event)
  local parts = {}
  for i = 1, #EVENT_FIELDS do
    local field = EVENT_FIELDS[i]
    local value = event[field]
    local encoded_value

    if value == nil then
      encoded_value = "null"
    elseif type(value) == "number" then
      encoded_value = tostring(value)
    elseif type(value) == "boolean" then
      encoded_value = value and "true" or "false"
    else
      encoded_value = "\"" .. escape_json_quoted(tostring(value)) .. "\""
    end

    parts[#parts + 1] = "\"" .. field .. "\":" .. encoded_value
  end

  return "{" .. table.concat(parts, ",") .. "}"
end

---Builds a standardized observability event payload.
---@param decision_ctx table|nil
---@param conf table|nil
---@return table
function _M.build_event(decision_ctx, conf)
  decision_ctx = decision_ctx or {}
  conf = conf or {}
  local should_include_versions = include_versions(conf)

  return {
    event_version = "1",
    plugin = "version-gate",
    policy_id = decision_ctx.policy_id or conf.policy_id,
    mode = decision_ctx.mode or conf.mode,
    phase = decision_ctx.phase,
    decision = decision_ctx.decision,
    reason = decision_ctx.reason,
    expected_version = should_include_versions and decision_ctx.expected_version or nil,
    actual_version = should_include_versions and decision_ctx.actual_version or nil,
    expected_version_raw = should_include_versions and decision_ctx.expected_version_raw or nil,
    actual_version_raw = should_include_versions and decision_ctx.actual_version_raw or nil,
    request_id = decision_ctx.request_id,
    route_id = decision_ctx.route_id,
    service_id = decision_ctx.service_id,
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
  conf = conf or {}

  if not should_emit(conf, emitters.random) then
    return nil
  end

  local event = _M.build_event(decision_ctx, conf)
  local emit_warn = emitters.warn
  local emit_notice = emitters.notice

  local serialized_payload
  if resolve_emit_format(conf) == "json" then
    serialized_payload = serialize_event_json(event)
  end

  if serialized_payload == nil then
    serialized_payload = serialize_event(event)
  end

  local serialized = " " .. serialized_payload

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
