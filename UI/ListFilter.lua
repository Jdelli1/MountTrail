local ADDON, ns = ...

-- The mount list's Filter menu, split out of UI/List.lua (loads right after
-- it): the menu items over ns.db.global.filters (UI.FilterMenuItems,
-- UI.FilterLabel, UI.FilterChecked, UI.ToggleFilter, UI.ApplyFilterAction,
-- UI.FiltersAreDefault), the Filter dropdown (UI.CreateFilterDropdown; the
-- list's own: UI.ListFilterDropdown) and the fallback checkbox panel for
-- clients without it (UI.BuildFilterPanel, UI.LayoutFilterPanel,
-- UI.RefreshFilterPanel). UI.List (UI/List.lua) calls these when it builds
-- and refreshes.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

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

-- Widgets ----------------------------------------------------------------------------

local FILTER_WIDTH = 150 -- fallback filter panel
local FILTER_BUTTON_WIDTH, FILTER_BUTTON_HEIGHT = 93, 22 -- the Mount Journal's Filter button
local CHECK_SIZE = 24

local function filtersDB()
  return ns.db and ns.db.global and ns.db.global.filters or nil
end


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
  UI.FlatDropdownButton(dropdown)

  -- key -> checked from the last items() read; nil = read again on demand
  -- (after a change).
  local checked
  local function readItems()
    local items = opts.items() or {}
    checked = {}
    for _, item in ipairs(items) do
      if item.kind == "checkbox" or item.kind == "radio" then checked[item.key] = item.checked == true end
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
      elseif item.kind == "radio" and type(root.CreateRadio) == "function" then
        local key = item.key
        root:CreateRadio(item.label, function() return isChecked(key) end,
          function() changed("radio", key) end)
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
-- extra (optional): { items = fn() -> more items after the filters (a
-- "radio" item: { kind = "radio", key =, label =, checked = }), onChange =
-- fn(kind, value) -> true when it handled the change }: a list's own
-- choices (a list page's sort).
local function createFilterDropdown(list, extra)
  return UI.CreateFilterDropdown(list, {
    items = function()
      local items = UI.FilterMenuItems(list.tab, filtersDB() or ns.Journal.DefaultFilters)
      local more = extra and extra.items and extra.items() or {}
      if #more > 0 then
        items[#items + 1] = { kind = "divider" }
        for _, it in ipairs(more) do items[#items + 1] = it end
      end
      return items
    end,
    onChange = function(kind, value)
      if extra and extra.onChange and extra.onChange(kind, value) then
        ns.Refresh()
        return
      end
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

-- For UI.List (UI/List.lua).
UI.BuildFilterPanel = buildFilterPanel
UI.LayoutFilterPanel = layoutFilterPanel
UI.RefreshFilterPanel = refreshFilterPanel
UI.ListFilterDropdown = createFilterDropdown
