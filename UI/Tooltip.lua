local ADDON, ns = ...

-- Mount tooltip: the mount item's own tooltip (or name + flavor text when the
-- mount has no item), then approximate drop rate, times farmed (ours, plus
-- Rarity's when readable), this character's lockout state and a preview hint.
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

-- -> { name, ["~1 in N (approx.)"], "Times farmed: N", ["Rarity: N"],
--      "Lockout: <state>", "Ctrl-click to preview" }
function UI.TooltipLines(mountID)
  local m = mountData(mountID) or {}
  local name = ns.Game.MountInfo(mountID)
  local lines = { name or m.name or tostring(mountID) }

  if type(m.chance) == "number" and m.chance > 0 then
    local n = math.max(1, math.floor(m.chance + 0.5))
    lines[#lines + 1] = string.format(L["~1 in %d (approx.)"], n)
  end

  local store = ns.db and ns.db.global and ns.db.global.attempts or {}
  lines[#lines + 1] = string.format(L["Times farmed: %d"], ns.Attempts.Get(store, mountID))

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

-- The mount's flavor text from the client's Mount Journal, or nil.
function UI.TooltipFlavor(mountID)
  local describe = ns.Game.MountDescription
  return describe and describe(mountID) or nil
end

-- Shows the mount tooltip anchored to `owner` (a list row). Mounts taught by
-- an item show that item's own tooltip (as when hovering the Reins in your
-- bags); others show the name and the wrapped flavor text. The farming lines
-- follow either way.
function UI.ShowMountTooltip(owner, mountID)
  local tip = GameTooltip
  if not (tip and mountID) then return end
  local lines = UI.TooltipLines(mountID)
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
  tip:AddLine(lines[#lines], 0.5, 0.9, 0.5)
  tip:Show()
end

function UI.HideMountTooltip()
  if GameTooltip_Hide then
    GameTooltip_Hide()
  elseif GameTooltip then
    GameTooltip:Hide()
  end
end
