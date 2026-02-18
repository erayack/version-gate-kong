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
      get_expected_version = function()
        return nil, nil
      end,
      get_actual_version = function()
        return nil, nil
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

    package.loaded["kong.plugins.version-gate.handler"] = nil
    package.loaded["kong.plugins.version-gate.ctx"] = {
      set_actual = function() end,
      set_decision = function() end,
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
      get_expected_version = function()
        return nil, nil
      end,
      get_actual_version = function()
        return "10", nil
      end,
    }
    package.loaded["kong.plugins.version-gate.observability"] = {
      emit = function() end,
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
    decision_snapshot = {
      decision = "VIOLATION",
      reason = "MISSING_ACTUAL",
    }

    local handler = require("kong.plugins.version-gate.handler")

    handler:header_filter({
      enabled = true,
      actual_header_name = "x-version",
    })

    assert.equals(0, #captured_warns)
  end)
end)
