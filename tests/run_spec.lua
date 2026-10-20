-- Run (Logic/Run.lua): tonight's farming run - stop order and progress.

local function load()
  return load_addon({ "Core/Locale.lua", "Logic/Run.lua" }).Run
end

local function stop(key, area, name, c, x, y)
  return { key = key, place = { area = area, areaName = name, continent = c, x = x, y = y } }
end

local function keys(stops)
  local out = {}
  for i, s in ipairs(stops) do out[i] = s.key end
  return out
end

local function always() return true end

describe("Run.Plan", function()
  it("rides the player's continent first, nearest stop next", function()
    local Run = load()
    local stops = {
      stop("far", 113, "Northrend", 571, 100, 0),
      stop("ek", 13, "Eastern Kingdoms", 0, 0, 0),
      stop("near", 113, "Northrend", 571, 10, 0),
      stop("mid", 113, "Northrend", 571, 50, 0),
    }
    eq(keys(Run.Plan(stops, { continent = 571, x = 0, y = 0 })), { "near", "mid", "far", "ek" })
  end)

  it("orders other continents by stop count, then name; unknown places last", function()
    local Run = load()
    local stops = {
      { key = "nowhere" },
      stop("k1", 12, "Kalimdor", 1, 0, 0),
      stop("e1", 13, "Eastern Kingdoms", 0, 0, 0),
      stop("o1", 101, "Outland", 530, 0, 0),
      stop("o2", 101, "Outland", 530, 5, 0),
    }
    eq(keys(Run.Plan(stops, nil)), { "o1", "o2", "e1", "k1", "nowhere" })
  end)

  it("starts a continent away from the player at one end of it", function()
    local Run = load()
    local stops = {
      stop("b", 113, "Northrend", 571, 50, 0),
      stop("a", 113, "Northrend", 571, 0, 0),
      stop("c", 113, "Northrend", 571, 120, 0),
    }
    eq(keys(Run.Plan(stops, { continent = 0, x = 0, y = 0 })), { "c", "b", "a" })
  end)

  it("puts zone-only stops after the pinned ones of their continent", function()
    local Run = load()
    local stops = {
      { key = "zone", place = { area = 113, areaName = "Northrend" } },
      stop("pin", 113, "Northrend", 571, 0, 0),
    }
    eq(keys(Run.Plan(stops, nil)), { "pin", "zone" })
  end)
end)

describe("Run progress", function()
  it("follows open stops, skips and expiry", function()
    local Run = load()
    local run = Run.New({ { key = "a" }, { key = "b" }, { key = "c" } }, 100, 200)
    local open = { a = true, b = true, c = true }
    local isOpen = function(k) return open[k] == true end
    eq(Run.Current(run, isOpen).key, "a")
    eq(keys(Run.Upcoming(run, isOpen, 5)), { "b", "c" })
    open.a = false -- the game reports the kill
    eq(Run.Current(run, isOpen).key, "b")
    eq({ Run.Progress(run, isOpen) }, { 1, 3 })
    eq(Run.Skip(run, isOpen).key, "c")
    eq(Run.SkippedOpen(run, isOpen), 1)
    open.c = false
    eq(Run.Current(run, isOpen), nil)
    eq({ Run.Progress(run, isOpen) }, { 3, 3 })
    Run.Unskip(run)
    eq(Run.Current(run, isOpen).key, "b")
    ok(not Run.Expired(run, 199))
    ok(Run.Expired(run, 200))
    ok(Run.Expired(nil, 0))
  end)

  it("treats an empty run as over", function()
    local Run = load()
    local run = Run.New({}, 0, 10)
    eq(Run.Current(run, always), nil)
    eq({ Run.Progress(run, always) }, { 0, 0 })
  end)
end)
