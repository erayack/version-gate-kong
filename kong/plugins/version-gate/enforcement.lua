local constants = require("kong.plugins.version-gate.constants")

local _M = {}

local REJECT_BODY_TEMPLATES = {
  default = function(decision_ctx)
    return {
      message = "version gate violation",
      decision = decision_ctx.decision,
      reason = decision_ctx.reason,
    }
  end,
  minimal = function(decision_ctx)
    return {
      error = "version gate violation",
      reason = decision_ctx.reason,
    }
  end,
}

--[[
Enforcement interface for decision outcomes.

Current PoC behavior is intentionally log-only. It does not mutate request/response
or terminate traffic.

Returns explicit enforcement instructions for handler execution:
  { action="none"|"annotate"|"reject", status=number|nil, body=table|string|nil, headers=table|nil }
]]

local function resolve_mode(conf, decision_ctx, policy)
  decision_ctx = decision_ctx or {}
  conf = conf or {}
  policy = policy or {}

  if policy.mode ~= nil then
    return policy.mode
  end

  if decision_ctx.mode ~= nil then
    return decision_ctx.mode
  end

  if conf.mode ~= nil then
    return conf.mode
  end

  if conf.log_only == true then
    return "shadow"
  end

  return "shadow"
end

local function should_enforce_mode(mode)
  return mode == "annotate" or mode == "reject"
end

local function resolve_reject_status(conf, policy)
  local status = policy and policy.reject_status_code
  if type(status) ~= "number" then
    status = conf and conf.reject_status_code
  end
  if type(status) ~= "number" then
    status = 409
  end
  return status
end

local function build_annotation_headers(decision_ctx, mode)
  return {
    [constants.HEADER_DECISION] = tostring(decision_ctx.decision),
    [constants.HEADER_REASON] = tostring(decision_ctx.reason),
    [constants.HEADER_MODE] = tostring(mode),
  }
end

local function resolve_reject_template(conf, policy)
  local template = policy and policy.reject_body_template
  if type(template) ~= "string" then
    template = conf and conf.reject_body_template
  end

  if type(template) ~= "string" then
    return "default"
  end

  if REJECT_BODY_TEMPLATES[template] == nil then
    return "default"
  end

  return template
end

local function build_reject_body(conf, policy, decision_ctx)
  local template = resolve_reject_template(conf, policy)
  return REJECT_BODY_TEMPLATES[template](decision_ctx)
end

local function should_enforce_reason(policy, reason)
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

---Handles enforcement for a version-gate decision.
---@param conf table|nil
---@param decision_ctx table|nil
---@param policy table|nil
---@return table
function _M.handle(conf, decision_ctx, policy)
  conf = conf or {}
  decision_ctx = decision_ctx or {}
  policy = policy or {}
  local mode = resolve_mode(conf, decision_ctx, policy)

  local result = {
    action = constants.ACTION_NONE,
    status = nil,
    body = nil,
    headers = nil,
  }

  if decision_ctx.decision ~= constants.DECISION_VIOLATION then
    return result
  end

  if not should_enforce_reason(policy, decision_ctx.reason) then
    return result
  end

  if not should_enforce_mode(mode) then
    return result
  end

  if mode == "annotate" then
    result.action = constants.ACTION_ANNOTATE
    result.headers = build_annotation_headers(decision_ctx, mode)
    return result
  end

  if mode == "reject" then
    result.action = constants.ACTION_REJECT
    result.status = resolve_reject_status(conf, policy)
    result.body = build_reject_body(conf, policy, decision_ctx)
    result.headers = build_annotation_headers(decision_ctx, mode)
    return result
  end

  return result
end

return _M
