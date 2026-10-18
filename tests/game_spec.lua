-- API globals these specs replace; every `it` below saves and restores them
-- so one test's stubs never leak into the next.
local API_GLOBALS = {
  "UnitFactionGroup", "UnitName", "GetNormalizedRealmName", "GetRealmName",
  "GetNumSavedInstances", "GetSavedInstanceInfo", "GetSavedInstanceEncounterInfo",
  "C_DateAndTime", "C_Calendar", "GetExpansionDisplayInfo", "C_MountJournal",
  "C_QuestLog", "GetLFGDungeonRewards", "RequestRaidInfo", "RequestLFDPlayerLockInfo",
  "GetServerTime", "geterrorhandler", "GetStatistic", "InCombatLockdown", "C_Map",
  "C_Item", "Item", "C_EncounterJournal", "EJ_GetInstanceInfo",
  "IsInInstance", "GetInstanceInfo",
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

  describe("ReportError (/azt debug)", function()
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
      eq(got, { "AzerothTrail: Map.lua:42: boom", "AzerothTrail: nil" })
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
    eq(ns.db.char.showCompleted, nil, "the route list's Show completed is retired (F16)")
    eq(ns.db.char.routeMode, "list")
  end)

  it("OnInitialize retires the route planner's saved state (F16)", function()
    local AceDB = LibStub("AceDB-3.0")
    local realNew = AceDB.New
    AceDB.New = function(self, svName, defaults)
      local db = realNew(self, svName, defaults)
      db.char.routeMode, db.char.routeView, db.char.showCompleted = "arrow", "checklist", true
      db.global.window = { tab = "route", point = "CENTER" }
      return db
    end
    local good, ns = pcall(setup)
    AceDB.New = realNew
    assert(good, ns)
    eq(ns.db.char.routeMode, "list", "the parked arrow can't show")
    eq(ns.db.char.routeView, nil)
    eq(ns.db.char.showCompleted, nil)
    eq(ns.db.global.window, { tab = "checklist", point = "CENTER" })
  end)

  it("OnInitialize migrates pre-F15 flat journal filters into filters.journal", function()
    local AceDB = LibStub("AceDB-3.0")
    local realNew = AceDB.New
    AceDB.New = function(self, svName, defaults)
      local db = realNew(self, svName, defaults)
      db.global.filters = { collected = true, dungeon = true, raid = false, vendor = false }
      return db
    end
    local good, ns = pcall(setup)
    AceDB.New = realNew
    assert(good, ns)
    eq(ns.db.global.filters, { collected = true, journal = { raid = false, vendor = false } })
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
      run_slash(ns.addon, "azt", "dump")
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
      run_slash(ns.addon, "azt", "dump")
      local out = table.concat(ns.addon.printed, "\n")
      ok(out:find("Mystery Raid", 1, true), "incomplete row printed: " .. out)
      ok(out:find("nil", 1, true), "missing id shown as nil")
    end)
    it("dump with no saved instances says so", function()
      local ns = setup()
      run_slash(ns.addon, "azt", "dump")
      ok(#ns.addon.printed >= 1, "prints something")
    end)
    it("no argument toggles the window when present, else prints", function()
      local ns = setup()
      run_slash(ns.addon, "azt", "")
      ok(#ns.addon.printed >= 1, "prints when no window")
      local toggled = 0
      ns.ToggleWindow = function() toggled = toggled + 1 end
      run_slash(ns.addon, "azerothtrail", "")
      eq(toggled, 1)
    end)
    it("help lists commands", function()
      local ns = setup()
      run_slash(ns.addon, "azt", "help")
      local out = table.concat(ns.addon.printed, "\n")
      ok(out:find("dump", 1, true), "help mentions dump")
      ok(out:find("/azt debug", 1, true), "help mentions /azt debug")
    end)
    it("debug toggles ns.db.global.debug (default off) and says so", function()
      local ns = setup()
      eq(ns.db.global.debug, false)
      run_slash(ns.addon, "azt", "debug")
      eq(ns.db.global.debug, true)
      ok(ns.addon.printed[#ns.addon.printed]:find("on", 1, true), "says on")
      run_slash(ns.addon, "azt", " DEBUG ")
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
