-- API globals these specs replace; every `it` below saves and restores them
-- so one test's stubs never leak into the next.
local API_GLOBALS = {
  "UnitFactionGroup", "UnitName", "GetNormalizedRealmName", "GetRealmName",
  "GetNumSavedInstances", "GetSavedInstanceInfo", "GetSavedInstanceEncounterInfo",
  "C_DateAndTime", "C_Calendar", "GetExpansionDisplayInfo", "C_MountJournal",
  "C_QuestLog", "GetLFGDungeonRewards", "RequestRaidInfo", "RequestLFDPlayerLockInfo",
  "GetServerTime", "geterrorhandler", "GetStatistic", "InCombatLockdown", "C_Map",
  "C_Item", "Item", "C_EncounterJournal", "EJ_GetInstanceInfo",
  "IsInInstance", "GetInstanceInfo", "C_AreaPoiInfo", "C_ContributionCollector",
}
local ORIGINAL = {}
for _, name in ipairs(API_GLOBALS) do ORIGINAL[name] = _G[name] end

local function restoring(fn)
  return function()
    local saved = {}
    for _, name in ipairs(API_GLOBALS) do saved[name] = _G[name] end
    local good, err = pcall(fn)
    for _, name in ipairs(API_GLOBALS) do _G[name] = saved[name] end
    if not good then error(err, 0) end
  end
end

local harnessIt = it
local function it(name, fn) return harnessIt(name, restoring(fn)) end

describe("game adapter", function()
  local function loadGame()
    return load_addon({"Data/Holidays.lua", "Game/API.lua"})
  end

  describe("Faction", function()
    it("maps nil to Neutral", function()
      UnitFactionGroup = function() return nil end
      eq(loadGame().Game.Faction(), "Neutral")
    end)
    it("passes Alliance and Horde through", function()
      local G = loadGame().Game
      UnitFactionGroup = function(unit) eq(unit, "player"); return "Horde", "Horde" end
      eq(G.Faction(), "Horde")
      UnitFactionGroup = function() return "Alliance" end
      eq(G.Faction(), "Alliance")
    end)
    it("maps Neutral and a missing API to Neutral", function()
      local G = loadGame().Game
      UnitFactionGroup = function() return "Neutral" end
      eq(G.Faction(), "Neutral")
      UnitFactionGroup = nil
      eq(G.Faction(), "Neutral")
    end)
  end)

  describe("ReportError (/mtrail debug)", function()
    local function capture()
      local got = {}
      geterrorhandler = function() return function(msg) got[#got + 1] = msg end end
      return got
    end

    it("is silent without a db or with debug off (the default)", function()
      local ns = loadGame()
      local got = capture()
      eq(ns.Game.ReportError("boom"), false)
      ns.db = { global = {} }
      eq(ns.Game.ReportError("boom"), false)
      ns.db.global.debug = false
      eq(ns.Game.ReportError("boom"), false)
      eq(got, {})
    end)

    it("sends the error to geterrorhandler(), prefixed, when debug is on", function()
      local ns = loadGame()
      local got = capture()
      ns.db = { global = { debug = true } }
      eq(ns.Game.ReportError("Map.lua:42: boom"), true)
      eq(ns.Game.ReportError(nil), true)
      eq(got, { "MountTrail: Map.lua:42: boom", "MountTrail: nil" })
    end)

    it("never raises: missing geterrorhandler, nil handler or a failing handler", function()
      local ns = loadGame()
      ns.db = { global = { debug = true } }
      geterrorhandler = nil
      eq(ns.Game.ReportError("x"), false)
      geterrorhandler = function() return nil end
      eq(ns.Game.ReportError("x"), false)
      geterrorhandler = function() return function() error("handler broke") end end
      eq(ns.Game.ReportError("x"), false)
    end)
  end)

  describe("SavedRows", function()
    it("skips unlocked instances and maps fields", function()
      local info = {
        -- name, lockoutId, reset, difficultyId, locked, extended, mostSig, isRaid, maxPlayers,
        -- difficultyName, numEncounters, encounterProgress, extendDisabled, instanceId
        { "Karazhan", 11, 3600, 3, true, false, 0, true, 10, "10 Player", 2, 1, false, 532 },
        { "Old Lock", 12, 0, 2, false, false, 0, false, 5, "Heroic", 1, 1, false, 556 },
        { "The Stonecore", 13, 60, 2, true, false, 0, false, 5, "Heroic", 1, 0, false, 725 },
      }
      local bosses = {
        [1] = { { "Attumen the Huntsman", 1, true, false }, { "Moroes", 2, false, false } },
        [2] = { { "Anzu", 3, true, false } },
        [3] = { { "Slabhide", 4, false, false } },
      }
      GetNumSavedInstances = function() return #info end
      GetSavedInstanceInfo = function(i) return unpack(info[i]) end
      GetSavedInstanceEncounterInfo = function(i, j) return unpack(bosses[i][j]) end
      eq(loadGame().Game.SavedRows(), {
        { name = "Karazhan", instance = 532, difficulty = 3, bosses = {
          { name = "Attumen the Huntsman", killed = true }, { name = "Moroes", killed = false } } },
        { name = "The Stonecore", instance = 725, difficulty = 2, bosses = {
          { name = "Slabhide", killed = false } } },
      })
    end)
    it("leaves out rows with nil instance or difficulty unless asked to include them", function()
      local info = {
        { "Karazhan", 11, 3600, 3, true, false, 0, true, 10, "10 Player", 1, 1, false, 532 },
        { "No ID", 12, 3600, 16, true, false, 0, true, 20, "Mythic", 1, 1, false, nil },
        { "No Diff", 13, 3600, nil, true, false, 0, true, 20, "?", 1, 1, false, 2900 },
      }
      GetNumSavedInstances = function() return #info end
      GetSavedInstanceInfo = function(i) return unpack(info[i], 1, 14) end
      GetSavedInstanceEncounterInfo = function() return "Boss", 1, true, false end
      local G = loadGame().Game
      local rows = G.SavedRows()
      eq(#rows, 1)
      eq(rows[1].instance, 532)
      local all = G.SavedRows(true)
      eq(#all, 3)
      eq(all[2].name, "No ID"); eq(all[2].instance, nil); eq(all[2].difficulty, 16)
      eq(all[3].name, "No Diff"); eq(all[3].instance, 2900); eq(all[3].difficulty, nil)
    end)
    it("returns {} when the saved-instance API is missing", function()
      GetNumSavedInstances, GetSavedInstanceInfo, GetSavedInstanceEncounterInfo = nil, nil, nil
      eq(loadGame().Game.SavedRows(), {})
    end)
  end)

  describe("guards", function()
    it("missing C_DateAndTime / C_Calendar / GetExpansionDisplayInfo fall back safely", function()
      C_DateAndTime, C_Calendar, GetExpansionDisplayInfo = nil, nil, nil
      local G = loadGame().Game
      eq(G.UntilDaily(), 0)
      eq(G.UntilWeekly(), 0)
      eq(G.ActiveHolidays(), {})
      eq(G.ExpansionLogo(1), nil)
    end)
    it("missing mount and quest APIs report not owned / not done", function()
      C_MountJournal, C_QuestLog, GetLFGDungeonRewards = nil, nil, nil
      local G = loadGame().Game
      eq(G.IsOwned(6), false)
      eq(G.Exists(6), false)
      eq(G.IsQuestDone(1), false)
      eq(G.IsLfgDone(285), false)
    end)
  end)

  describe("Statistic", function()
    it("parses GetStatistic's string; \"--\" (never done) is 0", function()
      local values = { [1] = "12", [2] = "--", [3] = " 7 ", [4] = "1,234", [5] = "1.234", [6] = 5 }
      GetStatistic = function(id) return values[id] end
      local G = loadGame().Game
      eq(G.Statistic(1), 12)
      eq(G.Statistic(2), 0)
      eq(G.Statistic(3), 7)
      eq(G.Statistic(4), 1234, "thousands separator")
      eq(G.Statistic(5), 1234, "thousands separator (other locales)")
      eq(G.Statistic(6), 5, "a number passes through")
    end)
    it("is nil for non-numeric, empty or missing values", function()
      local values = { [1] = "abc", [2] = "", [3] = "12|TInterface\MoneyFrame\UI-GoldIcon:0:0:2:0|t",
        [4] = "1-2" }
      GetStatistic = function(id) return values[id] end
      local G = loadGame().Game
      for id = 1, 5 do eq(G.Statistic(id), nil, tostring(id)) end
    end)
    it("is nil when the API is missing, errors, or no ID is given", function()
      GetStatistic = nil
      local G = loadGame().Game
      eq(G.Statistic(1), nil)
      GetStatistic = function() error("boom") end
      eq(G.Statistic(1), nil)
      local called = false
      GetStatistic = function() called = true; return "3" end
      eq(G.Statistic(nil), nil)
      eq(called, false)
    end)
  end)

  describe("MountSourceText", function()
    it("is nil when the API is missing", function()
      C_MountJournal = nil
      eq(loadGame().Game.MountSourceText(6), nil)
      C_MountJournal = {}
      eq(loadGame().Game.MountSourceText(6), nil)
    end)
    it("returns the 3rd value of GetMountInfoExtraByID, nil for unknown ids and non-strings", function()
      C_MountJournal = { GetMountInfoExtraByID = function(id)
        if id == 6 then return 1234, "A horse.", "|cFFFFD200Drop:|r Delve", false, 230, 4, 0, 0, false end
        if id == 7 then return 1, "x", nil end
      end }
      local G = loadGame().Game
      eq(G.MountSourceText(6), "|cFFFFD200Drop:|r Delve")
      eq(G.MountSourceText(7), nil)
      eq(G.MountSourceText(8), nil)
      eq(G.MountSourceText(nil), nil)
    end)
  end)

  describe("item data", function()
    it("ItemCached asks C_Item.IsItemDataCachedByID; nil when it cannot tell", function()
      C_Item = { IsItemDataCachedByID = function(id)
        if id == 1 then return true end
        if id == 3 then error("boom") end
        return false
      end }
      local G = loadGame().Game
      eq(G.ItemCached(1), true)
      eq(G.ItemCached(2), false)
      eq(G.ItemCached(3), nil, "error caught")
      eq(G.ItemCached(nil), nil)
      C_Item = {}
      eq(loadGame().Game.ItemCached(1), nil, "no API")
      C_Item = nil
      eq(loadGame().Game.ItemCached(1), nil, "no C_Item")
    end)

    it("OnItemLoad runs fn through the Item mixin's ContinueOnItemLoad", function()
      local got
      Item = { CreateFromItemID = function(self, id)
        eq(self, Item)
        return { ContinueOnItemLoad = function(_, fn) got = id; fn() end }
      end }
      local ran = false
      local G = loadGame().Game
      eq(G.OnItemLoad(87771, function() ran = true end), true)
      eq({ got, ran }, { 87771, true })
      eq(G.OnItemLoad(nil, function() end), false)
      Item = { CreateFromItemID = function() error("boom") end }
      eq(loadGame().Game.OnItemLoad(1, function() end), false, "error caught")
      Item = nil
      eq(loadGame().Game.OnItemLoad(1, function() end), false, "no mixin")
    end)
  end)

  describe("MapName", function()
    it("is C_Map.GetMapInfo(id).name; nil when missing, empty, unknown or erroring", function()
      C_Map = { GetMapInfo = function(id)
        if id == 317 then return { mapID = 317, name = "Stratholme" } end
        if id == 2 then return { mapID = 2, name = "" } end
        if id == 3 then return { mapID = 3 } end
        if id == 4 then error("boom") end
      end }
      local G = loadGame().Game
      eq(G.MapName(317), "Stratholme")
      eq(G.MapName(2), nil, "empty name")
      eq(G.MapName(3), nil, "no name")
      eq(G.MapName(4), nil, "error caught")
      eq(G.MapName(5), nil, "unknown map")
      eq(G.MapName(nil), nil)
      eq(G.MapName("x"), nil, "not a number")
      C_Map = nil
      eq(loadGame().Game.MapName(317), nil, "no C_Map")
      C_Map = {}
      eq(loadGame().Game.MapName(317), nil, "no GetMapInfo")
    end)
  end)

  describe("zone lookups (F6)", function()
    it("PlayerMap is GetBestMapForUnit('player'); nil when missing, erroring or not a number", function()
      C_Map = { GetBestMapForUnit = function(unit) eq(unit, "player"); return 71 end }
      eq(loadGame().Game.PlayerMap(), 71)
      C_Map = { GetBestMapForUnit = function() return nil end }
      eq(loadGame().Game.PlayerMap(), nil)
      C_Map = { GetBestMapForUnit = function() error("boom") end }
      eq(loadGame().Game.PlayerMap(), nil, "error caught")
      C_Map = nil
      eq(loadGame().Game.PlayerMap(), nil, "no C_Map")
    end)

    it("MapInfo copies name, mapType and parentMapID; nil when unknown or erroring", function()
      C_Map = { GetMapInfo = function(id)
        if id == 71 then return { mapID = 71, name = "Tanaris", mapType = 3, parentMapID = 12, flags = 4 } end
        if id == 4 then error("boom") end
      end }
      local G = loadGame().Game
      eq(G.MapInfo(71), { name = "Tanaris", mapType = 3, parentMapID = 12 })
      eq(G.MapInfo(5), nil)
      eq(G.MapInfo(4), nil, "error caught")
      eq(G.MapInfo(nil), nil)
      C_Map = {}
      eq(loadGame().Game.MapInfo(71), nil, "no GetMapInfo")
    end)

    it("MapChildren lists every descendant's mapID and mapType; {} otherwise", function()
      C_Map = { GetMapChildrenInfo = function(id, mapType, all)
        eq({ mapType, all }, { nil, true }, "all descendants, any type")
        if id == 71 then
          return { { mapID = 74, name = "Caverns of Time", mapType = 5, parentMapID = 71 }, { name = "no id" } }
        end
        if id == 4 then error("boom") end
      end }
      local G = loadGame().Game
      eq(G.MapChildren(71), { { mapID = 74, mapType = 5 } })
      eq(G.MapChildren(5), {})
      eq(G.MapChildren(4), {}, "error caught")
      eq(G.MapChildren(nil), {})
      C_Map = nil
      eq(loadGame().Game.MapChildren(71), {})
    end)

    it("DungeonEntrances keeps journalInstanceID and name of each entrance; {} otherwise", function()
      C_EncounterJournal = { GetDungeonEntrancesForMap = function(id)
        if id == 249 then
          return { { areaPoiID = 1, journalInstanceID = 68, name = "The Vortex Pinnacle", position = {} },
            { name = "no id" }, "junk" }
        end
        if id == 4 then error("boom") end
      end }
      local G = loadGame().Game
      eq(G.DungeonEntrances(249), { { journalInstanceID = 68, name = "The Vortex Pinnacle" } })
      eq(G.DungeonEntrances(5), {})
      eq(G.DungeonEntrances(4), {}, "error caught")
      eq(G.DungeonEntrances(nil), {})
      C_EncounterJournal = nil
      eq(loadGame().Game.DungeonEntrances(249), {}, "no C_EncounterJournal")
    end)

    it("InstanceForMap is GetInstanceForGameMap; 0, nil and errors -> nil", function()
      C_EncounterJournal = { GetInstanceForGameMap = function(id)
        if id == 325 then return 68 end
        if id == 71 then return 0 end
        if id == 4 then error("boom") end
      end }
      local G = loadGame().Game
      eq(G.InstanceForMap(325), 68)
      eq(G.InstanceForMap(71), nil, "0 means none")
      eq(G.InstanceForMap(5), nil)
      eq(G.InstanceForMap(4), nil)
      C_EncounterJournal = nil
      eq(loadGame().Game.InstanceForMap(325), nil)
    end)

    it("CurrentInstanceName is GetInstanceInfo's name while IsInInstance; nil otherwise", function()
      IsInInstance = function() return true, "raid" end
      GetInstanceInfo = function() return "Dragon Soul", "raid", 14 end
      eq(loadGame().Game.CurrentInstanceName(), "Dragon Soul")
      IsInInstance = function() return false, "none" end
      eq(loadGame().Game.CurrentInstanceName(), nil, "outside")
      IsInInstance = function() return true end
      GetInstanceInfo = function() return "" end
      eq(loadGame().Game.CurrentInstanceName(), nil, "empty name")
      GetInstanceInfo = function() error("boom") end
      eq(loadGame().Game.CurrentInstanceName(), nil, "error caught")
      IsInInstance, GetInstanceInfo = nil, nil
      eq(loadGame().Game.CurrentInstanceName(), nil, "no API")
    end)

    it("JournalInstanceName is EJ_GetInstanceInfo's name; nil when empty, missing or erroring", function()
      EJ_GetInstanceInfo = function(id)
        if id == 68 then return "The Vortex Pinnacle", "desc", 1 end
        if id == 2 then return "" end
        if id == 4 then error("boom") end
      end
      local G = loadGame().Game
      eq(G.JournalInstanceName(68), "The Vortex Pinnacle")
      eq(G.JournalInstanceName(2), nil)
      eq(G.JournalInstanceName(4), nil)
      eq(G.JournalInstanceName(nil), nil, "never the selected instance")
      EJ_GetInstanceInfo = nil
      eq(loadGame().Game.JournalInstanceName(68), nil)
    end)
  end)

  describe("MountDescription", function()
    it("is nil when the API is missing", function()
      C_MountJournal = nil
      eq(loadGame().Game.MountDescription(6), nil)
    end)
    it("returns the 2nd value of GetMountInfoExtraByID, nil for empty or non-strings", function()
      C_MountJournal = { GetMountInfoExtraByID = function(id)
        if id == 6 then return 1234, "A horse.", "Drop: Delve" end
        if id == 7 then return 1, "", "x" end
        if id == 8 then return 1, nil, "x" end
      end }
      local G = loadGame().Game
      eq(G.MountDescription(6), "A horse.")
      eq(G.MountDescription(7), nil)
      eq(G.MountDescription(8), nil)
      eq(G.MountDescription(9), nil)
      eq(G.MountDescription(nil), nil)
    end)
  end)

  -- F17: live status of event rares. Shapes per Blizzard's
  -- AreaPoiInfoDocumentation / ContributionCollectorDocumentation.
  describe("event status (F17)", function()
    it("AreaPOIsForMap is GetAreaPOIForMap(uiMapID)'s numbers; nil when missing, erroring or not a table", function()
      C_AreaPoiInfo = { GetAreaPOIForMap = function(id)
        if id == 1527 then return { 6488, "junk", 7000 } end
        if id == 4 then error("boom") end
        if id == 5 then return "nope" end
        return {}
      end }
      local G = loadGame().Game
      eq(G.AreaPOIsForMap(1527), { 6488, 7000 })
      eq(G.AreaPOIsForMap(249), {}, "the map has none")
      eq(G.AreaPOIsForMap(4), nil, "error caught")
      eq(G.AreaPOIsForMap(5), nil)
      eq(G.AreaPOIsForMap(nil), nil)
      C_AreaPoiInfo = nil
      eq(loadGame().Game.AreaPOIsForMap(1527), nil, "no C_AreaPoiInfo")
    end)

    it("AreaPOIInfo copies name and isCurrentEvent from GetAreaPOIInfo(uiMapID, areaPoiID); nil otherwise", function()
      C_AreaPoiInfo = { GetAreaPOIInfo = function(map, id)
        if map == 1527 and id == 6488 then
          return { areaPoiID = 6488, name = "Assault: Aqir", isCurrentEvent = false, position = {} }
        end
        if id == 4 then error("boom") end
      end }
      local G = loadGame().Game
      eq(G.AreaPOIInfo(1527, 6488), { name = "Assault: Aqir", isCurrentEvent = false })
      eq(G.AreaPOIInfo(1527, 6487), nil, "MayReturnNothing")
      eq(G.AreaPOIInfo(1527, 4), nil, "error caught")
      eq(G.AreaPOIInfo(1527, nil), nil)
      C_AreaPoiInfo = {}
      eq(loadGame().Game.AreaPOIInfo(1527, 6488), nil)
    end)

    it("AreaPOISecondsLeft is GetAreaPOISecondsLeft(areaPoiID); nil when missing, erroring or not positive", function()
      C_AreaPoiInfo = { GetAreaPOISecondsLeft = function(id)
        if id == 6488 then return 3600 end
        if id == 6487 then return 0 end
        if id == 4 then error("boom") end
      end }
      local G = loadGame().Game
      eq(G.AreaPOISecondsLeft(6488), 3600)
      eq(G.AreaPOISecondsLeft(6487), nil)
      eq(G.AreaPOISecondsLeft(6486), nil, "MayReturnNothing")
      eq(G.AreaPOISecondsLeft(4), nil, "error caught")
      C_AreaPoiInfo = nil
      eq(loadGame().Game.AreaPOISecondsLeft(6488), nil)
    end)

    it("ContributionsForMap: each map collector's managed contributions with state, appearance and time left", function()
      GetServerTime = function() return 1000 end
      local asked = {}
      C_ContributionCollector = {
        GetContributionCollectorsForMap = function(map)
          if map == 14 then
            return { { areaPoiID = 1, name = "Collector", collectorCreatureID = 130000, atlasName = "x", position = {} },
              { name = "no creature" }, "junk" }
          end
          if map == 4 then error("boom") end
          return {}
        end,
        GetManagedContributionsForCreatureID = function(creature)
          eq(creature, 130000)
          return 116, 11, 116
        end,
        GetName = function(id) return "Battle for Stromgarde" end,
        GetState = function(id)
          asked[#asked + 1] = id
          if id == 116 then return 1, 0.634, nil, 900 end
          return 2, 1, 4600, 500
        end,
        GetContributionAppearance = function(id, state)
          if id == 116 then return { stateName = "Contributing", tooltipUseTimeRemaining = false } end
          return { stateName = "Active", tooltipUseTimeRemaining = true }
        end,
      }
      local G = loadGame().Game
      eq(G.ContributionsForMap(14), {
        { id = 116, name = "Battle for Stromgarde", state = 1, percent = 0.634, stateName = "Contributing", useTime = false },
        { id = 11, name = "Battle for Stromgarde", state = 2, percent = 1, seconds = 3600, stateName = "Active", useTime = true },
      })
      eq(asked, { 116, 11 }, "each contribution once")
      eq(G.ContributionsForMap(62), {}, "no collector on the map")
      eq(G.ContributionsForMap(4), nil, "error caught")
      eq(G.ContributionsForMap(nil), nil)
      C_ContributionCollector = nil
      eq(loadGame().Game.ContributionsForMap(14), nil, "no C_ContributionCollector")
    end)

    it("ContributionsForMap survives a missing appearance or state call", function()
      C_ContributionCollector = {
        GetContributionCollectorsForMap = function() return { { collectorCreatureID = 1 } } end,
        GetManagedContributionsForCreatureID = function() return 117 end,
      }
      eq(loadGame().Game.ContributionsForMap(62), { { id = 117 } })
    end)
  end)

  describe("wrappers", function()
    it("reads mount info, quests, lfg, resets and expansion logos", function()
      C_MountJournal = { GetMountInfoByID = function(id)
        if id == 6 then return "Brown Horse", 458, 132261, false, true, 0, false, true, 1, false, true, 6 end
        if id == 7 then return "Gray Wolf", 459, 132262, false, true, 0, false, true, 0, false, false, 7 end
      end }
      C_QuestLog = { IsQuestFlaggedCompleted = function(q) return q == 100 end }
      GetLFGDungeonRewards = function(id) return id == 285, 0, 0 end
      C_DateAndTime = { GetSecondsUntilDailyReset = function() return 111 end,
                        GetSecondsUntilWeeklyReset = function() return 222 end }
      GetExpansionDisplayInfo = function(level) if level == 11 then return { logo = 5000 } end end
      local G = loadGame().Game
      eq(G.IsOwned(6), true); eq(G.IsOwned(7), false); eq(G.IsOwned(8), false)
      eq(G.Exists(7), true); eq(G.Exists(8), false)
      eq({ G.MountInfo(6) }, { "Brown Horse", 132261, 458 })
      eq(G.IsQuestDone(100), true); eq(G.IsQuestDone(101), false)
      eq(G.IsLfgDone(285), true); eq(G.IsLfgDone(287), false)
      eq(G.UntilDaily(), 111); eq(G.UntilWeekly(), 222)
      eq(G.ExpansionLogo(12), 5000, "index 12 (Midnight) -> expansion level 11")
      eq(G.ExpansionLogo(1), nil)
    end)
    it("builds CharKey as Name-Realm", function()
      UnitName = function() return "Jaina" end
      GetNormalizedRealmName = function() return "Proudmoore" end
      eq(loadGame().Game.CharKey(), "Jaina-Proudmoore")
    end)
    it("PlayerName is the character name, nil when unknown", function()
      UnitName = function(unit) if unit == "player" then return "Jaina" end end
      eq(loadGame().Game.PlayerName(), "Jaina")
      UnitName = nil
      eq(loadGame().Game.PlayerName(), nil)
    end)
  end)

  describe("ActiveHolidays", function()
    it("opens the calendar once and matches today's HOLIDAY titles", function()
      local opened = 0
      C_DateAndTime = { GetCurrentCalendarTime = function() return { year = 2026, month = 10, monthDay = 16 } end }
      local events = {
        { title = "Hallow's End", calendarType = "HOLIDAY" },
        { title = "Brewfest", calendarType = "PLAYER" },
        { title = "Some Other Holiday", calendarType = "HOLIDAY" },
      }
      C_Calendar = {
        OpenCalendar = function() opened = opened + 1 end,
        GetMonthInfo = function() return { year = 2026, month = 10 } end,
        GetNumDayEvents = function(monthOffset, day) eq(monthOffset, 0); eq(day, 16); return #events end,
        GetDayEvent = function(monthOffset, day, i) return events[i] end,
      }
      local G = loadGame().Game
      eq(G.ActiveHolidays(), { hallowsend = true })
      eq(G.ActiveHolidays(), { hallowsend = true })
      eq(opened, 1, "OpenCalendar called once")
    end)
    it("uses the month offset of today when the calendar shows another month", function()
      C_DateAndTime = { GetCurrentCalendarTime = function() return { year = 2026, month = 10, monthDay = 16 } end }
      local seen
      C_Calendar = {
        OpenCalendar = function() end,
        GetMonthInfo = function() return { year = 2026, month = 12 } end,
        GetNumDayEvents = function(monthOffset) seen = monthOffset; return 0 end,
        GetDayEvent = function() end,
      }
      eq(loadGame().Game.ActiveHolidays(), {})
      eq(seen, -2)
    end)
  end)

  describe("HolidaySchedule", function()
    local TODAY = { year = 2026, month = 10, monthDay = 19, weekday = 2, hour = 12, minute = 0 }
    local DAYS_IN_MONTH = { 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 } -- 2026 and 2027

    local function ct(year, month, monthDay, hour)
      return { year = year, month = month, monthDay = monthDay, weekday = 1, hour = hour or 0, minute = 0 }
    end

    -- A calendar showing `shown`: cfg.events["<year>-<month>-<day>"] = { day events }.
    -- Records every GetNumDayEvents(offset, day) in cal.calls.
    local function fakeCalendar(cfg)
      cfg = cfg or {}
      local shown = cfg.shown or { year = 2026, month = 10 }
      local events = cfg.events or {}
      local cal = { calls = {}, opened = 0, today = cfg.today or TODAY }
      local function monthOf(offset)
        local index = shown.year * 12 + (shown.month - 1) + offset
        local month = index % 12 + 1
        return math.floor(index / 12), month, DAYS_IN_MONTH[month]
      end
      C_DateAndTime = { GetCurrentCalendarTime = function() return cal.today end }
      C_Calendar = {
        OpenCalendar = function() cal.opened = cal.opened + 1 end,
        GetMonthInfo = function(offset)
          local year, month, numDays = monthOf(offset)
          return { year = year, month = month, numDays = numDays, firstWeekday = 1 }
        end,
        GetNumDayEvents = function(offset, day)
          cal.calls[#cal.calls + 1] = { offset, day }
          local year, month = monthOf(offset)
          return #(events[year .. "-" .. month .. "-" .. day] or {})
        end,
        GetDayEvent = function(offset, day, i)
          local year, month = monthOf(offset)
          return events[year .. "-" .. month .. "-" .. day][i]
        end,
        GetMaxCreateDate = cfg.max and function() return cfg.max end or nil,
      }
      return cal
    end

    local function holiday(title, startTime, endTime, extra)
      local event = { title = title, calendarType = "HOLIDAY", startTime = startTime, endTime = endTime,
        sequenceType = "ONGOING" }
      for k, v in pairs(extra or {}) do event[k] = v end
      return event
    end

    it("lists each holiday's coming runs: one entry per run, however many days it spans", function()
      local hallowStart, hallowEnd = ct(2026, 10, 18, 6), ct(2026, 11, 1, 6)
      local darkStart, darkEnd = ct(2026, 11, 1, 0), ct(2026, 11, 7, 23)
      fakeCalendar({ events = {
        ["2026-10-19"] = { holiday("Hallow's End", hallowStart, hallowEnd) },
        ["2026-10-20"] = { holiday("Hallow's End", hallowStart, hallowEnd) },
        ["2026-11-1"] = { holiday("Hallow's End", hallowStart, hallowEnd, { sequenceType = "END" }),
          holiday("Darkmoon Faire", darkStart, darkEnd, { sequenceType = "START" }) },
        ["2026-11-2"] = { holiday("Darkmoon Faire", darkStart, darkEnd) },
      } })
      local schedule = loadGame().Game.HolidaySchedule()
      eq(schedule.occurrences.hallowsend, { { startTime = hallowStart, endTime = hallowEnd } })
      eq(schedule.occurrences.darkmoon, { { startTime = darkStart, endTime = darkEnd } })
      eq(schedule.occurrences.brewfest, nil)
    end)

    it("hands over the calendar's current time", function()
      fakeCalendar()
      eq(loadGame().Game.HolidaySchedule().now, TODAY)
    end)

    it("ignores events that are not holidays or not in Data.Holidays, and ones without times", function()
      local s, e = ct(2026, 10, 25), ct(2026, 10, 30)
      fakeCalendar({ events = { ["2026-10-25"] = {
        holiday("Brewfest", s, e, { calendarType = "PLAYER" }),
        holiday("Some Other Holiday", s, e),
        holiday("Noblegarden", nil, e),
        holiday("Lunar Festival", s, nil),
        holiday("Winter Veil", s, e),
      } } })
      eq(loadGame().Game.HolidaySchedule().occurrences, {})
    end)

    it("keeps the next two runs of a holiday, in calendar order", function()
      local runs = { { ct(2026, 10, 21), ct(2026, 10, 22) }, { ct(2026, 11, 3), ct(2026, 11, 4) },
        { ct(2026, 12, 5), ct(2026, 12, 6) } }
      fakeCalendar({ events = {
        ["2026-10-21"] = { holiday("Darkmoon Faire", runs[1][1], runs[1][2], { sequenceType = "START" }) },
        ["2026-11-3"] = { holiday("Darkmoon Faire", runs[2][1], runs[2][2], { sequenceType = "START" }) },
        ["2026-12-5"] = { holiday("Darkmoon Faire", runs[3][1], runs[3][2], { sequenceType = "START" }) },
      } })
      eq(loadGame().Game.HolidaySchedule().occurrences.darkmoon, {
        { startTime = runs[1][1], endTime = runs[1][2] },
        { startTime = runs[2][1], endTime = runs[2][2] },
      })
    end)

    it("starts at today in this month and at the 1st in later ones, for each month's real length", function()
      local cal = fakeCalendar({ max = { year = 2026, month = 12 } })
      loadGame().Game.HolidaySchedule()
      eq(cal.calls[1], { 0, 19 })
      eq(cal.calls[13], { 0, 31 })
      eq(cal.calls[14], { 1, 1 })
      eq(cal.calls[43], { 1, 30 })
      eq(cal.calls[44], { 2, 1 })
      eq(cal.calls[#cal.calls], { 2, 31 })
      eq(#cal.calls, 13 + 30 + 31)
    end)

    it("counts month offsets from the month the calendar shows", function()
      local cal = fakeCalendar({ shown = { year = 2026, month = 12 }, max = { year = 2026, month = 10 } })
      loadGame().Game.HolidaySchedule()
      eq(cal.calls[1], { -2, 19 })
      eq(cal.calls[#cal.calls], { -2, 31 })
    end)

    it("looks ahead to the latest date the calendar offers, at most a year", function()
      local cal = fakeCalendar({ max = { year = 2030, month = 1 } })
      loadGame().Game.HolidaySchedule()
      eq(cal.calls[#cal.calls], { 12, DAYS_IN_MONTH[(10 - 1 + 12) % 12 + 1] })
      cal = fakeCalendar()
      loadGame().Game.HolidaySchedule()
      eq(cal.calls[#cal.calls][1], 12, "no GetMaxCreateDate: a year ahead")
    end)

    it("opens the calendar once", function()
      local cal = fakeCalendar()
      local G = loadGame().Game
      G.HolidaySchedule()
      G.CalendarChanged()
      G.HolidaySchedule()
      G.ActiveHolidays()
      eq(cal.opened, 1)
    end)

    it("reads the calendar once per day until it changes", function()
      local cal = fakeCalendar({ max = { year = 2026, month = 10 } })
      local G = loadGame().Game
      local first = G.HolidaySchedule()
      local reads = #cal.calls
      ok(reads > 0, "scanned")
      cal.today = { year = 2026, month = 10, monthDay = 19, weekday = 2, hour = 18, minute = 30 }
      local second = G.HolidaySchedule()
      eq(#cal.calls, reads, "same day: no rescan")
      eq(second.occurrences, first.occurrences)
      eq(second.now, cal.today, "but the time is current")
      G.CalendarChanged()
      G.HolidaySchedule()
      eq(#cal.calls, reads * 2, "CALENDAR_UPDATE_EVENT_LIST: rescan")
      cal.today = { year = 2026, month = 10, monthDay = 20, weekday = 3, hour = 0, minute = 5 }
      G.HolidaySchedule()
      ok(#cal.calls > reads * 2, "next day: rescan")
    end)

    it("is nil when the calendar API is missing or incomplete", function()
      local G = loadGame().Game
      C_DateAndTime, C_Calendar = nil, nil
      eq(G.HolidaySchedule(), nil)
      fakeCalendar()
      C_Calendar.GetDayEvent = nil
      eq(G.HolidaySchedule(), nil)
      fakeCalendar()
      C_Calendar.GetMonthInfo = nil
      eq(G.HolidaySchedule(), nil)
      fakeCalendar()
      C_DateAndTime.GetCurrentCalendarTime = function() return nil end
      eq(G.HolidaySchedule(), nil)
    end)

    it("skips a month the calendar has no length for", function()
      local cal = fakeCalendar({ max = { year = 2026, month = 11 } })
      local info = C_Calendar.GetMonthInfo
      C_Calendar.GetMonthInfo = function(offset) if offset ~= 1 then return info(offset) end end
      loadGame().Game.HolidaySchedule()
      eq(cal.calls[#cal.calls], { 0, 31 })
    end)

    it("an API error gives nil, nothing cached, no Lua error", function()
      local cal = fakeCalendar()
      local boom = true
      local count = C_Calendar.GetNumDayEvents
      C_Calendar.GetNumDayEvents = function(...) if boom then error("calendar hiccup") end return count(...) end
      local G = loadGame().Game
      eq(G.HolidaySchedule(), nil)
      boom = false
      ok(G.HolidaySchedule() ~= nil, "the next call retries")
      ok(#cal.calls > 0)
    end)
  end)
end)

describe("init", function()
  local function setup()
    local ns = load_addon(toc_lua_files())
    -- Small fixture data so the tracked list is predictable (R16).
    ns.Data.Lockouts = {
      [1] = { instance = 532, boss = "Attumen the Huntsman", difficulties = { 3 }, reset = "weekly" },
      [2] = { lfg = 285, reset = "daily" },
      [3] = { manual = true, reset = "weekly" },
    }
    ns.Data.BossLockouts = {}
    ns.Data.Mounts = { [4] = { name = "Quest Mount", quest = 900 }, [5] = { name = "Untracked" } }
    local rows, quests, lfg, owned = {}, {}, {}, {}
    ns.Game.SavedRows = function() return rows end
    ns.Game.IsQuestDone = function(id) return quests[id] == true end
    ns.Game.IsLfgDone = function(id) return lfg[id] == true end
    ns.Game.IsOwned = function(id) return owned[id] == true end
    ns.Game.RequestLockouts = function() end
    ns.Game.Now = function() return 1000 end
    ns.Game.CharKey = function() return "Me-Realm" end
    ns.addon:OnInitialize()
    ns.addon:OnEnable()
    local function kill()
      rows[1] = { instance = 532, difficulty = 3, bosses = { { name = "Attumen the Huntsman", killed = true } } }
    end
    return ns, { rows = rows, quests = quests, lfg = lfg, owned = owned, kill = kill }
  end

  -- This character's attempt counters (F8: ns.db.global.attemptsByChar).
  local function mine(ns)
    return ns.db.global.attemptsByChar["Me-Realm"] or {}
  end

  it("db defaults: filters is a copy of Journal.DefaultFilters", function()
    local ns = setup()
    eq(ns.db.global.filters, ns.Journal.DefaultFilters)
    eq(ns.db.global.filters, { collected = false })
    ok(ns.db.global.filters ~= ns.Journal.DefaultFilters, "a copy, not the same table")
    eq(ns.db.global.attempts, {})
    eq(ns.db.global.attemptsByChar, {})
    eq(ns.db.global.stats, {})
    eq(ns.db.global.minimap, { hide = false })
    eq(ns.db.global.window, {})
    eq(ns.db.char.ticks, {})
  end)

  it("first observation counts nothing, then open -> done adds +1", function()
    local ns, w = setup()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    eq(mine(ns), {})
    ok(ns.db.char.last, "last stored")
    w.kill()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    eq(mine(ns), { [1] = 1 })
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    eq(mine(ns), { [1] = 1 }, "done -> done does not count again")
  end)

  it("quest and lfg transitions count via their events", function()
    local ns, w = setup()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    fire_event(ns.addon, "LFG_UPDATE_RANDOM_INFO")
    w.quests[900] = true
    fire_event(ns.addon, "QUEST_TURNED_IN", 900)
    w.lfg[285] = true
    fire_event(ns.addon, "LFG_UPDATE_RANDOM_INFO")
    eq(mine(ns), { [2] = 1, [4] = 1 })
  end)

  it("owned mounts are not counted", function()
    local ns, w = setup()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    w.owned[1] = true
    w.kill()
    fire_event(ns.addon, "NEW_MOUNT_ADDED", 1)
    eq(mine(ns), {})
  end)

  it("a kill seen last session is not recounted when instance data arrives late", function()
    local ns, w = setup()
    -- Last session ended with the boss already dead.
    ns.db.char.last = { snap = { [532] = { [3] = { ["Attumen the Huntsman"] = true } } }, quests = {}, lfg = {} }
    -- A quest event fires before UPDATE_INSTANCE_INFO: SavedRows is still empty.
    fire_event(ns.addon, "QUEST_TURNED_IN", 1)
    w.kill()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    eq(mine(ns), {})
  end)

  it("only UPDATE_INSTANCE_INFO re-reads saved instances; other events reuse the last snapshot", function()
    local ns, w = setup()
    w.kill()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    fire_event(ns.addon, "LFG_UPDATE_RANDOM_INFO")
    -- The saved list is transiently incomplete while other events fire.
    w.rows[1] = nil
    w.quests[900] = true
    fire_event(ns.addon, "QUEST_TURNED_IN", 900)
    fire_event(ns.addon, "LFG_UPDATE_RANDOM_INFO")
    fire_event(ns.addon, "NEW_MOUNT_ADDED", 7)
    eq(ns.db.char.last.snap, { [532] = { [3] = { ["Attumen the Huntsman"] = true } } }, "snapshot kept")
    eq(ns.db.char.last.quests, { [900] = true }, "quest flags refreshed")
    -- The full list comes back: the kill is not counted as new.
    w.kill()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    eq(mine(ns), { [4] = 1 }, "only the quest counted")
  end)

  it("a kill is counted on UPDATE_INSTANCE_INFO, not on another event", function()
    local ns, w = setup()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    w.kill()
    fire_event(ns.addon, "QUEST_TURNED_IN", 1)
    eq(mine(ns), {})
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    eq(mine(ns), { [1] = 1 })
  end)

  it("an lfg done last session is not recounted when lfg data arrives late", function()
    local ns, w = setup()
    ns.db.char.last = { snap = {}, quests = {}, lfg = { [285] = true } }
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO") -- lfg data not loaded yet: IsLfgDone false
    w.lfg[285] = true
    fire_event(ns.addon, "LFG_UPDATE_RANDOM_INFO")
    eq(mine(ns), {})
  end)

  it("counts per character; the legacy account-wide counter is kept but never incremented", function()
    local ns, w = setup()
    ns.db.global.attempts[1] = 5 -- counted before F8
    ns.db.global.attemptsByChar["Alt-Realm"] = { [1] = 2 }
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    w.kill()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    eq(ns.db.global.attemptsByChar, { ["Me-Realm"] = { [1] = 1 }, ["Alt-Realm"] = { [1] = 2 } })
    eq(ns.db.global.attempts, { [1] = 5 }, "legacy bucket untouched")
  end)

  it("fires ns.Refresh looked up at call time", function()
    local ns = setup()
    local calls = 0
    ns.Refresh = function() calls = calls + 1 end
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    eq(calls, 1)
  end)

  it("PLAYER_ENTERING_WORLD requests lockouts and prunes expired ticks", function()
    local ns = setup()
    local requested = 0
    ns.Game.RequestLockouts = function() requested = requested + 1 end
    ns.db.char.ticks = { [1] = 900, [2] = 2000 }
    fire_event(ns.addon, "PLAYER_ENTERING_WORLD")
    eq(requested, 1)
    eq(ns.db.char.ticks, { [2] = 2000 })
  end)

  describe("kill statistics", function()
    local function withStats()
      local ns, w = setup()
      ns.Data.Mounts = {
        [6] = { name = "Stat Mount", stats = { 61, 62 } },
        [7] = { name = "Other Stat Mount", stats = { 71 } },
        [8] = { name = "No Stats" },
      }
      local values = { [61] = 2, [62] = 3, [71] = 0 }
      local combat, reads = false, 0
      ns.Game.Statistic = function(id) reads = reads + 1; return values[id] end
      ns.Game.InCombat = function() return combat end
      ns.Game.CharKey = function() return "Me-Realm" end
      w.values, w.setCombat, w.reads = values, function(v) combat = v end, function() return reads end
      return ns, w
    end

    it("PLAYER_ENTERING_WORLD stores this character's summed statistics", function()
      local ns = withStats()
      ns.db.global.stats["Alt-Realm"] = { [6] = 9 }
      fire_event(ns.addon, "PLAYER_ENTERING_WORLD")
      eq(ns.db.global.stats, { ["Alt-Realm"] = { [6] = 9 }, ["Me-Realm"] = { [6] = 5, [7] = 0 } })
    end)

    it("UPDATE_INSTANCE_INFO re-reads them; other events do not", function()
      local ns, w = withStats()
      fire_event(ns.addon, "PLAYER_ENTERING_WORLD")
      w.values[61] = 4
      fire_event(ns.addon, "QUEST_TURNED_IN", 1)
      fire_event(ns.addon, "LFG_UPDATE_RANDOM_INFO")
      eq(ns.db.global.stats["Me-Realm"][6], 5)
      fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
      eq(ns.db.global.stats["Me-Realm"][6], 7)
    end)

    it("keeps the last value when a statistic gives no reading or a lower one", function()
      local ns, w = withStats()
      fire_event(ns.addon, "PLAYER_ENTERING_WORLD")
      w.values[71] = nil
      w.values[61], w.values[62] = 10, nil -- partial: mount 6 is not read
      fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
      eq(ns.db.global.stats["Me-Realm"], { [6] = 5, [7] = 0 })
      w.values[61], w.values[62] = 0, 0 -- "--" before the data loads
      fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
      eq(ns.db.global.stats["Me-Realm"][6], 5)
      w.values[61], w.values[62] = 4, 3
      fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
      eq(ns.db.global.stats["Me-Realm"][6], 7)
    end)

    it("waits for the end of combat before reading", function()
      local ns, w = withStats()
      w.setCombat(true)
      fire_event(ns.addon, "PLAYER_ENTERING_WORLD")
      fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
      eq(w.reads(), 0, "nothing read in combat")
      eq(ns.db.global.stats, {})
      w.setCombat(false)
      local refreshed = 0
      ns.Refresh = function() refreshed = refreshed + 1 end
      fire_event(ns.addon, "PLAYER_REGEN_ENABLED")
      eq(ns.db.global.stats, { ["Me-Realm"] = { [6] = 5, [7] = 0 } })
      eq(refreshed, 1, "refreshes after the deferred read")
      local after = w.reads()
      fire_event(ns.addon, "PLAYER_REGEN_ENABLED")
      eq(w.reads(), after, "leaving combat again reads nothing new")
      eq(refreshed, 1, "and does not refresh")
    end)
  end)

  it("CALENDAR_UPDATE_EVENT_LIST fires ns.Refresh", function()
    local ns = setup()
    local calls = 0
    ns.Refresh = function() calls = calls + 1 end
    fire_event(ns.addon, "CALENDAR_UPDATE_EVENT_LIST")
    eq(calls, 1)
  end)

  it("CALENDAR_UPDATE_EVENT_LIST drops the cached holiday schedule before the refresh", function()
    local ns = setup()
    local order = {}
    ns.Game.CalendarChanged = function() order[#order + 1] = "changed" end
    ns.Refresh = function() order[#order + 1] = "refresh" end
    fire_event(ns.addon, "CALENDAR_UPDATE_EVENT_LIST")
    eq(order, { "changed", "refresh" })
  end)

  it("AREA_POIS_UPDATED and CONTRIBUTION_COLLECTOR_UPDATE tell the checklist's event status (F17)", function()
    local ns = setup()
    local calls, refreshes = 0, 0
    ns.Refresh = function() refreshes = refreshes + 1 end
    fire_event(ns.addon, "AREA_POIS_UPDATED") -- no UI loaded: nothing to tell, no error
    ns.UI = { EventStatusChanged = function() calls = calls + 1 end }
    fire_event(ns.addon, "AREA_POIS_UPDATED")
    fire_event(ns.addon, "CONTRIBUTION_COLLECTOR_UPDATE")
    eq(calls, 2)
    eq(refreshes, 0, "no full refresh: the checklist redraws itself, throttled")
  end)

  it("BOSS_KILL and ENCOUNTER_END request fresh lockouts", function()
    local ns = setup()
    local requested = 0
    ns.Game.RequestLockouts = function() requested = requested + 1 end
    fire_event(ns.addon, "BOSS_KILL")
    eq(requested, 1)
    fire_event(ns.addon, "ENCOUNTER_END")
    eq(requested, 2)
  end)

  describe("slash", function()
    it("dump prints instance, difficulty and bosses", function()
      local ns, w = setup()
      w.kill()
      run_slash(ns.addon, "mtrail", "dump")
      local out = table.concat(ns.addon.printed, "\n")
      ok(out:find("532", 1, true), "instance id printed: " .. out)
      ok(out:find("Attumen the Huntsman", 1, true), "boss printed")
      ok(out:find("killed", 1, true), "kill state printed")
    end)
    it("dump shows rows with nil instance or difficulty", function()
      local ns = setup()
      ns.Game.SavedRows = function(includeIncomplete)
        if not includeIncomplete then return {} end
        return { { name = "Mystery Raid", instance = nil, difficulty = 16, bosses = { { name = "Boss", killed = true } } } }
      end
      run_slash(ns.addon, "mtrail", "dump")
      local out = table.concat(ns.addon.printed, "\n")
      ok(out:find("Mystery Raid", 1, true), "incomplete row printed: " .. out)
      ok(out:find("nil", 1, true), "missing id shown as nil")
    end)
    it("dump with no saved instances says so", function()
      local ns = setup()
      run_slash(ns.addon, "mtrail", "dump")
      ok(#ns.addon.printed >= 1, "prints something")
    end)
    it("no argument toggles the window when present, else prints", function()
      local ns = setup()
      run_slash(ns.addon, "mtrail", "")
      ok(#ns.addon.printed >= 1, "prints when no window")
      local toggled = 0
      ns.ToggleWindow = function() toggled = toggled + 1 end
      run_slash(ns.addon, "mounttrail", "")
      eq(toggled, 1)
    end)
    it("help lists commands", function()
      local ns = setup()
      run_slash(ns.addon, "mtrail", "help")
      local out = table.concat(ns.addon.printed, "\n")
      ok(out:find("dump", 1, true), "help mentions dump")
      ok(out:find("/mtrail debug", 1, true), "help mentions /mtrail debug")
    end)
    it("debug toggles ns.db.global.debug (default off) and says so", function()
      local ns = setup()
      eq(ns.db.global.debug, false)
      run_slash(ns.addon, "mtrail", "debug")
      eq(ns.db.global.debug, true)
      ok(ns.addon.printed[#ns.addon.printed]:find("on", 1, true), "says on")
      run_slash(ns.addon, "mtrail", " DEBUG ")
      eq(ns.db.global.debug, false)
      ok(ns.addon.printed[#ns.addon.printed]:find("off", 1, true), "says off")
    end)
  end)
end)

describe("game spec hygiene", function()
  harnessIt("API globals are back to their original values", function()
    for _, name in ipairs(API_GLOBALS) do
      eq(_G[name], ORIGINAL[name], name .. " restored")
    end
  end)
end)
