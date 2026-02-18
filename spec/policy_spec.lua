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
      policy_by_service = {
        svc = { id = "svc-policy", mode = "annotate", emit_sample_rate = 0.4 },
      },
      policy_by_route = {
        rte = { id = "route-policy", mode = "reject", emit_sample_rate = 0.2 },
      },
    }, "rte", "svc")

    assert.equals("route-policy", resolved.id)
    assert.equals("reject", resolved.mode)
    assert.equals(0.2, resolved.emit_sample_rate)
  end)

  it("copies enforce_on_reason arrays to avoid mutation aliasing", function()
    local conf = {
      enforce_on_reason = { constants.REASON_INVARIANT_VIOLATION },
      policy_by_service = {
        svc = { enforce_on_reason = { constants.REASON_MISSING_ACTUAL } },
      },
    }

    local resolved = policy.resolve_policy(conf, nil, "svc")
    resolved.enforce_on_reason[1] = "CHANGED"

    assert.same({ constants.REASON_MISSING_ACTUAL }, conf.policy_by_service.svc.enforce_on_reason)
  end)
end)
