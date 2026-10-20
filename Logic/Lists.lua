local ADDON, ns = ...

-- Custom checklists: named lists of mounts the player builds (the detail
-- pane's "+ List"), shown in the Checklist under "My lists" and as pop-out
-- windows. Pure Lua over a store table (ns.db.global.lists, account-wide):
--   { nextID = n, lists = { [id] = { name =, mounts = { mountID, ... } } } }
-- Mount order is the order they were added.
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
