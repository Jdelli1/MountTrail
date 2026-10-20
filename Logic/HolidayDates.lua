local ADDON, ns = ...

-- Dates for the Holidays tab's section headers: "Active · ends in 6d" for a
-- running holiday, "Starts in 9d" / "Starts Feb 9" for the next one. Pure Lua,
-- no WoW API: Game.HolidaySchedule hands over the calendar's CalendarTime
-- tables ({year, month, monthDay, hour, minute}; one calendar, one clock).
local L = ns.L

local HolidayDates = {}
ns.HolidayDates = HolidayDates

local MINUTES_PER_DAY = 1440
-- Further away than this, "Starts in 142d" is hard to read: show the date.
local RELATIVE_DAYS = 30

local MONTHS = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }

-- Days since 1970-01-01 of a proleptic Gregorian date (Hinnant's days_from_civil).
local function daysFromCivil(year, month, day)
  if month <= 2 then year = year - 1 end
  local era = math.floor(year / 400)
  local yearOfEra = year - era * 400
  local dayOfYear = math.floor((153 * ((month + 9) % 12) + 2) / 5) + day - 1
  local dayOfEra = yearOfEra * 365 + math.floor(yearOfEra / 4) - math.floor(yearOfEra / 100) + dayOfYear
  return era * 146097 + dayOfEra - 719468
end

-- CalendarTime -> minutes since 1970-01-01 00:00 on the calendar's own clock
-- (no time zone: only differences between two calendar times mean anything),
-- nil when it is not one. A missing hour or minute counts as 0.
function HolidayDates.Minutes(calendarTime)
  if type(calendarTime) ~= "table" then return nil end
  local year, month, day = calendarTime.year, calendarTime.month, calendarTime.monthDay
  if not (type(year) == "number" and type(month) == "number" and type(day) == "number") then return nil end
  local hour, minute = tonumber(calendarTime.hour) or 0, tonumber(calendarTime.minute) or 0
  return daysFromCivil(year, month, day) * MINUTES_PER_DAY + hour * 60 + minute
end

-- occurrences: { {startTime=, endTime=} } in calendar order; now: CalendarTime.
-- -> { state = "active", minutes = <until it ends> } for one that is running,
-- { state = "upcoming", minutes = <until it starts>, startTime = } for the
-- first one still to come, nil when there is none (or no usable clock).
-- Occurrences that already ended are skipped.
function HolidayDates.Next(occurrences, now)
  local current = HolidayDates.Minutes(now)
  if not (current and type(occurrences) == "table") then return nil end
  for _, occurrence in ipairs(occurrences) do
    local from = HolidayDates.Minutes(occurrence.startTime)
    local to = HolidayDates.Minutes(occurrence.endTime)
    if from and to then
      if current < from then
        return { state = "upcoming", minutes = from - current, startTime = occurrence.startTime }
      elseif current < to then
        return { state = "active", minutes = to - current }
      end
    end
  end
  return nil
end

-- Minutes -> "6d" (whole days), "5h" (whole hours) or "<1h".
function HolidayDates.Span(minutes)
  minutes = math.max(0, math.floor(tonumber(minutes) or 0))
  local days = math.floor(minutes / MINUTES_PER_DAY)
  if days >= 1 then return string.format(L["%dd"], days) end
  local hours = math.floor(minutes / 60)
  if hours >= 1 then return string.format(L["%dh"], hours) end
  return L["<1h"]
end

-- Next()'s result -> badge text, muted (true for a holiday still to come, so
-- the header does not look like a running one). nil when there is nothing to
-- say.
function HolidayDates.Label(nxt)
  if type(nxt) ~= "table" then return nil end
  if nxt.state == "active" then
    return string.format(L["Active · ends in %s"], HolidayDates.Span(nxt.minutes)), false
  end
  if nxt.state ~= "upcoming" then return nil end
  if (tonumber(nxt.minutes) or 0) <= RELATIVE_DAYS * MINUTES_PER_DAY then
    return string.format(L["Starts in %s"], HolidayDates.Span(nxt.minutes)), true
  end
  local start = nxt.startTime
  local month = type(start) == "table" and MONTHS[start.month] or nil
  if not (month and start.monthDay) then return nil end
  return string.format(L["Starts %s %d"], L[month], start.monthDay), true
end

-- The header badge of a holiday: isActive = the calendar lists it on today's
-- date (Game.ActiveHolidays), occurrences = its Game.HolidaySchedule list,
-- now = the calendar's current time. -> text, muted.
--   * active: "Active · ends in 6d"; plain "Active now" when the schedule has
--     no running window for it (not loaded yet, or it only starts later today);
--   * not active: "Starts in 9d" / "Starts Feb 9" for the next occurrence,
--     nothing when there is none.
function HolidayDates.Badge(isActive, occurrences, now)
  local nxt = HolidayDates.Next(occurrences, now)
  if isActive then
    if nxt and nxt.state == "active" then return HolidayDates.Label(nxt) end
    return L["Active now"], false
  end
  if nxt and nxt.state == "upcoming" then return HolidayDates.Label(nxt) end
  return nil
end
