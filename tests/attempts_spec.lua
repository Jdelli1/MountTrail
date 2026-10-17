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
