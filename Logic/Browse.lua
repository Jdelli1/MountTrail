local ADDON, ns = ...

-- Browse by source (the navigation column's Browse section): where mounts
-- come from, each category a set of the data's sections. Holidays,
-- Achievements and Timewalking keep their own views (calendar dates,
-- achievement progress, the Timewalking vendors); the rest are pages of the
-- browse view (UI/BrowseView.lua), every mount of the category grouped by
-- expansion. Pure Lua: the caller passes mounts, the gate and the source
-- text.
local Browse = {}
ns.Browse = Browse

-- In navigation order. `view`: an existing view that shows the category;
-- `sections`: the data sections (Journal.SectionOf) a browse page takes;
-- `byGroup`: its page groups mounts by their data group (Faction: the race)
-- instead of by expansion.
Browse.CATEGORIES = {
  { key = "drops", label = "Drops", sections = { "dungeon", "raid", "world", "delve", "treasure" } },
  { key = "vendors", label = "Vendors & Reputation", sections = { "vendor", "reputation" } },
  { key = "quests", label = "Quests & Activities", sections = { "quest", "activity" } },
  { key = "achievements", label = "Achievements", view = "achievements" },
  { key = "professions", label = "Professions", sections = { "profession" } },
  { key = "shop", label = "In-game Shop", sections = { "shop" } },
  { key = "tradingpost", label = "Trading Post", sections = { "tradingpost" } },
  { key = "pvp", label = "PvP", sections = { "pvp" } },
  { key = "faction", label = "Faction", sections = { "racial" }, byGroup = true },
  { key = "keystone", label = "Mythic+", sections = { "keystone" } },
  { key = "holidays", label = "Holidays", view = "holidays" },
  { key = "timewalking", label = "Timewalking", view = "timewalking" },
  { key = "other", label = "Other",
    sections = { "class", "promotion", "bmah", "collection", "other", "unobtainable" } },
}

local byKey, bySection = {}, {}
for _, c in ipairs(Browse.CATEGORIES) do
  byKey[c.key] = c
  for _, s in ipairs(c.sections or {}) do bySection[s] = c.key end
end

-- Whether a category has anything counted: false when every one of its
-- sections is one the player does not count (Journal.excluded; e.g. In-game
-- Shop with "Count in-game shop mounts" off): Home leaves its row out (its
-- Browse page stays).
function Browse.Shown(c)
  if not (c and c.sections) then return true end
  for _, s in ipairs(c.sections) do
    if not (ns.Journal and ns.Journal.excluded and ns.Journal.excluded[s]) then return true end
  end
  return false
end

function Browse.Get(key)
  return byKey[key]
end

-- The IDs of every mount in category `key` (for the search).
function Browse.Ids(key, mounts, sourceText)
  local ids = {}
  for id, m in pairs(mounts or {}) do
    if Browse.CategoryOf(id, m, sourceText) == key then ids[#ids + 1] = id end
  end
  return ids
end

-- The allied races' mounts (one data group, earned by unlocking the race):
-- Faction too, under their own heading.
Browse.ALLIED = "Allied Races"

-- The browse category a mount belongs to (nil for the ones another view
-- shows: holidays, achievements, Timewalking). sourceText as Journal.SectionOf.
function Browse.CategoryOf(id, m, sourceText)
  local view = ns.Journal.ViewOf(m)
  if view == "holidays" or view == "achievements" or view == "timewalking" then return nil end
  if m and m.group == Browse.ALLIED then return "faction" end
  local section = ns.Journal.SectionOf(id, m, sourceText) or "other"
  return bySection[section] or "other"
end

-- A browse page's mounts (UI.List's select): every mount of category `key`
-- the gate keeps (owned ones too: Collected decides), grouped by expansion
-- (section = the expansion's name, Journal.GENERAL without one) in
-- `expansions` order, then by name; a `byGroup` category (Faction) by its
-- data group instead (the race; Allied Races last), alphabetically. query.match ({ [id] = true }, the
-- home page's search: UI.SearchMatches) narrows them, else query.search by
-- name.
-- query: { isOwned, exists, faction, showUnobtainable, sourceText, search, match }.
function Browse.Select(key, mounts, query, expansions)
  local rank = {}
  for i, e in ipairs(expansions or {}) do rank[e] = i end
  local byGroup = byKey[key] and byKey[key].byGroup
  local needle = query.search and string.lower(query.search) or ""
  local out = {}
  for id, m in pairs(mounts or {}) do
    if Browse.CategoryOf(id, m, query.sourceText) == key
      and ns.Journal.Gate(id, m, query.isOwned, query.exists, query.faction, query.showUnobtainable) ~= nil then
      local name = string.lower(m.name or "")
      local hit
      if query.match then hit = query.match[id] == true else hit = needle == "" or string.find(name, needle, 1, true) end
      if hit then
        if byGroup then
          local group = m.group or ns.Journal.GENERAL
          out[#out + 1] = { id = id, m = m, section = group, name = name,
            rank = group == Browse.ALLIED and 2 or 1, group = string.lower(group) }
        else
          out[#out + 1] = { id = id, m = m, section = m.exp or ns.Journal.GENERAL, name = name,
            rank = rank[m.exp] or (#(expansions or {}) + 1) }
        end
      end
    end
  end
  table.sort(out, function(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    if a.group ~= b.group then return (a.group or "") < (b.group or "") end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  return out
end
