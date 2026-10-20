local ADDON, ns = ...

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

-- The lists' search: the UI side of Logic/Search.lua, which only scores the
-- text it is given. UI.SearchFields turns a mount into that text (its source
-- lines by label kind, route boss and instance, zone, expansion, ...),
-- UI.SearchMatches runs it for any list's search box, and every box shares
-- one cache of the prepared fields. Loads after UI/List.lua, whose source
-- helpers (UI.SourcePairs, UI.SourceLabelKind, UI.RouteEntry) it reads.

local labelKinds = UI.SourceLabelKinds
local scannedAchievementName = UI.ScannedAchievementName
local routeEntry = UI.RouteEntry

-- One cache of the search's prepared fields (Search.Prepare by mount ID) for
-- every search box: a full one holds ~1.7 MB, so the pages share it, and it
-- goes when the window closes (fresh source text on the next search).
local searchCache = {}
function UI.SearchCache() return searchCache end
function UI.ClearSearchCache() searchCache = {} end

-- The home page's search (Search.Select over UI.SearchFields: typos, short
-- names such as tbc / icc, bosses, zones, achievements, expansions) for
-- any list's search box: the mounts of `ids` (a list of mount IDs) that
-- match `search` -> { [mountID] = true }, or nil when the search is empty
-- (everything matches). `cache` (optional): prepared fields by mount ID.
-- When none of `ids` match but the search names a place (icc, a boss, a
-- zone) whose mounts are mostly of one expansion, the mounts of `ids` of that
-- expansion match instead (icc on Vendors: the Wrath vendors); the second
-- result is then that expansion (m.exp).
function UI.SearchMatches(ids, search, sourceText, cache, noFallback)
  if type(search) ~= "string" or not string.find(search, "%S") or not ns.Search then return nil end
  cache = cache or UI.SearchCache()
  local mounts = (ns.Data and ns.Data.Mounts) or {}
  local subset = {}
  for _, id in ipairs(ids or {}) do
    if mounts[id] then subset[id] = mounts[id] end
  end
  local ctx = { sourceText = sourceText, mapName = ns.Game and ns.Game.MapName }
  local found = {}
  for _, r in ipairs(ns.Search.Select(subset, {
    search = search, cache = cache,
    gate = function() return false end,
    fields = function(id, m) return UI.SearchFields(id, m, ctx) end,
  })) do
    found[r.id] = true
  end
  if noFallback or next(found) or not ids or #ids == 0 then return found end
  local exp = UI.SearchExpansion(search, sourceText, cache)
  if exp then return UI.SearchMatches(ids, L[exp] or exp, sourceText, cache, true), exp end
  return found
end

-- The expansion a search points at over every mount: the m.exp of at least
-- half its outright place matches (boss, instance, zone, achievement) ->
-- m.exp, or nil.
function UI.SearchExpansion(search, sourceText, cache)
  if not ns.Search then return nil end
  cache = cache or UI.SearchCache()
  local mounts = (ns.Data and ns.Data.Mounts) or {}
  local ctx = { sourceText = sourceText, mapName = ns.Game and ns.Game.MapName }
  local counts, total = {}, 0
  for _, r in ipairs(ns.Search.Select(mounts, {
    search = search, cache = cache,
    gate = function() return false end,
    fields = function(id, m) return UI.SearchFields(id, m, ctx) end,
  })) do
    -- Only where a place matched outright (a word or abbreviation, no typos).
    if r.field ~= "name" and r.field ~= "expansion" and r.score >= 3 * r.matched then
      local exp = mounts[r.id] and mounts[r.id].exp
      total = total + 1
      if exp then counts[exp] = (counts[exp] or 0) + 1 end
    end
  end
  local best, n = nil, 0
  for exp, c in pairs(counts) do
    if c > n or (c == n and best and exp < best) then best, n = exp, c end
  end
  if best and n * 2 >= total then return best end
  return nil
end

-- Searchable text of a mount for Search.Select -> { name =, boss =,
-- instance =, zone =, achievement =, expansion =, other = } (lists of
-- strings): the client's source text by label kind (Drop -> boss, Zone /
-- Location -> zone, Achievement -> achievement, anything else -> other),
-- the achievement scan's name, the data group (instance / zone / faction /
-- profession) and route instance and boss, the coordinates' map name
-- (ctx.mapName), the expansion, and the section and holiday labels.
-- ctx: { sourceText = fn(id), mapName = fn(mapID) } (both optional).
function UI.SearchFields(id, m, ctx)
  ctx = ctx or {}
  m = m or {}
  local f = { name = { m.name }, boss = {}, instance = {}, zone = {}, achievement = {}, expansion = {}, other = {} }
  local function add(kind, text)
    if type(text) == "string" and text ~= "" then f[kind][#f[kind] + 1] = text end
  end
  local kinds = labelKinds()
  local text = ctx.sourceText and ctx.sourceText(id) or nil
  for _, pair in ipairs(UI.SourcePairs(text)) do
    local kind = pair.label and UI.SourceLabelKind(pair.label, kinds) or nil
    if kind == "drop" then
      add("boss", pair.value)
    elseif kind == "zone" then
      add("zone", pair.value)
    elseif kind == "achievement" then
      add("achievement", pair.value)
    elseif kind ~= "cost" then
      add("other", pair.value)
    end
  end
  add("achievement", scannedAchievementName(id))
  local entry = routeEntry(id)
  if entry then
    add("boss", entry.boss)
    add("instance", entry.instance)
  end
  local section = m.section
  if section == "dungeon" or section == "raid" then
    add("instance", m.group)
  elseif section == "world" or section == "treasure" or section == "quest" or section == "activity" then
    add("zone", m.group)
  else
    add("other", m.group)
  end
  local coords = m.coords
  if ctx.mapName and type(coords) == "table" and coords.m then add("zone", ctx.mapName(coords.m)) end
  if m.exp then add("expansion", L[m.exp]) end
  if section then add("other", UI.SectionLabel(section)) end
  return f
end
