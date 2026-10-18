-- Map.Resolve picks where a mount's waypoint goes; Map.SetWaypoint (row
-- left-click) and Map.OpenMap (Shift+left-click) act on it; Map.HasLocation
-- is the cheap pin check. They take the WoW API through an injected table, so
-- these specs never touch globals.

local function loadMap(mounts, holidays)
  local ns = load_addon({ "Core/Locale.lua", "Integrations/Map.lua" })
  ns.Data = { Mounts = mounts or {}, Holidays = holidays or {} }
  return ns.Map, ns
end

-- A fake WoW API. opts.canSet: set of map IDs that take a user waypoint.
-- opts.parents: map ID -> parent map ID. opts.journal: map ID -> journal
-- instance. opts.entrances: map ID -> list of entrance records. opts.names:
-- map ID -> GetMapInfo name. TomTom (unless opts.tomtom == false) hands out
-- uids "uid1", "uid2", ... and records RemoveWaypoint as "TomTomRemove".
-- opts.combat: InCombat() result. opts.clock: { now = seconds } read by
-- GetTime (absent: no GetTime, so no chat de-duplication). opts.mode: the
-- waypoint setting (F9) as api.waypointMode, "both" by default so the specs
-- written before F9 keep testing the game pin + TomTom behaviour.
local function fakeApi(opts)
  opts = opts or {}
  local log = {}
  local function rec(...) log[#log + 1] = { ... } end
  local api = {
    log = log,
    C_Map = {
      CanSetUserWaypointOnMap = function(m) return (opts.canSet or {})[m] == true end,
      GetMapInfo = function(m)
        local parent, name = (opts.parents or {})[m], (opts.names or {})[m]
        if parent == nil and name == nil then return nil end
        return { mapID = m, parentMapID = parent, name = name }
      end,
      SetUserWaypoint = function(point) rec("SetUserWaypoint", point) end,
    },
    UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { uiMapID = m, x = x, y = y } end },
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function(on) rec("SuperTrack", on) end },
    C_EncounterJournal = {
      GetInstanceForGameMap = function(m) return (opts.journal or {})[m] end,
      GetDungeonEntrancesForMap = function(m) return (opts.entrances or {})[m] or {} end,
    },
    OpenWorldMap = function(m) rec("OpenWorldMap", m) end,
    Print = function(msg) rec("Print", msg) end,
    InCombat = function() return opts.combat == true end,
    waypointMode = opts.mode or "both",
  }
  if opts.clock then api.GetTime = function() return opts.clock.now end end
  if opts.tomtom ~= false then
    local n = 0
    api.TomTom = {
      AddWaypoint = function(self, m, x, y, o)
        rec("TomTom", m, x, y, o)
        n = n + 1
        return "uid" .. n
      end,
      RemoveWaypoint = function(self, uid) rec("TomTomRemove", uid) end,
    }
  end
  return api
end

local function near(a, b) return math.abs(a - b) < 1e-9 end

describe("Map.Resolve", function()
  it("pins outdoor coordinates on a map that takes a waypoint", function()
    local Map = loadMap({ [517] = { name = "Heavenly Onyx Cloud Serpent", coords = { m = 379, x = 53.6, y = 64.4 } } })
    eq(Map.Resolve(517, fakeApi({ canSet = { [379] = true } })), { map = 379, x = 53.6, y = 64.4, kind = "pin" })
  end)

  it("uses the dungeon entrance on a parent map for an instance map", function()
    local Map = loadMap({ [395] = { name = "Drake of the North Wind", coords = { m = 325 } } })
    local api = fakeApi({
      canSet = { [249] = true },
      journal = { [325] = 68 },
      parents = { [325] = 249, [249] = 12, [12] = 947 },
      entrances = {
        [249] = { { journalInstanceID = 69, position = { x = 0.1, y = 0.2 } },
                  { journalInstanceID = 68, position = { x = 0.765, y = 0.84 } } },
      },
    })
    local r = Map.Resolve(395, api)
    eq(r.kind, "entrance"); eq(r.map, 249)
    ok(near(r.x, 76.5) and near(r.y, 84), "entrance position in percent: " .. r.x .. "," .. r.y)
  end)

  it("walks more than one parent up and reads GetXY positions", function()
    local Map = loadMap({ [1] = { name = "M", coords = { m = 100 } } })
    local pos = { GetXY = function(self) return 0.5, 0.25 end }
    local api = fakeApi({
      journal = { [100] = 7 },
      parents = { [100] = 101, [101] = 102, [102] = 0 },
      entrances = { [102] = { { journalInstanceID = 7, position = pos } } },
    })
    eq(Map.Resolve(1, api), { map = 102, x = 50, y = 25, kind = "entrance" })
  end)

  it("tries the entrance when an instance map has x/y but takes no waypoint", function()
    local Map = loadMap({ [202] = { name = "Swift Brewfest Ram", coords = { m = 242, x = 46.6, y = 60.0 } } })
    local api = fakeApi({
      journal = { [242] = 228 }, parents = { [242] = 35 },
      entrances = { [35] = { { journalInstanceID = 228, position = { x = 0.2, y = 0.3 } } } },
    })
    eq(Map.Resolve(202, api), { map = 35, x = 20, y = 30, kind = "entrance" })
  end)

  it("opens the map without a pin when no entrance resolves", function()
    local Map = loadMap({ [118] = { name = "Red Qiraji Battle Tank", coords = { m = 319 } } })
    eq(Map.Resolve(118, fakeApi({})), { map = 319, kind = "open" }, "no journal instance")
    eq(Map.Resolve(118, fakeApi({ journal = { [319] = 744 }, parents = { [319] = 81, [81] = 12 } })),
      { map = 319, kind = "open" }, "no parent lists the entrance")
  end)

  it("opens the map for map-only coordinates on a map that takes a waypoint", function()
    local Map = loadMap({ [16] = { name = "Nether-Swept Drake", coords = { m = 2405 } } })
    eq(Map.Resolve(16, fakeApi({ canSet = { [2405] = true } })), { map = 2405, kind = "open" })
  end)

  it("stops walking on a parent cycle", function()
    local Map = loadMap({ [1] = { name = "M", coords = { m = 10 } } })
    local api = fakeApi({ journal = { [10] = 5 }, parents = { [10] = 11, [11] = 10 } })
    eq(Map.Resolve(1, api), { map = 10, kind = "open" })
  end)

  it("returns none for a mount without coords or unknown to the data", function()
    local Map = loadMap({ [6] = { name = "Brown Horse" } })
    eq(Map.Resolve(6, fakeApi({})), { kind = "none" })
    eq(Map.Resolve(99999, fakeApi({})), { kind = "none" })
  end)

  it("uses Data.Holidays coords for a holiday mount, else its own", function()
    local Map = loadMap({
      [226] = { name = "Great Brewfest Kodo", tab = "holiday", section = "brewfest", coords = { m = 243, x = 46.6, y = 60.0 } },
      [999] = { name = "Bare Holiday", tab = "holiday", section = "noblegarden", coords = { m = 27, x = 1, y = 2 } },
      [267] = { name = "Violet Proto-Drake", tab = "holiday", section = "other", coords = { m = 28, x = 3, y = 4 } },
      [500] = { name = "Not Holiday", tab = "journal", section = "brewfest", coords = { m = 29, x = 5, y = 6 } },
    }, {
      brewfest = { title = "Brewfest", coords = { m = 242, x = 46.6, y = 60.0 } },
      noblegarden = { title = "Noblegarden" },
    })
    local api = fakeApi({ canSet = { [242] = true, [243] = true, [27] = true, [28] = true, [29] = true } })
    eq(Map.Resolve(226, api), { map = 242, x = 46.6, y = 60.0, kind = "pin" }, "holiday coords win")
    eq(Map.Resolve(999, api), { map = 27, x = 1, y = 2, kind = "pin" }, "holiday without coords")
    eq(Map.Resolve(267, api), { map = 28, x = 3, y = 4, kind = "pin" }, "section not a holiday key")
    eq(Map.Resolve(500, api), { map = 29, x = 5, y = 6, kind = "pin" }, "not on the holiday tab")
  end)

  it("survives a missing API table entries and erroring calls", function()
    local Map = loadMap({ [1] = { name = "M", coords = { m = 10, x = 1, y = 2 } }, [2] = { name = "N", coords = { m = 11 } } })
    eq(Map.Resolve(1, {}), { map = 10, kind = "open" })
    local api = fakeApi({})
    api.C_Map.CanSetUserWaypointOnMap = function() error("boom") end
    api.C_EncounterJournal.GetInstanceForGameMap = function() error("boom") end
    eq(Map.Resolve(2, api), { map = 11, kind = "open" })
  end)

  it("defaults to the real globals and does not error when they are absent", function()
    local Map = loadMap({ [1] = { name = "M", coords = { m = 10 } } })
    eq(Map.Resolve(1), { map = 10, kind = "open" })
  end)
end)

-- Log entries named `what`, in order.
local function logOf(api, what)
  local out = {}
  for _, entry in ipairs(api.log) do if entry[1] == what then out[#out + 1] = entry end end
  return out
end

-- Log entry names, in order (to check call order).
local function names(api)
  local out = {}
  for _, entry in ipairs(api.log) do out[#out + 1] = entry[1] end
  return out
end

local SERPENT = { name = "Heavenly Onyx Cloud Serpent", coords = { m = 379, x = 53.6, y = 64.4 } }
local DRAKE = { name = "Drake of the North Wind", coords = { m = 325 } }
local TANK = { name = "Red Qiraji Battle Tank", coords = { m = 319 } }

local function drakeApi(names_)
  return fakeApi({
    canSet = { [249] = true, [379] = true }, journal = { [325] = 68 }, parents = { [325] = 249 },
    entrances = { [249] = { { journalInstanceID = 68, position = { x = 0.5, y = 0.25 } } } },
    names = names_,
  })
end

describe("Map.SetWaypoint", function()
  it("pin: sets and super-tracks the waypoint, adds TomTom, prints the zone, never opens the map", function()
    local Map = loadMap({ [517] = SERPENT })
    local api = fakeApi({ canSet = { [379] = true }, names = { [379] = "Kun-Lai Summit" } })
    local place, kind = Map.SetWaypoint(517, api)
    eq(place, "Kun-Lai Summit")
    eq(kind, "pin")
    local wp = logOf(api, "SetUserWaypoint")
    eq(#wp, 1)
    eq(wp[1][2].uiMapID, 379)
    ok(near(wp[1][2].x, 0.536) and near(wp[1][2].y, 0.644), "0-1 coordinates")
    eq(logOf(api, "SuperTrack"), { { "SuperTrack", true } })
    eq(#logOf(api, "OpenWorldMap"), 0, "the world map is not opened")
    local tt = logOf(api, "TomTom")
    eq(#tt, 1)
    eq(tt[1][2], 379)
    eq(tt[1][5], { title = "Heavenly Onyx Cloud Serpent", persistent = false })
    eq(logOf(api, "Print"), { { "Print", "Waypoint: Kun-Lai Summit" } })
  end)

  it("pin: falls back to the source text's Zone:, then the mount name", function()
    local Map, ns = loadMap({ [517] = SERPENT })
    ns.Game = { MountSourceText = function(id) return id == 517 and "Drop: Sha of Anger|nZone: Kun-Lai Summit" or nil end }
    ns.UI = { SourceZone = function(text) return text and text:match("Zone: (.+)$") or nil end }
    local api = fakeApi({ canSet = { [379] = true } })
    eq(Map.SetWaypoint(517, api), "Kun-Lai Summit")
    eq(logOf(api, "Print"), { { "Print", "Waypoint: Kun-Lai Summit" } })
    ns.Game.MountSourceText = function() return nil end
    api = fakeApi({ canSet = { [379] = true } })
    eq(Map.SetWaypoint(517, api), "Heavenly Onyx Cloud Serpent")
  end)

  it("entrance: pins the entrance and names the instance", function()
    local Map = loadMap({ [395] = DRAKE })
    local api = drakeApi({ [325] = "The Vortex Pinnacle", [249] = "Uldum" })
    local place, kind = Map.SetWaypoint(395, api)
    eq(place, "The Vortex Pinnacle (entrance)")
    eq(kind, "entrance")
    eq(logOf(api, "SetUserWaypoint")[1][2], { uiMapID = 249, x = 0.5, y = 0.25 })
    eq(logOf(api, "TomTom")[1], { "TomTom", 249, 0.5, 0.25, { title = "Drake of the North Wind", persistent = false } })
    eq(#logOf(api, "OpenWorldMap"), 0)
    eq(logOf(api, "Print"), { { "Print", "Waypoint: The Vortex Pinnacle (entrance)" } })
  end)

  it("entrance: instance name from the source Zone:, else the instance map, else the route, else the parent", function()
    local Map, ns = loadMap({ [395] = DRAKE })
    ns.Game = { MountSourceText = function() return "Zone: Vortex Pinnacle" end }
    ns.UI = { SourceZone = function(text) return text and text:match("Zone: (.+)$") or nil end,
              RouteEntry = function() return { boss = "Altairus", instance = "The Vortex Pinnacle (route)" } end }
    eq(Map.SetWaypoint(395, drakeApi({ [325] = "The Vortex Pinnacle", [249] = "Uldum" })),
      "Vortex Pinnacle (entrance)", "source Zone: first, as UI.SubGroup")
    ns.Game.MountSourceText = function() return nil end
    eq(Map.SetWaypoint(395, drakeApi({ [325] = "The Vortex Pinnacle", [249] = "Uldum" })),
      "The Vortex Pinnacle (entrance)", "instance map name")
    eq(Map.SetWaypoint(395, drakeApi({ [249] = "Uldum" })), "The Vortex Pinnacle (route) (entrance)", "route instance")
    ns.UI.RouteEntry = function() return nil end
    eq(Map.SetWaypoint(395, drakeApi({ [249] = "Uldum" })), "Uldum (entrance)", "parent map")
  end)

  it("open: opens the world map there, no pin, prints Opened map", function()
    local Map = loadMap({ [118] = TANK })
    local api = fakeApi({ names = { [319] = "Ahn'Qiraj" } })
    local place, kind = Map.SetWaypoint(118, api)
    eq(place, "Ahn'Qiraj")
    eq(kind, "open")
    eq(logOf(api, "OpenWorldMap"), { { "OpenWorldMap", 319 } })
    eq(#logOf(api, "SetUserWaypoint"), 0)
    eq(#logOf(api, "TomTom"), 0)
    eq(logOf(api, "Print"), { { "Print", "Opened map: Ahn'Qiraj" } })
  end)

  it("none: prints the no-location message and returns nil", function()
    local Map = loadMap({ [6] = { name = "Brown Horse" } })
    local api = fakeApi({})
    local place, kind = Map.SetWaypoint(6, api)
    eq(place, nil)
    eq(kind, "none")
    eq(api.log, { { "Print", "No map location for Brown Horse" } })
  end)

  it("replaces the previous AzerothTrail TomTom waypoint", function()
    local Map = loadMap({ [517] = SERPENT, [395] = DRAKE, [118] = TANK, [6] = { name = "Brown Horse" } })
    local api = drakeApi({ [379] = "Kun-Lai Summit" })
    Map.SetWaypoint(517, api)
    eq(#logOf(api, "TomTomRemove"), 0, "nothing to remove the first time")
    Map.SetWaypoint(395, api)
    eq(logOf(api, "TomTomRemove"), { { "TomTomRemove", "uid1" } })
    local order = names(api)
    local removeAt, addAt
    for i, n in ipairs(order) do
      if n == "TomTomRemove" then removeAt = i end
      if n == "TomTom" then addAt = i end
    end
    ok(removeAt < addAt, "removed before the new one is added")
    Map.SetWaypoint(118, api) -- open: no new waypoint, the old one stays
    Map.SetWaypoint(6, api) -- none: the old one stays
    eq(#logOf(api, "TomTomRemove"), 1)
    Map.SetWaypoint(517, api)
    eq(logOf(api, "TomTomRemove"), { { "TomTomRemove", "uid1" }, { "TomTomRemove", "uid2" } })
  end)

  it("survives TomTom errors and a missing TomTom", function()
    local Map, ns = loadMap({ [517] = SERPENT })
    local reported = {}
    ns.Game = { ReportError = function(err) reported[#reported + 1] = tostring(err) end }
    local api = fakeApi({ canSet = { [379] = true }, tomtom = false })
    api.TomTom = { AddWaypoint = function() error("add broke") end, RemoveWaypoint = function() error("remove broke") end }
    eq(Map.SetWaypoint(517, api), "Heavenly Onyx Cloud Serpent")
    Map.SetWaypoint(517, api) -- failed add left no uid: nothing to remove
    eq(#reported, 2)
    ok(reported[1]:find("add broke", 1, true), reported[1])
    local n = 0
    api.TomTom = {
      AddWaypoint = function() n = n + 1; return "u" .. n end,
      RemoveWaypoint = function() error("remove broke") end,
    }
    Map.SetWaypoint(517, api)
    Map.SetWaypoint(517, api) -- remove errors, the new one is still added
    eq(n, 2)
    ok(reported[#reported]:find("remove broke", 1, true), reported[#reported])
    api = fakeApi({ canSet = { [379] = true }, tomtom = false })
    eq(Map.SetWaypoint(517, api), "Heavenly Onyx Cloud Serpent")
    eq(#logOf(api, "SetUserWaypoint"), 1)
  end)

  it("in combat: open targets do not open the map; pins still set the waypoint", function()
    local Map = loadMap({ [517] = SERPENT, [118] = TANK })
    local api = fakeApi({ combat = true, canSet = { [379] = true }, names = { [379] = "Kun-Lai Summit", [319] = "Ahn'Qiraj" } })
    eq({ Map.SetWaypoint(118, api) }, { "Ahn'Qiraj", "open" })
    eq(#logOf(api, "OpenWorldMap"), 0, "no OpenWorldMap in combat")
    eq(logOf(api, "Print"), { { "Print", "Can't open the map in combat" } })
    api = fakeApi({ combat = true, canSet = { [379] = true }, names = { [379] = "Kun-Lai Summit" } })
    eq(Map.SetWaypoint(517, api), "Kun-Lai Summit")
    eq(#logOf(api, "SetUserWaypoint"), 1)
    eq(#logOf(api, "TomTom"), 1)
    eq(logOf(api, "Print"), { { "Print", "Waypoint: Kun-Lai Summit" } })
  end)

  it("opens the map instead when the target map takes no waypoint and TomTom is not used", function()
    local Map = loadMap({ [395] = DRAKE })
    local names_ = { [325] = "The Vortex Pinnacle" }
    local function api(opts)
      opts.journal, opts.parents = { [325] = 68 }, { [325] = 249 }
      opts.entrances = { [249] = { { journalInstanceID = 68, position = { x = 0.5, y = 0.25 } } } }
      opts.names = names_
      return fakeApi(opts)
    end
    -- No user waypoint on 249, no TomTom: open the map.
    local a = api({ tomtom = false })
    eq({ Map.SetWaypoint(395, a) }, { "The Vortex Pinnacle (entrance)", "entrance" })
    eq(#logOf(a, "SetUserWaypoint"), 0)
    eq(logOf(a, "OpenWorldMap"), { { "OpenWorldMap", 249 } })
    eq(logOf(a, "Print"), { { "Print", "Opened map: The Vortex Pinnacle (entrance)" } })
    -- TomTom took it: that is the waypoint, no map.
    a = api({})
    Map.SetWaypoint(395, a)
    eq(#logOf(a, "TomTom"), 1)
    eq(#logOf(a, "OpenWorldMap"), 0)
    eq(logOf(a, "Print"), { { "Print", "Waypoint: The Vortex Pinnacle (entrance)" } })
    -- TomTom failing counts as not used.
    a = api({ tomtom = false })
    a.TomTom = { AddWaypoint = function() error("tomtom broke") end }
    Map.SetWaypoint(395, a)
    eq(logOf(a, "OpenWorldMap"), { { "OpenWorldMap", 249 } })
    -- SetUserWaypoint failing counts as not set.
    a = api({ tomtom = false, canSet = { [249] = true } })
    a.C_Map.SetUserWaypoint = function() error("bad point") end
    Map.SetWaypoint(395, a)
    eq(#logOf(a, "SuperTrack"), 0, "nothing to super-track")
    eq(logOf(a, "OpenWorldMap"), { { "OpenWorldMap", 249 } })
    eq(logOf(a, "Print"), { { "Print", "Opened map: The Vortex Pinnacle (entrance)" } })
    -- The fallback respects the combat guard.
    a = api({ tomtom = false, combat = true })
    Map.SetWaypoint(395, a)
    eq(#logOf(a, "OpenWorldMap"), 0)
    eq(logOf(a, "Print"), { { "Print", "Can't open the map in combat" } })
  end)

  it("reports swallowed errors through ns.Game.ReportError (/azt debug)", function()
    local Map, ns = loadMap({ [1] = { name = "M", coords = { m = 5, x = 10, y = 20 } } })
    local reported = {}
    ns.Game = { ReportError = function(err) reported[#reported + 1] = tostring(err) end }
    local api = fakeApi({ canSet = { [5] = true }, tomtom = false })
    api.C_Map.SetUserWaypoint = function() error("bad point") end
    api.OpenWorldMap = function() error("combat") end
    api.TomTom = { AddWaypoint = function() error("tomtom broke") end }
    Map.SetWaypoint(1, api)
    eq(#reported, 3)
    ok(reported[1]:find("bad point", 1, true), reported[1])
    ok(reported[2]:find("tomtom broke", 1, true), reported[2])
    ok(reported[3]:find("combat", 1, true), reported[3])
  end)

  it("drops an identical chat line repeated within 2 s", function()
    local Map = loadMap({ [6] = { name = "Brown Horse" }, [7] = { name = "Grey Horse" } })
    local clock = { now = 100 }
    local api = fakeApi({ clock = clock })
    local function prints() return #logOf(api, "Print") end
    Map.SetWaypoint(6, api)
    clock.now = 101.9
    Map.SetWaypoint(6, api)
    eq(prints(), 1, "same line within 2 s: dropped")
    clock.now = 102
    Map.SetWaypoint(7, api)
    eq(prints(), 2, "another line")
    clock.now = 102.5
    Map.SetWaypoint(6, api)
    eq(prints(), 3, "the last line differs: printed")
    clock.now = 104.6
    Map.SetWaypoint(6, api)
    eq(prints(), 4, "2 s later: printed again")
    Map.OpenMap(6, api)
    eq(prints(), 4, "OpenMap's line is de-duplicated too")
  end)

  it("does not error with missing APIs and prints through ns.addon by default", function()
    local Map, ns = loadMap({ [517] = SERPENT })
    local printed = {}
    ns.addon = { Print = function(self, msg) printed[#printed + 1] = msg end }
    -- No C_Map: the mount resolves to "open"; the label falls back to the
    -- mount name.
    eq(Map.SetWaypoint(517, {}), "Heavenly Onyx Cloud Serpent")
    eq(Map.SetWaypoint(517), "Heavenly Onyx Cloud Serpent") -- the real globals
    eq(Map.SetWaypoint(99999), nil)
    eq(printed, { "Opened map: Heavenly Onyx Cloud Serpent", "Opened map: Heavenly Onyx Cloud Serpent",
      "No map location for 99999" }, "no clock in {}: nothing recorded to de-duplicate against")
  end)
end)

describe("Map.OpenMap", function()
  it("opens the world map at the target without a waypoint or TomTom", function()
    local Map = loadMap({ [517] = SERPENT, [395] = DRAKE, [118] = TANK })
    local api = drakeApi({})
    eq(Map.OpenMap(517, api).kind, "pin")
    eq(Map.OpenMap(395, api).kind, "entrance")
    eq(Map.OpenMap(118, api).kind, "open")
    eq(logOf(api, "OpenWorldMap"), { { "OpenWorldMap", 379 }, { "OpenWorldMap", 249 }, { "OpenWorldMap", 319 } })
    eq(#logOf(api, "SetUserWaypoint"), 0)
    eq(#logOf(api, "SuperTrack"), 0)
    eq(#logOf(api, "TomTom"), 0)
    eq(#logOf(api, "Print"), 0)
  end)

  it("prints the no-location message for a mount without one", function()
    local Map = loadMap({ [6] = { name = "Brown Horse" } })
    local api = fakeApi({})
    eq(Map.OpenMap(6, api).kind, "none")
    eq(api.log, { { "Print", "No map location for Brown Horse" } })
  end)

  it("does not open the map in combat", function()
    local Map = loadMap({ [517] = SERPENT })
    local api = fakeApi({ combat = true, canSet = { [379] = true } })
    eq(Map.OpenMap(517, api).kind, "pin")
    eq(#logOf(api, "OpenWorldMap"), 0)
    eq(logOf(api, "Print"), { { "Print", "Can't open the map in combat" } })
  end)

  it("reads combat from ns.Game.InCombat by default", function()
    local Map, ns = loadMap({ [118] = TANK })
    local printed = {}
    ns.addon = { Print = function(self, msg) printed[#printed + 1] = msg end }
    ns.Game = { InCombat = function() return true end }
    Map.OpenMap(118)
    eq(printed, { "Can't open the map in combat" })
  end)
end)

describe("Map.HasLocation", function()
  it("is true when the mount (or its holiday) has coords, without any API call", function()
    local Map = loadMap({
      [517] = SERPENT, [118] = TANK, [6] = { name = "Brown Horse" },
      [226] = { name = "Great Brewfest Kodo", tab = "holiday", section = "brewfest" },
      [227] = { name = "Bare Holiday", tab = "holiday", section = "noblegarden" },
    }, {
      brewfest = { title = "Brewfest", coords = { m = 242, x = 46.6, y = 60.0 } },
      noblegarden = { title = "Noblegarden" },
    })
    eq(Map.HasLocation(517), true)
    eq(Map.HasLocation(118), true, "map-only coords: the map opens")
    eq(Map.HasLocation(226), true, "holiday coords")
    eq(Map.HasLocation(227), false, "holiday without coords, mount without coords")
    eq(Map.HasLocation(6), false)
    eq(Map.HasLocation(99999), false)
    eq(Map.HasLocation(nil), false)
  end)
end)

describe("Map.CoordsFor", function()
  it("is the mount's coords, its holiday's when it has some, else nil (the zone panel's lookup)", function()
    local Map = loadMap({
      [517] = SERPENT, [6] = { name = "Brown Horse" },
      [226] = { name = "Great Brewfest Kodo", tab = "holiday", section = "brewfest", coords = { m = 1 } },
      [227] = { name = "Bare Holiday", tab = "holiday", section = "noblegarden", coords = { m = 2 } },
    }, {
      brewfest = { title = "Brewfest", coords = { m = 242, x = 46.6, y = 60.0 } },
      noblegarden = { title = "Noblegarden" },
    })
    eq(Map.CoordsFor(517), SERPENT.coords)
    eq(Map.CoordsFor(226).m, 242, "holiday coords win")
    eq(Map.CoordsFor(227), { m = 2 }, "holiday without coords: the mount's own")
    eq(Map.CoordsFor(6), nil)
    eq(Map.CoordsFor(nil), nil)
  end)
end)

describe("integrations toc", function()
  it("lists Integrations after Game/API.lua and before Core/Init.lua", function()
    local files = toc_lua_files()
    local pos = {}
    for i, f in ipairs(files) do pos[f] = i end
    ok(pos["Integrations/Map.lua"] and pos["Integrations/Rarity.lua"], "both listed")
    ok(pos["Game/API.lua"] < pos["Integrations/Map.lua"], "Map after Game/API")
    ok(pos["Game/API.lua"] < pos["Integrations/Rarity.lua"], "Rarity after Game/API")
    eq(files[#files], "Core/Init.lua")
    local ns = load_addon(files)
    ok(ns.Map and ns.Map.Resolve and ns.Map.SetWaypoint and ns.Map.OpenMap and ns.Map.HasLocation, "ns.Map loaded")
    eq(ns.Map.Show, nil, "Map.Show removed (no callers since F5)")
    ok(ns.RarityBridge and ns.RarityBridge.Attempts, "ns.RarityBridge loaded")
  end)
end)

-- F9: the "Waypoints" setting (ns.db.global.settings.waypoints).
describe("Map.WaypointMode", function()
  it("reads the setting; missing or unknown values are the in-game pin", function()
    local Map, ns = loadMap({})
    eq(Map.WaypointMode(), "game", "no ns.db yet")
    ns.db = { global = {} }
    eq(Map.WaypointMode(), "game", "no settings table")
    for _, mode in ipairs({ "game", "tomtom", "both" }) do
      ns.db.global.settings = { waypoints = mode }
      eq(Map.WaypointMode(), mode)
    end
    ns.db.global.settings = { waypoints = "arrow" }
    eq(Map.WaypointMode(), "game", "unknown value")
    ns.db.global.settings = "junk"
    eq(Map.WaypointMode(), "game", "junk settings")
  end)
end)

describe("Map.SetWaypoint waypoint modes", function()
  local function serpentApi(opts)
    opts.canSet = opts.canSet or { [379] = true }
    opts.names = { [379] = "Kun-Lai Summit" }
    return fakeApi(opts)
  end

  it("game: only the user waypoint and super-track, never TomTom", function()
    local Map = loadMap({ [517] = SERPENT })
    local api = serpentApi({ mode = "game" })
    eq({ Map.SetWaypoint(517, api) }, { "Kun-Lai Summit", "pin" })
    eq(#logOf(api, "SetUserWaypoint"), 1)
    eq(logOf(api, "SuperTrack"), { { "SuperTrack", true } })
    eq(#logOf(api, "TomTom"), 0, "TomTom installed but not used")
    eq(#logOf(api, "TomTomRemove"), 0)
    eq(logOf(api, "Print"), { { "Print", "Waypoint: Kun-Lai Summit" } }, "chat line unchanged")
  end)

  it("game: an entrance map without user waypoints opens the world map, not TomTom", function()
    local Map = loadMap({ [395] = DRAKE })
    local api = fakeApi({ mode = "game", journal = { [325] = 68 }, parents = { [325] = 249 },
      entrances = { [249] = { { journalInstanceID = 68, position = { x = 0.5, y = 0.25 } } } },
      names = { [325] = "The Vortex Pinnacle" } })
    eq({ Map.SetWaypoint(395, api) }, { "The Vortex Pinnacle (entrance)", "entrance" })
    eq(#logOf(api, "TomTom"), 0, "TomTom installed but the mode is game")
    eq(logOf(api, "OpenWorldMap"), { { "OpenWorldMap", 249 } })
    eq(logOf(api, "Print"), { { "Print", "Opened map: The Vortex Pinnacle (entrance)" } })
  end)

  it("tomtom: only the TomTom waypoint (replacing ours), no user waypoint", function()
    local Map = loadMap({ [517] = SERPENT })
    local api = serpentApi({ mode = "tomtom" })
    eq({ Map.SetWaypoint(517, api) }, { "Kun-Lai Summit", "pin" })
    eq(#logOf(api, "SetUserWaypoint"), 0)
    eq(#logOf(api, "SuperTrack"), 0)
    eq(logOf(api, "TomTom")[1], { "TomTom", 379, 0.536, 0.644, { title = "Heavenly Onyx Cloud Serpent", persistent = false } })
    eq(logOf(api, "Print"), { { "Print", "Waypoint: Kun-Lai Summit" } })
    Map.SetWaypoint(517, api)
    eq(logOf(api, "TomTomRemove"), { { "TomTomRemove", "uid1" } }, "still one AzerothTrail TomTom waypoint")
    eq(#logOf(api, "SetUserWaypoint"), 0)
  end)

  it("tomtom: falls back to the in-game pin when TomTom is missing or fails", function()
    local Map = loadMap({ [517] = SERPENT })
    local api = serpentApi({ mode = "tomtom", tomtom = false })
    eq(Map.SetWaypoint(517, api), "Kun-Lai Summit")
    eq(#logOf(api, "SetUserWaypoint"), 1, "TomTom not loaded: the game pin")
    eq(logOf(api, "SuperTrack"), { { "SuperTrack", true } })
    eq(logOf(api, "Print"), { { "Print", "Waypoint: Kun-Lai Summit" } })
    api = serpentApi({ mode = "tomtom", tomtom = false })
    api.TomTom = { AddWaypoint = function() error("tomtom broke") end }
    Map.SetWaypoint(517, api)
    eq(#logOf(api, "SetUserWaypoint"), 1, "TomTom failed: the game pin")
    api = serpentApi({ mode = "tomtom", tomtom = false })
    api.TomTom = {} -- loaded without AddWaypoint
    Map.SetWaypoint(517, api)
    eq(#logOf(api, "SetUserWaypoint"), 1)
  end)

  it("both: the user waypoint and TomTom, as before F9", function()
    local Map = loadMap({ [517] = SERPENT })
    local api = serpentApi({ mode = "both" })
    Map.SetWaypoint(517, api)
    eq(#logOf(api, "SetUserWaypoint"), 1)
    eq(#logOf(api, "TomTom"), 1)
    eq(logOf(api, "Print"), { { "Print", "Waypoint: Kun-Lai Summit" } })
  end)

  it("without api.waypointMode the saved setting decides (default: the in-game pin)", function()
    local Map, ns = loadMap({ [517] = SERPENT })
    local api = serpentApi({})
    api.waypointMode = nil
    Map.SetWaypoint(517, api)
    eq(#logOf(api, "SetUserWaypoint"), 1)
    eq(#logOf(api, "TomTom"), 0, "default: game only")
    ns.db = { global = { settings = { waypoints = "tomtom" } } }
    api = serpentApi({})
    api.waypointMode = nil
    Map.SetWaypoint(517, api)
    eq(#logOf(api, "SetUserWaypoint"), 0)
    eq(#logOf(api, "TomTom"), 1, "the saved setting")
  end)

  it("open and none targets ignore the mode", function()
    local Map = loadMap({ [118] = TANK, [6] = { name = "Brown Horse" } })
    for _, mode in ipairs({ "game", "tomtom", "both" }) do
      local api = fakeApi({ mode = mode, names = { [319] = "Ahn'Qiraj" } })
      eq({ Map.SetWaypoint(118, api) }, { "Ahn'Qiraj", "open" }, mode)
      eq(logOf(api, "OpenWorldMap"), { { "OpenWorldMap", 319 } }, mode)
      eq(#logOf(api, "TomTom"), 0, mode)
      eq({ Map.SetWaypoint(6, api) }, { nil, "none" }, mode)
    end
  end)
end)
