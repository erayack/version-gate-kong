local typedefs = require("kong.db.schema.typedefs")
local constants = require("kong.plugins.version-gate.constants")

local function validate_non_empty_header_name(value)
  if type(value) ~= "string" or value:match("^%s*$") then
    return nil, "must be a non-empty header name"
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
        { policy_by_service = {
          type = "map",
          required = false,
          keys = { type = "string" },
          values = {
            type = "record",
            fields = {
              { id = { type = "string", required = false } },
              { mode = { type = "string", required = false, one_of = { "shadow", "annotate", "reject" } } },
              { emit_sample_rate = { type = "number", required = false, between = { 0, 1 } } },
              { enforce_on_reason = { type = "array", required = false, elements = { type = "string" } } },
            },
          },
        } },
        { policy_by_route = {
          type = "map",
          required = false,
          keys = { type = "string" },
          values = {
            type = "record",
            fields = {
              { id = { type = "string", required = false } },
              { mode = { type = "string", required = false, one_of = { "shadow", "annotate", "reject" } } },
              { emit_sample_rate = { type = "number", required = false, between = { 0, 1 } } },
              { enforce_on_reason = { type = "array", required = false, elements = { type = "string" } } },
            },
          },
        } },
        { expected_header_name = {
          type = "string",
          required = true,
          default = "x-expected-version",
          custom_validator = validate_non_empty_header_name,
        } },
        { actual_header_name = {
          type = "string",
          required = true,
          default = "x-actual-version",
          custom_validator = validate_non_empty_header_name,
        } },
        { emit_sample_rate = {
          type = "number",
          required = true,
          default = 1,
          between = { 0, 1 },
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
}
