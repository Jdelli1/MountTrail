-- Checklist.Build / Checklist.Rows (Logic/Checklist.lua): this character's
-- daily / weekly lockout checklist from the route tree plus spec'd mounts the
-- route does not list, with injected spec / state / gate lookups.

local function load()
  return load_addon({ "Core/Locale.lua", "Logic/Checklist.lua" }).Checklist
end

local EXPANSIONS = { "Classic", "Wrath of the Lich King", "Cataclysm" }

local MOUNTS = {
  [1] = { name = "Zebra Drake", exp = "Cataclysm" },
  [2] = { name = "Apple Drake", exp = "Cataclysm" },
  [3] = { name = "Mammoth", exp = "Wrath of the Lich King" },
  [4] = { name = "Horde Wolf", exp = "Classic", faction = "Horde" },
  [5] = { name = "Owned Thing", exp = "Classic" },
  [6] = { name = "Gone Thing", exp = "Classic" },
  [7] = { name = "No Spec", exp = "Classic" },
  [8] = { name = "Rare Cat", exp = "Classic" },
  [9] = { name = "Ram", exp = "Classic", tab = "holiday", section = "brewfest" },
  [10] = { name = "Heartbreaker", exp = "Classic" },
  [11] = { name = "Mystery", exp = "Midnight" },
  [12] = { name = "Locked Drake", exp = "Classic" },
}

local SPECS = {
  [1] = { instance = 1, boss = "A", difficulties = { 2 }, reset = "daily" },
  [2] = { instance = 1, boss = "B", difficulties = { 2 }, reset = "daily" },
  [3] = { instance = 2, boss = "Archavon", difficulties = { 3, 4 }, reset = "weekly" },
  [4] = { manual = true, reset = "weekly" },
  [5] = { manual = true, reset = "weekly" },
  [6] = { manual = true, reset = "weekly" },
  [8] = { quest = 100, reset = "weekly" },
  [9] = { lfg = 287, reset = "daily" },
  [10] = { lfg = 288, reset = "daily" },
  [11] = { manual = true, reset = "weekly" },
  [12] = { manual = true, reset = "weekly", requires = { quest = 77, text = "Needs the key" } },
}
local BOSS_SPECS = {
  Koralon = { instance = 2, boss = "Koralon", difficulties = { 3, 4 }, reset = "weekly" },
}

local TREE = {
  {
    title = "Start",
    steps = {
      {
        title = "Run The Vortex (Dungeon)",
        bosses = { { mount = 1, boss = "A" }, { mount = 2, boss = "B" }, { mount = 7, boss = "C" } },
      },
      {
        title = "Run Vault (Raid)",
        bosses = {
          { mount = 3, boss = "Archavon" },
          { mount = 3, boss = "Koralon" },
          { mount = 4, boss = "Wolfboss" },
          { mount = 5, boss = "X" },
          { mount = 6, boss = "Y" },
        },
      },
      -- The same mount under its own spec again (a second route node): one entry.
      { title = "Run The Vortex again", bosses = { { mount = 1, boss = "A2" } } },
      { title = "Alliance only", alliance = true, bosses = { { mount = 12, boss = "Z" } } },
      { title = "Gone", unavailable = true, bosses = { { mount = 11, boss = "Q" } } },
    },
  },
}

local HOLIDAYS = {
  brewfest = { title = "Brewfest", mounts = { 9 }, stepTitle = "Queue for Coren" },
  loveisintheair = { title = "Love", mounts = { 10 }, stepTitle = "Queue for Hummel" },
}

local function ctxFor(over)
  local ctx = {
    tree = TREE,
    mounts = MOUNTS,
    specFor = function(id, boss)
      if boss and BOSS_SPECS[boss] then return BOSS_SPECS[boss] end
      return SPECS[id]
    end,
    stateOf = function() return "open" end,
    gate = function(id, m)
      if m.faction and m.faction ~= "Alliance" then return nil end
      if id == 6 then return nil end -- unobtainable
      return id == 5
    end,
    faction = "Alliance",
    holidays = HOLIDAYS,
    active = { brewfest = true },
    expansions = EXPANSIONS,
    keyOf = function(id, boss)
      if boss and BOSS_SPECS[boss] then return id .. "@" .. boss end
      return id
    end,
    isQuestDone = function() return false end,
  }
  for k, v in pairs(over or {}) do ctx[k] = v end
  return ctx
end

local function keys(list)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = e.key end
  return out
end

local function ids(list)
  local out = {}
  for _, e in ipairs(list) do out[#out + 1] = e.id end
  return out
end

describe("Checklist.Build", function()
  it("groups route (mount, boss) pairs and spec'd extras by reset, sorted by expansion then name", function()
    local out = load().Build(ctxFor())
    -- Daily: the Ram (active holiday, Classic) then the Cataclysm drakes by name.
    eq(keys(out.daily), { 9, 2, 1 })
    -- Weekly: Classic (Locked Drake, Rare Cat: a quest flag the route does
    -- not list), then the Mammoth's two lockouts in route order.
    eq(keys(out.weekly), { 12, 8, 3, "3@Koralon" })
  end)

  it("fills each entry from the route node, the spec and the state", function()
    local out = load().Build(ctxFor())
    local zebra = out.daily[3]
    eq(zebra.id, 1)
    eq(zebra.m, MOUNTS[1])
    eq(zebra.boss, "A", "the first route boss wins")
    eq(zebra.title, "Run The Vortex (Dungeon)")
    eq(zebra.reset, "daily")
    eq(zebra.state, "open")
    eq(zebra.done, false)
    eq(zebra.auto, false)
    local koralon = out.weekly[4]
    eq(koralon.boss, "Koralon")
    eq(koralon.spec, BOSS_SPECS.Koralon, "the per-boss spec governs the row")
    local cat = out.weekly[2]
    eq(cat.boss, nil, "not routed: no boss")
    eq(cat.title, nil)
    eq(cat.holiday, nil)
    eq(out.daily[1].holiday, "brewfest")
  end)

  it("counts a mount once per lockout: the same tick key twice is one entry", function()
    local out = load().Build(ctxFor())
    local n1, n3 = 0, 0
    for _, e in ipairs(out.daily) do if e.id == 1 then n1 = n1 + 1 end end
    for _, e in ipairs(out.weekly) do if e.id == 3 then n3 = n3 + 1 end end
    eq(n1, 1, "mount 1 under bosses A and A2 shares its own spec")
    eq(n3, 2, "Archavon (mount spec) and Koralon (boss spec) are separate lockouts")
  end)

  it("default keyOf: one entry per mount", function()
    local out = load().Build(ctxFor({ keyOf = false }))
    eq(ids(out.weekly), { 12, 8, 3 })
  end)

  it("puts not-done entries first, done ones after (auto = done by the game)", function()
    local states = { [9] = "done", [2] = "manual-done", [1] = "manual-open" }
    local out = load().Build(ctxFor({ stateOf = function(id) return states[id] or "open" end }))
    eq(keys(out.daily), { 1, 9, 2 })
    eq(out.daily[1].done, false)
    eq(out.daily[1].state, "manual-open")
    eq(out.daily[2].done, true)
    eq(out.daily[2].auto, true)
    eq(out.daily[3].done, true)
    eq(out.daily[3].auto, false, "a hand tick is not auto")
  end)

  it("passes the route boss to stateOf (nil for mounts outside the route)", function()
    local seen = {}
    load().Build(ctxFor({ stateOf = function(id, boss)
      seen[#seen + 1] = tostring(id) .. "/" .. tostring(boss)
      return "open"
    end }))
    local set = {}
    for _, s in ipairs(seen) do set[s] = true end
    ok(set["3/Archavon"] and set["3/Koralon"] and set["8/nil"] and set["9/nil"], table.concat(seen, ","))
  end)

  it("drops owned, other-faction and unobtainable mounts (the gate), and mounts without a spec", function()
    local out = load().Build(ctxFor())
    local all = {}
    for _, e in ipairs(out.daily) do all[e.id] = true end
    for _, e in ipairs(out.weekly) do all[e.id] = true end
    ok(not all[5], "owned")
    ok(not all[4], "other faction")
    ok(not all[6], "unobtainable")
    ok(not all[7], "no spec")
  end)

  it("honours the route's faction and unavailable flags without re-adding those mounts", function()
    local out = load().Build(ctxFor({
      faction = "Horde",
      gate = function(id, m)
        if m.faction and m.faction ~= "Horde" then return nil end
        return false
      end,
    }))
    eq(keys(out.weekly), { 6, 4, 5, 8, 3, "3@Koralon" },
      "Horde: the wolf in, the Alliance-only node's drake out; Mystery (unavailable node) out")
  end)

  it("lists holiday mounts only while their holiday is active", function()
    local C = load()
    local out = C.Build(ctxFor({ active = {} }))
    eq(keys(out.daily), { 2, 1 }, "no holiday active")
    out = C.Build(ctxFor({ active = { brewfest = true, loveisintheair = true } }))
    eq(keys(out.daily), { 10, 9, 2, 1 })
    eq(out.daily[1].holiday, "loveisintheair")
    -- A holiday-tab mount counts as its section's holiday even when the
    -- holiday's mount list does not name it.
    local holidays = { brewfest = { title = "Brewfest", mounts = {} }, loveisintheair = HOLIDAYS.loveisintheair }
    out = C.Build(ctxFor({ holidays = holidays, active = {} }))
    eq(keys(out.daily), { 2, 1 })
    out = C.Build(ctxFor({ holidays = holidays, active = { brewfest = true } }))
    eq(keys(out.daily), { 9, 2, 1 })
  end)

  it("skips a routed holiday mount while its holiday is off", function()
    local tree = { { title = "Brewfest step", bosses = { { mount = 9, boss = "Coren" } } } }
    local out = load().Build(ctxFor({ tree = tree, active = {} }))
    eq(keys(out.daily), { 2, 1 })
  end)

  it("sorts unknown and missing expansions after the known ones, then by name and id", function()
    local mounts = {
      [21] = { name = "b" }, [22] = { name = "A", exp = "Unknown" }, [23] = { name = "c", exp = "Classic" },
      [24] = { name = "a", exp = "Cataclysm" }, [25] = { name = "A", exp = "Cataclysm" },
    }
    local specs = {}
    for id in pairs(mounts) do specs[id] = { manual = true, reset = "weekly" } end
    local out = load().Build(ctxFor({
      tree = {}, mounts = mounts, specFor = function(id) return specs[id] end,
    }))
    eq(ids(out.weekly), { 23, 24, 25, 22, 21 })
  end)

  it("sorts by the injected display name when given", function()
    local mounts = { [31] = { name = "Zed" }, [32] = { name = "Alpha" } }
    local out = load().Build(ctxFor({
      tree = {}, mounts = mounts,
      specFor = function() return { manual = true, reset = "daily" } end,
      nameOf = function(id) return id == 31 and "Aardvark" or "Beta" end,
    }))
    eq(ids(out.daily), { 31, 32 })
    eq(out.daily[1].name, "Aardvark")
  end)

  it("marks entries whose spec needs an unlock quest as locked", function()
    local C = load()
    local out = C.Build(ctxFor())
    eq(out.weekly[1].id, 12)
    eq(out.weekly[1].locked, true)
    eq(out.weekly[1].lockedText, "Needs the key")
    eq(out.weekly[2].locked, false)
    out = C.Build(ctxFor({ isQuestDone = function(q) return q == 77 end }))
    eq(out.weekly[1].locked, false)
  end)

  it("files a spec without a reset under daily (as hand ticks expire)", function()
    local out = load().Build(ctxFor({
      tree = {}, mounts = { [41] = { name = "x" } },
      specFor = function() return { manual = true } end,
    }))
    eq(ids(out.daily), { 41 })
    eq(out.daily[1].reset, "daily")
  end)

  it("works with an empty context", function()
    eq(load().Build({}), { daily = {}, weekly = {} })
  end)
end)

describe("Checklist.Rows", function()
  local function built()
    return load().Build(ctxFor({
      stateOf = function(id) return id == 9 and "done" or "open" end,
    }))
  end

  it("emits a header per non-empty reset group (daily first) with done/total and the entries left to do", function()
    local rows = load().Rows(built(), { label = function(reset) return "L:" .. reset end })
    eq(rows[1].header, true)
    eq(rows[1].depth, 1)
    eq(rows[1].key, "checklist|daily")
    eq(rows[1].reset, "daily")
    eq(rows[1].text, "L:daily")
    eq(rows[1].owned, 1, "done count (UI.HeaderText reads owned/total)")
    eq(rows[1].total, 3)
    eq(rows[1].collapsed, false)
    eq(rows[2].id, 2)
    eq(rows[2].entry.key, 2)
    eq(rows[3].id, 1)
    eq(rows[4].key, "checklist|weekly", "the done entry (9) is not listed")
    eq(rows[4].owned, 0)
    eq(rows[4].total, 4)
    eq(#rows, 8)
  end)

  it("hides a collapsed group's entries but keeps its header and counts", function()
    local rows = load().Rows(built(), { collapsed = { ["checklist|daily"] = true } })
    eq(rows[1].collapsed, true)
    eq(rows[1].total, 3)
    eq(rows[2].key, "checklist|weekly")
    eq(#rows, 6)
  end)

  it("done entries disappear on their own; the header still counts them", function()
    local rows = load().Rows(built())
    eq(rows[1].owned, 1)
    eq(rows[1].total, 3)
    eq(rows[2].id, 2)
    eq(rows[3].id, 1)
    eq(rows[4].key, "checklist|weekly")
  end)

  it("leaves out empty groups; the default label is the reset kind", function()
    local rows = load().Rows({ daily = {}, weekly = { { id = 1, key = 1, done = false } } })
    eq(#rows, 2)
    eq(rows[1].key, "checklist|weekly")
    eq(rows[1].text, "Weekly")
    eq(load().Rows({ daily = {}, weekly = {} }), {})
  end)

  it("counts the entries left to do", function()
    eq(load().Remaining(built()), 6)
    eq(load().Remaining({ daily = {}, weekly = {} }), 0)
  end)
end)
