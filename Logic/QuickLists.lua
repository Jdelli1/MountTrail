local ADDON, ns = ...

-- Built-in lists: ready-made checklists MountTrail ships (at the top of
-- Lists in the left column, before the player's own; poppable like custom lists; not
-- editable). Each is
-- worked out from the data, so a new mount joins on its own:
--   mythic  "Mythic Mounts": every dungeon mount that drops on Mythic
--           difficulty - a lockout spec whose difficulties include 23
--           (Mythic dungeon). The Encounter Journal's own drop table agrees
--           (tools/verify_data.py: JournalItemXDifficulty lists difficulty
--           23 for each of them), plus Smoldering Ember Wyrm, Aerial Unit
--           R-21/X and Cartel Master's Gearglider, which it does not list.
-- Pure Lua: the data tables come in as arguments (default ns.Data).
local QuickLists = {}
ns.QuickLists = QuickLists

local MYTHIC_DUNGEON = 23

local function hasDifficulty(list, id)
  if type(list) ~= "table" then return list == id end
  for _, d in ipairs(list) do
    if hasDifficulty(d, id) then return true end
  end
  return false
end

-- Shown at the top of Lists in the navigation (none at the moment beyond
-- Daily, Weekly and Rare Spawns, the Checklist's groups: UI.NavListEntries).
QuickLists.LISTS = {}

-- Examples: worked out the same way, but given to the player once as a
-- custom list of their own (under Lists: QuickLists.SeedExamples) to edit,
-- rename or delete. Still found by key (a pop-out saved before the move).
QuickLists.EXAMPLES = {
  {
    key = "mythic", name = "Mythic Mounts",
    test = function(id, m, spec)
      return type(spec) == "table" and spec.instance ~= nil and hasDifficulty(spec.difficulties, MYTHIC_DUNGEON)
    end,
  },
}

local byKey = {}
for _, l in ipairs(QuickLists.LISTS) do byKey[l.key] = l end
for _, l in ipairs(QuickLists.EXAMPLES) do byKey[l.key] = l end

function QuickLists.Get(key)
  return byKey[key]
end

-- The mounts of quick list `key` -> mountIDs in expansion order, then name.
-- data: { Mounts =, Lockouts =, Expansions = } (default ns.Data).
function QuickLists.Mounts(key, data)
  local l = byKey[key]
  data = data or ns.Data or {}
  if not l then return {} end
  local mounts, lockouts = data.Mounts or {}, data.Lockouts or {}
  local rank = {}
  for i, exp in ipairs(data.Expansions or {}) do rank[exp] = i end
  local out = {}
  for id, m in pairs(mounts) do
    if l.test(id, m, lockouts[id]) then out[#out + 1] = id end
  end
  table.sort(out, function(a, b)
    local ma, mb = mounts[a], mounts[b]
    local ra, rb = rank[ma.exp] or 99, rank[mb.exp] or 99
    if ra ~= rb then return ra < rb end
    local na, nb = string.lower(ma.name or ""), string.lower(mb.name or "")
    if na ~= nb then return na < nb end
    return a < b
  end)
  return out
end

-- Gives the account each example once (global.seededLists[key]) as a custom
-- list in `store` (Logic/Lists.lua), unless one by that name is already
-- there. Deleting it later does not bring it back. -> ids created.
function QuickLists.SeedExamples(global, store, data)
  if type(global.seededLists) ~= "table" then global.seededLists = {} end
  local made = {}
  for _, l in ipairs(QuickLists.EXAMPLES) do
    if not global.seededLists[l.key] then
      global.seededLists[l.key] = true
      local taken = false
      for _, existing in pairs(type(store.lists) == "table" and store.lists or {}) do
        if type(existing) == "table" and existing.name == l.name then taken = true end
      end
      if not taken then
        local id = ns.Lists.Create(store, l.name)
        for _, mountID in ipairs(QuickLists.Mounts(l.key, data)) do ns.Lists.Add(store, id, mountID) end
        made[#made + 1] = id
      end
    end
  end
  return made
end
