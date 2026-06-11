local constants = require("kong.plugins.version-gate.constants")
local memory_source_reader = require("kong.plugins.version-gate.source_readers.memory")
local version_intake = require("kong.plugins.version-gate.version_intake")

describe("version_intake", function()
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

  it("reads expected request header and actual response header", function()
    local reader = memory_source_reader.new({
      request_headers = { ["x-expected-version"] = "0007" },
      response_headers = { ["x-actual-version"] = "0008" },
    })

    local expected, expected_err, expected_raw = version_intake.read_expected(conf, reader)
    local actual, actual_err, actual_raw = version_intake.read_actual(conf, reader)

    assert.equals("7", expected)
    assert.is_nil(expected_err)
    assert.equals("0007", expected_raw)
    assert.equals("8", actual)
    assert.is_nil(actual_err)
    assert.equals("0008", actual_raw)
  end)

  it("maps query, cookie, and jwt strategy config fields", function()
    local reader = memory_source_reader.new({
      query = { expected_version = "9", actual_version = "10" },
      cookies = { expected_version = "11", actual_version = "12" },
      jwt_claims = { expected_version = "13", actual_version = "14" },
    })

    conf.expected_source_strategy = "query"
    conf.actual_source_strategy = "query"
    assert.equals("9", version_intake.read_expected(conf, reader))
    assert.equals("10", version_intake.read_actual(conf, reader))

    conf.expected_source_strategy = "cookie"
    conf.actual_source_strategy = "cookie"
    assert.equals("11", version_intake.read_expected(conf, reader))
    assert.equals("12", version_intake.read_actual(conf, reader))

    conf.expected_source_strategy = "jwt_claim"
    conf.actual_source_strategy = "jwt_claim"
    assert.equals("13", version_intake.read_expected(conf, reader))
    assert.equals("14", version_intake.read_actual(conf, reader))
  end)

  it("assigns expected and actual parse reasons", function()
    local reader = memory_source_reader.new({
      request_headers = { ["x-expected-version"] = "bad" },
      response_headers = { ["x-actual-version"] = "also-bad" },
    })

    local expected, expected_err, expected_raw = version_intake.read_expected(conf, reader)
    local actual, actual_err, actual_raw = version_intake.read_actual(conf, reader)

    assert.is_nil(expected)
    assert.equals(constants.REASON_PARSE_ERROR_EXPECTED, expected_err)
    assert.equals("bad", expected_raw)
    assert.is_nil(actual)
    assert.equals(constants.REASON_PARSE_ERROR_ACTUAL, actual_err)
    assert.equals("also-bad", actual_raw)
  end)

  it("keeps missing values fail-open compatible", function()
    local reader = memory_source_reader.new({})

    local expected, expected_err, expected_raw = version_intake.read_expected(conf, reader)
    local actual, actual_err, actual_raw = version_intake.read_actual(conf, reader)

    assert.is_nil(expected)
    assert.is_nil(expected_err)
    assert.is_nil(expected_raw)
    assert.is_nil(actual)
    assert.is_nil(actual_err)
    assert.is_nil(actual_raw)
  end)
end)
