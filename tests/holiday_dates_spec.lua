-- Logic/HolidayDates.lua: the Holidays tab's header dates from calendar times
-- (C_Calendar day events carry CalendarTime start/end; the times of one
-- calendar are compared on a zone-free minute scale).

describe("HolidayDates", function()
  local function load() return load_addon({ "Core/Locale.lua", "Logic/HolidayDates.lua" }).HolidayDates end

  local DAY = 1440
  local function ct(year, month, monthDay, hour, minute)
    return { year = year, month = month, monthDay = monthDay, hour = hour or 0, minute = minute or 0, weekday = 1 }
  end

  describe("Minutes", function()
    it("counts from 1970-01-01 00:00", function()
      eq(load().Minutes(ct(1970, 1, 1, 0, 0)), 0)
      eq(load().Minutes(ct(1970, 1, 2, 1, 30)), DAY + 90)
    end)

    it("differences are exact across month, year and leap-day boundaries", function()
      local M = load().Minutes
      eq(M(ct(2026, 10, 19, 12, 30)) - M(ct(2026, 10, 19, 12, 0)), 30)
      eq(M(ct(2026, 11, 1)) - M(ct(2026, 10, 31)), DAY)
      eq(M(ct(2027, 1, 2)) - M(ct(2026, 12, 30)), 3 * DAY)
      eq(M(ct(2028, 3, 1)) - M(ct(2028, 2, 28)), 2 * DAY, "2028 is a leap year")
      eq(M(ct(2026, 3, 1)) - M(ct(2026, 2, 28)), DAY)
      eq(M(ct(2100, 3, 1)) - M(ct(2100, 2, 28)), DAY, "2100 is not a leap year")
      eq(M(ct(2000, 3, 1)) - M(ct(2000, 2, 28)), 2 * DAY, "2000 is a leap year")
    end)

    it("is nil for anything that is not a calendar time", function()
      local M = load().Minutes
      eq(M(nil), nil)
      eq(M("2026-10-19"), nil)
      eq(M({ year = 2026, month = 10 }), nil)
      eq(M({ year = 2026, month = "10", monthDay = 19 }), nil)
    end)

    it("takes a missing hour or minute as 0", function()
      local M = load().Minutes
      eq(M({ year = 2026, month = 10, monthDay = 19 }), M(ct(2026, 10, 19, 0, 0)))
    end)
  end)

  describe("Next", function()
    local NOW = ct(2026, 10, 19, 12, 0)
    local function occ(s, e) return { startTime = s, endTime = e } end

    it("an occurrence that has begun and not ended is active, with the minutes left", function()
      local nxt = load().Next({ occ(ct(2026, 10, 18, 0, 0), ct(2026, 10, 25, 15, 0)) }, NOW)
      eq(nxt.state, "active")
      eq(nxt.minutes, 6 * DAY + 3 * 60)
    end)

    it("an occurrence still to come is upcoming, with the minutes to go and its start", function()
      local start = ct(2026, 10, 28, 12, 0)
      local nxt = load().Next({ occ(start, ct(2026, 11, 2, 0, 0)) }, NOW)
      eq(nxt.state, "upcoming")
      eq(nxt.minutes, 9 * DAY)
      eq(nxt.startTime, start)
    end)

    it("begins at the start minute and is over at the end minute", function()
      local N = load().Next
      local list = { occ(ct(2026, 10, 19, 12, 0), ct(2026, 10, 20, 12, 0)) }
      eq(N(list, ct(2026, 10, 19, 12, 0)).state, "active")
      eq(N(list, ct(2026, 10, 19, 11, 59)).state, "upcoming")
      eq(N(list, ct(2026, 10, 20, 12, 0)), nil)
    end)

    it("skips an occurrence that already ended and takes the next one", function()
      local nxt = load().Next({
        occ(ct(2026, 10, 10, 0, 0), ct(2026, 10, 19, 6, 0)),
        occ(ct(2027, 10, 18, 0, 0), ct(2027, 11, 1, 0, 0)),
      }, NOW)
      eq(nxt.state, "upcoming")
      eq(nxt.startTime, ct(2027, 10, 18, 0, 0))
    end)

    it("skips malformed occurrences and gives nil when nothing is left", function()
      local N = load().Next
      eq(N(nil, NOW), nil)
      eq(N({}, NOW), nil)
      eq(N({ occ(nil, nil), occ({ year = 2026 }, ct(2026, 11, 1)) }, NOW), nil)
      eq(N({ occ(ct(2026, 10, 1), ct(2026, 10, 2)) }, NOW), nil, "only an ended one")
      eq(N({ occ(ct(2026, 10, 25), ct(2026, 10, 26)) }, nil), nil, "no clock")
      eq(N({ occ(ct(2026, 10, 25), ct(2026, 10, 26)) }, "now"), nil)
    end)
  end)

  describe("Span", function()
    it("whole days, else whole hours, else under an hour", function()
      local S = load().Span
      eq(S(6 * DAY + 3 * 60), "6d")
      eq(S(DAY), "1d")
      eq(S(DAY - 1), "23h")
      eq(S(5 * 60 + 30), "5h")
      eq(S(60), "1h")
      eq(S(59), "<1h")
      eq(S(0), "<1h")
    end)
  end)

  describe("Label", function()
    it("a running holiday reads Active · ends in <span>, not muted", function()
      local text, muted = load().Label({ state = "active", minutes = 6 * DAY + 180 })
      eq(text, "Active · ends in 6d")
      eq(muted, false)
      eq((load().Label({ state = "active", minutes = 330 })), "Active · ends in 5h")
      eq((load().Label({ state = "active", minutes = 40 })), "Active · ends in <1h")
    end)

    it("an upcoming holiday within 30 days reads Starts in <span>, muted", function()
      local text, muted = load().Label({ state = "upcoming", minutes = 9 * DAY, startTime = ct(2026, 10, 28) })
      eq(text, "Starts in 9d")
      eq(muted, true)
      eq((load().Label({ state = "upcoming", minutes = 3 * 60, startTime = ct(2026, 10, 19, 15) })), "Starts in 3h")
      eq((load().Label({ state = "upcoming", minutes = 30 * DAY, startTime = ct(2026, 11, 18) })), "Starts in 30d")
    end)

    it("a holiday further away reads Starts <Mon> <day>", function()
      local L = load().Label
      eq((L({ state = "upcoming", minutes = 30 * DAY + 1, startTime = ct(2026, 11, 18, 0, 1) })), "Starts Nov 18")
      eq((L({ state = "upcoming", minutes = 120 * DAY, startTime = ct(2027, 2, 9) })), "Starts Feb 9")
      eq((L({ state = "upcoming", minutes = 300 * DAY, startTime = ct(2027, 12, 16) })), "Starts Dec 16")
    end)

    it("gives nil for nothing, an unknown state or an upcoming holiday without a start", function()
      local L = load().Label
      eq(L(nil), nil)
      eq(L({ state = "over", minutes = 5 }), nil)
      eq(L({ state = "upcoming", minutes = 90 * DAY }), nil, "too far for a span and no date to show")
    end)
  end)

  describe("Badge", function()
    local NOW = ct(2026, 10, 19, 12, 0)
    local RUNNING = { { startTime = ct(2026, 10, 18), endTime = ct(2026, 10, 25, 15, 0) } }
    local COMING = { { startTime = ct(2026, 10, 28, 12, 0), endTime = ct(2026, 11, 2) } }

    it("an active holiday with dates shows how long it runs", function()
      eq((load().Badge(true, RUNNING, NOW)), "Active · ends in 6d")
    end)

    it("an active holiday without a usable window keeps the plain Active now", function()
      local B = load().Badge
      eq((B(true, nil, NOW)), "Active now")
      eq((B(true, RUNNING, nil)), "Active now")
      eq((B(true, COMING, NOW)), "Active now", "the calendar day has it but it starts later today")
      local text, muted = B(true, nil, NOW)
      eq(muted, false)
    end)

    it("a holiday that is not active shows when it starts, muted", function()
      local text, muted = load().Badge(false, COMING, NOW)
      eq(text, "Starts in 9d")
      eq(muted, true)
    end)

    it("a holiday that is not active and has no coming date shows nothing", function()
      local B = load().Badge
      eq(B(false, nil, NOW), nil)
      eq(B(false, {}, NOW), nil)
      eq(B(false, RUNNING, NOW), nil, "the calendar says active, the active set says not: leave it")
      eq(B(nil, COMING, nil), nil)
    end)
  end)
end)
