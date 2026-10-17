local ADDON, ns = ...

-- Holidays, Achievements, Timewalking and Misc tabs: the shared mount list
-- (UI/List.lua) on the matching Journal.Select view (Journal.ViewOf: the
-- Achievements view takes the misc achievement section, grouped by
-- expansion; Timewalking takes the holiday timewalking section; Holidays and
-- Misc keep the rest of their data tabs). Holiday sections on the calendar
-- now come first, with green header text and an "Active now" badge; Trading Post
-- mounts in this month's rotation get a "Trading Post — this month" tag.
-- The two hooks are pure (UI.HolidayBadge, UI.TradingTag) and unit-tested;
-- the views are compile-checked only.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

-- active: {[holidayKey]=true} (Game.ActiveHolidays) -> badge text or nil.
function UI.HolidayBadge(section, active)
  if active and active[section] then return L["Active now"] end
  return nil
end

-- Misc row tag: Trading Post mounts in the current rotation.
function UI.TradingTag(_, m)
  if m and m.tradingNow then return L["Trading Post — this month"] end
  return nil
end

-- Holidays -------------------------------------------------------------------------

local holidayList
local activeNow = {}

UI.RegisterView("holidays", {
  Build = function(parent)
    holidayList = UI.List(parent, function()
      -- Read the calendar once per refresh; headerSuffix runs per header.
      -- Active holidays are pinned to the top (Journal.Select's pin) with
      -- green header text.
      activeNow = ns.Game.ActiveHolidays() or {}
      return { view = "holidays", pin = activeNow }
    end, {
      headerSuffix = function(section) return UI.HolidayBadge(section, activeNow) end,
      headerActive = function(section) return activeNow[section] == true end,
    })
  end,
  Refresh = function()
    if holidayList then holidayList:Refresh() end
  end,
})

-- Achievements: achievement-reward mounts grouped by expansion ---------------------

local achievementList

UI.RegisterView("achievements", {
  Build = function(parent)
    achievementList = UI.List(parent, function()
      return { view = "achievements" }
    end)
  end,
  Refresh = function()
    -- Opening the tab starts the mount -> achievement scan (spread over
    -- frames, never in combat), so hovers are ready sooner.
    if ns.AchievementScan then ns.AchievementScan.Ensure() end
    if achievementList then achievementList:Refresh() end
  end,
})

-- Rows describe achievement mounts by the scan's achievement name when the
-- source text has none (UI.RowDescription): redraw the visible view once the
-- scan finishes.
if ns.AchievementScan then
  ns.AchievementScan.OnDone(function() ns.Refresh() end)
end

-- Timewalking -----------------------------------------------------------------------

local timewalkingList

UI.RegisterView("timewalking", {
  Build = function(parent)
    timewalkingList = UI.List(parent, function()
      return { view = "timewalking" }
    end)
  end,
  Refresh = function()
    if timewalkingList then timewalkingList:Refresh() end
  end,
})

-- Misc -------------------------------------------------------------------------------

local miscList

UI.RegisterView("misc", {
  Build = function(parent)
    miscList = UI.List(parent, function()
      return { view = "misc" }
    end, { rowTag = UI.TradingTag })
  end,
  Refresh = function()
    if miscList then miscList:Refresh() end
  end,
})
