# Version Gate Kong Plugin

Kong plugin that detects monotonic-read violations by comparing:
- `expected` version from request header
- `actual` version from upstream response header

Current mode is fail-open and log-only.

## Behavior

- Decision = `VIOLATION` when `actual_version < expected_version`
- Decision = `ALLOW` for all other cases, including missing/invalid headers
- No request or response blocking/mutation in this PoC

## Config

```yaml
config:
  enabled: true
  mode: shadow
  log_only: true # deprecated compatibility field
  expected_header_name: x-expected-version
  actual_header_name: x-actual-version
```

## Example (declarative config)

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
              expected_header_name: x-expected-version
              actual_header_name: x-actual-version
```

## Install

1. Build/install the rock:
   `luarocks make version-gate-0.1.0-1.rockspec`
2. Enable plugin:
   set `KONG_PLUGINS=bundled,version-gate`
3. Restart Kong.
