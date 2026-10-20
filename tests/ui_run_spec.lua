-- Tonight's run, pure helpers (UI/RunWindow.lua): which checklist entries a
-- run rides to, its stops and open-check, and the window's lines.

local function load()
  return load_addon({ "Core/Locale.lua", "Logic/Lockouts.lua", "Logic/Checklist.lua", "Logic/Run.lua",
    "UI/RunWindow.lua" })
end

local function entry(key, opts)
  local e = { key = key, id = key, name = "M" .. key, category = "raids" }
  for k, v in pairs(opts or {}) do e[k] = v end
  return e
end

describe("UI.RunEntries", function()
  it("keeps open, unlocked daily and weekly entries in shown categories; never the camp group", function()
    local UI = load().UI
    local built = {
      daily = { entry(1), entry(2, { done = true }), entry(3, { locked = true }) },
      weekly = { entry(4), entry(5, { category = "rares" }) },
      camp = { entry(6) },
    }
    local keys = {}
    for i, e in ipairs(UI.RunEntries(built, { rares = false })) do keys[i] = e.key end
    eq(keys, { 1, 4 })
  end)
end)

describe("UI.RunStops / UI.RunIsOpen", function()
  it("locates each entry by mount and boss; open = still listed, not done, not locked", function()
    local UI = load().UI
    local stops = UI.RunStops({ entry(1, { boss = "Archavon" }) }, function(id, boss)
      return { map = id, areaName = boss }
    end)
    eq(stops, { { key = 1, id = 1, boss = "Archavon", name = "M1", place = { map = 1, areaName = "Archavon" } } })
    local isOpen = UI.RunIsOpen({ daily = { entry(1), entry(2, { done = true }) }, weekly = { entry(3, { locked = true }) } })
    ok(isOpen(1))
    ok(not isOpen(2), "done")
    ok(not isOpen(3), "locked")
    ok(not isOpen(9), "gone (owned)")
  end)
end)

describe("UI.RunWhere / UI.RunTitle", function()
  it("names continent and zone, once when they match", function()
    local UI = load().UI
    local names = { [1] = "Icecrown", [2] = "Northrend" }
    local mapName = function(m) return names[m] end
    eq(UI.RunWhere({ place = { map = 1, areaName = "Northrend" } }, mapName), "Northrend \194\183 Icecrown")
    eq(UI.RunWhere({ place = { map = 2, areaName = "Northrend" } }, mapName), "Northrend")
    eq(UI.RunWhere({ place = { map = 1 } }, mapName), "Icecrown")
    eq(UI.RunWhere({}, mapName), "")
    eq(UI.RunTitle(3, 12), "Tonight's run \194\183 3 / 12")
  end)
end)
