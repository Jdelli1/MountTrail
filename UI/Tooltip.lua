local ADDON, ns = ...

-- Mount tooltip: the mount item's own tooltip (or name + flavor text when the
-- mount has no item), then approximate drop rate, kills from the game's
-- statistics (Logic/Stats.lua) or else times farmed (ours), Rarity's count
-- when readable, this character's lockout state, for achievement
-- mounts the achievement with its criteria, and the click hints.
-- The text is built by pure helpers (UI.TooltipLines, UI.LockoutStatus) so it
-- can be tested without a client; UI.ShowMountTooltip only paints GameTooltip.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local STATUS_TEXT = {
  saved = "Saved",
  available = "Available",
  manual = "Manual",
}

local STATE_TO_STATUS = { done = "saved", open = "available", manual = "manual" }

local function mountData(mountID)
  local mounts = ns.Data and ns.Data.Mounts
  return mounts and mounts[mountID] or nil
end

-- This character's lockout state for the spec that governs the mount's first
-- route boss (Data.BossLockouts, e.g. Koralon), else the mount's own spec:
-- "saved" | "available" | "manual" | nil (not tracked).
function UI.LockoutStatus(mountID)
  local routeBoss = UI.RouteBoss and UI.RouteBoss(mountID) or nil
  local spec = ns.Lockouts.SpecFor(mountID, routeBoss)
  if not spec then return nil end
  local Game = ns.Game
  local snap = ns.Lockouts.Snapshot(Game.SavedRows())
  local state = ns.Lockouts.State(spec, snap, Game.IsQuestDone, Game.IsLfgDone)
  return STATE_TO_STATUS[state]
end

-- -> { name, ["~1 in N (approx.)"], "Kills: N (this character: M)" or
--      "Times farmed: N", ["Rarity: N"], "Lockout: <state>",
--      "Ctrl-click to preview" }
function UI.TooltipLines(mountID)
  local m = mountData(mountID) or {}
  local name = ns.Game.MountInfo(mountID)
  local lines = { name or m.name or tostring(mountID) }

  if type(m.chance) == "number" and m.chance > 0 then
    local n = math.max(1, math.floor(m.chance + 0.5))
    lines[#lines + 1] = string.format(L["~1 in %d (approx.)"], n)
  end

  -- Mounts with kill statistics show those (every character, and this one);
  -- the rest, and those not read yet, show our attempt counter.
  local global = ns.db and ns.db.global or {}
  local kills = m.stats and ns.Stats and ns.Stats.Line(global.stats, mountID, ns.Game.CharKey()) or nil
  lines[#lines + 1] = kills
    or string.format(L["Times farmed: %d"], ns.Attempts.Get(global.attempts or {}, mountID))

  if m.item and ns.RarityBridge then
    local rarity = ns.RarityBridge.Attempts(m.item)
    if type(rarity) == "number" then
      lines[#lines + 1] = string.format(L["Rarity: %d"], rarity)
    end
  end

  local status = UI.LockoutStatus(mountID)
  lines[#lines + 1] = string.format(L["Lockout: %s"], L[STATUS_TEXT[status] or "—"])
  lines[#lines + 1] = L["Ctrl-click to preview"]
  return lines
end

local GREY = { 0.6, 0.6, 0.6 }

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
-- bags); others show the name and the wrapped flavor text. The farming lines,
-- the achievement block (UI.AchievementLines) and the hints follow either way.
local shownOwner, shownMount

function UI.ShowMountTooltip(owner, mountID)
  local tip = GameTooltip
  if not (tip and mountID) then return end
  shownOwner, shownMount = owner, mountID
  local lines = UI.TooltipLines(mountID)
  local achievementLines, achievementID = UI.AchievementLines(mountID)
  local item = (mountData(mountID) or {}).item
  tip:SetOwner(owner, "ANCHOR_RIGHT")
  if item and tip.SetItemByID then
    tip:SetItemByID(item)
    tip:AddLine(" ")
  else
    tip:SetText(lines[1], 1, 1, 1)
    local flavor = UI.TooltipFlavor(mountID)
    if flavor then
      tip:AddLine(flavor, 0.9, 0.9, 0.9, true)
    end
  end
  for i = 2, #lines - 1 do
    tip:AddLine(lines[i], 1, 0.82, 0)
  end
  for _, line in ipairs(achievementLines) do
    tip:AddLine(line.text, line.r, line.g, line.b, line.wrap)
  end
  tip:AddLine(lines[#lines], 0.5, 0.9, 0.5)
  if achievementID then
    tip:AddLine(L["Shift-right-click to open the achievement"], 0.5, 0.9, 0.5)
  end
  tip:Show()
end

-- Repaints the mount tooltip if it is still showing (the achievement scan
-- finished while the row was hovered). List rows are recycled, so the row's
-- current mountID wins over the one it was shown for.
function UI.OnAchievementsReady()
  local tip = GameTooltip
  if not (shownOwner and tip and tip.IsOwned and tip:IsOwned(shownOwner)) then return end
  local mountID = type(shownOwner) == "table" and shownOwner.mountID or shownMount
  UI.ShowMountTooltip(shownOwner, mountID)
end

if ns.AchievementScan then
  ns.AchievementScan.OnDone(function() UI.OnAchievementsReady() end)
end

function UI.HideMountTooltip()
  shownOwner, shownMount = nil, nil
  if GameTooltip_Hide then
    GameTooltip_Hide()
  elseif GameTooltip then
    GameTooltip:Hide()
  end
end
