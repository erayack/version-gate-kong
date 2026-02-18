local typedefs = require("kong.db.schema.typedefs")

local function validate_non_empty_header_name(value)
  if type(value) ~= "string" or value:match("^%s*$") then
    return nil, "must be a non-empty header name"
  end

  return true
end

local function validate_log_only_poc(value)
  if value ~= true then
    return nil, "must be true in PoC mode"
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
        { log_only = {
          type = "boolean",
          required = true,
          default = true,
          custom_validator = validate_log_only_poc,
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
      },
    } },
  },
}
