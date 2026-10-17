-- Minimal stand-ins for WoW globals so addon logic can run under plain Lua 5.1.
-- Later tasks extend this file as they need more of the API.

wipe = wipe or function(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = tinsert or table.insert
tremove = tremove or table.remove
strlower = strlower or string.lower
strupper = strupper or string.upper
strfind = strfind or string.find
strsub = strsub or string.sub
strlen = strlen or string.len
strrep = strrep or string.rep
format = format or string.format
gsub = gsub or string.gsub
date = date or os.date
time = time or os.time

strtrim = strtrim or function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end

strsplit = strsplit or function(delim, s)
  local out, pos = {}, 1
  while true do
    local a, b = string.find(s, delim, pos, true)
    if not a then out[#out + 1] = string.sub(s, pos) break end
    out[#out + 1] = string.sub(s, pos, a - 1)
    pos = b + 1
  end
  return unpack(out)
end

GetTime = GetTime or function() return os.clock() end

-- Fake Ace3 for loading Core/Init.lua (Task 10). LibStub(name) returns a
-- stand-in library; the fake addon object records what it registers so specs
-- can fire events and slash commands by hand.
local function deepcopy(v)
  if type(v) ~= "table" then return v end
  local out = {}
  for k, x in pairs(v) do out[k] = deepcopy(x) end
  return out
end

local fakeLibs = {}

fakeLibs["AceAddon-3.0"] = {
  NewAddon = function(self, name, ...)
    local addon = { name = name, mixins = { ... }, events = {}, commands = {}, printed = {} }
    function addon:RegisterEvent(event, method) self.events[event] = method or event end
    function addon:UnregisterEvent(event) self.events[event] = nil end
    function addon:RegisterChatCommand(cmd, method) self.commands[cmd] = method end
    function addon:Print(...)
      local parts = {}
      for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
      self.printed[#self.printed + 1] = table.concat(parts, " ")
    end
    return addon
  end,
}

fakeLibs["AceDB-3.0"] = {
  New = function(self, svName, defaults)
    defaults = defaults or {}
    return { sv = svName, global = deepcopy(defaults.global) or {}, char = deepcopy(defaults.char) or {} }
  end,
}

LibStub = LibStub or function(name, silent)
  local lib = fakeLibs[name]
  if not lib and not silent then error("stub LibStub: no library " .. tostring(name), 2) end
  return lib
end

-- Calls the handler the fake addon registered for `event` (method name or function).
function fire_event(addon, event, ...)
  local handler = addon.events[event]
  if not handler then error("event not registered: " .. tostring(event), 2) end
  if type(handler) == "function" then return handler(event, ...) end
  return addon[handler](addon, event, ...)
end

-- Lua files listed in AzerothTrail.toc, in order, minus XML and UI/ files.
function toc_lua_files()
  local fh = assert(io.open(ROOT .. "/AzerothTrail.toc", "r"))
  local files = {}
  for line in fh:lines() do
    line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
    if line ~= "" and not line:find("^#") and line:find("%.lua$") then
      local path = line:gsub("\\", "/")
      if not path:find("^UI/") then files[#files + 1] = path end
    end
  end
  fh:close()
  return files
end

-- Calls the handler the fake addon registered for slash command `cmd`.
function run_slash(addon, cmd, input)
  local handler = addon.commands[cmd]
  if not handler then error("slash command not registered: " .. tostring(cmd), 2) end
  if type(handler) == "function" then return handler(input) end
  return addon[handler](addon, input)
end
