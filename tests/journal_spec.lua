describe("journal", function()
  local function load()
    return load_addon({"Logic/Journal.lua"}).Journal
  end

  local function mk(name, o)
    local m = { name = name, tab = "journal", section = "other", exp = "Legion" }
    for k, v in pairs(o or {}) do m[k] = v end
    return m
  end

  local function ids(list)
    local out = {}
    for i, r in ipairs(list) do out[i] = r.id end
    return out
  end

  -- Builds a query; `over` replaces fields.
  local function q(over)
    local c = {
      tab = "journal",
      filters = nil,
      isOwned = function() return false end,
      exists = function() return true end,
    }
    for k, v in pairs(over or {}) do c[k] = v end
    return c
  end

  local function ownedSet(set)
    return function(id) return set[id] == true end
  end

  it("DefaultFilters values", function()
    local J = load()
    eq(J.DefaultFilters, { dungeon=true, raid=true, world=true, delve=true, treasure=true, quest=true,
      activity=true, reputation=true, vendor=true, other=true, collected=false })
  end)

  it("filters out a section when its flag is false", function()
    local J = load()
    local mounts = { [1] = mk("A", {section="raid"}), [2] = mk("B", {section="dungeon"}) }
    local f = {}
    for k, v in pairs(J.DefaultFilters) do f[k] = v end
    f.raid = false
    eq(ids(J.Select(mounts, q({ filters = f }))), {2})
  end)

  it("returns id and mount table", function()
    local J = load()
    local m = mk("A")
    local r = J.Select({ [5] = m }, q())
    eq(#r, 1)
    eq(r[1].id, 5)
    ok(r[1].m == m, "m should be the mount table")
  end)

  it("hides collected by default and shows them with collected=true", function()
    local J = load()
    local mounts = { [1] = mk("A"), [2] = mk("B") }
    local owned = ownedSet({[1] = true})
    eq(ids(J.Select(mounts, q({ isOwned = owned }))), {2})
    local f = { collected = true }
    eq(ids(J.Select(mounts, q({ isOwned = owned, filters = f }))), {1, 2})
  end)

  it("collected filter applies to non-journal tabs", function()
    local J = load()
    local mounts = { [1] = mk("A", {tab="misc", section="shop"}), [2] = mk("B", {tab="misc", section="shop"}) }
    local owned = ownedSet({[1] = true})
    eq(ids(J.Select(mounts, q({ tab = "misc", isOwned = owned }))), {2})
    eq(ids(J.Select(mounts, q({ tab = "misc", isOwned = owned, filters = {collected=true} }))), {1, 2})
  end)

  it("section flags do not apply to non-journal tabs", function()
    local J = load()
    local mounts = { [1] = mk("A", {tab="misc", section="other"}) }
    eq(ids(J.Select(mounts, q({ tab = "misc", filters = {other=false} }))), {1})
  end)

  it("filters by tab", function()
    local J = load()
    local mounts = { [1] = mk("A"), [2] = mk("B", {tab="holiday", section="brewfest"}) }
    eq(ids(J.Select(mounts, q({ tab = "holiday" }))), {2})
  end)

  it("filters by expansion; nil exp means all", function()
    local J = load()
    local mounts = { [1] = mk("A", {exp="Legion"}), [2] = mk("B", {exp="Classic"}) }
    eq(ids(J.Select(mounts, q({ exp = "Classic" }))), {2})
    eq(ids(J.Select(mounts, q({ exp = nil }))), {1, 2})
  end)

  it("filters by a single section; nil means all", function()
    local J = load()
    local mounts = { [1] = mk("A", {section="raid"}), [2] = mk("B", {section="world"}) }
    eq(ids(J.Select(mounts, q({ section = "world" }))), {2})
    eq(ids(J.Select(mounts, q())), {1, 2})
  end)

  it("search is a case-insensitive substring of name", function()
    local J = load()
    local mounts = { [1] = mk("Swift Razzashi Raptor"), [2] = mk("Brown Horse") }
    eq(ids(J.Select(mounts, q({ search = "RAZZ" }))), {1})
    eq(ids(J.Select(mounts, q({ search = "horse" }))), {2})
  end)

  it("search also matches group", function()
    local J = load()
    local mounts = { [1] = mk("A", {group = "Netherwing Drakes"}), [2] = mk("B") }
    eq(ids(J.Select(mounts, q({ search = "netherwing" }))), {1})
  end)

  it("empty or whitespace search is no filter", function()
    local J = load()
    local mounts = { [1] = mk("A"), [2] = mk("B") }
    eq(#J.Select(mounts, q({ search = "" })), 2)
    eq(#J.Select(mounts, q({ search = "   " })), 2)
    eq(#J.Select(mounts, q({ search = nil })), 2)
  end)

  it("search treats pattern chars literally", function()
    local J = load()
    local mounts = { [1] = mk("Test (Rare)"), [2] = mk("Plain") }
    local good, r = pcall(J.Select, mounts, q({ search = "[(" }))
    ok(good, "must not error: " .. tostring(r))
    eq(r, {})
    eq(ids(J.Select(mounts, q({ search = "(rare" }))), {1})
    eq(ids(J.Select(mounts, q({ search = "%" }))), {})
  end)

  it("excludes mounts unknown to this client", function()
    local J = load()
    local mounts = { [1] = mk("A"), [2] = mk("B") }
    eq(ids(J.Select(mounts, q({ exists = function(id) return id ~= 1 end }))), {2})
  end)

  it("journal sorts by section order then name then id", function()
    local J = load()
    local mounts = {
      [1] = mk("zeta", {section="other"}),
      [2] = mk("Beta", {section="raid"}),
      [3] = mk("alpha", {section="raid"}),
      [4] = mk("Gamma", {section="dungeon"}),
      [5] = mk("Delta", {section="vendor"}),
      [6] = mk("Eps", {section="reputation"}),
      [7] = mk("Wld", {section="world"}),
      [9] = mk("Same", {section="raid"}),
      [8] = mk("same", {section="raid"}),
    }
    eq(ids(J.Select(mounts, q())), {4, 3, 2, 8, 9, 7, 6, 5, 1})
  end)

  it("journal section order: dungeon raid world delve treasure quest activity reputation vendor other", function()
    local J = load()
    local order = { "dungeon", "raid", "world", "delve", "treasure", "quest", "activity",
      "reputation", "vendor", "other" }
    local mounts = {}
    for i, s in ipairs(order) do mounts[100 - i] = mk("m", {section=s}) end
    local expect = {}
    for i = 1, #order do expect[i] = 100 - i end
    eq(ids(J.Select(mounts, q())), expect)
  end)

  it("a saved filter table without the new keys shows those sections", function()
    local J = load()
    local mounts = { [1] = mk("A", {section="delve"}), [2] = mk("B", {section="activity"}),
      [3] = mk("C", {section="raid"}) }
    local old = { dungeon=true, raid=false, world=true, reputation=true, vendor=true, other=true, collected=false }
    eq(ids(J.Select(mounts, q({ filters = old }))), {1, 2})
  end)

  describe("SectionOf", function()
    it("refines world/treasure/quest/activity/other journal mounts from the source text", function()
      local J = load()
      for _, s in ipairs({ "world", "treasure", "quest", "activity", "other" }) do
        eq(J.SectionOf(1, mk("A", {section=s}), "|cFFFFD200Drop:|r Zekvir (Delve)"), "delve", s)
        eq(J.SectionOf(1, mk("A", {section=s}), "found in a DELVE"), "delve", s .. " case-insensitive")
        eq(J.SectionOf(1, mk("A", {section=s}), "Paracausal cache"), "treasure", s)
        eq(J.SectionOf(1, mk("A", {section=s}), "Delver's Cache"), "delve", s .. ": delve wins")
        eq(J.SectionOf(1, mk("A", {section=s}), "Vendor: Somebody"), s, s .. " no match")
      end
    end)

    it("leaves dungeon, raid, reputation and vendor alone", function()
      local J = load()
      for _, s in ipairs({ "dungeon", "raid", "reputation", "vendor" }) do
        eq(J.SectionOf(1, mk("A", {section=s}), "Boss Cache in a Delve"), s, s)
      end
    end)

    it("only refines journal-tab mounts", function()
      local J = load()
      eq(J.SectionOf(1, mk("A", {tab="misc", section="other"}), "Delve"), "other")
      eq(J.SectionOf(1, mk("A", {tab="holiday", section="other"}), "Cache"), "other")
    end)

    it("no source text or a non-string keeps the generated section", function()
      local J = load()
      eq(J.SectionOf(1, mk("A", {section="world"})), "world")
      eq(J.SectionOf(1, mk("A", {section="world"}), 42), "world")
    end)

    it("takes a function of the mount id and only calls it when eligible", function()
      local J = load()
      local calls = {}
      local fn = function(id) calls[#calls + 1] = id; return id == 7 and "Delve" or nil end
      eq(J.SectionOf(7, mk("A", {section="world"}), fn), "delve")
      eq(J.SectionOf(8, mk("A", {section="world"}), fn), "world")
      eq(J.SectionOf(9, mk("A", {section="raid"}), fn), "raid")
      eq(calls, {7, 8})
    end)

    it("does not treat the text as a pattern", function()
      local J = load()
      eq(J.SectionOf(1, mk("A", {section="world"}), "[%(Delve"), "delve")
    end)
  end)

  describe("Select with sourceText", function()
    local function sources(map) return function(id) return map[id] end end

    it("groups by the refined section in journal order and tags each entry", function()
      local J = load()
      local mounts = {
        [1] = mk("Zed", {section="world"}),
        [2] = mk("Amy", {section="other"}),
        [3] = mk("Bob", {section="dungeon"}),
        [4] = mk("Cat", {section="vendor"}),
        [5] = mk("Dan", {section="quest"}),
      }
      local r = J.Select(mounts, q({ sourceText = sources({
        [1] = "Delve: Earthcrawl Mines", [2] = "Hidden Cache", [3] = "Cache of the boss", [4] = "Delve vendor",
      }) }))
      eq(ids(r), {3, 1, 2, 5, 4})
      local secs = {}
      for i, e in ipairs(r) do secs[i] = e.section end
      eq(secs, { "dungeon", "delve", "treasure", "quest", "vendor" })
    end)

    it("delve=false hides refined delve mounts; treasure=false hides refined caches", function()
      local J = load()
      local mounts = { [1] = mk("A", {section="world"}), [2] = mk("B", {section="world"}),
        [3] = mk("C", {section="other"}) }
      local st = sources({ [1] = "Delve", [3] = "Cache" })
      eq(ids(J.Select(mounts, q({ sourceText = st, filters = { delve = false } }))), {2, 3}, "world, then treasure")
      eq(ids(J.Select(mounts, q({ sourceText = st, filters = { treasure = false } }))), {2, 1}, "world before delve")
      eq(ids(J.Select(mounts, q({ sourceText = st, filters = { world = false } }))), {1, 3})
    end)

    it("single-section queries use the refined section", function()
      local J = load()
      local mounts = { [1] = mk("A", {section="world"}), [2] = mk("B", {section="world"}) }
      local st = sources({ [1] = "Delve" })
      eq(ids(J.Select(mounts, q({ sourceText = st, section = "delve" }))), {1})
      eq(ids(J.Select(mounts, q({ sourceText = st, section = "world" }))), {2})
    end)

    it("without sourceText entries carry the generated section", function()
      local J = load()
      local r = J.Select({ [1] = mk("A", {section="world"}) }, q())
      eq(r[1].section, "world")
    end)
  end)

  it("misc sorts achievement, profession, shop, tradingpost, other", function()
    local J = load()
    local function m(n, s) return mk(n, {tab="misc", section=s}) end
    local mounts = {
      [1] = m("a", "other"), [2] = m("b", "tradingpost"), [3] = m("c", "shop"),
      [4] = m("d", "profession"), [5] = m("e", "achievement"),
    }
    eq(ids(J.Select(mounts, q({ tab = "misc" }))), {5, 4, 3, 2, 1})
  end)

  it("holiday sorts by holiday key order", function()
    local J = load()
    local keys = { "other", "anniversary", "timewalking", "darkmoon", "midsummer", "lunarfestival",
      "winterveil", "noblegarden", "loveisintheair", "brewfest", "hallowsend" }
    local mounts = {}
    for i, k in ipairs(keys) do mounts[i] = mk("m" .. i, {tab="holiday", section=k}) end
    local expect = {}
    for i = #keys, 1, -1 do expect[#expect + 1] = i end
    eq(ids(J.Select(mounts, q({ tab = "holiday" }))), expect)
  end)

  describe("faction", function()
    it("excludes the other faction mounts", function()
      local J = load()
      local mounts = {
        [1] = mk("A", {faction="Alliance"}), [2] = mk("B", {faction="Horde"}), [3] = mk("C"),
      }
      eq(ids(J.Select(mounts, q({ faction = "Alliance" }))), {1, 3})
      eq(ids(J.Select(mounts, q({ faction = "Horde" }))), {2, 3})
    end)

    it("Neutral excludes all faction-specific mounts", function()
      local J = load()
      local mounts = {
        [1] = mk("A", {faction="Alliance"}), [2] = mk("B", {faction="Horde"}), [3] = mk("C"),
      }
      eq(ids(J.Select(mounts, q({ faction = "Neutral" }))), {3})
    end)

    it("nil faction does not filter", function()
      local J = load()
      local mounts = { [1] = mk("A", {faction="Alliance"}), [2] = mk("B", {faction="Horde"}) }
      eq(ids(J.Select(mounts, q())), {1, 2})
    end)
  end)

  describe("unobtainable", function()
    it("is excluded unless owned", function()
      local J = load()
      local mounts = { [1] = mk("A", {unobtainable=true}), [2] = mk("B", {unobtainable=true}), [3] = mk("C") }
      local owned = ownedSet({[2] = true})
      eq(ids(J.Select(mounts, q({ isOwned = owned }))), {3})
      eq(ids(J.Select(mounts, q({ isOwned = owned, filters = {collected=true} }))), {2, 3})
    end)
  end)

  describe("Counts", function()
    local function allExist() return true end

    it("counts owned and total for the journal tab only", function()
      local J = load()
      local mounts = {
        [1] = mk("A"), [2] = mk("B"),
        [3] = mk("H", {tab="holiday", section="brewfest"}),
        [4] = mk("M", {tab="misc", section="shop"}),
      }
      local owned, total = J.Counts(mounts, nil, ownedSet({[1]=true, [3]=true, [4]=true}), allExist)
      eq(owned, 1)
      eq(total, 2)
    end)

    it("excludes non-existent mounts", function()
      local J = load()
      local mounts = { [1] = mk("A"), [2] = mk("B"), [3] = mk("C") }
      local owned, total = J.Counts(mounts, nil, ownedSet({[1]=true, [2]=true}),
        function(id) return id ~= 2 end)
      eq(owned, 1)
      eq(total, 2)
    end)

    it("filters by expansion", function()
      local J = load()
      local mounts = { [1] = mk("A", {exp="Legion"}), [2] = mk("B", {exp="Classic"}), [3] = mk("C", {exp="Classic"}) }
      local owned, total = J.Counts(mounts, "Classic", ownedSet({[1]=true, [2]=true}), allExist)
      eq(owned, 1)
      eq(total, 2)
    end)

    it("excludes other-faction mounts", function()
      local J = load()
      local mounts = { [1] = mk("A", {faction="Alliance"}), [2] = mk("B", {faction="Horde"}), [3] = mk("C") }
      local o, t = J.Counts(mounts, nil, ownedSet({[1]=true, [2]=true}), allExist, "Horde")
      eq(o, 1); eq(t, 2)
      o, t = J.Counts(mounts, nil, ownedSet({[1]=true, [2]=true}), allExist, "Neutral")
      eq(o, 0); eq(t, 1)
      o, t = J.Counts(mounts, nil, ownedSet({[1]=true, [2]=true}), allExist)
      eq(o, 2); eq(t, 3)
    end)

    it("is unchanged by sourceText", function()
      local J = load()
      local mounts = { [1] = mk("A", {section="world"}), [2] = mk("B", {section="raid"}), [3] = mk("C") }
      local owned = ownedSet({[1]=true})
      local o1, t1 = J.Counts(mounts, nil, owned, allExist)
      local o2, t2 = J.Counts(mounts, nil, owned, allExist, nil, function() return "Delve Cache" end)
      eq({o1, t1}, {1, 3})
      eq({o2, t2}, {o1, t1})
    end)

    it("unobtainable counts only when owned (then owned and total)", function()
      local J = load()
      local mounts = { [1] = mk("A", {unobtainable=true}), [2] = mk("B", {unobtainable=true}), [3] = mk("C") }
      local o, t = J.Counts(mounts, nil, ownedSet({[1]=true}), allExist)
      eq(o, 1)
      eq(t, 2)
    end)
  end)
end)
