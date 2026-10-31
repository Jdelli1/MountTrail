local ADDON, ns = ...

-- Custom checklists: named lists of mounts the player builds (the detail
-- pane's "+ List"), shown in the Checklist under "My lists" and as pop-out
-- windows. Pure Lua over a store table (ns.db.global.lists, account-wide):
--   { nextID = n, lists = { [id] = { name =, mounts = { mountID, ... },
--     sort = "expansion" | nil } } }
-- Mount order is the order they were added, until the player moves one
-- (Lists.Move, Lists.MoveBefore). `sort`: how the list is shown, in that
-- order (nil, the default) or under expansion headers (Lists.Ordered).
local Lists = {}
ns.Lists = Lists

local MAX_NAME = 40

local function lists(store)
  if type(store.lists) ~= "table" then store.lists = {} end
  return store.lists
end

local function cleanName(name)
  if type(name) ~= "string" then return nil end
  name = string.match(name, "^%s*(.-)%s*$")
  if name == "" then return nil end
  if #name > MAX_NAME then name = string.sub(name, 1, MAX_NAME) end
  return name
end

-- A new empty list -> its id (nil for an empty name).
function Lists.Create(store, name)
  name = cleanName(name)
  if not name then return nil end
  local id = tonumber(store.nextID) or 1
  store.nextID = id + 1
  lists(store)[id] = { name = name, mounts = {} }
  return id
end

function Lists.Get(store, id)
  local l = lists(store)[id]
  return type(l) == "table" and l or nil
end

-- -> true when renamed.
function Lists.Rename(store, id, name)
  local l, clean = Lists.Get(store, id), cleanName(name)
  if not (l and clean) then return false end
  l.name = clean
  return true
end

function Lists.Delete(store, id)
  lists(store)[id] = nil
end

function Lists.Has(store, id, mountID)
  local l = Lists.Get(store, id)
  if not l then return false end
  for _, m in ipairs(l.mounts or {}) do
    if m == mountID then return true end
  end
  return false
end

function Lists.Add(store, id, mountID)
  local l = Lists.Get(store, id)
  if not l or Lists.Has(store, id, mountID) then return false end
  l.mounts = l.mounts or {}
  l.mounts[#l.mounts + 1] = mountID
  return true
end

function Lists.Remove(store, id, mountID)
  local l = Lists.Get(store, id)
  if not l then return false end
  for i, m in ipairs(l.mounts or {}) do
    if m == mountID then
      table.remove(l.mounts, i)
      return true
    end
  end
  return false
end

-- Adds when missing, removes when there -> true when now in the list.
function Lists.Toggle(store, id, mountID)
  if Lists.Has(store, id, mountID) then
    Lists.Remove(store, id, mountID)
    return false
  end
  return Lists.Add(store, id, mountID)
end

-- -> { { id =, name =, count = } } sorted by name (case-insensitive), then id.
function Lists.Sorted(store)
  local out = {}
  for id, l in pairs(lists(store)) do
    if type(l) == "table" and l.name then
      out[#out + 1] = { id = id, name = l.name, count = #(l.mounts or {}) }
    end
  end
  table.sort(out, function(a, b)
    local na, nb = string.lower(a.name), string.lower(b.name)
    if na ~= nb then return na < nb end
    return a.id < b.id
  end)
  return out
end

local function indexOf(l, mountID)
  for i, m in ipairs(l.mounts or {}) do
    if m == mountID then return i end
  end
  return nil
end

-- Moves a mount one place (`delta` -1 up, +1 down) -> true when it moved.
function Lists.Move(store, id, mountID, delta)
  local l = Lists.Get(store, id)
  local i = l and indexOf(l, mountID)
  local j = i and i + delta
  if not (j and j >= 1 and j <= #l.mounts) then return false end
  l.mounts[i], l.mounts[j] = l.mounts[j], l.mounts[i]
  return true
end

-- Moves a mount to just before `beforeID` (nil or not on the list: to the
-- end) -> true when the order changed.
function Lists.MoveBefore(store, id, mountID, beforeID)
  local l = Lists.Get(store, id)
  local i = l and indexOf(l, mountID)
  if not i or mountID == beforeID then return false end
  local before = {}
  for k, m in ipairs(l.mounts) do before[k] = m end
  table.remove(l.mounts, i)
  local j = beforeID ~= nil and indexOf(l, beforeID) or nil
  table.insert(l.mounts, j or (#l.mounts + 1), mountID)
  for k, m in ipairs(l.mounts) do
    if before[k] ~= m then return true end
  end
  return false
end

Lists.SORTS = { "added", "expansion" }

-- How a list is shown: "added" (its own order, the default) or "expansion".
function Lists.SortOf(store, id)
  local l = Lists.Get(store, id)
  return (l and l.sort == "expansion") and "expansion" or "added"
end

function Lists.SetSort(store, id, sort)
  local l = Lists.Get(store, id)
  if not l then return false end
  l.sort = sort == "expansion" and "expansion" or nil
  return true
end

-- `ids` (a list's mounts, in its order) for showing -> { { id =, exp = } }:
-- that order for "added"; for "expansion", by expansion in `expansions`'
-- order (unknown last), the list's order inside each. mounts: { [id] = m }.
function Lists.Ordered(ids, mounts, sort, expansions)
  local out = {}
  for i, mountID in ipairs(ids or {}) do
    local m = mounts and mounts[mountID]
    out[#out + 1] = { id = mountID, exp = m and m.exp or nil, index = i }
  end
  if sort ~= "expansion" then return out end
  local rank = {}
  for i, name in ipairs(expansions or {}) do rank[name] = i end
  local last = #(expansions or {}) + 1
  table.sort(out, function(a, b)
    local ra, rb = rank[a.exp] or last, rank[b.exp] or last
    if ra ~= rb then return ra < rb end
    return a.index < b.index
  end)
  return out
end
