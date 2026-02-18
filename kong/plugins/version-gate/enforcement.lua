local constants = require("kong.plugins.version-gate.constants")

local _M = {}

--[[
Enforcement interface for decision outcomes.

Current PoC behavior is intentionally log-only. It does not mutate request/response
or terminate traffic.

Future-safe mode shape (not implemented yet):
  mode = "log" | "reject" | "retry" | "reroute"
]]

---Handles enforcement for a version-gate decision.
---@param conf table|nil
---@param decision_ctx table|nil
---@param emit_warning function|nil
---@return nil
function _M.handle(conf, decision_ctx, emit_warning)
  conf = conf or {}
  decision_ctx = decision_ctx or {}

  if decision_ctx.decision == constants.DECISION_VIOLATION and conf.log_only == true and emit_warning ~= nil then
    emit_warning("[version-gate] violation detected", decision_ctx)
  end

  return nil
end

return _M
