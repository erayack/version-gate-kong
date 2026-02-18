local helpers = require "spec.helpers"
local redis_helper = require "spec.helpers.redis_helper"

local PLUGIN_NAME = "version-gate"

for _, strategy in helpers.all_strategies() do
  if strategy ~= "cassandra" then
    describe(PLUGIN_NAME .. ": (integration redis) [#" .. strategy .. "]", function()
      local client
      local redis_client
      local route_id
      local service_id

      local function build_config(overrides)
        local conf = {
          enabled = true,
          mode = "reject",
          log_only = false,
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
          state_suppression_window_ms = 60000,
          state_subject_header_name = "x-subject-id",
          state_store_ttl_sec = 30,
          state_store_dict_name = "missing_dict",
          state_store_adapter_module = "kong.plugins.version-gate.state_store_redis",
          state_store_redis_host = helpers.redis_host,
          state_store_redis_port = helpers.redis_port,
          state_store_redis_prefix = "version-gate:state",
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
        local svc = bp.services:insert({
          host = helpers.mock_upstream_host,
          port = helpers.mock_upstream_port,
          protocol = "http",
        })
        service_id = svc.id

        local redis_route = bp.routes:insert({
          hosts = { "redis-adapter.test" },
          service = { id = svc.id },
        })
        route_id = redis_route.id

        bp.plugins:insert({
          name = PLUGIN_NAME,
          route = { id = redis_route.id },
          config = build_config(),
        })

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
        redis_client = assert(redis_helper.connect(helpers.redis_host, helpers.redis_port))
        assert(redis_client:flushall())
      end)

      after_each(function()
        if client then
          client:close()
        end
        if redis_client then
          redis_client:close()
        end
      end)

      it("uses Redis adapter through lifecycle and reads seeded state via HMGET", function()
        local adapter = require("kong.plugins.version-gate.state_store_redis")
        local subject = "tenant-redis-1"
        local now_ts_ms = tostring(os.time() * 1000)
        local subject_state_key = "version-gate:state:subject:" .. subject
        local composite_subject_key = table.concat({
          "route:" .. tostring(route_id),
          "service:" .. tostring(service_id),
          "method:GET",
          "path:/response-headers",
        }, "|")
        local composite_state_key = "version-gate:state:" .. composite_subject_key

        assert(redis_client:hset(subject_state_key, "version", "10"))
        assert(redis_client:hset(subject_state_key, "ts_ms", now_ts_ms))
        assert(redis_client:expire(subject_state_key, 30))
        assert(redis_client:hset(composite_state_key, "version", "10"))
        assert(redis_client:hset(composite_state_key, "ts_ms", now_ts_ms))
        assert(redis_client:expire(composite_state_key, 30))

        local seeded_version, seeded_ts_ms = adapter.get_last_seen("subject:" .. subject, build_config())
        assert.equals("10", seeded_version)
        assert.equals(tonumber(now_ts_ms), seeded_ts_ms)

        local r = client:get("/response-headers", {
          headers = {
            host = "redis-adapter.test",
            ["x-subject-id"] = subject,
            ["x-expected-version"] = "7",
          },
          query = {
            ["x-actual-version"] = "8",
          },
        })

        assert.response(r).has.status(200)
        assert.response(r).has.no.header("x-version-gate-decision")

      end)
    end)
  end
end
