local typedefs = require("kong.db.schema.typedefs")
local constants = require("kong.plugins.version-gate.constants")

local SOURCE_STRATEGIES = { "header", "query", "jwt_claim", "cookie" }

local function validate_non_empty_name(value)
  if type(value) ~= "string" or value:match("^%s*$") then
    return nil, "must be a non-empty name"
  end

  return true
end

local function validate_uuid(value)
  if type(value) ~= "string" then
    return nil, "must be a UUID string"
  end

  if not value:match("^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
    return nil, "must be a valid UUID"
  end

  return true
end

local STRATEGY_TO_FIELD = {
  header = { expected = "expected_header_name", actual = "actual_header_name" },
  query = { expected = "expected_query_param_name", actual = "actual_query_param_name" },
  jwt_claim = { expected = "expected_jwt_claim_name", actual = "actual_jwt_claim_name" },
  cookie = { expected = "expected_cookie_name", actual = "actual_cookie_name" },
}

local function validate_strategy_name(conf, strategy_key, side)
  local strategy = conf[strategy_key]
  local strategy_fields = STRATEGY_TO_FIELD[strategy]
  if strategy_fields == nil then
    return true
  end

  local field_name = strategy_fields[side]
  local configured_name = conf[field_name]
  if type(configured_name) ~= "string" or configured_name:match("^%s*$") then
    return nil, field_name .. " must be a non-empty name when " .. strategy_key .. "=" .. strategy
  end

  return true
end

local function validate_strategy_bindings(conf)
  local ok, err = validate_strategy_name(conf, "expected_source_strategy", "expected")
  if not ok then
    return nil, err
  end

  ok, err = validate_strategy_name(conf, "actual_source_strategy", "actual")
  if not ok then
    return nil, err
  end

  return true
end

return {
  name = "version-gate",
  fields = {
    { consumer = typedefs.no_consumer },
    { protocols = typedefs.protocols_http },
    { config = {
      type = "record",
      fields = {
        { enabled = { type = "boolean", required = true, default = true } },
        { mode = {
          type = "string",
          required = true,
          default = "shadow",
          one_of = { "shadow", "annotate", "reject" },
        } },
        { log_only = {
          type = "boolean",
          required = true,
          default = true,
          description = "Deprecated compatibility field; use config.mode",
        } },
        { policy_id = {
          type = "string",
          required = true,
          default = "default",
        } },
        { enforce_on_reason = {
          type = "array",
          required = true,
          default = { constants.REASON_INVARIANT_VIOLATION },
          elements = { type = "string" },
        } },
        { policy_overrides = {
          type = "array",
          required = false,
          elements = {
            type = "record",
            fields = {
              { target_type = { type = "string", required = true, one_of = { "route", "service" } } },
              { target_id = { type = "string", required = true, custom_validator = validate_uuid } },
              { id = { type = "string", required = false } },
              { mode = { type = "string", required = false, one_of = { "shadow", "annotate", "reject" } } },
              { reject_status_code = { type = "integer", required = false, between = { 100, 599 } } },
              { reject_body_template = { type = "string", required = false, one_of = { "default", "minimal" } } },
              { emit_sample_rate = { type = "number", required = false, between = { 0, 1 } } },
              { enforce_on_reason = { type = "array", required = false, elements = { type = "string" } } },
            },
          },
        } },
        { expected_header_name = {
          type = "string",
          required = true,
          default = "x-expected-version",
          custom_validator = validate_non_empty_name,
        } },
        { actual_header_name = {
          type = "string",
          required = true,
          default = "x-actual-version",
          custom_validator = validate_non_empty_name,
        } },
        { expected_source_strategy = {
          type = "string",
          required = true,
          default = "header",
          one_of = SOURCE_STRATEGIES,
        } },
        { actual_source_strategy = {
          type = "string",
          required = true,
          default = "header",
          one_of = SOURCE_STRATEGIES,
        } },
        { expected_query_param_name = {
          type = "string",
          required = true,
          default = "expected_version",
          custom_validator = validate_non_empty_name,
        } },
        { actual_query_param_name = {
          type = "string",
          required = true,
          default = "actual_version",
          custom_validator = validate_non_empty_name,
        } },
        { expected_jwt_claim_name = {
          type = "string",
          required = true,
          default = "expected_version",
          custom_validator = validate_non_empty_name,
        } },
        { actual_jwt_claim_name = {
          type = "string",
          required = true,
          default = "actual_version",
          custom_validator = validate_non_empty_name,
        } },
        { expected_cookie_name = {
          type = "string",
          required = true,
          default = "expected_version",
          custom_validator = validate_non_empty_name,
        } },
        { actual_cookie_name = {
          type = "string",
          required = true,
          default = "actual_version",
          custom_validator = validate_non_empty_name,
        } },
        { emit_sample_rate = {
          type = "number",
          required = true,
          default = 1,
          between = { 0, 1 },
        } },
        { state_suppression_window_ms = {
          type = "integer",
          required = true,
          default = 0,
          between = { 0, 3600000 },
        } },
        { state_subject_header_name = {
          type = "string",
          required = false,
          custom_validator = validate_non_empty_name,
        } },
        { state_store_dict_name = {
          type = "string",
          required = false,
          custom_validator = validate_non_empty_name,
        } },
        { state_store_ttl_sec = {
          type = "integer",
          required = true,
          default = 30,
          between = { 1, 86400 },
        } },
        { state_store_adapter_module = {
          type = "string",
          required = false,
          custom_validator = validate_non_empty_name,
        } },
        { state_store_redis_host = {
          type = "string",
          required = false,
          custom_validator = validate_non_empty_name,
        } },
        { state_store_redis_port = {
          type = "integer",
          required = true,
          default = 6379,
          between = { 1, 65535 },
        } },
        { state_store_redis_password = {
          type = "string",
          required = false,
        } },
        { state_store_redis_database = {
          type = "integer",
          required = true,
          default = 0,
          between = { 0, 1024 },
        } },
        { state_store_redis_timeout_ms = {
          type = "integer",
          required = true,
          default = 100,
          between = { 1, 60000 },
        } },
        { state_store_redis_keepalive_ms = {
          type = "integer",
          required = true,
          default = 60000,
          between = { 1, 3600000 },
        } },
        { state_store_redis_pool_size = {
          type = "integer",
          required = true,
          default = 100,
          between = { 1, 10000 },
        } },
        { state_store_redis_prefix = {
          type = "string",
          required = true,
          default = "version-gate:state",
          custom_validator = validate_non_empty_name,
        } },
        { reject_status_code = {
          type = "integer",
          required = true,
          default = 409,
          between = { 100, 599 },
        } },
        { reject_body_template = {
          type = "string",
          required = false,
          one_of = { "default", "minimal" },
        } },
        { emit_include_versions = {
          type = "boolean",
          required = true,
          default = true,
        } },
        { emit_format = {
          type = "string",
          required = true,
          default = "logfmt",
          one_of = { "logfmt", "json" },
        } },
      },
    } },
  },
  entity_checks = {
    {
      custom_entity_check = {
        field_sources = {
          "config.expected_source_strategy",
          "config.actual_source_strategy",
          "config.expected_header_name",
          "config.actual_header_name",
          "config.expected_query_param_name",
          "config.actual_query_param_name",
          "config.expected_jwt_claim_name",
          "config.actual_jwt_claim_name",
          "config.expected_cookie_name",
          "config.actual_cookie_name",
        },
        fn = function(entity)
          return validate_strategy_bindings(entity.config or {})
        end,
      },
    },
  },
}
