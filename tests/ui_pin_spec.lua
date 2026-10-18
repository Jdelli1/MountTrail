-- Row location icons and the zone-only click message: a pin only where a
-- click can drop a waypoint on a spot (x/y coords, or a dungeon / raid
-- entrance); a map icon where only the zone is known.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua" }

local function loadUI(mounts, route)
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  ns.Data.Mounts = mounts or {}
  ns.Data.Route = route or {}
  ns.Data.Holidays = {}
  return ns
end

local MOUNTS = {
  [1] = { name = "Spot Mount", tab = "journal", section = "world", coords = { m = 10, x = 40, y = 50 } },
  [2] = { name = "Great Sea Ray", tab = "misc", section = "profession", coords = { m = 896 } },
  [3] = { name = "Raid Mount", tab = "journal", section = "raid", coords = { m = 248 } },
  [4] = { name = "Routed Mount", tab = "journal", section = "other", coords = { m = 657 } },
  [5] = { name = "Nowhere", tab = "misc", section = "shop" },
}

local ROUTE = {
  { title = "Run Vortex Pinnacle (Dungeon)", bosses = { { mount = 4, boss = "Altairus" } } },
}

describe("Map.HasSpot", function()
  it("is true for x/y coords and for dungeon / raid / routed mounts, false for a zone only", function()
    local ns = loadUI(MOUNTS, ROUTE)
    eq(ns.Map.HasSpot(1), true, "x/y")
    eq(ns.Map.HasSpot(2), false, "zone only")
    eq(ns.Map.HasSpot(3), true, "raid: the entrance")
    eq(ns.Map.HasSpot(4), true, "on the route: the entrance")
    eq(ns.Map.HasSpot(5), false, "no location")
  end)
end)

describe("UI.LocationIcon", function()
  it("is spot / zone / nil", function()
    local ns = loadUI(MOUNTS, ROUTE)
    eq(ns.UI.LocationIcon(1), "spot")
    eq(ns.UI.LocationIcon(2), "zone")
    eq(ns.UI.LocationIcon(3), "spot")
    eq(ns.UI.LocationIcon(5), nil)
  end)

  -- F12 (F10 carry-over): a row whose boss has a per-boss spec clicks through
  -- to that boss's instance entrance (Map.Resolve), so it shows a pin.
  it("a route boss with a per-boss instance spec is a spot, whatever the mount's own location", function()
    local ns = loadUI(MOUNTS, ROUTE)
    ns.Data.BossLockouts = {
      Koralon = { instance = 624, boss = "Koralon the Flame Watcher", difficulties = { 3, 4 }, reset = "weekly" },
      Ticked = { manual = true, reset = "weekly" },
    }
    eq(ns.Map.HasLocation(5, "Koralon"), true, "the boss's entrance")
    eq(ns.Map.HasSpot(5, "Koralon"), true)
    eq(ns.Map.HasSpot(2, "Koralon"), true, "zone-only mount, per-boss entrance")
    eq(ns.UI.LocationIcon(5, "Koralon"), "spot")
    eq(ns.UI.LocationIcon(2, "Koralon"), "spot")
    eq(ns.UI.LocationIcon(2, "Altairus"), "zone", "a boss without a per-boss spec changes nothing")
    eq(ns.UI.LocationIcon(5, "Ticked"), nil, "a per-boss spec without an instance has no entrance")
    eq(ns.UI.LocationIcon(5, nil), nil)
  end)

  it("ApplyPin shows the map pin for a spot and the map icon for a zone", function()
    local ns = loadUI(MOUNTS, ROUTE)
    local pin = { calls = {} }
    function pin:SetAtlas(a) self.calls[#self.calls + 1] = { "atlas", a } end
    function pin:SetTexture(t) self.calls[#self.calls + 1] = { "texture", t } end
    function pin:SetTexCoord() end
    ns.UI.AtlasExists = function() return true end
    ns.UI.ApplyPin(pin, "spot")
    eq(pin.calls[#pin.calls], { "atlas", "Waypoint-MapPin-ChatIcon" })
    ns.UI.ApplyPin(pin, "zone")
    eq(pin.calls[#pin.calls], { "texture", "Interface\\Icons\\INV_Misc_Map_01" })
  end)
end)

describe("zone-only click", function()
  it("says there is no exact spot and names the zone", function()
    local ns = loadUI(MOUNTS, ROUTE)
    local printed = {}
    local api = {
      C_Map = {
        CanSetUserWaypointOnMap = function() return true end,
        GetMapInfo = function(m) return { mapID = m, name = m == 896 and "Drustvar" or "?" } end,
      },
      OpenWorldMap = function() end,
      Print = function(msg) printed[#printed + 1] = msg end,
    }
    local place, kind = ns.Map.SetWaypoint(2, api)
    eq(kind, "open")
    eq(printed, { "No exact spot for Great Sea Ray (anywhere in Drustvar): opened the map" })
  end)
end)
