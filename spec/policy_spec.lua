local constants = require("kong.plugins.version-gate.constants")
local policy = require("kong.plugins.version-gate.policy")

describe("policy.resolve_policy", function()
  it("returns default policy values when config is empty", function()
    local resolved = policy.resolve_policy({}, nil, nil)

    assert.equals("default", resolved.id)
    assert.equals("shadow", resolved.mode)
    assert.equals(1.0, resolved.emit_sample_rate)
    assert.is_true(resolved.emit_include_versions)
    assert.equals("logfmt", resolved.emit_format)
    assert.equals(409, resolved.reject_status_code)
    assert.equals("default", resolved.reject_body_template)
    assert.same({ constants.REASON_INVARIANT_VIOLATION }, resolved.enforce_on_reason)
  end)

  it("applies deterministic precedence route > service > global", function()
    local resolved = policy.resolve_policy({
      policy_id = "global",
      mode = "shadow",
      emit_sample_rate = 0.9,
      emit_include_versions = true,
      emit_format = "logfmt",
      reject_status_code = 409,
      reject_body_template = "default",
      policy_overrides = {
        {
          target_type = "service",
          target_id = "svc",
          id = "svc-policy",
          mode = "annotate",
          emit_sample_rate = 0.4,
          emit_include_versions = true,
          emit_format = "logfmt",
          reject_status_code = 429,
          reject_body_template = "minimal",
        },
        {
          target_type = "route",
          target_id = "rte",
          id = "route-policy",
          mode = "reject",
          emit_sample_rate = 0.2,
          emit_include_versions = false,
          emit_format = "json",
          reject_status_code = 451,
          reject_body_template = "default",
        },
      },
    }, "rte", "svc")

    assert.equals("route-policy", resolved.id)
    assert.equals("reject", resolved.mode)
    assert.equals(0.2, resolved.emit_sample_rate)
    assert.is_false(resolved.emit_include_versions)
    assert.equals("json", resolved.emit_format)
    assert.equals(451, resolved.reject_status_code)
    assert.equals("default", resolved.reject_body_template)
  end)

  it("keeps deprecated log_only=true compatibility in effective policy", function()
    local resolved = policy.resolve_policy({ log_only = true }, nil, nil)

    assert.equals("shadow", resolved.mode)
  end)

  it("returns independent copies for cached default policies", function()
    local conf = {
      enforce_on_reason = { constants.REASON_INVARIANT_VIOLATION },
    }

    local first = policy.resolve_policy(conf, nil, nil)
    first.mode = "reject"
    first.enforce_on_reason[1] = "CHANGED"

    local second = policy.resolve_policy(conf, nil, nil)

    assert.equals("shadow", second.mode)
    assert.same({ constants.REASON_INVARIANT_VIOLATION }, second.enforce_on_reason)
  end)

  -- Regression: the no-overrides policy cache served stale public plugin
  -- config after in-place updates; cache reuse is now guarded by a field signature.
  it("recomputes cached default policies when plugin config changes", function()
    local conf = {
      mode = "shadow",
      reject_status_code = 409,
      reject_body_template = "default",
      emit_format = "logfmt",
      emit_include_versions = true,
      enforce_on_reason = { constants.REASON_INVARIANT_VIOLATION },
    }

    assert.equals("shadow", policy.resolve_policy(conf, nil, nil).mode)

    conf.mode = "reject"
    conf.reject_status_code = 451
    conf.reject_body_template = "minimal"
    conf.emit_format = "json"
    conf.emit_include_versions = false
    conf.enforce_on_reason = { constants.REASON_MISSING_ACTUAL }

    local resolved = policy.resolve_policy(conf, nil, nil)

    assert.equals("reject", resolved.mode)
    assert.equals(451, resolved.reject_status_code)
    assert.equals("minimal", resolved.reject_body_template)
    assert.equals("json", resolved.emit_format)
    assert.is_false(resolved.emit_include_versions)
    assert.same({ constants.REASON_MISSING_ACTUAL }, resolved.enforce_on_reason)
  end)

  -- Regression: invalid enforce_on_reason tables must not be cached by identity,
  -- because in-place schema/lifecycle updates can later make the same table valid.
  it("recomputes cached default policies when enforce_on_reason becomes a valid array in place", function()
    local reasons = { named_reason = constants.REASON_MISSING_ACTUAL }
    local conf = {
      enforce_on_reason = reasons,
    }

    assert.same({ constants.REASON_INVARIANT_VIOLATION }, policy.resolve_policy(conf, nil, nil).enforce_on_reason)

    reasons.named_reason = nil
    reasons[1] = constants.REASON_MISSING_ACTUAL

    assert.same({ constants.REASON_MISSING_ACTUAL }, policy.resolve_policy(conf, nil, nil).enforce_on_reason)
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
