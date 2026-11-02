local ADDON, ns = ...

-- The mount list's Filter menu, split out of UI/List.lua (loads right after
-- it): the menu items over ns.db.global.filters (UI.FilterMenuItems,
-- UI.FilterLabel, UI.FilterChecked, UI.ToggleFilter, UI.ApplyFilterAction,
-- UI.FiltersAreDefault) and the Filter button that opens them in
-- MountTrail's own menu (UI.CreateFilterDropdown; the list's own:
-- UI.ListFilterDropdown). UI.List (UI/List.lua) calls these when it builds
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

local FILTER_BUTTON_WIDTH, FILTER_BUTTON_HEIGHT = 70, 22

local function filtersDB()
  return ns.db and ns.db.global and ns.db.global.filters or nil
end

-- A Filter button: a flat gold button that opens MountTrail's own menu
-- (UI.ShowMenu, the gold-edged look of every menu). Reusable by any view
-- (the list, the checklist).
-- opts: {
--   items = function() -> UI.FilterMenuItems-style list (read when the
--     menu is built and again after each change; the checkboxes' states
--     come from that one read),
--   onChange = function(kind, value): ("toggle", key) when a checkbox is
--     clicked, ("radio", key) for a radio item, ("action", action) for a
--     button (the menu stays open and repaints),
--   isDefault = function() -> bool and reset = function() (optional, both
--     needed): a small Reset button left of it while not at the defaults,
-- }
-- The button's generator(button, root) builds the menu over a root with
-- CreateCheckbox / CreateRadio / CreateDivider / CreateTitle / CreateButton
-- (the shape of Blizzard's menu API), which the click turns into UI.ShowMenu
-- items. button:ValidateResetState() shows the Reset button while not at
-- the defaults; button.defaultCallback() resets.
function UI.CreateFilterDropdown(parent, opts)
  local button = UI.FlatButton(parent, L["Filter"], "gold", FILTER_BUTTON_HEIGHT)
  button:SetWidth(FILTER_BUTTON_WIDTH)

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
    if button.ValidateResetState then button:ValidateResetState() end
  end

  function button.generator(_, root)
    for _, item in ipairs(readItems()) do
      if item.kind == "checkbox" then
        local key = item.key
        root:CreateCheckbox(item.label, function() return isChecked(key) end,
          function() changed("toggle", key) end)
      elseif item.kind == "radio" then
        local key = item.key
        root:CreateRadio(item.label, function() return isChecked(key) end,
          function() changed("radio", key) end)
      elseif item.kind == "divider" then
        root:CreateDivider()
      elseif item.kind == "title" then
        root:CreateTitle(item.label)
      elseif item.kind == "button" then
        local action = item.action
        root:CreateButton(item.label, function() changed("action", action) end)
      end
    end
  end

  -- The menu's items, from the generator (every choice keeps it open).
  local function menuItems()
    local out = {}
    local function choice(label, isSel, onSel)
      out[#out + 1] = { text = label, checked = isSel() == true, keepOpen = true, onClick = function() onSel() end }
    end
    button.generator(button, {
      CreateCheckbox = function(_, label, isSel, onSel) choice(label, isSel, onSel) end,
      CreateRadio = function(_, label, isSel, onSel) choice(label, isSel, onSel) end,
      CreateDivider = function() out[#out + 1] = { separator = true } end,
      CreateTitle = function(_, label) out[#out + 1] = { title = label } end,
      CreateButton = function(_, label, fn) out[#out + 1] = { text = label, keepOpen = true, onClick = function() fn() end } end,
    })
    return out
  end
  button:SetScript("OnClick", function(self) UI.ShowMenu(self, menuItems) end)

  if opts.isDefault and opts.reset then
    local reset = UI.FlatButton(parent, L["Reset"], "plain", FILTER_BUTTON_HEIGHT)
    reset:SetPoint("RIGHT", button, "LEFT", -4, 0)
    reset:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Reset filters"]) end)
    reset:SetScript("OnLeave", function(self) UI.HideHint(self) end)
    reset:Hide()
    button.Reset = reset
    button.isDefaultCallback = opts.isDefault
    function button.defaultCallback()
      opts.reset()
      checked = nil
      button:ValidateResetState()
    end
    reset:SetScript("OnClick", function() button.defaultCallback() end)
    function button:ValidateResetState()
      self.resetShown = not opts.isDefault()
      self.Reset:SetShown(self.resetShown)
    end
    button:ValidateResetState()
  end
  return button
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
UI.ListFilterDropdown = createFilterDropdown
