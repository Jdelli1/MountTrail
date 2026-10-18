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
