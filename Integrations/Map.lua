local ADDON, ns = ...

-- Points the player at a mount's farm location: a user waypoint (super-tracked)
-- on the world map, the dungeon entrance for instance maps, and a TomTom
-- waypoint when TomTom is installed (Map.SetWaypoint, a row's left-click), or
-- just the world map there (Map.OpenMap, Shift+left-click). This is an integration layer, so it calls
-- the WoW API directly, but always through an `api` table (the real globals by
-- default) so the decision logic can be tested with stubs. Every call is
-- guarded; nothing here raises a Lua error (caught errors are shown only with
-- /azt debug).
local Map = {}
ns.Map = Map

local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

-- Parent-map steps to try when looking for a dungeon entrance.
local MAX_PARENT_STEPS = 8

local function defaultPrint(msg)
  local addon = ns.addon
  if addon and addon.Print then addon:Print(msg) else print(msg) end
end

-- The real WoW globals, looked up at call time.
local function realApi()
  return {
    C_Map = C_Map,
    C_SuperTrack = C_SuperTrack,
    C_EncounterJournal = C_EncounterJournal,
    UiMapPoint = UiMapPoint,
    OpenWorldMap = OpenWorldMap,
    TomTom = TomTom,
    Print = defaultPrint,
  }
end

-- A caught error: dropped, or shown when /azt debug is on (Game.ReportError,
-- looked up at call time).
local function swallowed(err)
  local game = ns.Game
  if game and type(game.ReportError) == "function" then game.ReportError(err) end
end

-- pcall(fn, ...) that reports a failure through swallowed() -> good, results.
local function guarded(fn, ...)
  return (function(good, ...)
    if not good then swallowed((...)) end
    return good, ...
  end)(pcall(fn, ...))
end

-- Calls lib[method](...) when present; returns its results, or nil when the
-- function is missing or raises an error.
local function try(lib, method, ...)
  if type(lib) ~= "table" or type(lib[method]) ~= "function" then return nil end
  return (function(good, ...)
    if not good then return nil end
    return ...
  end)(guarded(lib[method], ...))
end

-- Holiday mounts (tab "holiday" whose section is a Data.Holidays key) use the
-- holiday's coords when it has them; everything else uses the mount's own.
local function coordsFor(mountID)
  local data = ns.Data or {}
  local mount = data.Mounts and data.Mounts[mountID]
  if type(mount) ~= "table" then return nil end
  if mount.tab == "holiday" and mount.section and data.Holidays then
    local holiday = data.Holidays[mount.section]
    if type(holiday) == "table" and type(holiday.coords) == "table" and holiday.coords.m then
      return holiday.coords
    end
  end
  if type(mount.coords) == "table" and mount.coords.m then return mount.coords end
  return nil
end

local function positionXY(position)
  if type(position) ~= "table" then return nil end
  local x, y = position.x, position.y
  if (x == nil or y == nil) and type(position.GetXY) == "function" then
    local good, px, py = guarded(position.GetXY, position)
    if good then x, y = px, py end
  end
  if type(x) == "number" and type(y) == "number" then return x, y end
  return nil
end

-- Finds the entrance of the journal instance for instance map m by walking up
-- the parent maps. -> parentMapID, x, y (0-1) or nil.
local function findEntrance(api, m)
  local journalInstance = try(api.C_EncounterJournal, "GetInstanceForGameMap", m)
  if not journalInstance or journalInstance == 0 then return nil end
  local seen = { [m] = true }
  local current = m
  for _ = 1, MAX_PARENT_STEPS do
    local info = try(api.C_Map, "GetMapInfo", current)
    local parent = type(info) == "table" and info.parentMapID or nil
    if not parent or parent == 0 or seen[parent] then return nil end
    seen[parent] = true
    local entrances = try(api.C_EncounterJournal, "GetDungeonEntrancesForMap", parent)
    if type(entrances) == "table" then
      for _, entrance in ipairs(entrances) do
        if type(entrance) == "table" and entrance.journalInstanceID == journalInstance then
          local x, y = positionXY(entrance.position)
          if x then return parent, x, y end
        end
      end
    end
    current = parent
  end
  return nil
end

-- Decides where a mount's waypoint goes. -> { map=, x=, y=, kind= } with x/y in
-- percent (0-100) and kind one of:
--   "pin"      x/y on a map that takes a user waypoint
--   "entrance" the dungeon entrance of an instance map, on a parent map
--   "open"     only open the world map at `map` (no pin)
--   "none"     no location known
function Map.Resolve(mountID, api)
  api = api or realApi()
  local coords = coordsFor(mountID)
  if not coords then return { kind = "none" } end
  local m, x, y = coords.m, coords.x, coords.y
  local hasXY = type(x) == "number" and type(y) == "number"
  local canSet = try(api.C_Map, "CanSetUserWaypointOnMap", m) == true
  if hasXY and canSet then return { map = m, x = x, y = y, kind = "pin" } end
  if not canSet then
    local parent, ex, ey = findEntrance(api, m)
    if parent then return { map = parent, x = ex * 100, y = ey * 100, kind = "entrance" } end
  end
  return { map = m, kind = "open" }
end

local function mountName(mountID)
  local mount = ns.Data and ns.Data.Mounts and ns.Data.Mounts[mountID]
  if type(mount) == "table" and mount.name then return mount.name end
  return tostring(mountID)
end

local function say(api, msg)
  local print_ = type(api.Print) == "function" and api.Print or defaultPrint
  guarded(print_, msg)
end

local function noLocation(api, mountID)
  say(api, string.format(L["No map location for %s"], mountName(mountID)))
end

local function nonEmpty(s)
  if type(s) == "string" and s ~= "" then return s end
  return nil
end

-- C_Map.GetMapInfo(m).name through the api table, or nil.
local function mapName(api, m)
  if not m then return nil end
  local info = try(api.C_Map, "GetMapInfo", m)
  return type(info) == "table" and nonEmpty(info.name) or nil
end

-- The value of the mount's source text "Zone:" line (Game.MountSourceText,
-- UI.SourceZone; both looked up at call time, UI loads after this file).
local function sourceZone(mountID)
  local game, ui = ns.Game, ns.UI
  if not (game and type(game.MountSourceText) == "function" and ui and type(ui.SourceZone) == "function") then
    return nil
  end
  local good, text = guarded(game.MountSourceText, mountID)
  if not good then return nil end
  local good2, zone = guarded(ui.SourceZone, text)
  return good2 and nonEmpty(zone) or nil
end

-- The route's instance name for the mount (UI.RouteEntry), or nil.
local function routeInstance(mountID)
  local ui = ns.UI
  if not (ui and type(ui.RouteEntry) == "function") then return nil end
  local good, entry = guarded(ui.RouteEntry, mountID)
  return good and type(entry) == "table" and nonEmpty(entry.instance) or nil
end

-- Chat label of a resolved target:
--   pin      the zone: the map's name, else the source text's "Zone:"
--   entrance "<instance> (entrance)": the instance named as UI.SubGroup does
--            (source "Zone:", then the instance map's name, then the route
--            step), else the entrance's (parent) map name
--   open     the map's name, else the source text's "Zone:"
-- The mount's name when nothing else is known.
local function placeLabel(api, mountID, target)
  if target.kind == "entrance" then
    local coords = coordsFor(mountID)
    local instance = sourceZone(mountID) or mapName(api, coords and coords.m) or routeInstance(mountID)
      or mapName(api, target.map) or mountName(mountID)
    return string.format(L["%s (entrance)"], instance)
  end
  return mapName(api, target.map) or sourceZone(mountID) or mountName(mountID)
end

-- uid of the last TomTom waypoint this file added (TomTom:AddWaypoint's
-- return), removed before the next one is added so AzerothTrail keeps at most
-- one TomTom waypoint. The route arrow (UI/Arrow.lua) tracks its own.
local tomtomUid

local function replaceTomTom(api, m, x, y, title)
  local tomtom = api.TomTom
  if type(tomtom) ~= "table" then return end
  if tomtomUid ~= nil and type(tomtom.RemoveWaypoint) == "function" then
    guarded(tomtom.RemoveWaypoint, tomtom, tomtomUid)
  end
  tomtomUid = nil
  if type(tomtom.AddWaypoint) ~= "function" then return end
  local good, uid = guarded(tomtom.AddWaypoint, tomtom, m, x, y, { title = title, persistent = false })
  if good then tomtomUid = uid end
end

-- The game's user waypoint at target (x/y in percent), super-tracked, when the
-- map takes one.
local function setUserWaypoint(api, target)
  local m = target.map
  if try(api.C_Map, "CanSetUserWaypointOnMap", m) ~= true then return end
  local point = try(api.UiMapPoint, "CreateFromCoordinates", m, target.x / 100, target.y / 100)
  if point then
    try(api.C_Map, "SetUserWaypoint", point)
    try(api.C_SuperTrack, "SetSuperTrackedUserWaypoint", true)
  end
end

local function openWorldMap(api, m)
  if type(api.OpenWorldMap) == "function" then guarded(api.OpenWorldMap, m) end
end

-- Opens the world map at the mount's location; see Map.Resolve.
function Map.Show(mountID, api)
  api = api or realApi()
  local target = Map.Resolve(mountID, api)
  if target.kind == "none" then
    noLocation(api, mountID)
    return target
  end
  if target.x and target.y then setUserWaypoint(api, target) end
  openWorldMap(api, target.map)
  -- TomTom only for a real point (pin or entrance), never for "open".
  if target.x and target.y then
    replaceTomTom(api, target.map, target.x / 100, target.y / 100, mountName(mountID))
  end
  return target
end

-- Left-click on a mount row: points the player at the mount without opening
-- the world map. pin / entrance: the game's user waypoint (super-tracked) and
-- a TomTom waypoint (replacing the previous AzerothTrail one), chat
-- "Waypoint: <place>". open (no point to pin): opens the world map there,
-- chat "Opened map: <zone>". none: chat "No map location for <mount>".
-- -> the place label (nil for none), the Map.Resolve kind.
function Map.SetWaypoint(mountID, api)
  api = api or realApi()
  local target = Map.Resolve(mountID, api)
  if target.kind == "none" then
    noLocation(api, mountID)
    return nil, "none"
  end
  local place = placeLabel(api, mountID, target)
  if target.x and target.y then
    setUserWaypoint(api, target)
    replaceTomTom(api, target.map, target.x / 100, target.y / 100, mountName(mountID))
    say(api, string.format(L["Waypoint: %s"], place))
  else
    openWorldMap(api, target.map)
    say(api, string.format(L["Opened map: %s"], place))
  end
  return place, target.kind
end

-- Shift+left-click on a mount row: opens the world map at the mount's
-- location (Map.Resolve's map) without setting a waypoint. none: chat "No
-- map location for <mount>". -> the Map.Resolve result.
function Map.OpenMap(mountID, api)
  api = api or realApi()
  local target = Map.Resolve(mountID, api)
  if target.kind == "none" then
    noLocation(api, mountID)
    return target
  end
  openWorldMap(api, target.map)
  return target
end
