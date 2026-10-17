-- API globals these specs replace; every `it` below saves and restores them
-- so one test's stubs never leak into the next.
local API_GLOBALS = {
  "UnitFactionGroup", "UnitName", "GetNormalizedRealmName", "GetRealmName",
  "GetNumSavedInstances", "GetSavedInstanceInfo", "GetSavedInstanceEncounterInfo",
  "C_DateAndTime", "C_Calendar", "GetExpansionDisplayInfo", "C_MountJournal",
  "C_QuestLog", "GetLFGDungeonRewards", "RequestRaidInfo", "RequestLFDPlayerLockInfo",
  "GetServerTime",
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
    ns.addon:OnInitialize()
    ns.addon:OnEnable()
    local function kill()
      rows[1] = { instance = 532, difficulty = 3, bosses = { { name = "Attumen the Huntsman", killed = true } } }
    end
    return ns, { rows = rows, quests = quests, lfg = lfg, owned = owned, kill = kill }
  end

  it("db defaults: filters is a copy of Journal.DefaultFilters", function()
    local ns = setup()
    eq(ns.db.global.filters, ns.Journal.DefaultFilters)
    ok(ns.db.global.filters ~= ns.Journal.DefaultFilters, "a copy, not the same table")
    eq(ns.db.global.attempts, {})
    eq(ns.db.global.minimap, { hide = false })
    eq(ns.db.global.window, {})
    eq(ns.db.char.ticks, {})
    eq(ns.db.char.showCompleted, false)
  end)

  it("first observation counts nothing, then open -> done adds +1", function()
    local ns, w = setup()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    eq(ns.db.global.attempts, {})
    ok(ns.db.char.last, "last stored")
    w.kill()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    eq(ns.db.global.attempts, { [1] = 1 })
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    eq(ns.db.global.attempts, { [1] = 1 }, "done -> done does not count again")
  end)

  it("quest and lfg transitions count via their events", function()
    local ns, w = setup()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    fire_event(ns.addon, "LFG_UPDATE_RANDOM_INFO")
    w.quests[900] = true
    fire_event(ns.addon, "QUEST_TURNED_IN", 900)
    w.lfg[285] = true
    fire_event(ns.addon, "LFG_UPDATE_RANDOM_INFO")
    eq(ns.db.global.attempts, { [2] = 1, [4] = 1 })
  end)

  it("owned mounts are not counted", function()
    local ns, w = setup()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    w.owned[1] = true
    w.kill()
    fire_event(ns.addon, "NEW_MOUNT_ADDED", 1)
    eq(ns.db.global.attempts, {})
  end)

  it("a kill seen last session is not recounted when instance data arrives late", function()
    local ns, w = setup()
    -- Last session ended with the boss already dead.
    ns.db.char.last = { snap = { [532] = { [3] = { ["Attumen the Huntsman"] = true } } }, quests = {}, lfg = {} }
    -- A quest event fires before UPDATE_INSTANCE_INFO: SavedRows is still empty.
    fire_event(ns.addon, "QUEST_TURNED_IN", 1)
    w.kill()
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
    eq(ns.db.global.attempts, {})
  end)

  it("an lfg done last session is not recounted when lfg data arrives late", function()
    local ns, w = setup()
    ns.db.char.last = { snap = {}, quests = {}, lfg = { [285] = true } }
    fire_event(ns.addon, "UPDATE_INSTANCE_INFO") -- lfg data not loaded yet: IsLfgDone false
    w.lfg[285] = true
    fire_event(ns.addon, "LFG_UPDATE_RANDOM_INFO")
    eq(ns.db.global.attempts, {})
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
      ok(table.concat(ns.addon.printed, "\n"):find("dump", 1, true), "help mentions dump")
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
