-- Raid and dungeon mounts point at the instance entrance (Map.Resolve), found
-- through the Encounter Journal from the lockout data's instance ID (a game
-- map ID, which is what C_EncounterJournal.GetInstanceForGameMap takes), the
-- journal instance's own map (EJ_GetInstanceInfo, 7th return) and the parent
-- zone that lists the entrance (GetDungeonEntrancesForMap).

local function loadMap(mounts, lockouts, route)
  local ns = load_addon({ "Core/Locale.lua", "Logic/Lockouts.lua", "Integrations/Map.lua" })
  ns.Data = { Mounts = mounts or {}, Lockouts = lockouts or {}, BossLockouts = {}, Route = route or {}, Holidays = {} }
  return ns.Map, ns
end

-- opts.games: game map ID -> journal instance; opts.areas: journal instance
-- -> its uiMap (EJ_GetInstanceInfo 7th); opts.parents: uiMap -> parent;
-- opts.entrances: uiMap -> entrance list; opts.canSet: set of uiMaps taking a
-- user waypoint; opts.names: uiMap -> name.
local function fakeApi(opts)
  opts = opts or {}
  local log = {}
  local function rec(...) log[#log + 1] = { ... } end
  return {
    log = log,
    waypointMode = "game",
    C_Map = {
      CanSetUserWaypointOnMap = function(m) return (opts.canSet or {})[m] == true end,
      GetMapInfo = function(m)
        local parent, name = (opts.parents or {})[m], (opts.names or {})[m]
        if parent == nil and name == nil then return nil end
        return { mapID = m, parentMapID = parent, name = name }
      end,
      SetUserWaypoint = function(point) rec("SetUserWaypoint", point) end,
    },
    C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end },
    C_EncounterJournal = {
      GetInstanceForGameMap = function(id) return (opts.games or {})[id] end,
      GetDungeonEntrancesForMap = function(m) return (opts.entrances or {})[m] or {} end,
    },
    EJ_GetInstanceInfo = function(jid)
      local area = (opts.areas or {})[jid]
      if not area then return nil end
      return "Instance " .. jid, "", nil, nil, nil, nil, area
    end,
    UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { m = m, x = x, y = y } end },
    OpenWorldMap = function(m) rec("OpenWorldMap", m) end,
    Print = function(msg) rec("Print", msg) end,
  }
end

local ONYXIA = { name = "Onyxian Drake", tab = "journal", section = "raid", coords = { m = 70, x = 10, y = 20 } }
local ONYXIA_SPEC = { instance = 249, boss = "Onyxia", difficulties = { 3, 4 }, reset = "weekly" }
local ONYXIA_WORLD = {
  games = { [249] = 760 }, areas = { [760] = 248 }, parents = { [248] = 70, [70] = 12 },
  entrances = { [70] = { { journalInstanceID = 760, position = { x = 0.52, y = 0.76 } } } },
  canSet = { [70] = true }, names = { [70] = "Dustwallow Marsh", [248] = "Onyxia's Lair" },
}

describe("Map.Resolve for raid and dungeon mounts", function()
  it("pins the entrance from the lockout's instance ID, even when the data has a zone spot", function()
    local Map = loadMap({ [349] = ONYXIA }, { [349] = ONYXIA_SPEC })
    eq(Map.Resolve(349, fakeApi(ONYXIA_WORLD)), { map = 70, x = 52, y = 76, kind = "entrance" })
  end)

  it("finds the entrance when the mount only has a zone (no x/y)", function()
    local m = { name = "Onyxian Drake", tab = "journal", section = "raid", coords = { m = 70 } }
    local Map = loadMap({ [349] = m }, { [349] = ONYXIA_SPEC })
    eq(Map.Resolve(349, fakeApi(ONYXIA_WORLD)).kind, "entrance")
  end)

  it("uses the route boss's per-boss spec when there is one", function()
    local Map, ns = loadMap({ [349] = ONYXIA }, {}, {
      { title = "Run Onyxia (Raid)", bosses = { { mount = 349, boss = "Onyxia" } } },
    })
    ns.Data.BossLockouts = { Onyxia = ONYXIA_SPEC }
    ns.UI = { RouteBoss = function(id) return id == 349 and "Onyxia" or nil end }
    eq(Map.Resolve(349, fakeApi(ONYXIA_WORLD)).kind, "entrance")
  end)

  it("falls back to the data's spot when the journal knows no entrance", function()
    local Map = loadMap({ [349] = ONYXIA }, { [349] = ONYXIA_SPEC })
    local world = { canSet = { [70] = true } }
    eq(Map.Resolve(349, fakeApi(world)), { map = 70, x = 10, y = 20, kind = "pin" })
  end)

  it("leaves non-instance mounts at their spot", function()
    local rare = { name = "Rare Mount", tab = "journal", section = "world", coords = { m = 70, x = 10, y = 20 } }
    local Map = loadMap({ [1] = rare }, { [1] = { quest = 5, reset = "daily" } })
    eq(Map.Resolve(1, fakeApi(ONYXIA_WORLD)), { map = 70, x = 10, y = 20, kind = "pin" })
  end)

  it("a click pins the entrance and says so", function()
    local Map = loadMap({ [349] = ONYXIA }, { [349] = ONYXIA_SPEC })
    local api = fakeApi(ONYXIA_WORLD)
    local place, kind = Map.SetWaypoint(349, api)
    eq(kind, "entrance")
    eq(api.log[1][1], "SetUserWaypoint")
    eq(api.log[1][2], { m = 70, x = 0.52, y = 0.76 })
    eq(api.log[#api.log], { "Print", "Waypoint: " .. place })
    ok(place:find("(entrance)", 1, true), place)
  end)
end)

describe("Map.Resolve for a mount whose map is the instance itself", function()
  -- Rivendare's Deathcharger: no instance lockout spec (Stratholme has no
  -- lockout), coords on the Stratholme dungeon map (no user waypoints there).
  local RIVENDARE = { name = "Rivendare's Deathcharger", tab = "journal", section = "dungeon",
    coords = { m = 317, x = 14, y = 7 } }
  local MANUAL = { manual = true, reset = "daily", repeatable = true }

  it("pins the entrance on the zone whose entrance list has that instance map", function()
    local Map = loadMap({ [69] = RIVENDARE }, { [69] = MANUAL })
    local api = fakeApi({
      parents = { [317] = 23, [23] = 13 }, areas = { [236] = 317 },
      entrances = { [23] = { { journalInstanceID = 236, name = "Stratholme", position = { x = 0.27, y = 0.11 } } } },
      canSet = { [23] = true }, names = { [317] = "Stratholme", [23] = "Eastern Plaguelands" },
    })
    eq(Map.Resolve(69, api), { map = 23, x = 27, y = 11, kind = "entrance" })
  end)

  it("matches the entrance by name when the journal gives no instance map", function()
    local Map = loadMap({ [69] = RIVENDARE }, { [69] = MANUAL })
    local api = fakeApi({
      parents = { [317] = 23, [23] = 13 },
      entrances = { [23] = {
        { journalInstanceID = 999, name = "Scholomance", position = { x = 0.6, y = 0.7 } },
        { journalInstanceID = 236, name = "Stratholme", position = { x = 0.27, y = 0.11 } },
      } },
      canSet = { [23] = true }, names = { [317] = "Stratholme", [23] = "Eastern Plaguelands" },
    })
    eq(Map.Resolve(69, api), { map = 23, x = 27, y = 11, kind = "entrance" })
  end)

  it("a click pins it (no world map opened)", function()
    local Map = loadMap({ [69] = RIVENDARE }, { [69] = MANUAL })
    local api = fakeApi({
      parents = { [317] = 23, [23] = 13 }, areas = { [236] = 317 },
      entrances = { [23] = { { journalInstanceID = 236, name = "Stratholme", position = { x = 0.27, y = 0.11 } } } },
      canSet = { [23] = true }, names = { [317] = "Stratholme", [23] = "Eastern Plaguelands" },
    })
    local place, kind = Map.SetWaypoint(69, api)
    eq(kind, "entrance")
    for _, entry in ipairs(api.log) do ok(entry[1] ~= "OpenWorldMap", "no map opened") end
    eq(api.log[#api.log], { "Print", "Waypoint: " .. place })
  end)
end)

-- A checklist / route row names the boss it is about: a mount whose own
-- source is an old dungeon but whose row is a raid boss's per-boss spec
-- (Data.BossLockouts) goes to that boss's instance entrance.
describe("Map.Resolve / SetWaypoint / OpenMap with a route boss", function()
  local RIVENDARE = { name = "Rivendare's Deathcharger", tab = "journal", section = "dungeon",
    coords = { m = 317, x = 14, y = 7 } }
  local MANUAL = { manual = true, reset = "daily", repeatable = true }
  local HOARD = { instance = 2579, boss = "Grand Hoarder", difficulties = { 23 }, reset = "weekly" }
  local WORLD = {
    games = { [2579] = 1209 }, areas = { [236] = 317, [1209] = 2190 },
    parents = { [317] = 23, [23] = 13, [2190] = 2025, [2025] = 1978 },
    entrances = {
      [23] = { { journalInstanceID = 236, name = "Stratholme", position = { x = 0.27, y = 0.11 } } },
      [2025] = { { journalInstanceID = 1209, name = "Hoard Vault", position = { x = 0.61, y = 0.84 } } },
    },
    canSet = { [23] = true, [2025] = true },
    names = { [317] = "Stratholme", [23] = "Eastern Plaguelands", [2025] = "Thaldraszus" },
  }

  local function load(mounts)
    local Map, ns = loadMap(mounts or { [69] = RIVENDARE }, { [69] = MANUAL })
    ns.Data.BossLockouts = { ["Grand Hoarder"] = HOARD }
    ns.UI = { RouteBoss = function(id) return id == 69 and "Baron Rivendare" or nil end }
    return Map, ns
  end

  it("without a route boss: the mount's own (first route row's) place, as before", function()
    local Map = load()
    eq(Map.Resolve(69, fakeApi(WORLD)), { map = 23, x = 27, y = 11, kind = "entrance" })
  end)

  it("the given route boss's spec wins: that instance's entrance", function()
    local Map = load()
    eq(Map.Resolve(69, fakeApi(WORLD), "Grand Hoarder"), { map = 2025, x = 61, y = 84, kind = "entrance" })
    -- A boss without a per-boss spec changes nothing.
    eq(Map.Resolve(69, fakeApi(WORLD), "Baron Rivendare"), { map = 23, x = 27, y = 11, kind = "entrance" })
  end)

  it("a mount without coords still finds the boss's entrance", function()
    local Map = load({ [69] = { name = "No Coords" } })
    eq(Map.Resolve(69, fakeApi(WORLD), "Grand Hoarder"), { map = 2025, x = 61, y = 84, kind = "entrance" })
    eq(Map.Resolve(69, fakeApi(WORLD)), { kind = "none" })
  end)

  it("SetWaypoint pins the boss's entrance and names that instance", function()
    local Map = load()
    local api = fakeApi(WORLD)
    local place, kind = Map.SetWaypoint(69, api, "Grand Hoarder")
    eq(kind, "entrance")
    eq(api.log[1], { "SetUserWaypoint", { m = 2025, x = 0.61, y = 0.84 } })
    eq(place, "Instance 1209 (entrance)", "the journal's instance name, not Stratholme")
    eq(api.log[#api.log], { "Print", "Waypoint: Instance 1209 (entrance)" })
  end)

  it("OpenMap opens the boss's entrance map", function()
    local Map = load()
    eq(Map.OpenMap(69, fakeApi(WORLD), "Grand Hoarder").map, 2025)
    eq(Map.OpenMap(69, fakeApi(WORLD)).map, 23)
  end)
end)
