describe("handler.log", function()
  local saved_kong
  local saved_ngx
  local captured_conf

  before_each(function()
    saved_kong = _G.kong
    saved_ngx = _G.ngx
    captured_conf = nil

    package.loaded["kong.plugins.version-gate.handler"] = nil
    package.loaded["kong.plugins.version-gate.observability"] = {
      emit = function(conf)
        captured_conf = conf
      end,
    }
    package.loaded["kong.plugins.version-gate.ctx"] = {
      snapshot = function()
        return {}
      end,
      set_latency = function() end,
    }
    package.loaded["kong.plugins.version-gate.policy"] = {
      resolve_policy = function()
        return {}
      end,
    }
    package.loaded["kong.plugins.version-gate.decision_engine"] = {
      classify = function()
        return "ALLOW", "INVARIANT_OK"
      end,
    }
    package.loaded["kong.plugins.version-gate.enforcement"] = {
      handle = function() end,
    }
    package.loaded["kong.plugins.version-gate.version_extractor"] = {
      get_expected_raw = function()
        return nil
      end,
      get_actual_raw = function()
        return nil
      end,
      parse_version = function(raw)
        if raw == nil then
          return nil, nil
        end

        return tostring(raw), nil
      end,
      get_expected_version = function()
        return nil, nil
      end,
      get_actual_version = function()
        return nil, nil
      end,
    }
    package.loaded["kong.plugins.version-gate.state_store"] = {
      new = function()
        return {
          get_last_seen = function()
            return nil, nil
          end,
          set_last_seen = function()
            return true
          end,
        }
      end,
    }

    _G.ngx = { now = function() return 1000 end }
    _G.kong = {
      ctx = { plugin = { policy = { emit_sample_rate = 0.2 } } },
      log = {
        warn = function() end,
        notice = function() end,
      },
    }
  end)

  after_each(function()
    _G.kong = saved_kong
    _G.ngx = saved_ngx
    package.loaded["kong.plugins.version-gate.handler"] = nil
    package.loaded["kong.plugins.version-gate.observability"] = nil
    package.loaded["kong.plugins.version-gate.ctx"] = nil
    package.loaded["kong.plugins.version-gate.policy"] = nil
    package.loaded["kong.plugins.version-gate.decision_engine"] = nil
    package.loaded["kong.plugins.version-gate.enforcement"] = nil
    package.loaded["kong.plugins.version-gate.version_extractor"] = nil
    package.loaded["kong.plugins.version-gate.state_store"] = nil
  end)

  it("applies resolved policy emit_sample_rate for observability emission", function()
    local handler = require("kong.plugins.version-gate.handler")

    handler:log({
      enabled = true,
      emit_sample_rate = 1.0,
      emit_format = "logfmt",
      emit_include_versions = true,
    })

    assert.is_not_nil(captured_conf)
    assert.equals(0.2, captured_conf.emit_sample_rate)
  end)
end)

describe("handler.header_filter", function()
  local saved_kong
  local saved_ngx
  local captured_headers
  local captured_exit
  local captured_warns
  local enforcement_result
  local decision_snapshot
  local store_last_seen_version
  local store_last_seen_ts_ms
  local store_last_seen_key
  local store_write_calls
  local store_written
  local parse_inputs
  local actual_raw_calls

  before_each(function()
    saved_kong = _G.kong
    saved_ngx = _G.ngx
    captured_headers = {}
    captured_exit = nil
    captured_warns = {}
    enforcement_result = { action = "none" }
    decision_snapshot = {
      decision = "VIOLATION",
      reason = "INVARIANT_VIOLATION",
    }
    store_last_seen_version = nil
    store_last_seen_ts_ms = nil
    store_last_seen_key = nil
    store_write_calls = 0
    store_written = nil
    parse_inputs = {}
    actual_raw_calls = 0

    package.loaded["kong.plugins.version-gate.handler"] = nil
    package.loaded["kong.plugins.version-gate.ctx"] = {
      set_actual = function(_, _, parsed_value)
        decision_snapshot.actual_version = parsed_value
      end,
      set_decision = function(_, decision, reason)
        decision_snapshot.decision = decision
        decision_snapshot.reason = reason
      end,
      snapshot = function()
        return decision_snapshot
      end,
      set_latency = function() end,
      init_request_state = function() end,
      set_expected = function() end,
    }
    package.loaded["kong.plugins.version-gate.policy"] = {
      resolve_policy = function()
        return { mode = "shadow" }
      end,
    }
    package.loaded["kong.plugins.version-gate.decision_engine"] = {
      classify = function()
        return "VIOLATION", "INVARIANT_VIOLATION"
      end,
    }
    package.loaded["kong.plugins.version-gate.enforcement"] = {
      handle = function()
        return enforcement_result
      end,
    }
    package.loaded["kong.plugins.version-gate.version_extractor"] = {
      get_expected_raw = function()
        return nil
      end,
      get_actual_raw = function()
        actual_raw_calls = actual_raw_calls + 1
        return "10"
      end,
      parse_version = function(raw, parse_error_reason)
        parse_inputs[#parse_inputs + 1] = raw
        if raw == nil then
          return nil, nil
        end

        local value = tostring(raw)
        if not value:match("^%d+$") then
          return nil, parse_error_reason
        end

        return value:gsub("^0+", "") ~= "" and value:gsub("^0+", "") or "0", nil
      end,
    }
    package.loaded["kong.plugins.version-gate.observability"] = {
      emit = function() end,
    }
    package.loaded["kong.plugins.version-gate.state_store"] = {
      new = function()
        return {
          get_last_seen = function(_, subject_key)
            store_last_seen_key = subject_key
            return store_last_seen_version, store_last_seen_ts_ms
          end,
          set_last_seen = function(_, subject_key, version, ts_ms)
            store_write_calls = store_write_calls + 1
            store_written = { subject_key = subject_key, version = version, ts_ms = ts_ms }
            return true
          end,
        }
      end,
    }

    _G.ngx = { now = function() return 1000 end }
    _G.kong = {
      ctx = { plugin = { policy = { mode = "shadow", enforce_on_reason = { "INVARIANT_VIOLATION" } } } },
      response = {
        get_header = function()
          return "10"
        end,
        set_header = function(k, v)
          captured_headers[k] = v
        end,
        exit = function(status, body, headers)
          captured_exit = { status = status, body = body, headers = headers }
          return captured_exit
        end,
      },
      log = {
        warn = function(...)
          captured_warns[#captured_warns + 1] = { ... }
        end,
        notice = function() end,
      },
      request = {
        get_header = function()
          return nil
        end,
        get_method = function()
          return "GET"
        end,
        get_path = function()
          return "/foo"
        end,
      },
    }
  end)

  after_each(function()
    _G.kong = saved_kong
    _G.ngx = saved_ngx
    package.loaded["kong.plugins.version-gate.handler"] = nil
    package.loaded["kong.plugins.version-gate.ctx"] = nil
    package.loaded["kong.plugins.version-gate.policy"] = nil
    package.loaded["kong.plugins.version-gate.decision_engine"] = nil
    package.loaded["kong.plugins.version-gate.enforcement"] = nil
    package.loaded["kong.plugins.version-gate.version_extractor"] = nil
    package.loaded["kong.plugins.version-gate.observability"] = nil
    package.loaded["kong.plugins.version-gate.state_store"] = nil
  end)

  it("applies annotation headers from enforcement result", function()
    enforcement_result = {
      action = "annotate",
      headers = {
        ["x-version-gate-decision"] = "VIOLATION",
        ["x-version-gate-reason"] = "INVARIANT_VIOLATION",
      },
    }
    local handler = require("kong.plugins.version-gate.handler")

    handler:header_filter({
      enabled = true,
      actual_header_name = "x-version",
    })

    assert.equals("VIOLATION", captured_headers["x-version-gate-decision"])
    assert.equals("INVARIANT_VIOLATION", captured_headers["x-version-gate-reason"])
    assert.is_nil(captured_exit)
    assert.equals(1, #captured_warns)
  end)

  it("exits with reject result from enforcement", function()
    enforcement_result = {
      action = "reject",
      status = 409,
      body = { message = "version gate violation" },
      headers = { ["x-version-gate-decision"] = "VIOLATION" },
    }
    local handler = require("kong.plugins.version-gate.handler")

    local result = handler:header_filter({
      enabled = true,
      actual_header_name = "x-version",
    })

    assert.is_not_nil(captured_exit)
    assert.equals(409, captured_exit.status)
    assert.equals("version gate violation", captured_exit.body.message)
    assert.equals(captured_exit, result)
    assert.equals(1, #captured_warns)
  end)

  it("does not warn when violation reason is excluded from enforce_on_reason", function()
    package.loaded["kong.plugins.version-gate.decision_engine"].classify = function()
      return "VIOLATION", "MISSING_ACTUAL"
    end

    local handler = require("kong.plugins.version-gate.handler")

    handler:header_filter({
      enabled = true,
      actual_header_name = "x-version",
    })

    assert.equals(0, #captured_warns)
  end)

  it("parses the extracted raw value in a single pass", function()
    package.loaded["kong.plugins.version-gate.version_extractor"].get_actual_raw = function()
      actual_raw_calls = actual_raw_calls + 1
      return "0010"
    end

    local handler = require("kong.plugins.version-gate.handler")

    handler:header_filter({
      enabled = true,
      actual_header_name = "x-version",
      state_suppression_window_ms = 100,
    })

    assert.equals(1, actual_raw_calls)
    assert.equals("0010", parse_inputs[1])
  end)

  it("suppresses invariant violation when last_seen is fresh and non-violating", function()
    store_last_seen_version = "10"
    store_last_seen_ts_ms = 1000000 - 50
    _G.kong.ctx.plugin.expected_version = "10"

    local handler = require("kong.plugins.version-gate.handler")

    handler:header_filter({
      enabled = true,
      actual_header_name = "x-version",
      state_suppression_window_ms = 100,
    })

    assert.equals("ALLOW", decision_snapshot.decision)
    assert.equals("INVARIANT_OK", decision_snapshot.reason)
    assert.equals(0, #captured_warns)
  end)

  it("does not suppress when last_seen timestamp is stale", function()
    store_last_seen_version = "10"
    store_last_seen_ts_ms = 1000000 - 200
    _G.kong.ctx.plugin.expected_version = "10"

    local handler = require("kong.plugins.version-gate.handler")

    handler:header_filter({
      enabled = true,
      actual_header_name = "x-version",
      state_suppression_window_ms = 100,
    })

    assert.equals("VIOLATION", decision_snapshot.decision)
    assert.equals("INVARIANT_VIOLATION", decision_snapshot.reason)
    assert.equals(1, #captured_warns)
  end)

  it("does not suppress when last_seen is still violating expected version", function()
    store_last_seen_version = "8"
    store_last_seen_ts_ms = 1000000 - 50
    _G.kong.ctx.plugin.expected_version = "10"

    local handler = require("kong.plugins.version-gate.handler")

    handler:header_filter({
      enabled = true,
      actual_header_name = "x-version",
      state_suppression_window_ms = 100,
    })

    assert.equals("VIOLATION", decision_snapshot.decision)
    assert.equals("INVARIANT_VIOLATION", decision_snapshot.reason)
    assert.equals(1, #captured_warns)
  end)

  it("writes state only when suppression window is enabled", function()
    local handler = require("kong.plugins.version-gate.handler")

    handler:header_filter({
      enabled = true,
      actual_header_name = "x-version",
      state_suppression_window_ms = 0,
    })
    assert.equals(0, store_write_calls)

    handler:header_filter({
      enabled = true,
      actual_header_name = "x-version",
      state_suppression_window_ms = 100,
    })
    assert.equals(1, store_write_calls)
    assert.equals("10", store_written.version)
    assert.equals(1000000, store_written.ts_ms)
  end)

  it("uses subject header key before composite fallback key", function()
    store_last_seen_version = "10"
    store_last_seen_ts_ms = 1000000 - 50
    _G.kong.ctx.plugin.expected_version = "10"
    _G.kong.ctx.plugin.route_id = "route-1"
    _G.kong.ctx.plugin.service_id = "service-1"
    _G.kong.request.get_header = function(name)
      if name == "x-subject" then
        return "tenant-42"
      end

      return nil
    end

    local handler = require("kong.plugins.version-gate.handler")

    handler:header_filter({
      enabled = true,
      actual_header_name = "x-version",
      state_suppression_window_ms = 100,
      state_subject_header_name = "x-subject",
    })

    assert.equals("subject:tenant-42", store_last_seen_key)
  end)

  it("uses composite subject key when subject header is missing", function()
    store_last_seen_version = "10"
    store_last_seen_ts_ms = 1000000 - 50
    _G.kong.ctx.plugin.expected_version = "10"
    _G.kong.ctx.plugin.route_id = "route-1"
    _G.kong.ctx.plugin.service_id = "service-1"

    local handler = require("kong.plugins.version-gate.handler")

    handler:header_filter({
      enabled = true,
      actual_header_name = "x-version",
      state_suppression_window_ms = 100,
      state_subject_header_name = "x-subject",
    })

    assert.equals("route:route-1|service:service-1|method:GET|path:/foo", store_last_seen_key)
  end)
end)
