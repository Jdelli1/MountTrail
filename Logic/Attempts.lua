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
      if spec and not spec.manual and not (isOwned and isOwned(mountID)) then
        if spec.quest or spec.lfg then
          if stateOf(spec, prev) == "open" and stateOf(spec, curr) == "done" then
            out[#out + 1] = mountID
          end
        else
          local before = ns.Lockouts.GroupsDone(spec, prev.snap or {})
          local after = ns.Lockouts.GroupsDone(spec, curr.snap or {})
          for i in pairs(after) do
            if not before[i] then out[#out + 1] = mountID end
          end
        end
      end
    end
  end
  return out
end

-- store: account-wide { [mountID] = count }.
function Attempts.Add(store, mountID)
  store[mountID] = (store[mountID] or 0) + 1
end

function Attempts.Get(store, mountID)
  return store[mountID] or 0
end
