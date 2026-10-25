local ADDON, ns = ...

-- Lockout state from saved-instance rows and quest/LFG flags.
-- Pure Lua, no WoW API: callers pass rows and predicate functions in.
local Lockouts = {}
ns.Lockouts = Lockouts

-- rows: { {instance=, difficulty=, bosses={ {name=, killed=bool} }} } or nil
-- -> snap[instance][difficulty][bossName] = true, killed bosses only.
-- Rows with a nil instance or difficulty and bosses with a nil or empty name
-- are skipped (an empty name would match every boss).
function Lockouts.Snapshot(rows)
  local snap = {}
  for _, row in ipairs(rows or {}) do
    if row.instance ~= nil and row.difficulty ~= nil then
      for _, boss in ipairs(row.bosses or {}) do
        if boss.killed and type(boss.name) == "string" and boss.name ~= "" then
          local byDiff = snap[row.instance]
          if not byDiff then byDiff = {}; snap[row.instance] = byDiff end
          local byBoss = byDiff[row.difficulty]
          if not byBoss then byBoss = {}; byDiff[row.difficulty] = byBoss end
          byBoss[boss.name] = true
        end
      end
    end
  end
  return snap
end

local RARE_SPAWN = "Rare Spawn"
-- BfA zone rares: the warfront zones' and the N'Zoth assaults' rare spawns.
local DAILY_PREFIXES = { "Warfront: ", "Assault: " }

-- Whether a SimpleArmory group names rare spawns: "Rare Spawn", a group
-- ending in it such as "Necrolord Rare Spawn", or a BfA zone rare group
-- starting "Warfront: " / "Assault: ".
function Lockouts.IsRareGroup(group)
  if type(group) ~= "string" then return false end
  if #group >= #RARE_SPAWN and string.sub(group, -#RARE_SPAWN) == RARE_SPAWN
    and (#group == #RARE_SPAWN or string.sub(group, -#RARE_SPAWN - 1, -#RARE_SPAWN - 1) == " ") then
    return true
  end
  for _, prefix in ipairs(DAILY_PREFIXES) do
    if string.sub(group, 1, #prefix) == prefix then return true end
  end
  return false
end

-- Reset of a Rarity quest flag, from the mount's SimpleArmory group: a rare
-- spawn (Lockouts.IsRareGroup) is looted once a day -> "daily"; a world boss
-- ("World Boss") and anything else -> "weekly" (Data/Lockouts.lua entries
-- override both).
function Lockouts.QuestReset(mount)
  local group = type(mount) == "table" and mount.group or nil
  return Lockouts.IsRareGroup(group) and "daily" or "weekly"
end

-- Which spec governs a mount: a per-boss spec for the route boss, else the
-- mount's own spec, else the Rarity quest flag (reset: Lockouts.QuestReset),
-- else nil.
function Lockouts.SpecFor(mountID, routeBoss)
  local data = ns.Data or {}
  if routeBoss and data.BossLockouts and data.BossLockouts[routeBoss] then
    return data.BossLockouts[routeBoss]
  end
  if data.Lockouts and data.Lockouts[mountID] then
    return data.Lockouts[mountID]
  end
  local mount = data.Mounts and data.Mounts[mountID]
  if mount and mount.quest then
    return { quest = mount.quest, reset = Lockouts.QuestReset(mount) }
  end
  return nil
end

-- Plain-string containment (string.find with plain = true: no patterns).
local function contains(s, part)
  return string.find(s, part, 1, true) ~= nil
end

-- A spec boss matches a snapshot boss if either name contains the other,
-- case-insensitively ("Fyrakk" vs "Fyrakk the Blazing", "Harlan Sweete" vs
-- "Lord Harlan Sweete", "High Tinker Mekkatorque" vs "Mekkatorque": the
-- saved-instance list and the journal disagree on titles). An empty name on
-- either side never matches.
local function bossMatches(specBoss, snapBoss)
  if type(specBoss) ~= "string" or type(snapBoss) ~= "string"
    or specBoss == "" or snapBoss == "" then
    return false
  end
  local a, b = string.lower(specBoss), string.lower(snapBoss)
  return contains(b, a) or contains(a, b)
end

-- Legacy raid sizes the game now reports as size-free Normal / Heroic: a
-- 10 or 25 Normal spec (3, 4) is also met by a Normal (14) kill, a 10 or 25
-- Heroic one (5, 6) by a Heroic (15) kill (old raids such as Firelands lock
-- and drop on 14 / 15 now).
Lockouts.LEGACY_AS = { [3] = 14, [4] = 14, [5] = 15, [6] = 15 }

local function killedExactly(snap, instance, difficulty, specBoss)
  local byDiff = snap and snap[instance]
  local bosses = byDiff and byDiff[difficulty]
  if not bosses then return false end
  for name in pairs(bosses) do
    if bossMatches(specBoss, name) then return true end
  end
  return false
end

-- The difficulty a kill was reported on for spec difficulty `difficulty`
-- (itself, or its size-free equivalent) -> ID or nil.
local function killedOn(snap, instance, difficulty, specBoss)
  if killedExactly(snap, instance, difficulty, specBoss) then return difficulty end
  local modern = Lockouts.LEGACY_AS[difficulty]
  if modern and killedExactly(snap, instance, modern, specBoss) then return modern end
  return nil
end

-- -> the reported difficulty that satisfies the group, or nil.
local function groupSatisfied(snap, spec, group)
  if type(group) == "table" then
    for _, difficulty in ipairs(group) do
      local hit = killedOn(snap, spec.instance, difficulty, spec.boss)
      if hit then return hit end
    end
    return nil
  end
  return killedOn(snap, spec.instance, group, spec.boss)
end

local function isInstanceSpec(spec)
  return spec and not spec.manual and not spec.camp and not spec.quest and not spec.lfg
    and spec.instance and type(spec.difficulties) == "table" and #spec.difficulties > 0
end

-- Difficulty groups of an instance spec that the snapshot satisfies: a number
-- in spec.difficulties is its own group, a table is an any-of group.
-- -> { [groupIndex] = true }, count, { [groupIndex] = the difficulty the kill
-- was reported on } (two legacy groups met by one size-free kill share it).
-- Other specs (and nil) -> {}, 0, {}.
function Lockouts.GroupsDone(spec, snap)
  local done, count, by = {}, 0, {}
  if not isInstanceSpec(spec) then return done, count, by end
  for i, group in ipairs(spec.difficulties) do
    local hit = groupSatisfied(snap, spec, group)
    if hit then
      done[i] = true
      by[i] = hit
      count = count + 1
    end
  end
  return done, count, by
end

-- An instance spec with more than one group, some but not all done ->
-- { done = { difficulty IDs }, open = { difficulty IDs } } (a group's first
-- ID stands for it), else nil. For the checklist row's "Heroic done" line.
function Lockouts.Progress(spec, snap)
  if not isInstanceSpec(spec) or #spec.difficulties < 2 then return nil end
  local done, count, by = Lockouts.GroupsDone(spec, snap)
  if count == 0 or count == #spec.difficulties then return nil end
  local out = { done = {}, open = {} }
  for i, group in ipairs(spec.difficulties) do
    local first = type(group) == "table" and group[1] or group
    if done[i] then out.done[#out.done + 1] = by[i] else out.open[#out.open + 1] = first end
  end
  return out
end

-- A camp spec ({ camp = true, zone = }): a rare spawn with no known kill
-- flag and no reset. Nothing the game reports marks it, no hand tick spends
-- it, it never counts attempts; it stays on the checklist until the mount is
-- owned (Checklist.Build's "camp" list).
function Lockouts.IsCamp(spec)
  return type(spec) == "table" and spec.camp == true
end

-- spec nil -> nil (not tracked); else "done" | "open" | "manual" | "camp"
-- (Lockouts.IsCamp: never done).
function Lockouts.State(spec, snap, isQuestDone, isLfgDone)
  if not spec then return nil end
  if spec.camp then return "camp" end
  if spec.manual then return "manual" end
  if spec.quest then
    return (isQuestDone and isQuestDone(spec.quest)) and "done" or "open"
  end
  if spec.lfg then
    return (isLfgDone and isLfgDone(spec.lfg)) and "done" or "open"
  end
  if spec.instance and spec.difficulties and #spec.difficulties > 0 then
    for _, group in ipairs(spec.difficulties) do
      if not groupSatisfied(snap, spec, group) then return "open" end
    end
    return "done"
  end
  return "open"
end

-- Wrong-difficulty check (UI/DifficultyCheck.lua) ------------------------------

-- The difficulty IDs a spec's mount drops on (its groups flattened) -> set.
function Lockouts.DropDifficulties(spec)
  local set = {}
  for _, group in ipairs(type(spec) == "table" and spec.difficulties or {}) do
    if type(group) == "table" then
      for _, d in ipairs(group) do set[d] = true end
    else
      set[group] = true
    end
  end
  return set
end

-- The mounts of `mountIDs` that drop in instance `instanceID` but not on
-- `difficultyID` -> { { id =, wanted = { difficulty IDs, sorted }, journal =
-- true when the Encounter Journal said so } }. The journal decides when it
-- knows the mount in this instance (drops = ns.Data.JournalDrops: { map =,
-- d = difficulty IDs or nil for every one }); else specFor(mountID) -> the
-- lockout spec (Lockouts.SpecFor). A mount that drops on this difficulty, or
-- that neither knows here, is left out.
function Lockouts.WrongDifficulty(mountIDs, instanceID, difficultyID, specFor, drops)
  local out = {}
  if not (instanceID and difficultyID) then return out end
  for _, id in ipairs(mountIDs or {}) do
    local journal = drops and drops[id]
    local set
    if type(journal) == "table" and journal.map == instanceID then
      set = {}
      for _, d in ipairs(journal.d or {}) do set[d] = true end
      if not journal.d then set = nil end -- every difficulty
    else
      journal = nil
      local spec = specFor and specFor(id)
      if type(spec) == "table" and spec.instance == instanceID and type(spec.difficulties) == "table" then
        set = Lockouts.DropDifficulties(spec)
      end
    end
    if set then
      -- A hand-written spec's 10 / 25 drops may be on the size-free
      -- difficulty now (the journal lists those itself, as for Firelands).
      local here = set[difficultyID]
      for legacy, modern in pairs(Lockouts.LEGACY_AS) do
        if not journal and set[legacy] and modern == difficultyID then here = true end
      end
      if next(set) and not here then
        local wanted = {}
        for d in pairs(set) do wanted[#wanted + 1] = d end
        table.sort(wanted)
        out[#out + 1] = { id = id, wanted = wanted, journal = journal ~= nil }
      end
    end
  end
  return out
end
