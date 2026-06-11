local constants = require("kong.plugins.version-gate.constants")
local version_extractor = require("kong.plugins.version-gate.version_extractor")

describe("version_extractor", function()
  local conf

  before_each(function()
    conf = {
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
    }
  end)

  it("normalizes leading zeros and zero-only values", function()
    local v1, err1 = version_extractor.parse_version("00042", constants.REASON_PARSE_ERROR_EXPECTED)
    local v2, err2 = version_extractor.parse_version("000", constants.REASON_PARSE_ERROR_EXPECTED)

    assert.equals("42", v1)
    assert.is_nil(err1)
    assert.equals("0", v2)
    assert.is_nil(err2)
  end)

  it("returns source-specific parse reasons", function()
    local _, expected_err = version_extractor.get_expected_version(conf, {
      headers = { ["x-expected-version"] = "abc" },
    })
    local _, actual_err = version_extractor.get_actual_version(conf, {
      headers = { ["x-actual-version"] = "abc" },
    })

    assert.equals(constants.REASON_PARSE_ERROR_EXPECTED, expected_err)
    assert.equals(constants.REASON_PARSE_ERROR_ACTUAL, actual_err)
  end)

  it("extracts query strategy values", function()
    conf.expected_source_strategy = "query"
    conf.actual_source_strategy = "query"
    local expected, expected_err = version_extractor.get_expected_version(conf, {
      query = { expected_version = "0009" },
    })
    local actual, actual_err = version_extractor.get_actual_version(conf, {
      query = { actual_version = "010" },
    })

    assert.equals("9", expected)
    assert.is_nil(expected_err)
    assert.equals("10", actual)
    assert.is_nil(actual_err)
  end)

  it("extracts jwt claim strategy values", function()
    conf.expected_source_strategy = "jwt_claim"
    conf.actual_source_strategy = "jwt_claim"
    local expected = version_extractor.get_expected_version(conf, {
      jwt_claims = { expected_version = "7" },
    })
    local actual = version_extractor.get_actual_version(conf, {
      jwt_claims = { actual_version = "8" },
    })

    assert.equals("7", expected)
    assert.equals("8", actual)
  end)

  it("extracts cookie strategy values", function()
    conf.expected_source_strategy = "cookie"
    conf.actual_source_strategy = "cookie"
    local expected = version_extractor.get_expected_version(conf, {
      cookies = { expected_version = "15" },
    })
    local actual = version_extractor.get_actual_version(conf, {
      cookies = { actual_version = "16" },
    })

    assert.equals("15", expected)
    assert.equals("16", actual)
  end)

  it("extracts expected headers from request scope and actual headers from response scope", function()
    local expected_raw = version_extractor.get_expected_raw(conf, {
      headers = { ["x-expected-version"] = "21" },
    })
    local actual_raw = version_extractor.get_actual_raw(conf, {
      headers = { ["x-actual-version"] = "22" },
      request = { get_header = function() return "request-wrong" end },
    })

    assert.equals("21", expected_raw)
    assert.equals("22", actual_raw)
  end)

  it("falls back to request/response accessor functions", function()
    local expected_raw = version_extractor.get_expected_raw(conf, {
      request = { get_header = function(name) return name == "x-expected-version" and "31" or nil end },
    })
    local actual_raw = version_extractor.get_actual_raw(conf, {
      response = { get_header = function(name) return name == "x-actual-version" and "32" or nil end },
    })

    assert.equals("31", expected_raw)
    assert.equals("32", actual_raw)
  end)

  it("extracts jwt claims from token payload and claims table compatibility shapes", function()
    conf.expected_source_strategy = "jwt_claim"
    conf.actual_source_strategy = "jwt_claim"

    local expected = version_extractor.get_expected_version(conf, {
      authenticated_jwt_token = { claims = { expected_version = "41" } },
    })
    local actual = version_extractor.get_actual_version(conf, {
      jwt_token = { payload = { actual_version = "42" } },
    })

    assert.equals("41", expected)
    assert.equals("42", actual)
  end)

  it("extracts jwt claims from Kong shared and ngx context compatibility shapes", function()
    conf.expected_source_strategy = "jwt_claim"
    conf.actual_source_strategy = "jwt_claim"

    local expected = version_extractor.get_expected_version(conf, {
      kong_ctx = {
        shared = {
          authenticated_jwt_token = { claims = { expected_version = "51" } },
        },
      },
    })
    local actual = version_extractor.get_actual_version(conf, {
      ngx_ctx = {
        authenticated_jwt_token = { claims = { actual_version = "52" } },
      },
    })

    assert.equals("51", expected)
    assert.equals("52", actual)
  end)

  it("returns nil version and nil reason for missing raw values", function()
    local expected, expected_err = version_extractor.get_expected_version(conf, { headers = {} })
    local actual, actual_err = version_extractor.get_actual_version(conf, { headers = {} })

    assert.is_nil(expected)
    assert.is_nil(expected_err)
    assert.is_nil(actual)
    assert.is_nil(actual_err)
  end)
end)
