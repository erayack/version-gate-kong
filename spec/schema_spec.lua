package.loaded["kong.db.schema.typedefs"] = {
  no_consumer = {},
  protocols_http = {},
}

local schema = require("kong.plugins.version-gate.schema")

local function config_fields()
  for _, root_field in ipairs(schema.fields) do
    if root_field.config then
      return root_field.config.fields
    end
  end

  error("schema config fields not found")
end

local function field_name(field)
  return next(field)
end

local function contains(list, value)
  for i = 1, #(list or {}) do
    if list[i] == value then
      return true
    end
  end

  return false
end

-- Plain busted unit tests do not boot Kong's schema validator, so this helper
-- exercises the schema contract that matters to this plugin while keeping the
-- tests independent of Kong internals.
local validate_record

local function validate_value(name, rule, value)
  if value == nil then
    if rule.required then
      return nil, name .. " is required"
    end
    return true
  end

  if rule.type == "string" and type(value) ~= "string" then
    return nil, name .. " must be a string"
  end
  if rule.type == "boolean" and type(value) ~= "boolean" then
    return nil, name .. " must be a boolean"
  end
  if rule.type == "number" and type(value) ~= "number" then
    return nil, name .. " must be a number"
  end
  if rule.type == "integer" and (type(value) ~= "number" or value % 1 ~= 0) then
    return nil, name .. " must be an integer"
  end
  if rule.type == "array" and type(value) ~= "table" then
    return nil, name .. " must be an array"
  end
  if rule.type == "record" and type(value) ~= "table" then
    return nil, name .. " must be a record"
  end

  if rule.one_of and not contains(rule.one_of, value) then
    return nil, name .. " must be one of the allowed values"
  end

  if rule.between and (value < rule.between[1] or value > rule.between[2]) then
    return nil, name .. " must be between " .. rule.between[1] .. " and " .. rule.between[2]
  end

  if rule.custom_validator then
    local ok, err = rule.custom_validator(value)
    if not ok then
      return nil, name .. " " .. tostring(err)
    end
  end

  if rule.type == "array" and rule.elements then
    for i = 1, #value do
      local element_rule = rule.elements
      local ok, err
      if element_rule.fields then
        ok, err = validate_record(name .. "[" .. i .. "]", element_rule.fields, value[i])
      else
        ok, err = validate_value(name .. "[" .. i .. "]", element_rule, value[i])
      end

      if not ok then
        return nil, err
      end
    end
  end

  return true
end

function validate_record(prefix, fields, record)
  if type(record) ~= "table" then
    return nil, prefix .. " must be a record"
  end

  for _, field in ipairs(fields) do
    local name = field_name(field)
    local rule = field[name]
    local value = record[name]
    if value == nil and rule.default ~= nil then
      value = rule.default
    end

    local ok, err = validate_value(prefix .. "." .. name, rule, value)
    if not ok then
      return nil, err
    end
  end

  return true
end

local function validate_config(config)
  local ok, err = validate_record("config", config_fields(), config or {})
  if not ok then
    return nil, err
  end

  for _, check in ipairs(schema.entity_checks or {}) do
    local entity_check = check.custom_entity_check
    if entity_check and entity_check.fn then
      ok, err = entity_check.fn({ config = config or {} })
      if not ok then
        return nil, err
      end
    end
  end

  return true
end

local function valid_config(overrides)
  local config = {
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
    emit_sample_rate = 1,
    state_suppression_window_ms = 0,
    state_store_ttl_sec = 30,
    state_store_redis_port = 6379,
    state_store_redis_database = 0,
    state_store_redis_timeout_ms = 100,
    state_store_redis_keepalive_ms = 60000,
    state_store_redis_pool_size = 100,
    state_store_redis_prefix = "version-gate:state",
    reject_status_code = 409,
    emit_include_versions = true,
    emit_format = "logfmt",
  }

  for k, v in pairs(overrides or {}) do
    config[k] = v
  end

  return config
end

describe("schema", function()
  it("accepts supported source strategies with their configured names", function()
    for _, strategy in ipairs({ "header", "query", "jwt_claim", "cookie" }) do
      local ok, err = validate_config(valid_config({
        expected_source_strategy = strategy,
        actual_source_strategy = strategy,
      }))

      assert.is_true(ok, err)
    end
  end)

  it("rejects unsupported source strategies and blank active source names", function()
    local ok, err = validate_config(valid_config({ expected_source_strategy = "body" }))
    assert.is_nil(ok)
    assert.matches("expected_source_strategy", err)

    ok, err = validate_config(valid_config({
      expected_source_strategy = "query",
      expected_query_param_name = "  ",
    }))
    assert.is_nil(ok)
    assert.matches("expected_query_param_name must be a non%-empty name", err)
  end)

  it("validates telemetry bounds and formats", function()
    assert.is_true(validate_config(valid_config({ emit_sample_rate = 0, emit_format = "json", emit_include_versions = false })))
    assert.is_true(validate_config(valid_config({ emit_sample_rate = 1, emit_format = "logfmt" })))

    local ok, err = validate_config(valid_config({ emit_sample_rate = 1.1 }))
    assert.is_nil(ok)
    assert.matches("emit_sample_rate", err)

    ok, err = validate_config(valid_config({ emit_format = "xml" }))
    assert.is_nil(ok)
    assert.matches("emit_format", err)
  end)

  it("validates scalar array elements", function()
    local ok, err = validate_config(valid_config({ enforce_on_reason = { 123 } }))
    assert.is_nil(ok)
    assert.matches("enforce_on_reason", err)

    ok, err = validate_config(valid_config({
      policy_overrides = {
        {
          target_type = "route",
          target_id = "123e4567-e89b-12d3-a456-426614174000",
          enforce_on_reason = { 123 },
        },
      },
    }))
    assert.is_nil(ok)
    assert.matches("enforce_on_reason", err)
  end)

  it("validates state suppression and state-store config", function()
    assert.is_true(validate_config(valid_config({
      state_suppression_window_ms = 3600000,
      state_subject_header_name = "x-subject",
      state_store_dict_name = "version_gate_state",
      state_store_ttl_sec = 86400,
      state_store_adapter_module = "my.adapter",
    })))

    local ok, err = validate_config(valid_config({ state_suppression_window_ms = -1 }))
    assert.is_nil(ok)
    assert.matches("state_suppression_window_ms", err)

    ok, err = validate_config(valid_config({ state_subject_header_name = "" }))
    assert.is_nil(ok)
    assert.matches("state_subject_header_name", err)

    ok, err = validate_config(valid_config({ state_store_ttl_sec = 0 }))
    assert.is_nil(ok)
    assert.matches("state_store_ttl_sec", err)
  end)

  it("validates reject behavior configuration", function()
    assert.is_true(validate_config(valid_config({ reject_status_code = 599, reject_body_template = "minimal" })))

    local ok, err = validate_config(valid_config({ reject_status_code = 99 }))
    assert.is_nil(ok)
    assert.matches("reject_status_code", err)

    ok, err = validate_config(valid_config({ reject_body_template = "verbose" }))
    assert.is_nil(ok)
    assert.matches("reject_body_template", err)
  end)

  it("validates policy fields and route/service overrides", function()
    assert.is_true(validate_config(valid_config({
      policy_id = "default",
      enforce_on_reason = { "INVARIANT_VIOLATION" },
      policy_overrides = {
        {
          target_type = "route",
          target_id = "123e4567-e89b-12d3-a456-426614174000",
          mode = "reject",
          reject_status_code = 409,
          reject_body_template = "default",
          emit_sample_rate = 0.5,
          emit_include_versions = false,
          emit_format = "json",
        },
      },
    })))

    local ok, err = validate_config(valid_config({
      policy_overrides = {
        { target_type = "consumer", target_id = "123e4567-e89b-12d3-a456-426614174000" },
      },
    }))
    assert.is_nil(ok)
    assert.matches("target_type", err)

    ok, err = validate_config(valid_config({
      policy_overrides = {
        { target_type = "service", target_id = "not-a-uuid" },
      },
    }))
    assert.is_nil(ok)
    assert.matches("valid UUID", err)
  end)
end)
