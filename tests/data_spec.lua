describe("data", function()
  local FILES = {"Data/Mounts.lua", "Data/Route.lua", "Data/Lockouts.lua", "Data/Holidays.lua"}

  it("every route boss has a lockout spec or a Rarity quest", function()
    local ns = load_addon({"Data/Mounts.lua","Data/Route.lua","Data/Lockouts.lua"})
    local missing = {}
    local function walk(n) for _,b in ipairs(n.bosses or {}) do
        if not ns.Data.Lockouts[b.mount] and not (ns.Data.Mounts[b.mount] or {}).quest then missing[#missing+1]=b.mount end end
      for _,c in ipairs(n.steps or {}) do walk(c) end end
    for _,n in ipairs(ns.Data.Route) do walk(n) end
    eq(missing, {})
  end)

  -- Spec shape check shared by Lockouts (keyed by mountID) and BossLockouts
  -- (keyed by route boss name). difficulties entries (R9): a number, or a
  -- non-empty table of numbers = one lockout group satisfied by any of its IDs.
  local function checkSpec(id, s, fail, expansions)
    if type(s) ~= "table" then fail(id, "spec not a table") return end
    local kinds = 0
    if s.instance ~= nil then kinds = kinds + 1 end
    if s.quest ~= nil then kinds = kinds + 1 end
    if s.lfg ~= nil then kinds = kinds + 1 end
    if s.manual ~= nil then kinds = kinds + 1 end
    if s.camp ~= nil then kinds = kinds + 1 end
    if kinds ~= 1 then fail(id, "has " .. kinds .. " of instance/quest/lfg/manual/camp") end
    if s.camp ~= nil then
      -- A rare spawn with no kill flag: no reset at all, an optional zone.
      if s.camp ~= true then fail(id, "camp must be true") end
      if s.reset ~= nil then fail(id, "camp spec with a reset") end
      if s.zone ~= nil and (type(s.zone) ~= "string" or s.zone == "") then fail(id, "zone not a string") end
      if s.repeatable ~= nil then fail(id, "camp spec marked repeatable") end
    elseif s.reset ~= "daily" and s.reset ~= "weekly" then
      fail(id, "reset is " .. tostring(s.reset))
    end
    if s.zone ~= nil and s.camp == nil then fail(id, "zone on a non-camp spec") end
    if s.instance ~= nil then
      if type(s.instance) ~= "number" then fail(id, "instance not a number") end
      if type(s.boss) ~= "string" or s.boss == "" then fail(id, "instance spec without boss") end
      if type(s.difficulties) ~= "table" or #s.difficulties == 0 then
        fail(id, "instance spec without difficulties")
      else
        for _, d in ipairs(s.difficulties) do
          if type(d) == "table" then
            if #d == 0 then fail(id, "empty difficulty group") end
            for _, g in ipairs(d) do
              if type(g) ~= "number" then fail(id, "difficulty in group not a number") end
            end
          elseif type(d) ~= "number" then
            fail(id, "difficulty not a number or group")
          end
        end
      end
    else
      if s.boss ~= nil or s.difficulties ~= nil then fail(id, "boss/difficulties on a non-instance spec") end
    end
    if s.quest ~= nil and type(s.quest) ~= "number" then fail(id, "quest not a number") end
    if s.lfg ~= nil and type(s.lfg) ~= "number" then fail(id, "lfg not a number") end
    if s.manual ~= nil and s.manual ~= true then fail(id, "manual must be true") end
    -- category (checklist level, Checklist.CATEGORIES): only on a lockout spec.
    if s.category ~= nil then
      local cats = { raids = true, dungeons = true, worldbosses = true, rares = true, holidays = true, other = true }
      if not cats[s.category] then fail(id, "category " .. tostring(s.category) .. " is not a checklist category") end
      if s.camp ~= nil then fail(id, "category on a camp spec") end
    end
    -- exp (checklist sort order): a Data.Expansions name.
    if s.exp ~= nil then
      local known = false
      for _, e in ipairs(expansions or {}) do if e == s.exp then known = true end end
      if not known then fail(id, "exp " .. tostring(s.exp) .. " is not a Data.Expansions name") end
    end
    if s.requires ~= nil then
      if type(s.requires) ~= "table" or type(s.requires.quest) ~= "number"
        or type(s.requires.text) ~= "string" or s.requires.text == "" then
        fail(id, "requires must be {quest=<number>, text=<string>}")
      end
    end
  end

  -- every difficulty ID used by an instance spec, flattened over groups
  local function eachDifficulty(s, fn)
    for _, d in ipairs(s.difficulties or {}) do
      if type(d) == "table" then for _, g in ipairs(d) do fn(g) end else fn(d) end
    end
  end

  it("lockout specs are well-formed", function()
    local ns = load_addon(FILES)
    local bad = {}
    local function fail(id, why) bad[#bad + 1] = tostring(id) .. ": " .. why end
    for id, s in pairs(ns.Data.Lockouts) do
      if type(id) ~= "number" then fail(id, "key not a number") end
      if not ns.Data.Mounts[id] then fail(id, "unknown mount") end
      checkSpec(id, s, fail, ns.Data.Expansions)
    end
    table.sort(bad)
    eq(bad, {})
  end)

  it("spec checker accepts difficulty groups and rejects empty ones (R9)", function()
    local bad = {}
    local function fail(id, why) bad[#bad + 1] = tostring(id) .. ": " .. why end
    checkSpec("plain", { instance = 1, boss = "B", difficulties = { 3, 4 }, reset = "weekly" }, fail)
    checkSpec("group", { instance = 1, boss = "B", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }, fail)
    checkSpec("mixed", { instance = 1, boss = "B", difficulties = { { 5, 6 }, 4 }, reset = "weekly" }, fail)
    eq(bad, {})
    checkSpec("empty", { instance = 1, boss = "B", difficulties = { {} }, reset = "weekly" }, fail)
    checkSpec("str", { instance = 1, boss = "B", difficulties = { { "3" } }, reset = "weekly" }, fail)
    eq(bad, { "empty: empty difficulty group", "str: difficulty in group not a number" })
    bad = {}
    checkSpec("exp", { manual = true, reset = "weekly", exp = "Classic" }, fail, { "Classic" })
    eq(bad, {})
    checkSpec("badexp", { manual = true, reset = "weekly", exp = "Classik" }, fail, { "Classic" })
    eq(bad, { "badexp: exp Classik is not a Data.Expansions name" })
  end)

  it("spec checker accepts camp specs (no reset, optional zone) and rejects malformed ones", function()
    local bad = {}
    local function fail(id, why) bad[#bad + 1] = tostring(id) .. ": " .. why end
    checkSpec("camp", { camp = true, zone = "Gorgrond" }, fail)
    checkSpec("nozone", { camp = true }, fail)
    eq(bad, {})
    checkSpec("reset", { camp = true, reset = "daily" }, fail)
    checkSpec("both", { camp = true, manual = true }, fail)
    checkSpec("zone", { manual = true, reset = "daily", zone = "X" }, fail)
    checkSpec("cat", { quest = 1, reset = "daily", category = "rares" }, fail)
    checkSpec("badcat", { quest = 1, reset = "daily", category = "rare" }, fail)
    eq(bad, { "reset: camp spec with a reset", "both: has 2 of instance/quest/lfg/manual/camp",
      "zone: zone on a non-camp spec", "badcat: category rare is not a checklist category" })
  end)

  it("no instance spec tracks LFR (R10)", function()
    local ns = load_addon(FILES)
    local bad = {}
    local function check(id, s)
      eachDifficulty(s, function(d) if d == 17 then bad[#bad + 1] = tostring(id) end end)
    end
    for id, s in pairs(ns.Data.Lockouts) do check(id, s) end
    for name, s in pairs(ns.Data.BossLockouts) do check(name, s) end
    table.sort(bad)
    eq(bad, {})
  end)

  it("legacy raids: one lockout across sizes, so one difficulty group (R11)", function()
    local ns = load_addon(FILES)
    local L = ns.Data.Lockouts
    for _, id in ipairs({ 396, 425, 415, 445, 442, 478, 531, 543 }) do
      eq(L[id].difficulties, { { 3, 4, 5, 6 } }, "mount " .. id)
    end
    eq(L[444].difficulties, { { 5, 6 } }, "mount 444")
    for _, id in ipairs({ 349, 246, 247, 286, 287 }) do
      eq(L[id].difficulties, { { 3, 4 } }, "mount " .. id)
    end
    eq(L[363].difficulties, { 6 }, "mount 363")
    eq(L[781], { manual = true, reset = "daily", repeatable = true }, "mount 781")
  end)

  it("boss lockouts name route bosses of a single node and are well-formed (R12)", function()
    local ns = load_addon(FILES)
    local nodesByBoss = {}
    local function walk(n)
      for _, b in ipairs(n.bosses or {}) do
        local t = nodesByBoss[b.boss] or {}
        t[n] = true
        nodesByBoss[b.boss] = t
      end
      for _, c in ipairs(n.steps or {}) do walk(c) end
    end
    for _, n in ipairs(ns.Data.Route) do walk(n) end
    local bad = {}
    local function fail(id, why) bad[#bad + 1] = tostring(id) .. ": " .. why end
    for name, s in pairs(ns.Data.BossLockouts) do
      local nodes = nodesByBoss[name]
      if not nodes then
        fail(name, "not a route boss")
      else
        local count = 0
        for _ in pairs(nodes) do count = count + 1 end
        if count ~= 1 then fail(name, "boss name used by " .. count .. " route nodes") end
      end
      checkSpec(name, s, fail, ns.Data.Expansions)
    end
    table.sort(bad)
    eq(bad, {})
    for _, name in ipairs({ "Koralon", "Emalon", "Toravon" }) do
      ok(ns.Data.BossLockouts[name], "BossLockouts has " .. name)
      eq(ns.Data.BossLockouts[name].exp, "Wrath of the Lich King", name .. " sorts under Wrath")
    end
    -- The Quantum Courser rows (bogus planner data) are gone with their spec.
    eq(ns.Data.BossLockouts["Chrono-Lord Deios"], nil)
    local bogus = {}
    local function walkNotes(node)
      for _, b in ipairs(node.bosses or {}) do
        if type(b.note) == "string" and b.note:lower():find("quantum courser", 1, true) then
          bogus[#bogus + 1] = b.mount
        end
      end
      for _, c in ipairs(node.steps or {}) do walkNotes(c) end
    end
    for _, n in ipairs(ns.Data.Route) do walkNotes(n) end
    eq(bogus, {}, "no Quantum Courser route rows")
  end)

  it("defines the three holiday-boss events with their LFG dungeons", function()
    local ns = load_addon(FILES)
    local H = ns.Data.Holidays
    eq(H.hallowsend.lfg, 285)
    eq(H.brewfest.lfg, 287)
    eq(H.loveisintheair.lfg, 288)
    -- F12: LfgDungeons 286 "The Frost Lord Ahune" (Group_ID 11, holiday bosses; build 12.1.5.70448).
    eq(H.midsummer.lfg, 286)
    eq(H.midsummer.mounts, { 3036 })
    eq(ns.Data.Lockouts[3036], { lfg = 286, reset = "daily" })
    eq(H.hallowsend.title, "Hallow's End")
    eq(H.brewfest.title, "Brewfest")
    eq(H.loveisintheair.title, "Love is in the Air")
  end)

  it("holiday entries are well-formed and list mounts of their own section", function()
    local ns = load_addon(FILES)
    local bad = {}
    local function fail(key, why) bad[#bad + 1] = tostring(key) .. ": " .. why end
    for key, h in pairs(ns.Data.Holidays) do
      if type(h.title) ~= "string" or h.title == "" then fail(key, "no title") end
      if h.lfg ~= nil and type(h.lfg) ~= "number" then fail(key, "lfg not a number") end
      if type(h.mounts) ~= "table" then fail(key, "no mounts table") end
      if h.coords ~= nil and type(h.coords.m) ~= "number" then fail(key, "coords without map") end
      if #(h.mounts or {}) > 0 and (type(h.stepTitle) ~= "string" or h.stepTitle == "") then
        fail(key, "mounts but no stepTitle")
      end
      for _, id in ipairs(h.mounts or {}) do
        local m = ns.Data.Mounts[id]
        if not m then fail(key, "unknown mount " .. id)
        elseif m.tab ~= "holiday" or m.section ~= key then fail(key, "mount " .. id .. " is not in section " .. key)
        elseif m.unobtainable then fail(key, "mount " .. id .. " is unobtainable") end
      end
    end
    table.sort(bad)
    eq(bad, {})
  end)

  it("every holiday-boss mount has a daily lfg spec for its event (R3)", function()
    local ns = load_addon(FILES)
    local bad = {}
    for key, h in pairs(ns.Data.Holidays) do
      if h.lfg then
        for _, id in ipairs(h.mounts) do
          local s = ns.Data.Lockouts[id]
          if not s or s.lfg ~= h.lfg or s.reset ~= "daily" then
            bad[#bad + 1] = key .. ":" .. id
          end
        end
      end
    end
    table.sort(bad)
    eq(bad, {})
  end)

  it("every obtainable LFG-boss holiday mount is listed under its event", function()
    local ns = load_addon(FILES)
    local listed = {}
    for _, h in pairs(ns.Data.Holidays) do
      for _, id in ipairs(h.mounts) do listed[id] = true end
    end
    -- the mounts dropped by the holiday dungeon bosses (Rarity lockDungeonId 285/287/288)
    local expected = {219, 2623, 202, 226, 2640, 352, 2328, 2492, 3036}
    local missing = {}
    for _, id in ipairs(expected) do
      if not listed[id] then missing[#missing + 1] = id end
    end
    eq(missing, {})
  end)
end)

describe("repeatable no-lockout content", function()
  it("Rivendare's Deathcharger and the Infinite Timereaver are repeatable (no lockout)", function()
    local ns = load_addon({"Data/Mounts.lua","Data/Route.lua","Data/Lockouts.lua"})
    eq(ns.Data.Lockouts[69].repeatable, true)
    eq(ns.Data.Lockouts[781].repeatable, true)
  end)
end)
