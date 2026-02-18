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
