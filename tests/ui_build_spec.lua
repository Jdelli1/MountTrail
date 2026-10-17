-- Builds the restyled views (journal home and list, Holidays, Achievements,
-- Timewalking, Misc, Route)
-- under the widget stub, plus the extra widget methods and ScrollBox / menu
-- stand-ins below, so the widget code runs instead of being compile-checked
-- only. Checks the Filter dropdown wiring (menu content, writes to
-- ns.db.global.filters, reset arrow) and its checkbox-panel fallback.
-- UI/Arrow.lua is not loaded.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/JournalHome.lua",
  "UI/Tabs.lua", "UI/RouteView.lua" }

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
    eq(#home.children, #ns.Data.Expansions)
    local card = home.children[1]
    ok(card.Edge and #card.Edge.edges == 4, "flat 1 px edge")
    eq(card.Logo.texture, 123, "logo from the client")
    ok(card.Logo:IsShown() and not card.Name:IsShown(), "logo instead of the name")
    eq(card.Logo:GetPoint(1), "CENTER", "logo centred")
    eq(card.Bar.height, 6, "slim bar")
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
        ok(f.Name.font == "GameFontNormal" or f.Name.font == "GameFontDisable", "GameFont family")
      end
    end
    ok(sawStripe and sawPlain, "every other row striped")
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

    local raid = find(calls, "Raid drops")
    eq(raid.isSelected(), true)
    raid.setSelected()
    eq(ns.db.global.filters.raid, false)
    eq(raid.isSelected(), false, "checkbox reads the live filters")
    eq(refreshed, 1)
    eq(dd.resetShown, true, "reset arrow once a filter differs")

    find(calls, "Collected").setSelected()
    eq(ns.db.global.filters.collected, true)

    eq(find(calls, "Uncheck all").fn(), MenuResponse.Refresh, "menu stays open")
    eq(ns.db.global.filters.dungeon, false)
    eq(find(calls, "Check all").fn(), MenuResponse.Refresh)
    eq(ns.db.global.filters.dungeon, true)
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
    ok(find(calls, "Raid drops"), "sources listed")
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
    eq(#openMenu(list.FilterDropdown), 1, "Collected only on Misc")
  end)

  it("source lines use the dimmed highlight font", function()
    local ns = loadUI()
    local list = openJournalList(ns)
    local frames = render(list.ScrollBox)
    local row
    for _, f in ipairs(frames) do if f.Source then row = f; break end end
    eq(row.Source.template, "AzerothTrailFontSource")
    eq(AzerothTrailFontSource.base, GameFontHighlightSmall)
    eq(AzerothTrailFontSource.color, { 0.7, 0.7, 0.7 })
  end)

  it("falls back to the checkbox panel without the dropdown template", function()
    local ns = loadUI({ filters = { collected = true, raid = false } })
    STUB_TEMPLATES.WowStyle1FilterDropdownTemplate = nil
    local list = openJournalList(ns)
    eq(list.FilterDropdown, nil)
    ok(list.FilterPanel, "checkbox panel")
    eq(list.SearchBox:GetParent(), list.FilterPanel)
    eq(#list.SectionChecks, 10)
    eq(list.CollectedCheck.checked, true)
    eq(list.SectionChecks[2].checked, false, "raid unticked")
    eq({ list.ScrollBox:GetPoint(1) }, { "TOPLEFT", list.FilterPanel, "TOPRIGHT", 4, 0 })
    list.SectionChecks[2].checked = true
    list.SectionChecks[2]:RunScript("OnClick")
    eq(ns.db.global.filters.raid, true)
    eq(ns.UI.TemplateFallbacks.WowStyle1FilterDropdownTemplate, false)
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
    eq(ns.UI.TemplateFallbacks["DropdownButton:SetupMenu"], "checkbox panel", "listed by /azt debug")
    eq(ns.UI.TemplateFallbacks.WowStyle1FilterDropdownTemplate, nil, "the template itself was there")
    run_slash(ns.addon, "azt", "debug")
    eq(ns.addon.printed[#ns.addon.printed], "Template DropdownButton:SetupMenu missing, using checkbox panel")
  end)

  it("Holidays, Achievements, Timewalking and Misc build their lists with a Collected-only menu", function()
    local ns = loadUI()
    ns.ToggleWindow()
    for i, key in ipairs({ "holidays", "achievements", "timewalking", "misc" }) do
      ns.UI.SelectTab(key)
      local list = content(ns, key).children[2]
      ok(list and list.FilterDropdown, key .. ": dropdown")
      eq(list.tab, key, key .. ": the list knows its view")
      local calls = openMenu(list.FilterDropdown)
      eq(#calls, 1, key .. ": Collected only")
      render(list.ScrollBox)
    end
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
    local allowed = { profession = 1, shop = 2, tradingpost = 3, other = 4 }
    for _, row in ipairs(mounts) do eq(Journal.ViewOf(row.m), "misc", "misc row " .. row.id) end
    last = 0
    for _, h in ipairs(headers) do
      ok(allowed[h.section] and allowed[h.section] > last, "misc header " .. tostring(h.section))
      last = allowed[h.section]
    end
  end)

  it("Route builds a flat header, a two-segment mode control and striped rows", function()
    local ns = loadUI()
    ns.ToggleWindow()
    ns.UI.SelectTab("route")
    local arrowMode = "list"
    ns.Arrow = {
      Mode = function() return arrowMode end,
      SetMode = function(_, mode) arrowMode = mode; return mode end,
    }
    local root = content(ns, "route").children[2]
    local header = root.children[1]
    eq(header.ShowCompleted.template, "MinimalCheckboxTemplate")
    eq(header.Name:GetText(), "Tester")
    eq(header.ListMode.Label.font, "GameFontNormalSmall", "List selected")
    eq(header.ArrowMode.Label.font, "GameFontDisableSmall")
    eq(header.ListMode.Bg.color, { 1, 0.82, 0, 0.22 })
    eq(header.ModeControl.width, 60 * 2 + 3, "1 px frame, two segments, 1 px divider")
    eq(header.ModeControl.height, 22)
    eq({ header.ListMode:GetPoint(1) }, { "TOPLEFT", header.ModeControl, "TOPLEFT", 1, -1 }, "inset 1 px")
    eq({ header.ArrowMode:GetPoint(1) }, { "TOPRIGHT", header.ModeControl, "TOPRIGHT", -1, -1 })
    header.ArrowMode:RunScript("OnClick")
    eq(arrowMode, "arrow")
    eq(header.ArrowMode.Label.font, "GameFontNormalSmall", "Arrow segment selected")
    eq(header.ArrowMode.Bg.color, { 1, 0.82, 0, 0.22 })
    eq(header.ListMode.Label.font, "GameFontDisableSmall")
    header.ListMode:RunScript("OnClick")
    eq(header.ListMode.Label.font, "GameFontNormalSmall", "back to List")
    header.ShowCompleted.checked = true
    header.ShowCompleted:RunScript("OnClick")
    eq(ns.db.char.showCompleted, true)
    local box
    for _, child in ipairs(root.children) do if child.view then box = child end end
    local frames = render(box)
    ok(#frames > 10, "route rows rendered")
    local striped = 0
    for _, f in ipairs(frames) do
      if f.Stripe:IsShown() then striped = striped + 1 end
      ok(f.Title.font == "GameFontNormal" or f.Title.font == "GameFontDisable", "GameFont family")
    end
    eq(striped, math.floor(#frames / 2), "every other row striped")
  end)

  it("mount rows (lists and Route) take left and right clicks and dispatch through HandleRowClick", function()
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

    ns.UI.SelectTab("route")
    local root = content(ns, "route").children[2]
    local box
    for _, child in ipairs(root.children) do if child.view then box = child end end
    local routeRow
    for _, f in ipairs(render(box)) do
      if f.clickButtons and not routeRow then routeRow = f end
    end
    ok(routeRow, "route row rendered")
    eq(routeRow.clickButtons, { "LeftButtonUp", "RightButtonUp" })
    routeRow:RunScript("OnClick", "RightButton")
    eq(got[2][2], "RightButton")
    ok(got[2][1] ~= nil, "route row passes its first mount")
  end)

  it("mount rows have no Map button and show a pin only where Map.Resolve finds a location (once per refresh)", function()
    local ns = loadUI()
    local asked = {}
    ns.Map.Resolve = function(id)
      asked[id] = (asked[id] or 0) + 1
      if id % 2 == 0 then return { map = 1, x = 1, y = 2, kind = "pin" } end
      if id % 5 == 0 then return { map = 1, kind = "open" } end
      return { kind = "none" }
    end
    local list = openJournalList(ns)
    for id, n in pairs(asked) do eq(n, 1, "Resolve once for " .. id) end
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
    for id in pairs(asked) do asked[id] = 0 end
    list:Refresh()
    for id, n in pairs(asked) do ok(n <= 1, "Resolve at most once per refresh for " .. id) end

    -- The pin is the map-pin atlas when the client has it.
    STUB_ATLASES["Waypoint-MapPin-ChatIcon"] = true
    local f
    for i, row in ipairs(rows) do if not row.header and row.id % 2 == 0 and not f then f = render(list.ScrollBox)[i] end end
    eq(f.Pin.atlas, "Waypoint-MapPin-ChatIcon")
  end)

  it("route rows: pin and click target the first boss not done", function()
    local ns = loadUI()
    ns.Map.Resolve = function() return { map = 1, x = 1, y = 2, kind = "pin" } end
    local got = {}
    ns.UI.HandleRowClick = function(id, button) got[#got + 1] = { id, button } end
    ns.ToggleWindow()
    ns.UI.SelectTab("route")
    local root = content(ns, "route").children[2]
    local box
    for _, child in ipairs(root.children) do if child.view then box = child end end
    local rows = box.provider.rows
    local frames = render(box)
    local kills = 0
    for i, row in ipairs(rows) do
      local f = frames[i]
      eq(f.Map, nil, "no Map button")
      if row.kind == "kill" and ns.UI.RouteTargetMount(row) then
        kills = kills + 1
        ok(f.Pin:IsShown(), "kill row pin")
      else
        ok(not f.Pin:IsShown(), "travel row: no pin")
      end
    end
    ok(kills > 0, "kill rows rendered")
    -- A row whose first boss is done targets the next one.
    local data = { kind = "kill", title = "Run X", bosses = { { mount = 11, state = "done" }, { mount = 22, state = "open" } } }
    local f = frames[1]
    box.view.factory(function(_, init) init(f, data) end, data)
    f:RunScript("OnClick", "LeftButton")
    eq(got[#got], { 22, "LeftButton" })
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
    eq(top.Label.font, "GameFontNormal")
    eq(sub.Label.font, "GameFontNormalSmall")
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

  it("Route falls back to the classic checkbox", function()
    local ns = loadUI()
    STUB_TEMPLATES.MinimalCheckboxTemplate = nil
    ns.ToggleWindow()
    ns.UI.SelectTab("route")
    local header = content(ns, "route").children[2].children[1]
    eq(header.ShowCompleted.template, "UICheckButtonTemplate")
    eq(ns.UI.TemplateFallbacks.MinimalCheckboxTemplate, "UICheckButtonTemplate")
  end)
end)
