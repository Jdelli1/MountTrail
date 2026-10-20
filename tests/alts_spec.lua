-- Alts.Characters / Alts.StateOf / Alts.Build / Alts.Rows (Logic/Alts.lua):
-- the alt lockout matrix from every character's saved section.

local function load()
  return load_addon({ "Core/Locale.lua", "Logic/Resets.lua", "Logic/Lockouts.lua", "Logic/Checklist.lua",
    "Logic/Alts.lua" }).Alts
end

local NOW = 1000000
local EXPANSIONS = { "Classic", "Wrath of the Lich King", "Cataclysm" }

local MOUNTS = {
  [1] = { name = "Zebra Drake", exp = "Cataclysm" },
  [2] = { name = "Mammoth", exp = "Wrath of the Lich King" },
  [3] = { name = "Horde Wolf", exp = "Classic", faction = "Horde" },
  [4] = { name = "Hand Drake", exp = "Classic" },
  [5] = { name = "Rare Cat", exp = "Classic" },
  [6] = { name = "Camp Bird", exp = "Classic" },
  [7] = { name = "Owned Thing", exp = "Classic" },
  [8] = { name = "Alliance Lion", exp = "Classic" },
}

local SPECS = {
  [1] = { instance = 1, boss = "A", difficulties = { 2 }, reset = "daily" },
  [2] = { instance = 2, boss = "Archavon", difficulties = { 3 }, reset = "weekly" },
  [3] = { manual = true, reset = "weekly" },
  [4] = { manual = true, reset = "daily" },
  [5] = { quest = 100, reset = "weekly" },
  [6] = { camp = true, zone = "Somewhere" },
  [7] = { quest = 101, reset = "weekly" },
  [8] = { quest = 102, reset = "weekly" },
}

local TREE = {
  { title = "Run The Vortex", bosses = { { mount = 1, boss = "A" } } },
  { title = "Run Vault", bosses = { { mount = 2, boss = "Archavon" } } },
  { title = "Lion", alliance = true, bosses = { { mount = 8, boss = "Lion" } } },
}

local function checklist()
  return {
    tree = TREE,
    mounts = MOUNTS,
    specFor = function(id) return SPECS[id] end,
    holidays = {},
    active = {},
    expansions = EXPANSIONS,
    keyOf = function(id) return id end,
  }
end

-- Account-wide gate: owned mounts out; a faction mount only for its faction.
local function gate(id, m, faction)
  if m.faction and m.faction ~= faction then return nil end
  return id == 7
end

local function section(over)
  local s = {
    seen = { name = "Anna", realm = "Silvermoon", class = "MAGE", level = 80, faction = "Alliance",
      at = NOW - 100, dailyReset = NOW + 3600, weeklyReset = NOW + 86400 },
    last = { snap = {}, quests = {}, lfg = {} },
    ticks = {},
  }
  for k, v in pairs(over or {}) do s[k] = v end
  return s
end

local function cellsOf(rows, charKey)
  local out = {}
  for _, r in ipairs(rows) do out[r.key] = r.cells[charKey] end
  return out
end

local function build(A, sections, extra)
  local chars = A.Characters(sections, NOW, "Anna - Silvermoon")
  local ctx = { characters = chars, now = NOW, checklist = checklist(), gate = gate }
  for k, v in pairs(extra or {}) do ctx[k] = v end
  return A.Build(ctx), chars
end

describe("Alts.Characters", function()
  it("lists sections with a seen stamp, current character first, then by name", function()
    local A = load()
    local chars = A.Characters({
      ["Zed - Silvermoon"] = section({ seen = { name = "Zed", faction = "Horde", class = "WARRIOR" } }),
      ["bob - Silvermoon"] = section({ seen = { name = "bob", faction = "Alliance" } }),
      ["Anna - Silvermoon"] = section(),
      ["Old - Silvermoon"] = { last = {} }, -- never stamped: not listed
    }, NOW, "Zed - Silvermoon")
    eq(#chars, 3)
    eq(chars[1].key, "Zed - Silvermoon")
    eq(chars[1].current, true)
    eq(chars[1].class, "WARRIOR")
    eq(chars[2].name, "Anna")
    eq(chars[3].name, "bob")
    eq(chars[2].realm, "Silvermoon")
    eq(chars[3].realm, "Silvermoon", "realm from the key when seen has none")
  end)

  it("leaves hidden characters out and counts them", function()
    local chars, hidden = load().Characters({
      ["Anna - Silvermoon"] = section(),
      ["Bob - Silvermoon"] = section({ seen = { name = "Bob" } }),
    }, NOW, "Anna - Silvermoon", { ["Bob - Silvermoon"] = true, ["Gone - X"] = true })
    eq(#chars, 1)
    eq(chars[1].key, "Anna - Silvermoon")
    eq(hidden, 1, "only hidden characters that exist count")
  end)

  it("marks the daily / weekly data stale once its reset has passed", function()
    local chars = load().Characters({
      ["Anna - Silvermoon"] = section({ seen = { name = "Anna", dailyReset = NOW - 1, weeklyReset = NOW + 10 } }),
    }, NOW, "Anna - Silvermoon")
    eq(chars[1].dailyStale, true)
    eq(chars[1].weeklyStale, false)
  end)
end)

describe("Alts.Build", function()
  it("one row per daily / weekly lockout, weekly first, then expansion, then name; no camp rows", function()
    local rows = build(load(), { ["Anna - Silvermoon"] = section() })
    local keys = {}
    for i, r in ipairs(rows) do keys[i] = r.key end
    -- Weekly: Classic (Alliance Lion, Rare Cat by name), Wrath (Mammoth's
    -- instance lockout); then daily: Classic Hand Drake, Cataclysm Zebra.
    eq(keys, { "quest:102", "quest:100", "instance:2|Archavon|3|weekly", 4, "instance:1|A|2|daily" })
    eq(rows[1].reset, "weekly")
    eq(rows[1].name, "Alliance Lion")
    eq(rows[1].exp, "Classic")
    eq(rows[5].reset, "daily")
    eq(rows[5].category, "dungeons")
    eq(rows[5].entry.id, 1)
  end)

  it("a done lockout is done; an open one is open and counted", function()
    local A = load()
    local rows = build(A, {
      ["Anna - Silvermoon"] = section({ last = {
        snap = { [2] = { [3] = { Archavon = true } } }, quests = { [100] = true }, lfg = {},
      } }),
    })
    local cells = cellsOf(rows, "Anna - Silvermoon")
    eq(cells["instance:2|Archavon|3|weekly"], "done")
    eq(cells["quest:100"], "done")
    eq(cells["instance:1|A|2|daily"], "open")
    for _, r in ipairs(rows) do
      eq(r.open, r.cells["Anna - Silvermoon"] == "open" and 1 or 0, tostring(r.key))
    end
  end)

  it("stale data: past the weekly reset weeklies are open; past the daily reset dailies are", function()
    local A = load()
    local last = {
      snap = { [1] = { [2] = { A = true } }, [2] = { [3] = { Archavon = true } } }, quests = { [100] = true }, lfg = {},
    }
    local daily = build(A, { ["Anna - Silvermoon"] = section({ last = last,
      seen = { name = "Anna", faction = "Alliance", dailyReset = NOW - 1, weeklyReset = NOW + 10 } }) })
    local cells = cellsOf(daily, "Anna - Silvermoon")
    eq(cells["instance:1|A|2|daily"], "open", "daily reset passed")
    eq(cells["instance:2|Archavon|3|weekly"], "done", "the week is not over")
    eq(cells["quest:100"], "done")
    local weekly = build(A, { ["Anna - Silvermoon"] = section({ last = last,
      seen = { name = "Anna", faction = "Alliance", dailyReset = NOW - 1, weeklyReset = NOW } }) })
    cells = cellsOf(weekly, "Anna - Silvermoon")
    eq(cells["instance:2|Archavon|3|weekly"], "open")
    eq(cells["quest:100"], "open")
  end)

  it("hand ticks count for manual specs until they expire, never for game-tracked ones", function()
    local A = load()
    local rows = build(A, { ["Anna - Silvermoon"] = section({ ticks = { [4] = NOW + 5, [100] = NOW + 5 } }) })
    eq(cellsOf(rows, "Anna - Silvermoon")[4], "done")
    rows = build(A, { ["Anna - Silvermoon"] = section({ ticks = { [4] = NOW } }) })
    eq(cellsOf(rows, "Anna - Silvermoon")[4], "open", "expired tick")
    rows = build(A, { ["Anna - Silvermoon"] = section({ ticks = { [5] = NOW + 5 } }) })
    eq(cellsOf(rows, "Anna - Silvermoon")["quest:100"], "open", "a quest-flag lockout ignores ticks")
  end)

  it("rows are the union over characters; another faction's lockout is n/a", function()
    local A = load()
    local rows = build(A, {
      ["Anna - Silvermoon"] = section(),
      ["Zed - Silvermoon"] = section({ seen = { name = "Zed", faction = "Horde",
        dailyReset = NOW + 10, weeklyReset = NOW + 10 } }),
    })
    local anna, zed = cellsOf(rows, "Anna - Silvermoon"), cellsOf(rows, "Zed - Silvermoon")
    eq(anna[3], "na", "Horde Wolf: Horde only (mount faction)")
    eq(zed[3], "open")
    eq(zed["quest:102"], "na", "the Alliance route node")
    eq(anna["quest:102"], "open")
    eq(anna["quest:100"], "open")
    eq(zed["quest:100"], "open")
    for _, r in ipairs(rows) do
      if r.key == "quest:100" then eq(r.open, 2) end
      if r.key == 3 then eq(r.open, 1) end
    end
    eq(cellsOf(rows, "Anna - Silvermoon")[7], nil, "owned mounts are nobody's row")
  end)

  it("a character with no stored observation is unknown (n/a still wins)", function()
    local A = load()
    local rows = build(A, {
      ["Anna - Silvermoon"] = section(),
      ["New - Silvermoon"] = section({ last = false, seen = { name = "New", faction = "Horde" } }),
    })
    local new = cellsOf(rows, "New - Silvermoon")
    eq(new["quest:100"], "unknown")
    eq(new["quest:102"], "na", "Alliance only")
    for _, r in ipairs(rows) do
      if r.key == "quest:100" then eq(r.open, 1, "unknown is not counted open") end
    end
  end)

  it("hidden characters get no column; category filters drop rows", function()
    local A = load()
    local sections = {
      ["Anna - Silvermoon"] = section(),
      ["Zed - Silvermoon"] = section({ seen = { name = "Zed", faction = "Horde" } }),
    }
    local chars = A.Characters(sections, NOW, "Anna - Silvermoon", { ["Zed - Silvermoon"] = true })
    local rows = A.Build({ characters = chars, now = NOW, checklist = checklist(), gate = gate,
      filters = { dungeons = false } })
    for _, r in ipairs(rows) do
      eq(r.cells["Zed - Silvermoon"], nil)
      ok(r.category ~= "dungeons", "dungeons filtered")
      ok(r.key ~= 3, "the Horde-only lockout has no column to list it")
    end
  end)
end)

describe("Alts.Rows", function()
  it("weekly and daily headers, expansion sub-headers, collapse", function()
    local A = load()
    local rows = build(A, { ["Anna - Silvermoon"] = section() })
    local out = A.Rows(rows)
    eq(out[1].header, true)
    eq(out[1].key, "alts|weekly")
    eq(out[1].text, "Weekly")
    eq(out[1].total, 3)
    eq(out[2].key, "alts|weekly|Classic")
    eq(out[2].depth, 2)
    eq(out[3].row.key, "quest:102")
    local texts = {}
    for _, r in ipairs(out) do if r.header then texts[#texts + 1] = r.key end end
    eq(texts, { "alts|weekly", "alts|weekly|Classic", "alts|weekly|Wrath of the Lich King",
      "alts|daily", "alts|daily|Classic", "alts|daily|Cataclysm" })
    local folded = A.Rows(rows, { collapsed = { ["alts|weekly"] = true, ["alts|daily|Classic"] = true },
      label = function(reset) return reset .. "!" end })
    eq(folded[1].text, "weekly!")
    eq(folded[1].collapsed, true)
    eq(folded[2].key, "alts|daily")
    eq(folded[3].key, "alts|daily|Classic")
    eq(folded[4].key, "alts|daily|Cataclysm")
    eq(folded[5].row.key, "instance:1|A|2|daily")
    eq(#folded, 5)
  end)
end)
