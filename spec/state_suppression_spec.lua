local constants = require("kong.plugins.version-gate.constants")
local state_suppression = require("kong.plugins.version-gate.state_suppression")

local function suppress(opts)
  opts = opts or {}
  return state_suppression.apply({
    conf = opts.conf or { state_suppression_window_ms = 100 },
    store = opts.store,
    subject_key = opts.subject_key or "subject:test",
    decision = opts.decision or constants.DECISION_VIOLATION,
    reason = opts.reason or constants.REASON_INVARIANT_VIOLATION,
    expected_version = opts.expected_version or "10",
    actual_version = opts.actual_version,
    now_ts_ms = opts.now_ts_ms or 1100,
  })
end

describe("state_suppression", function()
  it("does nothing when suppression is disabled", function()
    local reads = 0
    local writes = 0
    local result = suppress({
      conf = { state_suppression_window_ms = 0 },
      actual_version = "9",
      store = {
        get_last_seen = function()
          reads = reads + 1
          return "10", 1050
        end,
        set_last_seen = function()
          writes = writes + 1
          return true
        end,
      },
    })

    assert.equals(constants.DECISION_VIOLATION, result.decision)
    assert.equals(constants.REASON_INVARIANT_VIOLATION, result.reason)
    assert.is_nil(result.state_suppressed)
    assert.equals(0, reads)
    assert.equals(0, writes)
  end)

  it("keeps violations when no last-seen state exists", function()
    local result = suppress({
      store = {
        get_last_seen = function()
          return nil, nil
        end,
      },
    })

    assert.equals(constants.DECISION_VIOLATION, result.decision)
    assert.equals(constants.REASON_INVARIANT_VIOLATION, result.reason)
    assert.is_nil(result.state_suppressed)
    assert.is_nil(result.last_seen_version)
    assert.is_nil(result.last_seen_ts_ms)
  end)

  it("keeps violations when last-seen state is stale", function()
    local result = suppress({
      store = {
        get_last_seen = function()
          return "10", 900
        end,
      },
    })

    assert.equals(constants.DECISION_VIOLATION, result.decision)
    assert.equals(constants.REASON_INVARIANT_VIOLATION, result.reason)
    assert.equals("10", result.last_seen_version)
    assert.equals(900, result.last_seen_ts_ms)
    assert.is_nil(result.state_suppressed)
  end)

  it("downgrades fresh non-violating last-seen violations", function()
    local result = suppress({
      store = {
        get_last_seen = function(_, subject_key)
          assert.equals("subject:test", subject_key)
          return "10", 1050
        end,
      },
    })

    assert.equals(constants.DECISION_ALLOW, result.decision)
    assert.equals(constants.REASON_INVARIANT_OK, result.reason)
    assert.is_true(result.state_suppressed)
    assert.equals("10", result.last_seen_version)
    assert.equals(1050, result.last_seen_ts_ms)
  end)

  it("keeps violations when last-seen version is also violating", function()
    local result = suppress({
      store = {
        get_last_seen = function()
          return "9", 1050
        end,
      },
    })

    assert.equals(constants.DECISION_VIOLATION, result.decision)
    assert.equals(constants.REASON_INVARIANT_VIOLATION, result.reason)
    assert.is_nil(result.state_suppressed)
  end)

  it("persists non-violating actual versions through the store seam", function()
    local writes = {}
    local result = suppress({
      decision = constants.DECISION_ALLOW,
      reason = constants.REASON_INVARIANT_OK,
      actual_version = "11",
      store = {
        get_last_seen = function()
          error("read should not be called for non-violations")
        end,
        set_last_seen = function(_, subject_key, version, ts_ms)
          writes[#writes + 1] = { subject_key = subject_key, version = version, ts_ms = ts_ms }
          return true
        end,
      },
    })

    assert.equals(constants.DECISION_ALLOW, result.decision)
    assert.is_true(result.state_store_write_ok)
    assert.equals(1, #writes)
    assert.equals("subject:test", writes[1].subject_key)
    assert.equals("11", writes[1].version)
    assert.equals(1100, writes[1].ts_ms)
  end)

  it("fails open on state-store read errors", function()
    local result = suppress({
      store = {
        get_last_seen = function()
          error("boom")
        end,
      },
    })

    assert.equals(constants.DECISION_VIOLATION, result.decision)
    assert.equals(constants.REASON_INVARIANT_VIOLATION, result.reason)
    assert.is_nil(result.state_suppressed)
  end)

  it("reports failed writes without changing allow decision", function()
    local result = suppress({
      decision = constants.DECISION_ALLOW,
      reason = constants.REASON_INVARIANT_OK,
      actual_version = "11",
      store = {
        set_last_seen = function()
          error("boom")
        end,
      },
    })

    assert.equals(constants.DECISION_ALLOW, result.decision)
    assert.is_false(result.state_store_write_ok)
  end)

  it("does not persist unsuppressed violations", function()
    local writes = 0
    local result = suppress({
      actual_version = "9",
      store = {
        get_last_seen = function()
          return nil, nil
        end,
        set_last_seen = function()
          writes = writes + 1
          return true
        end,
      },
    })

    assert.equals(constants.DECISION_VIOLATION, result.decision)
    assert.equals(constants.REASON_INVARIANT_VIOLATION, result.reason)
    assert.is_nil(result.state_store_write_ok)
    assert.equals(0, writes)
  end)

  it("does not persist suppressed violations", function()
    local writes = 0
    local result = suppress({
      actual_version = "9",
      store = {
        get_last_seen = function()
          return "10", 1050
        end,
        set_last_seen = function()
          writes = writes + 1
          return true
        end,
      },
    })

    assert.equals(constants.DECISION_ALLOW, result.decision)
    assert.equals(constants.REASON_INVARIANT_OK, result.reason)
    assert.is_true(result.state_suppressed)
    assert.is_nil(result.state_store_write_ok)
    assert.equals(0, writes)
  end)

  it("does not suppress or persist fail-open missing or invalid version decisions", function()
    local reads = 0
    local writes = 0
    local result = suppress({
      decision = constants.DECISION_ALLOW,
      reason = constants.REASON_MISSING_EXPECTED,
      expected_version = nil,
      actual_version = "9",
      store = {
        get_last_seen = function()
          reads = reads + 1
          return "10", 1050
        end,
        set_last_seen = function()
          writes = writes + 1
          return true
        end,
      },
    })

    assert.equals(constants.DECISION_ALLOW, result.decision)
    assert.equals(constants.REASON_MISSING_EXPECTED, result.reason)
    assert.is_nil(result.state_suppressed)
    assert.is_nil(result.state_store_write_ok)
    assert.equals(0, reads)
    assert.equals(0, writes)
  end)
end)
