local ADDON, ns = ...

-- Sharing custom lists (Logic/Share.lua has the format):
--   * Export: the list as a !MT1! string in a box to copy; Import pastes one.
--   * Share in chat: a WeakAuras-style link. Clicking it whispers the sharer's
--     MountTrail (addon messages), which answers with the list; the clicker
--     is then asked to import it. Only lists this character linked or sent
--     this session answer, so nobody can fetch the others.
--   * Send to player: whispers the list straight to someone, who is asked
--     whether to import it.
-- Every import asks first and takes the name the player confirms.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local PREFIX = "MountTrail" -- addon-message prefix (16 characters at most)
local REQUEST_TIMEOUT = 10 -- seconds to wait for a link's answer
local SEND_GAP = 0.1 -- seconds between chunks, clear of the game's throttle

local shared = {} -- list IDs this character linked or sent this session
local waiting = {} -- sender -> true while a link's answer is due
local assembler

local function say(msg)
  if ns.addon and ns.addon.Print then ns.addon:Print(msg) end
end

local function store()
  return UI.ListsDB and UI.ListsDB()
end

local function later(seconds, fn)
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(seconds, fn)
  else
    fn()
  end
end

-- The list's share string, or nil for an unknown list.
function UI.ListShareString(id)
  local s = store()
  local l = s and ns.Lists.Get(s, id)
  if not l then return nil end
  return ns.Share.Encode(l.name, l.mounts), l
end

-- Imports a decoded list under `name` (a free one: "name (2)" when taken) -> its id.
local function create(decoded, name)
  local s = store()
  if not s then return nil end
  local id = ns.Lists.Create(s, ns.Share.FreeName(s, name or decoded.name))
  if not id then return nil end
  for _, mountID in ipairs(decoded.mounts) do ns.Lists.Add(s, id, mountID) end
  local l = ns.Lists.Get(s, id)
  say(string.format(L["Imported %s (%d mounts)."], l.name, #decoded.mounts))
  ns.Refresh()
  return id
end

local ERRORS = {
  format = "That is not a MountTrail list.",
  damaged = "That list is cut off or changed: copy the whole line again.",
  empty = "That list has no mounts this version knows.",
}

-- Asks whether to import `decoded` (from `from`, optional), its name editable.
function UI.OfferImport(decoded, from)
  local title = from and string.format(L["%s shared a list (%d mounts)"], from, #decoded.mounts)
    or string.format(L["Import a list (%d mounts)"], #decoded.mounts)
  UI.AskText(title, decoded.name, function(name) create(decoded, name) end,
    { okLabel = L["Import"], hint = L["Name it, then Import."] })
end

-- A pasted string -> decoded list, or nil and the message to show.
function UI.DecodeShare(text)
  local decoded, err = ns.Share.Decode(text, ns.Data and ns.Data.Mounts)
  if not decoded then return nil, L[ERRORS[err] or ERRORS.format] end
  return decoded
end

-- Export: the list's string, selected, in a box to copy.
function UI.ExportList(id)
  local text, l = UI.ListShareString(id)
  if not text then return end
  UI.ShowCopyText(string.format(L["Export %s"], l.name), text,
    L["Ctrl+C to copy. Anyone with MountTrail can import it."])
end

-- Import: a box to paste a string into, then the usual question.
function UI.ImportListPrompt()
  UI.AskText(L["Import a list"], "", function(text)
    local decoded, msg = UI.DecodeShare(text)
    if not decoded then
      say(msg)
      return
    end
    -- After this prompt closes: the question reuses the same box.
    later(0, function() UI.OfferImport(decoded) end)
  end, { okLabel = L["Next"], hint = L["Paste a MountTrail list (!MT1!...)."], long = true })
end

-- Whispers list `id` to `target` in chunks ("D" answers a link, "O" offers).
-- -> false when the game refused the first chunk.
function UI.SendList(id, target, kind)
  local text = UI.ListShareString(id)
  if not (text and target and target ~= "") then return false end
  shared[id] = true
  local parts = ns.Share.Chunks(kind or "O", text)
  if not ns.Game.SendAddonWhisper(PREFIX, parts[1], target) then
    say(string.format(L["Could not send the list to %s right now."], target))
    return false
  end
  for i = 2, #parts do
    later((i - 1) * SEND_GAP, function() ns.Game.SendAddonWhisper(PREFIX, parts[i], target) end)
  end
  if kind ~= "D" then say(string.format(L["Sent to %s. They need MountTrail to receive it."], target)) end
  return true
end

function UI.SendListPrompt(id)
  UI.AskText(L["Send the list to"], "", function(target) UI.SendList(id, target, "O") end,
    { okLabel = L["Send"], hint = L["A player's name (Name-Realm from another realm)."] })
end

-- Share in chat: the list's !MT1! line into the chat box (MountTrail users
-- see it as a link to click). A list too long for one message goes as a
-- link that asks this character's MountTrail for it instead.
function UI.ShareListInChat(id)
  local text, l = UI.ListShareString(id)
  if not text then return false end
  shared[id] = true
  local name = string.gsub(l.name, "[|%[%]]", "")
  local line = text
  if #line > ns.Share.CHAT_MAX then line = ns.Share.Link(ns.Game.CharKey(), id, name) end
  if not ns.Game.InsertChatLink(line) then
    say(L["Open a chat box first, then Share in chat."])
    return false
  end
  return true
end

-- A clicked link: ask the sharer for the list (one's own link: offer a copy).
function UI.RequestSharedList(sender, id)
  if sender == ns.Game.CharKey() then
    local text = UI.ListShareString(id)
    local decoded = text and ns.Share.Decode(text, ns.Data and ns.Data.Mounts)
    if decoded then UI.OfferImport(decoded) end
    return
  end
  if not ns.Game.SendAddonWhisper(PREFIX, "R" .. id, sender) then
    say(string.format(L["Could not reach %s right now."], sender))
    return
  end
  waiting[sender] = true
  say(string.format(L["Asking %s for the list..."], sender))
  -- Give up after a while (only with a timer: without one it would fire at once).
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(REQUEST_TIMEOUT, function()
      if waiting[sender] then
        waiting[sender] = nil
        say(string.format(L["No answer from %s: they need MountTrail and must be online."], sender))
      end
    end)
  end
end

-- An addon message on our prefix.
function UI.OnShareMessage(msg, sender)
  local kind, a = ns.Share.Parse(msg)
  if kind == "R" then
    -- Only lists shared this session answer.
    if shared[a] then UI.SendList(a, sender, "D") end
    return
  end
  assembler = assembler or ns.Share.Assembler()
  local text, got = assembler:Add(sender, msg)
  if not text then return end
  if got == "D" then
    if not waiting[sender] then return end -- an answer nobody asked for
    waiting[sender] = nil
  end
  local decoded, err = UI.DecodeShare(text)
  if decoded then
    UI.OfferImport(decoded, sender)
  else
    say(err)
  end
end

-- Wiring ---------------------------------------------------------------------------

local status = { prefix = ns.Game.RegisterAddonPrefix(PREFIX), filters = 0, clicks = {} }

local events = CreateFrame("Frame")
events:RegisterEvent("CHAT_MSG_ADDON")
events:SetScript("OnEvent", function(_, _, prefix, msg, _, sender)
  if prefix == PREFIX then UI.OnShareMessage(msg, sender) end
end)

-- Share strings in chat -> links ------------------------------------------------
-- The chat filter swaps each !MT1! line for a link on this screen only; the
-- link's number points into chatLines. Clicking it offers the import.

local chatLines, chatCount = {}, 0
local KEEP = 200 -- links older than this many lines are forgotten

-- A chat message with its share strings as links -> the new text, or nil
-- when it has none (or none that decode).
function UI.LinkShareStrings(msg)
  if ns.Game.IsSecret(msg) or type(msg) ~= "string" or not string.find(msg, "!MT1!", 1, true) then return nil end
  local found = ns.Share.Find(msg)
  if #found == 0 then return nil end
  local out, from, changed = {}, 1, false
  for _, f in ipairs(found) do
    local decoded = ns.Share.Decode(f.text, ns.Data and ns.Data.Mounts)
    if decoded then
      chatCount = chatCount + 1
      chatLines[chatCount] = f.text
      chatLines[chatCount - KEEP] = nil
      out[#out + 1] = string.sub(msg, from, f.first - 1)
      out[#out + 1] = ns.Share.ImportLink(chatCount, decoded.name, #decoded.mounts)
      from = f.last + 1
      changed = true
    end
  end
  if not changed then return nil end
  out[#out + 1] = string.sub(msg, from)
  return table.concat(out)
end

-- A clicked link of ours (either kind) -> true when it was ours.
function UI.OnShareLink(link)
  local n = ns.Share.ParseImportLink(link)
  if n then
    local decoded = chatLines[n] and UI.DecodeShare(chatLines[n])
    if decoded then
      UI.OfferImport(decoded)
    else
      say(L["That list link is too old: ask for it again."])
    end
    return true
  end
  local sender, id = ns.Share.ParseLink(link)
  if sender then
    UI.RequestSharedList(sender, id)
    return true
  end
  return false
end

local function chatFilter(_, _, msg, ...)
  local good, linked = pcall(UI.LinkShareStrings, msg)
  if good and linked then return false, linked, ... end
  return false
end

for _, event in ipairs({ "CHAT_MSG_SAY", "CHAT_MSG_YELL", "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM",
  "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM", "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
  "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING", "CHAT_MSG_INSTANCE_CHAT",
  "CHAT_MSG_INSTANCE_CHAT_LEADER", "CHAT_MSG_GUILD", "CHAT_MSG_OFFICER", "CHAT_MSG_CHANNEL",
  "CHAT_MSG_COMMUNITIES_CHANNEL" }) do
  if ns.Game.AddChatFilter(event, chatFilter) then status.filters = status.filters + 1 end
end

-- Clicks: the "addon" link type is handed to addons (EventRegistry's
-- SetItemRef); older clients only let a hook on SetItemRef see it. Either
-- way one click is handled once.
local lastClick
local function onClick(link)
  local now = type(GetTime) == "function" and GetTime() or nil
  if now and lastClick and lastClick.link == link and lastClick.at == now then return end
  lastClick = { link = link, at = now }
  UI.OnShareLink(link)
end
if type(EventRegistry) == "table" and type(EventRegistry.RegisterCallback) == "function" then
  if pcall(EventRegistry.RegisterCallback, EventRegistry, "SetItemRef", function(_, link) onClick(link) end, UI) then
    status.clicks[#status.clicks + 1] = "EventRegistry"
  end
end
if type(hooksecurefunc) == "function" and type(SetItemRef) == "function" then
  hooksecurefunc("SetItemRef", function(link) onClick(link) end)
  status.clicks[#status.clicks + 1] = "SetItemRef hook"
end

-- /mtrail sharetest: what sharing could set up on this client, then a list
-- line shown in the chat window as its link (nothing is sent) to click.
function UI.ShareSelfTest()
  say(string.format(L["Sharing: addon messages %s, chat filters %d, clicks via %s."],
    status.prefix and L["on"] or L["off"], status.filters,
    #status.clicks > 0 and table.concat(status.clicks, ", ") or L["nothing"]))
  local s = store()
  local first = s and ns.Lists.Sorted(s)[1]
  local text = first and UI.ListShareString(first.id) or ns.Share.Encode("Test", { 1 })
  local linked = UI.LinkShareStrings(text)
  local frame = DEFAULT_CHAT_FRAME
  if frame and frame.AddMessage then
    frame:AddMessage(L["MountTrail test (only you see this): "] .. (linked or text))
  end
  if not linked then say(L["The test line did not turn into a link."]) end
end
