local ADDON, ns = ...

-- Scrollable mount list shared by every list page (an expansion, Browse,
-- a list page, Current Zone, Holidays, Achievements, Timewalking, Misc): a
-- page header, one line as the design's ([Back] the title, then on the
-- right the search box, what is left as a badge, the Filter button --
-- UI.CreateFilterDropdown: Collected, plus the view's own sections --
-- Journal sources, Misc categories, holidays, achievement expansions; none
-- on Timewalking -- as "Show ..." checkboxes with Check all / Uncheck all,
-- in MountTrail's own menu -- and the page's own buttons), and a full-width
-- ScrollBox of section headers and mount rows.
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
-- after the row's source line), menu = { items =, onChange = } (the list's
-- own choices after the Filter menu's: UI.ListFilterDropdown), title =
-- string (the header's title; list.Title to change it later), back = fn (a
-- Back button before the title: list.Back), buttons = { { text =, onClick
-- = } } (flat buttons at the header's right end: list.Buttons) }. The base
-- query may carry pin = {[section]=true} (Journal.Select: those sections
-- first) and bare = true (no headers: the mounts in the order selected).
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
-- This file holds the row clicks (PreviewMount, RowClickAction, HasLocation,
-- PinIcon, PaneRowAction, ...) and the list widget (UI.List). Split out of
-- it, loading right after it: the row and header frames (the card look,
-- HeaderColor, pins) in UI/ListItems.lua; the row model (UI.ListRows, SubGroup, CollapseKey, ToggleCollapsed,
-- ToggleAllCollapsed, HeaderGlyph, HeaderText, SourceLine, MountIcon,
-- SectionLabel, InstanceName) in UI/ListRows.lua; the Filter menu, its
-- dropdown and the fallback checkbox panel in UI/ListFilter.lua; the source
-- text (StripMarkup, SourcePairs, SourceZone, RowDescription) in
-- UI/SourceText.lua; the search box's matching (UI.SearchMatches,
-- UI.SearchFields and the shared search cache) in UI/Search.lua. The pure
-- helpers are unit-tested; the widget code is built under a stub by
-- tests/ui_build_spec.lua.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

-- Row clicks ---------------------------------------------------------------------

local function mountData(mountID)
  local mounts = ns.Data and ns.Data.Mounts
  return mounts and mounts[mountID] or nil
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
-- only selects (nil); right-click "achievement" for an achievement mount,
-- else "waypoint" (the zone map for an unknown event); Shift "map"; Ctrl
-- "preview" -> action.
function UI.PaneRowAction(mountID, button, ctrl, shift, routeBoss, eventMap)
  if ctrl then return "preview" end
  if shift then return "map" end
  if button ~= "RightButton" then return nil end
  if hasAchievement(mountID) then return "achievement" end
  if eventMap or UI.HasLocation(mountID, routeBoss) then return "waypoint" end
  return nil
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
  if achievement then
    add(L["Right-click"], L["view the achievement"])
  elseif eventMap then
    add(L["Right-click"], L["open the zone map"])
  elseif n > 1 then
    add(L["Right-click"], string.format(L["plot all %d spawn points"], n))
  elseif located then
    add(L["Right-click"], L["plot the coordinates"])
  end
  if located then add(L["Shift-click"], L["show on the map"]) end
  add(L["Ctrl-click"], L["preview in the dressing room"])
  return table.concat(lines, "\n")
end

-- The hint's title: the row's name.
function UI.RowHintTitle(row)
  return row.Name and row.Name:GetText() or ""
end

-- Widgets ----------------------------------------------------------------------------

local SEARCH_WIDTH = 160
local TOP_ROW = 36 -- the page header: title, search, what is left, Filter

-- A row's "where it comes from" line: the mount names' font (GameFontHighlight,
-- so "Mount names and text" sizes both) dimmed to 70 % grey; GameFontDisable
-- when the client has no CreateFont.
function UI.SourceFont()
  return UI.TintedFont("MountTrailFontSource", "GameFontHighlight", 0.7, 0.7, 0.7, UI.Font("GameFontDisable"))
end

-- Name font of owned (collected) mount rows: the other names' font in a
-- light green (readable on the dark fill and the green row tint), so it
-- sizes with them; GameFontGreen when the client has no CreateFont.
function UI.OwnedFont()
  return UI.TintedFont("MountTrailFontOwned", "GameFontHighlight", 0.55, 0.95, 0.6, UI.Font("GameFontGreen"))
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

  -- The page header, one line: [Back] the title on the left; the search box,
  -- what is left, Filter (its Reset beside it) and the page's buttons on the
  -- right, over a thin rule.
  local rule = list:CreateTexture(nil, "BORDER")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -(TOP_ROW - 2))
  rule:SetPoint("TOPRIGHT", rightEdge, rightPoint, 0, -(TOP_ROW - 2))
  local line = UI.THEME and UI.THEME.cardEdge or { 0.2, 0.16, 0.09 }
  rule:SetColorTexture(line[1], line[2], line[3], 1)
  list.Rule = rule

  -- The page's buttons (Pop out), right to left from the header's end.
  list.Buttons = {}
  local rightOf, rightOfPoint, gap = rightEdge, rightPoint == "TOPLEFT" and "TOPLEFT" or "TOPRIGHT", -20
  for i = #((opts and opts.buttons) or {}), 1, -1 do
    local spec = opts.buttons[i]
    local b = UI.FlatButton(list, spec.text, "plain", 22)
    b:SetPoint("TOPRIGHT", rightOf, rightOfPoint, gap, -6)
    b:SetScript("OnClick", spec.onClick)
    list.Buttons[i] = b
    rightOf, rightOfPoint, gap = b, "TOPLEFT", -6
  end

  local dropdown = UI.ListFilterDropdown(list, opts and opts.menu)
  dropdown:SetPoint("TOPRIGHT", rightOf, rightOfPoint, gap, -6)
  list.FilterDropdown = dropdown

  -- What is left (the mounts of the page not owned yet): a badge left of
  -- Filter (of its Reset while that shows).
  local count = UI.Badge(list)
  list.Count = count

  local search = CreateFrame("EditBox", nil, list, "SearchBoxTemplate")
  UI.FlatSearchBox(search)
  search:SetAutoFocus(false)
  search:SetSize(SEARCH_WIDTH, 20)
  search:HookScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    if text ~= list.searchText then
      list.searchText = text
      list:Refresh(true)
    end
  end)
  list.SearchBox = search

  -- Back and the title.
  local back
  if opts and opts.back then
    back = UI.FlatButton(list, L["Back"], "plain", 22)
    back:SetPoint("TOPLEFT", list, "TOPLEFT", 4, -6)
    back:SetScript("OnClick", opts.back)
    list.Back = back
  end
  local titleText = list:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalLarge"))
  if back then
    titleText:SetPoint("LEFT", back, "RIGHT", 12, 0)
  else
    titleText:SetPoint("TOPLEFT", list, "TOPLEFT", 10, -9)
  end
  titleText:SetPoint("RIGHT", search, "LEFT", -12, 0)
  titleText:SetJustifyH("LEFT")
  titleText:SetWordWrap(false)
  titleText:SetText(opts and opts.title or "")
  list.Title = titleText

  -- The right side's places follow the Reset button's (it comes and goes).
  function list.LayoutHeader()
    local reset = dropdown.Reset
    local anchor = (reset and reset:IsShown()) and reset or dropdown
    count:ClearAllPoints()
    if count:IsShown() then
      count:SetPoint("RIGHT", anchor, "LEFT", -8, 0)
      anchor = count
    end
    search:ClearAllPoints()
    search:SetPoint("RIGHT", anchor, "LEFT", -10, 0)
  end
  list.LayoutHeader()

  -- Scroll list ----------------------------------------------------------------
  local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", list, "TOPLEFT", 0, -TOP_ROW) -- full width
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
      return UI.HeaderHeight(elementData.depth == 2 and UI.SUB_HEADER_HEIGHT or UI.CARD_HEADER_HEIGHT)
    end
    return UI.RowHeight(UI.MOUNT_ROW_HEIGHT)
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
    UI.InitListHeader(frame, data)
  end
  view:SetElementFactory(function(factory, elementData)
    if elementData.header then
      factory("Frame", initListHeader)
    else
      factory("Button", UI.InitMountRow)
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

    self.tab = query.view or query.tab
    local tab = self.tab
    if self.FilterDropdown.ValidateResetState then self.FilterDropdown:ValidateResetState() end

    local select = (opts and opts.select) or ns.Journal.Select
    if not (opts and opts.select) and UI.SearchMatches then
      -- The home page's fuzzy search on the views' own pages too.
      local ids = {}
      for id in pairs((ns.Data and ns.Data.Mounts) or {}) do ids[#ids + 1] = id end
      query.match = UI.SearchMatches(ids, query.search, query.sourceText)
    end
    local selected = select((ns.Data and ns.Data.Mounts) or {}, query)
    -- What is left on the page: its mounts not owned yet.
    local left = 0
    for _, e in ipairs(selected) do
      if e.id and not query.isOwned(e.id) then left = left + 1 end
    end
    UI.SetBadge(self.Count, string.format(L["%d left"], left), left > 0 and "gold" or "green")
    self.LayoutHeader()
    local rows = UI.ListRows(selected, query.isOwned, {
      bare = query.bare,
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
          row.tooltip = UI.NoTooltip -- the pane shows what the tooltip would
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
