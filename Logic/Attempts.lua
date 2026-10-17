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

-- Mounts whose lockout went open -> done between two observations and that
-- are not owned. prev == nil (first observation) counts nothing. Each mount
-- is returned at most once, in input order.
function Attempts.Newly(prev, curr, mountIDs, specFor, isOwned)
  local out = {}
  if not prev or not curr then return out end
  local seen = {}
  for _, mountID in ipairs(mountIDs or {}) do
    if not seen[mountID] then
      seen[mountID] = true
      local spec = specFor(mountID)
      if spec and not spec.manual and not (isOwned and isOwned(mountID))
        and stateOf(spec, prev) == "open" and stateOf(spec, curr) == "done" then
        out[#out + 1] = mountID
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
