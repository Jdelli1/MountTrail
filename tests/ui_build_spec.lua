-- Builds the restyled views (journal home and list, Holidays, Achievements,
-- Timewalking, Misc, Checklist)
-- under the widget stub, plus the extra widget methods and ScrollBox / menu
-- stand-ins below, so the widget code runs instead of being compile-checked
-- only. Checks the Filter dropdown wiring (menu content, writes to
-- ns.db.global.filters, reset arrow) and its checkbox-panel fallback.
-- UI/Arrow.lua is not loaded.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/JournalHome.lua",
  "UI/Tabs.lua", "UI/LockoutHelpers.lua", "UI/ChecklistView.lua", "UI/AltsWindow.lua", "UI/Popouts.lua", "UI/ZonePanel.lua" }

-- Widget methods the views call that the base stub does not need.
local probe = CreateFrame("Frame")
local FrameMT = getmetatable(probe)
local RegionMT = getmetatable(FrameMT).__index
local function noop() end
for _, name in ipairs({ "SetTexCoord", "SetJustifyH", "SetWordWrap", "SetDesaturated", "SetTextColor",
  "SetStatusBarTexture", "SetStatusBarColor", "SetMinMaxValues", "SetValue", "SetDrawLayer",
  "SetBackdrop", "SetBackdropColor", "SetRotation", "AddMaskTexture" }) do
  RegionMT[name] = RegionMT[name] or noop
end
function RegionMT:SetFontObject(font) self.font = font end
function RegionMT:SetWordWrap(on) self.wordWrap = on end
function RegionMT:SetDesaturated(on) self.desaturated = on end
function RegionMT:GetStringWidth() return 60 end
function RegionMT:GetWidth() return self.width or 0 end
function FrameMT:RegisterForClicks(...) self.clickButtons = { ... } end
-- Under the mouse unless a spec says otherwise (a click implies the mouse).
function FrameMT:IsMouseOver() return self.mouseOver ~= false end
for _, name in ipairs({ "SetAutoFocus", "LockHighlight", "UnlockHighlight" }) do
  FrameMT[name] = FrameMT[name] or noop
end
function FrameMT:SetChecked(on) self.checked = on end
function FrameMT:GetChecked() return self.checked end
function FrameMT:SetEnabled(on) self.enabled = on end
function FrameMT:CreateMaskTexture() return self:CreateTexture(nil, "ARTWORK") end
function FrameMT:SetDataProvider(provider, retain) self.provider = provider; self.retain = retain end
function FrameMT:SetClampRectInsets(l, r, t, b) self.clampInsets = { l, r, t, b } end

function CreateScrollBoxListLinearView()
  local view = {}
  function view:SetElementExtentCalculator(fn) self.extent = fn end
  function view:SetElementFactory(fn) self.factory = fn end
  return view
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, bar, view) box.view = view end }
function CreateDataProvider(rows) return { rows = rows } end
IsControlKeyDown = function() return false end
GameFontHighlightSmall = { name = "GameFontHighlightSmall" }
GameFontNormal = { name = "GameFontNormal" }
function CreateFont(name)
  local font = { name = name }
  function font:SetFontObject(base) self.base = base end
  function font:SetTextColor(r, g, b) self.color = { r, g, b } end
  _G[name] = font
  return font
end
MenuResponse = { Refresh = 2 }

-- The 11.x DropdownButton stand-in: records the generator and callbacks.
STUB_TEMPLATE_METHODS.WowStyle1FilterDropdownTemplate = {
  SetupMenu = function(self, generator) self.generator = generator end,
  SetDefaultCallback = function(self, fn) self.defaultCallback = fn end,
  SetIsDefaultCallback = function(self, fn) self.isDefaultCallback = fn end,
  ValidateResetState = function(self)
    self.resetShown = self.isDefaultCallback ~= nil and not self.isDefaultCallback()
  end,
}

-- Runs a dropdown's menu generator against a recording root description.
local function openMenu(dropdown)
  local calls = {}
  local root = {}
  function root:CreateCheckbox(text, isSelected, setSelected)
    calls[#calls + 1] = { kind = "checkbox", text = text, isSelected = isSelected, setSelected = setSelected }
  end
  function root:CreateDivider() calls[#calls + 1] = { kind = "divider" } end
  function root:CreateTitle(text) calls[#calls + 1] = { kind = "title", text = text } end
  function root:CreateButton(text, fn) calls[#calls + 1] = { kind = "button", text = text, fn = fn } end
  dropdown.generator(dropdown, root)
  return calls
end

local function find(calls, text)
  for _, c in ipairs(calls) do if c.text == text then return c end end
end

-- Lays out every element of a ScrollBox the way the client would.
local function render(box)
  local frames = {}
  for _, data in ipairs(box.provider.rows) do
    ok(type(box.view.extent(1, data)) == "number", "extent is a number")
    box.view.factory(function(kind, init)
      local f = CreateFrame(kind, nil, box)
      init(f, data)
      init(f, data) -- frames are recycled: a second init must work too
      frames[#frames + 1] = f
    end, data)
  end
  return frames
end

local function loadUI(global)
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  for k, v in pairs(global or {}) do ns.db.global[k] = v end
  local stubGame = {
    MountInfo = function() return nil end,
    IsOwned = function(id) return id % 3 == 0 end,
    Exists = function() return true end,
    Faction = function() return "Alliance" end,
    SavedRows = function() return {} end,
    IsQuestDone = function() return false end,
    IsLfgDone = function() return false end,
    ExpansionLogo = function(i) if i == 1 then return 123 end end,
    MountSourceText = function() return nil end,
    ActiveHolidays = function() return { brewfest = true } end,
    Now = function() return 1700000000 end,
    UntilDaily = function() return 3600 end,
    UntilWeekly = function() return 86400 end,
    PlayerName = function() return "Tester" end,
  }
  for k, v in pairs(stubGame) do ns.Game[k] = v end
  return ns
end

local function content(ns, key) return ns.UI.frame.Contents[key] end

-- The journal list: open the window (journal tab) and click the first card.
local function openJournalList(ns)
  ns.ToggleWindow()
  local journal = content(ns, "journal")
  local home = journal.children[2] -- [1] is the Coming soon placeholder
  local card = home.children[1]
  card:RunScript("OnEnter")
  card:RunScript("OnLeave")
  card:RunScript("OnClick", "LeftButton")
  local listPage = journal.children[3]
  ok(listPage:IsShown() and not home:IsShown(), "card opens the list")
  local holder
  for _, child in ipairs(listPage.children) do
    local first = child.children and child.children[1]
    if first and first.SearchBox then holder = first end
  end
  ok(holder, "list found")
  return holder, home
end

describe("ui build", function()
  it("journal home builds a card per expansion with flat edges", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local home = content(ns, "journal").children[2]
    eq(#home.children, #ns.Data.Expansions + 1, "the cards, then the summary strip")
    local card = home.children[1]
    ok(card.Edge and #card.Edge.edges == 4, "flat 1 px edge")
    eq(card.Logo.texture, 123, "logo from the client")
    ok(card.Logo:IsShown() and not card.Name:IsShown(), "logo instead of the name")
    eq(card.Logo:GetPoint(1), "CENTER", "logo centred")
    eq(card.Bar.height, 3, "slim bar")
    card:RunScript("OnEnter")
    eq(card.Edge.edges[1].color, { 1, 0.82, 0, 0.6 }, "gold edge on hover")
    card:RunScript("OnLeave")
    eq(card.Edge.edges[1].color, { 1, 1, 1, 0.1 })
  end)

  it("the journal list has a full-width list under the search box and Filter button", function()
    local ns = loadUI()
    local list = openJournalList(ns)
    ok(list.FilterDropdown, "Filter dropdown")
    eq(list.FilterPanel, nil, "no checkbox panel")
    eq(list.FilterDropdown.template, "WowStyle1FilterDropdownTemplate")
    eq({ list.FilterDropdown:GetPoint(1) }, { "LEFT", list.SearchBox, "RIGHT", 8, 0 })
    eq({ list.ScrollBox:GetPoint(1) }, { "TOPLEFT", list, "TOPLEFT", 0, -30 }, "full width")
    eq(list.tab, "journal")
    local frames = render(list.ScrollBox)
    ok(#frames > 0, "rows rendered")
    local sawStripe, sawPlain = false, false
    for _, f in ipairs(frames) do
      if f.Stripe then
        if f.Stripe:IsShown() then sawStripe = true else sawPlain = true end
        ok(f.Name.font == ns.UI.Font("GameFontNormal") or f.Name.font == ns.UI.OwnedFont(), "GameFont family")
      end
    end
    ok(sawStripe and sawPlain, "every other row striped")
  end)

  it("Collected on: owned rows get a light green background, full-colour icon, green name, no strike", function()
    local ns = loadUI({ filters = { collected = true } })
    local list = openJournalList(ns)
    local rows = list.ScrollBox.provider.rows
    local frames = render(list.ScrollBox)
    local owned, plain
    for i, r in ipairs(rows) do
      if not r.header and r.owned and not owned then owned = i end
      if not r.header and not r.owned and not plain then plain = i end
    end
    ok(owned and plain, "owned and missing rows listed")
    local f = frames[owned]
    ok(f.Owned:IsShown(), "green background on")
    eq(f.Owned.color, { 0.25, 0.85, 0.35, 0.14 })
    eq(f.Owned.layer, "BACKGROUND")
    eq(f.Owned.sublevel, 1, "above the stripe")
    eq(f.Icon.desaturated, false, "full-colour icon")
    eq(f.Strike, nil, "no strikethrough")
    eq(f.Name.font, ns.UI.OwnedFont(), "light green name")
    local p = frames[plain]
    ok(not p.Owned:IsShown(), "missing mounts: no green")
    eq(p.Name.font, ns.UI.Font("GameFontNormal"))
    eq(p.Icon.desaturated, false)
    -- A recycled frame drops the green look.
    list.ScrollBox.view.factory(function(_, init) init(f, rows[plain]) end, rows[plain])
    ok(not f.Owned:IsShown(), "recycled: green off")
    eq(f.Name.font, ns.UI.Font("GameFontNormal"))
    list.ScrollBox.view.factory(function(_, init) init(f, rows[owned]) end, rows[owned])
    ok(f.Owned:IsShown(), "and on again")
  end)

  it("UI.OwnedFont: a light green copy of GameFontNormal, GameFontGreen without CreateFont", function()
    local ns = loadUI()
    local name = ns.UI.OwnedFont()
    eq(name, "MountTrailFontOwned")
    local font = _G[name]
    eq(font.base, _G[ns.UI.Font("GameFontNormal")], "from the sized copy of GameFontNormal")
    eq(font.color, { 0.55, 0.95, 0.6 })
  end)

  it("the Filter menu writes ns.db.global.filters, refreshes and drives the reset arrow", function()
    local ns = loadUI()
    local list = openJournalList(ns)
    local dd = list.FilterDropdown
    local calls = openMenu(dd)
    local kinds = {}
    for _, c in ipairs(calls) do kinds[#kinds + 1] = c.kind end
    eq(kinds, { "checkbox", "divider", "title", "checkbox", "checkbox", "checkbox", "checkbox", "checkbox",
      "checkbox", "checkbox", "checkbox", "checkbox", "checkbox", "divider", "button", "button" })
    eq(calls[1].text, "Collected")
    eq(dd.resetShown, false, "defaults: no reset arrow")

    local refreshed = 0
    local realRefresh = ns.Refresh
    ns.Refresh = function() refreshed = refreshed + 1; realRefresh() end

    local raid = find(calls, "Show raid drops")
    eq(raid.isSelected(), true)
    raid.setSelected()
    eq(ns.db.global.filters.journal.raid, false)
    eq(raid.isSelected(), false, "checkbox reads the live filters")
    eq(refreshed, 1)
    eq(dd.resetShown, true, "reset arrow once a filter differs")

    find(calls, "Collected").setSelected()
    eq(ns.db.global.filters.collected, true)

    eq(find(calls, "Uncheck all").fn(), MenuResponse.Refresh, "menu stays open")
    eq(ns.db.global.filters.journal.dungeon, false)
    eq(find(calls, "Check all").fn(), MenuResponse.Refresh)
    eq(ns.db.global.filters.journal, nil, "all shown: nothing stored")
    eq(refreshed, 4)

    dd.defaultCallback()
    eq(ns.db.global.filters, ns.Journal.DefaultFilters, "reset restores the defaults")
    eq(dd.resetShown, false)
  end)

  it("the Journal menu has the ten sources before the first Refresh", function()
    local ns = loadUI()
    local parent = CreateFrame("Frame", nil, UIParent)
    local list = ns.UI.List(parent, function() return { tab = "journal" } end)
    eq(list.tab, "journal", "tab known at build time")
    local calls = openMenu(list.FilterDropdown)
    local boxes = 0
    for _, c in ipairs(calls) do if c.kind == "checkbox" then boxes = boxes + 1 end end
    eq(boxes, 11, "Collected + ten sources")
    ok(find(calls, "Show raid drops"), "sources listed")
  end)

  it("regenerates the menu when the list's tab changes", function()
    local ns = loadUI()
    local parent = CreateFrame("Frame", nil, UIParent)
    local tab = "journal"
    local list = ns.UI.List(parent, function() return { tab = tab } end)
    local generated = 0
    list.FilterDropdown.GenerateMenu = function() generated = generated + 1 end
    list:Refresh()
    eq(generated, 0, "same tab: no regeneration")
    tab = "misc"
    list:Refresh()
    eq(generated, 1)
    local boxes = 0
    for _, c in ipairs(openMenu(list.FilterDropdown)) do if c.kind == "checkbox" then boxes = boxes + 1 end end
    eq(boxes, 13, "Misc: Collected + its twelve categories")
  end)

  it("source lines use the dimmed highlight font", function()
    local ns = loadUI()
    local list = openJournalList(ns)
    local frames = render(list.ScrollBox)
    local row
    for _, f in ipairs(frames) do if f.Source then row = f; break end end
    eq(row.Source.template, "MountTrailFontSource")
    eq(MountTrailFontSource.base, GameFontHighlightSmall)
    eq(MountTrailFontSource.color, { 0.7, 0.7, 0.7 })
  end)

  it("falls back to the checkbox panel without the dropdown template", function()
    local ns = loadUI({ filters = { collected = true, journal = { raid = false } } })
    STUB_TEMPLATES.WowStyle1FilterDropdownTemplate = nil
    local list = openJournalList(ns)
    eq(list.FilterDropdown, nil)
    ok(list.FilterPanel, "checkbox panel")
    eq(list.SearchBox:GetParent(), list.FilterPanel)
    eq(#list.SectionChecks, 10)
    eq(list.CollectedCheck.checked, true)
    eq(list.SectionChecks[2].filterKey, "raid")
    eq(list.SectionChecks[2].checked, false, "raid unticked")
    eq(list.SectionChecks[2].Label.text, "Show raid drops")
    eq({ list.ScrollBox:GetPoint(1) }, { "TOPLEFT", list.FilterPanel, "TOPRIGHT", 4, 0 })
    list.SectionChecks[2].checked = true
    list.SectionChecks[2]:RunScript("OnClick")
    eq(ns.db.global.filters.journal, nil, "shown again: nothing stored")
    eq(ns.UI.TemplateFallbacks.WowStyle1FilterDropdownTemplate, false)
  end)

  it("the fallback panel shows each view's own sections", function()
    local ns = loadUI({ filters = { collected = true } })
    STUB_TEMPLATES.WowStyle1FilterDropdownTemplate = nil
    local parent = CreateFrame("Frame", nil, UIParent)
    local view = "misc"
    local list = ns.UI.List(parent, function() return { view = view } end)
    list:Refresh()
    eq(#list.SectionChecks, 12, "Misc: twelve categories")
    eq(list.SectionsTitle.text, "Categories")
    ok(list.SectionsTitle:IsShown())
    eq(list.SectionChecks[2].filterKey, "shop")
    eq(list.SectionChecks[2].Label.text, "Show in-game shop mounts")
    -- Labels stay inside the panel: fixed width, one line.
    for _, cb in ipairs(list.SectionChecks) do
      ok(cb.Label.width and cb.Label.width > 0 and cb.Label.width <= 150 - 24, "label width " .. cb.filterKey)
      eq(cb.Label.wordWrap, false, "no wrap " .. cb.filterKey)
    end
    eq(list.CollectedCheck.Label.wordWrap, false)
    list.SectionChecks[2].checked = false
    list.SectionChecks[2]:RunScript("OnClick")
    eq(ns.db.global.filters.misc, { shop = false })
    list:Refresh()
    eq(list.SectionChecks[2].checked, false)

    view = "timewalking"
    list:Refresh()
    eq(#list.SectionChecks, 0, "Timewalking: Collected only")
    ok(not list.SectionsTitle:IsShown(), "no title")
    for _, cb in ipairs(list.SectionPool) do ok(not cb:IsShown(), "unused checkboxes hidden") end

    view = "journal"
    list:Refresh()
    eq(#list.SectionChecks, 10)
    eq(list.SectionsTitle.text, "Sources")
    eq(list.SectionChecks[1].checked, true)
    ok(list.SectionChecks[1]:IsShown())
  end)

  it("falls back to the panel when the template lacks SetupMenu", function()
    local ns = loadUI()
    local saved = STUB_TEMPLATE_METHODS.WowStyle1FilterDropdownTemplate
    STUB_TEMPLATE_METHODS.WowStyle1FilterDropdownTemplate = nil
    local good, list = pcall(openJournalList, ns)
    STUB_TEMPLATE_METHODS.WowStyle1FilterDropdownTemplate = saved -- restore before any assert
    ok(good, tostring(list))
    eq(list.FilterDropdown, nil)
    ok(list.FilterPanel, "checkbox panel")
    eq(ns.UI.TemplateFallbacks["DropdownButton:SetupMenu"], "checkbox panel", "listed by /mtrail debug")
    eq(ns.UI.TemplateFallbacks.WowStyle1FilterDropdownTemplate, nil, "the template itself was there")
    run_slash(ns.addon, "azt", "debug")
    eq(ns.addon.printed[#ns.addon.printed], "Template DropdownButton:SetupMenu missing, using checkbox panel")
  end)

  it("Holidays, Achievements, Timewalking and Misc build their lists with their own Filter menus", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local want = {
      holidays = { boxes = 1 + 10, title = "Holidays", first = "Show Hallow's End" },
      achievements = { boxes = 1 + #ns.Data.Expansions + 1, title = "Expansions", first = "Show Classic achievements" },
      timewalking = { boxes = 1 },
      misc = { boxes = 1 + 12, title = "Categories", first = "Show profession mounts" },
    }
    for _, key in ipairs({ "holidays", "achievements", "timewalking", "misc" }) do
      ns.UI.SelectTab(key)
      local list = content(ns, key).children[2]
      ok(list and list.FilterDropdown, key .. ": dropdown")
      eq(list.tab, key, key .. ": the list knows its view")
      local calls = openMenu(list.FilterDropdown)
      local boxes, title = 0, nil
      for _, c in ipairs(calls) do
        if c.kind == "checkbox" then boxes = boxes + 1 end
        if c.kind == "title" then title = c.text end
      end
      eq(boxes, want[key].boxes, key .. ": checkboxes")
      eq(title, want[key].title, key .. ": title")
      if want[key].first then eq(calls[4].text, want[key].first, key .. ": first section") end
      if key == "timewalking" then eq(#calls, 1, "Timewalking: Collected only") end
      render(list.ScrollBox)
    end
  end)

  it("a Misc filter hides that category on Misc only, with its own reset arrow", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local function sections(key)
      ns.UI.SelectTab(key)
      local seen = {}
      for _, row in ipairs(content(ns, key).children[2].ScrollBox.provider.rows) do
        if row.header and row.depth == 1 then seen[row.section] = true end
      end
      return seen
    end
    ok(sections("misc").shop, "shop listed")
    local misc = content(ns, "misc").children[2]
    eq(misc.FilterDropdown.resetShown, false)
    local shop = find(openMenu(misc.FilterDropdown), "Show in-game shop mounts")
    shop.setSelected()
    eq(ns.db.global.filters.misc, { shop = false })
    eq(shop.isSelected(), false)
    ok(not sections("misc").shop, "shop hidden")
    ok(sections("misc").profession, "the rest stays")
    eq(misc.FilterDropdown.resetShown, true, "Misc: reset arrow")
    ok(sections("holidays").brewfest, "Brewfest listed")
    local holidays = content(ns, "holidays").children[2]
    eq(holidays.FilterDropdown.isDefaultCallback(), true, "Holidays: no reset arrow")
    eq(holidays.FilterDropdown.resetShown, false)

    find(openMenu(holidays.FilterDropdown), "Show Brewfest").setSelected()
    eq(ns.db.global.filters.holidays, { brewfest = false })
    ok(not sections("holidays").brewfest, "Brewfest hidden on Holidays")

    ns.db.global.filters.collected = true
    misc.FilterDropdown.defaultCallback()
    eq(ns.db.global.filters.misc, nil, "Misc reset")
    eq(ns.db.global.filters.holidays, { brewfest = false }, "Holidays untouched")
    eq(ns.db.global.filters.collected, false, "reset turns Collected off")
    ok(sections("misc").shop, "shop back")
  end)

  it("Misc always lists Show unobtainable mounts in its menu, last", function()
    local ns = loadUI()
    ns.ToggleWindow()
    ns.UI.SelectTab("misc")
    local misc = content(ns, "misc").children[2]
    local calls = openMenu(misc.FilterDropdown)
    eq(calls[#calls - 3].text, "Show unobtainable mounts", "option off")
    ok(not find(calls, "Show limited-time mounts"), "no Limited time category")
    ns.db.global.settings.showUnobtainable = true
    calls = openMenu(misc.FilterDropdown)
    eq(calls[#calls - 3].text, "Show unobtainable mounts", "option on")
  end)

  it("UI.CreateFilterDropdown: a reusable Filter button over an items generator", function()
    local ns = loadUI()
    local parent = CreateFrame("Frame", nil, UIParent)
    local state = { collected = false, a = true }
    local changes, resets, defaultNow = {}, 0, true
    local dd = ns.UI.CreateFilterDropdown(parent, {
      items = function()
        return {
          { kind = "checkbox", key = "collected", label = "Collected", checked = state.collected },
          { kind = "divider" },
          { kind = "title", label = "Things" },
          { kind = "checkbox", key = "a", label = "Show a", checked = state.a },
          { kind = "button", action = "checkAll", label = "Check all" },
        }
      end,
      onChange = function(kind, value)
        changes[#changes + 1] = kind .. ":" .. value
        if kind == "toggle" then state[value] = not state[value] end
      end,
      isDefault = function() return defaultNow end,
      reset = function() resets = resets + 1 end,
    })
    ok(dd, "built")
    eq(dd:GetParent(), parent)
    local calls = openMenu(dd)
    eq(#calls, 5)
    eq(calls[3], { kind = "title", text = "Things" })
    local a = find(calls, "Show a")
    eq(a.isSelected(), true)
    a.setSelected()
    eq(a.isSelected(), false, "reads the generator live")
    eq(find(calls, "Check all").fn(), MenuResponse.Refresh)
    eq(changes, { "toggle:a", "action:checkAll" })
    dd:ValidateResetState()
    eq(dd.resetShown, false)
    defaultNow = false
    dd:ValidateResetState()
    eq(dd.resetShown, true)
    dd.defaultCallback()
    eq(resets, 1)

    local plain = ns.UI.CreateFilterDropdown(parent, { items = function() return {} end, onChange = function() end })
    ok(plain, "isDefault / reset are optional")
    eq(plain.defaultCallback, nil)

    -- Checkbox states come from one items() call per menu build / change,
    -- not one per checkbox.
    local calls, shown = 0, { a = true, b = false, c = true }
    local counted = ns.UI.CreateFilterDropdown(parent, {
      items = function()
        calls = calls + 1
        local out = {}
        for _, k in ipairs({ "a", "b", "c" }) do
          out[#out + 1] = { kind = "checkbox", key = k, label = k, checked = shown[k] }
        end
        return out
      end,
      onChange = function(_, key) shown[key] = not shown[key] end,
      isDefault = function() return true end,
      reset = function() shown.a, shown.b, shown.c = true, true, true end,
    })
    local menu = openMenu(counted)
    eq(calls, 1, "the menu build reads items() once")
    eq({ menu[1].isSelected(), menu[2].isSelected(), menu[3].isSelected() }, { true, false, true })
    eq(calls, 1, "checkbox states from the same read")
    menu[2].setSelected()
    eq({ menu[1].isSelected(), menu[2].isSelected(), menu[3].isSelected() }, { true, true, true })
    eq(calls, 2, "one fresh read after a change")
    shown.a = false
    counted.defaultCallback()
    eq(menu[1].isSelected(), true, "reset refreshes the states too")
    eq(calls, 3)

    -- opts.fallbackName: what /mtrail debug says replaces the dropdown
    -- (default "checkbox panel").
    local saved = STUB_TEMPLATE_METHODS.WowStyle1FilterDropdownTemplate
    local function noSetup(name)
      ns.UI.TemplateFallbacks["DropdownButton:SetupMenu"] = nil
      STUB_TEMPLATE_METHODS.WowStyle1FilterDropdownTemplate = nil
      local good, dd = pcall(ns.UI.CreateFilterDropdown, parent, { items = function() return {} end,
        onChange = function() end, fallbackName = name })
      STUB_TEMPLATE_METHODS.WowStyle1FilterDropdownTemplate = saved
      assert(good, dd)
      eq(dd, nil)
      return ns.UI.TemplateFallbacks["DropdownButton:SetupMenu"]
    end
    eq(noSetup("no checklist filter"), "no checklist filter")
    eq(noSetup(nil), "checkbox panel")

    STUB_TEMPLATES.WowStyle1FilterDropdownTemplate = nil
    eq(ns.UI.CreateFilterDropdown(parent, { items = function() return {} end, onChange = function() end }), nil,
      "nil without the 11.x template")
  end)

  -- Header and mount rows of a list tab, built from the real Data/Mounts.lua.
  local function tabRows(ns, key)
    ns.UI.SelectTab(key)
    local headers, mounts = {}, {}
    for _, row in ipairs(content(ns, key).children[2].ScrollBox.provider.rows) do
      if row.header then headers[#headers + 1] = row else mounts[#mounts + 1] = row end
    end
    return headers, mounts
  end

  it("each list tab shows its own mounts (real data)", function()
    local ns = loadUI({ filters = { collected = true } })
    ns.ToggleWindow()
    local Journal = ns.Journal

    local headers, mounts = tabRows(ns, "achievements")
    ok(#mounts > 50, "achievement mounts listed: " .. #mounts)
    for _, row in ipairs(mounts) do
      eq({ row.m.tab, row.m.section }, { "misc", "achievement" }, "achievements row " .. row.id)
    end
    local expIndex = {}
    for i, name in ipairs(ns.Data.Expansions) do expIndex[name] = i end
    local last = 0
    for _, h in ipairs(headers) do
      local i = expIndex[h.section] or (h.section == "General" and 1000)
      ok(i and i > last, "expansion headers in Data.Expansions order, General last: " .. tostring(h.section))
      eq(h.text, h.section, "header names the expansion")
      last = i
    end

    headers, mounts = tabRows(ns, "timewalking")
    ok(#mounts > 10, "timewalking mounts listed: " .. #mounts)
    eq(#headers, 1)
    eq(headers[1].text, "Timewalking")
    for _, row in ipairs(mounts) do eq(Journal.ViewOf(row.m), "timewalking", "timewalking row " .. row.id) end

    headers, mounts = tabRows(ns, "holidays")
    ok(#mounts > 10, "holiday mounts listed")
    for _, row in ipairs(mounts) do
      eq(Journal.ViewOf(row.m), "holidays", "holidays row " .. row.id)
      ok(row.m.section ~= "timewalking", "no timewalking on Holidays")
    end
    for _, h in ipairs(headers) do
      ok(h.section ~= "timewalking", "no Timewalking header on Holidays")
      if h.section == "brewfest" then eq(h.badge, "Active now") end
    end

    headers, mounts = tabRows(ns, "misc")
    ok(#mounts > 100, "misc mounts listed")
    local allowed = { profession = 1, shop = 2, tradingpost = 3, pvp = 4, racial = 5, keystone = 6,
      promotion = 7, class = 8, bmah = 9, collection = 10, other = 11, unobtainable = 12 }
    local labels = { profession = "Professions", shop = "In-game Shop", tradingpost = "Trading Post",
      pvp = "PvP", racial = "Racial", keystone = "Mythic+", promotion = "Promotions", class = "Class",
      bmah = "Black Market", collection = "Collection rewards", other = "Other", unobtainable = "Unobtainable" }
    for _, row in ipairs(mounts) do eq(Journal.ViewOf(row.m), "misc", "misc row " .. row.id) end
    last = 0
    for _, h in ipairs(headers) do
      ok(allowed[h.section] and allowed[h.section] > last, "misc header " .. tostring(h.section))
      eq(h.text, labels[h.section], "misc header label " .. tostring(h.section))
      last = allowed[h.section]
    end
  end)

  it("Show unobtainable mounts: Misc gains an Unobtainable section, last (real data)", function()
    local ns = loadUI({ filters = { collected = true } })
    ns.ToggleWindow()
    local Journal = ns.Journal
    -- Off: Unobtainable holds only owned limited-time mounts (data section
    -- "unobtainable"), listed with Collected on.
    local headers, offRows = tabRows(ns, "misc")
    eq(headers[#headers].section, "unobtainable", "off: the Unobtainable header is still last")
    local sawOwned = false
    for _, row in ipairs(offRows) do
      if row.m.unobtainable then
        eq(row.id % 3, 0, "off: owned unobtainable only " .. row.id)
        if row.m.section == "unobtainable" then sawOwned = true end
      end
    end
    ok(sawOwned, "owned limited-time mounts listed under Unobtainable")

    -- Not-owned unobtainable mounts the stub client lists (owned: id % 3 == 0;
    -- Alliance).
    local want = {}
    for id, m in pairs(ns.Data.Mounts) do
      if m.unobtainable and id % 3 ~= 0 and (m.faction == nil or m.faction == "Alliance") then
        want[id] = true
      end
    end
    ok(next(want), "the data has unobtainable mounts")

    ns.db.global.settings.showUnobtainable = true
    ns.Refresh()
    local mounts
    headers, mounts = tabRows(ns, "misc")
    local lastHeader = headers[#headers]
    eq(lastHeader.section, "unobtainable")
    eq(lastHeader.text, "Unobtainable")
    local got = {}
    for _, row in ipairs(mounts) do
      if row.m.unobtainable and row.id % 3 ~= 0 then -- owned ones stay in their own section
        ok(want[row.id], "only not-owned unobtainable mounts on Misc: " .. row.id)
        got[row.id] = true
      end
    end
    for id in pairs(want) do ok(got[id], "unobtainable mount " .. id .. " on Misc") end

    for _, key in ipairs({ "holidays", "achievements", "timewalking" }) do
      local _, rows = tabRows(ns, key)
      for _, row in ipairs(rows) do
        ok(not (row.m.unobtainable and want[row.id]), key .. " lists unobtainable " .. row.id)
      end
    end
    local o, t = Journal.Counts(ns.Data.Mounts, nil, ns.Game.IsOwned, ns.Game.Exists, "Alliance")
    ns.db.global.settings.showUnobtainable = false
    local o2, t2 = Journal.Counts(ns.Data.Mounts, nil, ns.Game.IsOwned, ns.Game.Exists, "Alliance")
    eq({ o, t }, { o2, t2 }, "journal counts do not depend on the setting")
  end)

  it("Holidays tab: headers carry the dates of Game.HolidaySchedule; Active now when it has none", function()
    local ns = loadUI({ filters = { collected = true } })
    local function ct(month, monthDay, hour)
      return { year = 2026, month = month, monthDay = monthDay, weekday = 1, hour = hour or 0, minute = 0 }
    end
    ns.Game.HolidaySchedule = function()
      return { now = ct(10, 19, 12), occurrences = {
        brewfest = { { startTime = ct(9, 20), endTime = ct(10, 25, 15) } }, -- running, 6d 3h left
        hallowsend = { { startTime = ct(10, 28, 12), endTime = ct(11, 2) } }, -- in 9d
      } }
    end
    ns.ToggleWindow()
    local headers = tabRows(ns, "holidays")
    local by = {}
    for _, h in ipairs(headers) do by[h.section] = h end
    eq(by.brewfest.badge, "Active · ends in 6d")
    eq(by.brewfest.badgeMuted, nil)
    eq(by.brewfest.active, true)
    eq(by.hallowsend.badge, "Starts in 9d")
    eq(by.hallowsend.badgeMuted, true)
    eq(by.hallowsend.active, nil)
    eq(by.loveisintheair.badge, nil, "no date in the schedule: no badge")

    ns.Game.HolidaySchedule = function() return nil end
    ns.Refresh()
    headers = tabRows(ns, "holidays")
    by = {}
    for _, h in ipairs(headers) do by[h.section] = h end
    eq(by.brewfest.badge, "Active now")
    eq(by.hallowsend.badge, nil)
  end)

  it("Checklist tab: a flat header (name, resets, flavour, Filter) over the list; no route controls (F16)", function()
    local ns = loadUI()
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    local root = content(ns, "checklist").children[2]
    local header = root.children[1]
    eq(header.Name:GetText(), "Tester")
    local summary = header.Resets:GetText()
    ok(summary:find("^Daily reset in "), summary)
    ok(summary:find("Weekly reset in ", 1, true), summary)
    ok(not summary:find("left", 1, true), "the chips carry the counts")
    eq(header.Flavour:GetText(), string.format("You have %d lockouts left. Saddle up?", ns.UI.ChecklistRemaining()))
    eq(header.height, 96)
    ok(header.ChecklistFilter and header.ChecklistFilter:IsShown(), "Filter button shown")
    eq(header.PopOut, nil, "no pop-out button: rare headers pop out on right-click")
    -- Chips: All (shown, gold) / Daily (n) / Weekly (n) / Rare spawns (n).
    local chips = header.Chips
    eq(#chips, 5)
    ok(chips[5].Text:GetText():find("^Lists %(%d+%)$"), chips[5].Text:GetText())
    eq(chips[1].Text:GetText(), "All")
    eq(chips[1].selected, true)
    ok(chips[2].Text:GetText():find("^Daily %(%d+%)$"), chips[2].Text:GetText())
    ok(chips[4].Text:GetText():find("^Rare spawns %(%d+%)$"), chips[4].Text:GetText())
    chips[4]:RunScript("OnClick", "LeftButton")
    eq(ns.db.char.checklistShow, "camp")
    eq(chips[4].selected, true)
    for _, row in ipairs(header.Checklist.ScrollBox.provider.rows) do
      ok(row.camp, "only the rare spawns group")
    end
    chips[1]:RunScript("OnClick", "LeftButton")
    ok(header.Checklist and header.Checklist:IsShown(), "the checklist list is shown")
    for _, gone in ipairs({ "ShowCompleted", "ModeControl", "ListMode", "ArrowMode", "ViewControl",
      "RouteViewButton", "ChecklistViewButton" }) do
      eq(header[gone], nil, gone .. " is retired")
    end
    local boxes = 0
    for _, child in ipairs(root.children) do if child.view then boxes = boxes + 1 end end
    eq(boxes, 0, "no route list beside the checklist")
    -- Everything done: the Oregon line.
    ns.db.char.checklistFilters = { raids = false, dungeons = false, worldbosses = false, rares = false,
      holidays = false, other = false, camp = false, quick = false }
    ns.Refresh()
    eq(header.Flavour:GetText(), "Tester has reached Oregon. Nothing left to farm until reset.")
    ok(header.Checklist.Empty:IsShown(), "empty line")
  end)

  it("Checklist: right-clicking a rare header pops that expansion out; hovering says so", function()
    local ns = loadUI()
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    local root = content(ns, "checklist").children[2]
    local header = root.children[1]
    local popped = {}
    ns.UI.OpenPopout = function(source) popped[#popped + 1] = source end
    local tip = { lines = {} }
    function tip:SetOwner() end
    function tip:SetText(t) self.text = t end
    function tip:Show() self.shown = true end
    function tip:Hide() self.shown = false end
    local oldTip = GameTooltip
    GameTooltip = tip
    local rareHeader, plainHeader
    for _, f in ipairs(render(header.Checklist.ScrollBox)) do
      if f.data and f.data.header then
        if f.data.popout and not rareHeader then rareHeader = f end
        if not f.data.popout and not plainHeader then plainHeader = f end
      end
    end
    ok(rareHeader, "real data has a rare header")
    rareHeader:RunScript("OnEnter")
    local hint = _G.MountTrailHint
    ok(hint and hint:IsShown(), "the window-styled hint, not the game tooltip")
    eq(hint.Title:GetText(), "Right-click to pop out " .. ns.UI.PopoutTitle(rareHeader.data.popout))
    eq(hint.Fill.color, { 0.05, 0.05, 0.06, 0.85 }, "flat, slightly see-through")
    eq(tip.text, nil, "the game tooltip is not used")
    rareHeader:RunScript("OnLeave")
    ok(not hint:IsShown(), "hidden on leave")
    rareHeader:RunScript("OnMouseUp", "RightButton")
    eq(popped, { rareHeader.data.popout })
    plainHeader:RunScript("OnMouseUp", "RightButton")
    eq(#popped, 1, "other headers do nothing on right-click")
    GameTooltip = oldTip
    eq(ns.UI.ChecklistPopout({ header = true, depth = 2, camp = true, exp = "Legion" }), { kind = "camp", exp = "Legion" })
    eq(ns.UI.ChecklistPopout({ header = true, depth = 1, camp = true }), { kind = "zone" })
    eq(ns.UI.ChecklistPopout({ header = true, depth = 3, reset = "daily", category = "rares", exp = "Cataclysm" }),
      { kind = "daily", exp = "Cataclysm", category = "rares" })
    eq(ns.UI.ChecklistPopout({ header = true, depth = 2, reset = "weekly", exp = "Legion" }), { kind = "weekly", exp = "Legion" })
    eq(ns.UI.ChecklistPopout({ header = true, depth = 1, reset = "daily" }), nil, "Daily itself")
  end)

  it("mount rows (lists and Checklist) take left and right clicks and dispatch through HandleRowClick", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local got = {}
    ns.UI.HandleRowClick = function(id, button) got[#got + 1] = { id, button } end
    ns.UI.SelectTab("achievements")
    local row
    for _, f in ipairs(render(content(ns, "achievements").children[2].ScrollBox)) do
      if f.mountID and not row then row = f end
    end
    ok(row, "achievement row rendered")
    eq(row.clickButtons, { "LeftButtonUp", "RightButtonUp" })
    row:RunScript("OnClick", "RightButton")
    eq(got[1], { row.mountID, "RightButton" })

    ns.UI.SelectTab("checklist")
    local box = content(ns, "checklist").children[2].children[1].Checklist.ScrollBox
    local checkRow
    for _, f in ipairs(render(box)) do
      if f.mountID and not checkRow then checkRow = f end
    end
    ok(checkRow, "checklist row rendered")
    eq(checkRow.clickButtons, { "LeftButtonUp", "RightButtonUp" })
    checkRow:RunScript("OnClick", "RightButton")
    eq(got[2], { checkRow.mountID, "RightButton" })
  end)

  it("mount rows have no Map button and show a pin only where Map.HasLocation says so", function()
    local ns = loadUI()
    ns.Map.Resolve = function() error("Resolve must not run on refresh") end
    ns.Map.HasLocation = function(id) return id % 2 == 0 or id % 5 == 0 end
    local list = openJournalList(ns)
    local rows = list.ScrollBox.provider.rows
    local frames = render(list.ScrollBox)
    local pins, bare = 0, 0
    for i, row in ipairs(rows) do
      local f = frames[i]
      if not row.header then
        eq(f.Map, nil, "no Map button")
        local want = row.id % 2 == 0 or row.id % 5 == 0
        eq(f.Pin:IsShown(), want, "pin for " .. row.id)
        if want then pins = pins + 1 else bare = bare + 1 end
      end
    end
    ok(pins > 0 and bare > 0, "both kinds of rows rendered")

    -- The pin is the map-pin atlas when the client has it.
    STUB_ATLASES["Waypoint-MapPin-ChatIcon"] = true
    local f
    for i, row in ipairs(rows) do if not row.header and row.id % 2 == 0 and not f then f = render(list.ScrollBox)[i] end end
    eq(f.Pin.atlas, "Waypoint-MapPin-ChatIcon")
  end)

  -- Mount rows under each section header of a provider -> { [key] = n }.
  local function shownPerSection(rows)
    local shown, key = {}, nil
    for _, row in ipairs(rows) do
      if row.header and row.depth == 1 then
        key = row.key
        shown[key] = 0
      elseif not row.header then
        shown[key] = shown[key] + 1
      end
    end
    return shown
  end

  it("Shift-click a header: every header of the list collapses; on a collapsed one, all expand (nested too)", function()
    local ns = loadUI()
    local list = openJournalList(ns)
    local rows = list.ScrollBox.provider.rows
    local before = #rows
    local tops = 0
    for _, r in ipairs(rows) do if r.header and r.depth == 1 then tops = tops + 1 end end
    ok(tops >= 2, "several sections")
    -- A sub-header collapsed earlier, to see Expand all reach it.
    local sub
    for _, r in ipairs(rows) do if r.header and r.depth == 2 then sub = r.key break end end
    ns.db.global.collapsed[sub or "journal|Classic|x|y"] = true
    IsShiftKeyDown = function() return true end
    render(list.ScrollBox)[1]:RunScript("OnMouseUp", "LeftButton")
    rows = list.ScrollBox.provider.rows
    for _, r in ipairs(rows) do ok(r.header and r.collapsed, "only collapsed headers left") end
    eq(#rows, tops)
    render(list.ScrollBox)[1]:RunScript("OnMouseUp", "LeftButton")
    IsShiftKeyDown = nil
    eq(ns.db.global.collapsed, {}, "all expanded, the nested one too")
    eq(#list.ScrollBox.provider.rows, before)
  end)

  it("headers explain collapsing on hover; a pop-out hint keeps its line on top", function()
    local ns = loadUI()
    eq({ ns.UI.HeaderHint(nil, true) }, { "Click: collapse or expand", "Shift-click: collapse or expand all" })
    eq({ ns.UI.HeaderHint("Right-click to pop out Weeklies", true) },
      { "Right-click to pop out Weeklies", "Click: collapse or expand. Shift-click: all at once" })
    eq({ ns.UI.HeaderHint("Just a hint", false) }, { "Just a hint", nil })
    eq(ns.UI.HeaderHint(nil, false), nil, "nothing to say")
    local hints = {}
    ns.UI.ShowHint = function(_, title, text) hints[#hints + 1] = { title, text } end
    local list = openJournalList(ns)
    render(list.ScrollBox)[1]:RunScript("OnEnter")
    eq(hints[#hints], { "Click: collapse or expand", "Shift-click: collapse or expand all" })
  end)

  it("UI.ToggleAllCollapsed: collapse every shown header; expand them and the keys under them", function()
    local ns = loadUI()
    local store = { ["c|a|x"] = true, ["other|z"] = true }
    local rows = { { header = true, key = "c|a" }, { id = 1 }, { header = true, key = "c|b", collapsed = true } }
    eq(ns.UI.ToggleAllCollapsed(store, rows, rows[1]), true)
    eq(store, { ["c|a"] = true, ["c|b"] = true, ["c|a|x"] = true, ["other|z"] = true })
    eq(ns.UI.ToggleAllCollapsed(store, rows, rows[3]), false)
    eq(store, { ["other|z"] = true }, "another list's keys stay")
  end)

  it("section headers collapse on left-click, saved per view and expansion", function()
    local ns = loadUI()
    eq(ns.db.global.collapsed, {}, "AceDB default")
    local list = openJournalList(ns)
    local rows = list.ScrollBox.provider.rows
    local first = rows[1]
    ok(first.header and first.depth == 1, "a section header first")
    eq(first.key, "journal|Classic|" .. first.section)
    local before = #rows
    local header = render(list.ScrollBox)[1]
    ok(header.mouse, "header takes the mouse")
    eq(header.Indicator:IsShown() or header.IndicatorText:IsShown(), true, "a +/- indicator")
    eq(header.IndicatorText.text, "\226\128\147", "expanded: en dash (no atlas in the stub)")

    header:RunScript("OnMouseUp", "LeftButton")
    eq(ns.db.global.collapsed, { [first.key] = true })
    rows = list.ScrollBox.provider.rows
    eq(rows[1].collapsed, true)
    ok(rows[2] == nil or (rows[2].header and rows[2].depth == 1), "its sub-headers and mounts are gone")
    ok(#rows < before, "fewer rows")
    header = render(list.ScrollBox)[1]
    eq(header.IndicatorText.text, "+")

    header:RunScript("OnMouseUp", "RightButton")
    eq(ns.db.global.collapsed[first.key], true, "right-click does nothing")
    header:RunScript("OnMouseUp", "LeftButton")
    eq(ns.db.global.collapsed, {}, "expanded again: the key is removed")
    eq(#list.ScrollBox.provider.rows, before)
  end)

  it("uses the atlas indicator when the client has it", function()
    local ns = loadUI()
    STUB_ATLASES.campaign_headericon_open = true
    STUB_ATLASES.campaign_headericon_closed = true
    local list = openJournalList(ns)
    local header = render(list.ScrollBox)[1]
    eq(header.Indicator.atlas, "campaign_headericon_open")
    ok(header.Indicator:IsShown() and not header.IndicatorText:IsShown(), "atlas, no text")
  end)

  it("sub-headers are indented and smaller; counts include owned mounts the Collected filter hides", function()
    local ns = loadUI()
    ns.Game.MountSourceText = function(id) return "|cFFFFD200Zone:|r Zone " .. (id % 2) end
    local list = openJournalList(ns)
    local rows = list.ScrollBox.provider.rows
    local frames = render(list.ScrollBox)
    local top, sub
    for i, row in ipairs(rows) do
      if row.header and row.depth == 1 and not top then top = frames[i] end
      if row.header and row.depth == 2 and not sub then sub = frames[i] end
      if not row.header then eq(row.owned, false, "Collected off: no owned rows") end
    end
    ok(sub, "dungeon/raid/world sections split into sub-groups")
    eq(top.Label.font, ns.UI.Font("GameFontNormal"))
    eq(sub.Label.font, ns.UI.Font("GameFontNormalSmall"))
    ok(select(4, sub.Indicator:GetPoint(1)) > select(4, top.Indicator:GetPoint(1)), "sub-header indented")
    eq(list.ScrollBox.view.extent(1, { header = true, depth = 2 }) < list.ScrollBox.view.extent(1, rows[1]), true,
      "sub-headers are shorter")

    local shown = shownPerSection(rows)
    local sawOwned = false
    for _, row in ipairs(rows) do
      if row.header and row.depth == 1 then
        eq(shown[row.key], row.total - row.owned, row.key .. ": hidden owned mounts still counted")
        if row.owned > 0 then sawOwned = true end
      end
    end
    ok(sawOwned, "some section has owned mounts")

    ns.db.global.filters.collected = true
    list:Refresh()
    rows = list.ScrollBox.provider.rows
    shown = shownPerSection(rows)
    for _, row in ipairs(rows) do
      if row.header and row.depth == 1 then eq(shown[row.key], row.total, row.key .. ": all shown") end
    end
  end)

  -- The init function the list's ScrollBox factory picks for `data`.
  local function initFor(box, data)
    local got
    box.view.factory(function(_, init) got = init end, data)
    return got
  end

  it("a header toggles only when the mouse is still over it, and recycled headers reset their hover", function()
    local ns = loadUI()
    local list = openJournalList(ns)
    local rows = list.ScrollBox.provider.rows
    local header = render(list.ScrollBox)[1]
    header.mouseOver = false
    header:RunScript("OnMouseUp", "LeftButton")
    eq(ns.db.global.collapsed, {}, "released outside: no toggle")
    header.mouseOver = true
    header:RunScript("OnMouseUp", "LeftButton")
    eq(ns.db.global.collapsed[rows[1].key], true, "released over it: toggles")

    header:RunScript("OnEnter")
    ok(header.Hover:IsShown(), "hover band")
    header.mouseOver = false
    initFor(list.ScrollBox, rows[1])(header, rows[1])
    ok(not header.Hover:IsShown(), "recycled away from the mouse: no stale hover")
    header.mouseOver = true
    initFor(list.ScrollBox, rows[1])(header, rows[1])
    ok(header.Hover:IsShown(), "recycled under the mouse: hover shown")
  end)

  it("mount rows under a sub-header are indented to the sub-header's inset", function()
    local ns = loadUI()
    ns.Game.MountSourceText = function(id) return "|cFFFFD200Zone:|r Zone " .. (id % 2) end
    local list = openJournalList(ns)
    local rows = list.ScrollBox.provider.rows
    local frames = render(list.ScrollBox)
    local subHeader, nested
    for i, row in ipairs(rows) do
      if row.header and row.depth == 2 and not subHeader then subHeader = frames[i] end
      if not row.header and row.depth == 2 and not nested then nested = i end
    end
    ok(subHeader and nested, "a nested mount row")
    local inset = select(4, subHeader.Indicator:GetPoint(1))
    eq(select(4, frames[nested].Icon:GetPoint(1)), inset, "icon lines up with the sub-header indicator")
    -- The same frame recycled for a flat row goes back to the normal inset.
    local flat = { id = rows[nested].id, m = rows[nested].m, owned = false }
    initFor(list.ScrollBox, flat)(frames[nested], flat)
    eq(select(4, frames[nested].Icon:GetPoint(1)), 4)
  end)

  it("other tabs collapse their (flat) sections under their own view key", function()
    local ns = loadUI()
    ns.ToggleWindow()
    ns.UI.SelectTab("holidays")
    local list = content(ns, "holidays").children[2]
    local header = render(list.ScrollBox)[1]
    local key = list.ScrollBox.provider.rows[1].key
    ok(key:find("^holidays||"), key)
    header:RunScript("OnMouseUp", "LeftButton")
    eq(ns.db.global.collapsed[key], true)
  end)

  it("opening the Achievements tab starts the achievement scan", function()
    local ns = loadUI()
    local ensured = 0
    ns.AchievementScan.Ensure = function() ensured = ensured + 1 end
    ns.ToggleWindow()
    eq(ensured, 0, "not on the Journal tab")
    ns.UI.SelectTab("achievements")
    ok(ensured >= 1, "started")
  end)

  -- Zone panel (F6) ------------------------------------------------------------

  local ZONE_MAPS = {
    [12] = { name = "Kalimdor", mapType = 2 },
    [71] = { name = "Tanaris", mapType = 3, parentMapID = 12 },
    [249] = { name = "Uldum", mapType = 3, parentMapID = 12 },
    [900] = { name = "Empty Isle", mapType = 3, parentMapID = 12 },
    [74] = { name = "Caverns of Time", mapType = 5, parentMapID = 71 },
    [75] = { name = "Caverns of Time", mapType = 5, parentMapID = 74 },
  }

  -- Real mount data; the player stands on `map.id` (Tanaris unless changed);
  -- mounts whose ID is a multiple of 7 say "Zone: Tanaris", of 11 "Zone: Uldum".
  local function loadZoneUI(global)
    local ns = loadUI(global)
    local map = { id = 71 }
    ns.Game.PlayerMap = function() return map.id end
    ns.Game.MapInfo = function(id) return ZONE_MAPS[id] end
    ns.Game.DungeonEntrances = function() return {} end
    ns.Game.MapChildren = function() return {} end
    ns.Game.InstanceForMap = function() return nil end
    ns.Game.JournalInstanceName = function() return nil end
    ns.Game.CurrentInstanceName = function() return nil end
    ns.Game.MountSourceText = function(id)
      if id % 7 == 0 then return "|cFFFFD200Zone:|r Tanaris" end
      if id % 11 == 0 then return "|cFFFFD200Zone:|r Uldum" end
      return nil
    end
    ns.Map.CoordsFor = function() return nil end
    ns.Map.Spots = function() return {} end -- the fixture zones only
    local computed = 0
    local real = ns.Zone.MountsFor
    ns.Zone.MountsFor = function(...) computed = computed + 1; return real(...) end
    return ns, map, function() return computed end
  end

  it("zone panel: docked right of the window, toggled by the title-bar button, state saved", function()
    local ns = loadZoneUI()
    eq(ns.db.global.zonePanel, { open = false }, "AceDB default")
    ns.ToggleWindow()
    local frame, panel = ns.UI.frame, ns.UI.zonePanel
    ok(panel and frame.ZoneButton, "panel and toggle built with the window")
    eq(panel:GetParent(), frame, "child of the window: shown only with it")
    eq({ panel:GetPoint(1) }, { "TOPLEFT", frame, "TOPRIGHT", 2, 0 })
    eq({ panel:GetPoint(2) }, { "BOTTOMLEFT", frame, "BOTTOMRIGHT", 2, 0 })
    eq(panel.width, 260)
    ok(not panel:IsShown(), "closed by default")
    eq({ frame.DragHandle:GetPoint(2) }, { "TOPRIGHT", frame, "TOPRIGHT", -74, 0 }, "drag handle leaves room (zone panel and settings buttons)")

    frame.ZoneButton:RunScript("OnClick")
    eq(ns.db.global.zonePanel.open, true)
    ok(panel:IsShown(), "opened")
    ok(frame.ZoneButton.Selected:IsShown(), "toggle shows the open state")
    local title = panel.Title:GetText()
    ok(title:find("^Mounts in Tanaris  "), title)
    -- Mount rows (the zone's sources may add a header each).
    local rows = {}
    for _, row in ipairs(panel.ScrollBox.provider.rows) do
      if not row.header then rows[#rows + 1] = row end
    end
    ok(#rows > 0, "mounts listed")
    ok(title:find("(" .. #rows .. ")", 1, true), "count in the title")
    ok(not panel.Empty:IsShown(), "no empty line")
    for _, row in ipairs(rows) do
      eq(row.id % 7, 0, "Tanaris mount " .. row.id)
      ok(row.id % 3 ~= 0, "owned mounts hidden")
      ok(row.m.faction == nil or row.m.faction == "Alliance", "other faction hidden")
    end

    -- Rows are the mount list's rows: tooltip, pin, click dispatch.
    local got = {}
    ns.UI.HandleRowClick = function(id, button) got[#got + 1] = { id, button } end
    local all = render(panel.ScrollBox)
    eq(#all, #panel.ScrollBox.provider.rows)
    -- Source headers (Dungeon drops, Vendors, ...) when the zone has several.
    local frames, headers = {}, 0
    for i, f in ipairs(all) do
      if panel.ScrollBox.provider.rows[i].header then
        headers = headers + 1
        ok(f.Label and f.Label:GetText() ~= "", "a source header")
      else
        frames[#frames + 1] = f
      end
    end
    eq(#frames, #rows)
    ok(frames[1].Name and frames[1].Pin and frames[1].Source, "mount row look")
    eq(frames[1].clickButtons, { "LeftButtonUp", "RightButtonUp" })
    frames[1]:RunScript("OnClick", "LeftButton")
    eq(got[1], { rows[1].id, "LeftButton" })

    frame.ZoneButton:RunScript("OnClick")
    eq(ns.db.global.zonePanel.open, false)
    ok(not panel:IsShown() and not frame.ZoneButton.Selected:IsShown(), "closed")
    panel.CloseButton:RunScript("OnClick")
    eq(ns.db.global.zonePanel.open, false, "its close button closes too")
  end)

  it("zone panel: reopens with the saved state; Collected shows owned mounts", function()
    local ns = loadZoneUI({ zonePanel = { open = true }, filters = { collected = true } })
    ns.ToggleWindow()
    ok(ns.UI.zonePanel:IsShown(), "open after a reload")
    local owned = 0
    for _, row in ipairs(ns.UI.zonePanel.ScrollBox.provider.rows) do if row.owned then owned = owned + 1 end end
    ok(owned > 0, "owned mounts listed with Collected on")
  end)

  it("zone panel: rebuilds on a zone change (only when the map changed) and on ns.Refresh", function()
    local ns, map, computed = loadZoneUI({ zonePanel = { open = true } })
    ns.ToggleWindow()
    local panel = ns.UI.zonePanel
    local n = computed()
    eq(n, 1, "built once when the window opened")
    fire_frame_event("ZONE_CHANGED")
    eq(computed(), n, "same map: nothing to do")
    map.id = 249
    fire_frame_event("ZONE_CHANGED_NEW_AREA")
    eq(computed(), n + 1)
    ok(panel.Title:GetText():find("^Mounts in Uldum"), "new zone")
    for _, row in ipairs(panel.ScrollBox.provider.rows) do
      if not row.header then eq(row.id % 11, 0) end
    end
    ns.Refresh()
    eq(computed(), n + 2, "data refresh rebuilds")
    fire_frame_event("PLAYER_ENTERING_WORLD")
    eq(computed(), n + 2)

    ns.ToggleWindow() -- hide
    map.id = 71
    fire_frame_event("ZONE_CHANGED_NEW_AREA")
    ns.Refresh()
    eq(computed(), n + 2, "hidden: nothing computed")
    ns.ToggleWindow() -- show
    eq(computed(), n + 3, "rebuilt on show")
    ok(panel.Title:GetText():find("^Mounts in Tanaris"))
  end)

  it("zone panel: the window's clamp rect takes the panel in while it is shown", function()
    local ns = loadZoneUI()
    ns.ToggleWindow()
    local frame = ns.UI.frame
    local before = { frame:GetPoint(1) }
    frame.ZoneButton:RunScript("OnClick")
    eq(frame.clampInsets, { 0, 262, 0, 0 }, "260 px panel + 2 px gap on the right")
    eq({ frame:GetPoint(1) }, before, "point re-applied unchanged (re-clamps in game)")
    frame.ZoneButton:RunScript("OnClick")
    eq(frame.clampInsets, { 0, 0, 0, 0 }, "reset when hidden")
    local reopened = loadZoneUI({ zonePanel = { open = true } })
    reopened.ToggleWindow()
    eq(reopened.UI.frame.clampInsets, { 0, 262, 0, 0 }, "saved open: set when built")
  end)

  it("zone panel: moving between sub-zones keeps the list; a refresh there keeps the scroll", function()
    local ns, map, computed = loadZoneUI({ zonePanel = { open = true } })
    ScrollBoxConstants = { RetainScrollPosition = "retain" }
    map.id = 74
    ns.ToggleWindow()
    local panel = ns.UI.zonePanel
    local n = computed()
    map.id = 75
    fire_frame_event("ZONE_CHANGED")
    map.id = 71
    fire_frame_event("ZONE_CHANGED_INDOORS")
    eq(computed(), n, "same zone root: no rebuild")
    ns.Refresh()
    eq(computed(), n + 1)
    eq(panel.ScrollBox.retain, "retain", "same zone: scroll kept")
    map.id = 249
    fire_frame_event("ZONE_CHANGED_NEW_AREA")
    eq(panel.ScrollBox.retain, nil, "new zone: back to the top")
    ScrollBoxConstants = nil
  end)

  it("zone panel: bursts of ns.Refresh rebuild once on the next frame (C_Timer.After(0))", function()
    local ns, _, computed = loadZoneUI({ zonePanel = { open = true } })
    ns.ToggleWindow()
    local n = computed()
    local timers = {}
    C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds, fn } end }
    ns.Refresh(); ns.Refresh(); ns.Refresh()
    eq(computed(), n, "deferred")
    eq(#timers, 1, "coalesced")
    eq(timers[1][1], 0)
    timers[1][2]()
    eq(computed(), n + 1)
    ns.Refresh()
    eq(#timers, 2, "a later burst schedules again")
    C_Timer = nil
  end)

  it("a window hook that errors is reported, not raised", function()
    local ns = loadZoneUI()
    local reported = {}
    ns.Game.ReportError = function(err) reported[#reported + 1] = tostring(err) end
    ns.UI.AddWindowHook(function() error("hook boom") end)
    ns.ToggleWindow()
    ok(ns.UI.frame:IsShown() and ns.UI.zonePanel, "window and panel still built")
    eq(#reported, 1)
    ok(reported[1]:find("hook boom"), reported[1])
    ns.UI.AddWindowHook(function() error("late boom") end)
    eq(#reported, 2, "a hook added after the window is built runs at once, guarded")
  end)

  it("zone panel: empty state line", function()
    local ns, map = loadZoneUI({ zonePanel = { open = true } })
    map.id = 900
    ns.ToggleWindow()
    local panel = ns.UI.zonePanel
    eq(#panel.ScrollBox.provider.rows, 0)
    ok(panel.Empty:IsShown(), "empty line shown")
    eq(panel.Empty:GetText(), "Nothing left to collect here")
    eq(panel.Title:GetText(), "Mounts in Empty Isle  |cff9d9d9d(0)|r")
    map.id = nil
    ns.Refresh()
    eq(panel.Title:GetText(), "Mounts in this zone  |cff9d9d9d(0)|r", "no map known")
  end)

  it("/mtrail zone opens the window with the panel, then toggles the panel; help lists it", function()
    local ns, _, computed = loadZoneUI()
    run_slash(ns.addon, "azt", "zone")
    ok(ns.UI.frame:IsShown(), "window opened")
    ok(ns.UI.zonePanel:IsShown(), "panel opened")
    eq(ns.db.global.zonePanel.open, true)
    eq(computed(), 1, "one build")
    ok(ns.UI.frame.ZoneButton.Selected:IsShown())
    run_slash(ns.addon, "azt", "zone")
    ok(ns.UI.frame:IsShown(), "window stays")
    ok(not ns.UI.zonePanel:IsShown(), "panel closed")
    eq(ns.db.global.zonePanel.open, false)
    run_slash(ns.addon, "azt", "zone")
    ok(ns.UI.zonePanel:IsShown(), "and open again")
    ns.ToggleWindow()
    run_slash(ns.addon, "azt", "zone")
    ok(ns.UI.frame:IsShown() and ns.UI.zonePanel:IsShown(), "window closed: opens both")
    run_slash(ns.addon, "azt", "help")
    local found = false
    for _, line in ipairs(ns.addon.printed) do if line:find("^/mtrail zone") then found = true end end
    ok(found, "help lists /mtrail zone")
  end)

  it("Checklist Filter dropdown: per-character category filters", function()
    local ns = loadUI()
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    local header = content(ns, "checklist").children[2].children[1]
    local dd = header.ChecklistFilter
    ok(dd, "Filter dropdown built")
    eq(dd.template, "WowStyle1FilterDropdownTemplate")
    eq({ dd:GetPoint(1) }, { "TOPRIGHT", header, "TOPRIGHT", -8, -4 }, "top right of the header")
    ok(dd:IsShown(), "shown")
    eq(dd.resetShown, false, "defaults: no reset arrow")
    local calls = openMenu(dd)
    local labels = {}
    for _, c in ipairs(calls) do if c.kind == "checkbox" then labels[#labels + 1] = c.text end end
    eq(labels, { "Show raids", "Show dungeons", "Show world bosses", "Show rares", "Show holidays", "Show other",
      "Show rare spawns (no lockout)", "Show quick lists" })

    local box = header.Checklist.ScrollBox
    local function count(category)
      local n = 0
      for _, r in ipairs(box.provider.rows) do
        if r.entry and r.entry.category == category then n = n + 1 end
      end
      return n
    end
    ok(count("raids") > 0, "raid lockouts listed")
    local weeklyTotal
    for _, r in ipairs(box.provider.rows) do if r.key == "checklist|weekly" then weeklyTotal = r.total end end

    local raids = find(calls, "Show raids")
    eq(raids.isSelected(), true)
    raids.setSelected()
    eq(ns.db.char.checklistFilters.raids, false, "saved per character")
    eq(raids.isSelected(), false)
    eq(count("raids"), 0, "raids gone from the rows")
    local after
    for _, r in ipairs(box.provider.rows) do if r.key == "checklist|weekly" then after = r.total end end
    ok(after < weeklyTotal, "header counts reflect the filter")
    eq(dd.resetShown, true, "reset arrow once a filter differs")

    eq(find(calls, "Uncheck all").fn(), MenuResponse.Refresh, "menu stays open")
    eq(#box.provider.rows, 0, "everything hidden")
    eq(find(calls, "Check all").fn(), MenuResponse.Refresh)
    eq(ns.db.char.checklistFilters, {})
    ns.db.char.checklistFilters.dungeons = false
    dd.defaultCallback()
    eq(ns.db.char.checklistFilters, {}, "reset shows every category")
    eq(dd.resetShown, false)

    -- Without the 11.x menu API /mtrail debug names what the checklist gets instead.
    local saved = STUB_TEMPLATE_METHODS.WowStyle1FilterDropdownTemplate
    ns.UI.TemplateFallbacks["DropdownButton:SetupMenu"] = nil
    STUB_TEMPLATE_METHODS.WowStyle1FilterDropdownTemplate = nil
    local good, none = pcall(ns.UI.ChecklistView.CreateFilterDropdown, header)
    STUB_TEMPLATE_METHODS.WowStyle1FilterDropdownTemplate = saved
    assert(good, none)
    eq(none, nil)
    eq(ns.UI.TemplateFallbacks["DropdownButton:SetupMenu"], "checklist filter (all categories shown)")
  end)

  it("Checklist rare spawns (no lockout): their group, a last-checked box per row, a 60 s ticker", function()
    local tickers = {}
    local oldTimer = C_Timer
    C_Timer = { NewTicker = function(seconds, fn)
      local t = { seconds = seconds, fn = fn }
      function t:Cancel() self.cancelled = true end
      tickers[#tickers + 1] = t
      return t
    end }
    local ns = loadUI()
    ns.Data.Lockouts[614] = { camp = true, zone = "Nagrand" } -- Mottled Meadowstomper (not owned: 614 % 3 ~= 0)
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    local root = content(ns, "checklist").children[2]
    local header = root.children[1]
    local box = header.Checklist.ScrollBox
    local function find(pred)
      for i, r in ipairs(box.provider.rows) do if pred(r) then return i, r end end
    end
    local hi, top = find(function(r) return r.key == "checklist|camp" end)
    ok(hi, "the camp group is listed")
    local frames = render(box)
    local label = frames[hi].Label:GetText()
    ok(label:find("^Rare spawns %(no lockout%)"), label)
    ok(label:find("(" .. top.left .. " left)", 1, true), label)
    ok(not label:find("resets in", 1, true), "no reset timer")
    ok(find(function(r) return r.key == "checklist|camp|Warlords of Draenor|Nagrand" end), "expansion -> zone")

    local ri = find(function(r) return r.entry and r.entry.id == 614 end)
    ok(ri, "the camp row")
    local f = frames[ri]
    ok(f.Check:IsShown() ~= false, "a box on the camp row")
    eq(f.Check.enabled ~= false, true, "enabled")
    ok(not f.Source:GetText():find("Last checked", 1, true), "never checked: no text")
    f.Check:RunScript("OnClick", "LeftButton")
    eq(ns.db.char.campChecked[614], 1700000000)
    ri = find(function(r) return r.entry and r.entry.id == 614 end)
    ok(ri, "still listed: a camp row is never done")
    f = render(box)[ri]
    ok(f.Source:GetText():find("Last checked 1 min ago", 1, true), f.Source:GetText())
    eq(f.Check:GetChecked(), true)
    f.Check:RunScript("OnClick", "RightButton")
    eq(ns.db.char.campChecked[614], nil, "right-click clears")

    -- The ticker: one while the tab is shown, cancelled on hide.
    eq(#tickers, 1)
    eq(tickers[1].seconds, 60)
    tickers[1].fn()
    root:Hide()
    eq(tickers[1].cancelled, true)
    root:Show()
    eq(#tickers, 2, "a new ticker on show")
    C_Timer = oldTimer
  end)

  it("Checklist rows: headers with reset timers and done/total, tick boxes, clicks, collapse, Hide done", function()
    local ns = loadUI()
    ns.Map.HasLocation = function(id) return id % 2 == 0 end
    local got = {}
    ns.UI.HandleRowClick = function(id, button) got[#got + 1] = { id, button } end
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    local header = content(ns, "checklist").children[2].children[1]
    local box = header.Checklist.ScrollBox
    local rows = box.provider.rows
    eq(rows[1].header, true)
    eq(rows[1].key, "checklist|daily")
    local frames = render(box)
    ok(frames[1].Label:GetText():find("^Daily \194\183 resets in "), frames[1].Label:GetText())
    ok(frames[1].Label:GetText():find("(0/" .. rows[1].total .. ")", 1, true), "done/total")
    local weekly
    for i, row in ipairs(rows) do if row.header and row.depth == 1 and row.reset == "weekly" then weekly = i end end
    ok(weekly and weekly > 2, "weekly header after the daily rows")

    -- F12: the daily group opens with an expansion sub-header (smaller, indented).
    eq(rows[2].header, true)
    eq(rows[2].depth, 2)
    ok(rows[2].key:find("^checklist|daily|"), rows[2].key)
    eq(box.view.extent(1, rows[2]), 20, "sub-header height")
    ok(frames[2].Label:GetText():find("(0/" .. rows[2].total .. ")", 1, true), "sub-header done/total")

    -- F14: then a category header (Raids, Dungeons, ...) one step further in.
    eq(rows[3].header, true)
    eq(rows[3].depth, 3)
    ok(rows[3].key:find("^" .. rows[2].key:gsub("%p", "%%%0") .. "|"), rows[3].key)
    ok(rows[3].category, "category header")
    eq(box.view.extent(1, rows[3]), 20, "category header: sub-header height")
    eq({ frames[3].Indicator:GetPoint(1) }, { "LEFT", frames[3], "LEFT", 22 + 16, 0 }, "indented a step further")
    eq(frames[3].Label.font, ns.UI.Font("GameFontNormalSmall"))
    ok(frames[3].Label:GetText():find("(0/" .. rows[3].total .. ")", 1, true), "category done/total")

    -- A row: list look, pin, click, hover. A game-tracked lockout has no
    -- tick box (the game decides); the icon keeps its place either way.
    local f, row = frames[4], rows[4]
    -- F12: hover and pin use the row's boss (the lockout line of that boss).
    local shown = {}
    local oldShow = ns.UI.ShowMountTooltip
    ns.UI.ShowMountTooltip = function(_, id, boss) shown[#shown + 1] = { id, boss } end
    f:RunScript("OnEnter")
    ns.UI.ShowMountTooltip = oldShow
    eq(shown[1], { row.id, row.entry.boss }, "hover names the row's boss")
    eq(row.routeBoss, row.entry.boss)
    ok(not row.entry.spec.manual, "the first daily entry is game-tracked")
    eq(row.depth, 3, "under its category header")
    eq(f.Check:IsShown(), false, "no tick box on a game-tracked lockout")
    eq({ f.Icon:GetPoint(1) }, { "LEFT", f, "LEFT", 6 + 22 + 4 + 32, 0 }, "icon after the tick-box column, indented")
    eq({ f.Check:GetPoint(1) }, { "LEFT", f, "LEFT", 6 + 32, 0 }, "tick-box column indented")
    eq(f.Pin:IsShown(), row.id % 2 == 0)
    ok(f.Source:GetText() ~= "", "grey description line")
    f:RunScript("OnClick", "LeftButton")
    eq(got[1], { row.id, "LeftButton" })

    -- A manual lockout (the game can't report it) has a tick box; ticking it
    -- writes the route's tick key and the entry disappears, counted as done.
    local m
    for i, r in ipairs(rows) do
      if not m and r.entry and r.entry.spec.manual and r.entry.reset == "weekly" then m = i end
    end
    ok(m and m > weekly, "a manual (weekly) entry to tick")
    f, row = frames[m], rows[m]
    ok(f.Check:IsShown() ~= false, "tick box on a manual lockout")
    local key = row.entry.key
    f.Check:RunScript("OnClick")
    ok(ns.db.char.ticks[key], "ticked " .. tostring(key))
    rows = box.provider.rows
    eq(rows[weekly].header, true)
    eq(rows[weekly].owned, 1, "1 done in the weekly group")
    eq(rows[1].owned, 0, "the daily group is untouched")
    for _, r in ipairs(rows) do ok(not (r.entry and r.entry.key == key), "done entry is gone") end

    -- Collapsing the daily header (saved like the list headers).
    frames = render(box)
    frames[1]:RunScript("OnMouseUp", "LeftButton")
    eq(ns.db.global.collapsed["checklist|daily"], true)
    rows = box.provider.rows
    eq(rows[2].header, true, "daily rows hidden")
    eq(rows[2].key, "checklist|weekly")
  end)

  it("Checklist: a lockout that drops several mounts is one row with the group tooltip", function()
    local ns = loadUI()
    -- A synthetic boss whose per-boss spec three route rows share.
    for _, id in ipairs({ 900001, 900002, 900004 }) do
      ns.Data.Mounts[id] = { name = "Hoard " .. id, exp = "Classic" }
    end
    table.insert(ns.Data.Route, 1, { title = "Run Hoard Vault (Raid)", bosses = {
      { mount = 900001, boss = "Grand Hoarder" }, { mount = 900002, boss = "Grand Hoarder" },
      { mount = 900004, boss = "Grand Hoarder" },
    } })
    ns.Data.BossLockouts["Grand Hoarder"] = { instance = 99999, boss = "Grand Hoarder", difficulties = { 16 },
      reset = "weekly", exp = "Dragonflight" }
    local got = {}
    ns.UI.HandleRowClick = function(id, button, boss) got[#got + 1] = { id, button, boss } end
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    local header = content(ns, "checklist").children[2].children[1]
    local box = header.Checklist.ScrollBox
    local rows = box.provider.rows
    local frames = render(box)
    local n, at = 0, nil
    for i, r in ipairs(rows) do
      if r.entry and r.entry.boss == "Grand Hoarder" then n = n + 1; at = i end
    end
    eq(n, 1, "Grand Hoarder: one row")
    local f, row = frames[at], rows[at]
    local e = row.entry
    eq(e.mounts, { 900001, 900002, 900004 })
    eq(e.expRank, 10, "sorted by the spec's expansion (Dragonflight), not the first mount's")
    eq(f.Name:GetText(), "Grand Hoarder", "named after the boss")
    eq(f.Source:GetText(), "Hoard Vault \194\183 3 mounts")
    eq(f.mountID, e.id, "click / waypoint on the first mount")
    f:RunScript("OnClick", "LeftButton")
    eq(got[#got], { 900001, "LeftButton", "Grand Hoarder" }, "the click names the boss (its instance's entrance)")

    local lines, tip = {}, {}
    function tip:SetOwner() end
    function tip:SetText(text) lines[#lines + 1] = text end
    function tip:AddLine(text) lines[#lines + 1] = text end
    function tip:AddDoubleLine(l, r) lines[#lines + 1] = l .. "=" .. r end
    function tip:SetItemByID() end
    function tip:Show() end
    function tip:Hide() end
    local old = GameTooltip
    GameTooltip = tip
    f:RunScript("OnEnter")
    f:RunScript("OnLeave")
    eq(lines[1], "Grand Hoarder")
    eq(lines[3], "Can drop:")

    -- A plain row of the same list keeps the mount tooltip.
    local plain
    for i, r in ipairs(rows) do
      if r.entry and not r.entry.grouped and not plain then plain = i end
    end
    lines = {}
    frames[plain]:RunScript("OnEnter")
    GameTooltip = old
    ok(lines[1] ~= "Can drop:" and lines[3] ~= "Can drop:", "mount tooltip for a single-mount row")
    eq(frames[plain].Name:GetText(), rows[plain].m.name, "single-mount rows keep the mount name")
  end)

  -- F17: event rares' live status on their rows and, when shared, headers.
  it("Checklist: event rares show their zone's assault / warfront status; a header shares it", function()
    local ns = loadUI()
    ns.Game.AreaPOIsForMap = function(map) if map == 1527 then return { 6488 } end return {} end
    ns.Game.AreaPOIInfo = function() return { name = "Assault: Aqir" } end
    ns.Game.AreaPOISecondsLeft = function() return 7200 end
    ns.Game.ContributionsForMap = function() return nil end
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    local box = content(ns, "checklist").children[2].children[1].Checklist.ScrollBox
    local uldum = "Uldum: Aqir assault \226\128\148 " .. ns.UI.FormatDuration(7200) .. " left"
    local frames = render(box)
    local seen = {}
    for i, row in ipairs(box.provider.rows) do
      local group = row.entry and row.entry.m and row.entry.m.group
      if group == "Assault: Uldum" then
        seen.uldum = true
        eq(row.status, uldum)
        ok(frames[i].Source:GetText():find(uldum, 1, true), frames[i].Source:GetText())
      elseif group == "Warfront: Darkshore" then
        seen.darkshore = true
        eq(row.status, "Status unknown — click to load")
      elseif row.entry and not ns.Data.EventGroups[group] then
        eq(row.status, nil, "not an event rare: " .. tostring(group))
      end
    end
    ok(seen.uldum and seen.darkshore, "event rares listed")

    -- Only the Uldum rares left to get: their headers share the line.
    local uldumIDs = { [1314] = true, [1317] = true, [1319] = true }
    ns.Game.IsOwned = function(id) return not uldumIDs[id] end
    ns.Refresh()
    local rares
    for _, row in ipairs(box.provider.rows) do
      if row.header and row.category == "rares" then rares = row end
    end
    ok(rares, "the Rares header")
    eq(rares.status, uldum)
    frames = render(box)
    ok(frames[1].Label:GetText():find(uldum, 1, true), "the header label shows it")
  end)

  it("Checklist tick boxes fall back to the classic checkbox", function()
    local ns = loadUI()
    STUB_TEMPLATES.MinimalCheckboxTemplate = nil
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    local box = content(ns, "checklist").children[2].children[1].Checklist.ScrollBox
    local check
    for _, f in ipairs(render(box)) do if f.Check and not check then check = f.Check end end
    ok(check, "a row with a tick box")
    eq(check.template, "UICheckButtonTemplate")
    eq(ns.UI.TemplateFallbacks.MinimalCheckboxTemplate, "UICheckButtonTemplate")
  end)

  it("Alt lockouts: a column per character, a cell per lockout, hide / show all, /mtrail alts", function()
    local ns = loadUI()
    RAID_CLASS_COLORS = { MAGE = { r = 0.2, g = 0.8, b = 1 } }
    local now = ns.Game.Now()
    ns.db.char.seen = { name = "Tester", class = "MAGE", faction = "Alliance", level = 80,
      at = now, dailyReset = now + 3600, weeklyReset = now + 86400 }
    ns.db.char.last = { snap = {}, quests = {}, lfg = {} }
    ns.db.sv = { char = {
      ["Tester - Realm"] = ns.db.char,
      ["Alt - Realm"] = { seen = { name = "Alt", class = "WARRIOR", faction = "Horde" } },
      ["Never - Realm"] = { last = {} }, -- never stamped: no column
    } }
    ns.db.keys = { char = "Tester - Realm" }
    eq(ns.UI.AltsWidth(1), 380)
    eq(select(2, ns.UI.AltsWidth(40)), 14, "columns past the max width are left off")
    eq(ns.UI.AltsCellHint("Alt", "unknown"), "Alt: no data yet (log in once)")
    run_slash(ns.addon, "mtrail", "alts")
    local w = ns.UI.AltsWindow()
    ok(w and w:IsShown(), "opened")
    eq(w.Title:GetText(), "Alt lockouts")
    ok(w.Resets:GetText():find("Weekly reset in ", 1, true), w.Resets:GetText())
    eq(#w.shownChars, 2)
    eq(w.Columns[1].Text:GetText(), "Tester", "the current character first")
    eq({ ns.UI.AltsColumnColor("MAGE") }, { 0.2, 0.8, 1 }, "class colour")
    eq({ ns.UI.AltsColumnColor("NOPE") }, { 1, 1, 1 })
    eq(w.Columns[2].Text:GetText(), "Alt")
    ok(not w.ShowAll:IsShown(), "nothing hidden")
    local rows = w.ScrollBox.provider.rows
    eq(rows[1].header, true)
    eq(rows[1].key, "alts|weekly")
    local frames = render(w.ScrollBox)
    local seen = {}
    for i, f in ipairs(frames) do
      local data = rows[i]
      if not data.header then
        local c1, c2 = f.Cells[1], f.Cells[2]
        ok(c1:IsShown() and c2:IsShown(), "one cell per character")
        seen[c1.state] = true
        ok(c2.state == "unknown" or c2.state == "na", "the alt has no stored lockouts: " .. tostring(c2.state))
        if c2.state == "na" then eq(c2.Text:GetText(), "-") else eq(c2.Text:GetText(), "?") end
        if c1.state == "open" then ok(c1.Box:IsShown() and not c1.Check:IsShown(), "open: the square") end
      end
    end
    ok(seen.open, "the current character has open lockouts")
    -- Hover a cell: the hint names the character and the state.
    local cell
    for i, f in ipairs(frames) do if not rows[i].header and not cell then cell = f.Cells[2] end end
    cell:RunScript("OnEnter")
    ok(cell.char and cell.char.name == "Alt")
    cell:RunScript("OnLeave")
    -- A header click collapses its group.
    frames[1].Name:RunScript("OnClick", "LeftButton")
    eq(ns.db.global.collapsed["alts|weekly"], true)
    eq(w.ScrollBox.provider.rows[1].collapsed, true)
    -- Right-click a column header: Hide <name>; then Show all.
    local menu
    ns.UI.ShowMenu = function(owner, items) menu = items end
    w.Columns[2]:RunScript("OnClick", "RightButton")
    eq(menu[2].text, "Hide Alt")
    menu[2].onClick()
    eq(ns.db.global.altsHidden["Alt - Realm"], true)
    eq(#w.shownChars, 1)
    ok(not w.Columns[2]:IsShown(), "the hidden column is gone")
    ok(w.ShowAll:IsShown(), "Show all")
    w.ShowAll:RunScript("OnClick", "LeftButton")
    eq(#w.shownChars, 2)
    ok(not w.ShowAll:IsShown())
    -- Closed: the refresh hook leaves it alone; the slash toggles.
    run_slash(ns.addon, "mtrail", "alts")
    ok(not w:IsShown(), "closed")
    -- The navigation column's Alts entry opens it again (the Checklist
    -- header has no Alts button any more).
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    local header = content(ns, "checklist").children[2].children[1]
    eq(header.AltsButton, nil, "no Alts button on the Checklist")
    ns.UI.NavClick({ action = "alts" })
    ok(w:IsShown(), "opened from the navigation")
    run_slash(ns.addon, "mtrail", "help")
    local found = false
    for _, line in ipairs(ns.addon.printed) do if line:find("^/mtrail alts") then found = true end end
    ok(found, "help lists /mtrail alts")
    RAID_CLASS_COLORS = nil
  end)
end)
