local ADDON, ns = ...

-- The mount list's row model, split out of UI/List.lua (loads right after
-- it): the pure helpers a row reads (route index, UI.SourceLine,
-- UI.SectionLabel), sub-groups (UI.SubGroup, UI.GroupKey),
-- collapse keys (UI.CollapseKey, UI.ToggleCollapsed, UI.ToggleAllCollapsed),
-- the header / mount rows (UI.ListRows) and the header and row text
-- (UI.HeaderHint, UI.HeaderGlyph, UI.HeaderText, UI.RowSourceText). No
-- frames here: the widgets that draw these rows are in UI/List.lua.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

-- Pure helpers -------------------------------------------------------------------

-- mountID -> { boss=, title=, instance= (UI.InstanceName) } for the first route boss row of each mount
-- (depth-first, Data.Route order); routeBossIndex: route boss name -> the
-- instance name of its first route step. Built once, on first use.
local routeIndex, routeBossIndex

local function stripRun(title)
  if type(title) ~= "string" then return nil end
  if string.sub(title, 1, 4) == "Run " then title = string.sub(title, 5) end
  return title
end

-- Instance name of a route step title: "Run <name>" without a trailing
-- "(...Dungeon)" / "(...Raid)" suffix; nil for anything that is not an
-- instance run ("Kill Galleon (World Boss)", "Fly to ...").
function UI.InstanceName(title)
  if type(title) ~= "string" or string.sub(title, 1, 4) ~= "Run " then return nil end
  local name = string.sub(title, 5)
  local inner = string.match(name, "%s*%(([^()]*)%)%s*$")
  if inner and (string.find(inner, "Dungeon", 1, true) or string.find(inner, "Raid", 1, true)) then
    name = string.gsub(name, "%s*%([^()]*%)%s*$", "")
  end
  name = string.match(name, "^%s*(.-)%s*$")
  if name == "" then return nil end
  return name
end

local function buildRouteIndex()
  local index, byBoss = {}, {}
  local function walk(nodes)
    if type(nodes) ~= "table" then return end
    for _, node in ipairs(nodes) do
      if type(node) == "table" then
        for _, boss in ipairs(node.bosses or {}) do
          if type(boss) == "table" and boss.mount and not index[boss.mount] then
            index[boss.mount] = { boss = boss.boss, title = stripRun(node.title),
              instance = UI.InstanceName(node.title) }
          end
          if type(boss) == "table" and boss.boss and not byBoss[boss.boss] then
            byBoss[boss.boss] = UI.InstanceName(node.title)
          end
        end
        walk(node.steps)
      end
    end
  end
  walk(ns.Data and ns.Data.Route)
  return index, byBoss
end

local function ensureRouteIndex()
  if not routeIndex then routeIndex, routeBossIndex = buildRouteIndex() end
end

local function routeEntry(mountID)
  ensureRouteIndex()
  return routeIndex[mountID]
end

-- Instance name (UI.InstanceName) of a route boss's first route step, or nil.
function UI.RouteBossInstance(boss)
  if boss == nil then return nil end
  ensureRouteIndex()
  return routeBossIndex[boss]
end

-- The mount's first route row (Data.Route order): { boss=, title= (step
-- title without "Run "), instance= (UI.InstanceName) }, or nil. Read-only.
function UI.RouteEntry(mountID)
  return routeEntry(mountID)
end

-- Boss name of the mount's first route row (Data.Route order), or nil.
function UI.RouteBoss(mountID)
  local entry = routeEntry(mountID)
  return entry and entry.boss or nil
end

local function mountData(mountID)
  local mounts = ns.Data and ns.Data.Mounts
  return mounts and mounts[mountID] or nil
end

-- "<group> · <boss> (<route step without 'Run '>)", or the parts that exist.
function UI.SourceLine(mountID)
  local m = mountData(mountID) or {}
  local group = (type(m.group) == "string" and m.group ~= "") and m.group or nil
  local where
  local entry = routeEntry(mountID)
  if entry and entry.boss then
    if entry.title and entry.title ~= "" then
      where = entry.boss .. " (" .. entry.title .. ")"
    else
      where = entry.boss
    end
  end
  if group and where then return group .. " · " .. where end
  return group or where or ""
end

local SECTION_NAMES = {
  dungeon = "Dungeon drops", raid = "Raid drops", world = "World drops / rares",
  delve = "Delves", treasure = "Treasures & caches", quest = "Quests",
  activity = "Zone activities", reputation = "Reputation", vendor = "Vendors",
  other = "Other",
  achievement = "Achievements", profession = "Professions", shop = "In-game Shop",
  tradingpost = "Trading Post", pvp = "PvP", racial = "Racial", keystone = "Mythic+",
  promotion = "Promotions", class = "Class", bmah = "Black Market",
  collection = "Collection rewards",
  timewalking = "Timewalking", anniversary = "Anniversary",
  unobtainable = "Unobtainable",
  -- Search results (Search.Select), by what matched.
  search_name = "Mount name", search_boss = "Boss / rare", search_instance = "Dungeon / raid",
  search_zone = "Zone", search_achievement = "Achievement", search_expansion = "Expansion",
  search_other = "Other matches",
}

-- Options "Show unobtainable mounts" (ns.db.global.settings.showUnobtainable):
-- not-owned unobtainable mounts listed on Misc (Journal.Select).
function UI.ShowUnobtainable()
  local global = ns.db and ns.db.global
  local settings = global and global.settings
  return type(settings) == "table" and settings.showUnobtainable == true
end

-- Header text for a section key: holiday titles from Data.Holidays, else the
-- section names above, else the key itself.
function UI.SectionLabel(section)
  local holidays = ns.Data and ns.Data.Holidays
  local holiday = holidays and holidays[section]
  if type(holiday) == "table" and holiday.title then return L[holiday.title] end
  return L[SECTION_NAMES[section] or tostring(section)]
end

-- Sub-groups -------------------------------------------------------------------

-- Sub-group key of mounts whose instance / zone / faction is unknown (sorted
-- last, labelled L["Other"]).
local OTHER_GROUP = "~other"
UI.OTHER_GROUP = OTHER_GROUP

-- Grouping key of a sub-group name: lower case, trimmed, single spaces, a
-- leading "The " dropped, so "The Vortex Pinnacle" and "Vortex Pinnacle"
-- are one group.
function UI.GroupKey(name)
  local key = string.lower(tostring(name))
  key = string.gsub(key, "%s+", " ")
  key = string.match(key, "^%s*(.-)%s*$")
  key = string.gsub(key, "^the ", "")
  return key
end

-- How each section is split: dungeon / raid by instance, world by zone,
-- reputation by faction group. Other sections are flat.
local GROUPED = { dungeon = "instance", raid = "instance", world = "zone", reputation = "faction" }

-- SimpleArmory's catch-all reputation groups (lower case): not a faction.
local GENERIC_FACTION = { reputation = true, renown = true, ["paragon reputation"] = true }

-- Sub-group of a mount listed under `section` -> key, label, fromClient, or
-- nil when the section is flat. Instance: the client's name first (the
-- source text's "Zone:", then the name of the data's coords map), the route
-- step ("Run <name> (Dungeon)") only as the last resort. Zone: "Zone:", then
-- the coords map name. Faction: the data's group, unless it is a catch-all
-- ("Reputation", "Renown", "Paragon Reputation" or the section's own label).
-- Unknown -> OTHER_GROUP, L["Other"]. key is UI.GroupKey(label); fromClient
-- is true unless the label came from the route (ListRows then prefers a
-- client label for the group). ctx (optional): { sourceText = fn(id) ->
-- string|nil, mapName = fn(mapID) -> string|nil }.
function UI.SubGroup(id, m, section, ctx)
  local kind = GROUPED[section]
  if not kind then return nil end
  m = m or {}
  local name, fromClient = nil, true
  if kind == "faction" then
    local group = m.group
    if type(group) == "string" and group ~= "" then
      local lower = string.lower(group)
      if not GENERIC_FACTION[lower] and lower ~= string.lower(UI.SectionLabel(section)) then name = group end
    end
  else
    if ctx and ctx.sourceText then
      name = UI.SourceZone(ctx.sourceText(id))
    end
    local coords = m.coords
    if not name and ctx and ctx.mapName and type(coords) == "table" and coords.m then
      local mapName = ctx.mapName(coords.m)
      if type(mapName) == "string" and mapName ~= "" then name = mapName end
    end
    if not name and kind == "instance" then
      local entry = routeEntry(id)
      name = entry and entry.instance or nil
      fromClient = false
    end
  end
  if name then
    local key = UI.GroupKey(name)
    if key ~= "" then return key, name, fromClient end
  end
  return OTHER_GROUP, L["Other"]
end

-- Saved collapse key of a header: "<view>|<exp or ''>|<section>" for a
-- section, plus "|<sub-group key>" for a sub-header.
function UI.CollapseKey(view, exp, section, group)
  local key = table.concat({ view or "", exp or "", tostring(section) }, "|")
  if group then key = key .. "|" .. group end
  return key
end

-- Flips header `key` in `store` (ns.db.global.collapsed), which holds only
-- collapsed = true (absent = expanded). -> the new collapsed state.
function UI.ToggleCollapsed(store, key)
  if store[key] then
    store[key] = nil
    return false
  end
  store[key] = true
  return true
end

-- Shift-click on a header: every header of that list at once. `rows`: the
-- list's rows as shown; `clicked`: the header's row. A collapsed header
-- expands them all: each shown header and every saved key under one
-- ("<key>|..."), so headers nested inside collapsed ones open too. An open
-- header collapses every shown header. -> true when collapsed.
function UI.ToggleAllCollapsed(store, rows, clicked)
  local collapse = not (clicked and clicked.collapsed)
  for _, row in ipairs(rows or {}) do
    if row.header and row.key ~= nil then
      local key = tostring(row.key)
      if collapse then
        store[key] = true
      else
        store[key] = nil
        local prefix = key .. "|"
        for k in pairs(store) do
          if type(k) == "string" and string.sub(k, 1, #prefix) == prefix then store[k] = nil end
        end
      end
    end
  end
  return collapse
end

-- A header's hover hint -> title, text: its own hint (e.g. "Right-click to
-- pop out ...") over the collapse lines when it collapses; nil when it has
-- neither.
function UI.HeaderHint(hint, collapsible)
  if not collapsible then return hint, nil end
  if hint then return hint, L["Click: collapse or expand. Shift-click: all at once"] end
  return L["Click: collapse or expand"], L["Shift-click: collapse or expand all"]
end

-- Whether Shift is held (a header's Shift-click: all headers at once).
function UI.ShiftDown()
  return type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false
end

local function groupOrder(a, b)
  if (a.key == OTHER_GROUP) ~= (b.key == OTHER_GROUP) then return b.key == OTHER_GROUP end
  return a.key < b.key -- UI.GroupKey: case-insensitive, a leading "The " ignored
end

-- Journal.Select output -> ScrollBox elements, a tree: a section header
-- (the entry's refined section, else the mount's; sections in Select order),
-- then for split sections (UI.SubGroup) a sub-header per instance / zone /
-- faction (by UI.GroupKey, Other last; labelled with a client-provided name
-- when any of its mounts has one, else the route's), then { id=, m=, owned= }
-- mount rows (Select order; depth = 2 under a sub-header). A section stays
-- flat when Other is its only sub-group with a shown mount.
-- Headers: { header = true, depth = 1 | 2, section =, group = (sub-headers),
-- key = UI.CollapseKey(...), text =, badge = (sections only), owned =,
-- total =, collapsed = }. owned / total count every selected mount under the
-- header, including owned ones hidden by opts.hideOwned and children of a
-- collapsed header. Headers with no shown mount are left out; a collapsed
-- header's children are left out.
-- opts (all optional): headerSuffix = fn(section) -> badge, muted, headerActive =
-- fn(section) -> true marks the section header active (row.active = true;
-- UI.HeaderText paints it green), rowTag =
-- fn(id, m) -> tag, view =, exp = (collapse keys), collapsed = { [key] = true },
-- hideOwned = true (drop owned mount rows: the Collected filter is off),
-- sourceText = fn(id), mapName = fn(mapID) (UI.SubGroup's ctx), bare = true
-- (the mounts in the order given, no headers). A section that is an
-- expansion carries exp = its name (its colour, UI.HeaderColor).
function UI.ListRows(selected, isOwned, opts)
  opts = opts or {}
  local headerSuffix, rowTag, headerActive = opts.headerSuffix, opts.rowTag, opts.headerActive
  local collapsed = opts.collapsed or {}
  local hideOwned = opts.hideOwned == true
  local ctx = { sourceText = opts.sourceText, mapName = opts.mapName }
  -- Bare: the mounts in the given order, no headers (a list in the order
  -- its mounts were added).
  if opts.bare then
    local rows = {}
    for _, entry in ipairs(selected or {}) do
      local owned = (isOwned and isOwned(entry.id)) and true or false
      if not (hideOwned and owned) then
        rows[#rows + 1] = { id = entry.id, m = entry.m, owned = owned,
          tag = rowTag and rowTag(entry.id, entry.m) or nil }
      end
    end
    return rows
  end

  local sections, bySection = {}, {}
  for _, entry in ipairs(selected or {}) do
    local section = entry.section or entry.m.section or "other"
    local sec = bySection[section]
    if not sec then
      sec = { key = section, items = {}, groups = {}, byGroup = {} }
      bySection[section] = sec
      sections[#sections + 1] = sec
    end
    local item = { entry = entry, owned = (isOwned and isOwned(entry.id)) and true or false }
    sec.items[#sec.items + 1] = item
    local gkey, glabel, fromClient = UI.SubGroup(entry.id, entry.m, section, ctx)
    if gkey then
      local group = sec.byGroup[gkey]
      if not group then
        group = { key = gkey, label = glabel, client = fromClient == true, items = {} }
        sec.byGroup[gkey] = group
        sec.groups[#sec.groups + 1] = group
      elseif fromClient and not group.client then
        -- A client name (source text / map) beats a route step title.
        group.label, group.client = glabel, true
      end
      group.items[#group.items + 1] = item
    end
  end

  local rows = {}
  local function tally(items)
    local owned, shown = 0, 0
    for _, item in ipairs(items) do
      if item.owned then owned = owned + 1 end
      if not (hideOwned and item.owned) then shown = shown + 1 end
    end
    return owned, #items, shown
  end
  local function addMounts(items, depth)
    for _, item in ipairs(items) do
      if not (hideOwned and item.owned) then
        local entry = item.entry
        rows[#rows + 1] = {
          id = entry.id, m = entry.m, owned = item.owned, depth = depth,
          tag = rowTag and rowTag(entry.id, entry.m) or nil,
        }
      end
    end
  end

  for _, sec in ipairs(sections) do
    local owned, total, shown = tally(sec.items)
    if shown > 0 then
      local key = UI.CollapseKey(opts.view, opts.exp, sec.key)
      local isCollapsed = collapsed[key] == true
      local badge, muted
      if headerSuffix then badge, muted = headerSuffix(sec.key) end
      rows[#rows + 1] = {
        header = true, depth = 1, section = sec.key, key = key, text = UI.SectionLabel(sec.key),
        -- A section that is an expansion takes its colour (UI.HeaderColor).
        exp = (UI.EXPANSION_COLORS and UI.EXPANSION_COLORS[sec.key]) and sec.key or nil,
        badge = badge or nil, badgeMuted = (badge and muted) and true or nil,
        owned = owned, total = total, collapsed = isCollapsed,
        active = (headerActive and headerActive(sec.key)) and true or nil,
      }
      if not isCollapsed then
        -- Sub-groups with at least one shown mount decide the shape.
        local shownGroups = {}
        for _, group in ipairs(sec.groups) do
          local gOwned, gTotal, gShown = tally(group.items)
          if gShown > 0 then
            group.owned, group.total = gOwned, gTotal
            shownGroups[#shownGroups + 1] = group
          end
        end
        if #shownGroups == 0 or (#shownGroups == 1 and shownGroups[1].key == OTHER_GROUP) then
          addMounts(sec.items)
        else
          table.sort(shownGroups, groupOrder)
          for _, group in ipairs(shownGroups) do
            local gkey = UI.CollapseKey(opts.view, opts.exp, sec.key, group.key)
            local gCollapsed = collapsed[gkey] == true
            rows[#rows + 1] = {
              header = true, depth = 2, section = sec.key, group = group.key, key = gkey,
              text = group.label, owned = group.owned, total = group.total, collapsed = gCollapsed,
            }
            if not gCollapsed then addMounts(group.items, 2) end
          end
        end
      end
    end
  end
  return rows
end

local GREEN = "|cff33ff99"
local GREY = "|cff9d9d9d"

-- Collapse glyph of a header, as a pop-out's group header: "+" collapsed,
-- "-" expanded.
function UI.HeaderGlyph(collapsed)
  return collapsed and "+" or "-"
end

-- Header label: section / sub-group name, "(owned/total)" in grey when
-- counted ("(n left)" for a Lockouts header, row.reset), then the badge in green (grey when row.badgeMuted, e.g. a holiday
-- that starts later). Active headers (row.active, e.g. a holiday on the
-- calendar now) paint the name and badge in the game's GREEN_FONT_COLOR.
local ACTIVE_GREEN = "|cff19ff19"
local STATUS_BLUE = "|cff71d5ff"
function UI.HeaderText(row)
  local text = row.text or ""
  if row.active then text = ACTIVE_GREEN .. text .. "|r" end
  if row.total and row.reset then
    -- A Lockouts header counts what is left, as the pop-outs do.
    text = text .. "  " .. GREY .. "(" .. string.format(L["%d left"], row.total - (row.owned or 0)) .. ")|r"
  elseif row.total then
    text = text .. "  " .. GREY .. "(" .. (row.owned or 0) .. "/" .. row.total .. ")|r"
  elseif row.left then
    -- A count where owned/total means nothing (the checklist's rare spawns
    -- with no lockout: mounts still to get).
    text = text .. "  " .. GREY .. "(" .. string.format(L["%d left"], row.left) .. ")|r"
  end
  if row.badge and row.badge ~= "" then
    local color = row.active and ACTIVE_GREEN or (row.badgeMuted and GREY or GREEN)
    text = text .. "  " .. color .. row.badge .. "|r"
  end
  -- A checklist header's event status (F17, Checklist.Rows opts.status).
  if row.status and row.status ~= "" then
    text = text .. "  " .. STATUS_BLUE .. row.status .. "|r"
  end
  return text
end

-- Row source line: the row's description (UI.RowDescription, set per
-- refresh as row.desc), else UI.SourceLine, plus the tag in green.
function UI.RowSourceText(row)
  local text = row.desc or UI.SourceLine(row.id)
  if row.tag and row.tag ~= "" then
    local tag = GREEN .. row.tag .. "|r"
    text = (text ~= "") and (text .. " · " .. tag) or tag
  end
  return text
end
