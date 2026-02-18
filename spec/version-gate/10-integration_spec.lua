local helpers = require "spec.helpers"

local PLUGIN_NAME = "version-gate"

for _, strategy in helpers.all_strategies() do if strategy ~= "cassandra" then

  describe(PLUGIN_NAME .. ": (integration) [#" .. strategy .. "]", function()
    local client

    local function build_config(overrides)
      local conf = {
        enabled = true,
        mode = "shadow",
        log_only = true,
        policy_id = "default",
        enforce_on_reason = { "INVARIANT_VIOLATION" },
        expected_header_name = "x-expected-version",
        actual_header_name = "x-actual-version",
        expected_source_strategy = "header",
        actual_source_strategy = "header",
        expected_query_param_name = "expected_version",
        actual_query_param_name = "actual_version",
        expected_jwt_claim_name = "expected_version",
        actual_jwt_claim_name = "actual_version",
        expected_cookie_name = "expected_version",
        actual_cookie_name = "actual_version",
        emit_sample_rate = 1.0,
        state_suppression_window_ms = 0,
        state_store_ttl_sec = 30,
        reject_status_code = 409,
        emit_include_versions = true,
        emit_format = "logfmt",
      }

      if overrides ~= nil then
        for k, v in pairs(overrides) do
          conf[k] = v
        end
      end

      return conf
    end

    lazy_setup(function()
      local bp = helpers.get_db_utils(strategy == "off" and "postgres" or strategy, nil, { PLUGIN_NAME })
      local default_service = bp.services:insert({
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = "http",
      })

      -- Route: shadow mode (default)
      local route_shadow = bp.routes:insert({
        hosts = { "shadow.test" },
        service = { id = default_service.id },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route_shadow.id },
        config = build_config({
          mode = "shadow",
        }),
      }

      -- Route: annotate mode
      local route_annotate = bp.routes:insert({
        hosts = { "annotate.test" },
        service = { id = default_service.id },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route_annotate.id },
        config = build_config({
          mode = "annotate",
        }),
      }

      -- Route: reject mode
      local route_reject = bp.routes:insert({
        hosts = { "reject.test" },
        service = { id = default_service.id },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route_reject.id },
        config = build_config({
          mode = "reject",
          reject_status_code = 409,
        }),
      }

      -- Route: reject mode with minimal body template
      local route_reject_minimal = bp.routes:insert({
        hosts = { "reject-minimal.test" },
        service = { id = default_service.id },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route_reject_minimal.id },
        config = build_config({
          mode = "reject",
          reject_status_code = 409,
          reject_body_template = "minimal",
        }),
      }

      -- Route: plugin disabled
      local route_disabled = bp.routes:insert({
        hosts = { "disabled.test" },
        service = { id = default_service.id },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route_disabled.id },
        config = build_config({
          enabled = false,
        }),
      }

      -- Route: with explicit service (tests kong.client.get_service)
      local service_explicit = bp.services:insert({
        host = helpers.mock_upstream_host,
        port = helpers.mock_upstream_port,
        protocol = "http",
      })
      local route_service = bp.routes:insert({
        hosts = { "service-resolve.test" },
        service = { id = service_explicit.id },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route_service.id },
        config = build_config({
          mode = "annotate",
        }),
      }

      -- Route: query-based extraction (non-header strategy e2e)
      local route_query_strategy = bp.routes:insert({
        hosts = { "query-strategy.test" },
        service = { id = default_service.id },
      })
      bp.plugins:insert {
        name = PLUGIN_NAME,
        route = { id = route_query_strategy.id },
        config = build_config({
          mode = "annotate",
          expected_source_strategy = "query",
          actual_source_strategy = "query",
        }),
      }

      assert(helpers.start_kong({
        database = strategy,
        nginx_conf = "spec/fixtures/custom_nginx.template",
        plugins = "bundled," .. PLUGIN_NAME,
        declarative_config = strategy == "off" and helpers.make_yaml_file() or nil,
      }))
    end)

    lazy_teardown(function()
      helpers.stop_kong(nil, true)
    end)

    before_each(function()
      client = helpers.proxy_client()
    end)

    after_each(function()
      if client then client:close() end
    end)

    -- ----------------------------------------------------------------
    -- Shadow mode
    -- ----------------------------------------------------------------
    describe("shadow mode", function()
      it("passes traffic without mutation when no version headers present", function()
        local r = client:get("/request", {
          headers = {
            host = "shadow.test",
          },
        })
        assert.response(r).has.status(200)
        assert.response(r).has.no.header("x-version-gate-decision")
        assert.response(r).has.no.header("x-version-gate-reason")
        assert.response(r).has.no.header("x-version-gate-mode")
      end)

      it("passes traffic without mutation on violation", function()
        -- Use /response-headers to make the mock upstream return
        -- x-actual-version as a real response header.
        local r = client:get("/response-headers", {
          headers = {
            host = "shadow.test",
            ["x-expected-version"] = "10",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        -- shadow mode: traffic flows, no annotation or rejection
        assert.response(r).has.status(200)
        assert.response(r).has.no.header("x-version-gate-decision")
        assert.response(r).has.no.header("x-version-gate-reason")
        assert.response(r).has.no.header("x-version-gate-mode")
      end)

      it("passes traffic without mutation when versions match", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "shadow.test",
            ["x-expected-version"] = "5",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        assert.response(r).has.status(200)
        assert.response(r).has.no.header("x-version-gate-decision")
      end)
    end)

    -- ----------------------------------------------------------------
    -- Annotate mode
    -- ----------------------------------------------------------------
    describe("annotate mode", function()
      it("adds decision headers on violation", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "annotate.test",
            ["x-expected-version"] = "10",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        assert.response(r).has.status(200)
        local decision = assert.response(r).has.header("x-version-gate-decision")
        local reason = assert.response(r).has.header("x-version-gate-reason")
        local mode = assert.response(r).has.header("x-version-gate-mode")
        assert.equal("VIOLATION", decision)
        assert.equal("INVARIANT_VIOLATION", reason)
        assert.equal("annotate", mode)
      end)

      it("does not add decision headers when versions match", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "annotate.test",
            ["x-expected-version"] = "5",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        assert.response(r).has.status(200)
        assert.response(r).has.no.header("x-version-gate-decision")
        assert.response(r).has.no.header("x-version-gate-reason")
      end)

      it("does not add decision headers when expected is missing (fail-open)", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "annotate.test",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        assert.response(r).has.status(200)
        assert.response(r).has.no.header("x-version-gate-decision")
      end)

      it("does not add decision headers when actual > expected", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "annotate.test",
            ["x-expected-version"] = "5",
          },
          query = {
            ["x-actual-version"] = "10",
          },
        })
        assert.response(r).has.status(200)
        assert.response(r).has.no.header("x-version-gate-decision")
      end)
    end)

    -- ----------------------------------------------------------------
    -- Reject mode
    -- ----------------------------------------------------------------
    describe("reject mode", function()
      it("returns 409 with default body on violation", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "reject.test",
            ["x-expected-version"] = "10",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        assert.response(r).has.status(409)
        local body = assert.response(r).has.jsonbody()
        assert.equal("version gate violation", body.message)
        assert.equal("VIOLATION", body.decision)
        assert.equal("INVARIANT_VIOLATION", body.reason)
        local decision = assert.response(r).has.header("x-version-gate-decision")
        assert.equal("VIOLATION", decision)
      end)

      it("returns 409 with minimal body template on violation", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "reject-minimal.test",
            ["x-expected-version"] = "10",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        assert.response(r).has.status(409)
        local body = assert.response(r).has.jsonbody()
        assert.equal("version gate violation", body.error)
        assert.equal("INVARIANT_VIOLATION", body.reason)
        assert.is_nil(body.message)
        assert.is_nil(body.decision)
      end)

      it("passes traffic when versions match", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "reject.test",
            ["x-expected-version"] = "5",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        assert.response(r).has.status(200)
        assert.response(r).has.no.header("x-version-gate-decision")
      end)

      it("passes traffic when actual > expected", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "reject.test",
            ["x-expected-version"] = "5",
          },
          query = {
            ["x-actual-version"] = "10",
          },
        })
        assert.response(r).has.status(200)
      end)
    end)

    -- ----------------------------------------------------------------
    -- Fail-open behavior
    -- ----------------------------------------------------------------
    describe("fail-open", function()
      it("allows when expected version header is absent", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "reject.test",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        assert.response(r).has.status(200)
      end)

      it("allows when actual version header is absent from upstream", function()
        local r = client:get("/request", {
          headers = {
            host = "reject.test",
            ["x-expected-version"] = "5",
          },
        })
        -- MISSING_ACTUAL -> ALLOW; default enforce_on_reason only
        -- includes INVARIANT_VIOLATION so no rejection
        assert.response(r).has.status(200)
      end)

      it("allows when both version headers are absent", function()
        local r = client:get("/request", {
          headers = {
            host = "reject.test",
          },
        })
        assert.response(r).has.status(200)
      end)

      it("allows when expected version is non-numeric (parse error)", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "reject.test",
            ["x-expected-version"] = "abc",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        -- PARSE_ERROR_EXPECTED -> ALLOW
        assert.response(r).has.status(200)
      end)

      it("allows when actual version is non-numeric (parse error)", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "reject.test",
            ["x-expected-version"] = "5",
          },
          query = {
            ["x-actual-version"] = "abc",
          },
        })
        -- PARSE_ERROR_ACTUAL -> ALLOW
        assert.response(r).has.status(200)
      end)
    end)

    -- ----------------------------------------------------------------
    -- Version comparison
    -- ----------------------------------------------------------------
    describe("version comparison", function()
      it("allows when actual equals expected", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "reject.test",
            ["x-expected-version"] = "5",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        assert.response(r).has.status(200)
      end)

      it("allows when actual > expected (same length)", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "reject.test",
            ["x-expected-version"] = "5",
          },
          query = {
            ["x-actual-version"] = "9",
          },
        })
        assert.response(r).has.status(200)
      end)

      it("allows when actual > expected (longer string)", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "reject.test",
            ["x-expected-version"] = "5",
          },
          query = {
            ["x-actual-version"] = "10",
          },
        })
        assert.response(r).has.status(200)
      end)

      it("rejects when actual < expected", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "reject.test",
            ["x-expected-version"] = "10",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        assert.response(r).has.status(409)
      end)

      it("handles leading zeros correctly", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "reject.test",
            ["x-expected-version"] = "005",
          },
          query = {
            ["x-actual-version"] = "005",
          },
        })
        -- Both normalize to "5", should be equal -> ALLOW
        assert.response(r).has.status(200)
      end)
    end)

    -- ----------------------------------------------------------------
    -- Disabled plugin
    -- ----------------------------------------------------------------
    describe("disabled plugin", function()
      it("passes traffic without any version-gate behavior", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "disabled.test",
            ["x-expected-version"] = "100",
          },
          query = {
            ["x-actual-version"] = "1",
          },
        })
        assert.response(r).has.status(200)
        assert.response(r).has.no.header("x-version-gate-decision")
      end)
    end)

    -- ----------------------------------------------------------------
    -- Service resolution (kong.client.get_service)
    -- ----------------------------------------------------------------
    describe("service resolution", function()
      it("works with explicit service via kong.client.get_service()", function()
        local r = client:get("/response-headers", {
          headers = {
            host = "service-resolve.test",
            ["x-expected-version"] = "10",
          },
          query = {
            ["x-actual-version"] = "5",
          },
        })
        -- If kong.client.get_service() was broken, Kong would return 500
        assert.response(r).has.not_status(500)
        -- annotate mode: should have annotation headers on violation
        local decision = assert.response(r).has.header("x-version-gate-decision")
        assert.equal("VIOLATION", decision)
      end)
    end)

    -- ----------------------------------------------------------------
    -- Non-header strategy e2e
    -- ----------------------------------------------------------------
    describe("query source strategy", function()
      it("evaluates versions end-to-end from query params across phases", function()
        local r = client:get("/request", {
          headers = {
            host = "query-strategy.test",
          },
          query = {
            expected_version = "10",
            actual_version = "5",
          },
        })
        assert.response(r).has.status(200)
        local decision = assert.response(r).has.header("x-version-gate-decision")
        local reason = assert.response(r).has.header("x-version-gate-reason")
        local mode = assert.response(r).has.header("x-version-gate-mode")
        assert.equal("VIOLATION", decision)
        assert.equal("INVARIANT_VIOLATION", reason)
        assert.equal("annotate", mode)
      end)
    end)

  end)

end end
