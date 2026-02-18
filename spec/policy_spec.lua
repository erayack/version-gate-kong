local constants = require("kong.plugins.version-gate.constants")
local policy = require("kong.plugins.version-gate.policy")

describe("policy.resolve_policy", function()
  it("returns default policy values when config is empty", function()
    local resolved = policy.resolve_policy({}, nil, nil)

    assert.equals("default", resolved.id)
    assert.equals("shadow", resolved.mode)
    assert.equals(1.0, resolved.emit_sample_rate)
    assert.same({ constants.REASON_INVARIANT_VIOLATION }, resolved.enforce_on_reason)
  end)

  it("applies deterministic precedence route > service > global", function()
    local resolved = policy.resolve_policy({
      policy_id = "global",
      mode = "shadow",
      emit_sample_rate = 0.9,
      policy_overrides = {
        { target_type = "service", target_id = "svc", id = "svc-policy", mode = "annotate", emit_sample_rate = 0.4 },
        { target_type = "route", target_id = "rte", id = "route-policy", mode = "reject", emit_sample_rate = 0.2 },
      },
    }, "rte", "svc")

    assert.equals("route-policy", resolved.id)
    assert.equals("reject", resolved.mode)
    assert.equals(0.2, resolved.emit_sample_rate)
  end)

  it("copies enforce_on_reason arrays to avoid mutation aliasing", function()
    local conf = {
      enforce_on_reason = { constants.REASON_INVARIANT_VIOLATION },
      policy_overrides = {
        { target_type = "service", target_id = "svc", enforce_on_reason = { constants.REASON_MISSING_ACTUAL } },
      },
    }

    local resolved = policy.resolve_policy(conf, nil, "svc")
    resolved.enforce_on_reason[1] = "CHANGED"

    assert.same({ constants.REASON_MISSING_ACTUAL }, conf.policy_overrides[1].enforce_on_reason)
  end)

  it("uses last matching override when multiple records target the same scope", function()
    local resolved = policy.resolve_policy({
      mode = "shadow",
      reject_status_code = 409,
      policy_overrides = {
        { target_type = "service", target_id = "svc", mode = "annotate", reject_status_code = 418 },
        { target_type = "service", target_id = "svc", mode = "reject", reject_status_code = 451 },
      },
    }, nil, "svc")

    assert.equals("reject", resolved.mode)
    assert.equals(451, resolved.reject_status_code)
  end)

  it("applies route override reject settings over service override", function()
    local resolved = policy.resolve_policy({
      mode = "shadow",
      reject_status_code = 409,
      reject_body_template = "default",
      policy_overrides = {
        {
          target_type = "service",
          target_id = "svc",
          mode = "reject",
          reject_status_code = 429,
          reject_body_template = "minimal",
        },
        {
          target_type = "route",
          target_id = "rte",
          mode = "reject",
          reject_status_code = 451,
          reject_body_template = "default",
        },
      },
    }, "rte", "svc")

    assert.equals("reject", resolved.mode)
    assert.equals(451, resolved.reject_status_code)
    assert.equals("default", resolved.reject_body_template)
  end)
end)
