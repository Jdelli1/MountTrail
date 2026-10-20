-- Zone.MountsFor (Logic/Zone.lua): the mounts whose location is the player's
-- current zone, from injected map / Encounter Journal lookups. UI.GroupKey
-- (UI/List.lua) is the name normaliser the panel passes in.

local function loadZone()
  return load_addon({ "Core/Locale.lua", "Logic/Journal.lua", "Logic/Zone.lua", "UI/List.lua" })
end

-- A small world:
--   1 Cosmic > 12 Kalimdor (continent) > 71 Tanaris (zone) > 74 Caverns of Time (micro)
--                                     > 75 Caverns of Time lower (micro, under 74)
--                                     > 249 Uldum (zone) > 325 Vortex Pinnacle (dungeon floor)
--                                     > 409 Dragon Soul (dungeon floor, child of 75), 410 its second floor
local MAPS = {
  [1] = { name = "Cosmic", mapType = 0 },
  [12] = { name = "Kalimdor", mapType = 2, parentMapID = 1 },
  [71] = { name = "Tanaris", mapType = 3, parentMapID = 12 },
  [74] = { name = "Caverns of Time", mapType = 5, parentMapID = 71 },
  [75] = { name = "Caverns of Time", mapType = 5, parentMapID = 74 },
  [249] = { name = "Uldum", mapType = 3, parentMapID = 12 },
  [325] = { name = "The Vortex Pinnacle", mapType = 4, parentMapID = 249 },
  [409] = { name = "The Dragon Wastes", mapType = 4, parentMapID = 75 },
  [410] = { name = "Eye of Eternity", mapType = 4, parentMapID = 75 },
  -- Nested zones: 1978 Dragon Isles (continent) > 2025 Thaldraszus (zone) >
  -- 2112 Valdrakken (zone) > 2113 a Valdrakken micro; 2026 a Thaldraszus micro.
  [1978] = { name = "Dragon Isles", mapType = 2, parentMapID = 1 },
  [2025] = { name = "Thaldraszus", mapType = 3, parentMapID = 1978 },
  [2026] = { name = "Tyrhold", mapType = 5, parentMapID = 2025 },
  [2112] = { name = "Valdrakken", mapType = 3, parentMapID = 2025 },
  [2113] = { name = "Seat of the Aspects", mapType = 5, parentMapID = 2112 },
  -- An orphan / micro map that is a journal instance (a delve, a scenario).
  [600] = { name = "Delve floor", mapType = 6, parentMapID = 71 },
}

local function ctxFor(ns, mounts, over)
  local ctx = {
    mounts = mounts,
    mapInfo = function(id) return MAPS[id] end,
    key = ns.UI.GroupKey,
    gate = function() return false end, -- everything known, nothing owned
  }
  for k, v in pairs(over or {}) do ctx[k] = v end
  return ctx
end

local function ids(list)
  local out = {}
  for _, row in ipairs(list) do out[#out + 1] = row.id end
  return out
end

describe("Zone.Root", function()
  it("climbs micro / dungeon floors to the zone, never to the continent", function()
    local Zone = loadZone().Zone
    local info = function(id) return MAPS[id] end
    eq(Zone.Root(75, info), 71, "micro under micro under zone")
    eq(Zone.Root(74, info), 71)
    eq(Zone.Root(71, info), 71, "a zone is its own root")
    eq(Zone.Root(325, info), 249, "dungeon floor without an instance lookup")
    eq(Zone.Root(12, info), 12, "a continent stays a continent")
    eq(Zone.Root(999, info), nil, "unknown map")
    eq(Zone.Root(nil, info), nil)
  end)

  it("stays on a map whose parent is a continent (orphan / micro straight under a continent)", function()
    local Zone = loadZone().Zone
    local maps = { [12] = MAPS[12], [500] = { name = "Lonely Isle", mapType = 5, parentMapID = 12 } }
    eq(Zone.Root(500, function(id) return maps[id] end), 500)
  end)

  it("survives a parent cycle", function()
    local Zone = loadZone().Zone
    local maps = { [1] = { name = "A", mapType = 5, parentMapID = 2 }, [2] = { name = "B", mapType = 5, parentMapID = 1 } }
    ok(Zone.Root(1, function(id) return maps[id] end) ~= nil, "terminates")
  end)
end)

describe("Zone.Root instance detection", function()
  local info = function(id) return MAPS[id] end
  it("any floor type below a zone (dungeon, micro, orphan) can be a journal instance", function()
    local Zone = loadZone().Zone
    local inst = function(id) if id == 600 or id == 74 or id == 71 or id == 12 then return 99 end end
    eq({ Zone.Root(600, info, inst) }, { 600, 99 }, "orphan")
    eq({ Zone.Root(74, info, inst) }, { 74, 99 }, "micro")
    eq({ Zone.Root(71, info, inst) }, { 71 }, "a zone is never an instance")
    eq({ Zone.Root(12, info, inst) }, { 12 }, "nor a continent (world-boss journal entries)")
  end)
end)

describe("Zone.Key", function()
  it("is the root plus the instance, so sub-zones of one zone share it", function()
    local ns = loadZone()
    local ctx = { mapInfo = function(id) return MAPS[id] end,
      instanceForMap = function(id) if id == 409 then return 187 end end }
    eq(ns.Zone.Key(74, ctx), "71")
    eq(ns.Zone.Key(75, ctx), "71")
    eq(ns.Zone.Key(71, ctx), "71")
    eq(ns.Zone.Key(409, ctx), "409:187")
    eq(ns.Zone.Key(999, ctx), nil)
    eq(ns.Zone.Key(nil, ctx), nil)
    ctx.currentInstance = "Dragon Soul"
    eq(ns.Zone.Key(nil, ctx), "instance:dragon soul", "no map inside an instance: by name")
  end)
end)

describe("Zone.MountsFor", function()
  it("(a) nested zones: the zone-type ancestors of the root count, not the continent or their other maps", function()
    local ns = loadZone()
    local mounts = {
      [1] = { name = "Thaldraszus rare", coords = { m = 2025 } },
      [2] = { name = "Valdrakken vendor", coords = { m = 2112 } },
      [3] = { name = "Tyrhold", coords = { m = 2026 } },
      [4] = { name = "Dragon Isles", coords = { m = 1978 } },
      [5] = { name = "Seat", coords = { m = 2113 } },
    }
    local list, zone = ns.Zone.MountsFor(2113, ctxFor(ns, mounts))
    eq(ids(list), { 5, 1, 2 })
    eq(zone, { mapID = 2112, name = "Valdrakken" }, "root and title stay the inner zone")
    eq(ids(ns.Zone.MountsFor(2025, ctxFor(ns, mounts))), { 5, 1, 3, 2 }, "outer zone: inner zone is a descendant")
  end)

  it("no map but inside an instance (ctx.currentInstance): mounts named for it", function()
    local ns = loadZone()
    local mounts = {
      [1] = { name = "By source", tab = "journal", section = "raid" },
      [2] = { name = "By sub-group", tab = "journal", section = "raid" },
      [3] = { name = "By route", tab = "journal", section = "raid" },
      [4] = { name = "Other", tab = "journal", section = "raid", coords = { m = 71 } },
    }
    local ctx = ctxFor(ns, mounts, {
      currentInstance = "Dragon Soul",
      sourceZone = function(id) if id == 1 then return "Dragon Soul" end end,
      subGroup = function(id) if id == 2 then return "dragon soul" end end,
      routeInstance = function(id) if id == 3 then return "The Dragon Soul" end end,
    })
    local list, zone = ns.Zone.MountsFor(nil, ctx)
    eq(ids(list), { 3, 1, 2 })
    eq(zone, { name = "Dragon Soul" })
  end)

  it("gates first: excluded mounts never reach the source text or instance lookups", function()
    local ns = loadZone()
    local mounts = { [1] = { name = "Kept" }, [2] = { name = "Owned" }, [3] = { name = "Horde" } }
    local asked = {}
    local ctx = ctxFor(ns, mounts, {
      gate = function(id) if id == 1 then return false elseif id == 2 then return true end return nil end,
      sourceZone = function(id) asked[#asked + 1] = id; return "Tanaris" end,
      subGroup = function(id) asked[#asked + 1] = id end,
    })
    eq(ids(ns.Zone.MountsFor(71, ctx)), { 1 })
    eq(asked, { 1 }, "only the kept mount was looked up")
  end)


  it("(a) coords on the zone, a map inside it, or the player's own floor", function()
    local ns = loadZone()
    local mounts = {
      [1] = { name = "On Tanaris", coords = { m = 71, x = 1, y = 1 } },
      [2] = { name = "In the Caverns", coords = { m = 75 } },
      [3] = { name = "On Kalimdor", coords = { m = 12 } },
      [4] = { name = "On Uldum", coords = { m = 249 } },
      [5] = { name = "No coords" },
    }
    local list, zone = ns.Zone.MountsFor(74, ctxFor(ns, mounts))
    eq(ids(list), { 2, 1 }, "sorted by name; continent and sibling zone left out")
    eq(zone, { mapID = 71, name = "Tanaris" })
    eq(list[1].via, "coords")
    eq(list[1].owned, false)
  end)

  it("(a) does not climb to the continent: standing on a continent only matches that map", function()
    local ns = loadZone()
    local mounts = {
      [1] = { name = "On Kalimdor", coords = { m = 12 } },
      [2] = { name = "On Tanaris", coords = { m = 71 } },
    }
    eq(ids(ns.Zone.MountsFor(12, ctxFor(ns, mounts))), { 1 })
  end)

  it("(a) uses the coords lookup (holiday override) when given", function()
    local ns = loadZone()
    local mounts = { [1] = { name = "Holiday", coords = { m = 12 } } }
    local ctx = ctxFor(ns, mounts, { coords = function(id, m) return { m = 71 } end })
    eq(ids(ns.Zone.MountsFor(71, ctx)), { 1 })
  end)

  it("(b) source text Zone: equals the zone name, case and a leading The ignored", function()
    local ns = loadZone()
    local mounts = {
      [1] = { name = "A" }, [2] = { name = "B" }, [3] = { name = "C" }, [4] = { name = "D" },
    }
    local zones = { [1] = "Tanaris", [2] = "the  tanaris", [3] = "Uldum" }
    local ctx = ctxFor(ns, mounts, { sourceZone = function(id) return zones[id] end })
    local list = ns.Zone.MountsFor(75, ctx)
    eq(ids(list), { 1, 2 })
    eq(list[1].via, "source")
  end)

  it("(c) dungeon entrances in the zone: instance sub-group, route instance and coords map instance", function()
    local ns = loadZone()
    local mounts = {
      [1] = { name = "Drake of the North Wind", tab = "journal", section = "dungeon" },
      [2] = { name = "Route only", tab = "journal", section = "dungeon" },
      [3] = { name = "Coords in the dungeon", coords = { m = 325 } },
      [4] = { name = "Elsewhere", tab = "journal", section = "raid" },
    }
    local ctx = ctxFor(ns, mounts, {
      entrances = function(id)
        if id == 249 then return { { journalInstanceID = 68, name = "Entrance name" } } end
        return {}
      end,
      instanceName = function(jid) if jid == 68 then return "The Vortex Pinnacle" end end,
      instanceForMap = function(id) if id == 325 then return 68 end end,
      subGroup = function(id) if id == 1 then return "Vortex Pinnacle" end if id == 4 then return "Dragon Soul" end end,
      routeInstance = function(id) if id == 2 then return "the vortex pinnacle" end end,
    })
    local list = ns.Zone.MountsFor(249, ctx)
    eq(ids(list), { 3, 1, 2 })
    for _, row in ipairs(list) do eq(row.via, row.id == 3 and "coords" or "instance") end
  end)

  it("(c) falls back to the entrance's own name when the journal has none", function()
    local ns = loadZone()
    local mounts = { [1] = { name = "X", tab = "journal", section = "dungeon" } }
    local ctx = ctxFor(ns, mounts, {
      entrances = function(id) if id == 249 then return { { journalInstanceID = 68, name = "Vortex Pinnacle" } } end end,
      subGroup = function() return "The Vortex Pinnacle" end,
    })
    eq(ids(ns.Zone.MountsFor(249, ctx)), { 1 })
  end)

  it("(c) asks for entrances on the player's own map too (an entrance on a micro map)", function()
    local ns = loadZone()
    local mounts = { [1] = { name = "X", tab = "journal", section = "raid" } }
    local asked = {}
    local ctx = ctxFor(ns, mounts, {
      entrances = function(id)
        asked[#asked + 1] = id
        if id == 74 then return { { journalInstanceID = 187, name = "Dragon Soul" } } end
      end,
      subGroup = function() return "Dragon Soul" end,
    })
    eq(ids(ns.Zone.MountsFor(74, ctx)), { 1 })
    eq(asked, { 71, 74 })
  end)

  it("(c) asks for entrances on the zone's micro / zone children too, not on dungeon floors", function()
    local ns = loadZone()
    local mounts = { [1] = { name = "X", tab = "journal", section = "raid" } }
    local asked = {}
    local ctx = ctxFor(ns, mounts, {
      children = function(id)
        eq(id, 71)
        return { { mapID = 74, mapType = 5 }, { mapID = 75, mapType = 5 }, { mapID = 409, mapType = 4 } }
      end,
      entrances = function(id)
        asked[#asked + 1] = id
        if id == 75 then return { { journalInstanceID = 187, name = "Dragon Soul" } } end
      end,
      subGroup = function() return "Dragon Soul" end,
    })
    eq(ids(ns.Zone.MountsFor(74, ctx)), { 1 })
    eq(asked, { 71, 74, 75 }, "root, the player's map, then children once each")
  end)

  it("inside an instance: the instance's mounts on every floor, titled with the instance", function()
    local ns = loadZone()
    local mounts = {
      [1] = { name = "Floor one", coords = { m = 409 } },
      [2] = { name = "Floor two", coords = { m = 410 } },
      [3] = { name = "By name", tab = "journal", section = "raid" },
      [4] = { name = "Tanaris rare", coords = { m = 71 } },
    }
    local ctx = ctxFor(ns, mounts, {
      instanceForMap = function(id) if id == 409 or id == 410 then return 187 end end,
      -- The two floors are one map group, as a dungeon's floors are in game.
      mapGroup = function(id) if id == 409 or id == 410 then return 9 end end,
      instanceName = function(jid) if jid == 187 then return "Dragon Soul" end end,
      subGroup = function(id) if id == 3 then return "Dragon Soul" end end,
    })
    local list, zone = ns.Zone.MountsFor(409, ctx)
    eq(ids(list), { 3, 1, 2 }, "not the zone outside")
    eq(zone, { mapID = 409, name = "Dragon Soul", instance = 187 })
  end)

  it("de-duplicates a mount matched several ways (first reason kept)", function()
    local ns = loadZone()
    local mounts = { [1] = { name = "Everywhere", tab = "journal", section = "dungeon", coords = { m = 325 } } }
    local ctx = ctxFor(ns, mounts, {
      sourceZone = function() return "Uldum" end,
      entrances = function(id) if id == 249 then return { { journalInstanceID = 68 } } end end,
      instanceName = function() return "The Vortex Pinnacle" end,
      instanceForMap = function(id) if id == 325 then return 68 end end,
      subGroup = function() return "The Vortex Pinnacle" end,
      routeInstance = function() return "The Vortex Pinnacle" end,
    })
    local list = ns.Zone.MountsFor(249, ctx)
    eq(#list, 1)
    eq(list[1].via, "coords")
  end)

  it("hides owned and gated-out mounts; Collected shows owned ones", function()
    local ns = loadZone()
    local mounts = {
      [1] = { name = "Missing", coords = { m = 71 } },
      [2] = { name = "Owned", coords = { m = 71 } },
      [3] = { name = "Horde only", coords = { m = 71 } },
    }
    local gate = function(id) if id == 1 then return false elseif id == 2 then return true end return nil end
    eq(ids(ns.Zone.MountsFor(71, ctxFor(ns, mounts, { gate = gate }))), { 1 })
    local list = ns.Zone.MountsFor(71, ctxFor(ns, mounts, { gate = gate, showCollected = true }))
    eq(ids(list), { 1, 2 })
    eq(list[2].owned, true)
  end)

  it("Zone.Gate applies the Journal rules: faction, unobtainable, unknown to the client", function()
    local ns = loadZone()
    local gate = ns.Zone.Gate(function(id) return id == 2 or id == 5 end, function(id) return id ~= 4 end, "Alliance")
    eq(gate(1, { name = "Plain" }), false)
    eq(gate(2, { name = "Owned" }), true)
    eq(gate(3, { name = "Horde", faction = "Horde" }), nil, "other faction")
    eq(gate(4, { name = "Not in this client" }), nil)
    eq(gate(6, { name = "Gone", unobtainable = true }), nil, "unobtainable and not owned")
    eq(gate(5, { name = "Gone but owned", unobtainable = true }), true)
  end)

  it("considers every data tab (journal, holiday, misc)", function()
    local ns = loadZone()
    local mounts = {
      [1] = { name = "J", tab = "journal", section = "world", coords = { m = 71 } },
      [2] = { name = "H", tab = "holiday", section = "brewfest", coords = { m = 71 } },
      [3] = { name = "M", tab = "misc", section = "profession", coords = { m = 71 } },
    }
    eq(ids(ns.Zone.MountsFor(71, ctxFor(ns, mounts))), { 2, 1, 3 })
  end)

  it("no map or an unknown map -> empty list, no zone; missing lookups are fine", function()
    local ns = loadZone()
    local mounts = { [1] = { name = "X", coords = { m = 71 } } }
    local list, zone = ns.Zone.MountsFor(nil, ctxFor(ns, mounts))
    eq(list, {})
    eq(zone, nil)
    list, zone = ns.Zone.MountsFor(999, ctxFor(ns, mounts))
    eq(list, {})
    eq(zone, nil)
    eq(ids(ns.Zone.MountsFor(71, { mounts = mounts, mapInfo = function(id) return MAPS[id] end })), { 1 },
      "no gate: everything kept; default key")
  end)
end)

-- Same-named zones, neighbours' entrances and UI vs game map IDs (the map
-- tab showed Huolon's Timeless Isle mount in Netherstorm, Karazhan's mounts
-- on the Blasted Lands, WoD Nagrand's in TBC Nagrand).
-- 13 Eastern Kingdoms > 17 Blasted Lands, 42 Deadwind Pass > 350 / 351
-- Karazhan floors; 101 Outland > 107 Nagrand, 109 Netherstorm > 266 The
-- Mechanar; 572 Draenor > 550 Nagrand; 424 Pandaria > 554 Timeless Isle.
local WORLD = {
  [1] = { name = "Cosmic", mapType = 0 },
  [13] = { name = "Eastern Kingdoms", mapType = 2, parentMapID = 1 },
  [17] = { name = "Blasted Lands", mapType = 3, parentMapID = 13 },
  [42] = { name = "Deadwind Pass", mapType = 3, parentMapID = 13 },
  [350] = { name = "Karazhan", mapType = 4, parentMapID = 42 },
  [351] = { name = "Karazhan", mapType = 4, parentMapID = 42 },
  [101] = { name = "Outland", mapType = 2, parentMapID = 1 },
  [107] = { name = "Nagrand", mapType = 3, parentMapID = 101 },
  [109] = { name = "Netherstorm", mapType = 3, parentMapID = 101 },
  [266] = { name = "The Mechanar", mapType = 4, parentMapID = 109 },
  [572] = { name = "Draenor", mapType = 2, parentMapID = 1 },
  [550] = { name = "Nagrand", mapType = 3, parentMapID = 572 },
  [424] = { name = "Pandaria", mapType = 2, parentMapID = 1 },
  [554] = { name = "Timeless Isle", mapType = 3, parentMapID = 424 },
}
local FLOORS = { [745] = 350, [258] = 266 } -- journal instance -> its first floor
local VERSIONS = { [107] = { g = 1, e = 1 }, [550] = { g = 1, e = 5 } }
local EXP = { ["The Burning Crusade"] = 1, ["Warlords of Draenor"] = 5, ["Mists of Pandaria"] = 4 }

local function worldCtx(ns, mounts, over)
  local ctx = {
    mounts = mounts,
    mapInfo = function(id) return WORLD[id] end,
    key = ns.UI.GroupKey,
    gate = function() return false end,
    instanceUiMap = function(jid) return FLOORS[jid] end,
    mapGroup = function(id) if id == 350 or id == 351 then return 77 end end,
    versionOk = function(root, m) return ns.Zone.VersionOk(VERSIONS, root, m and EXP[m.exp]) end,
    entrances = function(id)
      -- Netherstorm lists the Mechanar; the Blasted Lands' map also shows
      -- Karazhan's entrance near its edge; Deadwind Pass lists Karazhan.
      if id == 109 then return { { journalInstanceID = 258, name = "The Mechanar" } } end
      if id == 17 or id == 42 then return { { journalInstanceID = 745, name = "Karazhan" } } end
      return {}
    end,
    instanceName = function(jid) return ({ [745] = "Karazhan", [258] = "The Mechanar" })[jid] end,
  }
  for k, v in pairs(over or {}) do ctx[k] = v end
  return ctx
end

describe("Zone.MountsFor: versions, neighbours and map IDs", function()
  it("Timeless Isle's mount is not in Netherstorm (its map is no game map ID)", function()
    local ns = loadZone()
    local mounts = {
      [561] = { name = "Thundering Onyx Cloud Serpent", tab = "journal", section = "world", coords = { m = 554 } },
      [2] = { name = "Mechanar drop", tab = "journal", section = "dungeon", coords = { m = 266 } },
    }
    local ctx = worldCtx(ns, mounts, {
      sourceZone = function(id) if id == 561 then return { "Timeless Isle" } end end,
      -- Asked with UI map 554, GetInstanceForGameMap would say The Mechanar.
      instanceForMap = function(id) if id == 554 then return 258 end end,
    })
    eq(ids(ns.Zone.MountsFor(109, ctx)), { 2 })
    eq(ids(ns.Zone.MountsFor(554, ctx)), { 561 })
  end)

  it("a vendor's zone lists the mount even when it drops elsewhere; every Zone: line counts", function()
    local ns = loadZone()
    local mounts = {
      [1] = { name = "Dropped in Outland, sold in Netherstorm", tab = "journal", section = "world", coords = { m = 107 } },
      [2] = { name = "Two vendors", tab = "misc", section = "other" },
      [3] = { name = "Comma list", tab = "journal", section = "world" },
    }
    local ctx = worldCtx(ns, mounts, { sourceZone = function(id)
      return ({ [1] = { "Nagrand", "Netherstorm" }, [2] = { "Timeless Isle", "Netherstorm" },
        [3] = { "Blasted Lands, Netherstorm" } })[id]
    end })
    eq(ids(ns.Zone.MountsFor(109, ctx)), { 3, 1, 2 })
    local list = ns.Zone.MountsFor(107, ctx)
    eq(ids(list), { 1 }, "and still where it drops")
    eq(list[1].via, "coords")
  end)

  it("a zone inside the zone counts: a city vendor's mount shows on the zone around it", function()
    local ns = loadZone()
    local world = setmetatable({ [111] = { name = "Shattrath City", mapType = 3, parentMapID = 108 },
      [108] = { name = "Terokkar Forest", mapType = 3, parentMapID = 101 } }, { __index = WORLD })
    local mounts = { [1] = { name = "Sold in Shattrath", tab = "misc", section = "other" } }
    local ctx = worldCtx(ns, mounts, {
      mapInfo = function(id) return world[id] end,
      children = function(id) if id == 108 then return { { mapID = 111, mapType = 3 } } end return {} end,
      sourceZone = function() return { "Shattrath City" } end,
    })
    eq(ids(ns.Zone.MountsFor(108, ctx)), { 1 }, "Terokkar Forest")
    eq(ids(ns.Zone.MountsFor(111, ctx)), { 1 }, "Shattrath City")
    eq(ids(ns.Zone.MountsFor(109, ctx)), {}, "Netherstorm")
  end)

  it("the zone version applies to vendor zones too: an 8.3 Uldum mount with coords is not in old Uldum", function()
    local ns = loadZone()
    local world = setmetatable({ [12] = { name = "Kalimdor", mapType = 2, parentMapID = 1 },
      [249] = { name = "Uldum", mapType = 3, parentMapID = 12 },
      [1527] = { name = "Uldum", mapType = 3, parentMapID = 12 } }, { __index = WORLD })
    local versions = { [249] = { g = 3, e = 3 }, [1527] = { g = 3, e = 7 } }
    local mounts = {
      [1314] = { name = "Drake of the Four Winds", exp = "Battle for Azeroth", tab = "journal", section = "world", coords = { m = 1527 } },
      [398] = { name = "Brown Riding Camel", exp = "Cataclysm", tab = "journal", section = "world" },
    }
    local exps = { ["Battle for Azeroth"] = 7, ["Cataclysm"] = 3 }
    local ctx = worldCtx(ns, mounts, {
      mapInfo = function(id) return world[id] end,
      sourceZone = function() return { "Uldum" } end,
      versionOk = function(root, m) return ns.Zone.VersionOk(versions, root, exps[m.exp]) end,
    })
    eq(ids(ns.Zone.MountsFor(249, ctx)), { 398 })
    eq(ids(ns.Zone.MountsFor(1527, ctx)), { 1314 })
  end)

  it("a neighbour's entrance drawn on the zone map does not bring its instance's mounts", function()
    local ns = loadZone()
    local mounts = {
      [168] = { name = "Fiery Warhorse", tab = "journal", section = "raid", coords = { m = 350 } },
      [9] = { name = "Karazhan by name only", tab = "journal", section = "raid" },
    }
    local ctx = worldCtx(ns, mounts, { subGroup = function(id) if id == 9 then return "Karazhan" end end })
    eq(ids(ns.Zone.MountsFor(17, ctx)), {}, "Blasted Lands")
    eq(ids(ns.Zone.MountsFor(42, ctx)), { 168, 9 }, "Deadwind Pass")
  end)

  it("inside Karazhan: every floor of the map group", function()
    local ns = loadZone()
    local mounts = { [168] = { name = "Fiery Warhorse", tab = "journal", section = "raid", coords = { m = 350 } } }
    local ctx = worldCtx(ns, mounts, { instanceForMap = function(id) if id == 350 or id == 351 then return 745 end end })
    local list, zone = ns.Zone.MountsFor(351, ctx)
    eq(ids(list), { 168 })
    eq(zone.instance, 745)
  end)

  it("a mount known only by its zone name is listed in its expansion's version of the zone", function()
    local ns = loadZone()
    local mounts = {
      [614] = { name = "Mottled Meadowstomper", exp = "Warlords of Draenor", tab = "journal", section = "world" },
      [7] = { name = "TBC Nagrand mount", exp = "The Burning Crusade", tab = "journal", section = "world" },
      [8] = { name = "No expansion", tab = "misc", section = "other" },
    }
    local ctx = worldCtx(ns, mounts, { sourceZone = function() return "Nagrand" end })
    eq(ids(ns.Zone.MountsFor(107, ctx)), { 8, 7 }, "TBC Nagrand")
    eq(ids(ns.Zone.MountsFor(550, ctx)), { 614, 8 }, "WoD Nagrand")
  end)
end)

describe("Zone.VersionOk", function()
  local versions = {
    [110] = { g = 8 }, [2393] = { g = 8, e = 11 },               -- Silvermoon City
    [18] = { g = 2, e = 0 }, [2070] = { g = 2, e = 8 },           -- Tirisfal Glades
  }
  it("a version of the mount's expansion exists: only that one", function()
    local Z = loadZone().Zone
    eq(Z.VersionOk(versions, 2393, 11), true)
    eq(Z.VersionOk(versions, 110, 11), false)
    eq(Z.VersionOk(versions, 18, 0), true)
    eq(Z.VersionOk(versions, 2070, 0), false)
  end)
  it("none of its expansion: any version not newer than the mount, or unknown", function()
    local Z = loadZone().Zone
    eq(Z.VersionOk(versions, 110, 1), true, "unknown expansion")
    eq(Z.VersionOk(versions, 2393, 1), false, "Midnight's version for a TBC mount")
    eq(Z.VersionOk(versions, 2070, 9), true)
  end)
  it("no versions, an unversioned zone or a mount without expansion: true", function()
    local Z = loadZone().Zone
    eq(Z.VersionOk(nil, 110, 11), true)
    eq(Z.VersionOk(versions, 71, 3), true)
    eq(Z.VersionOk(versions, 110, nil), true)
  end)
end)

describe("Zone.InstanceForFloor", function()
  it("finds the floor's instance among the entrances above it, by map or map group", function()
    local ns = loadZone()
    local ctx = worldCtx(ns, {})
    eq(ns.Zone.InstanceForFloor(266, ctx), 258)
    eq(ns.Zone.InstanceForFloor(351, ctx), 745, "second floor, same map group")
    eq(ns.Zone.InstanceForFloor(554, ctx), nil, "a zone is no instance")
    eq(ns.Zone.InstanceForFloor(nil, ctx), nil)
  end)
end)
