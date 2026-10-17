local ADDON, ns = ...

-- Scrollable mount list shared by the Journal, Holidays and Misc tabs:
-- a left filter panel (search box, Collected, and on the Journal tab one box
-- per source section) and a ScrollBox of section headers and mount rows.
--
--   local list = ns.UI.List(parent, getQuery)
--   list:Refresh([resetScroll])
--
-- getQuery() returns the base query for Journal.Select ({ tab=, exp=,
-- section= }); the list fills in filters (ns.db.global.filters), the search
-- text, isOwned, exists and faction unless the query already has them.
-- The pure helpers above the widget code (SourceLine, MountIcon, SectionLabel,
-- ListRows, PreviewMount) are unit-tested; the widget code is not.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

-- Pure helpers -------------------------------------------------------------------

-- mountID -> { boss=, title= } for the first route boss row of each mount
-- (depth-first, Data.Route order). Built once, on first use.
local routeIndex

local function stripRun(title)
  if type(title) ~= "string" then return nil end
  if string.sub(title, 1, 4) == "Run " then title = string.sub(title, 5) end
  return title
end

local function buildRouteIndex()
  local index = {}
  local function walk(nodes)
    if type(nodes) ~= "table" then return end
    for _, node in ipairs(nodes) do
      if type(node) == "table" then
        for _, boss in ipairs(node.bosses or {}) do
          if type(boss) == "table" and boss.mount and not index[boss.mount] then
            index[boss.mount] = { boss = boss.boss, title = stripRun(node.title) }
          end
        end
        walk(node.steps)
      end
    end
  end
  walk(ns.Data and ns.Data.Route)
  return index
end

local function routeEntry(mountID)
  routeIndex = routeIndex or buildRouteIndex()
  return routeIndex[mountID]
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
  dungeon = "Dungeons", raid = "Raids", world = "World", reputation = "Reputation",
  vendor = "Vendor", other = "Other",
  achievement = "Achievements", profession = "Professions", shop = "Shop",
  tradingpost = "Trading Post",
  timewalking = "Timewalking", anniversary = "Anniversary",
}

-- Header text for a section key: holiday titles from Data.Holidays, else the
-- section names above, else the key itself.
function UI.SectionLabel(section)
  local holidays = ns.Data and ns.Data.Holidays
  local holiday = holidays and holidays[section]
  if type(holiday) == "table" and holiday.title then return L[holiday.title] end
  return L[SECTION_NAMES[section] or tostring(section)]
end

-- Journal.Select output -> ScrollBox elements: a header before each run of
-- one section, then { id=, m=, owned= } rows.
function UI.ListRows(selected, isOwned)
  local rows, last = {}, nil
  for _, entry in ipairs(selected or {}) do
    local section = entry.m.section
    if section ~= last then
      rows[#rows + 1] = { header = true, section = section, text = UI.SectionLabel(section) }
      last = section
    end
    rows[#rows + 1] = { id = entry.id, m = entry.m, owned = (isOwned and isOwned(entry.id)) and true or false }
  end
  return rows
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

-- Widgets ----------------------------------------------------------------------------

local FILTER_WIDTH = 150
local HEADER_HEIGHT = 24
local ROW_HEIGHT = 40
local CHECK_SIZE = 24
local SECTION_FILTERS = { "dungeon", "raid", "world", "reputation", "vendor", "other" }

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

local function initHeader(frame, data)
  if not frame.Label then
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(1, 1, 1, 0.06)
    frame.Bg = bg
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", frame, "LEFT", 8, 0)
    label:SetJustifyH("LEFT")
    frame.Label = label
  end
  frame.Label:SetText(data.text)
end

local function setupRow(row)
  row:RegisterForClicks("LeftButtonUp")
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  highlight:SetColorTexture(1, 1, 1, 0.08)

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(32, 32)
  icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  row.Icon = icon

  local map = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  map:SetSize(56, 22)
  map:SetPoint("RIGHT", row, "RIGHT", -6, 0)
  map:SetText(L["Map"])
  map:SetScript("OnClick", function()
    if row.mountID and ns.Map then ns.Map.Show(row.mountID) end
  end)
  row.Map = map

  local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
  name:SetPoint("RIGHT", map, "LEFT", -8, 0)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  row.Name = name

  -- Owned mounts: a thin line through the name (a strikethrough look).
  local strike = row:CreateTexture(nil, "OVERLAY")
  strike:SetHeight(1)
  strike:SetPoint("LEFT", name, "LEFT", 0, 0)
  strike:SetColorTexture(0.6, 0.6, 0.6, 0.9)
  row.Strike = strike

  local source = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  source:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
  source:SetPoint("RIGHT", map, "LEFT", -8, 0)
  source:SetJustifyH("LEFT")
  source:SetWordWrap(false)
  source:SetTextColor(0.7, 0.7, 0.7)
  row.Source = source

  row:SetScript("OnEnter", function(self)
    if self.mountID then UI.ShowMountTooltip(self, self.mountID) end
  end)
  row:SetScript("OnLeave", function() UI.HideMountTooltip() end)
  row:SetScript("OnClick", function(self, button)
    if button == "LeftButton" and IsControlKeyDown() and self.mountID then
      UI.PreviewMount(self.mountID)
    end
    -- Plain click: nothing in v1.
  end)
end

local function initRow(row, data)
  if not row.Icon then setupRow(row) end
  row.mountID = data.id
  local name = ns.Game.MountInfo(data.id)
  row.Icon:SetTexture(UI.MountIcon(data.id))
  row.Name:SetText(name or data.m.name or tostring(data.id))
  row.Source:SetText(UI.SourceLine(data.id))
  if data.owned then
    row.Name:SetTextColor(0.5, 0.5, 0.5)
    row.Icon:SetDesaturated(true)
    local width = row.Name:GetStringWidth() or 0
    local max = row.Name:GetWidth() or 0
    if max > 0 and width > max then width = max end
    row.Strike:SetWidth(math.max(width, 1))
    row.Strike:Show()
  else
    row.Name:SetTextColor(1, 0.82, 0)
    row.Icon:SetDesaturated(false)
    row.Strike:Hide()
  end
end

local function makeCheck(panel, label, onClick)
  local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
  cb:SetSize(CHECK_SIZE, CHECK_SIZE)
  local text = cb.Text or cb.text
  if not text then
    text = cb:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  end
  text:SetText(label)
  cb.Label = text
  cb:SetScript("OnClick", onClick)
  return cb
end

function UI.List(parent, getQuery)
  local list = CreateFrame("Frame", nil, parent)
  list:SetAllPoints(parent)
  list.searchText = ""

  -- Filter panel ---------------------------------------------------------------
  local panel = CreateFrame("Frame", nil, list)
  panel:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
  panel:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 0, 0)
  panel:SetWidth(FILTER_WIDTH)
  list.FilterPanel = panel

  local search = CreateFrame("EditBox", nil, panel, "SearchBoxTemplate")
  search:SetSize(FILTER_WIDTH - 16, 20)
  search:SetPoint("TOPLEFT", panel, "TOPLEFT", 10, -4)
  search:SetAutoFocus(false)
  search:HookScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    if text ~= list.searchText then
      list.searchText = text
      list:Refresh(true)
    end
  end)
  list.SearchBox = search

  local collected = makeCheck(panel, L["Collected"], function(self)
    local filters = filtersDB()
    if filters then filters.collected = self:GetChecked() and true or false end
    ns.Refresh()
  end)
  collected:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -6, -8)
  list.CollectedCheck = collected

  local sectionsTitle = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  sectionsTitle:SetPoint("TOPLEFT", collected, "BOTTOMLEFT", 4, -8)
  sectionsTitle:SetText(L["Sources"])
  list.SectionsTitle = sectionsTitle

  list.SectionChecks = {}
  local anchor = sectionsTitle
  for i, key in ipairs(SECTION_FILTERS) do
    local cb = makeCheck(panel, UI.SectionLabel(key), function(self)
      local filters = filtersDB()
      if filters then filters[key] = self:GetChecked() and true or false end
      ns.Refresh()
    end)
    if i == 1 then
      cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", -4, -4)
    else
      cb:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, 0)
    end
    cb.filterKey = key
    list.SectionChecks[i] = cb
    anchor = cb
  end

  -- Scroll list ----------------------------------------------------------------
  local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", panel, "TOPRIGHT", 4, 0)
  scrollBox:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -20, 0)
  list.ScrollBox = scrollBox

  local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 6, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 6, 0)
  list.ScrollBar = scrollBar

  local view = CreateScrollBoxListLinearView()
  view:SetElementExtentCalculator(function(_, elementData)
    return elementData.header and HEADER_HEIGHT or ROW_HEIGHT
  end)
  view:SetElementFactory(function(factory, elementData)
    if elementData.header then
      factory("Frame", initHeader)
    else
      factory("Button", initRow)
    end
  end)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  local empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  empty:SetPoint("CENTER", scrollBox, "CENTER", 0, 0)
  empty:SetText(L["No mounts match these filters."])
  empty:Hide()
  list.Empty = empty

  -- resetScroll: true to jump back to the top (new expansion, new search).
  function list:Refresh(resetScroll)
    local base = (getQuery and getQuery()) or {}
    local query = {}
    for k, v in pairs(base) do query[k] = v end
    local filters = query.filters or filtersDB() or ns.Journal.DefaultFilters
    query.filters = filters
    if query.search == nil then query.search = self.searchText end
    query.isOwned = query.isOwned or memo(ns.Game.IsOwned)
    query.exists = query.exists or memo(ns.Game.Exists)
    if query.faction == nil then query.faction = ns.Game.Faction() end

    collected:SetChecked(filters.collected == true)
    local showSections = query.tab == "journal"
    sectionsTitle:SetShown(showSections)
    for _, cb in ipairs(self.SectionChecks) do
      cb:SetChecked(filters[cb.filterKey] ~= false)
      cb:SetShown(showSections)
    end

    local selected = ns.Journal.Select((ns.Data and ns.Data.Mounts) or {}, query)
    local rows = UI.ListRows(selected, query.isOwned)
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
