# Version Gate Kong Plugin

Kong plugin that detects monotonic-read violations by comparing an `expected` version (request-side) with an `actual` version (response-side).

## Behavior

- Decision = `VIOLATION` when `actual_version < expected_version`
- Decision = `ALLOW` for all other cases
- Missing/invalid versions are fail-open (`ALLOW`) with reason classification
- Enforcement mode is configurable:
  - `shadow`: no mutation, emit telemetry/logs
  - `annotate`: add response headers (`x-version-gate-decision`, `x-version-gate-reason`, `x-version-gate-mode`)
  - `reject`: return configured synthetic response for violations

## Version Sources

Expected and actual versions can be sourced independently using:
- `header`
- `query`
- `jwt_claim`
- `cookie`

Parsed versions are normalized digit strings (`"00042"` -> `"42"`, `"000"` -> `"0"`).

## Stateful Suppression (Tier 3)

Optional anti-flap suppression can downgrade recent repeated invariant violations to `ALLOW` when:
- `state_suppression_window_ms > 0`
- a non-violating last-seen version exists for the same subject key
- and it is within the configured suppression window

Subject key resolution:
- first: `state_subject_header_name` (if configured and present)
- fallback: `route/service/method/path` composite key

State store options:
- shared dict (`state_store_dict_name`, default `version_gate_state`)
- optional adapter module (`state_store_adapter_module`)

## Config (Common)

```yaml
config:
  enabled: true
  mode: shadow
  log_only: true # deprecated compatibility field

  # extraction strategies
  expected_source_strategy: header
  actual_source_strategy: header
  expected_header_name: x-expected-version
  actual_header_name: x-actual-version
  expected_query_param_name: expected_version
  actual_query_param_name: actual_version
  expected_jwt_claim_name: expected_version
  actual_jwt_claim_name: actual_version
  expected_cookie_name: expected_version
  actual_cookie_name: actual_version

  # telemetry
  emit_sample_rate: 1.0
  emit_include_versions: true
  emit_format: logfmt

  # enforcement
  reject_status_code: 409
  reject_body_template: default # default|minimal

  # optional tier-3 state
  state_suppression_window_ms: 0
  state_subject_header_name: x-subject-id
  state_store_dict_name: version_gate_state
  state_store_ttl_sec: 30
  # state_store_adapter_module: my.custom.state_store_adapter
```

## Example (Declarative Config)

```yaml
_format_version: "3.0"

services:
  - name: example
    url: http://httpbin.org
    routes:
      - name: example-route
        paths:
          - /example
        plugins:
          - name: version-gate
            config:
              enabled: true
              mode: shadow
              log_only: true # deprecated compatibility field
              expected_source_strategy: header
              actual_source_strategy: header
              expected_header_name: x-expected-version
              actual_header_name: x-actual-version
              emit_sample_rate: 1.0
              emit_format: logfmt
              state_suppression_window_ms: 250
              state_store_dict_name: version_gate_state
```

## Install

1. Build/install the rock:
   `luarocks make version-gate-0.1.0-1.rockspec`
2. If using shared-dict state store, define an Nginx shared dict (for example `lua_shared_dict version_gate_state 10m;`).
3. Enable plugin:
   set `KONG_PLUGINS=bundled,version-gate`
4. Restart Kong.
