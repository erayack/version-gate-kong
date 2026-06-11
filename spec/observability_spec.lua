local constants = require("kong.plugins.version-gate.constants")
local observability = require("kong.plugins.version-gate.observability")

describe("observability", function()
  it("builds event with effective policy fallbacks", function()
    local event = observability.build_event(
      { decision = constants.DECISION_ALLOW, reason = "OK", phase = "log" },
      { id = "policy-default", mode = "shadow" }
    )

    assert.equals("policy-default", event.policy_id)
    assert.equals("shadow", event.mode)
    assert.equals("log", event.phase)
    assert.equals(constants.DECISION_ALLOW, event.decision)
    assert.equals("OK", event.reason)
  end)

  it("routes violation payloads to warning logs", function()
    local warning_payload
    local notice_payload

    observability.emit(
      {},
      { decision = constants.DECISION_VIOLATION, reason = constants.REASON_INVARIANT_VIOLATION },
      {
        warn = function(_, serialized)
          warning_payload = serialized
        end,
        notice = function(_, serialized)
          notice_payload = serialized
        end,
      }
    )

    assert.matches("decision=VIOLATION", warning_payload)
    assert.is_nil(notice_payload)
  end)

  it("serializes deterministic ordered fields with escaping", function()
    local payload

    observability.emit(
      {},
      {
        decision = constants.DECISION_ALLOW,
        reason = "INVARIANT_OK",
        policy_id = "policy-1",
        mode = "shadow",
        phase = "log",
        expected_version = 42,
        actual_version = 43,
        expected_version_raw = "value with spaces",
        actual_version_raw = "x=\"1\"\n",
        request_id = "req-1",
        route_id = "route-1",
        service_id = "service-1",
        started_at = 1000,
        latency_ms = 20,
      },
      {
        notice = function(_, serialized)
          payload = serialized
        end,
      }
    )

    assert.equals(
      " event_version=1 plugin=version-gate policy_id=policy-1 mode=shadow phase=log decision=ALLOW reason=INVARIANT_OK expected_version=42 actual_version=43 expected_version_raw=\"value with spaces\" actual_version_raw=\"x=\\\"1\\\"\\n\" request_id=req-1 route_id=route-1 service_id=service-1 started_at=1000 latency_ms=20",
      payload
    )
  end)

  it("keeps legacy policy_id config fallback", function()
    local event = observability.build_event(
      { decision = constants.DECISION_ALLOW, reason = "OK", phase = "log" },
      { policy_id = "legacy-policy", mode = "shadow" }
    )

    assert.equals("legacy-policy", event.policy_id)
  end)

  it("honors emit_sample_rate and leaves logs unchanged when sample misses", function()
    local payload

    observability.emit(
      { emit_sample_rate = 0.1 },
      { decision = constants.DECISION_ALLOW, reason = constants.REASON_INVARIANT_OK },
      {
        random = function()
          return 0.9
        end,
        notice = function(_, serialized)
          payload = serialized
        end,
      }
    )

    assert.is_nil(payload)
  end)

  it("emits json payload when emit_format=json", function()
    local payload

    observability.emit(
      {
        emit_format = "json",
      },
      {
        decision = constants.DECISION_ALLOW,
        reason = constants.REASON_INVARIANT_OK,
        mode = "shadow",
      },
      {
        notice = function(_, serialized)
          payload = serialized
        end,
      }
    )

    assert.matches("^ %b{}", payload)
    assert.matches("\"plugin\":\"version%-gate\"", payload)
    assert.matches("\"decision\":\"ALLOW\"", payload)
    assert.matches("\"reason\":\"INVARIANT_OK\"", payload)
  end)

  it("omits version values when emit_include_versions=false", function()
    local event = observability.build_event(
      {
        expected_version = 42,
        actual_version = 43,
        expected_version_raw = "42",
        actual_version_raw = "43",
      },
      { emit_include_versions = false }
    )

    assert.is_nil(event.expected_version)
    assert.is_nil(event.actual_version)
    assert.is_nil(event.expected_version_raw)
    assert.is_nil(event.actual_version_raw)
  end)
end)
