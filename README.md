# Version Gate Kong Plugin

Kong plugin that detects monotonic-read violations by comparing an `expected` version (request-side) with an `actual` version (response-side).

## Kong Compatibility

- Supported by package constraint: `kong >= 3.4, < 4.0`
- Verified in this repo integration tests: `3.8.0`
- Optional local validation example: `KONG_VERSION=3.9.1 pongo run`

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

1. Install from LuaRocks (recommended):
   `luarocks install kong-plugin-version-gate 0.1.0-2`
2. Optional (build from local source instead):
   `luarocks make kong-plugin-version-gate-0.1.0-2.rockspec`
3. If using shared-dict state store, define an Nginx shared dict (for example `lua_shared_dict version_gate_state 10m;`).
4. Enable plugin:
   set `KONG_PLUGINS=bundled,version-gate`
5. Restart Kong.

## Custom Kong Image (Recommended For Teams)

Use `examples/Dockerfile` to bake the plugin into a deployable Kong image.

Build:

```bash
docker build -f examples/Dockerfile -t kong-version-gate:3.8.0 .
```

Run (DB-less example):

```bash
docker run --rm -p 8000:8000 -p 8001:8001 \
  -e KONG_DATABASE=off \
  -e KONG_DECLARATIVE_CONFIG=/kong/declarative/kong.yaml \
  -e KONG_PROXY_LISTEN=0.0.0.0:8000 \
  -e KONG_ADMIN_LISTEN=0.0.0.0:8001 \
  -v "$(pwd)/examples/kong-declarative-version-gate.yaml:/kong/declarative/kong.yaml:ro" \
  kong-version-gate:3.8.0
```

Verify plugin is enabled:

```bash
curl -sS http://localhost:8001/plugins/enabled | grep -i version-gate
```

## Registration Readiness Checklist

- Rockspec dependency range and plugin modules are correct (`kong-plugin-version-gate-0.1.0-1.rockspec`).
- Plugin name is aligned everywhere: `version-gate` (`schema.name`, config, and `KONG_PLUGINS`).
- Integration tests pass against pinned Kong:  
  `KONG_VERSION=3.8.0 /Users/erayack/.kong-pongo/pongo.sh run -- -v -o gtest ./spec/version-gate/10-integration_spec.lua`
- At least one non-header extraction path is covered end-to-end (query strategy integration test included).

## Register in Kong

1. Ensure the plugin is enabled in Kong: `KONG_PLUGINS=bundled,version-gate`.
2. Restart Kong and confirm startup is clean.
3. Register via one of the methods below.
4. Send a request that should violate (`actual < expected`) and verify expected behavior for your mode (`shadow`, `annotate`, or `reject`).

### Method A: Declarative (DB-less or decK)

Use `examples/kong-declarative-version-gate.yaml`.

If Kong runs in DB-less mode, point `KONG_DECLARATIVE_CONFIG` to that file.

If using decK:

```bash
deck gateway sync examples/kong-declarative-version-gate.yaml
```

### Method B: Admin API

Create Service and Route:

```bash
curl -sS -X POST http://localhost:8001/services \
  --data name=version-gate-demo-service \
  --data url=http://httpbin.org

curl -sS -X POST http://localhost:8001/services/version-gate-demo-service/routes \
  --data name=version-gate-demo-route \
  --data paths[]=/version-gate-demo
```

Attach plugin to the Route:

```bash
curl -sS -X POST http://localhost:8001/routes/version-gate-demo-route/plugins \
  --data name=version-gate \
  --data config.enabled=true \
  --data config.mode=annotate \
  --data config.expected_source_strategy=header \
  --data config.actual_source_strategy=header \
  --data config.expected_header_name=x-expected-version \
  --data config.actual_header_name=x-actual-version \
  --data config.reject_status_code=409
```

Quick verification (annotate mode should return decision headers):

```bash
curl -i "http://localhost:8000/version-gate-demo/response-headers?x-actual-version=5" \
  -H "x-expected-version: 10"
```

## Testing (Pongo)

Pin Kong to a known compatible version (`3.8.0`) when running Pongo:

```bash
KONG_VERSION=3.8.0 pongo up
KONG_VERSION=3.8.0 pongo run
```

Override the pin when needed:

```bash
KONG_VERSION=3.9.1 pongo run
```
