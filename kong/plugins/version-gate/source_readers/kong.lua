local _M = {}

local function table_lookup_case_sensitive_or_lower(tbl, key)
  if type(tbl) ~= "table" or type(key) ~= "string" or key == "" then
    return nil
  end

  local value = tbl[key]
  if value ~= nil then
    return value
  end

  return tbl[key:lower()]
end

local function read_jwt_claim_from_token(token, claim_name)
  if type(token) ~= "table" then
    return nil
  end

  local claims = token.claims or token.payload
  if type(claims) ~= "table" then
    return nil
  end

  return claims[claim_name]
end

function _M.new(ctx)
  ctx = ctx or {}

  return {
    read_request_header = function(_, name)
      local from_headers = table_lookup_case_sensitive_or_lower(ctx.headers, name)
      if from_headers ~= nil then
        return from_headers
      end

      if type(ctx.get_header) == "function" then
        return ctx.get_header(name)
      end

      if type(ctx.request) == "table" and type(ctx.request.get_header) == "function" then
        return ctx.request.get_header(name)
      end

      if kong ~= nil and kong.request ~= nil and type(kong.request.get_header) == "function" then
        return kong.request.get_header(name)
      end

      return nil
    end,

    read_response_header = function(_, name)
      local from_headers = table_lookup_case_sensitive_or_lower(ctx.headers, name)
      if from_headers ~= nil then
        return from_headers
      end

      if type(ctx.get_header) == "function" then
        return ctx.get_header(name)
      end

      if type(ctx.response) == "table" and type(ctx.response.get_header) == "function" then
        return ctx.response.get_header(name)
      end

      if kong ~= nil and kong.response ~= nil and type(kong.response.get_header) == "function" then
        return kong.response.get_header(name)
      end

      return nil
    end,

    read_request_query = function(_, name)
      local from_query = table_lookup_case_sensitive_or_lower(ctx.query, name)
      if from_query ~= nil then
        return from_query
      end

      if type(ctx.get_query_arg) == "function" then
        return ctx.get_query_arg(name)
      end

      if type(ctx.request) == "table" and type(ctx.request.get_query_arg) == "function" then
        return ctx.request.get_query_arg(name)
      end

      if kong ~= nil and kong.request ~= nil and type(kong.request.get_query_arg) == "function" then
        return kong.request.get_query_arg(name)
      end

      return nil
    end,

    read_request_cookie = function(_, name)
      local from_cookies = table_lookup_case_sensitive_or_lower(ctx.cookies, name)
      if from_cookies ~= nil then
        return from_cookies
      end

      if type(ctx.get_cookie) == "function" then
        return ctx.get_cookie(name)
      end

      if type(ctx.request) == "table" and type(ctx.request.get_cookie) == "function" then
        return ctx.request.get_cookie(name)
      end

      if kong ~= nil and kong.request ~= nil and type(kong.request.get_cookie) == "function" then
        return kong.request.get_cookie(name)
      end

      return nil
    end,

    read_request_jwt_claim = function(_, name)
      local direct_claims = ctx.jwt_claims
      if type(direct_claims) == "table" and direct_claims[name] ~= nil then
        return direct_claims[name]
      end

      local claim_from_token = read_jwt_claim_from_token(ctx.authenticated_jwt_token or ctx.jwt_token, name)
      if claim_from_token ~= nil then
        return claim_from_token
      end

      if type(ctx.kong_ctx) == "table" and type(ctx.kong_ctx.shared) == "table" then
        local claim_from_shared = read_jwt_claim_from_token(ctx.kong_ctx.shared.authenticated_jwt_token, name)
        if claim_from_shared ~= nil then
          return claim_from_shared
        end
      end

      if type(ctx.ngx_ctx) == "table" then
        local claim_from_ngx = read_jwt_claim_from_token(ctx.ngx_ctx.authenticated_jwt_token, name)
        if claim_from_ngx ~= nil then
          return claim_from_ngx
        end
      end

      if kong ~= nil and kong.ctx ~= nil and type(kong.ctx.shared) == "table" then
        local claim_from_shared = read_jwt_claim_from_token(kong.ctx.shared.authenticated_jwt_token, name)
        if claim_from_shared ~= nil then
          return claim_from_shared
        end
      end

      if ngx ~= nil and type(ngx.ctx) == "table" then
        local claim_from_ngx = read_jwt_claim_from_token(ngx.ctx.authenticated_jwt_token, name)
        if claim_from_ngx ~= nil then
          return claim_from_ngx
        end
      end

      return nil
    end,
  }
end

return _M
