local ADDON, ns = ...

-- When the player learns a mount MountTrail tracks (one with a drop chance,
-- kill statistics or a lockout: UI.IsTracked), a chat line says how long the
-- grind took: "Invincible collected after 87 attempts (1 in 100: luckier
-- than 42% of players)". With the "Chime when a mount drops" option on (off
-- by default: the game shows its own banner, AllTheThings plays its own
-- fanfare) a sound of the player's choice plays too (UI.DROP_SOUNDS, the
-- game's own sounds). Core/Init.lua calls UI.OnMountLearned on
-- NEW_MOUNT_ADDED.

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

-- NEW_MOUNT_ADDED: the line, and the chime when chosen.
function UI.OnMountLearned(mountID)
  local m = ns.Data and ns.Data.Mounts and ns.Data.Mounts[mountID]
  if not (m and UI.IsTracked and UI.IsTracked(mountID, m)) then return end
  local name = ns.Game.MountInfo(mountID) or m.name or tostring(mountID)
  local attempts = UI.MountAttempts and UI.MountAttempts(mountID, m) or nil
  if ns.addon and ns.addon.Print then ns.addon:Print(UI.DropMessage(name, m, attempts)) end
  local options = ns.Options
  if options and options.DropChime and options.DropChime() then
    ns.Game.PlaySoundKit(options.DropSound())
  end
end
