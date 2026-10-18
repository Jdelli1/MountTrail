local ADDON, ns = ...

-- Points the player at a mount's farm location: a user waypoint (super-tracked)
-- on the world map, the dungeon entrance for instance maps, and / or a TomTom
-- waypoint, as the "Waypoints" setting says (Map.WaypointMode, F9;
-- Map.SetWaypoint, a row's left-click), or
-- just the world map there (Map.OpenMap, Shift+left-click; never in combat).
-- Map.HasLocation is the cheap check behind the rows' pin icons. (Map.Show,
-- the old Map button's action, was removed with the buttons in F5.) This is an integration layer, so it calls
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

local MODES = { game = true, tomtom = true, both = true }

-- The "Waypoints" setting (Options > AddOns > AzerothTrail, UI/Options.lua):
-- "game" (the in-game map pin, default), "tomtom" (only TomTom; the in-game
-- pin when TomTom is missing) or "both". Missing or unknown -> "game".
function Map.WaypointMode()
  local db = ns.db
  local settings = db and type(db.global) == "table" and db.global.settings or nil
  local mode = type(settings) == "table" and settings.waypoints or nil
  return MODES[mode] and mode or "game"
end

-- The real WoW globals, looked up at call time.
local function realApi()
  return {
    waypointMode = Map.WaypointMode(),
    C_Map = C_Map,
    C_SuperTrack = C_SuperTrack,
    C_EncounterJournal = C_EncounterJournal,
    EJ_GetInstanceInfo = EJ_GetInstanceInfo,
    UiMapPoint = UiMapPoint,
    OpenWorldMap = OpenWorldMap,
    TomTom = TomTom,
    Print = defaultPrint,
    GetTime = GetTime,
    InCombat = function()
      local game = ns.Game
      return game and type(game.InCombat) == "function" and game.InCombat() or false
    end,
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

-- The mount's location as coordsFor picks it ({ m=, x=, y= }, the holiday's
-- when it has one), or nil. Read-only; the zone panel (UI/ZonePanel.lua)
-- matches mounts to the player's zone with it.
function Map.CoordsFor(mountID)
  return coordsFor(mountID)
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

-- The entrance of journal instance `jid` listed on map m. -> x, y (0-1) or nil.
local function entranceOn(api, m, jid)
  local entrances = try(api.C_EncounterJournal, "GetDungeonEntrancesForMap", m)
  if type(entrances) ~= "table" then return nil end
  for _, entrance in ipairs(entrances) do
    if type(entrance) == "table" and entrance.journalInstanceID == jid then
      local x, y = positionXY(entrance.position)
      if x then return x, y end
    end
  end
  return nil
end

-- Finds journal instance `jid`'s entrance by walking up the parent maps from
-- `start` (start itself first when includeStart). -> mapID, x, y (0-1) or nil.
local function walkForEntrance(api, start, jid, includeStart)
  if not (start and jid) then return nil end
  if includeStart then
    local x, y = entranceOn(api, start, jid)
    if x then return start, x, y end
  end
  local seen = { [start] = true }
  local current = start
  for _ = 1, MAX_PARENT_STEPS do
    local info = try(api.C_Map, "GetMapInfo", current)
    local parent = type(info) == "table" and info.parentMapID or nil
    if not parent or parent == 0 or seen[parent] then return nil end
    seen[parent] = true
    local x, y = entranceOn(api, parent, jid)
    if x then return parent, x, y end
    current = parent
  end
  return nil
end

-- Lower-cased name without a leading "The " (entrance / map name matching).
local function nameKey(s)
  if type(s) ~= "string" or s == "" then return nil end
  s = string.lower(s)
  if string.sub(s, 1, 4) == "the " then s = string.sub(s, 5) end
  return s
end

-- The instance's own map (EJ_GetInstanceInfo's 7th return) for journal
-- instance jid, or nil.
local function instanceArea(api, jid)
  if type(api.EJ_GetInstanceInfo) ~= "function" then return nil end
  local area = select(7, (function(good, ...)
    if not good then return end
    return ...
  end)(guarded(api.EJ_GetInstanceInfo, jid)))
  if type(area) == "number" and area > 0 then return area end
  return nil
end

-- The entrance on map `on` that belongs to the instance whose (dungeon) map
-- is m: an entrance whose journal instance's own map is m, else one whose
-- name matches m's name. -> x, y (0-1) or nil.
local function entranceForInstanceMap(api, on, m, mKey)
  local entrances = try(api.C_EncounterJournal, "GetDungeonEntrancesForMap", on)
  if type(entrances) ~= "table" then return nil end
  local byName
  for _, entrance in ipairs(entrances) do
    if type(entrance) == "table" then
      local x, y = positionXY(entrance.position)
      if x then
        if entrance.journalInstanceID and instanceArea(api, entrance.journalInstanceID) == m then
          return x, y
        end
        if not byName and mKey and nameKey(entrance.name) == mKey then byName = { x, y } end
      end
    end
  end
  if byName then return byName[1], byName[2] end
  return nil
end

-- Finds the entrance of the instance whose dungeon map is m (a map that takes
-- no user waypoint) by walking up the parent maps to the zone that lists it.
-- GetInstanceForGameMap wants a game map ID, so a UI map only works there by
-- chance; the zone's entrance list (matched by the instance's own map, else
-- by name) is the reliable way. -> mapID, x, y (0-1) or nil.
local function findEntrance(api, m)
  local journalInstance = try(api.C_EncounterJournal, "GetInstanceForGameMap", m)
  if journalInstance and journalInstance ~= 0 then
    local em, ex, ey = walkForEntrance(api, m, journalInstance, false)
    if em then return em, ex, ey end
  end
  local info = try(api.C_Map, "GetMapInfo", m)
  local mKey = type(info) == "table" and nameKey(info.name) or nil
  local seen = { [m] = true }
  local current = m
  for _ = 1, MAX_PARENT_STEPS do
    local parentInfo = try(api.C_Map, "GetMapInfo", current)
    local parent = type(parentInfo) == "table" and parentInfo.parentMapID or nil
    if not parent or parent == 0 or seen[parent] then return nil end
    seen[parent] = true
    local x, y = entranceForInstanceMap(api, parent, m, mKey)
    if x then return parent, x, y end
    current = parent
  end
  return nil
end

-- The game instance ID (a game map ID, as GetSavedInstanceInfo reports it) of
-- a raid / dungeon mount, from its lockout spec: the route boss's per-boss
-- spec first (`routeBoss` when the clicked row names one, else UI.RouteBoss,
-- looked up at call time), else the mount's own. nil for mounts without an
-- instance spec.
local function instanceOf(mountID, routeBoss)
  local lockouts = ns.Lockouts
  if not (lockouts and type(lockouts.SpecFor) == "function") then return nil end
  local boss = routeBoss
  local ui = ns.UI
  if boss == nil and ui and type(ui.RouteBoss) == "function" then
    local good, b = guarded(ui.RouteBoss, mountID)
    if good then boss = b end
  end
  local good, spec = guarded(lockouts.SpecFor, mountID, boss)
  if good and type(spec) == "table" and type(spec.instance) == "number" then return spec.instance end
  return nil
end

-- Whether a per-boss spec (Data.BossLockouts) governs `routeBoss`: then the
-- boss, not the mount's own source, decides where a click goes.
local function bossSpec(routeBoss)
  local per = routeBoss and ns.Data and ns.Data.BossLockouts
  local spec = per and per[routeBoss]
  return type(spec) == "table" and type(spec.instance) == "number"
end

-- The entrance of a raid / dungeon mount's instance, from its lockout spec:
-- GetInstanceForGameMap(game instance ID) -> journal instance, whose own map
-- (EJ_GetInstanceInfo, 7th return) is walked up to the zone listing the
-- entrance; the mount's coords map is tried too (a zone map may list the
-- entrance itself). -> mapID, x, y (0-1) or nil.
local function instanceEntrance(api, mountID, coordsMap, routeBoss)
  local game = instanceOf(mountID, routeBoss)
  if not game then return nil end
  local jid = try(api.C_EncounterJournal, "GetInstanceForGameMap", game)
  if not jid or jid == 0 then return nil end
  local area = instanceArea(api, jid)
  if area then
    local m, x, y = walkForEntrance(api, area, jid, true)
    if m then return m, x, y end
  end
  return walkForEntrance(api, coordsMap, jid, true)
end

-- Decides where a mount's waypoint goes. -> { map=, x=, y=, kind= } with x/y in
-- percent (0-100) and kind one of:
--   "pin"      x/y on a map that takes a user waypoint
--   "entrance" the dungeon / raid entrance (on the zone that lists it)
--   "open"     only open the world map at `map` (no pin)
--   "none"     no location known
-- A raid / dungeon mount with an instance lockout spec always goes to its
-- instance's entrance when the Encounter Journal knows it; its coords are
-- the fallback. `routeBoss` (optional): the route / checklist row's boss,
-- whose per-boss spec (e.g. a Vault of Archavon watcher) picks the instance
-- before the mount's first route row; with such a spec the entrance is
-- found even for a mount without coords.
function Map.Resolve(mountID, api, routeBoss)
  api = api or realApi()
  local coords = coordsFor(mountID)
  if not coords then
    if bossSpec(routeBoss) then
      local em, ex0, ey0 = instanceEntrance(api, mountID, nil, routeBoss)
      if em then return { map = em, x = ex0 * 100, y = ey0 * 100, kind = "entrance" } end
    end
    return { kind = "none" }
  end
  local m, x, y = coords.m, coords.x, coords.y
  local em, ex0, ey0 = instanceEntrance(api, mountID, m, routeBoss)
  if em then return { map = em, x = ex0 * 100, y = ey0 * 100, kind = "entrance" } end
  local hasXY = type(x) == "number" and type(y) == "number"
  local canSet = try(api.C_Map, "CanSetUserWaypointOnMap", m) == true
  if hasXY and canSet then return { map = m, x = x, y = y, kind = "pin" } end
  if not canSet then
    local parent, ex, ey = findEntrance(api, m)
    if parent then return { map = parent, x = ex * 100, y = ey * 100, kind = "entrance" } end
  end
  return { map = m, kind = "open" }
end

-- Whether the mount has a location (its coords, or its holiday's): exactly
-- when Map.Resolve's kind is not "none", without any API call. For the row
-- pins, checked on every list refresh. `routeBoss` (optional): a route /
-- checklist row's boss; a per-boss instance spec (Data.BossLockouts) is a
-- location of its own (Map.Resolve goes to that instance's entrance).
function Map.HasLocation(mountID, routeBoss)
  return coordsFor(mountID) ~= nil or bossSpec(routeBoss)
end

-- Whether a click can drop a waypoint on a spot rather than only show a
-- zone: x/y coords, or a dungeon / raid mount (journal sections, or on the
-- route) whose instance entrance Map.Resolve looks up. A mount known only by
-- its zone (a fishing mount, a zone-wide drop) is false. No API call.
-- `routeBoss` (optional): a row boss with a per-boss instance spec is a spot
-- (its instance's entrance, as Map.Resolve picks it).
function Map.HasSpot(mountID, routeBoss)
  if bossSpec(routeBoss) then return true end
  local coords = coordsFor(mountID)
  if not coords then return false end
  if type(coords.x) == "number" and type(coords.y) == "number" then return true end
  local mount = ns.Data and ns.Data.Mounts and ns.Data.Mounts[mountID]
  if type(mount) == "table" and mount.tab == "journal"
    and (mount.section == "dungeon" or mount.section == "raid") then
    return true
  end
  local ui = ns.UI
  if ui and type(ui.RouteEntry) == "function" then
    local good, entry = guarded(ui.RouteEntry, mountID)
    if good and entry ~= nil then return true end
  end
  return false
end

local function mountName(mountID)
  local mount = ns.Data and ns.Data.Mounts and ns.Data.Mounts[mountID]
  if type(mount) == "table" and mount.name then return mount.name end
  return tostring(mountID)
end

-- The last chat line and when (api.GetTime) it was printed: the same line
-- again within REPEAT_WINDOW seconds is dropped (a double click, or clicking
-- the same row twice). Without a clock nothing is dropped.
local REPEAT_WINDOW = 2
local lastLine, lastAt

local function say(api, msg)
  local now
  if type(api.GetTime) == "function" then
    local good, t = guarded(api.GetTime)
    if good and type(t) == "number" then now = t end
  end
  if now and msg == lastLine and lastAt and now - lastAt < REPEAT_WINDOW then return end
  lastLine, lastAt = (now and msg or nil), now
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
local function placeLabel(api, mountID, target, routeBoss)
  if target.kind == "entrance" and bossSpec(routeBoss) then
    -- The boss's instance, not the mount's own source zone.
    local game = instanceOf(mountID, routeBoss)
    local jid = game and try(api.C_EncounterJournal, "GetInstanceForGameMap", game)
    local name
    if jid and jid ~= 0 and type(api.EJ_GetInstanceInfo) == "function" then
      local good, n = guarded(api.EJ_GetInstanceInfo, jid)
      if good then name = nonEmpty(n) end
    end
    name = name or (ns.UI and type(ns.UI.RouteBossInstance) == "function" and ns.UI.RouteBossInstance(routeBoss))
      or mapName(api, target.map) or mountName(mountID)
    return string.format(L["%s (entrance)"], name)
  end
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
-- one TomTom waypoint. The route arrow (UI/Arrow.lua) tracks its own. Both add
-- non-persistent waypoints (persistent = false), so /reload clears them along
-- with this session-only uid: nothing is left behind to remove.
local tomtomUid

-- Removes our TomTom waypoint, if any (game mode: an earlier both / tomtom
-- click's waypoint should not linger).
local function removeTomTom(api)
  local tomtom = api.TomTom
  if tomtomUid ~= nil and type(tomtom) == "table" and type(tomtom.RemoveWaypoint) == "function" then
    guarded(tomtom.RemoveWaypoint, tomtom, tomtomUid)
  end
  tomtomUid = nil
end

-- Replaces our TomTom waypoint with one at m, x, y (0-1). -> true when TomTom
-- took the new waypoint.
local function replaceTomTom(api, m, x, y, title)
  local tomtom = api.TomTom
  if type(tomtom) ~= "table" then return false end
  if tomtomUid ~= nil and type(tomtom.RemoveWaypoint) == "function" then
    guarded(tomtom.RemoveWaypoint, tomtom, tomtomUid)
  end
  tomtomUid = nil
  if type(tomtom.AddWaypoint) ~= "function" then return false end
  local good, uid = guarded(tomtom.AddWaypoint, tomtom, m, x, y, { title = title, persistent = false })
  if good then tomtomUid = uid end
  return good
end

-- The game's user waypoint at target (x/y in percent), super-tracked, when the
-- map takes one. -> true when the waypoint was set.
local function setUserWaypoint(api, target)
  local m = target.map
  if try(api.C_Map, "CanSetUserWaypointOnMap", m) ~= true then return false end
  local point = try(api.UiMapPoint, "CreateFromCoordinates", m, target.x / 100, target.y / 100)
  if not point or type(api.C_Map.SetUserWaypoint) ~= "function" then return false end
  if not guarded(api.C_Map.SetUserWaypoint, point) then return false end
  try(api.C_SuperTrack, "SetSuperTrackedUserWaypoint", true)
  return true
end

local function inCombat(api)
  if type(api.InCombat) ~= "function" then return false end
  local good, combat = guarded(api.InCombat)
  return good and combat == true
end

-- Opens the world map at m, unless the player is in combat (the map can be
-- blocked there): then chat says so. -> true when OpenWorldMap was called.
local function openWorldMap(api, m)
  if inCombat(api) then
    say(api, L["Can't open the map in combat"])
    return false
  end
  if type(api.OpenWorldMap) == "function" then guarded(api.OpenWorldMap, m) end
  return true
end

-- Opens the world map on `uiMapID` (a zone, no mount): the client then loads
-- that zone's POI / contribution data (checklist rows with an unknown event
-- status). In combat chat says the map can't be opened. -> true when opened.
function Map.OpenZone(uiMapID, api)
  api = api or realApi()
  if type(uiMapID) ~= "number" then return false end
  return openWorldMap(api, uiMapID)
end

-- Left-click on a mount row: points the player at the mount without opening
-- the world map. pin / entrance, by the waypoint mode (api.waypointMode, else
-- Map.WaypointMode()): game -> the game's user waypoint (super-tracked) only;
-- tomtom -> a TomTom waypoint only (replacing the previous AzerothTrail one),
-- the user waypoint instead when TomTom is missing or fails; both -> both.
-- Chat "Waypoint: <place>"; when nothing could be set (the map takes no user
-- waypoint and TomTom is not used) it falls back to opening the map.
-- open (no point to pin): opens the world map there, chat "Opened map:
-- <place>". Out of combat only: in combat chat says the map can't be opened.
-- none: chat "No map location for <mount>".
-- -> the place label (nil for none), the Map.Resolve kind.
function Map.SetWaypoint(mountID, api, routeBoss)
  api = api or realApi()
  local target = Map.Resolve(mountID, api, routeBoss)
  if target.kind == "none" then
    noLocation(api, mountID)
    return nil, "none"
  end
  local place = placeLabel(api, mountID, target, routeBoss)
  if target.x and target.y then
    local mode = MODES[api.waypointMode] and api.waypointMode or Map.WaypointMode()
    local set, tomtom = false, false
    if mode ~= "tomtom" then set = setUserWaypoint(api, target) end
    if mode ~= "game" then
      tomtom = replaceTomTom(api, target.map, target.x / 100, target.y / 100, mountName(mountID))
    else
      removeTomTom(api)
    end
    if mode == "tomtom" and not tomtom then set = setUserWaypoint(api, target) end
    if set or tomtom then
      say(api, string.format(L["Waypoint: %s"], place))
      return place, target.kind
    end
  end
  if openWorldMap(api, target.map) then
    if target.kind == "open" then
      -- Only the zone is known (no x/y, no entrance): say so plainly, naming
      -- the zone when the client or the source text knows it.
      local zone = mapName(api, target.map) or sourceZone(mountID)
      if zone then
        say(api, string.format(L["No exact spot for %s (anywhere in %s): opened the map"], mountName(mountID), zone))
      else
        say(api, string.format(L["No exact spot for %s: opened the map"], mountName(mountID)))
      end
    else
      say(api, string.format(L["Opened map: %s"], place))
    end
  end
  return place, target.kind
end

-- Shift+left-click on a mount row: opens the world map at the mount's
-- location (Map.Resolve's map) without setting a waypoint; in combat chat
-- says the map can't be opened. none: chat "No map location for <mount>".
-- -> the Map.Resolve result.
function Map.OpenMap(mountID, api, routeBoss)
  api = api or realApi()
  local target = Map.Resolve(mountID, api, routeBoss)
  if target.kind == "none" then
    noLocation(api, mountID)
    return target
  end
  openWorldMap(api, target.map)
  return target
end
