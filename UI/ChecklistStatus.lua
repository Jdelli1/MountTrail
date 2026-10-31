local ADDON, ns = ...

-- The Lockouts view's live status for event rares (F17): the light-blue lines
-- of the N'Zoth assaults and the Arathi / Darkshore warfronts
-- (UI.EventStatusTexts over Logic/Events.lua, cached and redrawn on
-- UI.EventStatusChanged), the row / header status (UI.ChecklistStatusOf,
-- UI.ChecklistStatusDesc) and the "status unknown" click that opens the event
-- zone's map (UI.ChecklistEventMap, UI.OpenEventMap). Split out of
-- UI/ChecklistView.lua, which calls these at run time only; unit-tested in
-- tests/ui_checklist_spec.lua. No user-facing strings of its own (the lines
-- come from Logic/Events.lua), so no `local L = ns.L`.

local UI = ns.UI or {}
ns.UI = UI

local DOT = " \194\183 " -- " · "

-- Event rares' live status (F17) -------------------------------------------------
-- Rows whose mount is in a Data/Events.lua group (N'Zoth assaults in Uldum
-- and the Vale, the Arathi / Darkshore warfronts) get that group's line from
-- Logic/Events.lua; a header whose open entries all share one shows it too
-- (Checklist.Rows opts.status). Read through the Game wrappers at most once
-- a minute, sooner when the game reports a change (AREA_POIS_UPDATED,
-- CONTRIBUTION_COLLECTOR_UPDATE: UI.EventStatusChanged, Core/Init.lua).

local STATUS_TTL = 60 -- seconds a read stays fresh
local STATUS_THROTTLE = 2 -- seconds between redraws for reported changes
local STATUS_COLOR = "|cff71d5ff" -- light blue: information, not a done / open state
local statusCache = { texts = nil, at = nil }
local redrawPending = false

-- { [group key] = line } at `now` (default Game.Now()), cached for a minute.
function UI.EventStatusTexts(now)
  local Game = ns.Game
  now = now or Game.Now()
  local at = statusCache.at
  if statusCache.texts and at and now >= at and now - at < STATUS_TTL then return statusCache.texts end
  statusCache.texts = ns.Events.Statuses(ns.Data and ns.Data.EventGroups, {
    poisForMap = Game.AreaPOIsForMap,
    poiInfo = Game.AreaPOIInfo,
    secondsLeft = Game.AreaPOISecondsLeft,
    contributionsForMap = Game.ContributionsForMap,
    formatDuration = UI.FormatDuration,
  })
  statusCache.at = now
  return statusCache.texts
end

-- The game reported a change: the next read is fresh, and the checklist (when
-- on screen) redraws once within STATUS_THROTTLE seconds, however many events
-- arrive (AREA_POIS_UPDATED fires often).
function UI.EventStatusChanged()
  statusCache.texts = nil
  if redrawPending then return end
  redrawPending = true
  local function redraw()
    redrawPending = false
    local checklist = UI.ChecklistView
    if checklist and checklist.IsShown() then checklist.Refresh() end
  end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    C_Timer.After(STATUS_THROTTLE, redraw)
  else
    redraw()
  end
end

-- Checklist.Rows opts.status over `texts` (UI.EventStatusTexts): an entry's
-- line by its mount's event group, nil for other entries.
function UI.ChecklistStatusOf(texts)
  local groups = ns.Data and ns.Data.EventGroups
  return function(entry)
    local key = ns.Events.GroupOf(entry and entry.m, groups)
    return key and texts and texts[key] or nil
  end
end

-- The UiMap a click on this entry's row opens: its event zone while the
-- group's line reads "status unknown", else nil (the normal waypoint click).
function UI.ChecklistEventMap(entry, texts)
  local key, def = ns.Events.GroupOf(entry and entry.m, ns.Data and ns.Data.EventGroups)
  if not key or not ns.Events.IsUnknown(texts and texts[key]) then return nil end
  return ns.Events.ZoneMap(def)
end

local mapHooked = false
-- Opens the event zone's world map so the client loads its data, and drops the
-- cached lines so the checklist redraws once the data arrives. Not in combat
-- (Map.OpenZone says so). The map closing also invalidates the cache (guarded,
-- hooked once).
function UI.OpenEventMap(uiMapID)
  local map = ns.Map
  if not (map and type(map.OpenZone) == "function") then return false end
  local good, opened = pcall(map.OpenZone, uiMapID)
  if not good then
    if ns.Game and ns.Game.ReportError then ns.Game.ReportError(opened) end
    return false
  end
  if not opened then return false end
  if not mapHooked and type(WorldMapFrame) == "table" and type(WorldMapFrame.HookScript) == "function" then
    mapHooked = pcall(WorldMapFrame.HookScript, WorldMapFrame, "OnHide", function() UI.EventStatusChanged() end)
  end
  UI.EventStatusChanged()
  return true
end

-- A row's grey line with its status appended in light blue.
function UI.ChecklistStatusDesc(desc, status)
  if not status or status == "" then return desc end
  local colored = STATUS_COLOR .. status .. "|r"
  if not desc or desc == "" then return colored end
  return desc .. DOT .. colored
end
