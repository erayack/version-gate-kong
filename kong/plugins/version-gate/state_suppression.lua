local constants = require("kong.plugins.version-gate.constants")
local invariant = require("kong.plugins.version-gate.invariant")

local _M = {}

local function suppression_window(conf)
  local window_ms = tonumber(conf and conf.state_suppression_window_ms)
  if window_ms == nil or window_ms <= 0 then
    return nil
  end

  return window_ms
end

local function copy_decision(input)
  return {
    decision = input and input.decision,
    reason = input and input.reason,
  }
end

local function read_last_seen(store, subject_key)
  if store == nil or subject_key == nil or type(store.get_last_seen) ~= "function" then
    return nil, nil
  end

  local ok, version, ts_ms = pcall(store.get_last_seen, store, subject_key)
  if not ok then
    return nil, nil
  end

  return version, ts_ms
end

local function write_last_seen(store, subject_key, version, ts_ms)
  if store == nil or subject_key == nil or type(store.set_last_seen) ~= "function" then
    return nil
  end

  local ok, did_write = pcall(store.set_last_seen, store, subject_key, version, ts_ms)
  if not ok then
    return false
  end

  return did_write == true
end

local function maybe_suppress(input, result, window_ms)
  if result.decision ~= constants.DECISION_VIOLATION or result.reason ~= constants.REASON_INVARIANT_VIOLATION then
    return
  end

  if input.store == nil or input.subject_key == nil or input.expected_version == nil then
    return
  end

  local last_seen_version, last_seen_ts_ms = read_last_seen(input.store, input.subject_key)
  result.last_seen_version = last_seen_version
  result.last_seen_ts_ms = last_seen_ts_ms

  if type(last_seen_version) ~= "string" or type(last_seen_ts_ms) ~= "number" then
    return
  end

  if invariant.is_violation(input.expected_version, last_seen_version) then
    return
  end

  if (input.now_ts_ms - last_seen_ts_ms) > window_ms then
    return
  end

  result.state_suppressed = true
  result.decision = constants.DECISION_ALLOW
  result.reason = constants.REASON_INVARIANT_OK
end

local function maybe_persist(input, result)
  if input.decision ~= constants.DECISION_ALLOW or input.reason ~= constants.REASON_INVARIANT_OK then
    return
  end

  if type(input.actual_version) ~= "string" then
    return
  end

  local write_ok = write_last_seen(input.store, input.subject_key, input.actual_version, input.now_ts_ms)
  if write_ok ~= nil then
    result.state_store_write_ok = write_ok
  end
end

---Applies last-seen state suppression and persistence through the state-store seam.
---@param input table
---@return table
function _M.apply(input)
  input = input or {}
  local result = copy_decision(input)
  local window_ms = suppression_window(input.conf)
  if window_ms == nil then
    return result
  end

  maybe_suppress(input, result, window_ms)
  maybe_persist(input, result)
  return result
end

return _M
