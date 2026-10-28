local ADDON, ns = ...

-- Attempt counting from lockout transitions. Pure Lua, no WoW API: the
-- caller passes observations and predicates in.
local Attempts = {}
ns.Attempts = Attempts

-- obs = { snap=, quests={[id]=bool}, lfg={[id]=bool} }; missing = not done.
local function stateOf(spec, obs)
  local quests, lfg = obs.quests or {}, obs.lfg or {}
  return ns.Lockouts.State(spec, obs.snap or {},
    function(id) return quests[id] == true end,
    function(id) return lfg[id] == true end)
end

-- New attempts between two observations, for mounts that are not owned.
-- Instance specs count +1 per difficulty group that became satisfied (a
-- Heroic-only kill on { 14, 15, 16 } is one attempt, a Mythic kill later the
-- same week another; an any-of group counts once however many of its
-- difficulties are killed). Quest and LFG specs count +1 on open -> done.
-- -> mountIDs in input order, a mount repeated once per new attempt (callers
-- Add each). prev == nil (first observation) counts nothing; a mountID listed
-- twice in mountIDs is considered once.
function Attempts.Newly(prev, curr, mountIDs, specFor, isOwned)
  local out = {}
  if not prev or not curr then return out end
  local seen = {}
  for _, mountID in ipairs(mountIDs or {}) do
    if not seen[mountID] then
      seen[mountID] = true
      local spec = specFor(mountID)
      -- Manual and camp specs have no lockout the game reports: nothing to count.
      if spec and not spec.manual and not spec.camp and not (isOwned and isOwned(mountID)) then
        if spec.quest or spec.lfg then
          if stateOf(spec, prev) == "open" and stateOf(spec, curr) == "done" then
            out[#out + 1] = mountID
          end
        else
          local before = ns.Lockouts.GroupsDone(spec, prev.snap or {})
          local after, _, by = ns.Lockouts.GroupsDone(spec, curr.snap or {})
          -- One kill is one attempt, even when a size-free Normal kill meets
          -- both a 10- and a 25-player group.
          local counted = {}
          for i in pairs(after) do
            if not before[i] and not counted[by[i]] then
              counted[by[i]] = true
              out[#out + 1] = mountID
            end
          end
        end
      end
    end
  end
  return out
end

-- store: { [mountID] = count } (one character's counters, or the legacy
-- account-wide ns.db.global.attempts from before F8).
function Attempts.Add(store, mountID)
  store[mountID] = (store[mountID] or 0) + 1
end

function Attempts.Get(store, mountID)
  return store[mountID] or 0
end

-- byChar: ns.db.global.attemptsByChar = { [charKey] = { [mountID] = count } }.
-- +1 for `mountID` on `charKey`, creating (or replacing junk with) its table.
function Attempts.AddForChar(byChar, charKey, mountID)
  local mine = byChar[charKey]
  if type(mine) ~= "table" then
    mine = {}
    byChar[charKey] = mine
  end
  Attempts.Add(mine, mountID)
end

local function count(store, mountID)
  local n = type(store) == "table" and store[mountID] or nil
  return type(n) == "number" and n or nil
end

-- Sum of `mountID` over every character of { [charKey] = { [mountID] = n } }
-- -> total or nil when no character has a number, and this character's n.
local function overChars(byChar, mountID, charKey)
  if type(byChar) ~= "table" then return nil, nil end
  local total, mine = nil, nil
  for key, counts in pairs(byChar) do
    local n = count(counts, mountID)
    if n then
      total = (total or 0) + n
      if key == charKey then mine = n end
    end
  end
  return total, mine
end

-- Attempts on a mount for the tooltip (F8) -> { this =, total = }.
-- ctx = {
--   charKey  = this character's key (Game.CharKey),
--   hasStats = the mount has kill statistic IDs (Data.Mounts `stats`),
--   stats    = ns.db.global.stats { [charKey] = { [mountID] = kills } },
--   byChar   = ns.db.global.attemptsByChar (our per-character counters),
--   legacy   = ns.db.global.attempts (the account-wide counter of earlier
--              versions: counted in the total only, never as this character's),
--   rarity   = Rarity's attempt count, or nil when unreadable,
-- }
-- this: this character's statistics reading when the mount has statistics
-- and one exists, else this character's own counter.
-- total: the statistics summed over characters when the mount has
-- statistics and any reading, else every character's counter + legacy; then
-- Rarity's count when larger. Stale readings of a mount without statistics
-- are ignored.
function Attempts.Summary(mountID, ctx)
  ctx = type(ctx) == "table" and ctx or {}
  local charKey = ctx.charKey
  local statTotal, statMine
  if ctx.hasStats then statTotal, statMine = overChars(ctx.stats, mountID, charKey) end
  local counted, counterMine = overChars(ctx.byChar, mountID, charKey)

  local this = statMine or counterMine or 0
  local total = statTotal
  if not total then
    total = (counted or 0) + (count(ctx.legacy, mountID) or 0)
  end
  local rarity = ctx.rarity
  if type(rarity) == "number" and rarity > total then total = rarity end
  -- Mixed sources (alts' statistics, this character's counter) could put
  -- this character above the total; the total includes this character.
  if this > total then total = this end
  return { this = this, total = total }
end
