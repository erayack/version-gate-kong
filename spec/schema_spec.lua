package.loaded["kong.db.schema.typedefs"] = {
  no_consumer = {},
  protocols_http = {},
}

local constants = require("kong.plugins.version-gate.constants")
local schema = require("kong.plugins.version-gate.schema")

local function config_field(name)
  for _, root_field in ipairs(schema.fields) do
    if root_field.config then
      for _, field in ipairs(root_field.config.fields) do
        if field[name] then
          return field[name]
        end
      end
    end
  end

  return nil
end

local function override_value_fields()
  local field = config_field("policy_overrides")
  if not field or not field.elements or not field.elements.fields then
    return nil
  end

  local indexed = {}
  for _, value_field in ipairs(field.elements.fields) do
    local key = next(value_field)
    if key ~= nil then
      indexed[key] = value_field[key]
    end
  end

  return indexed
end

local function has_value(list, needle)
  for i = 1, #list do
    if list[i] == needle then
      return true
    end
  end

  return false
end

local function assert_same_members(list, expected_a, expected_b)
  assert.equals(2, #list)
  assert.is_true(has_value(list, expected_a))
  assert.is_true(has_value(list, expected_b))
end

describe("schema", function()
  it("does not enforce deprecated log_only/mode cross-check", function()
    assert.is_nil(schema.entity_checks)
  end)

  it("defines telemetry bounds and format enum", function()
    local emit_sample_rate = config_field("emit_sample_rate")
    local emit_format = config_field("emit_format")
    local emit_include_versions = config_field("emit_include_versions")

    assert.same({ 0, 1 }, emit_sample_rate.between)
    assert.same({ "logfmt", "json" }, emit_format.one_of)
    assert.equals(true, emit_include_versions.default)
  end)

  it("defines reject configuration fields", function()
    local reject_status_code = config_field("reject_status_code")
    local reject_body_template = config_field("reject_body_template")

    assert.equals(409, reject_status_code.default)
    assert.same({ 100, 599 }, reject_status_code.between)
    assert.same({ "default", "minimal" }, reject_body_template.one_of)
  end)

  it("defines policy fields used by resolver", function()
    local policy_id = config_field("policy_id")
    local enforce_on_reason = config_field("enforce_on_reason")
    local policy_overrides = config_field("policy_overrides")

    assert.equals("default", policy_id.default)
    assert.same({ constants.REASON_INVARIANT_VIOLATION }, enforce_on_reason.default)
    assert.equals("array", policy_overrides.type)
  end)

  it("allows policy overrides for reject settings", function()
    local override_fields = override_value_fields()

    assert_same_members(override_fields.target_type.one_of, "route", "service")
    assert.is_false(has_value(override_fields.target_type.one_of, "consumer"))
    assert.equals("integer", override_fields.reject_status_code.type)
    assert.same({ 100, 599 }, override_fields.reject_status_code.between)
    assert.same({ "default", "minimal" }, override_fields.reject_body_template.one_of)
  end)

  it("validates policy override target_id as uuid", function()
    local override_fields = override_value_fields()
    local validator = override_fields.target_id.custom_validator
    local ok, err = validator("not-a-uuid")

    assert.is_nil(ok)
    assert.equals("must be a valid UUID", err)
    assert.is_true(validator("123e4567-e89b-12d3-a456-426614174000"))
  end)
end)
