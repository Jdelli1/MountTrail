local ADDON, ns = ...

-- Points the player at a mount's farm location: a user waypoint (super-tracked)
-- on the world map, the dungeon entrance for instance maps, and a TomTom
-- waypoint when TomTom is installed. This is an integration layer, so it calls
-- the WoW API directly, but always through an `api` table (the real globals by
-- default) so the decision logic can be tested with stubs. Every call is
-- guarded; nothing here raises a Lua error.
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

-- Calls lib[method](...) when present; returns its results, or nil when the
-- function is missing or raises an error.
local function try(lib, method, ...)
  if type(lib) ~= "table" or type(lib[method]) ~= "function" then return nil end
  return (function(good, ...)
    if not good then return nil end
    return ...
  end)(pcall(lib[method], ...))
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
    local good, px, py = pcall(position.GetXY, position)
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

-- Decides where the Map button points. -> { map=, x=, y=, kind= } with x/y in
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

-- Opens the world map at the mount's location; see Map.Resolve.
function Map.Show(mountID, api)
  api = api or realApi()
  local target = Map.Resolve(mountID, api)
  local name = mountName(mountID)
  if target.kind == "none" then
    local say = type(api.Print) == "function" and api.Print or defaultPrint
    pcall(say, string.format(L["No map location for %s"], name))
    return target
  end
  local m = target.map
  if target.x and target.y then
    local fx, fy = target.x / 100, target.y / 100
    if try(api.C_Map, "CanSetUserWaypointOnMap", m) == true then
      local point = try(api.UiMapPoint, "CreateFromCoordinates", m, fx, fy)
      if point then
        try(api.C_Map, "SetUserWaypoint", point)
        try(api.C_SuperTrack, "SetSuperTrackedUserWaypoint", true)
      end
    end
  end
  if type(api.OpenWorldMap) == "function" then pcall(api.OpenWorldMap, m) end
  -- TomTom only for a real point (pin or entrance), never for "open".
  local tomtom = api.TomTom
  if target.x and target.y and type(tomtom) == "table" and type(tomtom.AddWaypoint) == "function" then
    pcall(tomtom.AddWaypoint, tomtom, m, target.x / 100, target.y / 100, { title = name, persistent = false })
  end
  return target
end
