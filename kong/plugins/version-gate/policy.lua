local constants = require("kong.plugins.version-gate.constants")

local _M = {}

local function resolve_mode(conf)
  conf = conf or {}

  if conf.mode ~= nil then
    return conf.mode
  end

  if conf.log_only == true then
    return "shadow"
  end

  return "shadow"
end

local function is_array(value)
  if type(value) ~= "table" then
    return false
  end

  local count = 0
  for k, _ in pairs(value) do
    if type(k) ~= "number" then
      return false
    end
    count = count + 1
  end

  return count == #value
end

local function copy_array(values)
  local out = {}
  for i = 1, #values do
    out[i] = values[i]
  end
  return out
end

local function default_policy(conf)
  conf = conf or {}

  local enforce_on_reason = conf.enforce_on_reason
  if not is_array(enforce_on_reason) then
    enforce_on_reason = { constants.REASON_INVARIANT_VIOLATION }
  else
    enforce_on_reason = copy_array(enforce_on_reason)
  end

  local emit_sample_rate = conf.emit_sample_rate
  if type(emit_sample_rate) ~= "number" then
    emit_sample_rate = 1.0
  end

  local policy_id = conf.policy_id
  if type(policy_id) ~= "string" or policy_id == "" then
    policy_id = "default"
  end

  return {
    id = policy_id,
    mode = resolve_mode(conf),
    emit_sample_rate = emit_sample_rate,
    enforce_on_reason = enforce_on_reason,
  }
end

local function merge_policy(base, override)
  if type(override) ~= "table" then
    return base
  end

  local merged = {}
  for k, v in pairs(base) do
    merged[k] = v
  end

  for k, v in pairs(override) do
    if k == "enforce_on_reason" and is_array(v) then
      merged[k] = copy_array(v)
    else
      merged[k] = v
    end
  end

  if type(merged.id) ~= "string" or merged.id == "" then
    merged.id = base.id
  end

  if type(merged.mode) ~= "string" or merged.mode == "" then
    merged.mode = base.mode
  end

  if type(merged.emit_sample_rate) ~= "number" then
    merged.emit_sample_rate = base.emit_sample_rate
  end

  if not is_array(merged.enforce_on_reason) then
    merged.enforce_on_reason = copy_array(base.enforce_on_reason)
  end

  return merged
end

local function find_override(policy_overrides, target_type, target_id)
  if type(policy_overrides) ~= "table" then
    return nil
  end

  if type(target_type) ~= "string" or type(target_id) ~= "string" then
    return nil
  end

  local merged = nil

  for i = 1, #policy_overrides do
    local candidate = policy_overrides[i]
    if
      type(candidate) == "table"
      and candidate.target_type == target_type
      and candidate.target_id == target_id
    then
      if merged == nil then
        merged = {}
      end

      for k, v in pairs(candidate) do
        if k ~= "target_type" and k ~= "target_id" then
          if k == "enforce_on_reason" and is_array(v) then
            merged[k] = copy_array(v)
          else
            merged[k] = v
          end
        end
      end
    end
  end

  return merged
end

---Resolves an effective policy for the current request scope.
---@param conf table|nil
---@param route_id string|nil
---@param service_id string|nil
---@return table
function _M.resolve_policy(conf, route_id, service_id)
  local resolved = default_policy(conf)
  conf = conf or {}
  local policy_overrides = conf.policy_overrides

  if service_id ~= nil then
    resolved = merge_policy(resolved, find_override(policy_overrides, "service", service_id))
  end

  if route_id ~= nil then
    resolved = merge_policy(resolved, find_override(policy_overrides, "route", route_id))
  end

  return resolved
end

return _M
