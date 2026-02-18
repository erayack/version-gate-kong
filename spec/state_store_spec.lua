describe("state_store", function()
  local saved_ngx

  before_each(function()
    saved_ngx = _G.ngx
    package.loaded["kong.plugins.version-gate.state_store"] = nil
  end)

  after_each(function()
    _G.ngx = saved_ngx
    package.loaded["kong.plugins.version-gate.state_store"] = nil
  end)

  it("returns nil values when subject key is invalid", function()
    local state_store = require("kong.plugins.version-gate.state_store")
    local version, ts_ms = state_store.get_last_seen(nil, {})

    assert.is_nil(version)
    assert.is_nil(ts_ms)
    assert.is_false(state_store.set_last_seen("", "1", 1, {}))
  end)

  it("uses provided adapter when available", function()
    local captured_set
    local adapter = {
      get_last_seen = function(subject_key)
        return "77", 1234
      end,
      set_last_seen = function(subject_key, version, ts_ms)
        captured_set = { subject_key = subject_key, version = version, ts_ms = ts_ms }
        return true
      end,
    }

    local state_store = require("kong.plugins.version-gate.state_store")
    local version, ts_ms = state_store.get_last_seen("route:a", { state_store_adapter = adapter })
    local ok = state_store.set_last_seen("route:a", "88", 5678, { state_store_adapter = adapter })

    assert.equals("77", version)
    assert.equals(1234, ts_ms)
    assert.is_true(ok)
    assert.equals("route:a", captured_set.subject_key)
    assert.equals("88", captured_set.version)
    assert.equals(5678, captured_set.ts_ms)
  end)

  it("supports colon-style adapter methods", function()
    local adapter = {
      get_last_seen = function(self, subject_key)
        return self[subject_key], 4321
      end,
      set_last_seen = function(self, subject_key, version)
        self[subject_key] = version
        return true
      end,
    }

    local state_store = require("kong.plugins.version-gate.state_store")
    local ok = state_store.set_last_seen("route:c", "55", 1111, { state_store_adapter = adapter })
    local version, ts_ms = state_store.get_last_seen("route:c", { state_store_adapter = adapter })

    assert.is_true(ok)
    assert.equals("55", version)
    assert.equals(4321, ts_ms)
  end)

  it("returns adapter partial values without forcing dict fallback", function()
    local adapter = {
      get_last_seen = function()
        return "77", nil
      end,
    }

    local state_store = require("kong.plugins.version-gate.state_store")
    local version, ts_ms = state_store.get_last_seen("route:partial", { state_store_adapter = adapter })

    assert.equals("77", version)
    assert.is_nil(ts_ms)
  end)

  it("falls back to shared dict when adapter fails", function()
    local store = {}
    local captured_ttl = {}
    _G.ngx = {
      shared = {
        version_gate_state = {
          get = function(_, key)
            return store[key]
          end,
          set = function(_, key, value, ttl)
            store[key] = value
            captured_ttl[#captured_ttl + 1] = ttl
            return true
          end,
        },
      },
    }

    local state_store = require("kong.plugins.version-gate.state_store")
    local conf = {
      state_store_adapter = {
        get_last_seen = function()
          error("boom")
        end,
        set_last_seen = function()
          error("boom")
        end,
      },
    }

    conf.state_store_ttl_sec = 45
    assert.is_true(state_store.set_last_seen("route:b", "99", 2468, conf))

    local version, ts_ms = state_store.get_last_seen("route:b", conf)
    assert.equals("99", version)
    assert.equals(2468, ts_ms)
    assert.equals(2, #captured_ttl)
    assert.equals(45, captured_ttl[1])
    assert.equals(45, captured_ttl[2])
  end)
end)
