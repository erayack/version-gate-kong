local _M = {}

local DEFAULT_DICT_NAME = "version_gate_state"
local DEFAULT_TTL_SEC = 30

local function normalize_subject_key(subject_key)
  if type(subject_key) ~= "string" or subject_key == "" then
    return nil
  end

  return subject_key
end

local function resolve_dict(conf)
  conf = conf or {}
  if ngx == nil or ngx.shared == nil then
    return nil
  end

  local dict_name = conf.state_store_dict_name
  if type(dict_name) ~= "string" or dict_name == "" then
    dict_name = DEFAULT_DICT_NAME
  end

  return ngx.shared[dict_name]
end

local function resolve_ttl(conf)
  local ttl_sec = tonumber(conf and conf.state_store_ttl_sec)
  if ttl_sec == nil or ttl_sec <= 0 then
    ttl_sec = DEFAULT_TTL_SEC
  end

  return ttl_sec
end

local function resolve_adapter(conf)
  conf = conf or {}

  if type(conf.state_store_adapter) == "table" then
    return conf.state_store_adapter
  end

  local adapter_module = conf.state_store_adapter_module
  if type(adapter_module) ~= "string" or adapter_module == "" then
    return nil
  end

  local ok, adapter = pcall(require, adapter_module)
  if not ok or type(adapter) ~= "table" then
    return nil
  end

  return adapter
end

local function adapter_get(adapter, subject_key, conf)
  if type(adapter) ~= "table" or type(adapter.get_last_seen) ~= "function" then
    return nil, nil
  end

  local function normalize(version, ts_ms)
    if version ~= nil and type(version) ~= "string" then
      version = tostring(version)
    end

    if ts_ms ~= nil then
      ts_ms = tonumber(ts_ms)
    end

    return version, ts_ms
  end

  local ok_with_self, version_with_self, ts_with_self = pcall(adapter.get_last_seen, adapter, subject_key, conf)
  if ok_with_self then
    version_with_self, ts_with_self = normalize(version_with_self, ts_with_self)
  else
    version_with_self, ts_with_self = nil, nil
  end

  local ok_without_self, version_without_self, ts_without_self = pcall(adapter.get_last_seen, subject_key, conf)
  if ok_without_self then
    version_without_self, ts_without_self = normalize(version_without_self, ts_without_self)
  else
    version_without_self, ts_without_self = nil, nil
  end

  if version_with_self ~= nil then
    return version_with_self, ts_with_self
  end

  if version_without_self ~= nil then
    return version_without_self, ts_without_self
  end

  if ts_with_self ~= nil then
    return version_with_self, ts_with_self
  end

  if ts_without_self ~= nil then
    return version_without_self, ts_without_self
  end

  return nil, nil
end

local function adapter_set(adapter, subject_key, version, ts_ms, conf)
  if type(adapter) ~= "table" or type(adapter.set_last_seen) ~= "function" then
    return false
  end

  local ok, did_set = pcall(adapter.set_last_seen, subject_key, version, ts_ms, conf)
  if ok then
    return did_set == true
  end

  ok, did_set = pcall(adapter.set_last_seen, adapter, subject_key, version, ts_ms, conf)
  if not ok then
    return false
  end

  return did_set == true
end

local function dict_key(subject_key, suffix)
  return "version-gate:" .. subject_key .. ":" .. suffix
end

local function dict_get(dict, subject_key)
  if dict == nil then
    return nil, nil
  end

  local version = dict:get(dict_key(subject_key, "version"))
  local ts_ms = dict:get(dict_key(subject_key, "ts_ms"))

  if version ~= nil and type(version) ~= "string" then
    version = tostring(version)
  end

  if ts_ms ~= nil then
    ts_ms = tonumber(ts_ms)
  end

  return version, ts_ms
end

local function dict_set(dict, subject_key, version, ts_ms, ttl_sec)
  if dict == nil then
    return false
  end

  local ok_version = dict:set(dict_key(subject_key, "version"), version, ttl_sec)
  local ok_ts = dict:set(dict_key(subject_key, "ts_ms"), ts_ms, ttl_sec)
  return ok_version and ok_ts
end

---Fetches the last-seen version and timestamp for a subject key.
---@param subject_key string
---@param conf table|nil
---@return string|nil, number|nil
function _M.get_last_seen(subject_key, conf)
  local normalized_subject_key = normalize_subject_key(subject_key)
  if normalized_subject_key == nil then
    return nil, nil
  end

  local adapter = resolve_adapter(conf)
  local version, ts_ms = adapter_get(adapter, normalized_subject_key, conf)
  if version ~= nil or ts_ms ~= nil then
    return version, ts_ms
  end

  local dict = resolve_dict(conf)
  return dict_get(dict, normalized_subject_key)
end

---Stores the last-seen version and timestamp for a subject key.
---@param subject_key string
---@param version string
---@param ts_ms number|string
---@param conf table|nil
---@return boolean
function _M.set_last_seen(subject_key, version, ts_ms, conf)
  local normalized_subject_key = normalize_subject_key(subject_key)
  if normalized_subject_key == nil then
    return false
  end

  if type(version) ~= "string" or version == "" then
    return false
  end

  local parsed_ts_ms = tonumber(ts_ms)
  if parsed_ts_ms == nil then
    return false
  end

  local adapter = resolve_adapter(conf)
  if adapter_set(adapter, normalized_subject_key, version, parsed_ts_ms, conf) then
    return true
  end

  local dict = resolve_dict(conf)
  local ttl_sec = resolve_ttl(conf)
  return dict_set(dict, normalized_subject_key, version, parsed_ts_ms, ttl_sec)
end

---Binds store operations to a config table for request lifecycle usage.
---@param conf table|nil
---@return table
function _M.new(conf)
  return {
    get_last_seen = function(_, subject_key)
      return _M.get_last_seen(subject_key, conf)
    end,
    set_last_seen = function(_, subject_key, version, ts_ms)
      return _M.set_last_seen(subject_key, version, ts_ms, conf)
    end,
  }
end

return _M
