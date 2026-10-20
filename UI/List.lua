local ADDON, ns = ...

-- Scrollable mount list shared by the Journal, Holidays, Achievements,
-- Timewalking and Misc tabs: a top
-- row with the search box and a Filter dropdown (UI.CreateFilterDropdown:
-- Collected, plus the view's own sections -- Journal sources, Misc
-- categories, holidays, achievement expansions; none on Timewalking -- as
-- "Show ..." checkboxes with Check all / Uncheck all), and a
-- full-width ScrollBox of section headers and mount rows. Clients without the
-- 11.x dropdown (WowStyle1FilterDropdownTemplate / SetupMenu) get the older
-- left filter panel of checkboxes instead.
--
--   local list = ns.UI.List(parent, getQuery[, opts])
--   list:Refresh([resetScroll])
--
-- getQuery() returns the base query for Journal.Select ({ view= (or the
-- older tab=), exp=, section= }); list.tab is the query's view (else tab),
-- which picks the Filter menu's items and the per-view section filters
-- (ns.db.global.filters[view]; Journal.Select). The list fills in filters (ns.db.global.filters), the search
-- text, isOwned, exists, faction and sourceText (Game.MountSourceText, which
-- refines journal sections into delves / caches) unless the query already has
-- them.
-- opts (optional): { select = fn(mounts, query) -> Journal.Select-shaped
-- list (default Journal.Select; the front page's search uses Search.Select),
-- headerSuffix = fn(sectionKey) -> string|nil, muted (a green
-- badge after the header text; grey when the second return is true),
-- headerActive = fn(sectionKey) -> bool (the
-- header text in green), rowTag = fn(mountID, m) -> string|nil (a green tag
-- after the row's source line) }. The base query may carry pin =
-- {[section]=true} (Journal.Select: those sections first).
-- Rows are a tree (UI.ListRows): section headers, sub-headers (dungeon / raid
-- by instance, world by zone, reputation by faction group), mounts. Headers
-- show +/- and (owned/total) over every mount the view's filters select,
-- owned ones included even while Collected is off; left-clicking one
-- collapses or expands it, saved in ns.db.global.collapsed under
-- "<view>|<exp>|<section>[|<sub-group>]" (only collapsed = true is stored).
-- Each mount row's grey line is UI.RowDescription (the most specific source:
-- "Drop: Ultraxion · Dragon Soul", "Achievement: ...", the route boss, else
-- the category), computed once per refresh. Left-click sets a waypoint
-- (Map.SetWaypoint), Shift+left-click opens the world map there (Map.OpenMap);
-- rows with a location (UI.HasLocation) show a small pin on the right.
-- The pure helpers above the widget code (SourceLine, RowDescription,
-- StripMarkup, SourcePairs, MountIcon, SectionLabel,
-- ListRows, SubGroup, SourceZone, InstanceName, CollapseKey, ToggleCollapsed,
-- ToggleAllCollapsed,
-- HeaderIcon, PreviewMount, RowClickAction, HasLocation, PinIcon,
-- the filter menu helpers) are unit-tested; the widget
-- code is built under a stub by tests/ui_build_spec.lua.

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

-- Icon for a row: the client's icon first, else the data's (file ID or
-- Interface\Icons name), else the question mark.
function UI.MountIcon(mountID)
  local _, icon = ns.Game.MountInfo(mountID)
  if icon then return icon end
  local m = mountData(mountID)
  if m and type(m.icon) == "number" then return m.icon end
  if m and type(m.icon) == "string" and m.icon ~= "" then return "Interface\\Icons\\" .. m.icon end
  return 134400 -- INV_Misc_QuestionMark
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

-- Plain text of a Mount Journal source string (Game.MountSourceText), the
-- one sanitiser for every reader of it: hyperlinks (|H...|h text |h keep
-- their text), named (|cnNAME:) and hex (|cAARRGGBB) colour codes, |r,
-- textures (|T...|t) and atlases (|A...|a) are removed; |n and CRLF become
-- "\n". nil for non-strings.
function UI.StripMarkup(text)
  if type(text) ~= "string" then return nil end
  text = string.gsub(text, "|H.-|h(.-)|h", "%1")
  text = string.gsub(text, "|cn[^:|]*:", "")
  text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
  text = string.gsub(text, "|r", "")
  text = string.gsub(text, "|T.-|t", "")
  text = string.gsub(text, "|A.-|a", "")
  text = string.gsub(text, "|n", "\n")
  text = string.gsub(text, "\r\n?", "\n")
  return text
end

-- Icon markup for display: a texture (|Tpath-or-fileID:h:w...|t) or atlas
-- (|Aname:h:w...|a) with its size fields rewritten to 0, which WoW scales to
-- the font height, so the icon lines up with the text around it.
local function normalizeTexture(body)
  local file = string.match(body, "^([^:]*)")
  if file == "" then return "" end
  return "|T" .. file .. ":0|t"
end

local function normalizeAtlas(body)
  local name = string.match(body, "^:?([^:]*)")
  if name == "" then return "" end
  return "|A" .. name .. ":0:0|a"
end

-- Placeholders ("\1" + a byte >= 128) stand in for icons while the text is
-- split into labels and values (UI.SourcePairs, keepIcons), so a fileID's
-- digits or an icon next to a label never confuse the label detection.
local PLACEHOLDER = "\1[\128-\255]"
local MAX_ICONS = 120

local function hideIcons(text)
  local icons = {}
  local function hide(markup)
    if markup == "" or #icons >= MAX_ICONS then return "" end
    icons[#icons + 1] = markup
    return "\1" .. string.char(127 + #icons)
  end
  text = string.gsub(text, "|T(.-)|t", function(body) return hide(normalizeTexture(body)) end)
  text = string.gsub(text, "|A(.-)|a", function(body) return hide(normalizeAtlas(body)) end)
  return text, icons
end

local function showIcons(text, icons)
  return (string.gsub(text, PLACEHOLDER, function(mark) return icons[string.byte(mark, 2) - 127] or "" end))
end

local function dropIcons(text)
  return (string.gsub(text, PLACEHOLDER, ""))
end

-- UI.StripMarkup that keeps the icons (normalised, see above): the sanitiser
-- for text that is shown. Text that is compared stays on UI.StripMarkup.
function UI.DisplayMarkup(text)
  if type(text) ~= "string" then return nil end
  local hidden, icons = hideIcons(text)
  return showIcons(UI.StripMarkup(hidden), icons)
end

local FULLWIDTH_COLON = "\239\188\154" -- U+FF1A, zhCN / zhTW labels
local MAX_LABEL = 40 -- bytes; longer "labels" are sentences with a colon

local function trim(s)
  return string.match(s, "^%s*(.-)%s*$")
end

-- Comparable form of a label: lower case, without the colon and spaces.
local function labelKey(label)
  if type(label) ~= "string" then return nil end
  label = dropIcons(label)
  label = string.gsub(label, FULLWIDTH_COLON, "")
  label = string.gsub(label, ":", "")
  label = trim(label)
  if label == "" then return nil end
  return string.lower(label)
end

-- Label kinds of the source text: English words plus the client's own
-- (GlobalStrings: BATTLE_PET_SOURCE_n are the Mount Journal's source names,
-- ZONE_COLON / LOCATION_COLON / COSTS_LABEL / CATEGORY) for other locales.
-- Read on each call, so a client without them still works. cost and
-- category only serve to split lines (UI.SourcePairs).
local KIND_WORDS = {
  { kind = "drop", words = { "Drop" }, globals = { "BATTLE_PET_SOURCE_1" } },
  { kind = "quest", words = { "Quest" }, globals = { "BATTLE_PET_SOURCE_2" } },
  { kind = "vendor", words = { "Vendor" }, globals = { "BATTLE_PET_SOURCE_3" } },
  { kind = "achievement", words = { "Achievement" }, globals = { "BATTLE_PET_SOURCE_6" } },
  { kind = "zone", words = { "Zone", "Location" }, globals = { "ZONE_COLON", "LOCATION_COLON" } },
  { kind = "cost", words = { "Cost" }, globals = { "COSTS_LABEL" } },
  { kind = "category", words = { "Category" }, globals = { "CATEGORY" } },
}

local function labelKinds()
  local kinds = {}
  local function add(word, kind)
    local key = labelKey(word)
    if key and not kinds[key] then kinds[key] = kind end
  end
  for _, entry in ipairs(KIND_WORDS) do
    for _, word in ipairs(entry.words) do add(word, entry.kind) end
    for _, name in ipairs(entry.globals) do add(_G[name], entry.kind) end
  end
  return kinds
end

-- Kind of a source label: "drop" | "quest" | "vendor" | "achievement" |
-- "zone" (Zone / Location) | "cost" | "category" | nil.
function UI.SourceLabelKind(label, kinds)
  local key = labelKey(label)
  return key and (kinds or labelKinds())[key] or nil
end

-- "<label>: <value>" -> label (with its colon), value; nil when the line has
-- no short, digit-free label before its first colon.
local function splitLabel(line)
  local label, value = string.match(line, "^([^:]-:)%s*(.*)$")
  local wide, wideValue = string.match(line, "^(.-" .. FULLWIDTH_COLON .. ")%s*(.*)$")
  if wide and (not label or #wide < #label) then label, value = wide, wideValue end
  if not label or #label > MAX_LABEL or string.find(label, "%d") then return nil end
  if not string.find(label, "[^%s:]") then return nil end
  return label, value
end

-- A value that runs into another known label ("Ultraxion Zone: Dragon
-- Soul") -> head, label, tail; nil when no known label (labelKinds) follows a
-- space. Unknown words never split ("Ahead of the Curve: Ultraxion").
local function splitKnown(value, kinds)
  local from = 1
  while true do
    local space = string.find(value, "%s", from)
    if not space then return nil end
    local rest = string.sub(value, space + 1)
    local label = string.match(rest, "^([^:%s][^:]-:)")
    if label and #label <= MAX_LABEL and kinds[labelKey(label)] then
      local head = trim(string.sub(value, 1, space - 1))
      if head ~= "" then return head, label, trim(string.sub(rest, #label + 1)) end
    end
    from = space + 1
  end
end

-- Coloured labels ("|cFFFFD200Zone:|r", "|cnNORMAL_FONT_COLOR:Zone:|r") start
-- a line of their own, even when the client put several on one line.
local function breakColouredLabels(text)
  for _, colon in ipairs({ ":", FULLWIDTH_COLON }) do
    text = string.gsub(text, "(|c%x%x%x%x%x%x%x%x[^|\n]-" .. colon .. "%s*|r)", "|n%1")
    text = string.gsub(text, "(|cn[^:|]*:[^|\n]-" .. colon .. "%s*|r)", "|n%1")
  end
  return text
end

-- The source string's lines (UI.StripMarkup) -> { { label = "Drop:", value =
-- "Ultraxion" }, { value = "<unlabelled line>" }, ... } in order. Labels are
-- the client's own (localised) text with the colon; lines and values are
-- trimmed; empty lines and labels with an empty value are left out. Several
-- labels on one line become several pairs: coloured labels always, plain
-- ones when the label is a known word (UI.SourceLabelKind). With keepIcons
-- the values keep their (normalised) icons; labels never do.
function UI.SourcePairs(text, keepIcons)
  local out = {}
  if type(text) ~= "string" then return out end
  local icons
  if keepIcons then text, icons = hideIcons(text) end
  text = UI.StripMarkup(breakColouredLabels(text))
  local kinds = labelKinds()
  for line in string.gmatch(text .. "\n", "([^\n]*)\n") do
    line = trim(line)
    if line ~= "" then
      local label, value = splitLabel(line)
      if label then
        value = trim(value)
        while label do
          local head, nextLabel, tail = splitKnown(value, kinds)
          if head then value = head end
          if value ~= "" then
            out[#out + 1] = { label = trim(dropIcons(label)), value = icons and showIcons(value, icons) or value }
          end
          label, value = nextLabel, tail
        end
      else
        out[#out + 1] = { value = icons and showIcons(line, icons) or line }
      end
    end
  end
  return out
end

-- True for the label of the zone line: "Zone:", or ZONE_COLON (a
-- GlobalStrings entry) for other locales when the client has it. "Location:"
-- is not a sub-group source (UI.SourceLabelKind counts it as a zone).
local function isZoneLabel(label)
  local key = labelKey(label)
  return key ~= nil and (key == "zone" or key == labelKey(ZONE_COLON))
end

-- The value of the first "Zone:" line of a Mount Journal source string
-- (Game.MountSourceText; UI.SourcePairs), nil when there is none.
function UI.SourceZone(text)
  for _, pair in ipairs(UI.SourcePairs(text)) do
    if pair.label and isZoneLabel(pair.label) then return pair.value end
  end
  return nil
end

-- Every "Zone:" / "Location:" value of a Mount Journal source string, in
-- order (a drop's zone, a vendor's, ...); {} when there is none.
function UI.SourceZones(text)
  local out = {}
  local kinds = labelKinds()
  for _, pair in ipairs(UI.SourcePairs(text)) do
    if pair.label and UI.SourceLabelKind(pair.label, kinds) == "zone" then out[#out + 1] = pair.value end
  end
  return out
end

-- Name of the achievement the achievement scan mapped the mount to, or nil
-- (not an achievement mount, not known yet, or no match).
local function scannedAchievementName(mountID)
  local scan = ns.AchievementScan
  local id = scan and scan.Lookup and scan.Lookup(mountID) or nil
  if not id then return nil end
  local name = ns.Game.AchievementName and ns.Game.AchievementName(id) or nil
  if type(name) == "string" and name ~= "" then return name end
  return nil
end

-- The grey line under a mount row's name: the most specific source the
-- client's source text (Game.MountSourceText, passed in) or our data gives,
-- one line:
--   "Drop: Ultraxion · Dragon Soul" (Drop, plus Zone / Location),
--   "Achievement: <name>" (source text, else the achievement scan's name),
--   "Vendor: <name> · <zone>", "Quest: <name>",
--   another labelled line, not Cost / Category ("Treasure: <name> · <zone>"),
--   the route's "<boss> (<instance>)",
--   a lone "Zone: <name>", an unlabelled line,
--   else UI.SourceLine (the category text; "" when there is none).
-- Labels are the client's own.
function UI.RowDescription(mountID, sourceText)
  local kinds = labelKinds()
  local first, zone, unlabelled, other = {}, nil, nil, nil
  for _, pair in ipairs(UI.SourcePairs(sourceText, true)) do
    if pair.label then
      local kind = UI.SourceLabelKind(pair.label, kinds)
      if kind == "zone" then
        zone = zone or pair
      elseif kind then
        first[kind] = first[kind] or pair
      else
        other = other or pair
      end
    else
      unlabelled = unlabelled or pair.value
    end
  end
  local function text(pair, withZone)
    local out = pair.label .. " " .. pair.value
    if withZone and zone then out = out .. " · " .. zone.value end
    return out
  end

  if first.drop then return text(first.drop, true) end
  if first.achievement then return text(first.achievement) end
  local achievement = scannedAchievementName(mountID)
  if achievement then return string.format(L["Achievement: %s"], achievement) end
  if first.vendor then return text(first.vendor, true) end
  if first.quest then return text(first.quest) end
  if other then return text(other, true) end
  local entry = routeEntry(mountID)
  if entry and entry.boss then
    if entry.instance then return entry.boss .. " (" .. entry.instance .. ")" end
    return entry.boss
  end
  if zone then return text(zone) end
  if unlabelled then return unlabelled end
  return UI.SourceLine(mountID)
end

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
-- sourceText = fn(id), mapName = fn(mapID) (UI.SubGroup's ctx).
function UI.ListRows(selected, isOwned, opts)
  opts = opts or {}
  local headerSuffix, rowTag, headerActive = opts.headerSuffix, opts.rowTag, opts.headerActive
  local collapsed = opts.collapsed or {}
  local hideOwned = opts.hideOwned == true
  local ctx = { sourceText = opts.sourceText, mapName = opts.mapName }

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

-- Collapse indicator of a header: the quest log's campaign header atlas when
-- the client has it (UI.AtlasExists), and the text fallback ("+" collapsed,
-- an en dash expanded: the default font has no U+2212 minus).
-- -> atlas|nil, text.
local ICON_OPEN, ICON_CLOSED = "campaign_headericon_open", "campaign_headericon_closed"
function UI.HeaderIcon(collapsed)
  local atlas = collapsed and ICON_CLOSED or ICON_OPEN
  local text = collapsed and "+" or "\226\128\147"
  if UI.AtlasExists and UI.AtlasExists(atlas) then return atlas, text end
  return nil, text
end

-- Header label: section / sub-group name, "(owned/total)" in grey when
-- counted, then the badge in green (grey when row.badgeMuted, e.g. a holiday
-- that starts later). Active headers (row.active, e.g. a holiday on the
-- calendar now) paint the name and badge in the game's GREEN_FONT_COLOR.
local ACTIVE_GREEN = "|cff19ff19"
local STATUS_BLUE = "|cff71d5ff"
function UI.HeaderText(row)
  local text = row.text or ""
  if row.active then text = ACTIVE_GREEN .. text .. "|r" end
  if row.total then
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

-- Filter menu --------------------------------------------------------------------

-- Saved filters (ns.db.global.filters, Logic/Journal.lua): a global
-- `collected` plus, per list view, { [section] = false } for the hidden
-- sections. Each view's menu offers its own sections (Journal.FilterSections):
-- Journal the ten sources, Misc its categories, Holidays each holiday,
-- Achievements each expansion and General, Timewalking none.

-- Menu title above a view's section checkboxes.
local FILTER_TITLES = {
  journal = "Sources", misc = "Categories", holidays = "Holidays", achievements = "Expansions",
}

-- "Show <category>" labels of the Journal and Misc sections. Holidays use
-- "Show <holiday>", Achievements "Show <expansion> achievements".
local FILTER_LABELS = {
  journal = {
    dungeon = "Show dungeon drops", raid = "Show raid drops", world = "Show world drops / rares",
    delve = "Show delve mounts", treasure = "Show treasures & caches", quest = "Show quest mounts",
    activity = "Show zone activity mounts", reputation = "Show reputation mounts",
    vendor = "Show vendor mounts", other = "Show other mounts",
  },
  misc = {
    profession = "Show profession mounts", shop = "Show in-game shop mounts",
    tradingpost = "Show Trading Post mounts", pvp = "Show PvP mounts", racial = "Show racial mounts",
    keystone = "Show Mythic+ mounts", promotion = "Show promotion mounts", class = "Show class mounts",
    bmah = "Show Black Market mounts", collection = "Show collection rewards",
    other = "Show other mounts",
    unobtainable = "Show unobtainable mounts",
  },
  holidays = { other = "Show other mounts" },
}

-- The menu label of section `key` on `view`.
function UI.FilterLabel(view, key)
  local labels = FILTER_LABELS[view]
  if labels and labels[key] then return L[labels[key]] end
  if view == "achievements" then return string.format(L["Show %s achievements"], UI.SectionLabel(key)) end
  return string.format(L["Show %s"], UI.SectionLabel(key))
end

-- Section keys the Filter menu shows on `view` (Journal.FilterSections;
-- opts.expansions, else Data.Expansions, for Achievements).
local function menuSections(view, opts)
  return ns.Journal.FilterSections(view, opts)
end

-- Whether filter `key` is on: "collected" only when true (default off); a
-- section of `view` unless hidden (Journal.SectionShown: missing = shown).
function UI.FilterChecked(filters, key, view)
  if key == "collected" then return type(filters) == "table" and filters.collected == true end
  return ns.Journal.SectionShown(filters, view, key)
end

-- The Filter dropdown's items for the list view `view` -> { { kind =
-- "checkbox", key =, label =, checked = }, { kind = "divider" }, { kind =
-- "title", label = }, { kind = "button", action = "checkAll" | "uncheckAll",
-- label = } }: Collected, then (views with sections) the view's sections
-- with Check all / Uncheck all. opts (optional): { expansions = } as for
-- Journal.FilterSections (default: Data.Expansions).
function UI.FilterMenuItems(view, filters, opts)
  local items = {
    { kind = "checkbox", key = "collected", label = L["Collected"], checked = UI.FilterChecked(filters, "collected", view) },
  }
  local keys = menuSections(view, opts)
  if #keys == 0 then return items end
  items[#items + 1] = { kind = "divider" }
  items[#items + 1] = { kind = "title", label = L[FILTER_TITLES[view] or "Sources"] }
  for _, key in ipairs(keys) do
    items[#items + 1] = { kind = "checkbox", key = key, label = UI.FilterLabel(view, key),
      checked = UI.FilterChecked(filters, key, view) }
  end
  items[#items + 1] = { kind = "divider" }
  items[#items + 1] = { kind = "button", action = "checkAll", label = L["Check all"] }
  items[#items + 1] = { kind = "button", action = "uncheckAll", label = L["Uncheck all"] }
  return items
end

-- Flips Collected or section `key` of `view` in `filters` -> its new state.
function UI.ToggleFilter(filters, key, view)
  local on = not UI.FilterChecked(filters, key, view)
  if key == "collected" then
    filters.collected = on
  else
    ns.Journal.SetSectionShown(filters, view, key, on)
  end
  return on
end

-- "checkAll" / "uncheckAll": every section the menu shows on `view` on /
-- off (Collected and other views untouched). "reset" (the dropdown's reset
-- arrow): Collected off and every section of `view` shown.
function UI.ApplyFilterAction(filters, action, view, opts)
  if action == "checkAll" or action == "uncheckAll" then
    for _, key in ipairs(menuSections(view, opts)) do
      ns.Journal.SetSectionShown(filters, view, key, action == "checkAll")
    end
  elseif action == "reset" then
    filters.collected = ns.Journal.DefaultFilters.collected
    if view ~= nil and type(filters[view]) == "table" then filters[view] = nil end
  end
end

-- True when what the menu shows on `view` is at the defaults (Collected
-- off, every section shown): no reset arrow.
function UI.FiltersAreDefault(filters, view, opts)
  if UI.FilterChecked(filters, "collected", view) ~= (ns.Journal.DefaultFilters.collected == true) then
    return false
  end
  for _, key in ipairs(menuSections(view, opts)) do
    if not UI.FilterChecked(filters, key, view) then return false end
  end
  return true
end

-- Ctrl+left-click: open the dressing room on the mount.
function UI.PreviewMount(mountID)
  if type(DressUpMount) == "function" then
    return DressUpMount(mountID)
  end
  if type(DressUpMountLink) == "function" then
    local _, _, spellID = ns.Game.MountInfo(mountID)
    local m = mountData(mountID)
    spellID = spellID or (m and m.spell)
    if not spellID then return end
    local link
    if C_Spell and C_Spell.GetSpellLink then
      link = C_Spell.GetSpellLink(spellID)
    elseif GetSpellLink then
      link = GetSpellLink(spellID)
    end
    if link then return DressUpMountLink(link) end
  end
end

-- Row clicks: left-click -> "waypoint" (Map.SetWaypoint), Shift+left-click
-- -> "map" (Map.OpenMap), Ctrl+left-click -> "preview" (Ctrl wins over
-- Shift), Shift+right-click -> "achievement", anything else -> nil (plain
-- right-clicks are reserved).
function UI.RowClickAction(button, ctrl, shift)
  if button == "LeftButton" then
    if ctrl then return "preview" end
    if shift then return "map" end
    return "waypoint"
  end
  if button == "RightButton" and shift then return "achievement" end
  return nil
end

-- Whether a row shows the pin icon: the mount has a location to point at
-- (Map.HasLocation: coords, no API call, so it is cheap on every refresh).
-- false without ns.Map or when the check errors (Game.ReportError).
-- `routeBoss` (optional): the route / checklist row's boss (a per-boss
-- instance spec is a location: Map.HasLocation).
function UI.HasLocation(mountID, routeBoss)
  local map = ns.Map
  if not (mountID and map and type(map.HasLocation) == "function") then return false end
  local good, has = pcall(map.HasLocation, mountID, routeBoss)
  if not good then
    if ns.Game and ns.Game.ReportError then ns.Game.ReportError(has) end
    return false
  end
  return has == true
end

-- Which location icon a row shows: "spot" (a click drops a waypoint on an
-- exact spot or a dungeon / raid entrance, Map.HasSpot), "zone" (only the
-- zone is known: a click opens its map) or nil (no location). Cheap: no API
-- call. A failing check reports to Game.ReportError and counts as a zone.
-- `routeBoss` (optional): the route / checklist row's boss, so a per-boss
-- entrance (e.g. a Vault of Archavon watcher) shows the pin.
function UI.LocationIcon(mountID, routeBoss)
  if not UI.HasLocation(mountID, routeBoss) then return nil end
  local map = ns.Map
  if not (map and type(map.HasSpot) == "function") then return "zone" end
  local good, spot = pcall(map.HasSpot, mountID, routeBoss)
  if not good then
    if ns.Game and ns.Game.ReportError then ns.Game.ReportError(spot) end
    return "zone"
  end
  return spot == true and "spot" or "zone"
end

-- The row pin icon: the chat map-pin atlas (the icon of the client's own map
-- pin links, 9.0+) when the client has it (UI.AtlasExists), and the classic
-- map item icon as the fallback texture. -> atlas|nil, texture.
local PIN_ATLAS = "Waypoint-MapPin-ChatIcon"
local PIN_TEXTURE = "Interface\\Icons\\INV_Misc_Map_01"
function UI.PinIcon()
  if UI.AtlasExists and UI.AtlasExists(PIN_ATLAS) then return PIN_ATLAS, PIN_TEXTURE end
  return nil, PIN_TEXTURE
end

-- Opens the achievement that rewards the mount, when the achievement scan
-- (Integrations/AchievementScan.lua) knows it. In combat it only prints a
-- note. -> true when opened.
function UI.OpenMountAchievement(mountID)
  local scan = ns.AchievementScan
  local id = mountID and scan and scan.Lookup(mountID) or nil
  if not id then return false end
  if ns.Game.InCombat and ns.Game.InCombat() then
    if ns.addon and ns.addon.Print then ns.addon:Print(L["Can't open achievements in combat"]) end
    return false
  end
  return ns.Game.OpenAchievement(id) == true
end

-- With /mtrail debug on, prints a "debug: ..." line straight to chat (not
-- through the error handler, which BugSack-style addons capture silently),
-- so a click that seems to do nothing shows where it stopped.
local function trace(fmt, ...)
  local global = ns.db and ns.db.global
  if not (global and global.debug == true) then return end
  local addon = ns.addon
  if not (addon and addon.Print) then return end
  pcall(addon.Print, addon, "debug: " .. string.format(fmt, ...))
end
UI.DebugTrace = trace

-- Calls ns.Map[method](mountID, nil, routeBoss); an error goes to
-- Game.ReportError (/mtrail debug) instead of breaking the click. Traced with
-- /mtrail debug.
local function mapAction(method, mountID, routeBoss)
  local map = ns.Map
  if not (map and type(map[method]) == "function") then
    trace("%s missing", method)
    return
  end
  local good, place, kind = pcall(map[method], mountID, nil, routeBoss)
  if not good then
    trace("%s(%s) failed: %s", method, tostring(mountID), tostring(place))
    if ns.Game and ns.Game.ReportError then ns.Game.ReportError(place) end
    return
  end
  trace("%s(%s) -> %s, %s", method, tostring(mountID), tostring(kind), tostring(place))
end
-- Map.SetWaypoint / Map.OpenMap for a mount, guarded (the detail pane's buttons).
UI.MapAction = mapAction

-- The one waypoint action everywhere (a row click, the pane's Waypoint
-- button, a pop-out's pin): every spawn point on TomTom when the mount's
-- rare has several (Map.PlotCount / Map.PlotMounts; TomTom clears each as
-- you reach it), else the waypoint (Map.SetWaypoint).
function UI.GoTo(mountID, routeBoss)
  local map = ns.Map
  if map and map.PlotCount and map.PlotCount(mountID, routeBoss) > 1 then
    local good, err = pcall(map.PlotMounts, { mountID }, UI.MountName and UI.MountName(mountID) or nil)
    if not good and ns.Game and ns.Game.ReportError then ns.Game.ReportError(err) end
    return
  end
  mapAction("SetWaypoint", mountID, routeBoss)
end

-- An achievement mount's plain click: opens its achievement in the
-- Achievements window when the achievement scan knows it (-> "achievement");
-- while the scan still looks it up, a note only (-> "pending"); not an
-- achievement mount (or no match) -> nil.
function UI.AchievementClick(mountID)
  local scan = ns.AchievementScan
  if not (mountID and scan and scan.Lookup) then return nil end
  local id, status = scan.Lookup(mountID)
  if id then
    UI.OpenMountAchievement(mountID)
    return "achievement"
  end
  if status == "pending" then
    if ns.addon and ns.addon.Print then ns.addon:Print(L["Achievement: looking up..."]) end
    return "pending"
  end
  return nil
end

-- A mount row's plain click: an achievement mount opens its achievement
-- (UI.AchievementClick), anything else goes there (UI.GoTo).
-- -> "achievement" | "waypoint" | nil (still looking the achievement up).
function UI.RowGo(mountID, routeBoss)
  local done = UI.AchievementClick(mountID)
  if done == "achievement" then return "achievement" end
  if done == "pending" then return nil end
  UI.GoTo(mountID, routeBoss)
  return "waypoint"
end

-- OnClick of a mount row (lists, Checklist and zone panel): reads the modifier keys and
-- runs UI.RowClickAction's action for `mountID`. `routeBoss` (optional): the
-- route / checklist row's boss, so the waypoint and map go to that boss's
-- instance (Map.SetWaypoint / Map.OpenMap) rather than the mount's own place.
-- `eventMap` (optional, checklist rows with an unknown event status): a plain
-- left-click opens that zone's map instead (UI.OpenEventMap).
function UI.HandleRowClick(mountID, button, routeBoss, eventMap)
  if not mountID then
    trace("click %s on a row with no mount", tostring(button))
    return
  end
  local ctrl = type(IsControlKeyDown) == "function" and IsControlKeyDown() and true or false
  local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false
  local action = UI.RowClickAction(button, ctrl, shift)
  trace("click %s on mount %s -> %s", tostring(button), tostring(mountID), tostring(action))
  if action == "waypoint" and eventMap and UI.OpenEventMap then
    UI.OpenEventMap(eventMap)
  elseif action == "waypoint" then
    UI.RowGo(mountID, routeBoss)
  elseif action == "map" then
    mapAction("OpenMap", mountID, routeBoss)
  elseif action == "preview" then
    UI.PreviewMount(mountID)
  elseif action == "achievement" then
    UI.OpenMountAchievement(mountID)
  end
end

-- Rows of a list with the detail pane (no buttons there: the clicks do it).
local function hasAchievement(mountID)
  local scan = ns.AchievementScan
  return scan and scan.Lookup and scan.Lookup(mountID) ~= nil or false
end

-- What a click does on such a row (it also selects it): a plain left-click
-- only selects (nil); right-click "waypoint" (the zone map for an unknown
-- event, the achievement when there is nowhere to go); Shift "map"; Ctrl
-- "achievement" (the preview when it has none) -> action.
function UI.PaneRowAction(mountID, button, ctrl, shift, routeBoss, eventMap)
  if ctrl then return hasAchievement(mountID) and "achievement" or "preview" end
  if shift then return "map" end
  if button ~= "RightButton" then return nil end
  if eventMap or UI.HasLocation(mountID, routeBoss) then return "waypoint" end
  return hasAchievement(mountID) and "achievement" or nil
end

-- A click on a row of a list with the detail pane (after selecting it).
function UI.PaneRowClick(mountID, routeBoss, eventMap, button)
  local ctrl = type(IsControlKeyDown) == "function" and IsControlKeyDown() and true or false
  local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false
  local action = UI.PaneRowAction(mountID, button or "LeftButton", ctrl, shift, routeBoss, eventMap)
  trace("pane click on mount %s -> %s", tostring(mountID), tostring(action))
  if action == "waypoint" and eventMap and UI.OpenEventMap then
    UI.OpenEventMap(eventMap)
  elseif action == "waypoint" then
    UI.GoTo(mountID, routeBoss)
  elseif action == "map" then
    mapAction("OpenMap", mountID, routeBoss)
  elseif action == "achievement" then
    UI.OpenMountAchievement(mountID)
  elseif action == "preview" then
    UI.PreviewMount(mountID)
  end
  return action
end

local KEY_CODE = "|cffffd100"

-- The hover hint's lines on such a row: one per click that does something.
function UI.PaneRowHint(mountID, routeBoss, eventMap)
  local lines = {}
  local function add(key, what) lines[#lines + 1] = KEY_CODE .. key .. "|r  " .. what end
  local located = UI.HasLocation(mountID, routeBoss)
  local achievement = hasAchievement(mountID)
  local map = ns.Map
  local n = located and map and map.PlotCount and map.PlotCount(mountID, routeBoss) or 0
  add(L["Left-click"], L["view"])
  if eventMap then
    add(L["Right-click"], L["open the zone map"])
  elseif n > 1 then
    add(L["Right-click"], string.format(L["plot all %d spawn points"], n))
  elseif located then
    add(L["Right-click"], L["plot the coordinates"])
  elseif achievement then
    add(L["Right-click"], L["view the achievement"])
  end
  if located then add(L["Shift-click"], L["show on the map"]) end
  if achievement then
    add(L["Ctrl-click"], L["view the achievement"])
  else
    add(L["Ctrl-click"], L["preview in the dressing room"])
  end
  return table.concat(lines, "\n")
end

-- The hint's title: the row's name.
function UI.RowHintTitle(row)
  return row.Name and row.Name:GetText() or ""
end

-- Widgets ----------------------------------------------------------------------------

local FILTER_WIDTH = 150 -- fallback filter panel
local SEARCH_WIDTH = 220
local FILTER_BUTTON_WIDTH, FILTER_BUTTON_HEIGHT = 93, 22 -- the Mount Journal's Filter button
local TOP_ROW = 30 -- search box + Filter button above the list
local HEADER_HEIGHT = 24
local SUB_HEADER_HEIGHT = 20
local INDICATOR_SIZE = 14
local SUB_INDENT = 22 -- sub-header indicator inset (section headers: 6); icons of rows under it
local DEPTH_STEP = 16 -- each deeper header level (the checklist's depth 3) moves in this much more
local ROW_ICON_LEFT = 4 -- icon inset of other mount rows
local ROW_HEIGHT = 40
local ICON_SIZE = 32
local CHECK_SIZE = 24
local PIN_SIZE, PIN_RIGHT = 16, 8 -- the location pin on a row's right end
-- Rounded icon mask of the current action bars; used only when the client
-- has it (UI.AtlasExists). Icons are also cropped past their baked-in edge.
local ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"
local ICON_CROP = 0.08

-- Source line font: GameFontHighlightSmall dimmed to 70 % grey (readable on
-- the dark fill); GameFontDisableSmall when the client has no CreateFont.
local SOURCE_FONT = "MountTrailFontSource"
local sourceFont
function UI.SourceFont()
  if sourceFont then return sourceFont end
  if type(CreateFont) == "function" and GameFontHighlightSmall then
    local font = _G[SOURCE_FONT] or CreateFont(SOURCE_FONT)
    font:SetFontObject(GameFontHighlightSmall)
    font:SetTextColor(0.7, 0.7, 0.7)
    sourceFont = SOURCE_FONT
  else
    sourceFont = UI.Font("GameFontDisableSmall")
  end
  return sourceFont
end

-- Name font of owned (collected) mount rows: GameFontNormal in a light green
-- (readable on the dark fill and the green row tint); GameFontGreen when the
-- client has no CreateFont.
local OWNED_FONT = "MountTrailFontOwned"
local ownedFont
function UI.OwnedFont()
  if ownedFont then return ownedFont end
  if type(CreateFont) == "function" and GameFontNormal then
    local font = _G[OWNED_FONT] or CreateFont(OWNED_FONT)
    -- From the add-on's sized copy, so it follows the gold text size.
    font:SetFontObject(_G[UI.Font("GameFontNormal")] or GameFontNormal)
    font:SetTextColor(0.55, 0.95, 0.6)
    ownedFont = OWNED_FONT
  else
    ownedFont = UI.Font("GameFontGreen")
  end
  return ownedFont
end

local function filtersDB()
  return ns.db and ns.db.global and ns.db.global.filters or nil
end

-- Memoised predicate for one refresh: each client call at most once per mount.
local function memo(fn)
  local cache = {}
  return function(id)
    local v = cache[id]
    if v == nil then
      v = fn(id) and true or false
      cache[id] = v
    end
    return v
  end
end

-- Memoised text lookup for one refresh (false caches "no text").
local function memoText(fn)
  local cache = {}
  return function(id)
    local v = cache[id]
    if v == nil then
      v = fn(id)
      if type(v) ~= "string" then v = false end
      cache[id] = v
    end
    return v or nil
  end
end

-- Shared with the zone panel (UI/ZonePanel.lua).
UI.Memo, UI.MemoText = memo, memoText

local function collapsedDB()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.collapsed) ~= "table" then global.collapsed = {} end
  return global.collapsed
end

-- Section header (depth 1) and sub-header (depth 2, indented, smaller font,
-- fainter band; depth 3 -- the checklist's categories -- looks the same, one
-- DEPTH_STEP further in). A plain Frame (not a Button) so the ScrollBox pools it apart
-- from the mount rows; left-click (OnMouseUp) calls frame.onToggle(key), a
-- right-click frame.onRightClick(data, frame) when the caller set one, and hovering
-- shows frame.hint (UI.ShowHint, beside the cursor) when set.
local function initHeader(frame, data)
  if not frame.Label then
    frame:EnableMouse(true)
    -- Flat header: a faint band with a thin gold rule underneath.
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    frame.Bg = bg
    local hover = frame:CreateTexture(nil, "BORDER")
    hover:SetAllPoints(frame)
    hover:SetColorTexture(1, 1, 1, 0.05)
    hover:Hide()
    frame.Hover = hover
    local rule = frame:CreateTexture(nil, "BORDER")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    frame.Rule = rule
    -- +/- indicator: the campaign header atlas, else a text glyph.
    local indicator = frame:CreateTexture(nil, "ARTWORK")
    indicator:SetSize(INDICATOR_SIZE, INDICATOR_SIZE)
    frame.Indicator = indicator
    local indicatorText = frame:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlight"))
    indicatorText:SetPoint("CENTER", indicator, "CENTER", 0, 0)
    frame.IndicatorText = indicatorText
    local label = frame:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
    label:SetPoint("LEFT", indicator, "RIGHT", 6, 0)
    label:SetJustifyH("LEFT")
    frame.Label = label
    frame:SetScript("OnEnter", function(self)
      self.Hover:Show()
      local title, text = UI.HeaderHint(self.hint, self.onToggle ~= nil)
      if title and UI.ShowHint then UI.ShowHint(self, title, text, "cursor") end
    end)
    frame:SetScript("OnLeave", function(self)
      self.Hover:Hide()
      if UI.HideHint then UI.HideHint(self) end
    end)
    frame:SetScript("OnMouseUp", function(self, button)
      -- Only a release over the header counts (pressing, then dragging off
      -- it cancels, as with buttons).
      if type(self.IsMouseOver) == "function" and not self:IsMouseOver() then return end
      if button == "RightButton" and self.onRightClick and self.data then
        self.onRightClick(self.data, self)
        return
      end
      if button ~= "LeftButton" then return end
      -- Shift-click: every header of the list collapses (or, on a collapsed
      -- one, expands) at once.
      if UI.ShiftDown() and self.onToggleAll and self.data then
        self.onToggleAll(self.data, self)
        return
      end
      if not (self.key and self.onToggle) then return end
      self.onToggle(self.key)
    end)
  end
  local depth = data.depth or 1
  local sub = depth >= 2
  frame.key = data.key
  frame.data = data
  -- Recycled frames: the hover band follows the mouse, not the last use.
  frame.Hover:SetShown(type(frame.IsMouseOver) == "function" and frame:IsMouseOver() == true)
  frame.Bg:SetColorTexture(1, 1, 1, sub and 0.025 or 0.05)
  frame.Rule:SetColorTexture(1, 0.82, 0, sub and 0.1 or 0.25)
  frame.Indicator:ClearAllPoints()
  frame.Indicator:SetPoint("LEFT", frame, "LEFT", sub and (SUB_INDENT + (depth - 2) * DEPTH_STEP) or 6, 0)
  local atlas, glyph = UI.HeaderIcon(data.collapsed == true)
  if atlas then
    frame.Indicator:SetAtlas(atlas)
    frame.Indicator:Show()
    frame.IndicatorText:Hide()
  else
    frame.Indicator:Hide()
    frame.IndicatorText:SetText(glyph)
    frame.IndicatorText:Show()
  end
  frame.Label:SetFontObject(sub and UI.Font("GameFontNormalSmall") or UI.Font("GameFontNormal"))
  frame.Label:SetText(UI.HeaderText(data))
end

-- The section / sub-header row look, shared with the route checklist
-- (UI/ChecklistView.lua): a ScrollBox "Frame" initializer; set
-- frame.onToggle(key) for clicks.
UI.InitListHeader = initHeader

-- Crops `icon` past its baked-in edge and, when the client has the modern
-- rounded icon mask, masks it.
function UI.StyleIcon(owner, icon)
  icon:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
  if UI.AtlasExists(ICON_MASK) and owner.CreateMaskTexture and icon.AddMaskTexture then
    local mask = owner:CreateMaskTexture()
    mask:SetAtlas(ICON_MASK)
    mask:SetAllPoints(icon)
    icon:AddMaskTexture(mask)
  end
end

-- Paints a row's location icon for UI.LocationIcon's kind: the map pin
-- (UI.PinIcon) for "spot" (true counts as "spot"), the map item icon for
-- "zone".
function UI.ApplyPin(pin, kind)
  local atlas, texture = UI.PinIcon()
  if kind ~= "zone" and atlas then
    pin:SetAtlas(atlas)
    return
  end
  pin:SetTexture(texture)
  pin:SetTexCoord(ICON_CROP, 1 - ICON_CROP, ICON_CROP, 1 - ICON_CROP)
end

-- Shows a row's location icon for `kind` (UI.LocationIcon: "spot" / "zone";
-- true counts as "spot"), or hides it for nil / false.
function UI.ShowPin(pin, kind)
  if kind then UI.ApplyPin(pin, kind) end
  pin:SetShown(kind and true or false)
end

-- A row's location icon: a small texture on `owner`, hidden until the row
-- has a location (UI.ShowPin).
function UI.CreatePin(owner)
  local pin = owner:CreateTexture(nil, "OVERLAY")
  pin:SetSize(PIN_SIZE, PIN_SIZE)
  UI.ApplyPin(pin, "spot")
  pin:Hide()
  return pin
end

-- Room a row leaves on its right for the pin (PIN_RIGHT + PIN_SIZE + a gap).
UI.PIN_RIGHT = PIN_RIGHT
UI.PIN_ROOM = PIN_RIGHT + PIN_SIZE + 8

local function setupRow(row)
  row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- Modern list rows: no borders, a faint stripe on every other row and a
  -- soft hover highlight.
  local stripe = row:CreateTexture(nil, "BACKGROUND")
  stripe:SetAllPoints(row)
  stripe:SetColorTexture(1, 1, 1, 0.025)
  row.Stripe = stripe
  -- Owned (collected) mounts, listed with the Collected filter on: a light
  -- translucent green tint above the stripe.
  local owned = row:CreateTexture(nil, "BACKGROUND", nil, 1)
  owned:SetAllPoints(row)
  owned:SetColorTexture(0.25, 0.85, 0.35, 0.14)
  owned:Hide()
  row.Owned = owned
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  highlight:SetColorTexture(1, 1, 1, 0.07)
  -- The row shown in the detail pane: a soft gold fill with a gold bar on
  -- its left edge.
  local selected = row:CreateTexture(nil, "BACKGROUND", nil, 2)
  selected:SetAllPoints(row)
  selected:SetColorTexture(1, 0.82, 0, 0.12)
  local bar = row:CreateTexture(nil, "ARTWORK")
  bar:SetWidth(2)
  bar:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
  bar:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
  bar:SetColorTexture(1, 0.82, 0, 0.9)
  selected:Hide()
  bar:Hide()
  row.Selected = {
    SetShown = function(_, on) selected:SetShown(on); bar:SetShown(on) end,
    IsShown = function() return selected:IsShown() end,
  }

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("LEFT", row, "LEFT", ROW_ICON_LEFT, 0)
  UI.StyleIcon(row, icon)
  row.Icon = icon

  -- Location pin on the right end (rows with a waypoint target only).
  local pin = UI.CreatePin(row)
  pin:SetPoint("RIGHT", row, "RIGHT", -PIN_RIGHT, 0)
  row.Pin = pin

  local name = row:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
  -- Same-edge anchor pairs only (a RIGHT anchor would also pin the vertical
  -- centre). The 32 px icon is centred in the 40 px row, so its top is at -4
  -- and the name's at -6; the right edge stops 8 px left of the pin.
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
  name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -UI.PIN_ROOM, -((ROW_HEIGHT - 32) / 2 + 2))
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  row.Name = name

  local source = row:CreateFontString(nil, "OVERLAY", UI.SourceFont())
  source:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
  source:SetPoint("TOPRIGHT", name, "BOTTOMRIGHT", 0, -3)
  source:SetJustifyH("LEFT")
  source:SetWordWrap(false)
  row.Source = source

  row:SetScript("OnEnter", function(self)
    if self.onSelect and self.mountID then
      -- The detail pane shows the mount: the hover just says what a click does.
      UI.ShowHint(self, UI.RowHintTitle(self), UI.PaneRowHint(self.mountID, self.routeBoss, self.eventMap), "cursor")
    elseif self.tooltip then
      self.tooltip(self)
    elseif self.mountID then
      -- A route / checklist row's boss decides the lockout line.
      UI.ShowMountTooltip(self, self.mountID, self.routeBoss)
    end
  end)
  row:SetScript("OnLeave", function(self)
    UI.HideMountTooltip()
    UI.HideHint(self)
  end)
  row:SetScript("OnClick", function(self, button)
    -- In a list with the detail pane any click selects the row, then
    -- UI.PaneRowClick (right-click plots, Shift map, Ctrl achievement). Otherwise: left-click waypoint (or the
    -- achievement), Shift+left-click world map, Ctrl+left-click preview,
    -- Shift+right-click achievement (UI.RowClickAction).
    if self.onSelect and self.mountID and (button == "LeftButton" or button == "RightButton") then
      self.onSelect(self.mountID, self)
      UI.PaneRowClick(self.mountID, self.routeBoss, self.eventMap, button)
      return
    end
    UI.HandleRowClick(self.mountID, button, self.routeBoss, self.eventMap)
  end)
end

local function noTooltip() end

local function initRow(row, data)
  if not row.Icon then setupRow(row) end
  row.mountID = data.id
  row.tooltip = data.tooltip
  row.onSelect = data.onSelect
  row.Selected:SetShown(data.selected == true)
  row.routeBoss = data.routeBoss
  row.eventMap = data.eventMap
  -- Under a sub-header the icon lines up with the sub-header's indicator.
  row.Icon:SetPoint("LEFT", row, "LEFT", data.depth == 2 and SUB_INDENT or ROW_ICON_LEFT, 0)
  local name = data.name or ns.Game.MountInfo(data.id)
  row.Icon:SetTexture(UI.MountIcon(data.id))
  row.Name:SetText(name or data.m.name or tostring(data.id))
  row.Source:SetText(UI.RowSourceText(data))
  row.Stripe:SetShown(data.alt == true)
  UI.ShowPin(row.Pin, data.pin)
  -- Owned (collected) mounts: green tint and a light green name, the icon
  -- in full colour; everything reset for a recycled frame.
  row.Owned:SetShown(data.owned == true)
  row.Name:SetFontObject(data.owned and UI.OwnedFont() or UI.Font("GameFontNormal"))
  row.Icon:SetDesaturated(false)
end

-- The mount row look, shared by other mount lists (the zone panel): a
-- ScrollBox element initializer for "Button" frames. data: { id=, m=,
-- owned=, depth= (2: indented), desc= (UI.RowDescription), tag=, alt=
-- (striped), pin= (UI.HasLocation), name= (overrides the mount's name),
-- tooltip= (function(row) shown on hover instead of the mount tooltip),
-- onSelect= (function(mountID): a plain left-click selects instead of the
-- waypoint; the detail pane's lists), selected= (the selected row's look),
-- routeBoss= (the row's route boss, passed to the click: UI.HandleRowClick,
-- and to the hover: UI.ShowMountTooltip's lockout line) }.
-- Rows are UI.MOUNT_ROW_HEIGHT tall.
UI.InitMountRow = initRow
UI.MOUNT_ROW_HEIGHT = ROW_HEIGHT

-- Fallback panel checkbox; its label is one line kept inside the panel
-- (long "Show ..." labels are cut, not run under the list).
local FILTER_LABEL_WIDTH = FILTER_WIDTH - CHECK_SIZE - 10
local function makeCheck(panel, label, onClick)
  local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  cb:SetSize(CHECK_SIZE, CHECK_SIZE)
  local text = cb.Text or cb.text
  if not text then
    text = cb:CreateFontString(nil, "ARTWORK", UI.Font("GameFontHighlightSmall"))
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  end
  text:SetWidth(FILTER_LABEL_WIDTH)
  text:SetWordWrap(false)
  if text.SetJustifyH then text:SetJustifyH("LEFT") end
  text:SetText(label)
  cb.Label = text
  cb:SetScript("OnClick", onClick)
  return cb
end

-- Fallback filter panel (clients without the 11.x dropdown menus): a column
-- of checkboxes left of the list, under the search box: Collected, then the
-- current view's sections (UI.FilterMenuItems), rebuilt when the view changes.
local function buildFilterPanel(list)
  local panel = CreateFrame("Frame", nil, list)
  panel:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
  panel:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 0, 0)
  panel:SetWidth(FILTER_WIDTH)
  list.FilterPanel = panel
  return panel
end

-- Search box, Collected and the section title of the fallback filter panel;
-- the section checkboxes come from refreshFilterPanel.
local function layoutFilterPanel(list, search)
  local panel = list.FilterPanel
  search:SetSize(FILTER_WIDTH - 16, 20)
  search:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -4)

  local collected = makeCheck(panel, L["Collected"], function(self)
    local filters = filtersDB()
    if filters then filters.collected = self:GetChecked() and true or false end
    ns.Refresh()
  end)
  collected:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -8)
  list.CollectedCheck = collected

  local sectionsTitle = panel:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalSmall"))
  sectionsTitle:SetPoint("TOPLEFT", collected, "BOTTOMLEFT", 4, -8)
  sectionsTitle:SetText(L["Sources"])
  list.SectionsTitle = sectionsTitle

  -- SectionPool: every section checkbox made so far (reused across views);
  -- SectionChecks: the ones the current view shows, in menu order.
  list.SectionPool = {}
  list.SectionChecks = {}
end

-- One reusable section checkbox of the fallback panel: it writes its
-- current filterKey on the panel's current view.
local function sectionCheck(list, i)
  local cb = list.SectionPool[i]
  if cb then return cb end
  cb = makeCheck(list.FilterPanel, "", function(self)
    local filters = filtersDB()
    if filters then ns.Journal.SetSectionShown(filters, list.tab, self.filterKey, self:GetChecked() and true or false) end
    ns.Refresh()
  end)
  if i == 1 then
    cb:SetPoint("TOPLEFT", list.SectionsTitle, "BOTTOMLEFT", -4, -4)
  else
    cb:SetPoint("TOPLEFT", sectionCheck(list, i - 1), "BOTTOMLEFT", 0, 0)
  end
  list.SectionPool[i] = cb
  return cb
end

local function refreshFilterPanel(list, filters, view)
  list.CollectedCheck:SetChecked(filters.collected == true)
  local checks, title = {}, nil
  for _, item in ipairs(UI.FilterMenuItems(view, filters)) do
    if item.kind == "title" then
      title = item.label
    elseif item.kind == "checkbox" and item.key ~= "collected" then
      local cb = sectionCheck(list, #checks + 1)
      cb.filterKey = item.key
      cb.Label:SetText(item.label)
      cb:SetChecked(item.checked)
      cb:Show()
      checks[#checks + 1] = cb
    end
  end
  for i = #checks + 1, #list.SectionPool do list.SectionPool[i]:Hide() end
  list.SectionChecks = checks
  list.SectionsTitle:SetText(title or "")
  list.SectionsTitle:SetShown(#checks > 0)
end

-- A Filter button (the Mount Journal's WowStyle1FilterDropdownTemplate with
-- the 11.x SetupMenu API), or nil when this client lacks either (callers
-- fall back to checkboxes). Reusable by any view (the list, the checklist).
-- opts: {
--   items = function() -> UI.FilterMenuItems-style list (read when the
--     menu is built and again after each change; the checkboxes' states
--     come from that one read),
--   onChange = function(kind, value): ("toggle", key) when a checkbox is
--     clicked, ("action", action) for a button (the menu stays open),
--   isDefault = function() -> bool and reset = function() (optional, both
--     needed): the reset arrow next to the button while not at the defaults,
--   fallbackName = string (optional): what replaces the dropdown on clients
--     without it, for /mtrail debug (default "checkbox panel"),
-- }
function UI.CreateFilterDropdown(parent, opts)
  local fallbackName = opts.fallbackName or "checkbox panel"
  local template = UI.Template("WowStyle1FilterDropdownTemplate", nil)
  if not template then return nil end
  local good, dropdown = pcall(CreateFrame, "DropdownButton", nil, parent, template)
  if not (good and type(dropdown) == "table") then
    UI.RecordFallback("DropdownButton", fallbackName)
    return nil
  end
  if type(dropdown.SetupMenu) ~= "function" then
    dropdown:Hide()
    UI.RecordFallback("DropdownButton:SetupMenu", fallbackName)
    return nil
  end
  dropdown:SetSize(FILTER_BUTTON_WIDTH, FILTER_BUTTON_HEIGHT)
  if dropdown.Text and dropdown.Text.SetText then dropdown.Text:SetText(L["Filter"]) end

  -- key -> checked from the last items() read; nil = read again on demand
  -- (after a change).
  local checked
  local function readItems()
    local items = opts.items() or {}
    checked = {}
    for _, item in ipairs(items) do
      if item.kind == "checkbox" then checked[item.key] = item.checked == true end
    end
    return items
  end
  local function isChecked(key)
    if not checked then readItems() end
    return checked[key] == true
  end
  local function changed(kind, value)
    opts.onChange(kind, value)
    checked = nil
  end

  dropdown:SetupMenu(function(_, root)
    for _, item in ipairs(readItems()) do
      if item.kind == "checkbox" then
        local key = item.key
        root:CreateCheckbox(item.label, function() return isChecked(key) end,
          function() changed("toggle", key) end)
      elseif item.kind == "divider" then
        root:CreateDivider()
      elseif item.kind == "title" then
        root:CreateTitle(item.label)
      elseif item.kind == "button" then
        local action = item.action
        root:CreateButton(item.label, function()
          changed("action", action)
          -- Keep the menu open and redraw its checkboxes.
          return MenuResponse and MenuResponse.Refresh or nil
        end)
      end
    end
  end)

  if opts.isDefault and opts.reset and type(dropdown.SetDefaultCallback) == "function"
    and type(dropdown.SetIsDefaultCallback) == "function" then
    dropdown:SetIsDefaultCallback(opts.isDefault)
    dropdown:SetDefaultCallback(function()
      opts.reset()
      checked = nil
    end)
  end
  return dropdown
end

-- The list's Filter button: UI.FilterMenuItems of the list's view over
-- ns.db.global.filters; every change writes them and calls ns.Refresh().
local function createFilterDropdown(list)
  return UI.CreateFilterDropdown(list, {
    items = function()
      return UI.FilterMenuItems(list.tab, filtersDB() or ns.Journal.DefaultFilters)
    end,
    onChange = function(kind, value)
      local filters = filtersDB()
      if not filters then return end
      if kind == "toggle" then
        UI.ToggleFilter(filters, value, list.tab)
      else
        UI.ApplyFilterAction(filters, value, list.tab)
      end
      ns.Refresh()
    end,
    isDefault = function()
      local filters = filtersDB()
      return filters == nil or UI.FiltersAreDefault(filters, list.tab)
    end,
    reset = function()
      local filters = filtersDB()
      if filters then
        UI.ApplyFilterAction(filters, "reset", list.tab)
        ns.Refresh()
      end
    end,
  })
end

function UI.List(parent, getQuery, opts)
  local list = CreateFrame("Frame", nil, parent)
  list:SetAllPoints(parent)
  list.searchText = ""
  -- Known before the first Refresh, so the Filter menu has the right items
  -- even if it is opened first.
  local initial = (getQuery and getQuery()) or {}
  list.tab = initial.view or initial.tab

  -- Detail pane on the right (UI/DetailPane.lua) unless opts.detail == false:
  -- a left-click selects a row and shows it there.
  local pane
  if not (opts and opts.detail == false) and UI.CreateDetailPane then
    pane = UI.CreateDetailPane(list)
    pane:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
    pane:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", 0, 0)
    list.Detail = pane
  end
  local rightEdge, rightPoint = list, "TOPRIGHT"
  if pane then rightEdge, rightPoint = pane, "TOPLEFT" end

  -- Top row: search box + Filter button. Fallback: the left filter panel
  -- (search box on top of it).
  local dropdown = createFilterDropdown(list)
  list.FilterDropdown = dropdown
  local searchParent = list
  if not dropdown then searchParent = buildFilterPanel(list) end

  local search = CreateFrame("EditBox", nil, searchParent, "SearchBoxTemplate")
  search:SetAutoFocus(false)
  search:HookScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    if text ~= list.searchText then
      list.searchText = text
      list:Refresh(true)
    end
  end)
  list.SearchBox = search
  if dropdown then
    -- Flat header strip behind the top row, with a thin rule underneath.
    local strip = list:CreateTexture(nil, "BACKGROUND")
    strip:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
    strip:SetPoint("TOPRIGHT", rightEdge, rightPoint, 0, 0)
    strip:SetHeight(TOP_ROW - 2)
    strip:SetColorTexture(1, 1, 1, 0.04)
    local rule = list:CreateTexture(nil, "BORDER")
    rule:SetHeight(1)
    rule:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, 0)
    rule:SetColorTexture(1, 1, 1, 0.1)
    search:SetSize(SEARCH_WIDTH, 20)
    search:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -4)
    dropdown:SetPoint("LEFT", search, "RIGHT", 8, 0)
  else
    layoutFilterPanel(list, search)
  end

  -- Scroll list ----------------------------------------------------------------
  local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
  if list.FilterPanel then
    scrollBox:SetPoint("TOPLEFT", list.FilterPanel, "TOPRIGHT", 4, 0)
  else
    scrollBox:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -TOP_ROW) -- full width
  end
  if pane then
    scrollBox:SetPoint("BOTTOMRIGHT", pane, "BOTTOMLEFT", -20, 0)
  else
    scrollBox:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -20, 0)
  end
  list.ScrollBox = scrollBox

  local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
  list.ScrollBar = scrollBar

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtentCalculator(function(_, elementData)
    if elementData.header then
      return UI.HeaderHeight(elementData.depth == 2 and SUB_HEADER_HEIGHT or HEADER_HEIGHT)
    end
    return UI.RowHeight(ROW_HEIGHT)
  end)
  -- Clicking a header flips its saved collapse state and redraws in place.
  local function toggle(key)
    local store = collapsedDB()
    if not store then return end
    UI.ToggleCollapsed(store, key)
    list:Refresh()
  end
  local function toggleAll(data)
    local store = collapsedDB()
    if not store then return end
    UI.ToggleAllCollapsed(store, scrollBox.rowsShown, data)
    list:Refresh()
  end
  local function initListHeader(frame, data)
    frame.onToggle = toggle
    frame.onToggleAll = toggleAll
    initHeader(frame, data)
  end
  view:SetElementFactory(function(factory, elementData)
    if elementData.header then
      factory("Frame", initListHeader)
    else
      factory("Button", initRow)
    end
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  local empty = list:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisable"))
  empty:SetPoint("CENTER", scrollBox, "CENTER", 0, 0)
  empty:SetText(L["No mounts match these filters."])
  empty:Hide()
  list.Empty = empty

  -- Selects a mount row (detail pane) and redraws in place.
  function list:Select(mountID)
    self.selectedID = mountID
    self:Refresh()
  end
  list.selectHandler = function(mountID) list:Select(mountID) end

  -- resetScroll: true to jump back to the top (new expansion, new search).
  function list:Refresh(resetScroll)
    local base = (getQuery and getQuery()) or {}
    local query = {}
    for k, v in pairs(base) do query[k] = v end
    local filters = query.filters or filtersDB() or ns.Journal.DefaultFilters
    -- Select every mount, owned or not: header counts span all of them, and
    -- ListRows drops the owned rows itself while Collected is off.
    local showCollected = filters.collected == true
    local selectFilters = {}
    for k, v in pairs(filters) do selectFilters[k] = v end
    selectFilters.collected = true
    query.filters = selectFilters
    if query.search == nil then query.search = self.searchText end
    query.isOwned = query.isOwned or memo(ns.Game.IsOwned)
    query.exists = query.exists or memo(ns.Game.Exists)
    if query.faction == nil then query.faction = ns.Game.Faction() end
    query.sourceText = memoText(query.sourceText or ns.Game.MountSourceText)
    if query.showUnobtainable == nil then query.showUnobtainable = UI.ShowUnobtainable() end

    local tab = query.view or query.tab
    if tab ~= self.tab then
      self.tab = tab
      local dd = self.FilterDropdown
      if dd and type(dd.GenerateMenu) == "function" then dd:GenerateMenu() end
    end
    if self.FilterPanel then refreshFilterPanel(self, filters, tab) end
    if self.FilterDropdown and type(self.FilterDropdown.ValidateResetState) == "function" then
      self.FilterDropdown:ValidateResetState()
    end

    local select = (opts and opts.select) or ns.Journal.Select
    if not (opts and opts.select) and UI.SearchMatches then
      -- The home page's fuzzy search on the views' own pages too.
      local ids = {}
      for id in pairs((ns.Data and ns.Data.Mounts) or {}) do ids[#ids + 1] = id end
      query.match = UI.SearchMatches(ids, query.search, query.sourceText)
    end
    local selected = select((ns.Data and ns.Data.Mounts) or {}, query)
    local rows = UI.ListRows(selected, query.isOwned, {
      headerSuffix = opts and opts.headerSuffix,
      headerActive = opts and opts.headerActive,
      rowTag = opts and opts.rowTag,
      view = tab,
      exp = query.exp,
      collapsed = collapsedDB() or {},
      hideOwned = not showCollected,
      sourceText = query.sourceText,
      mapName = ns.Game.MapName and memoText(ns.Game.MapName) or nil,
    })
    -- Stripe every other mount row, restarting under each header; describe
    -- each shown mount once per refresh (UI.RowDescription over the memoised
    -- source text); rows with a location get the pin (UI.HasLocation).
    local sourceText = query.sourceText
    local describe = memoText(function(id) return UI.RowDescription(id, sourceText(id)) end)
    -- The selection stays while its mount is in this list (also under a
    -- collapsed header); else the first mount row.
    local selectedID
    if pane then
      for _, entry in ipairs(selected) do
        if entry.id == self.selectedID then selectedID = entry.id break end
      end
      if not selectedID then
        for _, row in ipairs(rows) do
          if not row.header then selectedID = row.id break end
        end
      end
      self.selectedID = selectedID
    end
    local n = 0
    for _, row in ipairs(rows) do
      if row.header then
        n = 0
      else
        n = n + 1
        row.alt = n % 2 == 0
        row.desc = describe(row.id)
        -- With the detail pane its clicks (UI.PaneRowClick) stand for the
        -- row's location icon.
        if not pane then row.pin = UI.LocationIcon(row.id) end
        if pane then
          row.selected = row.id == selectedID
          row.onSelect = self.selectHandler
          row.tooltip = noTooltip -- the pane shows what the tooltip would
        end
      end
    end
    if pane then pane:SetMount(selectedID) end
    scrollBox.rowsShown = rows -- a header's Shift-click (UI.ToggleAllCollapsed)
    local provider = CreateDataProvider(rows)
    if resetScroll or not ScrollBoxConstants then
      scrollBox:SetDataProvider(provider)
    else
      scrollBox:SetDataProvider(provider, ScrollBoxConstants.RetainScrollPosition)
    end
    empty:SetShown(#rows == 0)
  end

  return list
end
