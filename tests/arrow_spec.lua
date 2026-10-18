-- Pure helpers of UI/Arrow.lua (Bearing, NextStep, route mode), the Frame.lua
-- refresh hooks and UI.RouteNextStep. The arrow is parked (F16): routeMode is
-- forced to "list" on load and /azt arrow is gone. The arrow frame itself is
-- compile-checked only.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/JournalHome.lua",
  "UI/Tabs.lua", "UI/LockoutHelpers.lua", "UI/Arrow.lua" }

local NOW = 1000000
local PI = math.pi
local TAU = 2 * PI

local function loadUI(game, data)
  reset_ui_stub()
  AzerothTrailArrow = nil
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  local stubGame = {
    MountInfo = function() return nil end,
    IsOwned = function() return false end,
    Faction = function() return "Horde" end,
    SavedRows = function() return {} end,
    IsQuestDone = function() return false end,
    IsLfgDone = function() return false end,
    ActiveHolidays = function() return {} end,
    Now = function() return NOW end,
    PlayerName = function() return "Adventurer" end,
  }
  for k, v in pairs(game or {}) do stubGame[k] = v end
  for k, v in pairs(stubGame) do ns.Game[k] = v end
  ns.Data.Lockouts, ns.Data.BossLockouts = {}, {}
  ns.Data.Route, ns.Data.Holidays, ns.Data.Mounts = {}, {}, {}
  for k, v in pairs(data or {}) do ns.Data[k] = v end
  return ns
end

local function near(actual, expected, msg)
  ok(type(actual) == "number", (msg or "") .. ": not a number: " .. tostring(actual))
  -- compare modulo 2*pi
  local d = math.abs(actual - expected) % TAU
  d = math.min(d, TAU - d)
  ok(d < 1e-6, (msg or "") .. ": expected " .. expected .. ", got " .. actual)
end

local function travel(key, depth, title)
  return { key = key, depth = depth, kind = "travel", title = title, bosses = {}, state = "open" }
end

local function killRow(key, depth, title, state, locked)
  return { key = key, depth = depth, kind = "kill", title = title, state = state or "open",
    bosses = { { mount = 1, boss = "B", state = state or "open", locked = locked or false } } }
end

describe("arrow", function()
  it("toc lists UI\\Arrow.lua right after UI\\LockoutHelpers.lua", function()
    local fh = assert(io.open(ROOT .. "/AzerothTrail.toc", "r"))
    local lines = {}
    for line in fh:lines() do
      line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if line ~= "" and not line:find("^#") then lines[#lines + 1] = line end
    end
    fh:close()
    local rv
    for i, line in ipairs(lines) do if line == "UI\\LockoutHelpers.lua" then rv = i end end
    ok(rv, "UI\\LockoutHelpers.lua in toc")
    eq(lines[rv + 1], "UI\\Arrow.lua")
  end)

  it("loads and exposes the helpers without building the frame", function()
    local ns = loadUI()
    for _, name in ipairs({ "Bearing", "NextStep", "TargetBoss", "Mode", "SetMode", "ToggleMode" }) do
      eq(type(ns.Arrow[name]), "function", name)
    end
    eq(type(ns.UI.RouteNextStep), "function", "RouteNextStep")
    eq(AzerothTrailArrow, nil, "no arrow frame at load")
  end)

  describe("Bearing (world X north, Y west; facing 0 north, counter-clockwise)", function()
    local px, py = 100, 200
    local cases = {
      -- target name, tx, ty, angle at facing 0, angle at facing pi/2 (facing west)
      { "north", px + 30, py, 0, 3 * PI / 2 },
      { "west", px, py + 30, PI / 2, 0 },
      { "south", px - 30, py, PI, PI / 2 },
      { "east", px, py - 30, 3 * PI / 2, PI },
    }
    for _, c in ipairs(cases) do
      it("target " .. c[1], function()
        local Arrow = loadUI().Arrow
        local a0, d0 = Arrow.Bearing(px, py, c[2], c[3], 0)
        near(a0, c[4], c[1] .. " facing 0")
        near(d0, 30, c[1] .. " distance")
        local a1, d1 = Arrow.Bearing(px, py, c[2], c[3], PI / 2)
        near(a1, c[5], c[1] .. " facing pi/2")
        near(d1, 30, c[1] .. " distance at pi/2")
      end)
    end

    it("returns angles in [0, 2pi) and the straight-line distance", function()
      local Arrow = loadUI().Arrow
      local a, d = Arrow.Bearing(0, 0, 3, -4, 0) -- north-east-ish
      ok(a >= 0 and a < TAU, "angle in range: " .. a)
      near(d, 5, "3-4-5")
      a = Arrow.Bearing(0, 0, 10, 0, -PI / 2) -- facing east (-pi/2), target north: left
      ok(a >= 0 and a < TAU, "negative facing normalised: " .. a)
      near(a, PI / 2, "north is on the left when facing east")
    end)

    it("is 0 / 0 on the target itself", function()
      local a, d = loadUI().Arrow.Bearing(5, 5, 5, 5, 1)
      near(d, 0, "distance")
      ok(a >= 0 and a < TAU, "angle defined")
    end)
  end)

  describe("NextStep", function()
    local rows = {
      travel("1", 0, "Start in Orgrimmar"),
      travel("1.1", 1, "Portal to Uldum"),
      killRow("1.1.1", 2, "Done raid", "done"),
      travel("1.2", 1, "Fly to Twin Peaks"),
      killRow("1.2.1", 2, "Skipped raid"),
      killRow("1.2.2", 2, "Locked raid", "open", true),
      killRow("1.2.3", 2, "Run Throne of the Four Winds", "manual"),
      killRow("1.2.4", 2, "Later raid"),
    }

    it("skips done, skipped and locked rows; hints are the travel rows above it", function()
      local Arrow = loadUI().Arrow
      local row, hints = Arrow.NextStep(rows, { ["1.2.1"] = true })
      eq(row and row.title, "Run Throne of the Four Winds")
      eq(hints, { "Start in Orgrimmar", "Fly to Twin Peaks" })
    end)

    it("without skips the first open row wins", function()
      local Arrow = loadUI().Arrow
      local row, hints = Arrow.NextStep(rows, nil)
      eq(row.title, "Skipped raid")
      eq(hints, { "Start in Orgrimmar", "Fly to Twin Peaks" })
    end)

    it("a depth-0 kill row has no hints", function()
      local Arrow = loadUI().Arrow
      local row, hints = Arrow.NextStep({ killRow("h1", 0, "Queue for Coren Direbrew (Brewfest)") }, {})
      eq(row.key, "h1")
      eq(hints, {})
    end)

    it("returns nil when nothing remains", function()
      local Arrow = loadUI().Arrow
      local row, hints = Arrow.NextStep({
        travel("1", 0, "Start in Orgrimmar"),
        killRow("1.1", 1, "Done", "done"),
        killRow("1.2", 1, "Skipped"),
        killRow("1.3", 1, "Locked", "open", true),
      }, { ["1.2"] = true })
      eq(row, nil)
      eq(hints, {})
      eq(Arrow.NextStep({}, {}), nil, "empty route")
      eq(Arrow.NextStep(nil, nil), nil, "no rows")
    end)
  end)

  describe("TargetBoss", function()
    local function row(states)
      local bosses = {}
      for i, st in ipairs(states) do bosses[i] = { mount = 100 + i, boss = "B" .. i, state = st } end
      return { kind = "kill", bosses = bosses }
    end

    it("targets the first boss that is not done or manual-done", function()
      local Arrow = loadUI().Arrow
      local b, i = Arrow.TargetBoss(row({ "done", "manual-done", "open", "manual-open" }))
      eq({ b.mount, i }, { 103, 3 })
      b, i = Arrow.TargetBoss(row({ "done", "manual-open" }))
      eq({ b.mount, i }, { 102, 2 })
    end)

    it("falls back to the first boss, and nil without bosses", function()
      local Arrow = loadUI().Arrow
      local b, i = Arrow.TargetBoss(row({ "done", "manual-done" }))
      eq({ b.mount, i }, { 101, 1 })
      eq(Arrow.TargetBoss({ kind = "kill", bosses = {} }), nil)
      eq(Arrow.TargetBoss(nil), nil)
    end)
  end)

  describe("route mode", function()
    it("defaults to list and flips list <-> arrow in the db", function()
      local ns = loadUI()
      eq(ns.db.char.routeMode, "list", "AceDB default")
      eq(type(ns.db.global.arrow), "table", "arrow position store")
      eq(ns.Arrow.Mode(), "list")
      eq(ns.Arrow.ToggleMode(), "arrow")
      eq(ns.db.char.routeMode, "arrow")
      eq(ns.Arrow.Mode(), "arrow")
      eq(ns.Arrow.ToggleMode(), "list")
      eq(ns.db.char.routeMode, "list")
    end)

    it("works on a given store and treats unknown values as list", function()
      local Arrow = loadUI().Arrow
      local char = {}
      eq(Arrow.Mode(char), "list")
      eq(Arrow.ToggleMode(char), "arrow")
      eq(char.routeMode, "arrow")
      char.routeMode = "bogus"
      eq(Arrow.Mode(char), "list")
      eq(Arrow.ToggleMode(char), "arrow")
      eq(Arrow.SetMode(char, "list"), "list")
      eq(char.routeMode, "list")
      eq(Arrow.SetMode(char, "nonsense"), "list", "invalid -> list")
      eq(Arrow.Mode(nil), "list", "no db yet")
    end)
  end)

  describe("RouteNextStep", function()
    it("uses the character's route, context and session skips", function()
      local ns = loadUI({ IsQuestDone = function(q) return q == 1001 end }, {
        Route = { { title = "Fly to Twin Peaks", steps = {
          { title = "Done raid", type = "Raid", bosses = { { mount = 1, boss = "A" } } },
          { title = "Open raid", type = "Raid", bosses = { { mount = 2, boss = "B" } } },
          { title = "Other raid", type = "Raid", bosses = { { mount = 3, boss = "C" } } },
        } } },
        Lockouts = { [1] = { quest = 1001, reset = "weekly" }, [2] = { quest = 1002, reset = "weekly" } },
      })
      local row, hints = ns.UI.RouteNextStep(NOW, {})
      eq(row.title, "Open raid")
      eq(hints, { "Fly to Twin Peaks" })
      row = ns.UI.RouteNextStep(NOW, { [row.key] = true })
      eq(row.title, "Other raid")
    end)
  end)

  describe("refresh hooks", function()
    it("ns.Refresh runs hooks even while the window is closed", function()
      local ns = loadUI()
      local calls = 0
      ns.UI.AddRefreshHook(function() calls = calls + 1 end)
      ns.Refresh()
      eq(calls, 1)
      eq(ns.UI.frame, nil, "window still not built")
    end)

    it("list mode never builds the arrow frame", function()
      local ns = loadUI()
      ns.Refresh()
      eq(AzerothTrailArrow, nil)
    end)
  end)

  describe("parked (F16)", function()
    it("ns.RetireRoute forces list mode and drops the route list's settings", function()
      local ns = loadUI()
      local db = { char = { routeMode = "arrow", routeView = "route", showCompleted = true, ticks = { [1] = 5 } },
        global = { window = { tab = "route", x = 3 } } }
      ns.RetireRoute(db)
      eq(db.char, { routeMode = "list", ticks = { [1] = 5 } })
      eq(db.global.window, { tab = "checklist", x = 3 })
      local other = { char = {}, global = { window = { tab = "misc" } } }
      ns.RetireRoute(other)
      eq(other.global.window.tab, "misc", "other tabs are kept")
      ns.RetireRoute({}) -- no sections: no error
      ns.RetireRoute(nil)
    end)

    it("OnInitialize runs it, so a saved arrow mode never shows the frame", function()
      local ns = loadUI()
      local retired
      local old = ns.RetireRoute
      ns.RetireRoute = function(db) retired = db; return old(db) end
      ns.addon:OnInitialize()
      eq(retired, ns.db)
      eq(ns.db.char.routeMode, "list")
      ns.Refresh()
      eq(AzerothTrailArrow, nil)
    end)

    it("/azt arrow is no longer a command: it prints the help, which no longer lists it", function()
      local ns = loadUI()
      run_slash(ns.addon, "azt", "arrow")
      eq(ns.db.char.routeMode, "list")
      local text = table.concat(ns.addon.printed, " | ")
      ok(text:find("Commands:", 1, true), "help printed")
      ok(not text:find("/azt arrow", 1, true), "help does not mention /azt arrow")
    end)
  end)
end)
