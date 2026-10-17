-- Map.Resolve picks where a mount's Map button should point; Map.Show acts on
-- it. Both take the WoW API through an injected table, so these specs never
-- touch globals.

local function loadMap(mounts, holidays)
  local ns = load_addon({ "Core/Locale.lua", "Integrations/Map.lua" })
  ns.Data = { Mounts = mounts or {}, Holidays = holidays or {} }
  return ns.Map, ns
end

-- A fake WoW API. opts.canSet: set of map IDs that take a user waypoint.
-- opts.parents: map ID -> parent map ID. opts.journal: map ID -> journal
-- instance. opts.entrances: map ID -> list of entrance records.
local function fakeApi(opts)
  opts = opts or {}
  local log = {}
  local function rec(...) log[#log + 1] = { ... } end
  local api = {
    log = log,
    C_Map = {
      CanSetUserWaypointOnMap = function(m) return (opts.canSet or {})[m] == true end,
      GetMapInfo = function(m)
        local parent = (opts.parents or {})[m]
        if parent == nil then return nil end
        return { mapID = m, parentMapID = parent }
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
  }
  if opts.tomtom ~= false then
    api.TomTom = { AddWaypoint = function(self, m, x, y, o) rec("TomTom", m, x, y, o) end }
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

describe("Map.Show", function()
  local function calls(api, what)
    local out = {}
    for _, entry in ipairs(api.log) do if entry[1] == what then out[#out + 1] = entry end end
    return out
  end

  it("pin: sets and super-tracks the waypoint, opens the map, adds a TomTom waypoint", function()
    local Map = loadMap({ [517] = { name = "Heavenly Onyx Cloud Serpent", coords = { m = 379, x = 53.6, y = 64.4 } } })
    local api = fakeApi({ canSet = { [379] = true } })
    Map.Show(517, api)
    local wp = calls(api, "SetUserWaypoint")
    eq(#wp, 1)
    eq(wp[1][2].uiMapID, 379)
    ok(near(wp[1][2].x, 0.536) and near(wp[1][2].y, 0.644), "waypoint uses 0-1 coordinates")
    eq(calls(api, "SuperTrack"), { { "SuperTrack", true } })
    eq(calls(api, "OpenWorldMap"), { { "OpenWorldMap", 379 } })
    local tt = calls(api, "TomTom")
    eq(#tt, 1)
    eq(tt[1][2], 379)
    ok(near(tt[1][3], 0.536) and near(tt[1][4], 0.644), "TomTom uses 0-1 coordinates")
    eq(tt[1][5], { title = "Heavenly Onyx Cloud Serpent", persistent = false })
    eq(#calls(api, "Print"), 0)
  end)

  it("entrance: pins the entrance on the parent map", function()
    local Map = loadMap({ [395] = { name = "Drake of the North Wind", coords = { m = 325 } } })
    local api = fakeApi({
      canSet = { [249] = true }, journal = { [325] = 68 }, parents = { [325] = 249 },
      entrances = { [249] = { { journalInstanceID = 68, position = { x = 0.5, y = 0.25 } } } },
    })
    Map.Show(395, api)
    local wp = calls(api, "SetUserWaypoint")
    eq(#wp, 1); eq(wp[1][2], { uiMapID = 249, x = 0.5, y = 0.25 })
    eq(calls(api, "OpenWorldMap"), { { "OpenWorldMap", 249 } })
    eq(calls(api, "TomTom")[1], { "TomTom", 249, 0.5, 0.25, { title = "Drake of the North Wind", persistent = false } })
  end)

  it("open: opens the map only, no pin and no TomTom", function()
    local Map = loadMap({ [118] = { name = "Red Qiraji Battle Tank", coords = { m = 319 } } })
    local api = fakeApi({})
    Map.Show(118, api)
    eq(calls(api, "OpenWorldMap"), { { "OpenWorldMap", 319 } })
    eq(#calls(api, "SetUserWaypoint"), 0)
    eq(#calls(api, "TomTom"), 0)
    eq(#calls(api, "Print"), 0)
  end)

  it("none: prints the no-location message and does nothing else", function()
    local Map, ns = loadMap({ [6] = { name = "Brown Horse" } })
    local api = fakeApi({})
    Map.Show(6, api)
    eq(api.log, { { "Print", string.format(ns.L["No map location for %s"], "Brown Horse") } })
    eq(ns.L["No map location for %s"], "No map location for %s")
    api = fakeApi({})
    Map.Show(4242, api)
    eq(api.log, { { "Print", "No map location for 4242" } })
  end)

  it("works without TomTom and when TomTom errors", function()
    local Map = loadMap({ [1] = { name = "M", coords = { m = 5, x = 10, y = 20 } } })
    local api = fakeApi({ canSet = { [5] = true }, tomtom = false })
    Map.Show(1, api)
    eq(#calls(api, "OpenWorldMap"), 1)
    api = fakeApi({ canSet = { [5] = true }, tomtom = false })
    api.TomTom = { AddWaypoint = function() error("tomtom broke") end }
    Map.Show(1, api)
    eq(#calls(api, "OpenWorldMap"), 1)
    api = fakeApi({ canSet = { [5] = true }, tomtom = false })
    api.TomTom = {}
    Map.Show(1, api)
    eq(#calls(api, "OpenWorldMap"), 1)
  end)

  it("does not error when the map APIs are missing or erroring", function()
    local Map = loadMap({ [1] = { name = "M", coords = { m = 5, x = 10, y = 20 } } })
    Map.Show(1, {})
    local api = fakeApi({ canSet = { [5] = true } })
    api.C_Map.SetUserWaypoint = function() error("bad point") end
    api.OpenWorldMap = function() error("combat") end
    Map.Show(1, api)
    eq(#calls(api, "TomTom"), 1, "TomTom still tried")
  end)

  it("reports swallowed errors through ns.Game.ReportError (/azt debug)", function()
    local Map, ns = loadMap({ [1] = { name = "M", coords = { m = 5, x = 10, y = 20 } } })
    local reported = {}
    ns.Game = { ReportError = function(err) reported[#reported + 1] = tostring(err) end }
    local api = fakeApi({ canSet = { [5] = true } })
    api.C_Map.SetUserWaypoint = function() error("bad point") end
    api.OpenWorldMap = function() error("combat") end
    api.TomTom = { AddWaypoint = function() error("tomtom broke") end }
    Map.Show(1, api)
    eq(#reported, 3)
    ok(reported[1]:find("bad point", 1, true), reported[1])
    ok(reported[2]:find("combat", 1, true), reported[2])
    ok(reported[3]:find("tomtom broke", 1, true), reported[3])
  end)

  it("prints through ns.addon by default", function()
    local Map, ns = loadMap({})
    local printed = {}
    ns.addon = { Print = function(self, msg) printed[#printed + 1] = msg end }
    Map.Show(7)
    eq(printed, { "No map location for 7" })
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
    ok(ns.Map and ns.Map.Show and ns.Map.Resolve, "ns.Map loaded")
    ok(ns.RarityBridge and ns.RarityBridge.Attempts, "ns.RarityBridge loaded")
  end)
end)
