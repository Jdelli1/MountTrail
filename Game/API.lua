local ADDON, ns = ...

-- The only place MountTrail calls the WoW API. Every global is looked up at
-- call time and guarded: an API missing on this client gives a safe fallback
-- (false / 0 / nil / {}), never a Lua error.
local Game = {}
ns.Game = Game

local function mountInfo(mountID)
  local journal = C_MountJournal
  if not (journal and journal.GetMountInfoByID and mountID) then return nil end
  return journal.GetMountInfoByID(mountID)
end

-- Errors the addon catches on purpose (pcall around map, waypoint and arrow
-- calls) are dropped silently unless `/mtrail debug` is on
-- (ns.db.global.debug): then they go to geterrorhandler(), prefixed
-- "MountTrail: ". -> true when the error was handed to the handler. Never
-- raises.
function Game.ReportError(err)
  local db = ns.db
  if not (db and db.global and db.global.debug == true) then return false end
  if type(geterrorhandler) ~= "function" then return false end
  local good, handler = pcall(geterrorhandler)
  if not (good and type(handler) == "function") then return false end
  return (pcall(handler, "MountTrail: " .. tostring(err)))
end

-- C_MountJournal.GetMountInfoByID: name, spellID, icon, isActive, isUsable,
-- sourceType, isFavorite, isFactionSpecific, faction, shouldHideOnChar,
-- isCollected, mountID.
function Game.IsOwned(mountID)
  return select(11, mountInfo(mountID)) == true
end

function Game.Exists(mountID)
  return mountInfo(mountID) ~= nil
end

-- -> name, icon, spellID (nil when unknown to this client).
function Game.MountInfo(mountID)
  local name, spellID, icon = mountInfo(mountID)
  return name, icon, spellID
end

-- C_MountJournal.GetMountInfoExtraByID: creatureDisplayInfoID, description,
-- source, isSelfMount, mountTypeID, ... -> the source text (may hold colour
-- codes), or nil when unknown or the API is missing.
function Game.MountSourceText(mountID)
  local journal = C_MountJournal
  if not (journal and journal.GetMountInfoExtraByID and mountID) then return nil end
  local source = select(3, journal.GetMountInfoExtraByID(mountID))
  if type(source) == "string" then return source end
  return nil
end

-- C_Map.GetMapInfo(mapID).name, or nil when the map is unknown, has no name,
-- the API is missing or errors (Game.ReportError).
function Game.MapName(mapID)
  if type(mapID) ~= "number" then return nil end
  local map = C_Map
  if not (type(map) == "table" and type(map.GetMapInfo) == "function") then return nil end
  local good, info = pcall(map.GetMapInfo, mapID)
  if not good then
    Game.ReportError(info)
    return nil
  end
  local name = type(info) == "table" and info.name or nil
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- Zone side panel (UI/ZonePanel.lua) -------------------------------------------

-- Calls lib[method](...) under pcall -> the results, or nothing when the
-- function is missing or errors (Game.ReportError).
local function call(lib, method, ...)
  if type(lib) ~= "table" or type(lib[method]) ~= "function" then return end
  return (function(good, ...)
    if not good then
      Game.ReportError((...))
      return
    end
    return ...
  end)(pcall(lib[method], ...))
end

-- The player's map: C_Map.GetBestMapForUnit("player"), nil when unknown
-- (loading screens, some instances) or the API is missing / errors.
function Game.PlayerMap()
  local id = call(C_Map, "GetBestMapForUnit", "player")
  if type(id) == "number" then return id end
  return nil
end

-- C_Map.GetMapInfo(mapID) -> { name=, mapType= (Enum.UIMapType), parentMapID= }
-- (a copy of those fields), nil when unknown or the API is missing / errors.
function Game.MapInfo(mapID)
  if type(mapID) ~= "number" then return nil end
  local info = call(C_Map, "GetMapInfo", mapID)
  if type(info) ~= "table" then return nil end
  return { name = info.name, mapType = info.mapType, parentMapID = info.parentMapID }
end

-- C_Map.GetMapChildrenInfo(mapID, nil, true) (every descendant, any type;
-- UiMapDetails) -> { { mapID=, mapType= } }; {} when none, unknown or the API
-- is missing / errors.
function Game.MapChildren(mapID)
  local out = {}
  if type(mapID) ~= "number" then return out end
  local list = call(C_Map, "GetMapChildrenInfo", mapID, nil, true)
  if type(list) ~= "table" then return out end
  for _, child in ipairs(list) do
    if type(child) == "table" and type(child.mapID) == "number" then
      out[#out + 1] = { mapID = child.mapID, mapType = child.mapType }
    end
  end
  return out
end

-- C_EncounterJournal.GetDungeonEntrancesForMap(mapID) (DungeonEntranceMapInfo:
-- areaPoiID, position, name, description, atlasName, journalInstanceID) ->
-- { { journalInstanceID=, name= } } for entrances with a journal instance;
-- {} when none, unknown or the API is missing / errors.
function Game.DungeonEntrances(mapID)
  local out = {}
  if type(mapID) ~= "number" then return out end
  local list = call(C_EncounterJournal, "GetDungeonEntrancesForMap", mapID)
  if type(list) ~= "table" then return out end
  for _, entrance in ipairs(list) do
    if type(entrance) == "table" and type(entrance.journalInstanceID) == "number" then
      out[#out + 1] = { journalInstanceID = entrance.journalInstanceID, name = entrance.name }
    end
  end
  return out
end

-- The UI map of a journal instance's first floor (EJ_GetInstanceInfo's 7th
-- return, dungeonAreaMapID), nil when unknown (0) or the API is missing /
-- errors.
function Game.InstanceUiMap(journalInstanceID)
  if type(journalInstanceID) ~= "number" then return nil end
  local id = select(7, call(_G, "EJ_GetInstanceInfo", journalInstanceID))
  if type(id) == "number" and id ~= 0 then return id end
  return nil
end

-- C_Map.GetMapGroupID(uiMapID): the group of a multi-floor map (every floor
-- of one dungeon shares it), nil for a map without floors or a missing /
-- erroring API.
function Game.MapGroup(uiMapID)
  if type(uiMapID) ~= "number" then return nil end
  local id = call(C_Map, "GetMapGroupID", uiMapID)
  if type(id) == "number" and id ~= 0 then return id end
  return nil
end

-- The journal instance the player is in: GetInstanceInfo's 8th return (the
-- game map ID) through GetInstanceForGameMap, while IsInInstance() says so;
-- nil outside, when unknown or for a missing / erroring API.
function Game.CurrentJournalInstance()
  if not call(_G, "IsInInstance") then return nil end
  local gameMap = select(8, call(_G, "GetInstanceInfo"))
  if type(gameMap) ~= "number" then return nil end
  return Game.InstanceForMap(gameMap)
end

-- C_EncounterJournal.GetInstanceForGameMap(mapID) -> the journal instance
-- the map belongs to, nil for none (0), unknown or a missing / erroring API.
-- mapID is a GAME map ID (GetInstanceInfo's 8th return, a saved instance's
-- ID, JournalInstance.MapID), never a UI map ID: those are other numbers
-- (UI map 554 is Timeless Isle, game map 554 The Mechanar).
function Game.InstanceForMap(mapID)
  if type(mapID) ~= "number" then return nil end
  local id = call(C_EncounterJournal, "GetInstanceForGameMap", mapID)
  if type(id) == "number" and id ~= 0 then return id end
  return nil
end

-- The name of the instance the player is in (GetInstanceInfo's 1st return)
-- while IsInInstance() says so; nil outside, for an empty name or a missing
-- / erroring API. The zone panel's fallback when GetBestMapForUnit has no
-- map inside an instance.
function Game.CurrentInstanceName()
  if not call(_G, "IsInInstance") then return nil end
  local name = call(_G, "GetInstanceInfo")
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- EJ_GetInstanceInfo(journalInstanceID)'s name, nil when empty, unknown or
-- the API is missing / errors. Never called without an ID (that would read
-- the Encounter Journal's selected instance).
function Game.JournalInstanceName(journalInstanceID)
  if type(journalInstanceID) ~= "number" then return nil end
  local name = call(_G, "EJ_GetInstanceInfo", journalInstanceID)
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- The mount's flavor text as the Mount Journal shows it (2nd return of
-- GetMountInfoExtraByID), nil when missing or empty.
function Game.MountDescription(mountID)
  local journal = C_MountJournal
  if not (journal and journal.GetMountInfoExtraByID and mountID) then return nil end
  local description = select(2, journal.GetMountInfoExtraByID(mountID))
  if type(description) == "string" and description ~= "" then return description end
  return nil
end

-- Saved instances this character is locked to:
-- { {name=, instance=<instanceId, return 14>, difficulty=<difficultyId>,
--    bosses={ {name=, killed=bool} }} }. Unlocked (expired) rows are skipped.
-- Rows with a nil instance or difficulty are left out (nothing to match them
-- against) unless includeIncomplete is true (/mtrail dump shows them).
function Game.SavedRows(includeIncomplete)
  local rows = {}
  if not (GetNumSavedInstances and GetSavedInstanceInfo) then return rows end
  for i = 1, GetNumSavedInstances() or 0 do
    local name, _, _, difficulty, locked, _, _, _, _, _, numEncounters, _, _, instanceID = GetSavedInstanceInfo(i)
    if locked and (includeIncomplete or (instanceID ~= nil and difficulty ~= nil)) then
      local bosses = {}
      if GetSavedInstanceEncounterInfo then
        for j = 1, numEncounters or 0 do
          local bossName, _, isKilled = GetSavedInstanceEncounterInfo(i, j)
          if bossName then bosses[#bosses + 1] = { name = bossName, killed = isKilled == true } end
        end
      end
      rows[#rows + 1] = { name = name, instance = instanceID, difficulty = difficulty, bosses = bosses }
    end
  end
  return rows
end

-- Asks the server for fresh saved-instance (UPDATE_INSTANCE_INFO) and
-- dungeon-finder (LFG_UPDATE_RANDOM_INFO) data.
function Game.RequestLockouts()
  if RequestRaidInfo then RequestRaidInfo() end
  if RequestLFDPlayerLockInfo then RequestLFDPlayerLockInfo() end
end

function Game.IsQuestDone(questID)
  local log = C_QuestLog
  if not (log and log.IsQuestFlaggedCompleted and questID) then return false end
  return log.IsQuestFlaggedCompleted(questID) == true
end

-- GetLFGDungeonRewards(dungeonID) -> doneToday, moneyBase, ...
function Game.IsLfgDone(dungeonID)
  if not (GetLFGDungeonRewards and dungeonID) then return false end
  return GetLFGDungeonRewards(dungeonID) == true
end

function Game.UntilDaily()
  local dt = C_DateAndTime
  return (dt and dt.GetSecondsUntilDailyReset and dt.GetSecondsUntilDailyReset()) or 0
end

function Game.UntilWeekly()
  local dt = C_DateAndTime
  return (dt and dt.GetSecondsUntilWeeklyReset and dt.GetSecondsUntilWeeklyReset()) or 0
end

-- Epoch seconds, the clock manual ticks (Logic/Resets.lua) are stored in.
function Game.Now()
  return (GetServerTime and GetServerTime()) or time()
end

-- "Alliance" | "Horde" | "Neutral" (nil or anything else -> "Neutral").
function Game.Faction()
  local faction = UnitFactionGroup and UnitFactionGroup("player")
  if faction == "Alliance" or faction == "Horde" then return faction end
  return "Neutral"
end

-- Calendar -----------------------------------------------------------------------
-- C_Calendar.GetNumDayEvents(monthOffset, monthDay), GetDayEvent(monthOffset,
-- monthDay, index) -> { title, calendarType ("HOLIDAY"), sequenceType,
-- startTime, endTime = CalendarTime { year, month, monthDay, weekday, hour,
-- minute } }, GetMonthInfo(monthOffset) -> { year, month, numDays },
-- GetMaxCreateDate() -> CalendarTime; C_DateAndTime.GetCurrentCalendarTime()
-- -> CalendarTime (Blizzard_APIDocumentationGenerated, 12.1.5). Month offsets
-- are relative to the month the calendar UI shows.

local calendarOpened = false

local function openCalendarOnce(cal)
  if not calendarOpened and cal.OpenCalendar then
    calendarOpened = true
    cal.OpenCalendar()
  end
end

-- Month offset of today's month: the player may have browsed the calendar to
-- another month.
local function todayMonthOffset(cal, today)
  local shown = cal.GetMonthInfo and cal.GetMonthInfo(0)
  if shown and shown.year and shown.month and today.year and today.month then
    return (today.year - shown.year) * 12 + (today.month - shown.month)
  end
  return 0
end

-- {[calendar title] = holidayKey} for Data.Holidays.
local function holidayKeysByTitle()
  local keyByTitle = {}
  for key, holiday in pairs((ns.Data and ns.Data.Holidays) or {}) do
    if holiday.title then keyByTitle[holiday.title] = key end
  end
  return keyByTitle
end

-- {[holidayKey]=true} for every Data.Holidays entry whose title matches a
-- HOLIDAY event on today's calendar. The calendar loads asynchronously:
-- the first call may return {} until CALENDAR_UPDATE_EVENT_LIST fires.
function Game.ActiveHolidays()
  local active = {}
  local cal, dt = C_Calendar, C_DateAndTime
  if not (cal and dt and dt.GetCurrentCalendarTime and cal.GetNumDayEvents and cal.GetDayEvent) then
    return active
  end
  openCalendarOnce(cal)
  local today = dt.GetCurrentCalendarTime()
  if not (today and today.monthDay) then return active end
  local offset = todayMonthOffset(cal, today)
  local keyByTitle = holidayKeysByTitle()
  for i = 1, cal.GetNumDayEvents(offset, today.monthDay) or 0 do
    local event = cal.GetDayEvent(offset, today.monthDay, i)
    if event and event.calendarType == "HOLIDAY" and event.title and keyByTitle[event.title] then
      active[keyByTitle[event.title]] = true
    end
  end
  return active
end

local MONTHS_AHEAD = 12 -- how far the schedule reads (the calendar's own limit is GetMaxCreateDate)
local RUNS_PER_HOLIDAY = 2 -- the one running or next, and the one after (when the first ended today)

local function timeKey(t)
  return table.concat({ tostring(t.year), tostring(t.month), tostring(t.monthDay),
    tostring(t.hour), tostring(t.minute) }, "-")
end

-- {[holidayKey] = { {startTime=, endTime=}, ... }} from today on, the first
-- RUNS_PER_HOLIDAY runs of each holiday in calendar order. A run that spans
-- days shows up on each of them with the same start: counted once. Raises
-- whatever the calendar API raises (HolidaySchedule catches it).
local function scanHolidayRuns(cal, today)
  local keyByTitle = holidayKeysByTitle()
  local wanted = 0
  for _ in pairs(keyByTitle) do wanted = wanted + 1 end
  local runs, complete = {}, 0
  local offset = todayMonthOffset(cal, today)
  local ahead = MONTHS_AHEAD
  local last = cal.GetMaxCreateDate and cal.GetMaxCreateDate() or nil
  if last and last.year and last.month then
    ahead = math.max(0, math.min(ahead, (last.year - today.year) * 12 + (last.month - today.month)))
  end
  for plus = 0, ahead do
    local info = cal.GetMonthInfo(offset + plus)
    local numDays = info and tonumber(info.numDays)
    if numDays then
      for day = (plus == 0) and today.monthDay or 1, numDays do
        for i = 1, cal.GetNumDayEvents(offset + plus, day) or 0 do
          local event = cal.GetDayEvent(offset + plus, day, i)
          local key = event and event.calendarType == "HOLIDAY" and keyByTitle[event.title]
          if key and type(event.startTime) == "table" and type(event.endTime) == "table" then
            local list = runs[key]
            if not list then
              list = {}
              runs[key] = list
            end
            local newest = list[#list]
            if #list < RUNS_PER_HOLIDAY and not (newest and timeKey(newest.startTime) == timeKey(event.startTime)) then
              list[#list + 1] = { startTime = event.startTime, endTime = event.endTime }
              if #list == RUNS_PER_HOLIDAY then complete = complete + 1 end
            end
          end
        end
        if complete == wanted then return runs end
      end
    end
  end
  return runs
end

local scheduleCache
local calendarGeneration = 0

-- CALENDAR_UPDATE_EVENT_LIST: the calendar's contents changed, so
-- HolidaySchedule reads them again.
function Game.CalendarChanged()
  calendarGeneration = calendarGeneration + 1
end

-- { now = <current CalendarTime>, occurrences = { [holidayKey] = { {startTime=,
-- endTime=} } } } for every Data.Holidays entry the calendar lists from today
-- on (see scanHolidayRuns), or nil when the calendar API is missing or
-- errors (Game.ReportError). The calendar is read once per calendar day and
-- again after CalendarChanged. Like ActiveHolidays, the first call may find
-- little until the calendar has loaded.
function Game.HolidaySchedule()
  local cal, dt = C_Calendar, C_DateAndTime
  if not (cal and dt and dt.GetCurrentCalendarTime and cal.GetNumDayEvents and cal.GetDayEvent
    and cal.GetMonthInfo) then
    return nil
  end
  openCalendarOnce(cal)
  local today = dt.GetCurrentCalendarTime()
  if not (today and today.year and today.month and today.monthDay) then return nil end
  local cache = scheduleCache
  local day = today.year .. "-" .. today.month .. "-" .. today.monthDay
  if not (cache and cache.day == day and cache.generation == calendarGeneration) then
    local good, runs = pcall(scanHolidayRuns, cal, today)
    if not good then
      Game.ReportError(runs)
      return nil
    end
    cache = { day = day, generation = calendarGeneration, occurrences = runs }
    scheduleCache = cache
  end
  return { now = today, occurrences = cache.occurrences }
end

-- index: position in Data.Expansions (1 = Classic); the API takes the
-- 0-based expansion level. -> logo fileID or nil.
function Game.ExpansionLogo(index)
  if not (GetExpansionDisplayInfo and index) then return nil end
  local info = GetExpansionDisplayInfo(index - 1)
  return info and info.logo or nil
end

-- "Name-Realm" for this character.
function Game.CharKey()
  local name = UnitName and UnitName("player") or "?"
  local realm = (GetNormalizedRealmName and GetNormalizedRealmName())
    or (GetRealmName and GetRealmName()) or "?"
  return name .. "-" .. realm
end

-- This character's class file ("MAGE") and level, nil when unknown.
function Game.ClassFile()
  if not UnitClass then return nil end
  local _, classFile = UnitClass("player")
  return type(classFile) == "string" and classFile or nil
end

function Game.Level()
  local level = UnitLevel and UnitLevel("player")
  return type(level) == "number" and level or nil
end

-- This character's name (no realm), or nil when unknown.
function Game.PlayerName()
  local name = UnitName and UnitName("player")
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- Achievements ------------------------------------------------------------------

local MAX_CRITERIA = 100

-- True when `flags` has bit `flag` (bit.band in game; arithmetic otherwise).
local function hasFlag(flags, flag)
  flags = tonumber(flags)
  if not (flags and flag and flag > 0) then return false end
  if bit and bit.band then return bit.band(flags, flag) == flag end
  return math.floor(flags / flag) % 2 == 1
end

-- GetAchievementInfo(id): id, name, points, completed, month, day, year,
-- description, flags, icon, rewardText, ... GetAchievementCriteriaInfo(id,
-- i): criteriaString, criteriaType, completed, quantity, reqQuantity,
-- charName, flags, assetID, quantityString, ...
-- -> { id=, name=, description=, completed=, numCriteria=, criteria = {
-- { text=, completed=, quantity=, required=, progressBar= (flags has
-- EVALUATION_TREE_FLAG_PROGRESS_BAR, as the Achievements UI checks),
-- quantityString= } } } (at most 100 criteria read; one that errors is left
-- out), or nil when unknown.
function Game.AchievementInfo(achievementID)
  if not (GetAchievementInfo and achievementID) then return nil end
  local good, id, name, _, completed, _, _, _, description = pcall(GetAchievementInfo, achievementID)
  if not (good and id and type(name) == "string") then return nil end
  local info = { id = id, name = name, description = description, completed = completed == true,
    numCriteria = 0, criteria = {} }
  local n = 0
  if GetAchievementNumCriteria then
    local good2, count = pcall(GetAchievementNumCriteria, achievementID)
    n = good2 and tonumber(count) or 0
  end
  info.numCriteria = n
  if GetAchievementCriteriaInfo then
    local progressFlag = tonumber(EVALUATION_TREE_FLAG_PROGRESS_BAR) or 1
    for i = 1, math.min(n, MAX_CRITERIA) do
      local good3, text, _, done, quantity, required, _, flags, _, quantityString =
        pcall(GetAchievementCriteriaInfo, achievementID, i)
      if good3 then
        info.criteria[#info.criteria + 1] = { text = text, completed = done == true,
          quantity = tonumber(quantity), required = tonumber(required),
          progressBar = hasFlag(flags, progressFlag),
          quantityString = type(quantityString) == "string" and quantityString ~= "" and quantityString or nil }
      end
    end
  end
  return info
end

-- Items -------------------------------------------------------------------------

-- C_Item.IsItemDataCachedByID(itemID) -> true / false; nil when the API is
-- missing, errors (Game.ReportError) or no ID is given (cannot tell).
function Game.ItemCached(itemID)
  local item = C_Item
  if not (itemID and type(item) == "table" and type(item.IsItemDataCachedByID) == "function") then
    return nil
  end
  local good, cached = pcall(item.IsItemDataCachedByID, itemID)
  if not good then
    Game.ReportError(cached)
    return nil
  end
  return cached == true
end

-- Runs fn once the item's data has loaded (Item:CreateFromItemID(itemID)
-- :ContinueOnItemLoad(fn)). -> true when the callback was registered; false
-- without an ID, without the Item mixin, or on an error (Game.ReportError).
function Game.OnItemLoad(itemID, fn)
  if not (itemID and type(fn) == "function" and type(Item) == "table"
    and type(Item.CreateFromItemID) == "function") then
    return false
  end
  local good, err = pcall(function()
    Item:CreateFromItemID(itemID):ContinueOnItemLoad(fn)
  end)
  if not good then Game.ReportError(err) end
  return good
end

-- The achievement's name alone (GetAchievementInfo's 2nd return; no
-- criteria reads, cheap enough for list rows). nil when unknown, empty, the
-- API is missing or errors.
function Game.AchievementName(achievementID)
  if not (achievementID and type(GetAchievementInfo) == "function") then return nil end
  local good, _, name = pcall(GetAchievementInfo, achievementID)
  if good and type(name) == "string" and name ~= "" then return name end
  return nil
end

-- GetStatistic(id) gives this character's statistic as a display string:
-- "--" when never done (-> 0), digits maybe with thousands separators (",",
-- ".", spaces) -> the number. Anything else (money with coin icons, text),
-- a missing API, an error (Game.ReportError) or no ID -> nil.
function Game.Statistic(statisticID)
  if not (statisticID and type(GetStatistic) == "function") then return nil end
  local good, value = pcall(GetStatistic, statisticID)
  if not good then
    Game.ReportError(value)
    return nil
  end
  if type(value) == "number" then return value end
  if type(value) ~= "string" then return nil end
  value = string.gsub(value, "^%s+", "")
  value = string.gsub(value, "%s+$", "")
  if value == "--" then return 0 end
  local digits = string.gsub(string.gsub(value, "\194\160", ""), "[,%.%s]", "")
  if digits == "" or string.find(digits, "%D") then return nil end
  return tonumber(digits)
end

-- True while the player is in combat (InCombatLockdown); false when the API
-- is missing.
function Game.InCombat()
  return type(InCombatLockdown) == "function" and InCombatLockdown() == true
end

-- Opens the achievement UI on `achievementID`: the bootstrap's
-- ShowAchievementFrameForAchievement (12.x), else the older
-- OpenAchievementFrameToAchievement, else load Blizzard_AchievementUI, show
-- AchievementFrame and AchievementFrame_SelectAchievement. -> true when a call
-- went through; errors are caught (Game.ReportError) and give false.
function Game.OpenAchievement(achievementID)
  if not achievementID then return false end
  local function try(fn, ...)
    local good, err = pcall(fn, ...)
    if not good then Game.ReportError(err) end
    return good
  end
  if type(ShowAchievementFrameForAchievement) == "function" then
    return try(ShowAchievementFrameForAchievement, achievementID)
  end
  if type(OpenAchievementFrameToAchievement) == "function" then
    return try(OpenAchievementFrameToAchievement, achievementID)
  end
  if not AchievementFrame then
    local load = (C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if type(load) == "function" then try(load, "Blizzard_AchievementUI") end
  end
  if not (AchievementFrame and type(AchievementFrame_SelectAchievement) == "function") then return false end
  return try(function()
    if not AchievementFrame:IsShown() then
      if type(AchievementFrame_ToggleAchievementFrame) == "function" then
        AchievementFrame_ToggleAchievementFrame()
      else
        ShowUIPanel(AchievementFrame)
      end
    end
    AchievementFrame_SelectAchievement(achievementID)
  end)
end

-- Event rares' live status (F17, Logic/Events.lua) ----------------------------
-- Shapes per Blizzard_APIDocumentationGenerated (AreaPoiInfoDocumentation,
-- ContributionCollectorDocumentation, GarrisonConstantsDocumentation for
-- Enum.ContributionState). Every call is pcall-guarded (`call`); a missing
-- API, an error or an odd value gives nil, never a Lua error.

-- C_AreaPoiInfo.GetAreaPOIForMap(uiMapID) -> its AreaPOI IDs (numbers only),
-- nil when the API is missing, errors or returns no table.
function Game.AreaPOIsForMap(uiMapID)
  if type(uiMapID) ~= "number" then return nil end
  local list = call(C_AreaPoiInfo, "GetAreaPOIForMap", uiMapID)
  if type(list) ~= "table" then return nil end
  local out = {}
  for _, id in ipairs(list) do
    if type(id) == "number" then out[#out + 1] = id end
  end
  return out
end

-- C_AreaPoiInfo.GetAreaPOIInfo(uiMapID, areaPoiID) (AreaPOIInfo) -> { name=,
-- isCurrentEvent= }, nil when it returns nothing (MayReturnNothing), the API
-- is missing or errors.
function Game.AreaPOIInfo(uiMapID, areaPoiID)
  if type(areaPoiID) ~= "number" then return nil end
  local info = call(C_AreaPoiInfo, "GetAreaPOIInfo", uiMapID, areaPoiID)
  if type(info) ~= "table" then return nil end
  return { name = info.name, isCurrentEvent = info.isCurrentEvent }
end

-- C_AreaPoiInfo.GetAreaPOISecondsLeft(areaPoiID) -> seconds until the POI
-- expires, nil when unknown (MayReturnNothing), not positive, or the API is
-- missing / errors.
function Game.AreaPOISecondsLeft(areaPoiID)
  if type(areaPoiID) ~= "number" then return nil end
  local seconds = call(C_AreaPoiInfo, "GetAreaPOISecondsLeft", areaPoiID)
  if type(seconds) == "number" and seconds > 0 then return seconds end
  return nil
end

-- The warfront contributions the map shows this character, read the way
-- Blizzard's map pin does (ContributionCollectorDataProvider): each
-- C_ContributionCollector.GetContributionCollectorsForMap(uiMapID)
-- collector's GetManagedContributionsForCreatureID(collectorCreatureID),
-- then per contribution GetName, GetState (state = Enum.ContributionState,
-- percent = contributionPercentageComplete 0..1, timeOfNextStateChange) and
-- GetContributionAppearance(id, state) (stateName, tooltipUseTimeRemaining).
-- -> { { id=, name=, state=, percent=, seconds= (until the next state
-- change, by GetServerTime), stateName=, useTime= } } ({} when the map has
-- no collector), nil when the API is missing or errors.
function Game.ContributionsForMap(uiMapID)
  if type(uiMapID) ~= "number" then return nil end
  local lib = C_ContributionCollector
  local collectors = call(lib, "GetContributionCollectorsForMap", uiMapID)
  if type(collectors) ~= "table" then return nil end
  local out, seen = {}, {}
  for _, collector in ipairs(collectors) do
    local creature = type(collector) == "table" and collector.collectorCreatureID or nil
    if type(creature) == "number" then
      for _, id in ipairs({ call(lib, "GetManagedContributionsForCreatureID", creature) }) do
        if type(id) == "number" and not seen[id] then
          seen[id] = true
          local row = { id = id }
          local name = call(lib, "GetName", id)
          if type(name) == "string" and name ~= "" then row.name = name end
          local state, percent, nextChange = call(lib, "GetState", id)
          if type(state) == "number" then row.state = state end
          if type(percent) == "number" then row.percent = percent end
          if type(nextChange) == "number" then row.seconds = nextChange - Game.Now() end
          if row.state then
            local appearance = call(lib, "GetContributionAppearance", id, row.state)
            if type(appearance) == "table" then
              if type(appearance.stateName) == "string" then row.stateName = appearance.stateName end
              row.useTime = appearance.tooltipUseTimeRemaining == true
            end
          end
          out[#out + 1] = row
        end
      end
    end
  end
  return out
end

-- Addon messages and chat links (shared lists, UI/Share.lua) ------------------

-- Registers the addon-message prefix -> true when the client took it.
function Game.RegisterAddonPrefix(prefix)
  local chat = C_ChatInfo
  if not (chat and chat.RegisterAddonMessagePrefix) then return false end
  local good, result = pcall(chat.RegisterAddonMessagePrefix, prefix)
  return good and result ~= false
end

-- Whispers `msg` to `target` ("Name-Realm") addon to addon -> true when sent.
-- The game can refuse (throttled, or addon messages blocked in an encounter).
function Game.SendAddonWhisper(prefix, msg, target)
  local chat = C_ChatInfo
  if not (chat and chat.SendAddonMessage and target) then return false end
  local good, result = pcall(chat.SendAddonMessage, prefix, msg, "WHISPER", target)
  if not good then return false end
  -- 11.x+ returns an Enum.SendAddonMessageResult (0 = Success); older a boolean.
  if type(result) == "number" then return result == 0 end
  return result ~= false
end

-- Puts `link` into the chat box: the open one, else a new one.
function Game.InsertChatLink(link)
  local util = ChatFrameUtil
  if util and type(util.InsertLink) == "function" and util.InsertLink(link) then return true end
  if type(ChatEdit_InsertLink) == "function" and ChatEdit_InsertLink(link) then return true end
  if util and type(util.OpenChat) == "function" then
    util.OpenChat(link)
    return true
  end
  if type(ChatFrame_OpenChat) == "function" then
    ChatFrame_OpenChat(link)
    return true
  end
  return false
end

-- Runs `fn(self, event, msg, ...)` on each `event` chat message before it shows
-- (it may return false, msg, ... to change the text) -> true when added.
function Game.AddChatFilter(event, fn)
  local util = ChatFrameUtil
  local add = (util and util.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
  if type(add) ~= "function" then return false end
  return pcall(add, event, fn)
end

-- Whether `value` is a Midnight secret value (unreadable chat text in an
-- encounter): addons must not touch those.
function Game.IsSecret(value)
  return type(issecretvalue) == "function" and issecretvalue(value) == true
end

-- Guides (UI/Guides.lua) ---------------------------------------------------------

-- How many of an item are in the bags (bank and reagent bank not counted).
function Game.ItemCount(itemID)
  local item = C_Item
  local fn = (item and item.GetItemCount) or GetItemCount
  if type(fn) ~= "function" then return 0 end
  local good, n = pcall(fn, itemID)
  return good and type(n) == "number" and n or 0
end

-- An item's name, or nil while the client has not loaded it.
function Game.ItemName(itemID)
  local item = C_Item
  local fn = (item and item.GetItemNameByID) or (GetItemInfo and function(id) return (GetItemInfo(id)) end)
  if type(fn) ~= "function" then return nil end
  local good, name = pcall(fn, itemID)
  return good and type(name) == "string" and name or nil
end

-- A quest's title, or nil when the client does not know it yet.
function Game.QuestName(questID)
  local log = C_QuestLog
  if not (log and log.GetTitleForQuestID) then return nil end
  local good, name = pcall(log.GetTitleForQuestID, questID)
  return good and type(name) == "string" and name ~= "" and name or nil
end

-- An item's link (quality colour and all), or nil while it is not loaded.
function Game.ItemLink(itemID)
  local item = C_Item
  local fn = (item and item.GetItemInfo) or GetItemInfo
  if type(fn) ~= "function" then return nil end
  local good, _, link = pcall(fn, itemID)
  return good and type(link) == "string" and link or nil
end

-- Asks the client to load an item / a quest (GET_ITEM_INFO_RECEIVED /
-- QUEST_DATA_LOAD_RESULT follow).
function Game.RequestItem(itemID)
  local item = C_Item
  if item and item.RequestLoadItemDataByID then pcall(item.RequestLoadItemDataByID, itemID) end
end

function Game.RequestQuest(questID)
  local log = C_QuestLog
  if log and log.RequestLoadQuestByID then pcall(log.RequestLoadQuestByID, questID) end
end

function Game.SpellName(spellID)
  local spell = C_Spell
  local fn = (spell and spell.GetSpellName) or (GetSpellInfo and function(id) return (GetSpellInfo(id)) end)
  if type(fn) ~= "function" then return nil end
  local good, name = pcall(fn, spellID)
  return good and type(name) == "string" and name or nil
end

-- An achievement's link, or nil.
function Game.AchievementLink(achievementID)
  if type(GetAchievementLink) ~= "function" then return nil end
  local good, link = pcall(GetAchievementLink, achievementID)
  return good and type(link) == "string" and link ~= "" and link or nil
end

-- Makes (or updates) the account-wide macro `name` with `body` and puts it on
-- the cursor to drop on an action bar -> true, or false and why ("combat",
-- "full", "error").
function Game.MakeMacro(name, body)
  if type(InCombatLockdown) == "function" and InCombatLockdown() then return false, "combat" end
  if type(CreateMacro) ~= "function" or type(GetMacroIndexByName) ~= "function" then return false, "error" end
  local icon = "INV_MISC_QUESTIONMARK"
  local good, index = pcall(GetMacroIndexByName, name)
  index = good and index or 0
  if index and index > 0 and type(EditMacro) == "function" then
    good = pcall(EditMacro, index, name, icon, body)
  else
    local made
    good, made = pcall(CreateMacro, name, icon, body, false)
    if not good or not made then return false, "full" end
  end
  if not good then return false, "error" end
  if type(PickupMacro) == "function" then pcall(PickupMacro, name) end
  return true
end
