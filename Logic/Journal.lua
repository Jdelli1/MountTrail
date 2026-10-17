local ADDON, ns = ...

-- Journal list selection and counts. Pure Lua, no WoW API: ownership and
-- client knowledge come in as functions.
local Journal = {}
ns.Journal = Journal

Journal.DefaultFilters = {
  dungeon = true, raid = true, world = true, reputation = true,
  vendor = true, other = true, collected = false,
}

local ORDER = {
  journal = { "dungeon", "raid", "world", "reputation", "vendor", "other" },
  misc = { "achievement", "profession", "shop", "tradingpost", "other" },
  holiday = { "hallowsend", "brewfest", "loveisintheair", "noblegarden", "winterveil",
    "lunarfestival", "midsummer", "darkmoon", "timewalking", "anniversary", "other" },
}

local RANK = {}
for tab, list in pairs(ORDER) do
  RANK[tab] = {}
  for i, key in ipairs(list) do RANK[tab][key] = i end
end

-- True when the mount belongs in the player's faction view.
local function factionOk(m, faction)
  if not faction then return true end
  if not m.faction then return true end
  if faction == "Neutral" then return false end
  return m.faction == faction
end

-- Common gate for Select and Counts: known to this client, right faction, and
-- obtainable (or already owned). Returns owned (boolean) or nil when excluded.
local function gate(id, m, isOwned, exists, faction)
  if not exists(id) then return nil end
  if not factionOk(m, faction) then return nil end
  local owned = isOwned(id) and true or false
  if m.unobtainable and not owned then return nil end
  return owned
end

function Journal.Select(mounts, query)
  local filters = query.filters or Journal.DefaultFilters
  local showCollected = filters.collected == true
  local isOwned, exists = query.isOwned, query.exists
  local tab = query.tab
  local needle
  if query.search and query.search:find("%S") then
    needle = query.search:lower()
  end

  local out = {}
  for id, m in pairs(mounts) do
    if m.tab == tab
      and (query.exp == nil or m.exp == query.exp)
      and (query.section == nil or m.section == query.section)
      and not (tab == "journal" and filters[m.section] == false) then
      local owned = gate(id, m, isOwned, exists, query.faction)
      if owned ~= nil and (showCollected or not owned) then
        local keep = true
        if needle then
          keep = (m.name or ""):lower():find(needle, 1, true) ~= nil
            or (m.group or ""):lower():find(needle, 1, true) ~= nil
        end
        if keep then out[#out + 1] = { id = id, m = m } end
      end
    end
  end

  local rank = RANK[tab] or {}
  local none = 1000
  table.sort(out, function(a, b)
    local ra, rb = rank[a.m.section] or none, rank[b.m.section] or none
    if ra ~= rb then return ra < rb end
    local na, nb = (a.m.name or ""):lower(), (b.m.name or ""):lower()
    if na ~= nb then return na < nb end
    return a.id < b.id
  end)
  return out
end

-- Journal tab only. Returns owned, total.
function Journal.Counts(mounts, exp, isOwned, exists, faction)
  local owned, total = 0, 0
  for id, m in pairs(mounts) do
    if m.tab == "journal" and (exp == nil or m.exp == exp) then
      local o = gate(id, m, isOwned, exists, faction)
      if o ~= nil then
        total = total + 1
        if o then owned = owned + 1 end
      end
    end
  end
  return owned, total
end
