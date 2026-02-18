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

  it("defines policy fields used by resolver", function()
    local policy_id = config_field("policy_id")
    local enforce_on_reason = config_field("enforce_on_reason")
    local policy_by_service = config_field("policy_by_service")
    local policy_by_route = config_field("policy_by_route")

    assert.equals("default", policy_id.default)
    assert.same({ constants.REASON_INVARIANT_VIOLATION }, enforce_on_reason.default)
    assert.equals("map", policy_by_service.type)
    assert.equals("map", policy_by_route.type)
  end)
end)
