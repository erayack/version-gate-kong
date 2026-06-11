local constants = require("kong.plugins.version-gate.constants")

local function base_conf(overrides)
  local conf = {
    enabled = true,
    mode = "annotate",
    expected_header_name = "x-expected-version",
    actual_header_name = "x-actual-version",
    expected_source_strategy = "header",
    actual_source_strategy = "header",
    enforce_on_reason = { constants.REASON_INVARIANT_VIOLATION },
    state_suppression_window_ms = 0,
    reject_status_code = 409,
  }

  for k, v in pairs(overrides or {}) do
    conf[k] = v
  end

  return conf
end

describe("handler", function()
  local saved_kong
  local saved_ngx
  local captured_headers
  local captured_exit
  local captured_warns
  local captured_notices
  local request_headers
  local response_headers
  local route_id
  local service_id

  local function install_kong()
    _G.ngx = {
      now = function()
        return 1000
      end,
      ctx = {},
    }
    _G.kong = {
      ctx = { plugin = {}, shared = {} },
      router = {
        get_route = function()
          return route_id and { id = route_id } or nil
        end,
      },
      client = {
        get_service = function()
          return service_id and { id = service_id } or nil
        end,
      },
      request = {
        get_id = function()
          return "request-1"
        end,
        get_header = function(name)
          return request_headers[name]
        end,
        get_method = function()
          return "GET"
        end,
        get_path = function()
          return "/foo"
        end,
      },
      response = {
        get_header = function(name)
          return response_headers[name]
        end,
        set_header = function(name, value)
          captured_headers[name] = value
        end,
        exit = function(status, body, headers)
          captured_exit = { status = status, body = body, headers = headers }
          return captured_exit
        end,
      },
      log = {
        warn = function(...)
          captured_warns[#captured_warns + 1] = { ... }
        end,
        notice = function(...)
          captured_notices[#captured_notices + 1] = { ... }
        end,
      },
    }
  end

  before_each(function()
    saved_kong = _G.kong
    saved_ngx = _G.ngx
    package.loaded["kong.plugins.version-gate.handler"] = nil

    captured_headers = {}
    captured_exit = nil
    captured_warns = {}
    captured_notices = {}
    request_headers = {}
    response_headers = {}
    route_id = "route-1"
    service_id = "service-1"

    install_kong()
  end)

  after_each(function()
    _G.kong = saved_kong
    _G.ngx = saved_ngx
    package.loaded["kong.plugins.version-gate.handler"] = nil
  end)

  it("annotates violation responses without rejecting traffic", function()
    request_headers["x-expected-version"] = "10"
    response_headers["x-actual-version"] = "9"
    local handler = require("kong.plugins.version-gate.handler")
    local conf = base_conf({ mode = "annotate" })

    handler:access(conf)
    local result = handler:header_filter(conf)

    assert.is_nil(result)
    assert.is_nil(captured_exit)
    assert.equals(constants.DECISION_VIOLATION, captured_headers[constants.HEADER_DECISION])
    assert.equals(constants.REASON_INVARIANT_VIOLATION, captured_headers[constants.HEADER_REASON])
    assert.equals("annotate", captured_headers[constants.HEADER_MODE])
    assert.equals(1, #captured_warns)
  end)

  it("exits with reject result when reject policy is violated", function()
    request_headers["x-expected-version"] = "10"
    response_headers["x-actual-version"] = "9"
    local handler = require("kong.plugins.version-gate.handler")
    local conf = base_conf({ mode = "reject", reject_status_code = 409 })

    handler:access(conf)
    local result = handler:header_filter(conf)

    assert.is_not_nil(captured_exit)
    assert.equals(409, captured_exit.status)
    assert.equals("version gate violation", captured_exit.body.message)
    assert.equals(constants.DECISION_VIOLATION, captured_exit.headers[constants.HEADER_DECISION])
    assert.equals(captured_exit, result)
    assert.equals(1, #captured_warns)
  end)

  it("does not warn when violation reason is not enforced", function()
    request_headers["x-expected-version"] = "10"
    response_headers["x-actual-version"] = nil
    local handler = require("kong.plugins.version-gate.handler")
    local conf = base_conf({ mode = "annotate", enforce_on_reason = { constants.REASON_INVARIANT_VIOLATION } })

    handler:access(conf)
    handler:header_filter(conf)

    assert.same({}, captured_headers)
    assert.equals(0, #captured_warns)
  end)

  it("uses subject header key before composite fallback for suppression state", function()
    local store_reads = {}
    request_headers["x-expected-version"] = "10"
    request_headers["x-subject"] = "tenant-42"
    response_headers["x-actual-version"] = "9"
    local handler = require("kong.plugins.version-gate.handler")
    local conf = base_conf({
      mode = "annotate",
      state_suppression_window_ms = 100,
      state_subject_header_name = "x-subject",
      state_store_adapter = {
        get_last_seen = function(_, subject_key)
          store_reads[#store_reads + 1] = subject_key
          return "10", 1000000 - 50
        end,
      },
    })

    handler:access(conf)
    handler:header_filter(conf)

    assert.equals("subject:tenant-42", store_reads[1])
    assert.same({}, captured_headers)
    assert.equals(0, #captured_warns)
  end)

  it("uses composite subject key when subject header is missing", function()
    local store_reads = {}
    request_headers["x-expected-version"] = "10"
    response_headers["x-actual-version"] = "9"
    local handler = require("kong.plugins.version-gate.handler")
    local conf = base_conf({
      mode = "annotate",
      state_suppression_window_ms = 100,
      state_subject_header_name = "x-subject",
      state_store_adapter = {
        get_last_seen = function(_, subject_key)
          store_reads[#store_reads + 1] = subject_key
          return "10", 1000000 - 50
        end,
      },
    })

    handler:access(conf)
    handler:header_filter(conf)

    assert.equals("route:route-1|service:service-1|method:GET|path:/foo", store_reads[1])
    assert.same({}, captured_headers)
  end)

  it("emits log records using the resolved request policy", function()
    request_headers["x-expected-version"] = "10"
    response_headers["x-actual-version"] = "10"
    local handler = require("kong.plugins.version-gate.handler")
    local conf = base_conf({ mode = "shadow", emit_sample_rate = 1.0, emit_format = "logfmt" })

    handler:access(conf)
    handler:header_filter(conf)
    handler:log(conf)

    assert.equals(1, #captured_notices)
    assert.matches("mode=shadow", captured_notices[1][2])
    assert.matches("decision=ALLOW", captured_notices[1][2])
  end)

  it("does nothing when disabled", function()
    request_headers["x-expected-version"] = "10"
    response_headers["x-actual-version"] = "9"
    local handler = require("kong.plugins.version-gate.handler")
    local conf = base_conf({ enabled = false, mode = "reject" })

    handler:access(conf)
    local result = handler:header_filter(conf)
    handler:log(conf)

    assert.is_nil(result)
    assert.is_nil(captured_exit)
    assert.same({}, captured_headers)
    assert.equals(0, #captured_warns)
    assert.equals(0, #captured_notices)
  end)
end)
