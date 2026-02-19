local _M = {}

local DEFAULT_TTL_SEC = 30
local DEFAULT_PORT = 6379
local DEFAULT_DATABASE = 0
local DEFAULT_TIMEOUT_MS = 100
local DEFAULT_KEEPALIVE_MS = 60000
local DEFAULT_POOL_SIZE = 100
local DEFAULT_PREFIX = "version-gate:state"

local function as_non_empty_string(value)
  if value == nil then
    return nil
  end

  if type(value) ~= "string" then
    value = tostring(value)
  end

  if value == "" then
    return nil
  end

  return value
end

local function resolve_string(conf, conf_key, env_key, default_value)
  local value = conf and conf[conf_key] or nil
  value = as_non_empty_string(value)

  if value == nil and type(env_key) == "string" then
    value = as_non_empty_string(os.getenv(env_key))
  end

  if value == nil then
    return default_value
  end

  return value
end

local function resolve_string_many(conf, conf_key, env_keys, default_value)
  local value = conf and conf[conf_key] or nil
  value = as_non_empty_string(value)

  if value == nil and type(env_keys) == "table" then
    for i = 1, #env_keys do
      value = as_non_empty_string(os.getenv(env_keys[i]))
      if value ~= nil then
        break
      end
    end
  end

  if value == nil then
    return default_value
  end

  return value
end

local function resolve_integer(conf, conf_key, env_key, default_value)
  local value = conf and conf[conf_key] or nil
  local num = tonumber(value)

  if num == nil and type(env_key) == "string" then
    num = tonumber(os.getenv(env_key))
  end

  if num == nil then
    return default_value
  end

  return math.floor(num)
end

local function resolve_integer_many(conf, conf_key, env_keys, default_value)
  local value = conf and conf[conf_key] or nil
  local num = tonumber(value)

  if num == nil and type(env_keys) == "table" then
    for i = 1, #env_keys do
      num = tonumber(os.getenv(env_keys[i]))
      if num ~= nil then
        break
      end
    end
  end

  if num == nil then
    return default_value
  end

  return math.floor(num)
end

local function resolve_options(conf)
  conf = conf or {}

  local host = resolve_string_many(conf, "state_store_redis_host", {
    "KONG_REDIS_HOST",
    "KONG_SPEC_TEST_REDIS_HOST",
    "KONG_SPEC_REDIS_HOST",
  }, nil)
  local port = resolve_integer_many(conf, "state_store_redis_port", {
    "KONG_REDIS_PORT",
    "KONG_SPEC_TEST_REDIS_PORT",
    "KONG_SPEC_REDIS_PORT",
  }, DEFAULT_PORT)
  local database = resolve_integer(conf, "state_store_redis_database", "KONG_REDIS_DATABASE", DEFAULT_DATABASE)
  local timeout_ms = resolve_integer(conf, "state_store_redis_timeout_ms", "KONG_REDIS_TIMEOUT_MS", DEFAULT_TIMEOUT_MS)
  local keepalive_ms = resolve_integer(
    conf,
    "state_store_redis_keepalive_ms",
    "KONG_REDIS_KEEPALIVE_MS",
    DEFAULT_KEEPALIVE_MS
  )
  local pool_size = resolve_integer(conf, "state_store_redis_pool_size", "KONG_REDIS_POOL_SIZE", DEFAULT_POOL_SIZE)
  local prefix = resolve_string(conf, "state_store_redis_prefix", "KONG_REDIS_PREFIX", DEFAULT_PREFIX)
  local password = resolve_string_many(conf, "state_store_redis_password", {
    "KONG_REDIS_PASSWORD",
    "REDIS_PASSWORD",
  }, nil)
  local ttl_sec = resolve_integer(conf, "state_store_ttl_sec", "KONG_REDIS_TTL_SEC", DEFAULT_TTL_SEC)

  if port <= 0 then
    port = DEFAULT_PORT
  end

  if database < 0 then
    database = DEFAULT_DATABASE
  end

  if timeout_ms <= 0 then
    timeout_ms = DEFAULT_TIMEOUT_MS
  end

  if keepalive_ms <= 0 then
    keepalive_ms = DEFAULT_KEEPALIVE_MS
  end

  if pool_size <= 0 then
    pool_size = DEFAULT_POOL_SIZE
  end

  if ttl_sec <= 0 then
    ttl_sec = DEFAULT_TTL_SEC
  end

  return {
    host = host,
    port = port,
    database = database,
    timeout_ms = timeout_ms,
    keepalive_ms = keepalive_ms,
    pool_size = pool_size,
    prefix = prefix,
    password = password,
    ttl_sec = ttl_sec,
  }
end

local function redis_nil(value)
  if value == nil then
    return nil
  end

  if ngx ~= nil and value == ngx.null then
    return nil
  end

  return value
end

local function close_client(red, options, reuse)
  if red == nil then
    return
  end

  if reuse and type(red.set_keepalive) == "function" then
    local ok = red:set_keepalive(options.keepalive_ms, options.pool_size)
    if ok then
      return
    end
  end

  if type(red.close) == "function" then
    red:close()
  end
end

local function connect(conf)
  local options = resolve_options(conf)
  if options.host == nil then
    return nil, nil
  end

  local ok, redis = pcall(require, "resty.redis")
  if not ok or type(redis) ~= "table" or type(redis.new) ~= "function" then
    return nil, nil
  end

  local red = redis:new()
  if type(red) ~= "table" then
    return nil, "failed to initialize redis client"
  end

  if type(red.set_timeout) == "function" then
    red:set_timeout(options.timeout_ms)
  end

  local connected, err = red:connect(options.host, options.port)
  if not connected then
    close_client(red, options, false)
    return nil, err
  end

  if options.password ~= nil then
    local authed
    authed, err = red:auth(options.password)
    if not authed then
      close_client(red, options, false)
      return nil, err
    end
  end

  if options.database > 0 then
    local selected
    selected, err = red:select(options.database)
    if not selected then
      close_client(red, options, false)
      return nil, err
    end
  end

  return red, options
end

local function key_for(options, subject_key)
  return options.prefix .. ":" .. subject_key
end

local function parse_subject_and_conf(arg1, arg2, arg3)
  if type(arg1) == "table" then
    return arg2, arg3
  end

  return arg1, arg2
end

function _M.get_last_seen(arg1, arg2, arg3)
  local subject_key, conf = parse_subject_and_conf(arg1, arg2, arg3)
  if type(subject_key) ~= "string" or subject_key == "" then
    return nil, nil
  end

  local red, options = connect(conf)
  if red == nil or options == nil then
    return nil, nil
  end

  local values = red:hmget(key_for(options, subject_key), "version", "ts_ms")
  if type(values) ~= "table" then
    close_client(red, options, false)
    return nil, nil
  end

  local version = redis_nil(values[1])
  local ts_ms = redis_nil(values[2])

  if version ~= nil and type(version) ~= "string" then
    version = tostring(version)
  end

  if ts_ms ~= nil then
    ts_ms = tonumber(ts_ms)
  end

  close_client(red, options, true)
  return version, ts_ms
end

function _M.set_last_seen(arg1, arg2, arg3, arg4, arg5)
  local subject_key
  local version
  local ts_ms
  local conf

  if type(arg1) == "table" then
    subject_key = arg2
    version = arg3
    ts_ms = arg4
    conf = arg5
  else
    subject_key = arg1
    version = arg2
    ts_ms = arg3
    conf = arg4
  end

  if type(subject_key) ~= "string" or subject_key == "" then
    return false
  end

  if type(version) ~= "string" or version == "" then
    return false
  end

  ts_ms = tonumber(ts_ms)
  if ts_ms == nil then
    return false
  end

  local red, options = connect(conf)
  if red == nil or options == nil then
    return false
  end

  local key = key_for(options, subject_key)
  local did_set_version = red:hset(key, "version", version)
  if did_set_version == nil or did_set_version == false then
    close_client(red, options, false)
    return false
  end

  local did_set_ts = red:hset(key, "ts_ms", tostring(ts_ms))
  if did_set_ts == nil or did_set_ts == false then
    close_client(red, options, false)
    return false
  end

  local did_expire = red:expire(key, options.ttl_sec)
  if did_expire == nil or did_expire == false or tonumber(did_expire) == 0 then
    close_client(red, options, false)
    return false
  end

  close_client(red, options, true)
  return true
end

return _M
