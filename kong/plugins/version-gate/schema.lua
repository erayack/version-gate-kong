local typedefs = require("kong.db.schema.typedefs")
local constants = require("kong.plugins.version-gate.constants")

local function validate_non_empty_header_name(value)
  if type(value) ~= "string" or value:match("^%s*$") then
    return nil, "must be a non-empty header name"
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
}
