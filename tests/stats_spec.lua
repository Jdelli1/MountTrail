-- Logic/Stats.lua: kill statistics per character (pure; no WoW API).

describe("stats", function()
  local function load()
    return load_addon({ "Core/Locale.lua", "Logic/Stats.lua" }).Stats
  end

  describe("Read", function()
    it("sums every statistic of a mount", function()
      local S = load()
      local values = { [1] = 3, [2] = 4, [3] = 0 }
      eq(S.Read({ 1, 2, 3 }, function(id) return values[id] end), 7)
    end)

    it("skips statistics with no reading and is nil when none read", function()
      local S = load()
      eq(S.Read({ 1, 2 }, function(id) if id == 2 then return 5 end end), 5)
      eq(S.Read({ 1, 2 }, function() return nil end), nil)
      eq(S.Read({}, function() return 1 end), nil)
      eq(S.Read(nil, function() return 1 end), nil)
    end)

    it("counts a zero reading (\"--\" in game) as data", function()
      eq(load().Read({ 9 }, function() return 0 end), 0)
    end)
  end)

  describe("Collect", function()
    it("reads every mount that has statistics", function()
      local S = load()
      local mounts = {
        [10] = { name = "A", stats = { 1, 2 } },
        [11] = { name = "B" },
        [12] = { name = "C", stats = { 3 } },
        [13] = { name = "D", stats = { 4 } },
      }
      local values = { [1] = 2, [2] = 1, [3] = 0 }
      local asked = {}
      local got = S.Collect(mounts, function(id) asked[#asked + 1] = id; return values[id] end)
      eq(got, { [10] = 3, [12] = 0 }, "13 had no reading, 11 has no stats")
      table.sort(asked)
      eq(asked, { 1, 2, 3, 4 })
    end)

    it("is empty without data", function()
      eq(load().Collect(nil, function() return 1 end), {})
    end)
  end)

  describe("Merge", function()
    it("stores this character's readings, keeping older ones that were not read", function()
      local S = load()
      local store = { ["Other-Realm"] = { [10] = 9 } }
      S.Merge(store, "Me-Realm", { [10] = 2 })
      eq(store, { ["Other-Realm"] = { [10] = 9 }, ["Me-Realm"] = { [10] = 2 } })
      S.Merge(store, "Me-Realm", { [12] = 0 })
      eq(store["Me-Realm"], { [10] = 2, [12] = 0 })
      S.Merge(store, "Me-Realm", { [10] = 5 })
      eq(store["Me-Realm"], { [10] = 5, [12] = 0 })
    end)

    it("replaces a damaged character entry", function()
      local S = load()
      local store = { ["Me-Realm"] = "junk" }
      S.Merge(store, "Me-Realm", { [10] = 1 })
      eq(store["Me-Realm"], { [10] = 1 })
    end)
  end)

  describe("Totals", function()
    local store = {
      ["A-R"] = { [10] = 3, [11] = 0 },
      ["B-R"] = { [10] = 4 },
      ["C-R"] = { [10] = "bad" },
      ["D-R"] = "junk",
    }

    it("sums every character and reports this one's count", function()
      eq({ load().Totals(store, 10, "A-R") }, { 7, 3, 2 })
    end)

    it("is nil for this character when it has no reading", function()
      eq({ load().Totals(store, 10, "Z-R") }, { 7, nil, 2 })
    end)

    it("is nil overall when no character has a reading", function()
      eq({ load().Totals(store, 99, "A-R") }, { nil, nil, 0 })
      eq({ load().Totals(nil, 10, "A-R") }, { nil, nil, 0 })
    end)

    it("keeps zero readings", function()
      eq({ load().Totals(store, 11, "A-R") }, { 0, 0, 1 })
    end)
  end)

  describe("Line", function()
    local store = {
      ["A-R"] = { [10] = 3, [11] = 6 },
      ["B-R"] = { [10] = 4 },
      ["C-R"] = { [12] = 2, [13] = 0 },
      ["D-R"] = { [13] = 5 },
    }

    it("shows the total and this character's count", function()
      eq(load().Line(store, 10, "A-R"), "Kills: 7 (this character: 3)")
    end)

    it("shows the split when another character's reading is 0", function()
      eq(load().Line(store, 13, "D-R"), "Kills: 5 (this character: 5)")
    end)

    it("shows only the total when this character is the only one with data", function()
      eq(load().Line(store, 11, "A-R"), "Kills: 6")
    end)

    it("shows only the total when this character has no reading yet", function()
      eq(load().Line(store, 12, "A-R"), "Kills: 2")
    end)

    it("is nil when no character has data", function()
      eq(load().Line(store, 99, "A-R"), nil)
      eq(load().Line(nil, 10, "A-R"), nil)
    end)
  end)
end)
