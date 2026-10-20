-- Pure helpers of UI/LockoutHelpers.lua and UI/Tabs.lua (route context, tick
-- boxes, row text, flavour, durations, the parked arrow's route rows, holiday
-- badge, trading tag), the List opts hooks (UI/List.lua) and the route-boss
-- LockoutStatus fix. The frame code (Checklist, Holidays/Misc views) is built
-- in tests/ui_build_spec.lua.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/JournalHome.lua",
  "UI/Tabs.lua", "UI/LockoutHelpers.lua" }

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

-- Kill rows of this character's route (Route.Build over UI.RouteContext)
-- not done yet; `showCompleted` lists done rows too.
local function routeRows(ns, now, showCompleted)
  local ctx = ns.UI.RouteContext(now)
  ctx.showCompleted = showCompleted == true
  return ns.Route.Build(ns.Data.Route, ctx)
end

local function left(ns, now)
  local n = 0
  for _, row in ipairs(routeRows(ns, now)) do
    if row.kind == "kill" and row.state ~= "done" then n = n + 1 end
  end
  return n
end

describe("ui route", function()
  it("toc lists Tabs and LockoutHelpers right after JournalHome", function()
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
    eq({ lines[home + 1], lines[home + 2] }, { "UI\\Tabs.lua", "UI\\LockoutHelpers.lua" })
  end)

  it("loads and exposes the helpers without building any view", function()
    local ns = loadUI()
    for _, name in ipairs({ "RouteContext", "RouteCheck", "RouteToggle", "RouteTickKey", "RouteTargetMount",
      "RouteNextStep", "RouteRowLines", "RouteFlavour", "FormatDuration", "HolidayBadge", "TradingTag",
      "HeaderText", "RowSourceText", "RouteBoss" }) do
      eq(type(ns.UI[name]), "function", name)
    end
    eq(ns.UI.RouteRemaining, nil, "the route count is retired (F16)")
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

    it("carries faction and predicates; never lists done rows (Show completed is retired)", function()
      local ns = loadUI({ IsOwned = function(id) return id == 5 end })
      ns.db.char.showCompleted = true -- a leftover saved value
      local ctx = ns.UI.RouteContext(NOW)
      eq(ctx.faction, "Horde")
      eq(ctx.showCompleted, false)
      eq(ctx.isOwned(5), true)
      eq(ctx.isOwned(6), false)
      eq(ctx.isQuestDone, ns.Game.IsQuestDone)
      eq(ctx.holidaySteps, {})
    end)

    it("defaults now to Game.Now()", function()
      local ns = loadUI(nil, { Lockouts = { [12] = { manual = true, reset = "daily" } } })
      ns.db.char.ticks[12] = NOW + 1
      eq(ns.UI.RouteContext().stateOf(12), "manual-done")
    end)
  end)

  describe("route rows (the parked arrow's steps)", function()
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
      eq(left(ns, NOW), 2, "Open raid + Manual rare")
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
      eq(left(ns, NOW), 1, "holiday boss open")
      ns.Game.IsLfgDone = function() return true end
      eq(left(ns, NOW), 0)
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
        ok(left(ns, NOW) > 10, faction .. ": steps left")
        for _, row in ipairs(rows) do
          ns.UI.RouteRowLines(row)
          if row.kind == "kill" then
            local store = {}
            ns.UI.RouteToggle(row, store, NOW, 100, 5000) -- every manual spec has a valid reset
          end
        end
      end
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

    it("ticks every manual boss with its spec's reset, then unticks them; game-tracked bosses are left alone", function()
      local ns = loadUI(nil, {
        Lockouts = { [1] = { manual = true, reset = "daily" }, [3] = { quest = 9, reset = "weekly" } },
        BossLockouts = { ["Weekly Rare"] = { manual = true, reset = "weekly" } },
      })
      local store = {}
      local r = row({
        { mount = 1, boss = "Daily Rare", state = "manual-open" },
        { mount = 2, boss = "Weekly Rare", state = "manual-open" },
        { mount = 3, boss = "Quest Boss", state = "open" },
        { mount = 4, boss = "Untracked", state = "open" },
      }, "manual")
      eq(ns.UI.RouteToggle(r, store, NOW, 100, 5000), true)
      eq(store, { [1] = NOW + 100, ["2@Weekly Rare"] = NOW + 5000 },
        "BossLockouts bosses are keyed per route boss; quest-tracked and untracked mounts are not ticked")

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

    it("an open game-tracked row (instance, quest or lfg spec) is display-only", function()
      local ns = loadUI(nil, { Lockouts = {
        [1] = { instance = 616, boss = "Malygos", difficulties = { 3, 4 }, reset = "weekly" },
      } })
      eq({ ns.UI.RouteCheck(row({ { mount = 1, boss = "Malygos", state = "open" } })) }, { false, false, false })
      eq(ns.UI.RouteToggle(row({ { mount = 1, boss = "Malygos", state = "open" } }), {}, NOW, 100, 5000), false)
      eq({ ns.UI.RouteCheck(row({ { mount = 9, state = "open" } })) }, { false, false, false }, "untracked stays disabled")
    end)

    it("a stored hand tick on a game-tracked row is ignored: only the game's lockouts count", function()
      local saved = {}
      local ns = loadUI({ SavedRows = function() return saved end }, {
        Route = { kill("Eye of Eternity", { { mount = 1, boss = "Malygos" } }) },
        Lockouts = { [1] = { instance = 616, boss = "Malygos", difficulties = { 3, 4 }, reset = "weekly" } },
      })
      -- A tick left over from an older version (or another click path).
      ns.db.char.ticks = { [1] = NOW + 5000 }
      eq(ns.UI.RouteContext(NOW).stateOf(1, "Malygos"), "open")
      eq(left(ns, NOW), 1)
      local rows = routeRows(ns, NOW)
      eq({ ns.UI.RouteCheck(rows[1]) }, { false, false, false })

      -- The game reports it done: checked, disabled, auto.
      saved[1] = { instance = 616, difficulty = 3, bosses = { { name = "Malygos", killed = true } } }
      saved[2] = { instance = 616, difficulty = 4, bosses = { { name = "Malygos", killed = true } } }
      eq(ns.UI.RouteContext(NOW).stateOf(1, "Malygos"), "done")
      rows = routeRows(ns, NOW, true)
      eq({ ns.UI.RouteCheck(rows[1]) }, { true, false, true })
    end)

    it("a hand tick on a BossLockouts row does not mark the mount's other rows", function()
      local ns = loadUI(nil, {
        Route = {
          kill("Vortex Pinnacle", { { mount = 395, boss = "Altairus" } }),
          kill("Hoard Vault", { { mount = 395, boss = "Grand Hoarder" } }),
        },
        Lockouts = { [395] = { manual = true, reset = "daily" } },
        BossLockouts = { ["Grand Hoarder"] = { manual = true, reset = "weekly" } },
      })
      local rows = ns.Route.Build(ns.Data.Route, ns.UI.RouteContext(NOW))
      ns.UI.RouteToggle(rows[2], ns.db.char.ticks, NOW, 100, 5000)
      local ctx = ns.UI.RouteContext(NOW)
      eq(ctx.stateOf(395, "Grand Hoarder"), "manual-done")
      eq(ctx.stateOf(395, "Altairus"), "manual-open")
      eq(left(ns, NOW), 1)
    end)

    it("game-tracked rows can't be hand ticked, so no attempts come from clicks", function()
      local ns = loadUI({ RequestLockouts = function() end }, {
        Route = { kill("Eye of Eternity", { { mount = 1, boss = "Malygos" } }) },
        Lockouts = { [1] = { instance = 616, boss = "Malygos", difficulties = { 3, 4 }, reset = "weekly" } },
      })
      ns.addon:OnEnable()
      fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
      local rows = ns.Route.Build(ns.Data.Route, ns.UI.RouteContext(NOW))
      eq(ns.UI.RouteToggle(rows[1], ns.db.char.ticks, NOW, 100, 5000), false)
      eq(ns.db.char.ticks, {})
      fire_event(ns.addon, "UPDATE_INSTANCE_INFO")
      fire_event(ns.addon, "QUEST_TURNED_IN", 1)
      eq(ns.db.global.attempts, {})
    end)

    it("round-trips through RouteContext: a ticked row reads manual-done", function()
      local ns = loadUI(nil, {
        Route = { kill("Rare", { { mount = 3, boss = "C" } }) },
        Lockouts = { [3] = { manual = true, reset = "daily" } },
      })
      local rows = ns.Route.Build(ns.Data.Route, ns.UI.RouteContext(NOW))
      eq(rows[1].bosses[1].state, "manual-open")
      ns.UI.RouteToggle(rows[1], ns.db.char.ticks, NOW, 100, 5000)
      eq(left(ns, NOW), 0)
      rows = routeRows(ns, NOW, true)
      eq(rows[1].state, "done")
      eq({ ns.UI.RouteCheck(rows[1]) }, { true, true, false }, "still clickable to untick")
      eq(left(ns, NOW + 100), 1, "gone after the daily reset")
    end)
  end)

  describe("RouteTargetMount", function()
    it("is the first boss not done (by the game or by hand), else the first; nil without bosses", function()
      local ns = loadUI()
      local t = ns.UI.RouteTargetMount
      eq(t({ kind = "kill", bosses = { { mount = 1, state = "open" }, { mount = 2, state = "open" } } }), 1)
      eq(t({ kind = "kill", bosses = { { mount = 1, state = "done" }, { mount = 2, state = "manual-done" },
        { mount = 3, state = "manual-open" } } }), 3)
      eq(t({ kind = "kill", bosses = { { mount = 1, state = "done" }, { mount = 2, state = "done" } } }), 1,
        "all done: the first")
      eq(t({ kind = "travel", bosses = {} }), nil)
      eq(t({ kind = "travel" }), nil)
      eq(t(nil), nil)
    end)

    it("also returns the target's route boss", function()
      local ns = loadUI()
      local t = ns.UI.RouteTargetMount
      eq({ t({ kind = "kill", bosses = { { mount = 1, boss = "A", state = "done" }, { mount = 2, boss = "B" } } }) },
        { 2, "B" })
      eq({ t({ kind = "kill", bosses = { { mount = 1, boss = "A", state = "done" } } }) }, { 1, "A" })
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
        { header = true, depth = 1, section = "brewfest", key = "||brewfest", text = "Brewfest",
          badge = "Active now", owned = 0, total = 1, collapsed = false },
        { id = 1, m = a, owned = false },
        { header = true, depth = 1, section = "darkmoon", key = "||darkmoon", text = "Darkmoon Faire",
          owned = 0, total = 2, collapsed = false },
        { id = 2, m = b, owned = false, tag = "Trading Post — this month" },
        { id = 3, m = c, owned = false },
      })
    end)

    it("ListRows marks headers of active sections (opts.headerActive)", function()
      local ns = loadUI(nil, { Holidays = { brewfest = { title = "Brewfest" }, darkmoon = { title = "Darkmoon Faire" } } })
      local a, b = { section = "brewfest" }, { section = "darkmoon" }
      local active = { brewfest = true }
      local rows = ns.UI.ListRows({ { id = 1, m = a }, { id = 2, m = b } }, nil, {
        headerSuffix = function(section) return ns.UI.HolidayBadge(section, active) end,
        headerActive = function(section) return active[section] == true end,
      })
      eq(rows[1], { header = true, depth = 1, section = "brewfest", key = "||brewfest", text = "Brewfest",
        badge = "Active now", owned = 0, total = 1, collapsed = false, active = true })
      eq(rows[3].active, nil, "inactive header: no flag")
    end)

    it("ListRows carries a muted badge (headerSuffix's second return) as badgeMuted", function()
      local ns = loadUI(nil, { Holidays = { brewfest = { title = "Brewfest" }, darkmoon = { title = "Darkmoon Faire" } } })
      local a, b = { section = "brewfest" }, { section = "darkmoon" }
      local rows = ns.UI.ListRows({ { id = 1, m = a }, { id = 2, m = b } }, nil, {
        headerSuffix = function(section)
          if section == "darkmoon" then return "Starts in 9d", true end
          return "Active now", false
        end,
      })
      eq(rows[1].badge, "Active now")
      eq(rows[1].badgeMuted, nil)
      eq(rows[3].badge, "Starts in 9d")
      eq(rows[3].badgeMuted, true)
    end)

    it("HeaderText paints a muted badge in grey, an active header's in green", function()
      local ns = loadUI()
      eq(ns.UI.HeaderText({ text = "Darkmoon Faire", owned = 0, total = 2, badge = "Starts in 9d", badgeMuted = true }),
        "Darkmoon Faire  |cff9d9d9d(0/2)|r  |cff9d9d9dStarts in 9d|r")
      eq(ns.UI.HeaderText({ text = "Brewfest", active = true, badge = "Active · ends in 6d", badgeMuted = true }),
        "|cff19ff19Brewfest|r  |cff19ff19Active · ends in 6d|r")
    end)

    it("HeaderText paints an active header's text and badge in green", function()
      local ns = loadUI()
      eq(ns.UI.HeaderText({ text = "Brewfest", badge = "Active now", active = true, owned = 1, total = 3 }),
        "|cff19ff19Brewfest|r  |cff9d9d9d(1/3)|r  |cff19ff19Active now|r")
      eq(ns.UI.HeaderText({ text = "Brewfest", active = true }), "|cff19ff19Brewfest|r")
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

    it("HolidayBadge dates a holiday from the schedule: running, upcoming, or nothing", function()
      local ns = loadUI()
      local function ct(month, monthDay, hour)
        return { year = 2026, month = month, monthDay = monthDay, weekday = 1, hour = hour or 0, minute = 0 }
      end
      local schedule = { now = ct(10, 19, 12), occurrences = {
        brewfest = { { startTime = ct(9, 20), endTime = ct(10, 25, 15) } },
        hallowsend = { { startTime = ct(10, 28, 12), endTime = ct(11, 2) } },
        darkmoon = { { startTime = { year = 2027, month = 3, monthDay = 1, weekday = 1, hour = 0, minute = 0 },
          endTime = { year = 2027, month = 3, monthDay = 7, weekday = 1, hour = 0, minute = 0 } } },
      } }
      local active = { brewfest = true }
      eq({ ns.UI.HolidayBadge("brewfest", active, schedule) }, { "Active · ends in 6d", false })
      eq({ ns.UI.HolidayBadge("hallowsend", active, schedule) }, { "Starts in 9d", true })
      eq({ ns.UI.HolidayBadge("darkmoon", active, schedule) }, { "Starts Mar 1", true })
      eq(ns.UI.HolidayBadge("noblegarden", active, schedule), nil, "not in the schedule")
      eq({ ns.UI.HolidayBadge("brewfest", active, {}) }, { "Active now", false }, "schedule without data")
      eq({ ns.UI.HolidayBadge("brewfest", active, nil) }, { "Active now", false }, "no schedule")
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
      kill("Hoard Vault", { { mount = 781, boss = "Grand Hoarder" } }),
    }

    it("uses the first route boss's BossLockouts spec", function()
      local ns = loadUI({
        SavedRows = function()
          return { { instance = 624, difficulty = 3, bosses = { { name = "Koralon the Flame Watcher", killed = true } } },
                   { instance = 624, difficulty = 4, bosses = { { name = "Koralon the Flame Watcher", killed = true } } },
                   { instance = 2579, difficulty = 23, bosses = { { name = "Grand Hoarder", killed = true } } } }
        end,
      }, {
        Route = route,
        Lockouts = {
          [286] = { instance = 624, boss = "Archavon the Stone Watcher", difficulties = { 3, 4 }, reset = "weekly" },
          [781] = { manual = true, reset = "daily" },
        },
        BossLockouts = {
          ["Koralon"] = { instance = 624, boss = "Koralon the Flame Watcher", difficulties = { 3, 4 }, reset = "weekly" },
          ["Grand Hoarder"] = { instance = 2579, boss = "Grand Hoarder", difficulties = { 23 }, reset = "weekly" },
        },
      })
      eq(ns.UI.RouteBoss(286), "Koralon")
      eq(ns.UI.LockoutStatus(286), "saved", "Koralon spec, not Archavon's")
      eq(ns.UI.LockoutStatus(781), "saved", "Hoarder spec instead of manual")
    end)

    -- F12 (F10 carry-over): a checklist / route row's hover names its own boss.
    it("a row's own route boss wins over the mount's first route boss", function()
      local ns = loadUI({
        SavedRows = function()
          return { { instance = 624, difficulty = 3, bosses = { { name = "Koralon the Flame Watcher", killed = true } } },
                   { instance = 624, difficulty = 4, bosses = { { name = "Koralon the Flame Watcher", killed = true } } } }
        end,
      }, {
        Route = route,
        Mounts = { [286] = { name = "Grand Black War Mammoth" } },
        Lockouts = {
          [286] = { instance = 624, boss = "Archavon the Stone Watcher", difficulties = { 3, 4 }, reset = "weekly" },
        },
        BossLockouts = {
          ["Koralon"] = { instance = 624, boss = "Koralon the Flame Watcher", difficulties = { 3, 4 }, reset = "weekly" },
        },
      })
      eq(ns.UI.LockoutStatus(286, "Archavon"), "available", "the Archavon row: Archavon's own lockout")
      eq(ns.UI.LockoutStatus(286, "Koralon"), "saved")
      eq(ns.UI.LockoutStatus(286), "saved", "no row boss: the first route boss (Koralon)")
      local function lockoutLine(boss)
        for _, l in ipairs(ns.UI.TooltipLines(286, boss)) do
          if l.left and l.left:find("^Lockout: ") then return l.left end
        end
      end
      eq(lockoutLine("Archavon"), "Lockout: Available")
      eq(lockoutLine("Koralon"), "Lockout: Saved")
      eq(lockoutLine(nil), "Lockout: Saved")
    end)
  end)
end)
