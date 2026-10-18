local ADDON, ns = ...

-- Mount tooltip, Rarity style: the mount item's own tooltip (or name +
-- flavor text when the mount has no item), then
--   "Mount [CATA]" and the kind of source ("Drops from NPC(s)", ...),
--   the client's source lines (gold label, white value) and "Dropped by
--   <boss> in <instance>" from the route when no line names the boss,
--   "1 in N chance", "Lucky if you obtain in K or less" (Logic/Odds.lua),
--   "Attempts (this character)  N" and "Total attempts  T" (Attempts.Summary:
--   kill statistics, else our per-character counters; the total also takes
--   Rarity's count when larger), "Chance so far  P%" (of T),
--   this character's lockout state, the achievement block for achievement
--   mounts (UI.AchievementLines) and the click hints.
-- The lines are built by pure helpers (UI.TooltipLines -> structured lines,
-- UI.SourceKind, UI.ExpansionTag, UI.LockoutStatus) so they can be tested
-- without a client; UI.ShowMountTooltip only paints GameTooltip.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local STATUS_TEXT = {
  saved = "Saved",
  available = "Available",
  manual = "Manual",
}

local STATE_TO_STATUS = { done = "saved", open = "available", manual = "manual" }

local WHITE = { 1, 1, 1 }
local GOLD = { 1, 0.82, 0 }
local BLUE = { 0.4, 0.78, 1 }
local GREY = { 0.6, 0.6, 0.6 }
local HINT = { 0.5, 0.9, 0.5 }
local GOLD_CODE = "|cffffd100"

local function mountData(mountID)
  local mounts = ns.Data and ns.Data.Mounts
  return mounts and mounts[mountID] or nil
end

-- This character's lockout state for the spec that governs `routeBoss` (a
-- route / checklist row's boss; default the mount's first route boss) when
-- Data.BossLockouts has one (e.g. Koralon), else the mount's own spec:
-- "saved" | "available" | "manual" | nil (not tracked).
function UI.LockoutStatus(mountID, routeBoss)
  if routeBoss == nil then routeBoss = UI.RouteBoss and UI.RouteBoss(mountID) or nil end
  local spec = ns.Lockouts.SpecFor(mountID, routeBoss)
  if not spec then return nil end
  local Game = ns.Game
  local snap = ns.Lockouts.Snapshot(Game.SavedRows())
  local state = ns.Lockouts.State(spec, snap, Game.IsQuestDone, Game.IsLfgDone)
  return STATE_TO_STATUS[state]
end

-- Short expansion tag of a Data.Expansions name ("Cataclysm" -> "CATA"),
-- nil for anything else.
local EXPANSION_TAGS = {
  ["Classic"] = "CLASSIC", ["The Burning Crusade"] = "TBC", ["Wrath of the Lich King"] = "WOTLK",
  ["Cataclysm"] = "CATA", ["Mists of Pandaria"] = "MOP", ["Warlords of Draenor"] = "WOD",
  ["Legion"] = "LEGION", ["Battle for Azeroth"] = "BFA", ["Shadowlands"] = "SL",
  ["Dragonflight"] = "DF", ["The War Within"] = "TWW", ["Midnight"] = "MID",
}

function UI.ExpansionTag(exp)
  return exp and EXPANSION_TAGS[exp] or nil
end

-- Kind-of-source line per (refined) section; holiday mounts are all
-- "Holiday event", unobtainable ones (m.unobtainable; the Misc >
-- Unobtainable section) "No longer obtainable". Sections not listed (other)
-- give no line.
local SOURCE_KINDS = {
  dungeon = "Drops from NPC(s)", raid = "Drops from NPC(s)", world = "Drops from NPC(s)",
  treasure = "Found in a treasure / cache", delve = "Delve reward", quest = "Quest reward",
  activity = "Zone activity reward", reputation = "Reputation reward", vendor = "Sold by a vendor",
  achievement = "Achievement reward", profession = "Crafted by a profession", shop = "In-game shop",
  tradingpost = "Trading Post", pvp = "PvP reward", racial = "Racial mount", keystone = "Mythic+ reward",
  promotion = "Promotion", class = "Class mount", bmah = "Black Market Auction House",
  collection = "Collection reward", limited = "Limited-time offer", unobtainable = "No longer obtainable",
}

-- The kind-of-source line of a mount -> localised text or nil. The section is
-- refined by the client's source text (Journal.SectionOf: delves, caches);
-- sourceText is a string or a function(id), optional.
function UI.SourceKind(mountID, m, sourceText)
  if type(m) ~= "table" then return nil end
  if m.unobtainable then return L[SOURCE_KINDS.unobtainable] end
  if m.tab == "holiday" then return L["Holiday event"] end
  if not m.section then return nil end
  local section = ns.Journal.SectionOf(mountID, m, sourceText)
  local kind = SOURCE_KINDS[section]
  return kind and L[kind] or nil
end

local function line(left, color, wrap)
  return { left = left, r = color[1], g = color[2], b = color[3], wrap = wrap }
end

local function double(left, right)
  return { double = true, left = left, right = right, r = GOLD[1], g = GOLD[2], b = GOLD[3],
    rr = WHITE[1], rg = WHITE[2], rb = WHITE[3] }
end

-- Source lines: one per UI.SourcePairs entry (label gold, value white), then
-- "Dropped by <boss> in <instance>" when the route has a boss for the mount
-- and no line already names it. The instance is the route step's, else the
-- source text's zone.
local function sourceLines(lines, mountID, text)
  local pairsList = UI.SourcePairs and UI.SourcePairs(text) or {}
  local zone
  for _, pair in ipairs(pairsList) do
    if pair.label then
      lines[#lines + 1] = line(GOLD_CODE .. pair.label .. "|r " .. pair.value, WHITE, true)
      if not zone and UI.SourceLabelKind(pair.label) == "zone" then zone = pair.value end
    else
      lines[#lines + 1] = line(pair.value, WHITE, true)
    end
  end
  local entry = UI.RouteEntry and UI.RouteEntry(mountID) or nil
  local boss = entry and entry.boss
  if type(boss) ~= "string" or boss == "" then return end
  local needle = string.lower(boss)
  for _, pair in ipairs(pairsList) do
    if string.find(string.lower(pair.value), needle, 1, true) then return end
  end
  local where = entry.instance or zone
  if where then
    lines[#lines + 1] = line(string.format(L["Dropped by %s in %s"], boss, where), WHITE, true)
  else
    lines[#lines + 1] = line(string.format(L["Dropped by %s"], boss), WHITE, true)
  end
end

-- { this =, total = } attempts on the mount (Attempts.Summary over the
-- saved statistics, our per-character counters, the legacy account-wide
-- counter and Rarity's count when readable).
local function attempts(mountID, m)
  local global = ns.db and ns.db.global or {}
  local rarity
  if m.item and ns.RarityBridge then rarity = ns.RarityBridge.Attempts(m.item) end
  return ns.Attempts.Summary(mountID, {
    charKey = ns.Game.CharKey(),
    hasStats = m.stats ~= nil and ns.Stats ~= nil,
    stats = global.stats,
    byChar = global.attemptsByChar,
    legacy = global.attempts,
    rarity = rarity,
  })
end

-- Whether attempts are worth showing for a mount: it has a drop chance,
-- kill statistics, or a lockout spec (Lockouts.SpecFor, incl. the route
-- boss's BossLockouts; `routeBoss` as UI.LockoutStatus). Shop / vendor /
-- profession mounts have none.
function UI.IsTracked(mountID, m, routeBoss)
  m = m or mountData(mountID) or {}
  if (type(m.chance) == "number" and m.chance > 0) or m.stats then return true end
  if routeBoss == nil then routeBoss = UI.RouteBoss and UI.RouteBoss(mountID) or nil end
  return ns.Lockouts.SpecFor(mountID, routeBoss) ~= nil
end

-- -> the tooltip's lines after the item tooltip / name + flavor, in order,
-- each { left =, r =, g =, b = [, wrap = true] } or, for the two Attempts
-- lines and "Chance so far", { double = true, left =, right =, r, g, b (left colour),
-- rr, rg, rb (right colour) }. See the file header for the order.
-- `routeBoss` (optional): the hovered route / checklist row's boss, whose
-- lockout the "Lockout:" line reports (UI.LockoutStatus).
function UI.TooltipLines(mountID, routeBoss)
  local m = mountData(mountID) or {}
  local lines = {}

  local tag = UI.ExpansionTag(m.exp)
  lines[#lines + 1] = line(tag and (L["Mount"] .. " " .. GOLD_CODE .. "[" .. tag .. "]|r") or L["Mount"], WHITE)
  local text = ns.Game.MountSourceText and ns.Game.MountSourceText(mountID) or nil
  local kind = UI.SourceKind(mountID, m, text)
  if kind then lines[#lines + 1] = line(kind, BLUE) end
  sourceLines(lines, mountID, text)

  local n = (type(m.chance) == "number" and m.chance > 0) and math.max(1, math.floor(m.chance + 0.5)) or nil
  if n then
    lines[#lines + 1] = line(string.format(L["1 in %d chance"], n), WHITE)
    lines[#lines + 1] = line(string.format(L["Lucky if you obtain in %d or less"], ns.Odds.LuckyBy(n)), GREY)
  end
  if UI.IsTracked(mountID, m, routeBoss) then
    local counts = attempts(mountID, m)
    lines[#lines + 1] = double(L["Attempts (this character)"], tostring(counts.this))
    lines[#lines + 1] = double(L["Total attempts"], tostring(counts.total))
    if n then
      lines[#lines + 1] = double(L["Chance so far"], ns.Odds.Percent(ns.Odds.ChanceSoFar(n, counts.total)))
    end
  end

  local status = UI.LockoutStatus(mountID, routeBoss)
  lines[#lines + 1] = line(string.format(L["Lockout: %s"], L[STATUS_TEXT[status] or "—"]), GOLD)

  local achievementLines, achievementID = UI.AchievementLines(mountID)
  for _, a in ipairs(achievementLines) do
    lines[#lines + 1] = { left = a.text, r = a.r, g = a.g, b = a.b, wrap = a.wrap }
  end
  lines[#lines + 1] = line(L["Click: waypoint · Shift-click: map · Ctrl-click: preview"], HINT)
  if achievementID then
    lines[#lines + 1] = line(L["Shift-right-click to open the achievement"], HINT)
  end
  return lines
end

-- Achievement block for achievement mounts (Achievements.TooltipLines of
-- the achievement the scan mapped the mount to; "looking up..." while the
-- scan runs) -> lines { { text=, r=, g=, b=, wrap= } }, achievementID or nil.
-- Other mounts and mounts without a match -> {}.
function UI.AchievementLines(mountID)
  local scan = ns.AchievementScan
  if not (scan and mountID) then return {} end
  local id, status = scan.Lookup(mountID)
  if status == "pending" then
    return { { text = L["Achievement: looking up..."], r = GREY[1], g = GREY[2], b = GREY[3] } }
  end
  if not id then return {} end
  local info = ns.Game.AchievementInfo and ns.Game.AchievementInfo(id) or nil
  return ns.Achievements.TooltipLines(info), id
end

-- The mount's flavor text from the client's Mount Journal, or nil.
function UI.TooltipFlavor(mountID)
  local describe = ns.Game.MountDescription
  return describe and describe(mountID) or nil
end

-- Shows the mount tooltip anchored to `owner` (a list row). Mounts taught by
-- an item show that item's own tooltip (as when hovering the Reins in your
-- bags); others show the name and the wrapped flavor text. UI.TooltipLines
-- follow either way (double lines via AddDoubleLine; one joined line when the
-- tooltip has none). When the item's data is not cached yet, the client
-- rebuilds the item tooltip once it arrives, wiping our lines: we wait for
-- the data (Game.OnItemLoad) and repaint a frame later (C_Timer.After(0)),
-- once per owner and mount, and
-- never for an item that has loaded before.
local shownOwner, shownMount, shownBoss
local waiting = {} -- owner -> { [mountID] = true } while a callback is pending
local loadedItems = {} -- itemID -> true once a callback ran

-- Repaints the tooltip when it still shows `owner` (or, without one, whatever
-- row it shows). List rows are recycled, so the row's current mountID wins
-- over the one it was shown for.
local function repaint(owner)
  local tip = GameTooltip
  if not (shownOwner and tip and tip.IsOwned and tip:IsOwned(shownOwner)) then return end
  if owner ~= nil and owner ~= shownOwner then return end
  -- A list row carries its mount and route boss; other owners (route rows)
  -- keep what they were shown with.
  local row = type(shownOwner) == "table" and shownOwner.mountID ~= nil
  local mountID = row and shownOwner.mountID or shownMount
  local boss = row and shownOwner.routeBoss or shownBoss
  UI.ShowMountTooltip(shownOwner, mountID, boss)
end

local function waitForItem(owner, mountID, item)
  if loadedItems[item] or ns.Game.ItemCached(item) ~= false then return end
  local forOwner = waiting[owner]
  if forOwner and forOwner[mountID] then return end
  forOwner = forOwner or {}
  forOwner[mountID] = true
  waiting[owner] = forOwner
  local registered = ns.Game.OnItemLoad(item, function()
    loadedItems[item] = true
    forOwner[mountID] = nil
    if next(forOwner) == nil and waiting[owner] == forOwner then waiting[owner] = nil end
    -- The client rebuilds the item tooltip on the same event: repaint a
    -- frame later so ours comes last.
    local timer = C_Timer
    if type(timer) == "table" and type(timer.After) == "function" then
      timer.After(0, function() repaint(owner) end)
    else
      repaint(owner)
    end
  end)
  if not registered then
    forOwner[mountID] = nil
    loadedItems[item] = true -- no mixin / error: do not try again
  end
end

-- `routeBoss` (optional): the route / checklist row's boss (the lockout
-- line follows that boss's spec: UI.TooltipLines).
function UI.ShowMountTooltip(owner, mountID, routeBoss)
  local tip = GameTooltip
  if not (tip and mountID) then return end
  shownOwner, shownMount, shownBoss = owner, mountID, routeBoss
  local m = mountData(mountID) or {}
  local lines = UI.TooltipLines(mountID, routeBoss)
  tip:SetOwner(owner, "ANCHOR_RIGHT")
  if m.item and tip.SetItemByID then
    tip:SetItemByID(m.item)
    tip:AddLine(" ")
  else
    local name = ns.Game.MountInfo(mountID)
    tip:SetText(name or m.name or tostring(mountID), 1, 1, 1)
    local flavor = UI.TooltipFlavor(mountID)
    if flavor then
      tip:AddLine(flavor, 0.9, 0.9, 0.9, true)
    end
  end
  for _, l in ipairs(lines) do
    if l.double and tip.AddDoubleLine then
      tip:AddDoubleLine(l.left, l.right, l.r, l.g, l.b, l.rr, l.rg, l.rb)
    elseif l.double then
      tip:AddLine(l.left .. "  " .. l.right, l.r, l.g, l.b)
    else
      tip:AddLine(l.left, l.r, l.g, l.b, l.wrap)
    end
  end
  tip:Show()
  if m.item and tip.SetItemByID and ns.Game.ItemCached and ns.Game.OnItemLoad then
    waitForItem(owner, mountID, m.item)
  end
end

-- Repaints the mount tooltip if it is still showing (the achievement scan
-- finished while the row was hovered).
function UI.OnAchievementsReady()
  repaint(nil)
end

if ns.AchievementScan then
  ns.AchievementScan.OnDone(function() UI.OnAchievementsReady() end)
end

function UI.HideMountTooltip()
  shownOwner, shownMount, shownBoss = nil, nil, nil
  if GameTooltip_Hide then
    GameTooltip_Hide()
  elseif GameTooltip then
    GameTooltip:Hide()
  end
end
