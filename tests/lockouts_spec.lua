describe("lockouts", function()
  local function load()
    return load_addon({"Logic/Lockouts.lua"})
  end
  local function loadWithData()
    return load_addon({"Data/Mounts.lua", "Data/Lockouts.lua", "Logic/Lockouts.lua"})
  end

  local function killed(instance, diff, boss)
    return { [instance] = { [diff] = { [boss] = true } } }
  end
  local function merge(...)
    local out = {}
    for _, s in ipairs({...}) do
      for inst, byDiff in pairs(s) do
        out[inst] = out[inst] or {}
        for d, bosses in pairs(byDiff) do
          out[inst][d] = out[inst][d] or {}
          for b in pairs(bosses) do out[inst][d][b] = true end
        end
      end
    end
    return out
  end

  describe("Snapshot", function()
    it("snapshot of nil rows is empty", function()
      eq(load().Lockouts.Snapshot(nil), {})
    end)

    it("records only killed bosses by instance, difficulty, name", function()
      local rows = {
        { instance = 657, difficulty = 2, bosses = { { name = "Altairus", killed = true }, { name = "Asaad", killed = false } } },
        { instance = 657, difficulty = 1, bosses = { { name = "Asaad", killed = true } } },
      }
      eq(load().Lockouts.Snapshot(rows), {
        [657] = { [2] = { Altairus = true }, [1] = { Asaad = true } },
      })
    end)

    it("skips rows with nil instance or difficulty and bosses with nil name", function()
      local rows = {
        { instance = nil, difficulty = 2, bosses = { { name = "A", killed = true } } },
        { instance = 657, difficulty = nil, bosses = { { name = "B", killed = true } } },
        { instance = 657, difficulty = 2, bosses = { { name = nil, killed = true }, { name = "Altairus", killed = true } } },
      }
      eq(load().Lockouts.Snapshot(rows), { [657] = { [2] = { Altairus = true } } })
    end)

    it("omits rows with no kills", function()
      local rows = { { instance = 1, difficulty = 1, bosses = { { name = "X", killed = false } } } }
      eq(load().Lockouts.Snapshot(rows), {})
    end)
  end)

  describe("State", function()
    local spec = { instance = 657, boss = "Altairus", difficulties = { 2 }, reset = "daily" }

    it("done when killed on the required difficulty", function()
      eq(load().Lockouts.State(spec, killed(657, 2, "Altairus")), "done")
    end)

    it("open when killed on another difficulty only", function()
      eq(load().Lockouts.State(spec, killed(657, 1, "Altairus")), "open")
    end)

    it("open when a different boss was killed", function()
      eq(load().Lockouts.State(spec, killed(657, 2, "Asaad")), "open")
    end)

    it("tolerates nil and empty snapshots", function()
      local L = load().Lockouts
      eq(L.State(spec, nil), "open")
      eq(L.State(spec, {}), "open")
    end)

    it("nil spec is not tracked", function()
      eq(load().Lockouts.State(nil, {}), nil)
    end)

    it("separate difficulties {14,15} need both", function()
      local L = load().Lockouts
      local s = { instance = 1, boss = "B", difficulties = { 14, 15 }, reset = "weekly" }
      eq(L.State(s, killed(1, 14, "B")), "open")
      eq(L.State(s, killed(1, 15, "B")), "open")
      eq(L.State(s, merge(killed(1, 14, "B"), killed(1, 15, "B"))), "done")
    end)

    it("group {{3,4,5,6}} is done by any one of them", function()
      local L = load().Lockouts
      local s = { instance = 1, boss = "B", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }
      eq(L.State(s, killed(1, 5, "B")), "done")
      eq(L.State(s, killed(1, 3, "B")), "done")
      eq(L.State(s, killed(1, 14, "B")), "open")
    end)

    it("mixed { 2, {5,6} } needs both groups", function()
      local L = load().Lockouts
      local s = { instance = 1, boss = "B", difficulties = { 2, { 5, 6 } }, reset = "weekly" }
      eq(L.State(s, killed(1, 2, "B")), "open")
      eq(L.State(s, killed(1, 6, "B")), "open")
      eq(L.State(s, merge(killed(1, 2, "B"), killed(1, 6, "B"))), "done")
    end)

    it("boss name matches by prefix in either direction, plainly", function()
      local L = load().Lockouts
      local s = { instance = 1, boss = "Fyrakk", difficulties = { 16 }, reset = "weekly" }
      eq(L.State(s, killed(1, 16, "Fyrakk the Blazing")), "done")
      local s2 = { instance = 1, boss = "Fyrakk the Blazing", difficulties = { 16 }, reset = "weekly" }
      eq(L.State(s2, killed(1, 16, "Fyrakk")), "done")
      eq(L.State(s, killed(1, 16, "Not Fyrakk")), "open")
    end)

    it("boss names with pattern characters match literally", function()
      local L = load().Lockouts
      local s = { instance = 1, boss = "Kael'thas (Sunstrider)-", difficulties = { 2 }, reset = "daily" }
      eq(L.State(s, killed(1, 2, "Kael'thas (Sunstrider)-")), "done")
      local s2 = { instance = 1, boss = "A.c", difficulties = { 2 }, reset = "daily" }
      eq(L.State(s2, killed(1, 2, "Abc")), "open")
    end)

    it("quest spec uses isQuestDone", function()
      local L = load().Lockouts
      local s = { quest = 123, reset = "weekly" }
      local seen
      eq(L.State(s, {}, function(id) seen = id; return true end), "done")
      eq(seen, 123)
      eq(L.State(s, {}, function() return false end), "open")
      eq(L.State(s, {}), "open")
    end)

    it("lfg spec uses isLfgDone", function()
      local L = load().Lockouts
      local s = { lfg = 99, reset = "daily" }
      eq(L.State(s, {}, nil, function() return false end), "open")
      eq(L.State(s, {}, nil, function(id) return id == 99 end), "done")
      eq(L.State(s, {}), "open")
    end)

    it("manual spec is manual", function()
      eq(load().Lockouts.State({ manual = true, reset = "weekly" }, {}), "manual")
    end)

    it("unknown spec kind is open", function()
      eq(load().Lockouts.State({ reset = "weekly" }, {}), "open")
    end)
  end)

  describe("SpecFor", function()
    it("prefers the per-boss spec when the route boss has one", function()
      local ns = loadWithData()
      eq(ns.Lockouts.SpecFor(286, "Koralon"), ns.Data.BossLockouts["Koralon"])
    end)

    it("falls back to the mount spec for an unknown route boss", function()
      local ns = loadWithData()
      eq(ns.Lockouts.SpecFor(286, "Nobody"), ns.Data.Lockouts[286])
      eq(ns.Lockouts.SpecFor(286), ns.Data.Lockouts[286])
    end)

    it("falls back to the Rarity quest flag", function()
      local ns = load_addon({"Logic/Lockouts.lua"})
      ns.Data = { Lockouts = {}, BossLockouts = {}, Mounts = { [5] = { quest = 777 } } }
      eq(ns.Lockouts.SpecFor(5), { quest = 777, reset = "weekly" })
    end)

    it("returns nil with no spec and no quest", function()
      local ns = load_addon({"Logic/Lockouts.lua"})
      ns.Data = { Lockouts = {}, BossLockouts = {}, Mounts = { [5] = {} } }
      eq(ns.Lockouts.SpecFor(5), nil)
      eq(ns.Lockouts.SpecFor(6), nil)
    end)
  end)
end)
