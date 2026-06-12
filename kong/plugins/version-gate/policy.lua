local constants = require("kong.plugins.version-gate.constants")

local _M = {}

local DEFAULT_ENFORCE_ON_REASON = { constants.REASON_INVARIANT_VIOLATION }
local DEFAULT_POLICY_CACHE = setmetatable({}, { __mode = "k" })
local NIL_CONF_CACHE_KEY = {}

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

local function same_array(left, right)
  if left == right then
    return true
  end

  if not is_array(left) or not is_array(right) then
    return false
  end

  if #left ~= #right then
    return false
  end

  for i = 1, #left do
    if left[i] ~= right[i] then
      return false
    end
  end

  return true
end

local function config_matches_cached_entry(conf, cached)
  return cached.policy_id == conf.policy_id
    and cached.mode == conf.mode
    and cached.log_only == conf.log_only
    and cached.emit_sample_rate == conf.emit_sample_rate
    and cached.emit_include_versions == conf.emit_include_versions
    and cached.emit_format == conf.emit_format
    and cached.reject_status_code == conf.reject_status_code
    and cached.reject_body_template == conf.reject_body_template
    and same_array(cached.enforce_on_reason, conf.enforce_on_reason)
end

local function cache_entry(conf, resolved_policy)
  local enforce_on_reason = conf.enforce_on_reason
  if is_array(enforce_on_reason) then
    enforce_on_reason = copy_array(enforce_on_reason)
  end

  return {
    policy_id = conf.policy_id,
    mode = conf.mode,
    log_only = conf.log_only,
    emit_sample_rate = conf.emit_sample_rate,
    emit_include_versions = conf.emit_include_versions,
    emit_format = conf.emit_format,
    reject_status_code = conf.reject_status_code,
    reject_body_template = conf.reject_body_template,
    enforce_on_reason = enforce_on_reason,
    policy = resolved_policy,
  }
end

local function resolve_reject_status(value)
  if type(value) == "number" then
    return value
  end
  return 409
end

local function resolve_reject_template(value)
  if value == "minimal" then
    return "minimal"
  end
  return "default"
end

local function resolve_emit_include_versions(value)
  if value == nil then
    return true
  end
  return value == true
end

local function resolve_emit_format(value)
  if value == "json" then
    return "json"
  end
  return "logfmt"
end

local function default_policy(conf)
  conf = conf or {}

  local enforce_on_reason = conf.enforce_on_reason
  if not is_array(enforce_on_reason) then
    enforce_on_reason = DEFAULT_ENFORCE_ON_REASON
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
    emit_include_versions = resolve_emit_include_versions(conf.emit_include_versions),
    emit_format = resolve_emit_format(conf.emit_format),
    enforce_on_reason = enforce_on_reason,
    reject_status_code = resolve_reject_status(conf.reject_status_code),
    reject_body_template = resolve_reject_template(conf.reject_body_template),
  }
end

local function copy_policy(policy)
  local copied = {}
  for k, v in pairs(policy) do
    if k == "enforce_on_reason" and is_array(v) then
      copied[k] = copy_array(v)
    else
      copied[k] = v
    end
  end
  return copied
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

  if type(merged.reject_status_code) ~= "number" then
    merged.reject_status_code = base.reject_status_code
  end

  merged.reject_body_template = resolve_reject_template(merged.reject_body_template)
  merged.emit_include_versions = resolve_emit_include_versions(merged.emit_include_versions)
  merged.emit_format = resolve_emit_format(merged.emit_format)

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
  local original_conf = conf
  conf = conf or {}
  local policy_overrides = conf.policy_overrides
  if policy_overrides == nil then
    local cache_key = original_conf or NIL_CONF_CACHE_KEY
    local cached = DEFAULT_POLICY_CACHE[cache_key]
    if cached ~= nil and config_matches_cached_entry(conf, cached) then
      return copy_policy(cached.policy)
    end

    local resolved_default = default_policy(conf)
    DEFAULT_POLICY_CACHE[cache_key] = cache_entry(conf, resolved_default)
    return copy_policy(resolved_default)
  end

  local resolved = default_policy(conf)

  if service_id ~= nil then
    resolved = merge_policy(resolved, find_override(policy_overrides, "service", service_id))
  end

  if route_id ~= nil then
    resolved = merge_policy(resolved, find_override(policy_overrides, "route", route_id))
  end

  return resolved
end

return _M
