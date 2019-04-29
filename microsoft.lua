-- Copyright 2015-2016 CloudFlare
-- Copyright 2014-2015 Aaron Westendorf

local json = require("cjson")
local http = require("resty.http")

local uri         = ngx.var.uri
local uri_args    = ngx.req.get_uri_args()
local scheme      = ngx.var.scheme

local client_id         = ngx.var.client_id
local client_secret     = ngx.var.client_secret
local token_secret      = ngx.var.token_secret
local domain            = ngx.var.domain
local cb_scheme         = ngx.var.callback_scheme or scheme
local cb_server_name    = ngx.var.callback_host or ngx.var.server_name
local cb_uri            = ngx.var.callback_uri or "/_oauth"
local cb_url            = cb_scheme .. "://" .. cb_server_name .. cb_uri
local redirect_url      = cb_scheme .. "://" .. cb_server_name .. ngx.var.request_uri
local signout_uri       = ngx.var.signout_uri or "/_signout"
local extra_validity    = tonumber(ngx.var.extra_validity or "0")
local whitelist         = ngx.var.whitelist or ""
local blacklist         = ngx.var.blacklist or ""
local secure_cookies    = ngx.var.secure_cookies == "true" or false
local http_only_cookies = ngx.var.http_only_cookies == "true" or false
local set_user          = ngx.var.user or false
local email_as_user     = ngx.var.email_as_user == "true" or false


if whitelist:len() == 0 then
  whitelist = nil
end

if blacklist:len() == 0 then
  blacklist = nil
end

local function handle_token_uris(email, token, expires, profile)
  if uri == "/_token.json" then
    ngx.header["Content-type"] = "application/json"
    ngx.say(json.encode({
      email   = email,
      token   = token,
      expires = expires,
      first_name = profile['First_Name'],
      last_name = profile['Last_Name'],
      display_name = profile['Display_Name'],
      ID = profile['ID']
    }))
    ngx.exit(ngx.OK)
  end

  if uri == "/_token.txt" then
    ngx.header["Content-type"] = "text/plain"
    ngx.say("email: " .. email .. "\n" .. "token: " .. token .. "\n" .. "expires: " .. expires .. "\n")
    ngx.exit(ngx.OK)
  end

  if uri == "/_token.curl" then
    ngx.header["Content-type"] = "text/plain"
    ngx.say("-H \"OauthEmail: " .. email .. "\" -H \"OauthAccessToken: " .. token .. "\" -H \"OauthExpires: " .. expires .. "\"\n")
    ngx.exit(ngx.OK)
  end
end

local function check_domain(email, whitelist_failed)
  local oauth_domain = email:match("[^@]+@(.+)")
  -- if domain is configured, check it, if it isn't, permit request
  if domain:len() ~= 0 then
    if not string.find(" " .. domain .. " ", " " .. oauth_domain .. " ", 1, true) then
      if whitelist_failed then
        ngx.log(ngx.ERR, email .. " is not on " .. domain .. " nor in the whitelist")
      else
        ngx.log(ngx.ERR, email .. " is not on " .. domain)
      end
      return ngx.exit(ngx.HTTP_FORBIDDEN)
    end
  elseif whitelist_failed then
    return ngx.exit(ngx.HTTP_FORBIDDEN)
  end
end

local function on_auth(email, token, expires, profile)
  if blacklist then
    -- blacklisted user is always rejected
    if string.find(" " .. blacklist .. " ", " " .. email .. " ", 1, true) then
      ngx.log(ngx.ERR, email .. " is in blacklist")
      return ngx.exit(ngx.HTTP_FORBIDDEN)
    end
  end

  if whitelist then
    -- if whitelisted, no need check the if it's a valid domain
    if not string.find(" " .. whitelist .. " ", " " .. email .. " ", 1, true) then
      check_domain(email, true)
    end
  else
    -- empty whitelist, lets check if it's a valid domain
    check_domain(email, false)
  end


  if set_user then
    if email_as_user then
      ngx.var.user = email
    else
      ngx.var.user = email:match("([^@]+)@.+")
    end
  end
  
  handle_token_uris(email, token, expires, profile)
end

local function request_access_token(code)
  local request = http.new()

  request:set_timeout(7000)

  local uri = "https://login.microsoftonline.com/common/oauth2/v2.0/token" 
  local body = ngx.encode_args({
      code          = code,
      client_id     = client_id,
      client_secret = client_secret,
      redirect_uri  = cb_url,
      grant_type    = "authorization_code",
  })

  local res, err = request:request_uri(uri , {
    method = "POST",
    body = body,
    headers = {
      ["Content-type"] = "application/x-www-form-urlencoded"
    },
    ssl_verify = true,
  })
  if not res then
    return nil, (err or "auth token request failed: " .. (err or "unknown reason"))
  end

  if res.status ~= 200 then
    return nil, "received " .. res.status .. " from https://login.microsoftonline.com/common/oauth2/v2.0/token: " .. res.body
  end

  return json.decode(res.body)
end

local function request_profile(token)
  local request = http.new()

  request:set_timeout(7000)

  local res, err = request:request_uri("https://graph.microsoft.com/v1.0/me", {
    headers = {
      ["Authorization"] = "Bearer " .. token,
    },
    ssl_verify = true,
  })
  if not res then
    return nil, "auth info request failed: " .. (err or "unknown reason")
  end

  if res.status ~= 200 then
    return nil, "received " .. res.status .. " from https://graph.microsoft.com/v1.0/me"
  end

  return json.decode(res.body)
end

local function is_authorized()
  local headers = ngx.req.get_headers()

  local expires = tonumber(ngx.var.cookie_OauthExpires) or 0
  local email   = ngx.unescape_uri(ngx.var.cookie_OauthEmail or "")
  local token   = ngx.unescape_uri(ngx.var.cookie_OauthAccessToken or "")
  local profile = json.decode(ngx.unescape_uri(ngx.var.cookie_OauthProfile or "{}"))

  if expires == 0 and headers["oauthexpires"] then
    expires = tonumber(headers["oauthexpires"])
  end

  if email:len() == 0 and headers["oauthemail"] then
    email = headers["oauthemail"]
  end

  if token:len() == 0 and headers["oauthaccesstoken"] then
    token = headers["oauthaccesstoken"]
  end

  local expected_token = ngx.encode_base64(ngx.hmac_sha1(token_secret, cb_server_name .. email .. expires))

  if token == expected_token and expires and expires > ngx.time() - extra_validity then
    on_auth(email, token, expires, profile)
    return true
  else
    return false
  end
end

local function redirect_to_auth()
  return ngx.redirect("https://login.microsoftonline.com/common/oauth2/v2.0/authorize?" .. ngx.encode_args({
    client_id     = client_id,
    scope         = "User.Read",
      state         = redirect_url,
      redirect_uri  = cb_url,
      response_type = "code"
  }))
end

local function authorize()
  if uri ~= cb_uri then
    return redirect_to_auth()
  end

  if uri_args["error"] then
    ngx.log(ngx.ERR, "received " .. uri_args["error"] )
    return ngx.exit(ngx.HTTP_FORBIDDEN)
  end
  
  local token, token_err = request_access_token(uri_args["code"])
  if not token then
    ngx.log(ngx.ERR, "got error during access token request: " .. token_err)
    return ngx.exit(ngx.HTTP_FORBIDDEN)
  end

  local profile, profile_err = request_profile(token["access_token"])
  if not profile then
    ngx.log(ngx.ERR, "got error during profile request: " .. profile_err)
    return ngx.exit(ngx.HTTP_FORBIDDEN)
  end

  local expires      = ngx.time() + token["expires_in"]
  local cookie_tail  = ";version=1;path=/;Max-Age=" .. extra_validity + token["expires_in"]
  if secure_cookies then
    cookie_tail = cookie_tail .. ";secure"
  end
  if http_only_cookies then
    cookie_tail = cookie_tail .. ";httponly"
  end

  local email      = profile["userPrincipalName"]
  local user_token = ngx.encode_base64(ngx.hmac_sha1(token_secret, cb_server_name .. email .. expires))

  local p={}
  p['First_Name']=profile['givenName']
  p['Last_Name']=profile['surname']
  p['Display_Name']=profile['displayName']
  p['ID']=profile['id']
  on_auth(email, user_token, expires, p)

  ngx.header["Set-Cookie"] = {
    "OauthEmail="       .. ngx.escape_uri(email) .. cookie_tail,
    "OauthAccessToken=" .. ngx.escape_uri(user_token) .. cookie_tail,
    "OauthExpires="     .. expires .. cookie_tail,
    "OauthProfile="     .. ngx.escape_uri(json.encode(p)) .. cookie_tail,
  }

  return ngx.redirect(uri_args["state"])
end

local function handle_signout()
  if uri == signout_uri then
    ngx.header["Set-Cookie"] = "OauthAccessToken==deleted; path=/; expires=Thu, 01 Jan 1970 00:00:00 GMT"
    return ngx.redirect("/")
  end
end

handle_signout()

if not is_authorized() then
  authorize()
end

-- if already authenticated, but still receives a /_oauth request, redirect to the correct destination
if uri == "/_oauth" then
  if uri_args["state"] then
    return ngx.redirect(uri_args["state"])
  else
    return ngx.redirect("/")
  end
end