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
