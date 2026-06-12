local constants = require("kong.plugins.version-gate.constants")
local coordinator = require("kong.plugins.version-gate.request_coordinator")

local function access(conf, plugin_ctx, raw)
  coordinator.access(conf, plugin_ctx, {
    now_ms = 1000,
    request_id = "request-1",
    route_id = "route-1",
    service_id = "service-1",
    state_subject_key = "subject:test",
    request_ctx = {
      request = {
        get_header = function(name)
          if name == (conf.expected_header_name or "x-expected-version") then
            return raw
          end
          return nil
        end,
      },
    },
  })
end

local function header_filter(conf, plugin_ctx, raw, now_ms, warnings)
  return coordinator.header_filter(conf, plugin_ctx, {
    now_ms = now_ms or 1100,
    state_subject_key = "subject:test",
    response_ctx = {
      response = {
        get_header = function(name)
          if name == (conf.actual_header_name or "x-actual-version") then
            return raw
          end
          return nil
        end,
      },
    },
    warn = function(...)
      warnings[#warnings + 1] = { ... }
    end,
  })
end

describe("request_coordinator", function()
  after_each(function()
    package.loaded["spec.fixtures.version_gate_state_store"] = nil
  end)

  it("classifies allow and invariant violation across access and header_filter", function()
    local warnings = {}
    local conf = {
      mode = "shadow",
      expected_header_name = "x-expected-version",
      actual_header_name = "x-actual-version",
    }
    local plugin_ctx = {}

    access(conf, plugin_ctx, "10")
    assert.equals("default", plugin_ctx.policy_id)
    assert.equals("shadow", plugin_ctx.mode)
    local result = header_filter(conf, plugin_ctx, "9", 1100, warnings)

    assert.equals(constants.DECISION_VIOLATION, plugin_ctx.decision)
    assert.equals(constants.REASON_INVARIANT_VIOLATION, plugin_ctx.reason)
    assert.equals(constants.ACTION_NONE, result.action)
    assert.equals(1, #warnings)

    plugin_ctx = {}
    warnings = {}
    access(conf, plugin_ctx, "10")
    header_filter(conf, plugin_ctx, "10", 1100, warnings)

    assert.equals(constants.DECISION_ALLOW, plugin_ctx.decision)
    assert.equals(constants.REASON_INVARIANT_OK, plugin_ctx.reason)
    assert.equals(0, #warnings)
  end)

  it("keeps missing and invalid versions fail-open with reason classification", function()
    local warnings = {}
    local conf = {
      expected_header_name = "x-expected-version",
      actual_header_name = "x-actual-version",
    }
    local plugin_ctx = {}

    access(conf, plugin_ctx, nil)
    header_filter(conf, plugin_ctx, "9", 1100, warnings)

    assert.equals(constants.DECISION_ALLOW, plugin_ctx.decision)
    assert.equals(constants.REASON_MISSING_EXPECTED, plugin_ctx.reason)

    plugin_ctx = {}
    access(conf, plugin_ctx, "10")
    header_filter(conf, plugin_ctx, "bad", 1100, warnings)

    assert.equals(constants.DECISION_ALLOW, plugin_ctx.decision)
    assert.equals(constants.REASON_PARSE_ERROR_ACTUAL, plugin_ctx.reason)
  end)

  it("downgrades fresh non-violating last-seen violations without persisting violating actual state", function()
    local writes = {}
    package.loaded["spec.fixtures.version_gate_state_store"] = {
      get_last_seen = function()
        return "10", 1050
      end,
      set_last_seen = function(subject_key, version, ts_ms)
        writes[#writes + 1] = { subject_key = subject_key, version = version, ts_ms = ts_ms }
        return true
      end,
    }

    local conf = {
      expected_header_name = "x-expected-version",
      actual_header_name = "x-actual-version",
      state_suppression_window_ms = 100,
      state_store_adapter_module = "spec.fixtures.version_gate_state_store",
    }
    local plugin_ctx = {}
    local warnings = {}

    access(conf, plugin_ctx, "10")
    header_filter(conf, plugin_ctx, "9", 1100, warnings)

    assert.equals(constants.DECISION_ALLOW, plugin_ctx.decision)
    assert.equals(constants.REASON_INVARIANT_OK, plugin_ctx.reason)
    assert.is_true(plugin_ctx.state_suppressed)
    assert.equals(0, #writes)
    assert.equals(0, #warnings)
  end)

  it("returns reject enforcement instructions for reject mode violations", function()
    local conf = {
      mode = "reject",
      reject_status_code = 409,
      expected_header_name = "x-expected-version",
      actual_header_name = "x-actual-version",
    }
    local plugin_ctx = {}
    local warnings = {}

    access(conf, plugin_ctx, "10")
    local result = header_filter(conf, plugin_ctx, "9", 1100, warnings)

    assert.equals(constants.ACTION_REJECT, result.action)
    assert.equals(409, result.status)
    assert.equals(constants.DECISION_VIOLATION, result.headers[constants.HEADER_DECISION])
  end)
end)
