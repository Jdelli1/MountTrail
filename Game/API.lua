local ADDON, ns = ...

-- The only place AzerothTrail calls the WoW API. Every global is looked up at
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
-- calls) are dropped silently unless `/azt debug` is on
-- (ns.db.global.debug): then they go to geterrorhandler(), prefixed
-- "AzerothTrail: ". -> true when the error was handed to the handler. Never
-- raises.
function Game.ReportError(err)
  local db = ns.db
  if not (db and db.global and db.global.debug == true) then return false end
  if type(geterrorhandler) ~= "function" then return false end
  local good, handler = pcall(geterrorhandler)
  if not (good and type(handler) == "function") then return false end
  return (pcall(handler, "AzerothTrail: " .. tostring(err)))
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
-- against) unless includeIncomplete is true (/azt dump shows them).
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

local calendarOpened = false

-- {[holidayKey]=true} for every Data.Holidays entry whose title matches a
-- HOLIDAY event on today's calendar. The calendar loads asynchronously:
-- the first call may return {} until CALENDAR_UPDATE_EVENT_LIST fires.
function Game.ActiveHolidays()
  local active = {}
  local cal, dt = C_Calendar, C_DateAndTime
  if not (cal and dt and dt.GetCurrentCalendarTime and cal.GetNumDayEvents and cal.GetDayEvent) then
    return active
  end
  if not calendarOpened and cal.OpenCalendar then
    calendarOpened = true
    cal.OpenCalendar()
  end
  local today = dt.GetCurrentCalendarTime()
  if not (today and today.monthDay) then return active end
  -- Month offsets are relative to the month the calendar UI shows; work out
  -- where today's month is in case the player browsed to another month.
  local offset = 0
  local shown = cal.GetMonthInfo and cal.GetMonthInfo(0)
  if shown and shown.year and shown.month and today.year and today.month then
    offset = (today.year - shown.year) * 12 + (today.month - shown.month)
  end
  local keyByTitle = {}
  for key, holiday in pairs((ns.Data and ns.Data.Holidays) or {}) do
    if holiday.title then keyByTitle[holiday.title] = key end
  end
  for i = 1, cal.GetNumDayEvents(offset, today.monthDay) or 0 do
    local event = cal.GetDayEvent(offset, today.monthDay, i)
    if event and event.calendarType == "HOLIDAY" and event.title and keyByTitle[event.title] then
      active[keyByTitle[event.title]] = true
    end
  end
  return active
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

-- This character's name (no realm), or nil when unknown.
function Game.PlayerName()
  local name = UnitName and UnitName("player")
  if type(name) == "string" and name ~= "" then return name end
  return nil
end
