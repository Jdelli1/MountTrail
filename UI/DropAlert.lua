local ADDON, ns = ...

-- When the player gets a mount MountTrail tracks (one with a drop chance,
-- kill statistics or a lockout: UI.IsTracked), a chat line says how long the
-- grind took: "Invincible collected after 87 attempts (1 in 100: luckier
-- than 42% of players)". With the "Chime when a mount drops" option on (off
-- by default: the game shows its own banner, AllTheThings plays its own
-- fanfare) a sound of the player's choice plays too (UI.DROP_SOUNDS, the
-- game's own sounds).
-- The moment is the drop: the mount's item arriving in the bags (a bag
-- check on BAG_UPDATE_DELAYED, the same in raids, Mythic+ and the open world;
-- chat is not read). A mount with no item, or learned straight away, alerts
-- when learned (Core/Init.lua calls UI.OnMountLearned on NEW_MOUNT_ADDED);
-- a mount already announced at its drop stays quiet then. An item bought or
-- mailed counts as a drop too.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

-- The sounds offered, the game's (SOUNDKIT names); only those the client
-- has are listed (UI.DropSounds). The first is the default.
UI.DROP_SOUNDS = {
  { key = "UI_EPICLOOT_TOAST", label = "Epic loot" },
  { key = "UI_LEGENDARY_LOOT_TOAST", label = "Legendary loot" },
  { key = "UI_WORLDQUEST_COMPLETE", label = "World quest complete" },
  { key = "IG_QUEST_LIST_COMPLETE", label = "Quest complete" },
  { key = "READY_CHECK", label = "Ready check" },
  { key = "RAID_WARNING", label = "Raid warning" },
  { key = "ALARM_CLOCK_WARNING_3", label = "Alarm clock" },
}

-- The sounds this client has -> { { key =, label = } }.
function UI.DropSounds()
  local out = {}
  for _, s in ipairs(UI.DROP_SOUNDS) do
    if ns.Game.HasSoundKit(s.key) then out[#out + 1] = s end
  end
  return out
end

-- The chat line for a learned mount -> text, or nil for a mount MountTrail
-- does not track. attempts: { this =, total = } (UI.MountAttempts); m: the
-- mount's data (its `chance`: 1 in N).
function UI.DropMessage(name, m, attempts)
  local total = attempts and attempts.total or 0
  if total <= 0 then return string.format(L["%s collected!"], name) end
  local text = string.format(L["%s collected after %d attempts"], name, total)
  local chance = m and m.chance
  local soFar = ns.Odds and ns.Odds.ChanceSoFar(chance, total)
  if soFar then
    -- The share of players still without it after as many attempts.
    local luckier = math.floor((1 - soFar) * 100 + 0.5)
    text = text .. " " .. string.format(L["(1 in %d: luckier than %d%% of players)"], chance, luckier)
  end
  return text
end

local announced = {} -- mountID -> true once alerted this session (drop or learned)

-- The line and, when chosen, the chime, once per mount and session.
local function alert(mountID, m)
  if announced[mountID] then return end
  announced[mountID] = true
  local name = ns.Game.MountInfo(mountID) or m.name or tostring(mountID)
  local attempts = UI.MountAttempts and UI.MountAttempts(mountID, m) or nil
  if ns.addon and ns.addon.Print then ns.addon:Print(UI.DropMessage(name, m, attempts)) end
  local options = ns.Options
  if options and options.DropChime and options.DropChime() then
    ns.Game.PlaySoundKit(options.DropSound())
  end
end

local function tracked(mountID)
  local m = ns.Data and ns.Data.Mounts and ns.Data.Mounts[mountID]
  if m and UI.IsTracked and UI.IsTracked(mountID, m) then return m end
  return nil
end

-- NEW_MOUNT_ADDED: the alert, unless the mount's drop already gave it.
function UI.OnMountLearned(mountID)
  local m = tracked(mountID)
  if m then alert(mountID, m) end
end

-- The bag check. watch: itemID -> mountID for the tracked mounts not owned
-- (built on the first check, again after a mount is learned); counts: the
-- last count of each item (the first check only records them, so items
-- already in the bags at login never alert).
local watch, counts

local function buildWatch()
  watch = {}
  for id, m in pairs(ns.Data and ns.Data.Mounts or {}) do
    if m.item and not ns.Game.IsOwned(id) and tracked(id) then watch[m.item] = id end
  end
end

-- BAG_UPDATE_DELAYED: a watched item whose count goes up is a drop.
function UI.CheckBagsForMounts()
  if not watch then buildWatch() end
  local first = counts == nil
  counts = counts or {}
  for itemID, mountID in pairs(watch) do
    local n = ns.Game.ItemCount(itemID)
    if not first and n > (counts[itemID] or 0) then alert(mountID, ns.Data.Mounts[mountID]) end
    counts[itemID] = n
  end
end

-- Forget the watch list (a mount was learned) and the session's state (tests).
function UI.ForgetDropWatch(all)
  watch = nil
  if all then counts, announced = nil, {} end
end

local events = CreateFrame("Frame")
events:RegisterEvent("BAG_UPDATE_DELAYED")
events:RegisterEvent("NEW_MOUNT_ADDED")
events:SetScript("OnEvent", function(_, event)
  if event == "NEW_MOUNT_ADDED" then
    UI.ForgetDropWatch()
    return
  end
  if not ns.db then return end
  local good, err = pcall(UI.CheckBagsForMounts)
  if not good and ns.Game.ReportError then ns.Game.ReportError(err) end
end)
