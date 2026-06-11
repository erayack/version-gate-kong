local constants = require("kong.plugins.version-gate.constants")
local version_parser = require("kong.plugins.version-gate.version_parser")

describe("version_parser", function()
  it("normalizes digit strings without losing precision", function()
    local version, err = version_parser.parse("000123456789012345678901234567890", constants.REASON_PARSE_ERROR_EXPECTED)

    assert.equals("123456789012345678901234567890", version)
    assert.is_nil(err)
  end)

  it("normalizes zero-only values", function()
    local version, err = version_parser.parse("000", constants.REASON_PARSE_ERROR_EXPECTED)

    assert.equals("0", version)
    assert.is_nil(err)
  end)

  it("returns nil reason for missing raw values", function()
    local version, err = version_parser.parse(nil, constants.REASON_PARSE_ERROR_EXPECTED)

    assert.is_nil(version)
    assert.is_nil(err)
  end)

  it("returns supplied reason for invalid values", function()
    local version, err = version_parser.parse("12a", constants.REASON_PARSE_ERROR_ACTUAL)

    assert.is_nil(version)
    assert.equals(constants.REASON_PARSE_ERROR_ACTUAL, err)
  end)
end)
