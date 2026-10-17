-- Pure helpers of UI/RouteView.lua and UI/Tabs.lua (route context, steps
-- left, tick boxes, row text, flavour, durations, holiday badge, trading tag),
-- the List opts hooks (UI/List.lua) and the route-boss LockoutStatus fix.
-- The frame code (route view, Holidays/Misc views) is compile-checked only.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/JournalHome.lua",
  "UI/Tabs.lua", "UI/RouteView.lua" }

local NOW = 1000000

-- Loads the addon plus the UI files; `game` overrides ns.Game functions and
-- `data` replaces ns.Data tables.
local function loadUI(game, data)
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  local stubGame = {
    MountInfo = function() return nil end,
    IsOwned = function() return false end,
    Exists = function() return true end,
    Faction = function() return "Horde" end,
    SavedRows = function() return {} end,
    IsQuestDone = function() return false end,
    IsLfgDone = function() return false end,
    ActiveHolidays = function() return {} end,
    Now = function() return NOW end,
    UntilDaily = function() return 3600 end,
    UntilWeekly = function() return 86400 end,
    PlayerName = function() return "Adventurer" end,
  }
  for k, v in pairs(game or {}) do stubGame[k] = v end
  for k, v in pairs(stubGame) do ns.Game[k] = v end
  ns.Data.Lockouts, ns.Data.BossLockouts = {}, {}
  ns.Data.Route = {}
  ns.Data.Holidays = {}
  ns.Data.Mounts = {}
  for k, v in pairs(data or {}) do ns.Data[k] = v end
  return ns
end

local function kill(title, bosses)
  return { title = title, type = "Raid", bosses = bosses }
end

describe("ui route", function()
  it("toc lists Tabs and RouteView right after JournalHome", function()
    local fh = assert(io.open(ROOT .. "/AzerothTrail.toc", "r"))
    local lines = {}
    for line in fh:lines() do
      line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if line ~= "" and not line:find("^#") then lines[#lines + 1] = line end
    end
    fh:close()
    local home
    for i, line in ipairs(lines) do if line == "UI\\JournalHome.lua" then home = i end end
    ok(home, "UI\\JournalHome.lua in toc")
    eq({ lines[home + 1], lines[home + 2] }, { "UI\\Tabs.lua", "UI\\RouteView.lua" })
  end)

  it("loads and exposes the helpers without building any view", function()
    local ns = loadUI()
    for _, name in ipairs({ "RouteContext", "RouteRemaining", "RouteCheck", "RouteToggle",
      "RouteRowLines", "RouteFlavour", "FormatDuration", "HolidayBadge", "TradingTag",
      "HeaderText", "RowSourceText", "RouteBoss" }) do
      eq(type(ns.UI[name]), "function", name)
    end
    eq(ns.UI.frame, nil, "no window until toggled")
  end)

  describe("RouteContext", function()
    it("maps manual specs to manual-done while ticked and manual-open otherwise", function()
      local ns = loadUI(nil, { Lockouts = {
        [12] = { manual = true, reset = "daily" },
        [13] = { manual = true, reset = "weekly" },
        [14] = { manual = true, reset = "daily" },
      } })
      ns.db.char.ticks[12] = NOW + 100
      ns.db.char.ticks[13] = NOW -- expired at exactly now
      local ctx = ns.UI.RouteContext(NOW)
      eq(ctx.stateOf(12), "manual-done")
      eq(ctx.stateOf(13), "manual-open", "expired tick")
      eq(ctx.stateOf(14), "manual-open", "never ticked")
    end)

    it("maps tracked specs to done/open and untracked mounts to open", function()
      local ns = loadUI({ IsQuestDone = function(q) return q == 111 end }, {
        Mounts = { [10] = { name = "Q", quest = 111 }, [11] = { name = "Q2", quest = 222 }, [99] = { name = "x" } },
      })
      local ctx = ns.UI.RouteContext(NOW)
      eq(ctx.stateOf(10), "done")
      eq(ctx.stateOf(11), "open")
      eq(ctx.stateOf(99), "open", "no spec")
    end)

    it("routes BossLockouts bosses to their own spec", function()
      local ns = loadUI({
        SavedRows = function()
          return { { instance = 624, difficulty = 3, bosses = {
            { name = "Koralon the Flame Watcher", killed = true },
            { name = "Archavon the Stone Watcher", killed = false },
          } }, { instance = 624, difficulty = 4, bosses = {
            { name = "Koralon the Flame Watcher", killed = true },
          } } }
        end,
      }, {
        Lockouts = { [286] = { instance = 624, boss = "Archavon the Stone Watcher", difficulties = { 3, 4 }, reset = "weekly" } },
        BossLockouts = { ["Koralon"] = { instance = 624, boss = "Koralon the Flame Watcher", difficulties = { 3, 4 }, reset = "weekly" } },
      })
      local ctx = ns.UI.RouteContext(NOW)
      eq(ctx.stateOf(286, "Koralon"), "done", "Koralon killed on both sizes")
      eq(ctx.stateOf(286, "Archavon"), "open", "no per-boss spec: the mount's own spec")
      eq(ctx.stateOf(286), "open")
    end)

    it("builds holiday steps from ActiveHolidays (only events with mounts), sorted by key", function()
      local ns = loadUI({
        ActiveHolidays = function() return { brewfest = true, darkmoon = true, hallowsend = true } end,
      }, { Holidays = {
        brewfest = { title = "Brewfest", mounts = { 202, 226 }, stepTitle = "Queue for Coren Direbrew (Brewfest)" },
        hallowsend = { title = "Hallow's End", mounts = { 219 }, stepTitle = "Queue for the Headless Horseman (Hallow's End)" },
        loveisintheair = { title = "Love is in the Air", mounts = { 352 }, stepTitle = "Queue for Apothecary Hummel" },
        darkmoon = { title = "Darkmoon Faire", mounts = {} },
      } })
      eq(ns.UI.RouteContext(NOW).holidaySteps, {
        { title = "Queue for Coren Direbrew (Brewfest)", mounts = { 202, 226 } },
        { title = "Queue for the Headless Horseman (Hallow's End)", mounts = { 219 } },
      })
    end)

    it("carries faction, showCompleted and predicates", function()
      local ns = loadUI({ IsOwned = function(id) return id == 5 end })
      ns.db.char.showCompleted = true
      local ctx = ns.UI.RouteContext(NOW)
      eq(ctx.faction, "Horde")
      eq(ctx.showCompleted, true)
      eq(ctx.isOwned(5), true)
      eq(ctx.isOwned(6), false)
      eq(ctx.isQuestDone, ns.Game.IsQuestDone)
      eq(ctx.holidaySteps, {})
      ns.db.char.showCompleted = false
      eq(ns.UI.RouteContext(NOW).showCompleted, false)
    end)

    it("defaults now to Game.Now()", function()
      local ns = loadUI(nil, { Lockouts = { [12] = { manual = true, reset = "daily" } } })
      ns.db.char.ticks[12] = NOW + 1
      eq(ns.UI.RouteContext().stateOf(12), "manual-done")
    end)
  end)

  describe("RouteRemaining", function()
    local route = {
      { title = "Fly somewhere", steps = {
        kill("Saved raid", { { mount = 1, boss = "A" } }),
        kill("Open raid", { { mount = 2, boss = "B" } }),
        kill("Manual rare", { { mount = 3, boss = "C" } }),
        kill("Ticked rare", { { mount = 4, boss = "D" } }),
        kill("Owned", { { mount = 5, boss = "E" } }),
      } },
    }
    local lockouts = {
      [1] = { quest = 1001, reset = "weekly" },
      [2] = { quest = 1002, reset = "weekly" },
      [3] = { manual = true, reset = "daily" },
      [4] = { manual = true, reset = "daily" },
    }

    it("counts kill rows that are not done (owned and done rows excluded)", function()
      local ns = loadUI({
        IsQuestDone = function(q) return q == 1001 end,
        IsOwned = function(id) return id == 5 end,
      }, { Route = route, Lockouts = lockouts })
      ns.db.char.ticks[4] = NOW + 60
      eq(ns.UI.RouteRemaining(NOW), 2, "Open raid + Manual rare")
      ns.db.char.showCompleted = true
      eq(ns.UI.RouteRemaining(NOW), 2, "showCompleted does not change the count")
    end)

    it("counts active holiday steps and drops to zero when all is done", function()
      local ns = loadUI({
        ActiveHolidays = function() return { brewfest = true } end,
        IsQuestDone = function() return true end,
      }, {
        Route = { kill("Done raid", { { mount = 1, boss = "A" } }) },
        Lockouts = { [1] = { quest = 1001, reset = "weekly" }, [202] = { lfg = 287, reset = "daily" } },
        Holidays = { brewfest = { title = "Brewfest", mounts = { 202 }, stepTitle = "Queue for Coren Direbrew (Brewfest)" } },
      })
      eq(ns.UI.RouteRemaining(NOW), 1, "holiday boss open")
      ns.Game.IsLfgDone = function() return true end
      eq(ns.UI.RouteRemaining(NOW), 0)
    end)

    it("runs on the shipped data for both factions", function()
      for _, faction in ipairs({ "Horde", "Alliance" }) do
        reset_ui_stub()
        local files = toc_lua_files()
        for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
        local ns = load_addon(files)
        ns.addon:OnInitialize()
        ns.Game.Faction = function() return faction end
        ns.Game.MountInfo = function() return nil end
        ns.Game.IsOwned = function() return false end
        ns.Game.SavedRows = function() return {} end
        ns.Game.IsQuestDone = function() return false end
        ns.Game.IsLfgDone = function() return false end
        ns.Game.ActiveHolidays = function() return { brewfest = true } end
        local ctx = ns.UI.RouteContext(NOW)
        local rows = ns.Route.Build(ns.Data.Route, ctx)
        ok(#rows > 10, faction .. ": route has rows")
        eq(rows[1].title, "Queue for Coren Direbrew (Brewfest)", faction .. ": holiday boss first")
        local left = ns.UI.RouteRemaining(NOW)
        ok(left > 10, faction .. ": steps left")
        for _, row in ipairs(rows) do
          ns.UI.RouteRowLines(row)
          if row.kind == "kill" then
            local store = {}
            ns.UI.RouteToggle(row, store, NOW, 100, 5000) -- every manual spec has a valid reset
          end
        end
      end
    end)

    it("feeds the minimap tooltip line", function()
      local ns = loadUI(nil, { Route = { kill("Open", { { mount = 2, boss = "B" } }) } })
      fire_frame_event("PLAYER_LOGIN")
      local launcher = ns.UI.launcher
      ok(launcher, "launcher registered")
      local lines = {}
      launcher.OnTooltipShow({ AddLine = function(_, text) lines[#lines + 1] = text end })
      eq(lines[#lines], "Route: 1 steps left")
    end)
  end)

  describe("RouteCheck and RouteToggle", function()
    local function row(bosses, state, auto)
      return { kind = "kill", bosses = bosses, state = state or "open", auto = auto or false }
    end

    it("auto rows are checked, disabled and tagged; open rows unchecked and disabled", function()
      local ns = loadUI()
      eq({ ns.UI.RouteCheck(row({ { mount = 1, state = "done" } }, "done", true)) }, { true, false, true })
      eq({ ns.UI.RouteCheck(row({ { mount = 1, state = "open" } })) }, { false, false, false })
      eq(ns.UI.RouteCheck({ kind = "travel", bosses = {} }), nil, "travel rows have no box")
    end)

    it("manual rows are enabled and checked only when every manual boss is ticked", function()
      local ns = loadUI()
      eq({ ns.UI.RouteCheck(row({ { mount = 1, state = "manual-open" } }, "manual")) }, { false, true, false })
      eq({ ns.UI.RouteCheck(row({ { mount = 1, state = "manual-done" }, { mount = 2, state = "manual-open" } }, "manual")) },
        { false, true, false })
      eq({ ns.UI.RouteCheck(row({ { mount = 1, state = "manual-done" }, { mount = 2, state = "open" } }, "open")) },
        { true, true, false })
    end)

    it("an auto + manual mix is clickable and never tagged auto", function()
      local ns = loadUI()
      eq({ ns.UI.RouteCheck(row({ { mount = 1, state = "done" }, { mount = 2, state = "manual-done" } }, "done", true)) },
        { true, true, false })
      eq({ ns.UI.RouteCheck(row({ { mount = 1, state = "done" }, { mount = 2, state = "manual-open" } }, "manual", false)) },
        { false, true, false })
    end)

    it("ticks every manual boss with its spec's reset, then unticks them", function()
      local ns = loadUI(nil, {
        Lockouts = { [1] = { manual = true, reset = "daily" }, [3] = { quest = 9, reset = "weekly" } },
        BossLockouts = { ["Weekly Rare"] = { manual = true, reset = "weekly" } },
      })
      local store = {}
      local r = row({
        { mount = 1, boss = "Daily Rare", state = "manual-open" },
        { mount = 2, boss = "Weekly Rare", state = "manual-open" },
        { mount = 3, boss = "Quest Boss", state = "open" },
      }, "manual")
      eq(ns.UI.RouteToggle(r, store, NOW, 100, 5000), true)
      eq(store, { [1] = NOW + 100, [2] = NOW + 5000 })

      r.bosses[1].state, r.bosses[2].state = "manual-done", "manual-done"
      eq(ns.UI.RouteToggle(r, store, NOW, 100, 5000), true)
      eq(store, {})
    end)

    it("does nothing on rows without manual bosses", function()
      local ns = loadUI()
      local store = { [9] = 1 }
      eq(ns.UI.RouteToggle(row({ { mount = 1, state = "done" } }, "done", true), store, NOW, 1, 2), false)
      eq(store, { [9] = 1 })
    end)

    it("round-trips through RouteContext: a ticked row reads manual-done", function()
      local ns = loadUI(nil, {
        Route = { kill("Rare", { { mount = 3, boss = "C" } }) },
        Lockouts = { [3] = { manual = true, reset = "daily" } },
      })
      local rows = ns.Route.Build(ns.Data.Route, ns.UI.RouteContext(NOW))
      eq(rows[1].bosses[1].state, "manual-open")
      ns.UI.RouteToggle(rows[1], ns.db.char.ticks, NOW, 100, 5000)
      eq(ns.UI.RouteRemaining(NOW), 0)
      ns.db.char.showCompleted = true
      rows = ns.Route.Build(ns.Data.Route, ns.UI.RouteContext(NOW))
      eq(rows[1].state, "done")
      eq({ ns.UI.RouteCheck(rows[1]) }, { true, true, false }, "still clickable to untick")
      eq(ns.UI.RouteRemaining(NOW + 100), 1, "gone after the daily reset")
    end)
  end)

  describe("RouteRowLines", function()
    it("shows boss -> mount, notes in grey and locked text in grey", function()
      local ns = loadUI({ MountInfo = function(id) if id == 1 then return "Client Mount" end end },
        { Mounts = { [2] = { name = "Data Mount" } } })
      local title, lines = ns.UI.RouteRowLines({
        kind = "kill", title = "Run X", notes = "Heroic only",
        bosses = {
          { mount = 1, boss = "Boss One", note = "no watchers" },
          { mount = 2, boss = "Boss Two", locked = true, lockedText = "Garrison needed" },
          { mount = 3 },
        },
      })
      eq(title, "Run X")
      eq(lines, {
        "Boss One → Client Mount  |cff808080no watchers|r",
        "Boss Two → Data Mount  |cff808080(Garrison needed)|r",
        "3",
        "|cff808080Heroic only|r",
      })
    end)

    it("travel rows show only their notes", function()
      local ns = loadUI()
      local title, lines = ns.UI.RouteRowLines({ kind = "travel", title = "Portal to Uldum", bosses = {} })
      eq(title, "Portal to Uldum")
      eq(lines, {})
    end)
  end)

  describe("flavour and durations", function()
    it("uses the brief's lines", function()
      local ns = loadUI()
      eq(ns.UI.RouteFlavour(37, "Adventurer"), "You have 37 lockouts left. Saddle up?")
      eq(ns.UI.RouteFlavour(0, "Adventurer"), "Adventurer has reached Oregon. Nothing left to farm until reset.")
      eq(ns.UI.RouteFlavour(0, nil), "Your party has reached Oregon. Nothing left to farm until reset.")
    end)

    it("formats with SecondsToTime when present, else a fallback", function()
      local ns = loadUI()
      local old = SecondsToTime
      SecondsToTime = nil
      eq(ns.UI.FormatDuration(2 * 86400 + 3 * 3600 + 4 * 60 + 5), "2d 3h 4m")
      eq(ns.UI.FormatDuration(3 * 3600 + 60), "3h 1m")
      eq(ns.UI.FormatDuration(59), "0m")
      eq(ns.UI.FormatDuration(nil), "0m")
      local got
      SecondsToTime = function(s, noSeconds) got = { s, noSeconds }; return "3 Hr 1 Min" end
      eq(ns.UI.FormatDuration(3 * 3600 + 60.7), "3 Hr 1 Min")
      eq(got, { 10860, true })
      SecondsToTime = old
    end)
  end)

  describe("List opts hooks", function()
    it("ListRows adds header badges and row tags from opts", function()
      local ns = loadUI(nil, { Holidays = { brewfest = { title = "Brewfest" }, darkmoon = { title = "Darkmoon Faire" } } })
      local a, b, c = { section = "brewfest" }, { section = "darkmoon", tradingNow = true }, { section = "darkmoon" }
      local active = { brewfest = true }
      local rows = ns.UI.ListRows({ { id = 1, m = a }, { id = 2, m = b }, { id = 3, m = c } }, nil, {
        headerSuffix = function(section) return ns.UI.HolidayBadge(section, active) end,
        rowTag = ns.UI.TradingTag,
      })
      eq(rows, {
        { header = true, section = "brewfest", text = "Brewfest", badge = "Active now" },
        { id = 1, m = a, owned = false },
        { header = true, section = "darkmoon", text = "Darkmoon Faire" },
        { id = 2, m = b, owned = false, tag = "Trading Post — this month" },
        { id = 3, m = c, owned = false },
      })
    end)

    it("HeaderText and RowSourceText paint the badge and tag in green", function()
      local ns = loadUI(nil, { Mounts = { [7] = { name = "x", group = "Trading Post: October" }, [8] = { name = "y" } } })
      eq(ns.UI.HeaderText({ text = "Brewfest", badge = "Active now" }), "Brewfest  |cff33ff99Active now|r")
      eq(ns.UI.HeaderText({ text = "Shop" }), "Shop")
      eq(ns.UI.RowSourceText({ id = 7, tag = "Trading Post — this month" }),
        "Trading Post: October · |cff33ff99Trading Post — this month|r")
      eq(ns.UI.RowSourceText({ id = 8, tag = "T" }), "|cff33ff99T|r")
      eq(ns.UI.RowSourceText({ id = 7 }), "Trading Post: October")
    end)

    it("HolidayBadge and TradingTag", function()
      local ns = loadUI()
      eq(ns.UI.HolidayBadge("brewfest", { brewfest = true }), "Active now")
      eq(ns.UI.HolidayBadge("hallowsend", { brewfest = true }), nil)
      eq(ns.UI.HolidayBadge("brewfest", nil), nil)
      eq(ns.UI.TradingTag(1, { tradingNow = true }), "Trading Post — this month")
      eq(ns.UI.TradingTag(1, {}), nil)
      eq(ns.UI.TradingTag(1, nil), nil)
    end)
  end)

  describe("LockoutStatus with route bosses", function()
    local route = {
      kill("Vault of Archavon", {
        { mount = 286, boss = "Koralon", alliance = true },
        { mount = 286, boss = "Archavon" },
      }),
      kill("Dawn of the Infinites", { { mount = 781, boss = "Chrono-Lord Deios" } }),
    }

    it("uses the first route boss's BossLockouts spec", function()
      local ns = loadUI({
        SavedRows = function()
          return { { instance = 624, difficulty = 3, bosses = { { name = "Koralon the Flame Watcher", killed = true } } },
                   { instance = 624, difficulty = 4, bosses = { { name = "Koralon the Flame Watcher", killed = true } } },
                   { instance = 2579, difficulty = 23, bosses = { { name = "Chrono-Lord Deios", killed = true } } } }
        end,
      }, {
        Route = route,
        Lockouts = {
          [286] = { instance = 624, boss = "Archavon the Stone Watcher", difficulties = { 3, 4 }, reset = "weekly" },
          [781] = { manual = true, reset = "daily" },
        },
        BossLockouts = {
          ["Koralon"] = { instance = 624, boss = "Koralon the Flame Watcher", difficulties = { 3, 4 }, reset = "weekly" },
          ["Chrono-Lord Deios"] = { instance = 2579, boss = "Chrono-Lord Deios", difficulties = { 23 }, reset = "weekly" },
        },
      })
      eq(ns.UI.RouteBoss(286), "Koralon")
      eq(ns.UI.LockoutStatus(286), "saved", "Koralon spec, not Archavon's")
      eq(ns.UI.LockoutStatus(781), "saved", "Deios spec instead of manual")
    end)
  end)
end)
