local ADDON, ns = ...

-- How to get a mount, in words, from AllTheThings when it is loaded (read at
-- run time, nothing bundled): the description ATT keeps on the mount's item
-- or spell, else on the NPC that drops or sells it (Alani: "collect ten
-- Skyshards..."). Without ATT every lookup is nil and nothing shows. Plus the
-- mount's Wowhead page (its guides and comments) for the pane's copy box.
local Notes = {}
ns.Notes = Notes

-- ATT's app, or nil. Notes.app (tests) overrides the global lookup
-- (false: none).
local function app()
  if Notes.app ~= nil then return Notes.app or nil end
  local att = _G.AllTheThings
  if type(att) == "table" and type(att.SearchForField) == "function" then return att end
  return nil
end

function Notes.Available()
  return app() ~= nil
end

local function textOf(o)
  local d = type(o) == "table" and o.description or nil
  if type(d) == "string" and string.find(d, "%S") then return d end
  return nil
end

-- The first description among ATT's objects for field = id: the object's
-- own, else its NPC parent's (the boss / rare / vendor it comes from).
local function lookup(att, field, id)
  if not id then return nil end
  local good, found = pcall(att.SearchForField, field, id)
  if not (good and type(found) == "table") then return nil end
  for _, o in ipairs(found) do
    local d = textOf(o)
    if d then return d end
    local parent = type(o) == "table" and o.parent or nil
    if type(parent) == "table" and parent.npcID then
      d = textOf(parent)
      if d then return d end
    end
  end
  return nil
end

local cache = {} -- mountID -> description or false (none), while ATT is loaded

-- -> ATT's description of how to get the mount, or nil.
function Notes.Description(mountID)
  local att = app()
  if not (att and mountID) then return nil end
  local hit = cache[mountID]
  if hit ~= nil then return hit or nil end
  local m = ns.Data and ns.Data.Mounts and ns.Data.Mounts[mountID] or {}
  local d = lookup(att, "itemID", m.item) or lookup(att, "spellID", m.spell)
  if not d then
    -- This character's spots (Map.Spots leaves the other faction's vendors out).
    local map = ns.Map
    local faction = ns.Game and ns.Game.Faction and ns.Game.Faction() or nil
    local spots = map and map.Spots and map.Spots(mountID, faction)
      or (ns.Data and ns.Data.Spots and ns.Data.Spots[mountID]) or {}
    for _, spot in ipairs(spots) do
      d = lookup(att, "npcID", spot.npc)
      if d then break end
    end
  end
  cache[mountID] = d or false
  return d
end

-- The mount's Wowhead page (by its spell, else its item), or nil.
function Notes.WowheadURL(mountID)
  local m = ns.Data and ns.Data.Mounts and ns.Data.Mounts[mountID]
  if not m then return nil end
  if m.spell then return "https://www.wowhead.com/spell=" .. m.spell end
  if m.item then return "https://www.wowhead.com/item=" .. m.item end
  return nil
end
