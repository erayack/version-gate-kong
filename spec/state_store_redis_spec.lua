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

  it("reads and writes last-seen state through Redis using configured connection options", function()
    _G.ngx = { null = {} }

    local state = {
      ["custom-prefix:route:a"] = { version = "42", ts_ms = "1234" },
    }
    local expirations = {}
    local connections = {}
    local keepalives = {}

    package.loaded["resty.redis"] = {
      new = function()
        return {
          set_timeout = function(_, timeout_ms)
            connections.timeout_ms = timeout_ms
          end,
          connect = function(_, host, port)
            connections[#connections + 1] = { host = host, port = port }
            return true
          end,
          select = function(_, db)
            connections.database = db
            return true
          end,
          hmget = function(_, key)
            local stored = state[key] or {}
            return { stored.version or _G.ngx.null, stored.ts_ms or _G.ngx.null }
          end,
          hset = function(_, key, ...)
            state[key] = state[key] or {}
            local args = { ... }
            for i = 1, #args, 2 do
              state[key][args[i]] = args[i + 1]
            end
            return 1
          end,
          expire = function(_, key, ttl_sec)
            expirations[key] = ttl_sec
            return 1
          end,
          set_keepalive = function(_, keepalive_ms, pool_size)
            keepalives[#keepalives + 1] = { keepalive_ms = keepalive_ms, pool_size = pool_size }
            return true
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
    assert.same({ version = "88", ts_ms = "5678" }, state["custom-prefix:route:a"])
    assert.equals(45, expirations["custom-prefix:route:a"])
    assert.equals("127.0.0.1", connections[1].host)
    assert.equals(6380, connections[1].port)
    assert.equals(2, connections.database)
    assert.equals(250, connections.timeout_ms)
    assert.equals(70000, keepalives[1].keepalive_ms)
    assert.equals(22, keepalives[1].pool_size)
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
