local ADDON, ns = ...

-- Journal list selection and counts. Pure Lua, no WoW API: ownership and
-- client knowledge come in as functions.
local Journal = {}
ns.Journal = Journal

-- Saved filter tables may predate a section key: a missing key means shown.
Journal.DefaultFilters = {
  dungeon = true, raid = true, world = true, delve = true, treasure = true,
  quest = true, activity = true, reputation = true, vendor = true, other = true,
  collected = false,
}

local ORDER = {
  journal = { "dungeon", "raid", "world", "delve", "treasure", "quest", "activity",
    "reputation", "vendor", "other" },
  misc = { "achievement", "profession", "shop", "tradingpost", "other" },
  holiday = { "hallowsend", "brewfest", "loveisintheair", "noblegarden", "winterveil",
    "lunarfestival", "midsummer", "darkmoon", "timewalking", "anniversary", "other" },
}

-- Section order of each list view (Journal.Select with query.view). The
-- Achievements view has no fixed list: its sections are expansion names
-- (Data.Expansions order) and "General" last.
local VIEW_ORDER = {
  journal = ORDER.journal,
  holidays = { "hallowsend", "brewfest", "loveisintheair", "noblegarden", "winterveil",
    "lunarfestival", "midsummer", "darkmoon", "anniversary", "other" },
  timewalking = { "timewalking" },
  misc = { "profession", "shop", "tradingpost", "other" },
}

local function rankOf(list)
  local rank = {}
  for i, key in ipairs(list) do rank[key] = i end
  return rank
end

local RANK, VIEW_RANK = {}, {}
for tab, list in pairs(ORDER) do RANK[tab] = rankOf(list) end
for view, list in pairs(VIEW_ORDER) do VIEW_RANK[view] = rankOf(list) end

-- The list views, in tab order (UI/Frame.lua's tabs minus Route).
Journal.Views = { "journal", "holidays", "achievements", "timewalking", "misc" }

-- Section key of achievement mounts without an expansion.
Journal.GENERAL = "General"

-- The list view a mount belongs to: "journal", "holidays", "achievements",
-- "timewalking" or "misc". Timewalking takes the holiday timewalking section
-- and any SimpleArmory "Timewalking" subcat (group); Achievements takes the
-- misc achievement section. Every mount is in exactly one view.
function Journal.ViewOf(m)
  local tab, section = m.tab, m.section
  if m.group == "Timewalking" or (tab == "holiday" and section == "timewalking") then
    return "timewalking"
  end
  if tab == "misc" and section == "achievement" then return "achievements" end
  if tab == "holiday" then return "holidays" end
  return tab
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

-- The same gate for other lists (Logic/Zone.lua): (id, m, isOwned, exists,
-- faction) -> owned (boolean), or nil when the mount is excluded.
Journal.Gate = gate

-- Generated sections the client's source text may refine (delves and caches
-- the data does not label).
local REFINABLE = { world = true, treasure = true, quest = true, activity = true, other = true }

-- Section a mount is listed under. sourceText is the client's source string
-- (Game.MountSourceText) or a function(id) returning it; it is only consulted
-- for journal-tab mounts in a refinable section. "Delve" (case-insensitive)
-- -> delve, else "Cache" -> treasure, else the generated section.
function Journal.SectionOf(id, m, sourceText)
  local section = m.section
  if m.tab ~= "journal" or not REFINABLE[section] or sourceText == nil then return section end
  local text = sourceText
  if type(text) == "function" then text = text(id) end
  if type(text) ~= "string" then return section end
  text = text:lower()
  if text:find("delve", 1, true) then return "delve" end
  if text:find("cache", 1, true) then return "treasure" end
  return section
end

-- Achievements view: expansion name -> rank (query.expansions, else
-- Data.Expansions), unknown expansions after the list, General last.
local function expansionRank(ns, list)
  list = list or (ns.Data and ns.Data.Expansions) or {}
  local rank = rankOf(list)
  rank[Journal.GENERAL] = 1000000
  return rank
end

-- query: { view= | tab=, exp=, section=, filters=, search=, isOwned=fn(id),
-- exists=fn(id), faction=, sourceText=fn(id)|nil, expansions=list|nil,
-- pin={[section]=true}|nil }.
-- view (one of Journal.Views) selects by Journal.ViewOf and wins over tab;
-- tab (data tab "journal"/"holiday"/"misc") is the older raw selection.
-- -> list of { id=, m=, section= } sorted by section order, then name, then
-- id. Sections: journal mounts refined by SectionOf; the Achievements view
-- groups by expansion (m.exp, nil -> "General"); the Timewalking view has the
-- one section "timewalking". Section filters apply on the journal only.
-- pin (e.g. the Holidays tab's active holidays) moves those sections to the
-- top, keeping their usual order among themselves; the rest follow in order.
function Journal.Select(mounts, query)
  local filters = query.filters or Journal.DefaultFilters
  local showCollected = filters.collected == true
  local isOwned, exists = query.isOwned, query.exists
  local view, tab = query.view, query.tab
  local journal = (view or tab) == "journal"
  local sourceText = query.sourceText
  local needle
  if query.search and query.search:find("%S") then
    needle = query.search:lower()
  end

  -- Section of a mount in this list, or nil when it is not in the list.
  local sectionIn
  if view == "achievements" then
    sectionIn = function(_, m)
      if Journal.ViewOf(m) ~= view then return nil end
      return m.exp or Journal.GENERAL
    end
  elseif view == "timewalking" then
    sectionIn = function(_, m)
      return Journal.ViewOf(m) == view and "timewalking" or nil
    end
  elseif view then
    sectionIn = function(id, m)
      return Journal.ViewOf(m) == view and Journal.SectionOf(id, m, sourceText) or nil
    end
  else
    sectionIn = function(id, m)
      return m.tab == tab and Journal.SectionOf(id, m, sourceText) or nil
    end
  end

  local out = {}
  for id, m in pairs(mounts) do
    -- SectionOf may ask the client, so only for mounts in this expansion.
    local section = (query.exp == nil or m.exp == query.exp) and sectionIn(id, m)
    if section
      and (query.section == nil or section == query.section)
      and not (journal and filters[section] == false) then
      local owned = gate(id, m, isOwned, exists, query.faction)
      if owned ~= nil and (showCollected or not owned) then
        local keep = true
        if needle then
          keep = (m.name or ""):lower():find(needle, 1, true) ~= nil
            or (m.group or ""):lower():find(needle, 1, true) ~= nil
        end
        if keep then out[#out + 1] = { id = id, m = m, section = section } end
      end
    end
  end

  local rank
  if view == "achievements" then
    rank = expansionRank(ns, query.expansions)
  elseif view then
    rank = VIEW_RANK[view] or {}
  else
    rank = RANK[tab] or {}
  end
  local none = 1000
  local pin = query.pin or {}
  table.sort(out, function(a, b)
    local pa, pb = pin[a.section] == true, pin[b.section] == true
    if pa ~= pb then return pa end
    local ra, rb = rank[a.section] or none, rank[b.section] or none
    if ra ~= rb then return ra < rb end
    local na, nb = (a.m.name or ""):lower(), (b.m.name or ""):lower()
    if na ~= nb then return na < nb end
    return a.id < b.id
  end)
  return out
end

-- Journal view only (Journal.ViewOf). Returns owned, total. The optional sourceText (as in
-- Select) is accepted so callers can pass the same inputs, but it never
-- changes the totals: Counts span every section, so refining a mount's
-- section cannot move it in or out.
function Journal.Counts(mounts, exp, isOwned, exists, faction, sourceText)
  local owned, total = 0, 0
  for id, m in pairs(mounts) do
    if (exp == nil or m.exp == exp) and Journal.ViewOf(m) == "journal" then
      local o = gate(id, m, isOwned, exists, faction)
      if o ~= nil then
        total = total + 1
        if o then owned = owned + 1 end
      end
    end
  end
  return owned, total
end
