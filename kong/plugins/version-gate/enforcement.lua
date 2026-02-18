local constants = require("kong.plugins.version-gate.constants")

local _M = {}

--[[
Enforcement interface for decision outcomes.

Current PoC behavior is intentionally log-only. It does not mutate request/response
or terminate traffic.

Future-safe mode shape (not implemented yet):
  mode = "log" | "reject" | "retry" | "reroute"
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

local function is_tier0_shadow_behavior_mode(mode)
  return mode == "shadow" or mode == "annotate" or mode == "reject"
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
---@param emit_warning function|nil
---@param policy table|nil
---@return nil
function _M.handle(conf, decision_ctx, emit_warning, policy)
  conf = conf or {}
  decision_ctx = decision_ctx or {}
  policy = policy or {}
  local mode = resolve_mode(conf, decision_ctx, policy)

  -- Tier 0 keeps all modes fail-open with shadow-style warning emission.
  if decision_ctx.decision == constants.DECISION_VIOLATION
    and should_enforce_reason(policy, decision_ctx.reason)
    and is_tier0_shadow_behavior_mode(mode)
    and emit_warning ~= nil
  then
    emit_warning("[version-gate] violation detected", decision_ctx)
  end

  return nil
end

return _M
