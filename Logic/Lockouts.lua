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

local function killedOn(snap, instance, difficulty, specBoss)
  local byDiff = snap and snap[instance]
  local bosses = byDiff and byDiff[difficulty]
  if not bosses then return false end
  for name in pairs(bosses) do
    if bossMatches(specBoss, name) then return true end
  end
  return false
end

local function groupSatisfied(snap, spec, group)
  if type(group) == "table" then
    for _, difficulty in ipairs(group) do
      if killedOn(snap, spec.instance, difficulty, spec.boss) then return true end
    end
    return false
  end
  return killedOn(snap, spec.instance, group, spec.boss)
end

local function isInstanceSpec(spec)
  return spec and not spec.manual and not spec.camp and not spec.quest and not spec.lfg
    and spec.instance and type(spec.difficulties) == "table" and #spec.difficulties > 0
end

-- Difficulty groups of an instance spec that the snapshot satisfies: a number
-- in spec.difficulties is its own group, a table is an any-of group.
-- -> { [groupIndex] = true }, count. Other specs (and nil) -> {}, 0.
function Lockouts.GroupsDone(spec, snap)
  local done, count = {}, 0
  if not isInstanceSpec(spec) then return done, count end
  for i, group in ipairs(spec.difficulties) do
    if groupSatisfied(snap, spec, group) then
      done[i] = true
      count = count + 1
    end
  end
  return done, count
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
      if next(set) and not set[difficultyID] then
        local wanted = {}
        for d in pairs(set) do wanted[#wanted + 1] = d end
        table.sort(wanted)
        out[#out + 1] = { id = id, wanted = wanted, journal = journal ~= nil }
      end
    end
  end
  return out
end
