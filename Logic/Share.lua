local ADDON, ns = ...

-- Shared lists: a custom list (Logic/Lists.lua) as one line of text to copy,
-- paste, whisper or send addon to addon (UI/Share.lua). Pure Lua.
--
--   MountTrail: !MT1!<name>!<mount ids>!<check>
--
-- "MountTrail: " is only a label so people reading the line know what it is;
-- decoding takes the line with or without it.
-- The name is percent-encoded (anything but letters, digits, space, - _ '),
-- the mount IDs are base 36 joined by dots, and the check is a base-36 sum
-- that catches a cut-off paste. Decoding keeps only mounts the data knows.
-- Addon messages carry at most 255 bytes, so a string travels in numbered
-- chunks (Share.Chunks) put back together by Share.Assembler.
local Share = {}
ns.Share = Share

Share.PREFIX = "!MT1!"
Share.LABEL = "MountTrail: "
Share.MAX_MOUNTS = 2000 -- more than the game has: anything above is not a list
Share.MAX_TEXT = 20000

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

local function toBase36(n)
  if n == 0 then return "0" end
  local out = ""
  while n > 0 do
    local d = n % 36
    out = string.sub(DIGITS, d + 1, d + 1) .. out
    n = math.floor(n / 36)
  end
  return out
end

local function checksum(text)
  local sum = 0
  for i = 1, #text do sum = (sum * 31 + string.byte(text, i)) % 1679616 end -- 36^4
  return toBase36(sum)
end

local function escape(name)
  return (string.gsub(name, "[^%w %-_']", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local function unescape(text)
  return (string.gsub(text, "%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- `name` and its mount IDs -> the share string.
function Share.Encode(name, mounts)
  local ids = {}
  for _, id in ipairs(mounts or {}) do
    if type(id) == "number" and id >= 0 and id == math.floor(id) then ids[#ids + 1] = toBase36(id) end
  end
  local body = escape(tostring(name or "")) .. "!" .. table.concat(ids, ".")
  return Share.LABEL .. Share.PREFIX .. body .. "!" .. checksum(body)
end

-- A share string (spaces around it are fine) -> { name =, mounts = { id, ... } },
-- or nil and why ("format", "damaged", "empty"). `known` (optional,
-- { [id] = mount }): mounts outside it are dropped (a list from a newer
-- version, or made up).
function Share.Decode(text, known)
  if type(text) ~= "string" or #text > Share.MAX_TEXT then return nil, "format" end
  text = string.match(text, "^%s*(.-)%s*$")
  text = string.gsub(text, "^[Mm][Oo][Uu][Nn][Tt][Tt][Rr][Aa][Ii][Ll]:%s*", "")
  if string.sub(text, 1, #Share.PREFIX) ~= Share.PREFIX then return nil, "format" end
  local body, check = string.match(string.sub(text, #Share.PREFIX + 1), "^(.*)!([%w]+)$")
  if not body then return nil, "format" end
  if checksum(body) ~= check then return nil, "damaged" end
  local rawName, rawIds = string.match(body, "^([^!]*)!([%w%.]*)$")
  if not rawName then return nil, "format" end
  local name = unescape(rawName)
  if not string.find(name, "%S") then return nil, "format" end
  local mounts, seen = {}, {}
  for part in string.gmatch(rawIds, "[^%.]+") do
    local id = tonumber(part, 36)
    if id and not seen[id] and (known == nil or known[id] ~= nil) then
      seen[id] = true
      mounts[#mounts + 1] = id
      if #mounts > Share.MAX_MOUNTS then return nil, "format" end
    end
  end
  if #mounts == 0 then return nil, "empty" end
  return { name = name, mounts = mounts }
end

-- A name not yet taken in `store` (Logic/Lists.lua): `name`, else "name (2)", ...
function Share.FreeName(store, name)
  local taken = {}
  for _, l in pairs(type(store) == "table" and type(store.lists) == "table" and store.lists or {}) do
    if type(l) == "table" and l.name then taken[l.name] = true end
  end
  if not taken[name] then return name end
  local n = 2
  while taken[name .. " (" .. n .. ")"] do n = n + 1 end
  return name .. " (" .. n .. ")"
end

-- Addon-message chunks -----------------------------------------------------------
-- "<kind><n>/<total>:<data>": kind "D" answers a request, "O" offers a list
-- unasked (Send to player). Requests are "R<list id>".

Share.CHUNK = 230

function Share.Chunks(kind, text)
  local parts = {}
  local total = math.max(1, math.ceil(#text / Share.CHUNK))
  for i = 1, total do
    local data = string.sub(text, (i - 1) * Share.CHUNK + 1, i * Share.CHUNK)
    parts[i] = kind .. i .. "/" .. total .. ":" .. data
  end
  return parts
end

-- A message -> kind, n, total, data; or "R", listID for a request; nil else.
function Share.Parse(msg)
  if type(msg) ~= "string" then return nil end
  local id = string.match(msg, "^R(%d+)$")
  if id then return "R", tonumber(id) end
  local kind, n, total, data = string.match(msg, "^([DO])(%d+)/(%d+):(.*)$")
  if not kind then return nil end
  return kind, tonumber(n), tonumber(total), data
end

-- Puts chunks back together per sender and kind. :Add(sender, msg) -> the
-- whole text and its kind once the last chunk is in, else nil. A chunk out
-- of order or a new first chunk starts over; at most MAX_TEXT characters.
function Share.Assembler()
  local pending = {}
  local a = {}
  function a:Add(sender, msg)
    local kind, n, total, data = Share.Parse(msg)
    if kind ~= "D" and kind ~= "O" then return nil end
    if not (n and total and n >= 1 and n <= total and total * Share.CHUNK <= Share.MAX_TEXT) then return nil end
    local key = tostring(sender) .. "|" .. kind
    local p = pending[key]
    if n == 1 then
      p = { total = total, parts = {} }
      pending[key] = p
    end
    if not p or p.total ~= total or #p.parts ~= n - 1 then
      pending[key] = nil
      return nil
    end
    p.parts[n] = data
    if n < total then return nil end
    pending[key] = nil
    return table.concat(p.parts), kind
  end
  return a
end

-- Chat links ---------------------------------------------------------------------
-- WeakAuras-style: the link names the sharer and the list; clicking it asks
-- the sharer's MountTrail for the list. "garrmission" is a link type the chat
-- passes through; the "mounttrail" field tells it apart from the game's own.

Share.LINK_TYPE = "garrmission"
Share.LINK_TAG = "mounttrail"

function Share.Link(sender, listID, name)
  return string.format("|cff3fc7eb|H%s:%s:%s:%d|h[MountTrail: %s]|h|r",
    Share.LINK_TYPE, Share.LINK_TAG, sender, listID, name)
end

-- A clicked link's text ("garrmission:mounttrail:Name-Realm:3") -> sender, listID; nil else.
function Share.ParseLink(link)
  if type(link) ~= "string" then return nil end
  local sender, id = string.match(link, "^" .. Share.LINK_TYPE .. ":" .. Share.LINK_TAG .. ":([^:]+):(%d+)")
  if not sender then return nil end
  return sender, tonumber(id)
end

-- Share strings in chat --------------------------------------------------------
-- A !MT1! line posted in chat turns into a clickable link on screens with
-- MountTrail (UI/Share.lua's chat filter); others just see the text.

Share.CHAT_MAX = 255 -- a chat message's length limit
local FIND = "!MT1![^!]*![%w%.]*![%w]+"

-- Every share string in a chat message -> { { first =, last =, text = } } in
-- order; `first` takes in a "MountTrail:" label right before it.
function Share.Find(msg)
  local out = {}
  if type(msg) ~= "string" then return out end
  local from = 1
  while true do
    local first, last = string.find(msg, FIND, from)
    if not first then break end
    local text = string.sub(msg, first, last)
    local labelFirst = string.find(string.sub(msg, 1, first - 1), "[Mm][Oo][Uu][Nn][Tt][Tt][Rr][Aa][Ii][Ll]:%s*$")
    if labelFirst and labelFirst >= from then first = labelFirst end
    out[#out + 1] = { first = first, last = last, text = text }
    from = last + 1
  end
  return out
end

-- The link that stands for share string number `n` (kept by the caller).
function Share.ImportLink(n, name, count)
  return string.format("|cff3fc7eb|Haddon:MountTrail:import:%d|h[MountTrail: %s (%d)]|h|r",
    n, (string.gsub(name, "[|%[%]]", "")), count)
end

-- A clicked import link's text -> its number, or nil.
function Share.ParseImportLink(link)
  local n = type(link) == "string" and string.match(link, "^addon:MountTrail:import:(%d+)")
  return n and tonumber(n) or nil
end
