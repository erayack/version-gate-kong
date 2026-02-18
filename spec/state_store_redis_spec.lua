describe("state_store_redis", function()
  local saved_ngx
  local saved_getenv
  local env

  before_each(function()
    saved_ngx = _G.ngx
    saved_getenv = os.getenv
    env = {}
    os.getenv = function(key) -- luacheck: ignore
      return env[key]
    end

    package.loaded["resty.redis"] = nil
    package.loaded["kong.plugins.version-gate.state_store_redis"] = nil
  end)

  after_each(function()
    _G.ngx = saved_ngx
    os.getenv = saved_getenv -- luacheck: ignore

    package.loaded["resty.redis"] = nil
    package.loaded["kong.plugins.version-gate.state_store_redis"] = nil
  end)

  it("reads and writes hash state with keepalive", function()
    _G.ngx = { null = {} }

    local captured = {}
    package.loaded["resty.redis"] = {
      new = function()
        return {
          set_timeout = function(_, timeout_ms)
            captured.timeout_ms = timeout_ms
          end,
          connect = function(_, host, port)
            captured.host = host
            captured.port = port
            return true
          end,
          select = function(_, db)
            captured.db = db
            return true
          end,
          hmget = function(_, key, field_a, field_b)
            captured.hmget = { key = key, field_a = field_a, field_b = field_b }
            return { "42", "1234" }
          end,
          hset = function(_, key, field_a, value_a, field_b, value_b)
            captured.hset = captured.hset or {}
            captured.hset[#captured.hset + 1] = {
              key = key,
              field_a = field_a,
              value_a = value_a,
              field_b = field_b,
              value_b = value_b,
            }
            return 1
          end,
          expire = function(_, key, ttl_sec)
            captured.expire = { key = key, ttl_sec = ttl_sec }
            return 1
          end,
          set_keepalive = function(_, keepalive_ms, pool_size)
            captured.keepalive = { keepalive_ms = keepalive_ms, pool_size = pool_size }
            return true
          end,
          close = function()
            captured.closed = true
          end,
        }
      end,
    }

    local adapter = require("kong.plugins.version-gate.state_store_redis")
    local conf = {
      state_store_redis_host = "127.0.0.1",
      state_store_redis_port = 6380,
      state_store_redis_database = 2,
      state_store_redis_timeout_ms = 250,
      state_store_redis_keepalive_ms = 70000,
      state_store_redis_pool_size = 22,
      state_store_redis_prefix = "custom-prefix",
      state_store_ttl_sec = 45,
    }

    local version, ts_ms = adapter.get_last_seen("route:a", conf)
    local ok = adapter.set_last_seen("route:a", "88", 5678, conf)

    assert.equals("42", version)
    assert.equals(1234, ts_ms)
    assert.is_true(ok)
    assert.equals(250, captured.timeout_ms)
    assert.equals("127.0.0.1", captured.host)
    assert.equals(6380, captured.port)
    assert.equals(2, captured.db)
    assert.equals("custom-prefix:route:a", captured.hmget.key)
    assert.equals(2, #captured.hset)
    assert.equals("custom-prefix:route:a", captured.hset[1].key)
    assert.equals("version", captured.hset[1].field_a)
    assert.equals("88", captured.hset[1].value_a)
    assert.is_nil(captured.hset[1].field_b)
    assert.equals("custom-prefix:route:a", captured.hset[2].key)
    assert.equals("ts_ms", captured.hset[2].field_a)
    assert.equals("5678", captured.hset[2].value_a)
    assert.is_nil(captured.hset[2].field_b)
    assert.equals("custom-prefix:route:a", captured.expire.key)
    assert.equals(45, captured.expire.ttl_sec)
    assert.equals(70000, captured.keepalive.keepalive_ms)
    assert.equals(22, captured.keepalive.pool_size)
    assert.is_nil(captured.closed)
  end)

  it("supports env fallback and missing values", function()
    _G.ngx = { null = {} }
    env.KONG_REDIS_HOST = "redis-from-env"
    env.KONG_REDIS_PORT = "6390"
    env.KONG_REDIS_PREFIX = "env-prefix"

    local captured = {}
    package.loaded["resty.redis"] = {
      new = function()
        return {
          connect = function(_, host, port)
            captured.host = host
            captured.port = port
            return true
          end,
          hmget = function(_, key)
            captured.key = key
            return { _G.ngx.null, _G.ngx.null }
          end,
          set_keepalive = function()
            return true
          end,
        }
      end,
    }

    local adapter = require("kong.plugins.version-gate.state_store_redis")
    local version, ts_ms = adapter:get_last_seen("route:env")

    assert.is_nil(version)
    assert.is_nil(ts_ms)
    assert.equals("redis-from-env", captured.host)
    assert.equals(6390, captured.port)
    assert.equals("env-prefix:route:env", captured.key)
  end)

  it("fails open when redis host or client is unavailable", function()
    local adapter = require("kong.plugins.version-gate.state_store_redis")

    local version, ts_ms = adapter.get_last_seen("route:nohost", {})
    local ok = adapter.set_last_seen("route:nohost", "1", 1, {})
    assert.is_nil(version)
    assert.is_nil(ts_ms)
    assert.is_false(ok)

    package.loaded["resty.redis"] = {
      new = function()
        return {
          connect = function()
            return nil, "boom"
          end,
        }
      end,
    }

    version, ts_ms = adapter.get_last_seen("route:down", { state_store_redis_host = "redis" })
    ok = adapter.set_last_seen("route:down", "1", 1, { state_store_redis_host = "redis" })
    assert.is_nil(version)
    assert.is_nil(ts_ms)
    assert.is_false(ok)
  end)

  it("fails open when redis client initialization returns nil", function()
    package.loaded["resty.redis"] = {
      new = function()
        return nil
      end,
    }

    local adapter = require("kong.plugins.version-gate.state_store_redis")
    local version, ts_ms = adapter.get_last_seen("route:init", { state_store_redis_host = "redis" })
    local ok = adapter.set_last_seen("route:init", "2", 2, { state_store_redis_host = "redis" })

    assert.is_nil(version)
    assert.is_nil(ts_ms)
    assert.is_false(ok)
  end)
end)
