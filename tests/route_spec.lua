describe("route", function()
  -- Loads the route builder with small inline data tables.
  local function load(data)
    local ns = load_addon({"Core/Locale.lua", "Logic/Lockouts.lua", "Logic/Route.lua"})
    ns.Data = data or {}
    ns.Data.Mounts = ns.Data.Mounts or {}
    return ns
  end

  -- ctx with sensible defaults; `over` replaces fields.
  local function ctx(over)
    local c = {
      faction = "Horde",
      isOwned = function() return false end,
      isQuestDone = function() return false end,
      stateOf = function() return "open" end,
      showCompleted = false,
      holidaySteps = {},
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
  end

  local function kill(title, bosses, extra)
    local n = { title = title, type = "Raid", bosses = bosses }
    for k, v in pairs(extra or {}) do n[k] = v end
    return n
  end

  local function titles(rows)
    local out = {}
    for i, r in ipairs(rows) do out[i] = r.title end
    return out
  end

  local function stateMap(map)
    return function(id) return map[id] or "open" end
  end

  describe("faction", function()
    local tree = {
      { title = "Fly to A", steps = {
        kill("Alliance raid", { { mount = 1, boss = "A" } }, { alliance = true }),
        kill("Horde raid", { { mount = 2, boss = "H" } }, { horde = true }),
        kill("Shared raid", { { mount = 3, boss = "S" } }),
      } },
    }

    it("alliance keeps alliance nodes and drops horde nodes", function()
      local rows = load().Route.Build(tree, ctx({ faction = "Alliance" }))
      eq(titles(rows), { "Fly to A", "Alliance raid", "Shared raid" })
    end)

    it("horde keeps horde nodes and drops alliance nodes", function()
      local rows = load().Route.Build(tree, ctx({ faction = "Horde" }))
      eq(titles(rows), { "Fly to A", "Horde raid", "Shared raid" })
    end)

    it("neutral hides faction steps", function()
      local capTree = {
        { title = "", capital = true, steps = tree },
      }
      local rows = load().Route.Build(capTree, ctx({ faction = "Neutral" }))
      eq(titles(rows), { "Hearthstone to your capital", "Fly to A", "Shared raid" })
      ok(string.find(rows[1].title, "your capital", 1, true), "capital title names your capital")
    end)

    it("faction-flagged bosses follow the same rule", function()
      local t = {
        kill("VoA", {
          { mount = 286, boss = "Koralon", alliance = true },
          { mount = 287, boss = "Koralon", horde = true },
          { mount = 9, boss = "Shared" },
        }),
      }
      local ns = load()
      local a = ns.Route.Build(t, ctx({ faction = "Alliance" }))
      eq(#a[1].bosses, 2)
      eq(a[1].bosses[1].mount, 286)
      eq(a[1].bosses[2].mount, 9)
      local h = ns.Route.Build(t, ctx({ faction = "Horde" }))
      eq(#h[1].bosses, 2)
      eq(h[1].bosses[1].mount, 287)
      local n = ns.Route.Build(t, ctx({ faction = "Neutral" }))
      eq(#n[1].bosses, 1)
      eq(n[1].bosses[1].mount, 9)
    end)
  end)

  describe("capital", function()
    local tree = {
      { title = "and Portal to Oribos", capital = true, notes = "Set Hearthstone to Faction Capital",
        steps = { kill("Run X", { { mount = 1, boss = "B" } }) } },
    }

    it("horde hearths to Orgrimmar, then the node title", function()
      local rows = load().Route.Build(tree, ctx({ faction = "Horde" }))
      eq(rows[1].title, "Hearthstone to Orgrimmar and Portal to Oribos")
      eq(rows[1].notes, "Set Hearthstone to Faction Capital")
    end)

    it("alliance hearths to Stormwind", function()
      local rows = load().Route.Build(tree, ctx({ faction = "Alliance" }))
      eq(rows[1].title, "Hearthstone to Stormwind and Portal to Oribos")
    end)

    it("empty node title adds nothing after the capital", function()
      local t = { { title = "", capital = true, steps = tree[1].steps } }
      local rows = load().Route.Build(t, ctx({ faction = "Horde" }))
      eq(rows[1].title, "Hearthstone to Orgrimmar")
    end)

    it("start step reads Start in <capital>", function()
      local t = { { title = "Start in ", capital = true, startStep = true, steps = tree[1].steps } }
      local ns = load()
      eq(ns.Route.Build(t, ctx({ faction = "Horde" }))[1].title, "Start in Orgrimmar")
      eq(ns.Route.Build(t, ctx({ faction = "Alliance" }))[1].title, "Start in Stormwind")
      eq(ns.Route.Build(t, ctx({ faction = "Neutral" }))[1].title, "Start in your capital")
      eq(rawget(ns.L, "Start in %s"), "Start in %s")
    end)

    it("locale has explicit capital strings", function()
      local ns = load()
      eq(rawget(ns.L, "Hearthstone to %s"), "Hearthstone to %s")
      eq(rawget(ns.L, "your capital"), "your capital")
    end)
  end)

  describe("bosses", function()
    it("owned boss removed and empty kill dropped", function()
      local t = {
        kill("Two bosses", { { mount = 1, boss = "A" }, { mount = 2, boss = "B" } }),
        kill("All owned", { { mount = 3, boss = "C" } }),
      }
      local owned = { [1] = true, [3] = true }
      local rows = load().Route.Build(t, ctx({ isOwned = function(id) return owned[id] == true end }))
      eq(titles(rows), { "Two bosses" })
      eq(#rows[1].bosses, 1)
      eq(rows[1].bosses[1].mount, 2)
      eq(rows[1].bosses[1].boss, "B")
    end)

    it("unobtainable mounts are dropped like owned", function()
      local t = {
        kill("Mixed", { { mount = 1, boss = "A" }, { mount = 2, boss = "B" } }),
        kill("Gone", { { mount = 1, boss = "A" } }),
      }
      local ns = load({ Mounts = { [1] = { unobtainable = true }, [2] = {} } })
      local rows = ns.Route.Build(t, ctx())
      eq(titles(rows), { "Mixed" })
      eq(#rows[1].bosses, 1)
      eq(rows[1].bosses[1].mount, 2)
    end)

    it("unavailable nodes and bosses are dropped", function()
      local t = {
        { title = "Fly", steps = {
          kill("Removed raid", { { mount = 1, boss = "A" } }, { unavailable = true }),
          kill("Live raid", { { mount = 2, boss = "B" }, { mount = 3, boss = "C", unavailable = true } }),
        } },
        { title = "Removed zone", unavailable = true, steps = {
          kill("Inner", { { mount = 4, boss = "D" } }),
        } },
      }
      local rows = load().Route.Build(t, ctx())
      eq(titles(rows), { "Fly", "Live raid" })
      eq(#rows[2].bosses, 1)
      eq(rows[2].bosses[1].mount, 2)
    end)

    it("boss rows carry note and state", function()
      local t = { kill("K", { { mount = 7, boss = "B", note = "Mythic only" } }) }
      local rows = load().Route.Build(t, ctx({ stateOf = stateMap({ [7] = "manual-open" }) }))
      eq(rows[1].bosses[1].note, "Mythic only")
      eq(rows[1].bosses[1].state, "manual-open")
      eq(rows[1].bosses[1].locked, false)
    end)

    it("locked boss stays visible and flagged", function()
      local t = { kill("Garrison", { { mount = 5, boss = "Gorgrond" }, { mount = 6, boss = "Free" } }) }
      local ns = load({ Lockouts = {
        [5] = { quest = 100, reset = "weekly", requires = { quest = 900, text = "Garrison unlocked" } },
      } })
      local rows = ns.Route.Build(t, ctx())
      eq(#rows, 1)
      eq(rows[1].bosses[1].locked, true)
      eq(rows[1].bosses[1].lockedText, "Garrison unlocked")
      eq(rows[1].bosses[2].locked, false)
      eq(rows[1].bosses[2].lockedText, nil)
      local done = ns.Route.Build(t, ctx({ isQuestDone = function(q) return q == 900 end }))
      eq(done[1].bosses[1].locked, false)
    end)

    it("requires is looked up through Lockouts.SpecFor with the route boss", function()
      local t = { kill("Per boss", { { mount = 8, boss = "Special" } }) }
      local ns = load({ BossLockouts = {
        Special = { lfg = 1, requires = { quest = 901, text = "Mechagon unlocked" } },
      } })
      local rows = ns.Route.Build(t, ctx())
      eq(rows[1].bosses[1].locked, true)
      eq(rows[1].bosses[1].lockedText, "Mechagon unlocked")
    end)
  end)

  describe("travel", function()
    it("travel with no surviving children dropped", function()
      local t = {
        { title = "Empty fly", steps = {
          { title = "Deeper fly", steps = {
            kill("Owned", { { mount = 1, boss = "A" } }),
          } },
        } },
        { title = "No steps" },
        { title = "Kept fly", steps = { kill("Open", { { mount = 2, boss = "B" } }) } },
      }
      local rows = load().Route.Build(t, ctx({ isOwned = function(id) return id == 1 end }))
      eq(titles(rows), { "Kept fly", "Open" })
    end)

    it("output is the depth-first flattening with depth and key", function()
      local t = {
        { title = "T1", steps = {
          kill("K1", { { mount = 1, boss = "A" } }),
          { title = "T2", steps = { kill("K2", { { mount = 2, boss = "B" } }) } },
        } },
        kill("K3", { { mount = 3, boss = "C" } }, { notes = "n3" }),
      }
      local rows = load().Route.Build(t, ctx())
      eq(titles(rows), { "T1", "K1", "T2", "K2", "K3" })
      local depths, kinds, keys = {}, {}, {}
      for i, r in ipairs(rows) do depths[i], kinds[i], keys[i] = r.depth, r.kind, r.key end
      eq(depths, { 0, 1, 1, 2, 0 })
      eq(kinds, { "travel", "kill", "travel", "kill", "kill" })
      eq(keys, { "1", "1.1", "1.2", "1.2.1", "2" })
      eq(rows[5].notes, "n3")
    end)
  end)

  describe("state", function()
    local t = { kill("K", { { mount = 1, boss = "A" }, { mount = 2, boss = "B" } }) }

    it("done kill hidden unless showCompleted", function()
      local ns = load()
      local c = ctx({ stateOf = stateMap({ [1] = "done", [2] = "manual-done" }) })
      eq(#ns.Route.Build(t, c), 0)
      c.showCompleted = true
      local rows = ns.Route.Build(t, c)
      eq(#rows, 1)
      eq(rows[1].state, "done")
      eq(rows[1].auto, true)
    end)

    it("all manual-done is done but not auto", function()
      local c = ctx({ showCompleted = true, stateOf = stateMap({ [1] = "manual-done", [2] = "manual-done" }) })
      local rows = load().Route.Build(t, c)
      eq(rows[1].state, "done")
      eq(rows[1].auto, false)
    end)

    it("mixed done and manual-open is manual", function()
      local c = ctx({ stateOf = stateMap({ [1] = "done", [2] = "manual-open" }) })
      local rows = load().Route.Build(t, c)
      eq(rows[1].state, "manual")
    end)

    it("done and open is open", function()
      local c = ctx({ stateOf = stateMap({ [1] = "done", [2] = "open" }) })
      local rows = load().Route.Build(t, c)
      eq(rows[1].state, "open")
      eq(rows[1].auto, false)
    end)

    it("travel over only done kills is dropped unless showCompleted", function()
      local tree = { { title = "Fly", steps = t } }
      local ns = load()
      local c = ctx({ stateOf = stateMap({ [1] = "done", [2] = "done" }) })
      eq(#ns.Route.Build(tree, c), 0)
      c.showCompleted = true
      local rows = ns.Route.Build(tree, c)
      eq(titles(rows), { "Fly", "K" })
      eq(rows[1].state, "done")
    end)
  end)

  describe("holidays", function()
    it("holiday steps first", function()
      local t = { kill("Raid", { { mount = 1, boss = "A" } }) }
      local c = ctx({
        holidaySteps = { { title = "Queue for Coren Direbrew (Brewfest)", mounts = { 202, 226 } } },
        isOwned = function(id) return id == 226 end,
      })
      local rows = load().Route.Build(t, c)
      eq(titles(rows), { "Queue for Coren Direbrew (Brewfest)", "Raid" })
      eq(rows[1].depth, 0)
      eq(rows[1].kind, "kill")
      eq(#rows[1].bosses, 1)
      eq(rows[1].bosses[1].mount, 202)
      ok(rows[1].key ~= rows[2].key, "holiday key differs from tree keys")
    end)

    it("fully owned or done holiday step is dropped", function()
      local c = ctx({
        holidaySteps = {
          { title = "Owned", mounts = { 1 } },
          { title = "Done", mounts = { 2 } },
        },
        isOwned = function(id) return id == 1 end,
        stateOf = stateMap({ [2] = "done" }),
      })
      eq(#load().Route.Build({}, c), 0)
    end)
  end)

  describe("stateOf", function()
    it("receives the mount and the route boss name (nil on holiday steps)", function()
      local calls = {}
      local c = ctx({
        stateOf = function(id, boss) calls[#calls + 1] = { id, boss }; return "open" end,
        holidaySteps = { { title = "Holiday", mounts = { 5 } } },
      })
      load().Route.Build({ kill("VoA", { { mount = 286, boss = "Koralon" } }) }, c)
      eq(calls, { { 5, nil }, { 286, "Koralon" } })
    end)
  end)
end)
