local ADDON, ns = ...

-- Scrollable mount list shared by the Journal, Holidays and Misc tabs: a top
-- row with the search box and a Filter dropdown (Collected, and on the Journal
-- tab one checkbox per source section plus Check all / Uncheck all), and a
-- full-width ScrollBox of section headers and mount rows. Clients without the
-- 11.x dropdown (WowStyle1FilterDropdownTemplate / SetupMenu) get the older
-- left filter panel of checkboxes instead.
--
--   local list = ns.UI.List(parent, getQuery[, opts])
--   list:Refresh([resetScroll])
--
-- getQuery() returns the base query for Journal.Select ({ tab=, exp=,
-- section= }); the list fills in filters (ns.db.global.filters), the search
-- text, isOwned, exists, faction and sourceText (Game.MountSourceText, which
-- refines journal sections into delves / caches) unless the query already has
-- them.
-- opts (optional): { headerSuffix = fn(sectionKey) -> string|nil (a green
-- badge after the header text), rowTag = fn(mountID, m) -> string|nil (a
-- green tag after the row's source line) }.
-- The pure helpers above the widget code (SourceLine, MountIcon, SectionLabel,
-- ListRows, PreviewMount, the filter menu helpers) are unit-tested; the widget
-- code is built under a stub by tests/ui_build_spec.lua.

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
-- one section (the entry's refined section, else the mount's), then
-- { id=, m=, owned= } rows. With opts (see UI.List),
-- headers get badge = opts.headerSuffix(section) and rows tag =
-- opts.rowTag(id, m) (nil when the hook returns nil or is absent).
function UI.ListRows(selected, isOwned, opts)
  local headerSuffix = opts and opts.headerSuffix
  local rowTag = opts and opts.rowTag
  local rows, last = {}, nil
  for _, entry in ipairs(selected or {}) do
    local section = entry.section or entry.m.section
    if section ~= last then
      rows[#rows + 1] = {
        header = true, section = section, text = UI.SectionLabel(section),
        badge = headerSuffix and headerSuffix(section) or nil,
      }
      last = section
    end
    rows[#rows + 1] = {
      id = entry.id, m = entry.m, owned = (isOwned and isOwned(entry.id)) and true or false,
      tag = rowTag and rowTag(entry.id, entry.m) or nil,
    }
  end
  return rows
end

local GREEN = "|cff33ff99"

-- Header label: section name, plus the badge in green.
function UI.HeaderText(row)
  local text = row.text or ""
  if row.badge and row.badge ~= "" then
    text = text .. "  " .. GREEN .. row.badge .. "|r"
  end
  return text
end

-- Row source line: UI.SourceLine, plus the tag in green.
function UI.RowSourceText(row)
  local text = UI.SourceLine(row.id)
  if row.tag and row.tag ~= "" then
    local tag = GREEN .. row.tag .. "|r"
    text = (text ~= "") and (text .. " · " .. tag) or tag
  end
  return text
end

-- Filter menu --------------------------------------------------------------------

-- Source filters of the Journal tab, in menu order (Journal.Select's order).
local SECTION_FILTERS = { "dungeon", "raid", "world", "delve", "treasure", "quest", "activity",
  "reputation", "vendor", "other" }

-- Whether filter `key` is on: "collected" only when true (default off); a
-- source section unless false (a missing key means shown, as in
-- Journal.Select).
function UI.FilterChecked(filters, key)
  filters = filters or {}
  if key == "collected" then return filters.collected == true end
  return filters[key] ~= false
end

-- The Filter dropdown's items for a list on `tab` ("journal", "holiday",
-- "misc") -> { { kind = "checkbox", key =, label =, checked = },
-- { kind = "divider" }, { kind = "title", label = },
-- { kind = "button", action = "checkAll" | "uncheckAll", label = } }.
-- Every tab gets Collected; the Journal tab adds the source sections and the
-- Check all / Uncheck all buttons for them.
function UI.FilterMenuItems(tab, filters)
  local items = {
    { kind = "checkbox", key = "collected", label = L["Collected"], checked = UI.FilterChecked(filters, "collected") },
  }
  if tab ~= "journal" then return items end
  items[#items + 1] = { kind = "divider" }
  items[#items + 1] = { kind = "title", label = L["Sources"] }
  for _, key in ipairs(SECTION_FILTERS) do
    items[#items + 1] = { kind = "checkbox", key = key, label = UI.SectionLabel(key),
      checked = UI.FilterChecked(filters, key) }
  end
  items[#items + 1] = { kind = "divider" }
  items[#items + 1] = { kind = "button", action = "checkAll", label = L["Check all"] }
  items[#items + 1] = { kind = "button", action = "uncheckAll", label = L["Uncheck all"] }
  return items
end

-- Flips filter `key` in `filters` (ns.db.global.filters) -> its new state.
function UI.ToggleFilter(filters, key)
  local on = not UI.FilterChecked(filters, key)
  filters[key] = on
  return on
end

-- Keys the Filter dropdown shows on `tab`.
local function menuKeys(tab)
  local keys = { "collected" }
  if tab == "journal" then
    for _, key in ipairs(SECTION_FILTERS) do keys[#keys + 1] = key end
  end
  return keys
end

-- "checkAll" / "uncheckAll": every source section on / off. "reset": the
-- keys the dropdown shows on `tab` back to Journal.DefaultFilters (the
-- dropdown's reset arrow).
function UI.ApplyFilterAction(filters, action, tab)
  if action == "checkAll" or action == "uncheckAll" then
    for _, key in ipairs(SECTION_FILTERS) do filters[key] = action == "checkAll" end
  elseif action == "reset" then
    local defaults = ns.Journal.DefaultFilters
    for _, key in ipairs(menuKeys(tab)) do filters[key] = defaults[key] end
  end
end

-- True when the keys the dropdown shows on `tab` match
-- Journal.DefaultFilters (no reset arrow).
function UI.FiltersAreDefault(filters, tab)
  local defaults = ns.Journal.DefaultFilters
  for _, key in ipairs(menuKeys(tab)) do
    if UI.FilterChecked(filters, key) ~= UI.FilterChecked(defaults, key) then return false end
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

-- Widgets ----------------------------------------------------------------------------

local FILTER_WIDTH = 150 -- fallback filter panel
local SEARCH_WIDTH = 220
local FILTER_BUTTON_WIDTH, FILTER_BUTTON_HEIGHT = 93, 22 -- the Mount Journal's Filter button
local TOP_ROW = 30 -- search box + Filter button above the list
local HEADER_HEIGHT = 24
local ROW_HEIGHT = 40
local ICON_SIZE = 32
local CHECK_SIZE = 24
local MAP_WIDTH, MAP_RIGHT = 56, 6
-- Rounded icon mask of the current action bars; used only when the client
-- has it (UI.AtlasExists). Icons are also cropped past their baked-in edge.
local ICON_MASK = "UI-HUD-ActionBar-IconFrame-Mask"
local ICON_CROP = 0.08

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

local function initHeader(frame, data)
  if not frame.Label then
    -- Flat section header: a faint band with a thin gold rule underneath.
    local bg = frame:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(frame)
    bg:SetColorTexture(1, 1, 1, 0.05)
    frame.Bg = bg
    local rule = frame:CreateTexture(nil, "BORDER")
    rule:SetHeight(1)
    rule:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    rule:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    rule:SetColorTexture(1, 0.82, 0, 0.25)
    frame.Rule = rule
    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", frame, "LEFT", 8, 0)
    label:SetJustifyH("LEFT")
    frame.Label = label
  end
  frame.Label:SetText(UI.HeaderText(data))
end

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

local function setupRow(row)
  row:RegisterForClicks("LeftButtonUp")
  -- Modern list rows: no borders, a faint stripe on every other row and a
  -- soft hover highlight.
  local stripe = row:CreateTexture(nil, "BACKGROUND")
  stripe:SetAllPoints(row)
  stripe:SetColorTexture(1, 1, 1, 0.025)
  row.Stripe = stripe
  local highlight = row:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(row)
  highlight:SetColorTexture(1, 1, 1, 0.07)

  local icon = row:CreateTexture(nil, "ARTWORK")
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetPoint("LEFT", row, "LEFT", 4, 0)
  UI.StyleIcon(row, icon)
  row.Icon = icon

  local map = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
  map:SetSize(MAP_WIDTH, 22)
  map:SetPoint("RIGHT", row, "RIGHT", -MAP_RIGHT, 0)
  map:SetText(L["Map"])
  map:SetScript("OnClick", function()
    if row.mountID and ns.Map then ns.Map.Show(row.mountID) end
  end)
  row.Map = map

  local name = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  -- Same-edge anchor pairs only (a RIGHT anchor would also pin the vertical
  -- centre). The 32 px icon is centred in the 40 px row, so its top is at -4
  -- and the name's at -6; the right edge stops 8 px left of the Map button.
  name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 8, -2)
  name:SetPoint("TOPRIGHT", row, "TOPRIGHT", -(MAP_RIGHT + MAP_WIDTH + 8), -((ROW_HEIGHT - 32) / 2 + 2))
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  row.Name = name

  -- Owned mounts: a thin line through the name (a strikethrough look).
  local strike = row:CreateTexture(nil, "OVERLAY")
  strike:SetHeight(1)
  strike:SetPoint("LEFT", name, "LEFT", 0, 0)
  strike:SetColorTexture(0.6, 0.6, 0.6, 0.9)
  row.Strike = strike

  local source = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  source:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -3)
  source:SetPoint("TOPRIGHT", name, "BOTTOMRIGHT", 0, -3)
  source:SetJustifyH("LEFT")
  source:SetWordWrap(false)
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
  row.Source:SetText(UI.RowSourceText(data))
  row.Stripe:SetShown(data.alt == true)
  if data.owned then
    row.Name:SetFontObject("GameFontDisable")
    row.Icon:SetDesaturated(true)
    local width = row.Name:GetStringWidth() or 0
    local max = row.Name:GetWidth() or 0
    if max > 0 and width > max then width = max end
    row.Strike:SetWidth(math.max(width, 1))
    row.Strike:Show()
  else
    row.Name:SetFontObject("GameFontNormal")
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

-- Fallback filter panel (clients without the 11.x dropdown menus): a column
-- of checkboxes left of the list, under the search box.
local function buildFilterPanel(list)
  local panel = CreateFrame("Frame", nil, list)
  panel:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
  panel:SetPoint("BOTTOMLEFT", list, "BOTTOMLEFT", 0, 0)
  panel:SetWidth(FILTER_WIDTH)
  list.FilterPanel = panel
  return panel
end

-- Search box and checkboxes of the fallback filter panel.
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
end

local function refreshFilterPanel(list, filters, tab)
  list.CollectedCheck:SetChecked(filters.collected == true)
  local showSections = tab == "journal"
  list.SectionsTitle:SetShown(showSections)
  for _, cb in ipairs(list.SectionChecks) do
    cb:SetChecked(filters[cb.filterKey] ~= false)
    cb:SetShown(showSections)
  end
end

-- The Mount Journal's Filter button (11.x menu API) with UI.FilterMenuItems as
-- its menu, or nil when this client lacks the template or SetupMenu. Every
-- change writes ns.db.global.filters and calls ns.Refresh().
local function createFilterDropdown(list)
  local template = UI.Template("WowStyle1FilterDropdownTemplate", nil)
  if not template then return nil end
  local good, dropdown = pcall(CreateFrame, "DropdownButton", nil, list, template)
  if not (good and type(dropdown) == "table") then return nil end
  if type(dropdown.SetupMenu) ~= "function" then
    dropdown:Hide()
    if ns.Game and ns.Game.ReportError then
      ns.Game.ReportError("DropdownButton:SetupMenu missing, using the filter panel")
    end
    return nil
  end
  dropdown:SetSize(FILTER_BUTTON_WIDTH, FILTER_BUTTON_HEIGHT)
  if dropdown.Text and dropdown.Text.SetText then dropdown.Text:SetText(L["Filter"]) end

  local function isChecked(key)
    local filters = filtersDB()
    return filters ~= nil and UI.FilterChecked(filters, key)
  end
  local function toggle(key)
    local filters = filtersDB()
    if not filters then return end
    UI.ToggleFilter(filters, key)
    ns.Refresh()
  end
  local function act(action)
    local filters = filtersDB()
    if filters then
      UI.ApplyFilterAction(filters, action, list.tab)
      ns.Refresh()
    end
    -- Keep the menu open and redraw its checkboxes.
    return MenuResponse and MenuResponse.Refresh or nil
  end

  dropdown:SetupMenu(function(_, root)
    for _, item in ipairs(UI.FilterMenuItems(list.tab, filtersDB() or ns.Journal.DefaultFilters)) do
      if item.kind == "checkbox" then
        root:CreateCheckbox(item.label, function() return isChecked(item.key) end,
          function() toggle(item.key) end)
      elseif item.kind == "divider" then
        root:CreateDivider()
      elseif item.kind == "title" then
        root:CreateTitle(item.label)
      elseif item.kind == "button" then
        root:CreateButton(item.label, function() return act(item.action) end)
      end
    end
  end)

  -- The reset arrow next to the button while the filters differ from the
  -- defaults (WowStyle1FilterDropdownMixin).
  if type(dropdown.SetDefaultCallback) == "function" and type(dropdown.SetIsDefaultCallback) == "function" then
    dropdown:SetIsDefaultCallback(function()
      local filters = filtersDB()
      return filters == nil or UI.FiltersAreDefault(filters, list.tab)
    end)
    dropdown:SetDefaultCallback(function()
      local filters = filtersDB()
      if filters then
        UI.ApplyFilterAction(filters, "reset", list.tab)
        ns.Refresh()
      end
    end)
  end
  return dropdown
end

function UI.List(parent, getQuery, opts)
  local list = CreateFrame("Frame", nil, parent)
  list:SetAllPoints(parent)
  list.searchText = ""

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
    strip:SetPoint("TOPRIGHT", list, "TOPRIGHT", 0, 0)
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
    query.sourceText = memoText(query.sourceText or ns.Game.MountSourceText)

    self.tab = query.tab
    if self.FilterPanel then refreshFilterPanel(self, filters, query.tab) end
    if self.FilterDropdown and type(self.FilterDropdown.ValidateResetState) == "function" then
      self.FilterDropdown:ValidateResetState()
    end

    local selected = ns.Journal.Select((ns.Data and ns.Data.Mounts) or {}, query)
    local rows = UI.ListRows(selected, query.isOwned, opts)
    -- Stripe every other mount row, restarting under each header.
    local n = 0
    for _, row in ipairs(rows) do
      if row.header then
        n = 0
      else
        n = n + 1
        row.alt = n % 2 == 0
      end
    end
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
