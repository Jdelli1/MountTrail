-- The zone panel's glue (UI/ZonePanel.lua): UI.ZoneContext wires Zone.MountsFor
-- to ns.Game / ns.Map / the list helpers; UI.ZoneTitle and UI.ZoneRows shape
-- the header and rows. The panel widget is built in tests/ui_build_spec.lua.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/ZonePanel.lua" }

-- 12 Kalimdor > 249 Uldum > 325 Vortex Pinnacle (floor); 71 Tanaris.
local MAPS = {
  [12] = { name = "Kalimdor", mapType = 2 },
  [249] = { name = "Uldum", mapType = 3, parentMapID = 12 },
  [325] = { name = "The Vortex Pinnacle", mapType = 4, parentMapID = 249 },
  [71] = { name = "Tanaris", mapType = 3, parentMapID = 12 },
}

local SOURCES = {
  [2] = "|cFFFFD200Zone:|r Uldum",
  [3] = "|cFFFFD200Drop:|r Altairus|n|cFFFFD200Zone:|r The Vortex Pinnacle",
  [5] = "|cFFFFD200Zone:|r Vortex Pinnacle",
  [6] = "|cFFFFD200Zone:|r Uldum",
}

local function loadUI(over)
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  local calls = { source = 0 }
  local game = {
    MountInfo = function() return nil end,
    IsOwned = function(id) return id == 4 end,
    Exists = function() return true end,
    Faction = function() return "Alliance" end,
    MountSourceText = function(id) calls.source = calls.source + 1; return SOURCES[id] or "" end,
    MapName = function(id) return MAPS[id] and MAPS[id].name end,
    MapInfo = function(id) return MAPS[id] end,
    PlayerMap = function() return 249 end,
    DungeonEntrances = function(id)
      if id == 249 then return { { journalInstanceID = 68, name = "The Vortex Pinnacle" } } end
      return {}
    end,
    MapChildren = function() return {} end,
    InstanceForMap = function(id) if id == 325 then return 68 end end,
    JournalInstanceName = function(id) if id == 68 then return "The Vortex Pinnacle" end end,
  }
  for k, v in pairs(over or {}) do game[k] = v end
  for k, v in pairs(game) do ns.Game[k] = v end
  ns.Data.Mounts = {
    [1] = { name = "Holiday on Uldum", tab = "holiday", section = "brewfest" },
    [2] = { name = "Horde only", tab = "journal", section = "world", faction = "Horde" },
    [3] = { name = "Drake of the North Wind", tab = "journal", section = "dungeon" },
    [4] = { name = "Owned here", tab = "journal", section = "world", coords = { m = 249 } },
    [5] = { name = "World mount named like the dungeon", tab = "journal", section = "world" },
    [6] = { name = "Source Uldum", tab = "misc", section = "other" },
    [7] = { name = "Route boss", tab = "journal", section = "raid" },
    [8] = { name = "Tanaris rare", tab = "journal", section = "world", coords = { m = 71 } },
  }
  ns.Data.Holidays = { brewfest = { title = "Brewfest", coords = { m = 249, x = 1, y = 1 } } }
  ns.Data.Route = { { title = "Run The Vortex Pinnacle (Dungeon)", bosses = { { boss = "Asaad", mount = 7 } } } }
  return ns, calls
end

local function ids(list)
  local out = {}
  for _, row in ipairs(list) do out[#out + 1] = row.id end
  return out
end

describe("zone panel glue", function()
  it("ZoneContext feeds Zone.MountsFor from the game, the map data and the list helpers", function()
    local ns = loadUI()
    local list, zone = ns.Zone.MountsFor(249, ns.UI.ZoneContext())
    -- 1 holiday coords, 3 instance sub-group (dungeon), 6 source Zone:, 7 route
    -- instance; 2 other faction, 4 owned, 5 a world mount (no instance
    -- sub-group), 8 another zone.
    eq(ids(list), { 3, 1, 7, 6 })
    eq(zone, { mapID = 249, name = "Uldum" })
    local via = {}
    for _, row in ipairs(list) do via[row.id] = row.via end
    eq(via, { [1] = "coords", [3] = "instance", [6] = "source", [7] = "instance" })
  end)

  it("the Collected filter keeps owned mounts", function()
    local ns = loadUI()
    ns.db.global.filters.collected = true
    local list = ns.Zone.MountsFor(249, ns.UI.ZoneContext())
    local owned
    for _, row in ipairs(list) do if row.id == 4 then owned = row end end
    ok(owned and owned.owned == true, "owned mount listed and marked")
  end)

  it("reads each mount's source text once per session", function()
    local ns, calls = loadUI()
    ns.Zone.MountsFor(249, ns.UI.ZoneContext())
    ns.Zone.MountsFor(71, ns.UI.ZoneContext())
    local first = calls.source
    ok(first > 0, "source text read")
    ns.Zone.MountsFor(249, ns.UI.ZoneContext())
    ns.Zone.MountsFor(71, ns.UI.ZoneContext())
    eq(calls.source - first, 0, "later refreshes: no new reads")
  end)

  it("ZoneTitle names the zone and counts the rows", function()
    local ns = loadUI()
    eq(ns.UI.ZoneTitle({ name = "Uldum" }, 3), "Mounts in Uldum  |cff9d9d9d(3)|r")
    eq(ns.UI.ZoneTitle(nil, 0), "Mounts in this zone  |cff9d9d9d(0)|r")
  end)

  it("ZoneRows: striped rows with the list's description and pin", function()
    local ns = loadUI()
    ns.Map.HasLocation = function(id) return id == 3 end
    local rows = ns.UI.ZoneRows({ { id = 3, m = ns.Data.Mounts[3], owned = false },
      { id = 6, m = ns.Data.Mounts[6], owned = true } })
    eq(rows[1].desc, "Drop: Altairus · The Vortex Pinnacle")
    eq(rows[1].pin, true)
    eq(rows[1].alt, false)
    eq(rows[2].alt, true)
    eq(rows[2].pin, false)
    eq(rows[2].owned, true)
  end)

  it("ZoneMounts: the player's map through ZoneContext; errors give an empty list", function()
    local ns = loadUI()
    local list, zone = ns.UI.ZoneMounts()
    eq(zone.name, "Uldum")
    eq(#list, 4)
    ns.Game.PlayerMap = function() return nil end
    list, zone = ns.UI.ZoneMounts()
    eq(list, {})
    eq(zone, nil)
    ns.Game.Faction = function() error("boom") end
    ns.Game.PlayerMap = function() return 249 end
    list, zone = ns.UI.ZoneMounts()
    eq(list, {}, "error caught")
  end)

  it("asks the map and journal lookups once per session", function()
    local ns = loadUI()
    local asked = {}
    for _, name in ipairs({ "MapInfo", "DungeonEntrances", "MapChildren", "JournalInstanceName" }) do
      local real = ns.Game[name]
      asked[name] = 0
      ns.Game[name] = function(...) asked[name] = asked[name] + 1; return real(...) end
    end
    ns.UI.ZoneMounts()
    local first = {}
    for k, v in pairs(asked) do first[k] = v; ok(v > 0, k .. " asked") end
    ns.UI.ZoneMounts()
    eq(asked, first, "second build: all from the session cache")
  end)
end)
