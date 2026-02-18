local constants = require("kong.plugins.version-gate.constants")
local version_extractor = require("kong.plugins.version-gate.version_extractor")

describe("version_extractor", function()
  it("normalizes leading zeros and zero-only values", function()
    local v1, err1 = version_extractor.parse_version("00042", constants.REASON_PARSE_ERROR_EXPECTED)
    local v2, err2 = version_extractor.parse_version("000", constants.REASON_PARSE_ERROR_EXPECTED)

    assert.equals("42", v1)
    assert.is_nil(err1)
    assert.equals("0", v2)
    assert.is_nil(err2)
  end)

  it("returns source-specific parse reasons", function()
    local _, expected_err = version_extractor.get_expected_version("abc")
    local _, actual_err = version_extractor.get_actual_version("abc")

    assert.equals(constants.REASON_PARSE_ERROR_EXPECTED, expected_err)
    assert.equals(constants.REASON_PARSE_ERROR_ACTUAL, actual_err)
  end)
end)
