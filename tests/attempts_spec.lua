describe("attempts", function()
  local function load()
    return load_addon({"Logic/Lockouts.lua", "Logic/Attempts.lua"})
  end

  local SPECS = {
    [1] = { quest = 100, reset = "weekly" },
    [2] = { lfg = 200, reset = "weekly" },
    [3] = { instance = 657, boss = "Altairus", difficulties = { 2 }, reset = "daily" },
    [4] = { manual = true },
  }
  local function specFor(id) return SPECS[id] end
  local function notOwned() return false end

  local function state(quests, lfg, snap)
    return { snap = snap or {}, quests = quests or {}, lfg = lfg or {} }
  end

  describe("Newly", function()
    it("counts a quest mount going open -> done", function()
      local A = load().Attempts
      eq(A.Newly(state(), state({ [100] = true }), { 1 }, specFor, notOwned), { 1 })
    end)

    it("counts an lfg mount going open -> done", function()
      local A = load().Attempts
      eq(A.Newly(state(), state({}, { [200] = true }), { 2 }, specFor, notOwned), { 2 })
    end)

    it("counts an instance mount going open -> done via snapshot", function()
      local A = load().Attempts
      local killed = { [657] = { [2] = { Altairus = true } } }
      eq(A.Newly(state(), state({}, {}, killed), { 3 }, specFor, notOwned), { 3 })
    end)

    it("does not count done -> done", function()
      local A = load().Attempts
      local s = state({ [100] = true })
      eq(A.Newly(s, state({ [100] = true }), { 1 }, specFor, notOwned), {})
    end)

    it("does not count open -> open", function()
      local A = load().Attempts
      eq(A.Newly(state(), state(), { 1, 2, 3 }, specFor, notOwned), {})
    end)

    it("does not count done -> open (reset)", function()
      local A = load().Attempts
      eq(A.Newly(state({ [100] = true }), state(), { 1 }, specFor, notOwned), {})
    end)

    it("does not count an owned mount", function()
      local A = load().Attempts
      local owned = function(id) return id == 1 end
      eq(A.Newly(state(), state({ [100] = true, [200] = true }, { [200] = true }), { 1, 2 }, specFor, owned), { 2 })
    end)

    it("unknown mount is skipped", function()
      local A = load().Attempts
      eq(A.Newly(state(), state({ [100] = true }), { 999, 1 }, specFor, notOwned), { 1 })
    end)

    it("manual specs are never counted", function()
      local A = load().Attempts
      eq(A.Newly(state(), state({ [100] = true }), { 4 }, specFor, notOwned), {})
    end)

    it("first observation (prev nil) counts nothing", function()
      local A = load().Attempts
      eq(A.Newly(nil, state({ [100] = true }), { 1 }, specFor, notOwned), {})
    end)

    it("tolerates missing quests/lfg/snap tables", function()
      local A = load().Attempts
      eq(A.Newly({}, { quests = { [100] = true } }, { 1, 2 }, specFor, notOwned), { 1 })
    end)

    it("counts a duplicated mountID once", function()
      local A = load().Attempts
      eq(A.Newly(state(), state({ [100] = true }), { 1, 1, 1 }, specFor, notOwned), { 1 })
    end)
  end)

  describe("Newly per difficulty group", function()
    local GROUPS = {
      [10] = { instance = 2657, boss = "Queen Ansurek", difficulties = { 14, 15, 16 }, reset = "weekly" },
      [11] = { instance = 616, boss = "Malygos", difficulties = { 3, 4 }, reset = "weekly" },
      [12] = { instance = 754, boss = "Al'Akir", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" },
    }
    local function groupSpec(id) return GROUPS[id] end
    -- snap with `boss` killed on each listed difficulty of `instance`.
    local function kills(instance, boss, ...)
      local byDiff = {}
      for _, d in ipairs({ ... }) do byDiff[d] = { [boss] = true } end
      return state({}, {}, { [instance] = byDiff })
    end

    it("a Heroic-only kill on {14,15,16} counts +1, then Mythic +1 more", function()
      local A = load().Attempts
      local none = kills(2657, "Queen Ansurek")
      local heroic = kills(2657, "Queen Ansurek", 15)
      local both = kills(2657, "Queen Ansurek", 15, 16)
      eq(A.Newly(none, heroic, { 10 }, groupSpec, notOwned), { 10 })
      eq(A.Newly(heroic, both, { 10 }, groupSpec, notOwned), { 10 })
      eq(A.Newly(both, both, { 10 }, groupSpec, notOwned), {}, "nothing new")
    end)

    it("{3,4}: a 10-player then a 25-player kill count +1 each", function()
      local A = load().Attempts
      local ten = kills(616, "Malygos", 3)
      eq(A.Newly(kills(616, "Malygos"), ten, { 11 }, groupSpec, notOwned), { 11 })
      eq(A.Newly(ten, kills(616, "Malygos", 3, 4), { 11 }, groupSpec, notOwned), { 11 })
    end)

    it("two groups satisfied at once repeat the mount once per group", function()
      local A = load().Attempts
      eq(A.Newly(kills(616, "Malygos"), kills(616, "Malygos", 3, 4), { 11 }, groupSpec, notOwned), { 11, 11 })
    end)

    it("any-of group {{3,4,5,6}}: kills on 3 then 5 the same week count +1 in total", function()
      local A = load().Attempts
      local three = kills(754, "Al'Akir", 3)
      eq(A.Newly(kills(754, "Al'Akir"), three, { 12 }, groupSpec, notOwned), { 12 })
      eq(A.Newly(three, kills(754, "Al'Akir", 3, 5), { 12 }, groupSpec, notOwned), {})
    end)

    it("owned and manual mounts still count nothing", function()
      local A = load().Attempts
      local owned = function() return true end
      eq(A.Newly(kills(616, "Malygos"), kills(616, "Malygos", 3), { 11 }, groupSpec, owned), {})
    end)
  end)

  describe("Add / Get", function()
    it("Get is 0 for an unseen mount", function()
      eq(load().Attempts.Get({}, 5), 0)
    end)

    it("Add increments from zero and accumulates", function()
      local A = load().Attempts
      local store = {}
      A.Add(store, 5)
      eq(A.Get(store, 5), 1)
      A.Add(store, 5)
      A.Add(store, 7)
      eq(A.Get(store, 5), 2)
      eq(A.Get(store, 7), 1)
    end)
  end)
end)
