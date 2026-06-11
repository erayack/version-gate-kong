local kong_source_reader = require("kong.plugins.version-gate.source_readers.kong")
local memory_source_reader = require("kong.plugins.version-gate.source_readers.memory")

describe("source readers", function()
  local original_kong
  local original_ngx

  before_each(function()
    original_kong = _G.kong
    original_ngx = _G.ngx
  end)

  after_each(function()
    _G.kong = original_kong
    _G.ngx = original_ngx
  end)

  it("read equivalent table-backed request and response values", function()
    local memory_reader = memory_source_reader.new({
      request_headers = { ["x-expected-version"] = "1" },
      response_headers = { ["x-actual-version"] = "2" },
      query = { expected_version = "3" },
      cookies = { expected_version = "4" },
      jwt_claims = { expected_version = "5" },
    })
    local kong_reader = kong_source_reader.new({
      headers = { ["x-expected-version"] = "1", ["x-actual-version"] = "2" },
      query = { expected_version = "3" },
      cookies = { expected_version = "4" },
      jwt_claims = { expected_version = "5" },
    })

    assert.equals("1", memory_reader:read_request_header("x-expected-version"))
    assert.equals("1", kong_reader:read_request_header("x-expected-version"))
    assert.equals("2", memory_reader:read_response_header("x-actual-version"))
    assert.equals("2", kong_reader:read_response_header("x-actual-version"))
    assert.equals("3", memory_reader:read_request_query("expected_version"))
    assert.equals("3", kong_reader:read_request_query("expected_version"))
    assert.equals("4", memory_reader:read_request_cookie("expected_version"))
    assert.equals("4", kong_reader:read_request_cookie("expected_version"))
    assert.equals("5", memory_reader:read_request_jwt_claim("expected_version"))
    assert.equals("5", kong_reader:read_request_jwt_claim("expected_version"))
  end)

  it("Kong reader preserves accessor and JWT context compatibility", function()
    local reader = kong_source_reader.new({
      request = {
        get_header = function(name) return name == "x-expected-version" and "11" or nil end,
        get_query_arg = function(name) return name == "expected_version" and "12" or nil end,
        get_cookie = function(name) return name == "expected_version" and "13" or nil end,
      },
      response = {
        get_header = function(name) return name == "x-actual-version" and "14" or nil end,
      },
      kong_ctx = {
        shared = {
          authenticated_jwt_token = { claims = { expected_version = "15" } },
        },
      },
    })

    assert.equals("11", reader:read_request_header("x-expected-version"))
    assert.equals("12", reader:read_request_query("expected_version"))
    assert.equals("13", reader:read_request_cookie("expected_version"))
    assert.equals("14", reader:read_response_header("x-actual-version"))
    assert.equals("15", reader:read_request_jwt_claim("expected_version"))
  end)

  it("Kong reader falls back to global Kong and ngx JWT contexts", function()
    _G.kong = {
      ctx = {
        shared = {
          authenticated_jwt_token = { claims = { expected_version = "21" } },
        },
      },
    }
    _G.ngx = {
      ctx = {
        authenticated_jwt_token = { claims = { actual_version = "22" } },
      },
    }

    local reader = kong_source_reader.new({})

    assert.equals("21", reader:read_request_jwt_claim("expected_version"))
    assert.equals("22", reader:read_request_jwt_claim("actual_version"))
  end)

  it("memory reader stays independent of Kong fallback globals", function()
    _G.kong = {
      request = {
        get_header = function() return "global" end,
      },
    }

    local reader = memory_source_reader.new({ request_headers = {} })
    assert.is_nil(reader:read_request_header("x-expected-version"))
  end)
end)
