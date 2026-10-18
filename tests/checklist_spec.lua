-- Checklist.Build / Checklist.Rows (Logic/Checklist.lua): this character's
-- daily / weekly lockout checklist from the route tree plus spec'd mounts the
-- route does not list, with injected spec / state / gate lookups.

local function load()
  return load_addon({ "Core/Locale.lua", "Logic/Lockouts.lua", "Logic/Checklist.lua" }).Checklist
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
    eq(load().Build({}), { daily = {}, weekly = {}, camp = {} })
  end)
end)

describe("Checklist.Build repeatable content", function()
  it("leaves out repeatable no-lockout specs (they stay route steps only)", function()
    local base = load().Build(ctxFor())
    local function has(out, id)
      for _, list in pairs(out) do
        for _, e in ipairs(list) do if e.id == id then return true end end
      end
      return false
    end
    local any
    for _, list in pairs(base) do if list[1] then any = list[1] end end
    ok(any, "the test data lists something")
    local out = load().Build(ctxFor({
      specFor = function(id, boss)
        if id == any.id then return { manual = true, reset = "daily", repeatable = true } end
        if boss and BOSS_SPECS[boss] then return BOSS_SPECS[boss] end
        return SPECS[id]
      end,
    }))
    eq(has(out, any.id), false, "repeatable: not on the checklist")
  end)
end)

describe("Checklist.Rows", function()
  local function built()
    return load().Build(ctxFor({
      stateOf = function(id) return id == 9 and "done" or "open" end,
    }))
  end

  local function shape(rows)
    local out = {}
    for _, r in ipairs(rows) do
      if r.header then
        out[#out + 1] = r.key .. " (" .. r.owned .. "/" .. r.total .. ")" .. (r.collapsed and " +" or "")
      else
        out[#out + 1] = tostring(r.entry.key) .. "@" .. tostring(r.depth)
      end
    end
    return out
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
    eq(rows[4].id, 2)
    eq(rows[4].entry.key, 2)
    eq(rows[5].id, 1)
    eq(rows[6].key, "checklist|weekly", "the done entry (9) is not listed")
    eq(rows[6].owned, 0)
    eq(rows[6].total, 4)
    eq(#rows, 13)
  end)

  it("splits each reset group into expansion sub-headers (Data.Expansions order) with done/total", function()
    local rows = load().Rows(built())
    eq(shape(rows), {
      "checklist|daily (1/3)",
      -- Classic holds only the done Ram: no shown entry, no sub-header.
      "checklist|daily|Cataclysm (0/2)", "checklist|daily|Cataclysm|dungeons (0/2)", "2@3", "1@3",
      "checklist|weekly (0/4)",
      -- Classic holds only "Other" entries: no category level.
      "checklist|weekly|Classic (0/2)", "12@2", "8@2",
      "checklist|weekly|Wrath of the Lich King (0/2)", "checklist|weekly|Wrath of the Lich King|raids (0/2)",
      "3@3", "3@Koralon@3",
    })
    local sub = rows[2]
    eq(sub.header, true)
    eq(sub.depth, 2)
    eq(sub.reset, "daily")
    eq(sub.exp, "Cataclysm")
    eq(sub.text, "Cataclysm")
    eq(sub.collapsed, false)
  end)

  it("sub-header counts include done entries of that expansion", function()
    local rows = load().Rows(load().Build(ctxFor({
      stateOf = function(id) return id == 12 and "manual-done" or "open" end,
    })))
    local classic
    for _, r in ipairs(rows) do if r.key == "checklist|weekly|Classic" then classic = r end end
    eq(classic.owned, 1)
    eq(classic.total, 2)
  end)

  it("hides a collapsed group's entries but keeps its header and counts", function()
    local rows = load().Rows(built(), { collapsed = { ["checklist|daily"] = true } })
    eq(rows[1].collapsed, true)
    eq(rows[1].total, 3)
    eq(rows[2].key, "checklist|weekly")
    eq(#rows, 9)
  end)

  it("a collapsed sub-header hides only its own entries", function()
    local rows = load().Rows(built(), { collapsed = { ["checklist|weekly|Classic"] = true } })
    eq(shape(rows), {
      "checklist|daily (1/3)",
      "checklist|daily|Cataclysm (0/2)", "checklist|daily|Cataclysm|dungeons (0/2)", "2@3", "1@3",
      "checklist|weekly (0/4)",
      "checklist|weekly|Classic (0/2) +",
      "checklist|weekly|Wrath of the Lich King (0/2)", "checklist|weekly|Wrath of the Lich King|raids (0/2)",
      "3@3", "3@Koralon@3",
    })
  end)

  it("done entries disappear on their own; the header still counts them", function()
    local rows = load().Rows(built())
    eq(rows[1].owned, 1)
    eq(rows[1].total, 3)
    eq(rows[4].id, 2)
    eq(rows[5].id, 1)
    eq(rows[6].key, "checklist|weekly")
  end)

  it("unknown expansions sort after known ones (by name), a missing one last as Other", function()
    local entry = function(id, exp, rank) return { id = id, key = id, done = false, exp = exp, expRank = rank } end
    local rows = load().Rows({ daily = {}, weekly = {
      entry(1, nil, 9), entry(2, "Zeta", 9), entry(3, "Legion", 2), entry(4, "Alpha", 9),
    } })
    eq(shape(rows), {
      "checklist|weekly (0/4)",
      "checklist|weekly|Legion (0/1)", "3@2",
      "checklist|weekly|Alpha (0/1)", "4@2",
      "checklist|weekly|Zeta (0/1)", "2@2",
      "checklist|weekly|Other (0/1)", "1@2",
    })
    eq(rows[#rows - 1].text, "Other")
  end)

  -- F17: event rares' live status (opts.status(entry) -> text or nil).
  it("opts.status: entry rows carry their line; a header gets it when every open entry under it shares it", function()
    local entry = function(id, exp, cat) return { id = id, key = id, done = false, exp = exp, expRank = 1, category = cat } end
    local lines = { [1] = "Uldum: Aqir assault", [2] = "Uldum: Aqir assault", [3] = "Arathi warfront: Active" }
    local list = { entry(1, "Battle for Azeroth", "rares"), entry(2, "Battle for Azeroth", "rares"),
      entry(4, "Legion", "rares"), entry(5, "Legion", "dungeons") }
    local done = { id = 6, key = 6, done = true, exp = "Battle for Azeroth", expRank = 1, category = "rares" }
    list[#list + 1] = done
    local rows = load().Rows({ daily = list, weekly = {} }, { status = function(e) return lines[e.id] end })
    local byKey, byId = {}, {}
    for _, r in ipairs(rows) do
      if r.header then byKey[r.key] = r else byId[r.id] = r end
    end
    eq(byId[1].status, "Uldum: Aqir assault")
    eq(byId[4].status, nil, "no event, no line")
    eq(byKey["checklist|daily|Battle for Azeroth|rares"].status, "Uldum: Aqir assault",
      "both open rares share it (the done one is not listed)")
    eq(byKey["checklist|daily|Battle for Azeroth"].status, "Uldum: Aqir assault", "the expansion too")
    eq(byKey["checklist|daily|Legion|rares"].status, nil)
    eq(byKey["checklist|daily"].status, nil, "mixed under the reset header")

    -- A third rare with another event: the category no longer shares one line.
    list[#list + 1] = entry(3, "Battle for Azeroth", "rares")
    rows = load().Rows({ daily = list, weekly = {} }, { status = function(e) return lines[e.id] end })
    for _, r in ipairs(rows) do
      if r.header then eq(r.status, nil, r.key) end
    end
    -- Without opts.status nothing changes.
    for _, r in ipairs(load().Rows({ daily = list, weekly = {} })) do eq(r.status, nil) end
  end)

  it("stays flat when Other is the only expansion (as the list sections do)", function()
    local rows = load().Rows({ daily = {}, weekly = { { id = 1, key = 1, done = false } } })
    eq(#rows, 2)
    eq(rows[1].key, "checklist|weekly")
    eq(rows[1].text, "Weekly")
    eq(rows[2].id, 1)
    eq(rows[2].depth, nil)
    eq(load().Rows({ daily = {}, weekly = {} }), {})
  end)

  it("Build records each entry's expansion: the spec's exp, else the mount's", function()
    local out = load().Build(ctxFor({
      bossLockouts = BOSS_SPECS,
      specFor = function(id, boss)
        if boss == "Koralon" then return { instance = 2, boss = "Koralon", difficulties = { 3, 4 },
          reset = "weekly", exp = "Classic" } end
        return SPECS[id]
      end,
    }))
    local byKey = {}
    for _, e in ipairs(out.weekly) do byKey[e.key] = e end
    eq(byKey[3].exp, "Wrath of the Lich King")
    eq(byKey["3@Koralon"].exp, "Classic")
  end)

  it("counts the entries left to do", function()
    eq(load().Remaining(built()), 6)
    eq(load().Remaining({ daily = {}, weekly = {} }), 0)
  end)
end)

-- F10: one entry per lockout. Mounts sharing one lockout (a per-boss spec
-- such as a synthetic "Grand Hoarder" row set, an identical instance spec, one quest / LFG
-- flag) become a single entry listing its mounts; manual specs never group.
describe("Checklist.Build lockout groups", function()
  local GROUP_MOUNTS = {
    [51] = { name = "Deathcharger", exp = "Classic" },
    [52] = { name = "Bronze Drake", exp = "Wrath of the Lich King" },
    [53] = { name = "Horde Raptor", exp = "Cataclysm" },
    [54] = { name = "Blazing Drake", exp = "Cataclysm" },
    [55] = { name = "Handmaiden", exp = "Cataclysm" },
    [56] = { name = "Experiment", exp = "Cataclysm" },
    [57] = { name = "Ram One", exp = "Classic" },
    [58] = { name = "Ram Two", exp = "Classic" },
    [59] = { name = "Hand A", exp = "Classic" },
    [60] = { name = "Hand B", exp = "Classic" },
    [61] = { name = "Rare One", exp = "Legion" },
    [62] = { name = "Rare Two", exp = "Legion" },
  }
  local GROUP_SPECS = {
    -- Deathwing: two separate (but equal) tables -> one lockout.
    [54] = { instance = 967, boss = "Madness of Deathwing", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" },
    [55] = { instance = 967, boss = "Madness of Deathwing", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" },
    -- Same instance, other boss: its own lockout.
    [56] = { instance = 967, boss = "Ultraxion", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" },
    [57] = { lfg = 287, reset = "daily" },
    [58] = { lfg = 287, reset = "daily" },
    [59] = { manual = true, reset = "weekly" },
    [60] = { manual = true, reset = "weekly" },
    [61] = { quest = 900, reset = "weekly" },
    [62] = { quest = 900, reset = "weekly" },
  }
  local GROUP_BOSS = {
    Hoarder = { instance = 2579, boss = "Grand Hoarder", difficulties = { 23 }, reset = "weekly" },
  }
  local GROUP_TREE = {
    {
      title = "Run Hoard Vault (Dungeon)",
      bosses = {
        { mount = 51, boss = "Hoarder" },
        { mount = 52, boss = "Hoarder" },
        { mount = 53, boss = "Hoarder", horde = true },
      },
    },
    { title = "Run Dragon Soul (Raid)", bosses = {
      { mount = 56, boss = "Ultraxion" },
      { mount = 54, boss = "Madness of Deathwing" },
      { mount = 55, boss = "Madness of Deathwing" },
    } },
  }

  local function groupCtx(over)
    local ctx = {
      tree = GROUP_TREE,
      mounts = GROUP_MOUNTS,
      bossLockouts = GROUP_BOSS,
      specFor = function(id, boss)
        if boss and GROUP_BOSS[boss] then return GROUP_BOSS[boss] end
        return GROUP_SPECS[id]
      end,
      gate = function() return false end,
      faction = "Alliance",
      holidays = { brewfest = { title = "Brewfest", mounts = { 57, 58 } } },
      active = { brewfest = true },
      expansions = EXPANSIONS,
      keyOf = function(id, boss)
        if boss and GROUP_BOSS[boss] then return id .. "@" .. boss end
        return id
      end,
    }
    for k, v in pairs(over or {}) do ctx[k] = v end
    return ctx
  end

  local function find(list, pred)
    for _, e in ipairs(list) do if pred(e) then return e end end
    return nil
  end

  it("a per-boss spec shared by several route rows is one entry listing its mounts", function()
    local out = load().Build(groupCtx())
    local hoard = find(out.weekly, function(e) return e.boss == "Hoarder" end)
    ok(hoard, "Hoarder listed")
    eq(hoard.id, 51, "the first mount (icon / click / waypoint)")
    eq(hoard.mounts, { 51, 52 }, "the Horde-only row stays out for an Alliance character")
    eq(hoard.names, { "Deathcharger", "Bronze Drake" })
    eq(hoard.key, "51@Hoarder", "the first member's tick key")
    eq(hoard.grouped, true)
    eq(hoard.name, "Hoarder", "named after the boss")
    eq(hoard.title, "Run Hoard Vault (Dungeon)")
    local n = 0
    for _, e in ipairs(out.weekly) do if e.boss == "Hoarder" then n = n + 1 end end
    eq(n, 1, "one row per lockout")
  end)

  it("header totals count lockouts, not mounts", function()
    local C = load()
    local rows = C.Rows(C.Build(groupCtx()))
    local weekly
    for _, r in ipairs(rows) do if r.key == "checklist|weekly" then weekly = r end end
    -- Hoarder, Deathwing (54 + 55), Ultraxion, Rare One + Two, Hand A, Hand B.
    eq(weekly.total, 6)
  end)

  it("identical instance specs group; a different boss stays separate", function()
    local out = load().Build(groupCtx())
    local dw = find(out.weekly, function(e) return e.id == 54 end)
    eq(dw.mounts, { 54, 55 })
    eq(dw.name, "Madness of Deathwing")
    local ul = find(out.weekly, function(e) return e.id == 56 end)
    eq(ul.mounts, { 56 })
    eq(ul.grouped, false)
    eq(ul.name, "Experiment", "single-mount entries keep the mount name")
    eq(find(out.weekly, function(e) return e.id == 55 end), nil, "55 only inside the Deathwing entry")
  end)

  it("quest and LFG flags group by their ID; manual specs never group", function()
    local out = load().Build(groupCtx())
    local rams = find(out.daily, function(e) return e.id == 57 end)
    eq(rams.mounts, { 57, 58 })
    eq(rams.name, "Brewfest", "no boss: the holiday's title")
    eq(#out.daily, 1)
    local rare = find(out.weekly, function(e) return e.id == 61 end)
    eq(rare.mounts, { 61, 62 })
    eq(rare.name, "Rare One", "no boss, no holiday: the first mount's name")
    eq(find(out.weekly, function(e) return e.id == 59 end).mounts, { 59 })
    eq(find(out.weekly, function(e) return e.id == 60 end).mounts, { 60 })
  end)

  it("owned members drop out of the list; the next one leads", function()
    local out = load().Build(groupCtx({ gate = function(id) return id == 51 end }))
    local hoard = find(out.weekly, function(e) return e.boss == "Hoarder" end)
    eq(hoard.id, 52)
    eq(hoard.mounts, { 52 })
    eq(hoard.grouped, false, "one mount left: a plain entry")
    eq(hoard.name, "Bronze Drake")
    eq(hoard.key, "52@Hoarder")
  end)

  it("all members owned or gated: the entry is gone", function()
    local out = load().Build(groupCtx({ gate = function(id)
      if id == 51 then return true end
      if id == 52 then return nil end
      return false
    end }))
    eq(find(out.weekly, function(e) return e.boss == "Hoarder" end), nil)
  end)

  it("the faction rule applies per member", function()
    local out = load().Build(groupCtx({ faction = "Horde" }))
    local hoard = find(out.weekly, function(e) return e.boss == "Hoarder" end)
    eq(hoard.mounts, { 51, 52, 53 })
  end)

  it("one lockout, one state: the first member's", function()
    local out = load().Build(groupCtx({ stateOf = function(id) return id == 51 and "done" or "open" end }))
    local hoard = find(out.weekly, function(e) return e.boss == "Hoarder" end)
    eq(hoard.done, true)
    eq(hoard.auto, true)
  end)

  it("a spec's exp sorts the entry before the members' own expansion", function()
    local boss = { Hoarder = { instance = 2579, boss = "Grand Hoarder", difficulties = { 23 }, reset = "weekly",
      exp = "Cataclysm" } }
    local out = load().Build(groupCtx({
      bossLockouts = boss,
      specFor = function(id, b)
        if b and boss[b] then return boss[b] end
        return GROUP_SPECS[id]
      end,
    }))
    local hoard = find(out.weekly, function(e) return e.boss == "Hoarder" end)
    eq(hoard.expRank, 3, "Cataclysm (spec), not Classic (first member)")
    -- Hand A / Hand B are Classic manual rows: they now come first.
    eq(out.weekly[1].id, 59)
    eq(out.weekly[2].id, 60)
    local ul = find(out.weekly, function(e) return e.id == 56 end)
    eq(ul.expRank, 3, "no spec exp: the mount's")
  end)

  it("without bossLockouts the per-boss spec groups by its signature", function()
    local out = load().Build(groupCtx({ bossLockouts = false }))
    local hoard = find(out.weekly, function(e) return e.boss == "Hoarder" end)
    eq(hoard.mounts, { 51, 52 })
  end)
end)

describe("Checklist.LockoutKey", function()
  it("names one lockout: per-boss spec, instance signature, quest, LFG; manual -> nil", function()
    local K = load().LockoutKey
    local boss = { Hoarder = { instance = 1, boss = "D", difficulties = { 23 }, reset = "weekly" } }
    eq(K(boss.Hoarder, "Hoarder", boss), "boss:Hoarder")
    local a = { instance = 967, boss = "X", difficulties = { { 3, 4 }, 5 }, reset = "weekly" }
    local b = { instance = 967, boss = "X", difficulties = { { 3, 4 }, 5 }, reset = "weekly" }
    local c = { instance = 967, boss = "X", difficulties = { { 3, 4 } }, reset = "weekly" }
    eq(K(a, nil, boss), K(b, "Other", boss))
    ok(K(a) ~= K(c), "other difficulties: other lockout")
    eq(K({ quest = 5, reset = "weekly" }), "quest:5")
    eq(K({ lfg = 287, reset = "daily" }), "lfg:287")
    eq(K({ manual = true, reset = "weekly" }), nil)
    eq(K(nil), nil)
  end)
end)

-- F14: reset -> expansion -> category -> entries. Categories: Raids,
-- Dungeons, World bosses, Rares, Holidays, Other.
describe("Checklist.Category", function()
  local C = load()

  it("instance specs: Raids when any difficulty is a raid one, else Dungeons", function()
    for _, d in ipairs({ 3, 4, 5, 6, 7, 9, 14, 15, 16, 17, 33 }) do
      eq(C.Category({ instance = 1, difficulties = { d } }, {}), "raids", "difficulty " .. d)
    end
    eq(C.Category({ instance = 1, difficulties = { { 3, 4, 5, 6 } } }, {}), "raids", "nested lockout group")
    eq(C.Category({ instance = 1, difficulties = { 2, 16 } }, {}), "raids", "any raid difficulty")
    for _, d in ipairs({ 1, 2, 8, 23 }) do
      eq(C.Category({ instance = 1, difficulties = { d } }, { section = "raid" }), "dungeons", "difficulty " .. d)
    end
    eq(C.Category({ instance = 1 }, { section = "raid" }), "dungeons", "no difficulties: a dungeon")
  end)

  it("the Vault of Archavon per-boss spec is a raid", function()
    eq(C.Category({ instance = 624, boss = "Koralon", difficulties = { 3, 4 }, reset = "weekly" },
      { section = "world" }), "raids")
  end)

  it("manual / quest specs: the mount's journal section", function()
    -- Midnight dungeons: instance IDs unknown, hand ticks.
    eq(C.Category({ manual = true, reset = "weekly" }, { section = "dungeon", group = "Dungeon Drop" }), "dungeons")
    eq(C.Category({ manual = true, reset = "weekly" }, { section = "raid", group = "Raid Drop" }), "raids")
    eq(C.Category({ quest = 1 }, { section = "dungeon" }), "dungeons")
  end)

  it("world bosses and rares by SimpleArmory group", function()
    eq(C.Category({ quest = 1 }, { section = "world", group = "World Boss" }), "worldbosses")
    eq(C.Category({ quest = 1 }, { section = "world", group = "Rare Spawn" }), "rares")
    eq(C.Category({ quest = 1 }, { section = "world", group = "Necrolord Rare Spawn" }), "rares")
    eq(C.Category({ quest = 1 }, { section = "activity", group = "Warfront: Arathi" }), "rares")
    eq(C.Category({ quest = 1 }, { section = "activity", group = "Assault: Uldum" }), "rares")
    eq(C.Category({ quest = 1 }, { section = "world", group = "Tormentors" }), "other")
    eq(C.Category({ quest = 1 }, { section = "activity", group = "Garrison" }), "other")
    eq(C.Category({ quest = 1 }, { section = "vendor", group = "Necrolord Vendor" }), "other")
  end)

  it("LFG specs and holiday mounts: Holidays", function()
    eq(C.Category({ lfg = 287, reset = "daily" }, { tab = "holiday", section = "brewfest" }), "holidays")
    eq(C.Category({ lfg = 285, reset = "daily" }, {}), "holidays", "LFG flag alone")
    eq(C.Category({ quest = 9 }, {}, "brewfest"), "holidays", "a holiday's own mount")
    eq(C.Category({ quest = 9 }, { tab = "holiday", section = "lunarfestival" }), "holidays")
  end)

  it("anything else (and no data) is Other", function()
    eq(C.Category({ manual = true }, {}), "other")
    eq(C.Category(nil, nil), "other")
    eq(C.Category({ quest = 1 }, { section = "quest", group = "Quest" }), "other")
  end)

  it("lists the categories in order with their labels", function()
    eq(C.CATEGORIES, { "raids", "dungeons", "worldbosses", "rares", "holidays", "other" })
    eq(C.CategoryLabel("raids"), "Raids")
    eq(C.CategoryLabel("dungeons"), "Dungeons")
    eq(C.CategoryLabel("worldbosses"), "World bosses")
    eq(C.CategoryLabel("rares"), "Rares")
    eq(C.CategoryLabel("holidays"), "Holidays")
    eq(C.CategoryLabel("other"), "Other")
  end)

  it("Build records each entry's category", function()
    local out = load().Build(ctxFor())
    local byKey = {}
    for _, reset in ipairs({ "daily", "weekly" }) do
      for _, e in ipairs(out[reset]) do byKey[e.key] = e.category end
    end
    eq(byKey[9], "holidays")
    eq(byKey[1], "dungeons")
    eq(byKey[3], "raids")
    eq(byKey["3@Koralon"], "raids")
    eq(byKey[8], "other")
    eq(byKey[12], "other")
  end)
end)

describe("Checklist.Rows categories", function()
  local function e(id, exp, rank, category, done)
    return { id = id, key = id, exp = exp, expRank = rank, category = category, done = done == true }
  end

  local function shape(rows)
    local out = {}
    for _, r in ipairs(rows) do
      if r.header then
        out[#out + 1] = r.key .. " (" .. r.owned .. "/" .. r.total .. ")" .. (r.collapsed and " +" or "")
          .. " d" .. r.depth
      else
        out[#out + 1] = tostring(r.entry.key) .. "@" .. tostring(r.depth)
      end
    end
    return out
  end

  local BUILT = { daily = {}, weekly = {
    e(1, "Shadowlands", 9, "other"),
    e(2, "Shadowlands", 9, "dungeons"),
    e(3, "Shadowlands", 9, "raids"),
    e(4, "Shadowlands", 9, "holidays"),
    e(5, "Shadowlands", 9, "rares"),
    e(6, "Shadowlands", 9, "worldbosses"),
    e(7, "Shadowlands", 9, "dungeons", true),
    e(8, "Legion", 7, "dungeons"),
    e(9, "Legion", 7, nil), -- no category: Other
  } }

  it("nests reset -> expansion -> category (Raids, Dungeons, World bosses, Rares, Holidays, Other)", function()
    eq(shape(load().Rows(BUILT)), {
      "checklist|weekly (1/9) d1",
      "checklist|weekly|Legion (0/2) d2",
      "checklist|weekly|Legion|dungeons (0/1) d3", "8@3",
      "checklist|weekly|Legion|other (0/1) d3", "9@3",
      "checklist|weekly|Shadowlands (1/7) d2",
      "checklist|weekly|Shadowlands|raids (0/1) d3", "3@3",
      "checklist|weekly|Shadowlands|dungeons (1/2) d3", "2@3",
      "checklist|weekly|Shadowlands|worldbosses (0/1) d3", "6@3",
      "checklist|weekly|Shadowlands|rares (0/1) d3", "5@3",
      "checklist|weekly|Shadowlands|holidays (0/1) d3", "4@3",
      "checklist|weekly|Shadowlands|other (0/1) d3", "1@3",
    })
  end)

  it("category headers carry their label, reset, expansion and category", function()
    local rows = load().Rows(BUILT)
    local h = rows[3]
    eq(h.header, true)
    eq(h.text, "Dungeons")
    eq(h.reset, "weekly")
    eq(h.exp, "Legion")
    eq(h.category, "dungeons")
    eq(h.collapsed, false)
  end)

  it("a lone category still shows its header; a lone Other does not", function()
    local rows = load().Rows({ daily = {}, weekly = {
      e(1, "Legion", 7, "dungeons"), e(2, "Legion", 7, "dungeons"), e(3, "Classic", 1, "other"),
    } })
    eq(shape(rows), {
      "checklist|weekly (0/3) d1",
      "checklist|weekly|Classic (0/1) d2", "3@2",
      "checklist|weekly|Legion (0/2) d2",
      "checklist|weekly|Legion|dungeons (0/2) d3", "1@3", "2@3",
    })
  end)

  it("a category with only done entries gets no header (as expansions)", function()
    local rows = load().Rows({ daily = {}, weekly = {
      e(1, "Legion", 7, "dungeons", true), e(2, "Legion", 7, "raids"),
    } })
    eq(shape(rows), {
      "checklist|weekly (1/2) d1",
      "checklist|weekly|Legion (1/2) d2",
      "checklist|weekly|Legion|raids (0/1) d3", "2@3",
    })
  end)

  it("without an expansion level the categories hang under the reset header", function()
    local rows = load().Rows({ daily = { e(1, nil, 99, "holidays"), e(2, nil, 99, "holidays") }, weekly = {} })
    eq(shape(rows), {
      "checklist|daily (0/2) d1",
      "checklist|daily|Other|holidays (0/2) d2", "1@2", "2@2",
    })
  end)

  it("a collapsed category hides only its own entries", function()
    local rows = load().Rows(BUILT, { collapsed = { ["checklist|weekly|Shadowlands|raids"] = true } })
    local s = shape(rows)
    eq(s[8], "checklist|weekly|Shadowlands|raids (0/1) + d3")
    eq(s[9], "checklist|weekly|Shadowlands|dungeons (1/2) d3")
    -- A collapsed expansion hides its categories too.
    rows = load().Rows(BUILT, { collapsed = { ["checklist|weekly|Shadowlands"] = true } })
    eq(shape(rows)[#rows], "checklist|weekly|Shadowlands (1/7) + d2")
  end)

  it("filters drop hidden categories from the rows and every count", function()
    local rows = load().Rows(BUILT, { filters = { raids = false, other = false, dungeons = false } })
    eq(shape(rows), {
      "checklist|weekly (0/3) d1",
      "checklist|weekly|Shadowlands (0/3) d2",
      "checklist|weekly|Shadowlands|worldbosses (0/1) d3", "6@3",
      "checklist|weekly|Shadowlands|rares (0/1) d3", "5@3",
      "checklist|weekly|Shadowlands|holidays (0/1) d3", "4@3",
    })
  end)

  it("a reset group with every entry filtered out disappears", function()
    local rows = load().Rows({ daily = { e(1, "Legion", 7, "rares") }, weekly = { e(2, "Legion", 7, "raids") } },
      { filters = { rares = false } })
    eq(rows[1].key, "checklist|weekly")
    eq(#rows, 4)
  end)

  it("an entry without a category counts as Other for the filter", function()
    local rows = load().Rows({ daily = {}, weekly = { e(1, "Legion", 7, nil), e(2, "Legion", 7, "raids") } },
      { filters = { other = false } })
    eq(shape(rows), {
      "checklist|weekly (0/1) d1",
      "checklist|weekly|Legion (0/1) d2",
      "checklist|weekly|Legion|raids (0/1) d3", "2@3",
    })
  end)

  it("Remaining honours the filters", function()
    eq(load().Remaining(BUILT), 8)
    eq(load().Remaining(BUILT, { raids = false, dungeons = false }), 5)
    eq(load().Remaining(BUILT, {}), 8)
  end)

  it("Shown: a category is shown unless its filter is false", function()
    local C = load()
    eq(C.Shown(nil, "raids"), true)
    eq(C.Shown({}, "raids"), true)
    eq(C.Shown({ raids = false }, "raids"), false)
    eq(C.Shown({ raids = false }, "dungeons"), true)
    eq(C.Shown({ other = false }, nil), false, "nil category = other")
  end)
end)

describe("Checklist rare spawns with no lockout (camp specs)", function()
  local CAMP_MOUNTS = {
    [21] = { name = "Garn Nighthowl", exp = "Warlords of Draenor", group = "Rare Spawn" },
    [22] = { name = "Great Greytusk", exp = "Warlords of Draenor", group = "Rare Spawn" },
    [23] = { name = "Sunhide Gronnling", exp = "Warlords of Draenor", group = "Rare Spawn" },
    [24] = { name = "Grey Riding Camel", exp = "Cataclysm", group = "Rare Spawn" },
    [25] = { name = "Fabious", exp = "Battle for Azeroth", group = "Rare Spawn" },
    [26] = { name = "Owned Rare", exp = "Cataclysm", group = "Rare Spawn" },
    [27] = { name = "Daily Rare", exp = "Cataclysm", group = "Rare Spawn" },
  }
  local CAMP_SPECS = {
    [21] = { camp = true, zone = "Frostfire Ridge" },
    [22] = { camp = true, zone = "Frostfire Ridge" },
    [23] = { camp = true, zone = "Gorgrond" },
    [24] = { camp = true, zone = "Feralas" },
    [25] = { camp = true },
    [26] = { camp = true, zone = "Feralas" },
    [27] = { quest = 5, reset = "daily" },
  }
  local EXPS = { "Cataclysm", "Warlords of Draenor", "Battle for Azeroth" }
  local function build(over)
    local ctx = {
      mounts = CAMP_MOUNTS, expansions = EXPS,
      specFor = function(id) return CAMP_SPECS[id] end,
      -- A stray hand tick never makes a camp row done.
      stateOf = function(id) return id == 27 and "open" or "manual-done" end,
      gate = function(id) return id == 26 end,
    }
    for k, v in pairs(over or {}) do ctx[k] = v end
    return load().Build(ctx)
  end
  local function shape(rows)
    local out = {}
    for _, r in ipairs(rows) do
      if r.header then
        local count = r.left and ("(" .. r.left .. " left)") or ("(" .. tostring(r.owned) .. "/" .. tostring(r.total) .. ")")
        out[#out + 1] = r.key .. " " .. count .. " d" .. r.depth
      else
        out[#out + 1] = tostring(r.entry.key) .. "@" .. tostring(r.depth)
      end
    end
    return out
  end

  it("Build files camp specs in their own list: never done, no reset, category camp, the spec's zone", function()
    local out = build()
    eq(ids(out.daily), { 27 })
    eq(out.weekly, {})
    eq(ids(out.camp), { 24, 21, 22, 23, 25 }, "expansion order, then zone, then name; owned left out")
    local nighthowl = out.camp[2]
    eq(nighthowl.done, false)
    eq(nighthowl.auto, false)
    eq(nighthowl.state, "camp")
    eq(nighthowl.reset, "camp")
    eq(nighthowl.category, "camp")
    eq(nighthowl.zone, "Frostfire Ridge")
    eq(nighthowl.grouped, false)
    eq(out.camp[5].zone, nil)
  end)

  it("camp specs never group, even with the same zone", function()
    local out = build()
    for _, e in ipairs(out.camp) do eq(#e.mounts, 1) end
    eq(load().LockoutKey({ camp = true, zone = "X" }), nil)
  end)

  it("Rows: a third group after Daily / Weekly, nested expansion -> zone, counting mounts left", function()
    eq(shape(load().Rows(build(), { label = function(r) return r end })), {
      "checklist|daily (0/1) d1",
      "checklist|daily|Cataclysm (0/1) d2",
      "checklist|daily|Cataclysm|rares (0/1) d3", "27@3",
      "checklist|camp (5 left) d1",
      "checklist|camp|Cataclysm (1 left) d2",
      "checklist|camp|Cataclysm|Feralas (1 left) d3", "24@3",
      "checklist|camp|Warlords of Draenor (3 left) d2",
      "checklist|camp|Warlords of Draenor|Frostfire Ridge (2 left) d3", "21@3", "22@3",
      "checklist|camp|Warlords of Draenor|Gorgrond (1 left) d3", "23@3",
      "checklist|camp|Battle for Azeroth (1 left) d2",
      "checklist|camp|Battle for Azeroth|Other (1 left) d3", "25@3",
    })
  end)

  it("Rows: the camp header's text, flags and zone headers' text", function()
    local rows = load().Rows(build())
    local top
    for _, r in ipairs(rows) do if r.key == "checklist|camp" then top = r end end
    eq(top.text, "Rare spawns (no lockout)")
    eq(top.camp, true)
    eq(top.owned, nil, "no done/total: nothing here is ever done")
    eq(top.total, nil)
    for _, r in ipairs(rows) do
      if r.key == "checklist|camp|Warlords of Draenor|Gorgrond" then eq(r.text, "Gorgrond") eq(r.zone, "Gorgrond") end
      if r.key == "checklist|camp|Battle for Azeroth|Other" then eq(r.text, "Other") end
      if r.entry and r.entry.id == 23 then eq(r.camp, true) eq(r.done, false) end
    end
  end)

  it("Rows: collapsed camp, expansion and zone headers hide what is under them", function()
    local C = load()
    eq(shape(C.Rows(build(), { collapsed = { ["checklist|camp"] = true }, filters = { rares = false } })),
      { "checklist|camp (5 left) d1" })
    local rows = shape(C.Rows(build(), { filters = { rares = false }, collapsed = {
      ["checklist|camp|Warlords of Draenor|Frostfire Ridge"] = true, ["checklist|camp|Cataclysm"] = true } }))
    eq(rows, {
      "checklist|camp (5 left) d1",
      "checklist|camp|Cataclysm (1 left) d2",
      "checklist|camp|Warlords of Draenor (3 left) d2",
      "checklist|camp|Warlords of Draenor|Frostfire Ridge (2 left) d3",
      "checklist|camp|Warlords of Draenor|Gorgrond (1 left) d3", "23@3",
      "checklist|camp|Battle for Azeroth (1 left) d2",
      "checklist|camp|Battle for Azeroth|Other (1 left) d3", "25@3",
    })
  end)

  it("the filter key camp hides the group; Remaining counts lockouts only", function()
    local C = load()
    local rows = shape(C.Rows(build(), { filters = { camp = false } }))
    eq(rows[#rows], "27@3")
    eq(C.Remaining(build()), 1, "camp rows are not lockouts")
    eq(C.CampLeft(build()), 5)
    eq(C.CampLeft(build(), { camp = false }), 0)
    eq(C.FILTERS, { "raids", "dungeons", "worldbosses", "rares", "holidays", "other", "camp" })
  end)
end)
