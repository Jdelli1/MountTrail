-- Logic/Events.lua (F17): live status of event rares (N'Zoth assaults in
-- Uldum / the Vale, the Arathi / Darkshore warfronts), pure over injected
-- game lookups; Data/Events.lua against the mount data.

local function load()
  return load_addon({ "Core/Locale.lua", "Data/Mounts.lua", "Data/Events.lua", "Logic/Events.lua" })
end

local function fmt(seconds) return tostring(seconds) .. "s" end

local ULDUM = {
  kind = "assault", zone = "Uldum", maps = { 1527, 249 },
  pois = { [6486] = "N'Zoth", [6487] = "Amathet", [6488] = "Aqir" },
}
local ARATHI = {
  kind = "warfront", zone = "Arathi Highlands", label = "Arathi", maps = { 14 },
  contribution = "Battle for Stromgarde", contributions = { 11, 116 },
}

describe("events", function()
  describe("Data/Events.lua", function()
    it("names the four SimpleArmory groups with the IDs verified against DB2 12.1.5.70448", function()
      local ns = load()
      local G = ns.Data.EventGroups
      eq(G["Assault: Uldum"].pois, { [6486] = "N'Zoth", [6487] = "Amathet", [6488] = "Aqir" })
      eq(G["Assault: Uldum"].maps, { 1527, 249 })
      eq(G["Assault: Vale of Eternal Blossoms"].pois, { [6489] = "N'Zoth", [6490] = "Mogu", [6491] = "Mantid" })
      eq(G["Assault: Vale of Eternal Blossoms"].maps, { 1530, 390 })
      eq(G["Warfront: Arathi"].contributions, { 11, 116 })
      eq(G["Warfront: Arathi"].maps, { 14 })
      eq(G["Warfront: Darkshore"].contributions, { 117, 118 })
      eq(G["Warfront: Darkshore"].maps, { 62 })
    end)

    it("every group is a mount group in Data/Mounts.lua, with a rare that has a quest flag", function()
      local ns = load()
      for key in pairs(ns.Data.EventGroups) do
        local flagged = 0
        for _, m in pairs(ns.Data.Mounts) do
          if m.group == key and m.quest then flagged = flagged + 1 end
        end
        ok(flagged > 0, key .. ": a mount with a quest flag (a checklist rare)")
      end
    end)
  end)

  describe("GroupOf", function()
    it("finds a mount's event group by its SimpleArmory group", function()
      local ns = load()
      local E = ns.Events
      local key, def = E.GroupOf({ group = "Assault: Uldum" }, ns.Data.EventGroups)
      eq(key, "Assault: Uldum")
      eq(def.zone, "Uldum")
      eq(E.GroupOf({ group = "Rare Spawn" }, ns.Data.EventGroups), nil)
      eq(E.GroupOf(nil, ns.Data.EventGroups), nil)
      eq(E.GroupOf({ group = "Assault: Uldum" }, nil), nil)
    end)
  end)

  describe("AssaultStatus", function()
    it("the zone's assault from the POIs the map reports, with its time left", function()
      local E = load().Events
      local st = E.AssaultStatus(ULDUM, { 5000, 6488, 7000 }, function(id) if id == 6488 then return 3600 end end)
      eq(st, { kind = "assault", known = true, poi = 6488, name = "Aqir", seconds = 3600 })
    end)

    it("no time left when the game gives none (or a bad value)", function()
      local E = load().Events
      eq(E.AssaultStatus(ULDUM, { 6487 }, function() return nil end).seconds, nil)
      eq(E.AssaultStatus(ULDUM, { 6487 }, function() return -5 end).seconds, nil)
      eq(E.AssaultStatus(ULDUM, { 6487 }, nil).name, "Amathet")
    end)

    it("two at once (a map change in progress): the lowest ID, so the line is stable", function()
      local E = load().Events
      eq(E.AssaultStatus(ULDUM, { 6488, 6486 }).poi, 6486)
    end)

    it("unknown when the map reports none of the assault POIs, or nothing at all", function()
      local E = load().Events
      eq(E.AssaultStatus(ULDUM, { 1, 2 }), { kind = "assault", known = false })
      eq(E.AssaultStatus(ULDUM, {}), { kind = "assault", known = false })
      eq(E.AssaultStatus(ULDUM, nil), { kind = "assault", known = false })
    end)
  end)

  describe("WarfrontStatus", function()
    it("keeps the verified contributions the map reports, with the game's state names", function()
      local E = load().Events
      local st = E.WarfrontStatus(ARATHI, {
        { id = 116, state = 1, stateName = "Contributing", percent = 0.634 },
        { id = 999, state = 2, stateName = "Active" }, -- not one of ours
      })
      eq(st, { kind = "warfront", known = true, parts = {
        { id = 116, state = 1, stateName = "Contributing", percent = 63 },
      } })
    end)

    it("time left only when the game's appearance says to use it", function()
      local E = load().Events
      local st = E.WarfrontStatus(ARATHI, {
        { id = 11, state = 2, stateName = "Active", seconds = 7200, useTime = true },
        { id = 116, state = 3, stateName = "Under Attack", seconds = 7200, useTime = false },
      })
      eq(st.parts, {
        { id = 11, state = 2, stateName = "Active", seconds = 7200 },
        { id = 116, state = 3, stateName = "Under Attack" },
      })
    end)

    it("falls back to the state's enum name when the game gives no appearance", function()
      local E = load().Events
      eq(E.WarfrontStatus(ARATHI, { { id = 11, state = 4 } }).parts[1].stateName, "Destroyed")
      eq(E.WarfrontStatus(ARATHI, { { id = 11, state = 3 } }).parts[1].stateName, "Under attack")
    end)

    it("unknown without a reported contribution, or with state None / missing", function()
      local E = load().Events
      local unknown = { kind = "warfront", known = false }
      eq(E.WarfrontStatus(ARATHI, nil), unknown)
      eq(E.WarfrontStatus(ARATHI, {}), unknown)
      eq(E.WarfrontStatus(ARATHI, { { id = 11, state = 0 } }), unknown)
      eq(E.WarfrontStatus(ARATHI, { { id = 11 } }), unknown)
      eq(E.WarfrontStatus(ARATHI, { "junk", { id = "11", state = 2 } }), unknown)
    end)
  end)

  describe("StatusText", function()
    it("assaults: zone, assault and time left", function()
      local E = load().Events
      eq(E.StatusText(ULDUM, { kind = "assault", known = true, name = "Aqir", seconds = 90 }, fmt),
        "Uldum: Aqir assault — 90s left")
      eq(E.StatusText(ULDUM, { kind = "assault", known = true, name = "Aqir" }, fmt), "Uldum: Aqir assault")
    end)

    it("warfronts: the label and each reported state (percent or time left)", function()
      local E = load().Events
      eq(E.StatusText(ARATHI, { kind = "warfront", known = true, parts = {
        { stateName = "Contributing", percent = 63 } } }, fmt), "Arathi warfront: Contributing (63%)")
      eq(E.StatusText(ARATHI, { kind = "warfront", known = true, parts = {
        { stateName = "Active", seconds = 60 }, { stateName = "Under Attack" } } }, fmt),
        "Arathi warfront: Active — 60s left / Under Attack")
    end)

    it("unknown or missing status: the hint", function()
      local E = load().Events
      eq(E.StatusText(ULDUM, { kind = "assault", known = false }, fmt), "Status unknown (open the map once)")
      eq(E.StatusText(ARATHI, nil, fmt), "Status unknown (open the map once)")
    end)
  end)

  describe("Statuses", function()
    local function lookups(o)
      return {
        poisForMap = o.pois or function() return nil end,
        secondsLeft = o.seconds or function() return nil end,
        contributionsForMap = o.contributions or function() return nil end,
        formatDuration = fmt,
      }
    end

    it("one line per group from the injected lookups; every map of a group is asked", function()
      local ns = load()
      local asked = {}
      local texts = ns.Events.Statuses(ns.Data.EventGroups, lookups({
        pois = function(map)
          asked[#asked + 1] = map
          if map == 249 then return { 6487 } end
          if map == 1530 then return { 6491 } end
          return {}
        end,
        seconds = function(id) if id == 6491 then return 120 end end,
        contributions = function(map)
          if map == 62 then return { { id = 118, state = 1, stateName = "Contributing", percent = 0.5 } } end
        end,
      }))
      eq(texts, {
        ["Assault: Uldum"] = "Uldum: Amathet assault",
        ["Assault: Vale of Eternal Blossoms"] = "Vale of Eternal Blossoms: Mantid assault — 120s left",
        ["Warfront: Arathi"] = "Status unknown (open the map once)",
        ["Warfront: Darkshore"] = "Darkshore warfront: Contributing (50%)",
      })
      table.sort(asked)
      eq(asked, { 249, 390, 1527, 1530 })
    end)

    it("with lookups.poiInfo, an assault POI counts only when GetAreaPOIInfo knows it on that map", function()
      local ns = load()
      local L = lookups({ pois = function(map) if map == 1527 then return { 6486, 6488 } end return {} end })
      local infoAsked = {}
      L.poiInfo = function(map, id)
        infoAsked[#infoAsked + 1] = map .. ":" .. id
        if id == 6488 then return { name = "Assault: Aqir" } end
      end
      local texts = ns.Events.Statuses({ ["Assault: Uldum"] = ns.Data.EventGroups["Assault: Uldum"] }, L)
      eq(texts["Assault: Uldum"], "Uldum: Aqir assault", "6486 is listed but GetAreaPOIInfo has nothing for it")
      eq(infoAsked, { "1527:6486", "1527:6488" }, "only the group's own POIs are looked up")
    end)

    it("a lookup that errors gives the unknown line, never an error", function()
      local ns = load()
      local texts = ns.Events.Statuses(ns.Data.EventGroups, lookups({
        pois = function() error("boom") end,
        contributions = function() error("boom") end,
      }))
      for key, text in pairs(texts) do eq(text, "Status unknown (open the map once)", key) end
      eq(ns.Events.Statuses(nil, lookups({})), {})
    end)
  end)
end)
