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

    it("ignores bosses with an empty name", function()
      local rows = {
        { instance = 657, difficulty = 2, bosses = { { name = "", killed = true }, { name = "Altairus", killed = true } } },
        { instance = 658, difficulty = 2, bosses = { { name = "", killed = true } } },
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
      eq(L.State(s, killed(1, 14, "B")), "done", "a size-free Normal kill too")
      eq(L.State(s, killed(1, 16, "B")), "open")
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
      eq(L.State(s, killed(1, 16, "Someone Else")), "open")
    end)

    -- F12: the game's saved-instance names can carry a title the journal
    -- leaves out, or the other way round (DungeonEncounter vs JournalEncounter,
    -- tools/verify_data.py): plain substring containment either way.
    it("boss name matches when either contains the other, case-insensitively", function()
      local L = load().Lockouts
      local sweete = { instance = 1754, boss = "Harlan Sweete", difficulties = { 23 }, reset = "weekly" }
      eq(L.State(sweete, killed(1754, 23, "Lord Harlan Sweete")), "done", "title in the game's name")
      local gmod = { instance = 2070, boss = "High Tinker Mekkatorque", difficulties = { 16 }, reset = "weekly" }
      eq(L.State(gmod, killed(2070, 16, "Mekkatorque")), "done", "title in the spec's name")
      eq(L.State(gmod, killed(2070, 16, "high tinker MEKKATORQUE")), "done", "case-insensitive")
    end)

    -- JournalEncounter 2172 "Dazar, The First King" links to DungeonEncounter 2143
    -- "King Dazar" (map 1762): the shipped spec names what both contain.
    it("Tomb Stalker's King's Rest spec matches the journal and the DungeonEncounter name", function()
      local ns = loadWithData()
      local L, spec = ns.Lockouts, ns.Data.Lockouts[1040]
      eq(spec.boss, "Dazar")
      eq(L.State(spec, killed(1762, 23, "King Dazar")), "done")
      eq(L.State(spec, killed(1762, 23, "Dazar, The First King")), "done")
      local others = merge(killed(1762, 23, "The Golden Serpent"), killed(1762, 23, "The Council of Tribes"),
        killed(1762, 23, "Mchimba the Embalmer"))
      eq(L.State(spec, others), "open", "no other King's Rest boss contains Dazar")
    end)

    it("does not match another boss of the same instance", function()
      local L = load().Lockouts
      local archavon = { instance = 624, boss = "Archavon the Stone Watcher", difficulties = { 3 }, reset = "weekly" }
      local others = merge(killed(624, 3, "Koralon the Flame Watcher"), killed(624, 3, "Emalon the Storm Watcher"),
        killed(624, 3, "Toravon the Ice Watcher"))
      eq(L.State(archavon, others), "open")
      local deathwing = { instance = 967, boss = "Madness of Deathwing", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }
      eq(L.State(deathwing, killed(967, 5, "Spine of Deathwing")), "open")
      local ultraxion = { instance = 967, boss = "Ultraxion", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }
      eq(L.State(ultraxion, killed(967, 5, "Madness of Deathwing")), "open")
    end)

    it("an empty name never matches, on either side", function()
      local L = load().Lockouts
      local s = { instance = 1, boss = "Fyrakk", difficulties = { 16 }, reset = "weekly" }
      eq(L.State(s, killed(1, 16, "")), "open", "empty snapshot name")
      local empty = { instance = 1, boss = "", difficulties = { 16 }, reset = "weekly" }
      eq(L.State(empty, killed(1, 16, "Fyrakk")), "open", "empty spec name")
      eq(L.State(empty, killed(1, 16, "")), "open", "both empty")
    end)

    it("boss names with pattern characters match literally", function()
      local L = load().Lockouts
      local s = { instance = 1, boss = "Kael'thas (Sunstrider)-", difficulties = { 2 }, reset = "daily" }
      eq(L.State(s, killed(1, 2, "Kael'thas (Sunstrider)-")), "done")
      local s2 = { instance = 1, boss = "A.c", difficulties = { 2 }, reset = "daily" }
      eq(L.State(s2, killed(1, 2, "Abc")), "open")
      eq(L.State(s2, killed(1, 2, "XA.cY")), "done", "contained literally")
      local s3 = { instance = 1, boss = "%a+", difficulties = { 2 }, reset = "daily" }
      eq(L.State(s3, killed(1, 2, "Onyxia")), "open", "no pattern magic")
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

    it("camp spec (rare with no kill flag) is camp: never done, never ticked", function()
      local L = load().Lockouts
      eq(L.State({ camp = true, zone = "Gorgrond" }, {}), "camp")
      eq(L.State({ camp = true }, {}, function() return true end, function() return true end), "camp")
      eq(L.IsCamp({ camp = true }), true)
      eq(L.IsCamp({ manual = true, reset = "daily" }), false)
      eq(L.IsCamp(nil), false)
    end)

    it("unknown spec kind is open", function()
      eq(load().Lockouts.State({ reset = "weekly" }, {}), "open")
    end)
  end)

  describe("GroupsDone", function()
    it("numbers are their own group, tables are any-of groups", function()
      local L = load().Lockouts
      local s = { instance = 1, boss = "B", difficulties = { 14, 15, 16 }, reset = "weekly" }
      eq({ L.GroupsDone(s, {}) }, { {}, 0, {} })
      eq({ L.GroupsDone(s, killed(1, 15, "B")) }, { { [2] = true }, 1, { [2] = 15 } })
      eq({ L.GroupsDone(s, merge(killed(1, 14, "B"), killed(1, 16, "B"))) }, { { [1] = true, [3] = true }, 2, { [1] = 14, [3] = 16 } })
      local anyOf = { instance = 1, boss = "B", difficulties = { 2, { 5, 6 } }, reset = "weekly" }
      eq({ L.GroupsDone(anyOf, killed(1, 6, "B")) }, { { [2] = true }, 1, { [2] = 6 } })
      eq((L.GroupsDone(anyOf, merge(killed(1, 5, "B"), killed(1, 6, "B")))), { [2] = true })
    end)

    it("non-instance specs and nil have no groups", function()
      local L = load().Lockouts
      eq({ L.GroupsDone(nil, {}) }, { {}, 0, {} })
      eq({ L.GroupsDone({ quest = 1, reset = "weekly" }, {}) }, { {}, 0, {} })
      eq({ L.GroupsDone({ manual = true }, {}) }, { {}, 0, {} })
      eq({ L.GroupsDone({ instance = 1, boss = "B", difficulties = { 2 } }, nil) }, { {}, 0, {} })
    end)
  end)

  describe("legacy 10/25 raids reported as Normal / Heroic", function()
    it("a Normal (14) kill meets 10 / 25 Normal, a Heroic (15) kill 10 / 25 Heroic", function()
      local L = load().Lockouts
      local fire = { instance = 720, boss = "Alysrazor", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }
      eq(L.State(fire, killed(720, 14, "Alysrazor")), "done")
      eq(L.State(fire, killed(720, 15, "Alysrazor")), "done")
      eq(L.State(fire, killed(720, 16, "Alysrazor")), "open")
      local heroic = { instance = 967, boss = "Deathwing", difficulties = { { 5, 6 } }, reset = "weekly" }
      eq(L.State(heroic, killed(967, 15, "Deathwing")), "done")
    end)

    it("one lockout across all four sizes: any legacy kill spends the week", function()
      local L = load().Lockouts
      local invincible = { instance = 631, boss = "The Lich King", difficulties = { 6 }, reset = "weekly" }
      eq(L.IsLegacySpec(invincible), true)
      eq(L.State(invincible, killed(631, 3, "The Lich King")), "done", "10 Normal spends the 25 Heroic chance")
      eq(L.State(invincible, killed(631, 33, "The Lich King")), "open", "Timewalking is its own lockout")
      eq((L.GroupsDone(invincible, killed(631, 3, "The Lich King"))), {}, "but it is no attempt")
      eq((L.GroupsDone(invincible, killed(631, 6, "The Lich King"))), { [1] = true })
      eq(L.IsLegacySpec({ instance = 1, boss = "B", difficulties = { 14, 15 } }), false)
      eq(L.Progress({ instance = 1, boss = "B", difficulties = { 3, 4 } }, killed(1, 3, "B")), nil)
    end)

    it("one Normal kill meets both size groups, reported on the same difficulty", function()
      local L = load().Lockouts
      local ony = { instance = 249, boss = "Onyxia", difficulties = { 3, 4 }, reset = "weekly" }
      eq({ L.GroupsDone(ony, killed(249, 14, "Onyxia")) }, { { [1] = true, [2] = true }, 2, { [1] = 14, [2] = 14 } })
    end)

    it("the real Firelands and Antorus specs check off on a kill", function()
      local ns = loadWithData()
      local L = ns.Lockouts
      eq(L.State(L.SpecFor(425), killed(720, 14, "Alysrazor")), "done")
      eq(L.State(L.SpecFor(415), killed(720, 15, "Ragnaros")), "done")
      local hounds = L.SpecFor(971)
      eq(L.State(hounds, killed(1712, 15, "Felhounds of Sargeras")), "open")
      eq(L.Progress(hounds, killed(1712, 15, "Felhounds of Sargeras")), { done = { 15 }, open = { 14, 16 } })
    end)

    it("no wrong-difficulty warning on Normal / Heroic in a legacy raid", function()
      local L = load().Lockouts
      local function specFor() return { instance = 967, boss = "Deathwing", difficulties = { { 3, 4, 5, 6 } } } end
      eq(L.WrongDifficulty({ 1 }, 967, 14, specFor), {})
      eq(L.WrongDifficulty({ 1 }, 967, 15, specFor), {})
      eq(#L.WrongDifficulty({ 1 }, 967, 16, specFor), 1)
    end)
  end)

  describe("Progress", function()
    it("only for a multi-group spec part done", function()
      local L = load().Lockouts
      local s = { instance = 1, boss = "B", difficulties = { 14, 15, 16 } }
      eq(L.Progress(s, {}), nil)
      eq(L.Progress(s, merge(killed(1, 14, "B"), killed(1, 15, "B"), killed(1, 16, "B"))), nil)
      eq(L.Progress(s, killed(1, 16, "B")), { done = { 16 }, open = { 14, 15 } })
      eq(L.Progress({ instance = 1, boss = "B", difficulties = { { 3, 4 } } }, killed(1, 3, "B")), nil)
      eq(L.Progress({ quest = 1 }, {}), nil)
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

    -- F12: a Rarity quest flag's reset follows the mount's SimpleArmory group.
    it("a quest-flag rare spawn resets daily, a world boss weekly, anything else weekly", function()
      local ns = load_addon({"Logic/Lockouts.lua"})
      ns.Data = { Lockouts = {}, BossLockouts = {}, Mounts = {
        [1] = { quest = 11, group = "Rare Spawn" },
        [2] = { quest = 12, group = "Necrolord Rare Spawn" },
        [3] = { quest = 13, group = "World Boss" },
        [4] = { quest = 14, group = "Garrison" },
        [5] = { quest = 15 },
        [6] = { quest = 16, group = "Rare Spawns of Old" },
        [7] = { quest = 17, group = "rare spawn" },
      } }
      local L = ns.Lockouts
      eq(L.SpecFor(1), { quest = 11, reset = "daily" })
      eq(L.SpecFor(2), { quest = 12, reset = "daily" }, "ends with Rare Spawn")
      eq(L.SpecFor(3), { quest = 13, reset = "weekly" })
      eq(L.SpecFor(4), { quest = 14, reset = "weekly" }, "other groups keep the weekly default")
      eq(L.SpecFor(5), { quest = 15, reset = "weekly" }, "no group")
      eq(L.SpecFor(6), { quest = 16, reset = "weekly" }, "only a trailing Rare Spawn counts")
      eq(L.SpecFor(7), { quest = 17, reset = "weekly" }, "SimpleArmory's exact spelling")
    end)

    it("BfA warfront and assault zone rares (Warfront: / Assault: groups) reset daily", function()
      local ns = load_addon({"Logic/Lockouts.lua"})
      ns.Data = { Lockouts = {}, BossLockouts = {}, Mounts = {
        [1] = { quest = 21, group = "Warfront: Arathi" },
        [2] = { quest = 22, group = "Warfront: Darkshore" },
        [3] = { quest = 23, group = "Assault: Uldum" },
        [4] = { quest = 24, group = "Assault: Vale of Eternal Blossoms" },
        [5] = { quest = 25, group = "Warfront" },
        [6] = { quest = 26, group = "Old Assault: Uldum" },
        [7] = { quest = 27, group = "warfront: arathi" },
      } }
      local L = ns.Lockouts
      eq(L.SpecFor(1).reset, "daily")
      eq(L.SpecFor(2).reset, "daily")
      eq(L.SpecFor(3).reset, "daily")
      eq(L.SpecFor(4).reset, "daily")
      eq(L.SpecFor(5).reset, "weekly", "needs the 'Warfront: ' prefix")
      eq(L.SpecFor(6).reset, "weekly", "a prefix, not anywhere in the group")
      eq(L.SpecFor(7).reset, "weekly", "SimpleArmory's exact spelling")
    end)

    it("an explicit Lockouts entry wins over the quest flag's group rule", function()
      local ns = load_addon({"Logic/Lockouts.lua"})
      local spec = { quest = 99, reset = "weekly" }
      ns.Data = { Lockouts = { [1] = spec }, BossLockouts = {},
        Mounts = { [1] = { quest = 11, group = "Rare Spawn" } } }
      eq(ns.Lockouts.SpecFor(1), spec)
    end)

    it("returns nil with no spec and no quest", function()
      local ns = load_addon({"Logic/Lockouts.lua"})
      ns.Data = { Lockouts = {}, BossLockouts = {}, Mounts = { [5] = {} } }
      eq(ns.Lockouts.SpecFor(5), nil)
      eq(ns.Lockouts.SpecFor(6), nil)
    end)
  end)
end)

describe("Lockouts.IsRareGroup / QuestReset", function()
  local L = load_addon({ "Logic/Lockouts.lua" }).Lockouts
  it("rare spawn groups: Rare Spawn, '<x> Rare Spawn', Warfront: / Assault: zone rares", function()
    eq(L.IsRareGroup("Rare Spawn"), true)
    eq(L.IsRareGroup("Necrolord Rare Spawn"), true)
    eq(L.IsRareGroup("Warfront: Arathi"), true)
    eq(L.IsRareGroup("Assault: Uldum"), true)
    eq(L.IsRareGroup("NotRare Spawn"), false)
    eq(L.IsRareGroup("World Boss"), false)
    eq(L.IsRareGroup(nil), false)
  end)
  it("QuestReset: rare spawns daily, anything else weekly", function()
    eq(L.QuestReset({ group = "Rare Spawn" }), "daily")
    eq(L.QuestReset({ group = "Warfront: Darkshore" }), "daily")
    eq(L.QuestReset({ group = "World Boss" }), "weekly")
    eq(L.QuestReset({}), "weekly")
    eq(L.QuestReset(nil), "weekly")
  end)
end)

-- Midnight Mythic mounts: instance specs from the game's DB2 tables
-- (JournalInstance MapID + DungeonEncounter name, build 12.1.5.70448).
describe("Midnight lockout specs", function()
  local data = load_addon({ "Data/Mounts.lua", "Data/Lockouts.lua", "Logic/Lockouts.lua" }).Data
  local function spec(id) return data.Lockouts[id] end
  it("dungeons: Mythic (23) on the instance's MapID", function()
    eq(spec(2817), { instance = 2811, boss = "Degentrius", difficulties = { 23 }, reset = "weekly" })
    eq(spec(2805), { instance = 2805, boss = "Restless Heart", difficulties = { 23 }, reset = "weekly" })
    eq(spec(3058), { instance = 2993, boss = "Zul'jan", difficulties = { 23 }, reset = "weekly" })
  end)
  it("raids: Mythic (16)", function()
    eq(spec(3030), { instance = 3004, boss = "Ula'tek", difficulties = { 16 }, reset = "weekly" })
    eq(spec(2607), { instance = 2913, boss = "Midnight Falls", difficulties = { 16 }, reset = "weekly" })
  end)
  it("the Sporefall multi-week mount stays a hand tick", function()
    eq(spec(2950), { manual = true, reset = "weekly" })
  end)
end)
