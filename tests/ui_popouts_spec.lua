-- Pop-out checklists (UI/Popouts.lua), custom lists in the detail pane and
-- the Checklist, and the flat widgets (UI.ShowMenu / UI.AskText).

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/DetailPane.lua",
  "UI/Tabs.lua", "UI/LockoutHelpers.lua", "UI/ChecklistView.lua", "UI/Popouts.lua", "UI/ZonePanel.lua" }

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

do
  local FrameMT = getmetatable(CreateFrame("Frame"))
  local RegionMT = getmetatable(FrameMT).__index
  for _, name in ipairs({ "SetMaxLines", "EnableMouseWheel", "SetAlpha", "SetMaxLetters", "HighlightText",
    "SetFocus", "Raise" }) do
    RegionMT[name] = RegionMT[name] or function() end
  end
  FrameMT.SetScrollChild = FrameMT.SetScrollChild or function(self, child) self.scrollChild = child end
  FrameMT.SetVerticalScroll = FrameMT.SetVerticalScroll or function(self, v) self.vscroll = v end
  FrameMT.GetVerticalScroll = FrameMT.GetVerticalScroll or function(self) return self.vscroll or 0 end
end

local WOD = "Warlords of Draenor"

local function loadUI()
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  local stubGame = {
    MountInfo = function() return nil end,
    IsOwned = function(id) return id == 7 end,
    Exists = function() return true end,
    Faction = function() return "Alliance" end,
    SavedRows = function() return {} end,
    IsQuestDone = function() return false end,
    IsLfgDone = function() return false end,
    MountSourceText = function() return nil end,
    ActiveHolidays = function() return {} end,
    Now = function() return 1700000000 end,
    UntilDaily = function() return 3600 end,
    UntilWeekly = function() return 86400 end,
    PlayerName = function() return "Tester" end,
    MapName = function(m) return ({ [550] = "Nagrand", [525] = "Frostfire Ridge" })[m] end,
  }
  for k, v in pairs(stubGame) do ns.Game[k] = v end
  ns.Data.Spots = {
    [614] = { { npc = 50981, name = "Luk'hok", kind = "drop", pts = { 550, 67.6, 42.6, 550, 72.8, 53.4 } } },
    [657] = { { npc = 81001, name = "Nok-Karosh", kind = "drop", pts = { 525, 13.1, 50.4 } } },
  }
  ns.Data.SpotsExtra = {}
  return ns
end

-- A Checklist.Build-shaped fixture.
local function built()
  return {
    daily = {
      { key = "614", id = 614, m = { name = "Mottled Meadowstomper", exp = WOD }, exp = WOD, category = "rares", reset = "daily", done = false },
      { key = "9", id = 9, m = { name = "Daily boss mount", exp = WOD }, exp = WOD, category = "worldbosses", reset = "daily", name = "Daily boss mount", done = false },
      { key = "636", id = 636, m = { name = "Swift Breezestrider", exp = WOD }, exp = WOD, category = "rares", reset = "daily", done = true },
    },
    weekly = {
      { key = "10", id = 10, m = { name = "Weekly mount", exp = WOD }, exp = WOD, category = "raids", reset = "weekly", name = "Weekly mount", done = false, boss = "Boss" },
    },
    camp = {
      { key = "657", id = 657, m = { name = "Garn Nighthowl", exp = WOD }, exp = WOD, category = "camp", reset = "camp", zone = "Frostfire Ridge", done = false },
      { key = "1", id = 1, m = { name = "Old rare", exp = "Classic" }, exp = "Classic", category = "camp", reset = "camp", done = false },
    },
  }
end

local function names(rows)
  local out = {}
  for i, r in ipairs(rows) do out[i] = r.name end
  return out
end

describe("pop-out sets", function()
  it("keys and titles", function()
    local ns = loadUI()
    local U = ns.UI
    eq(U.PopoutKey({ kind = "camp", exp = WOD }), "camp|" .. WOD)
    eq(U.PopoutKey({ kind = "daily", exp = WOD, category = "rares" }), "daily|" .. WOD .. "|rares")
    eq(U.PopoutKey({ kind = "zone" }), "zone")
    eq(U.PopoutKey({ kind = "list", list = 3 }), "list|3")
    eq(U.PopoutTitle({ kind = "camp", exp = WOD }), WOD .. " rare spawns")
    eq(U.PopoutTitle({ kind = "daily", exp = WOD }), WOD .. " dailies")
    eq(U.PopoutTitle({ kind = "weekly", exp = WOD }), WOD .. " weeklies")
    eq(U.PopoutTitle({ kind = "daily", exp = WOD, category = "rares" }), WOD .. " dailies \194\183 Rares")
    local store = {}
    local id = ns.Lists.Create(store, "My loop")
    eq(U.PopoutTitle({ kind = "list", list = id }, store), "My loop")
  end)

  it("rows: rare spawns, a reset (all or one category), the zone's rares", function()
    local ns = loadUI()
    local U = ns.UI
    eq(names((U.PopoutRows({ kind = "camp", exp = WOD }, built(), {}))), { "Nok-Karosh" })
    local rows, left = U.PopoutRows({ kind = "daily", exp = WOD }, built(), {})
    eq(names(rows), { "Daily boss mount", "Luk'hok", "Swift Breezestrider" })
    eq(left, 2)
    eq(names((U.PopoutRows({ kind = "daily", exp = WOD, category = "rares" }, built(), {}))), { "Luk'hok", "Swift Breezestrider" })
    eq(names((U.PopoutRows({ kind = "weekly", exp = WOD }, built(), {}))), { "Weekly mount" })
    eq(names((U.PopoutRows({ kind = "zone" }, built(), { zoneIDs = { [657] = true, [9] = true } }))), { "Nok-Karosh" },
      "the zone's rares only")
  end)

  it("a custom list: the Checklist's entry when tracked, else a plain row; mounts already known left out", function()
    local ns = loadUI()
    local store = {}
    local id = ns.Lists.Create(store, "Mine")
    ns.Lists.Add(store, id, 614)
    ns.Lists.Add(store, id, 7)
    ns.Lists.Add(store, id, 8)
    ns.Data.Mounts[7] = { name = "Owned shop mount" }
    ns.Data.Mounts[8] = { name = "Wanted shop mount" }
    local rows, left = ns.UI.PopoutRows({ kind = "list", list = id }, built(), { store = store, isOwned = ns.Game.IsOwned })
    eq(names(rows), { "Mottled Meadowstomper", "Wanted shop mount" }, "the owned shop mount is not listed")
    eq(rows[1].entry.key, "614", "tracked: the Checklist's entry")
    eq(rows[2].listOnly, true)
    eq(left, 2)
  end)
end)

describe("pop-out windows", function()
  local function setup(ns)
    ns.UI.ChecklistBuild = function() return built() end
  end

  it("several open at once, each its own set; closing one leaves the others; saved", function()
    local ns = loadUI()
    setup(ns)
    local camp = ns.UI.OpenPopout({ kind = "camp", exp = WOD })
    local daily = ns.UI.OpenPopout({ kind = "daily", exp = WOD })
    ok(camp ~= daily and camp:IsShown() and daily:IsShown(), "two windows")
    ok(camp.Title:GetText():find("^" .. WOD .. " rare spawns"), camp.Title:GetText())
    ok(daily.Title:GetText():find("(2 left)", 1, true), daily.Title:GetText())
    eq(ns.db.global.popouts["camp|" .. WOD].open, true)
    eq(ns.UI.OpenPopout({ kind = "camp", exp = WOD }), camp, "same set: the same window")
    camp.Close:RunScript("OnClick", "LeftButton")
    ok(not camp:IsShown() and daily:IsShown())
    eq(ns.db.global.popouts["camp|" .. WOD].open, false)
  end)

  it("a row click goes through UI.GoTo with the entry's boss; no pin per row; Plot all at the top", function()
    local ns = loadUI()
    setup(ns)
    local w = ns.UI.OpenPopout({ kind = "weekly", exp = WOD })
    local went = {}
    ns.UI.GoTo = function(id, boss) went[#went + 1] = { id, boss } end
    local row
    for _, c in ipairs(w.Content.children) do if c.data and c.data.id == 10 then row = c end end
    row:RunScript("OnClick", "LeftButton")
    eq(went, { { 10, "Boss" } })
    eq(row.Go, nil, "no pin on rows")
    local plotted
    ns.Map.PlotMounts = function(ids, label) plotted = { table.concat(ids, ","), label } end
    local d = ns.UI.OpenPopout({ kind = "daily", exp = WOD })
    eq(d.PlotAll.Text:GetText(), "Plot all")
    d.PlotAll:RunScript("OnClick", "LeftButton")
    eq(plotted[1], "9,614", "the open rows")
    eq(plotted[2], WOD .. " dailies")
    local daily = ns.UI.OpenPopout({ kind = "daily", exp = WOD, category = "rares" })
    for _, c in ipairs(daily.Content.children) do
      ok(not (c.Text and c.m), "no coordinate buttons")
    end
    local camp = ns.UI.OpenPopout({ kind = "camp", exp = WOD })
    local nok
    for _, c in ipairs(camp.Content.children) do if c.data and c.data.id == 657 then nok = c end end
    nok.Check:RunScript("OnClick", "LeftButton")
    eq(ns.db.char.campChecked["657"], 1700000000)
  end)

  it("Plot all skips ticked rows (done, or a rare spawn marked checked); Ctrl-click x closes every pop-out", function()
    local ns = loadUI()
    setup(ns)
    local w = ns.UI.OpenPopout({ kind = "camp", exp = WOD })
    local daily = ns.UI.OpenPopout({ kind = "daily", exp = WOD })
    local plotted
    ns.Map.PlotMounts = function(ids) plotted = table.concat(ids, ",") end
    w.PlotAll:RunScript("OnClick", "LeftButton")
    eq(plotted, "657")
    ns.db.char.campChecked = { ["657"] = 1699990000 }
    ns.Refresh()
    plotted = nil
    w.PlotAll:RunScript("OnClick", "LeftButton")
    eq(plotted, "", "the checked rare is left out")
    eq(ns.UI.PopoutPlotIDs({ { id = 1 }, { id = 2, done = true }, { id = 3, camp = true, checked = 5 }, { id = 4, camp = true } }),
      { 1, 4 })
    IsControlKeyDown = function() return true end
    w.Close:RunScript("OnClick", "LeftButton")
    IsControlKeyDown = nil
    ok(not w:IsShown() and not daily:IsShown(), "all closed")
    eq(ns.db.global.popouts["daily|" .. WOD].open, false)
  end)

  it("a list's window: right-click a row to take it off; a deleted list's window closes", function()
    local ns = loadUI()
    setup(ns)
    local store = ns.UI.ListsDB()
    local id = ns.Lists.Create(store, "Loop")
    ns.Lists.Add(store, id, 614)
    local w = ns.UI.OpenPopout({ kind = "list", list = id })
    eq(#w.rows, 1)
    local row
    for _, c in ipairs(w.Content.children) do if c.data and c.data.id == 614 then row = c end end
    row:RunScript("OnClick", "RightButton")
    local menu = _G.AzerothTrailMenu
    ok(menu and menu:IsShown(), "flat menu")
    local remove
    for _, it in ipairs(menu.items) do
      if it:IsShown() and it.data and it.data.text == "Remove from Loop" then remove = it end
    end
    remove:RunScript("OnClick", "LeftButton")
    eq(ns.Lists.Get(store, id).mounts, {})
    ok(not menu:IsShown(), "menu closed after the click")
    ns.Lists.Delete(store, id)
    ns.UI.RefreshPopouts()
    ok(not w:IsShown(), "deleted list: window closed")
  end)

  it("snapping: under, above, beside another window, aligning the edge when close; nothing when far", function()
    local ns = loadUI()
    local S = ns.UI.SnapRect
    local other = { left = 100, top = 500, right = 380, bottom = 400 }
    -- 280 x 100 window dropped 10 px under the other, 8 px to the right.
    eq({ S({ left = 108, top = 390, right = 388, bottom = 290 }, { other }) }, { 100, 400 }, "under, left edges aligned")
    eq({ S({ left = 108, top = 610, right = 388, bottom = 510 }, { other }) }, { 100, 600 }, "above")
    eq({ S({ left = 390, top = 505, right = 670, bottom = 405 }, { other }) }, { 380, 500 }, "right of it, tops aligned")
    eq({ S({ left = -170, top = 450, right = 110, bottom = 350 }, { other }) }, { -180, 450 }, "left of it, tops far apart: kept")
    eq(S({ left = 600, top = 200, right = 880, bottom = 100 }, { other }), nil, "far away")
    eq({ S({ left = 300, top = 392, right = 580, bottom = 292 }, { other }) }, { 300, 400 }, "under, edges apart: left kept")
  end)

  it("resize grip: saved size kept (no auto-fit); right-click fits the rows again", function()
    local ns = loadUI()
    setup(ns)
    local w = ns.UI.OpenPopout({ kind = "camp", exp = WOD })
    ok(w.resizable, "resizable")
    w.left, w.top = 100, 600
    w.Grip:RunScript("OnMouseDown", "LeftButton")
    w.width, w.height = 420, 300
    w.Grip:RunScript("OnMouseUp", "LeftButton")
    local st = ns.db.global.popouts["camp|" .. WOD]
    eq({ st.width, st.height }, { 420, 300 })
    ns.UI.RefreshPopouts()
    eq(w.height, 300, "kept, not fitted")
    w.Grip:RunScript("OnClick", "RightButton")
    eq({ st.width, st.height }, { nil, nil })
    ok(w.height ~= 300, "fitted again")
  end)

  it("saved order: named rows first in that order, done rows last; MoveKey", function()
    local ns = loadUI()
    local U = ns.UI
    local rows = { { key = "a" }, { key = "b" }, { key = "c", done = true }, { key = "d" } }
    U.ApplyOrder(rows, { "d", "c", "a" })
    local keys = {}
    for i, r in ipairs(rows) do keys[i] = r.key end
    eq(keys, { "d", "a", "b", "c" })
    eq(U.MoveKey({ "a", "b", "c" }, "c", 1), { "c", "a", "b" })
    eq(U.MoveKey({ "a", "b", "c" }, "a", 3), { "b", "c", "a" })
    eq(U.MoveKey({ "a", "b", "c" }, "a", 99), { "b", "c", "a" })
  end)

  it("Alt-drag a row to a new place: saved per window; a plain drag does nothing", function()
    local ns = loadUI()
    setup(ns)
    local w = ns.UI.OpenPopout({ kind = "daily", exp = WOD })
    local function order()
      local keys = {}
      for _, r in ipairs(w.rows) do if not r.done then keys[#keys + 1] = r.key end end
      return keys
    end
    eq(order(), { "9", "614" })
    local rowLuk
    for _, c in ipairs(w.Content.children) do if c.data and c.data.key == "614" then rowLuk = c end end
    rowLuk:RunScript("OnDragStart")
    eq(w.dragKey, nil, "no Alt: no drag")
    IsAltKeyDown = function() return true end
    rowLuk:RunScript("OnDragStart")
    eq(w.dragKey, "614")
    ok(w.DropLine:IsShown(), "drop line")
    w.Content.top = 500
    STUB_CURSOR[1], STUB_CURSOR[2] = 50, 498 -- over the first slot
    w:RunScript("OnUpdate")
    eq(w.dropAt, 1)
    rowLuk:RunScript("OnDragStop")
    IsAltKeyDown = nil
    STUB_CURSOR[1], STUB_CURSOR[2] = 0, 0
    eq(ns.db.global.popouts["daily|" .. WOD].order, { "614", "9" })
    eq(order(), { "614", "9" }, "the window follows the saved order")
    ok(not w.DropLine:IsShown())
    local went
    ns.UI.GoTo = function(id) went = id end
    rowLuk:RunScript("OnClick", "LeftButton")
    eq(went, nil, "the click that ends a drag is not a waypoint")
  end)

  it("each row shows its expansion's tag", function()
    local ns = loadUI()
    setup(ns)
    local w = ns.UI.OpenPopout({ kind = "camp", exp = WOD })
    local row
    for _, c in ipairs(w.Content.children) do if c.data and c.data.id == 657 then row = c end end
    ok(row.Badge:IsShown())
    eq(row.Badge.Text:GetText(), "WOD")
    eq(row.Badge.exp, WOD)
  end)

  it("open windows come back after /reload", function()
    local ns = loadUI()
    setup(ns)
    ns.db.global.popouts = {
      ["camp|" .. WOD] = { open = true, source = { kind = "camp", exp = WOD } },
      ["zone"] = { open = true, source = { kind = "zone" } },
      ["daily|Legion"] = { open = false, source = { kind = "daily", exp = "Legion" } },
    }
    fire_frame_event("PLAYER_LOGIN")
    local W = ns.UI.PopoutWindows
    ok(W["camp|" .. WOD] and W["camp|" .. WOD]:IsShown())
    ok(W.zone and W.zone:IsShown())
    eq(W["daily|Legion"], nil, "closed ones stay closed")
  end)
end)

describe("flat widgets", function()
  it("menu: titles, boxes, keepOpen repaints, disabled items, a click elsewhere closes", function()
    local ns = loadUI()
    local owner = CreateFrame("Button", nil, UIParent)
    local clicked = 0
    local state = false
    local function items()
      return {
        { title = "Add to list" },
        { text = "Loop", checked = state, keepOpen = true, onClick = function() state = not state; clicked = clicked + 1 end },
        { separator = true },
        { text = "Disabled", disabled = true, onClick = function() clicked = 100 end },
      }
    end
    local menu = ns.UI.ShowMenu(owner, items())
    ok(menu:IsShown())
    eq(menu.items[1].Label:GetText(), "Add to list")
    ok(menu.items[2].Box:IsShown(), "box for a toggle item")
    menu.items[2]:RunScript("OnClick", "LeftButton")
    eq(clicked, 1)
    ok(menu:IsShown(), "keepOpen")
    menu.items[4]:RunScript("OnClick", "LeftButton")
    eq(clicked, 1, "disabled does nothing")
    _G.AzerothTrailMenuCatcher:RunScript("OnClick", "LeftButton")
    ok(not menu:IsShown(), "a click elsewhere closes")
  end)

  it("name prompt: Enter accepts the trimmed text, empty is ignored, Cancel closes", function()
    local ns = loadUI()
    local got
    local p = ns.UI.AskText("Name", "  Loop  ", function(t) got = t end)
    ok(p:IsShown())
    p.Edit:RunScript("OnEnterPressed")
    eq(got, "Loop")
    ok(not p:IsShown())
    got = nil
    ns.UI.AskText("Name", "   ", function(t) got = t end)
    p.OK:RunScript("OnClick", "LeftButton")
    eq(got, nil)
    ns.UI.AskText("Name", "x", function(t) got = t end)
    p.Cancel:RunScript("OnClick", "LeftButton")
    eq(got, nil)
  end)
end)

describe("custom lists in the pane and the Checklist", function()
  it("+ List: each list toggled in place; New list... creates one with the mount on it", function()
    local ns = loadUI()
    local store = ns.UI.ListsDB()
    local id = ns.Lists.Create(store, "Loop")
    local owner = CreateFrame("Button", nil, UIParent)
    ns.UI.ShowListMenu(owner, 614)
    local menu = _G.AzerothTrailMenu
    eq(menu.items[2].data.text, "Loop")
    eq(menu.items[2].data.checked, false)
    menu.items[2]:RunScript("OnClick", "LeftButton")
    eq(ns.Lists.Has(store, id, 614), true)
    ok(menu:IsShown(), "stays open")
    eq(menu.items[2].data.checked, true, "repainted")
    local newItem
    for _, it in ipairs(menu.items) do if it:IsShown() and it.data.text == "New list..." then newItem = it end end
    newItem:RunScript("OnClick", "LeftButton")
    local p = _G.AzerothTrailPrompt
    ok(p:IsShown(), "asks for a name")
    p.Edit:SetText("Tanaan")
    p.Edit:RunScript("OnEnterPressed")
    local sorted = ns.Lists.Sorted(store)
    eq(#sorted, 2)
    eq(sorted[2].name, "Tanaan")
    eq(ns.Lists.Get(store, sorted[2].id).mounts, { 614 })
  end)

  it("Checklist: My lists chip; a list's header right-click pops it out", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local store = ns.UI.ListsDB()
    local id = ns.Lists.Create(store, "Loop")
    ns.Lists.Add(store, id, 614)
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    ns.db.char.checklistShow = "lists"
    ns.Refresh()
    local root
    for _, c in ipairs(ns.UI.frame.Contents.checklist.children) do if c.Detail then root = c end end
    local header
    for _, c in ipairs(root.children) do if c.Chips then header = c end end
    local all = header.Checklist.ScrollBox.provider.rows
    eq(all[1].text, "Quick lists", "quick lists first")
    eq(all[2].text, "Mythic Mounts")
    eq(all[2].popout, { kind = "quick", key = "mythic" }, "right-click pops it out")
    local rows
    for i, r in ipairs(all) do
      if r.listsRoot then rows = { unpack(all, i) } end
    end
    eq(rows[1].text, "My lists")
    eq(rows[2].text, "Loop")
    eq(rows[2].listID, id)
    eq(rows[3].id, 614)
    local opened
    ns.UI.OpenPopout = function(source) opened = source end
    local f = CreateFrame("Frame", nil, UIParent)
    header.Checklist.ScrollBox.view.factory(function(kind, init) init(f, rows[2]) end, rows[2])
    f:RunScript("OnMouseUp", "RightButton")
    local menu = _G.AzerothTrailMenu
    local pop
    for _, it in ipairs(menu.items) do if it:IsShown() and it.data.text == "Pop out" then pop = it end end
    pop:RunScript("OnClick", "LeftButton")
    eq(opened, { kind = "list", list = id })
  end)

  it("deleting a list asks for its name; Delete only works once it is typed", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local store = ns.UI.ListsDB()
    local id = ns.Lists.Create(store, "WoD loop")
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    ns.db.char.checklistShow = "lists"
    ns.Refresh()
    local root
    for _, c in ipairs(ns.UI.frame.Contents.checklist.children) do if c.Detail then root = c end end
    local header
    for _, c in ipairs(root.children) do if c.Chips then header = c end end
    local listRow
    for _, r in ipairs(header.Checklist.ScrollBox.provider.rows) do if r.listID == id then listRow = r end end
    local f = CreateFrame("Frame", nil, UIParent)
    header.Checklist.ScrollBox.view.factory(function(kind, init) init(f, listRow) end, listRow)
    f:RunScript("OnMouseUp", "RightButton")
    local menu = _G.AzerothTrailMenu
    local del
    for _, it in ipairs(menu.items) do if it:IsShown() and it.data.text == "Delete..." then del = it end end
    del:RunScript("OnClick", "LeftButton")
    local p = _G.AzerothTrailPrompt
    ok(p:IsShown(), "prompt")
    eq(p.Title:GetText(), "Delete WoD loop?")
    eq(p.Hint:GetText(), "Type WoD loop to confirm. This can't be undone.")
    eq(p.OK.Text:GetText(), "Delete")
    eq(p.OK.enabled, false, "greyed out while empty")
    p.Edit:SetText("WoD")
    p.Edit:RunScript("OnTextChanged")
    eq(p.OK.enabled, false)
    p.Edit:RunScript("OnEnterPressed")
    ok(p:IsShown(), "Enter does nothing until it matches")
    ok(ns.Lists.Get(store, id), "still there")
    p.Edit:SetText("  wod LOOP ")
    p.Edit:RunScript("OnTextChanged")
    eq(p.OK.enabled, true, "trimmed, any case")
    p.OK:RunScript("OnClick", "LeftButton")
    eq(ns.Lists.Get(store, id), nil, "deleted")
    ok(not p:IsShown())
    -- A plain prompt (no match) works as before.
    local got
    ns.UI.AskText("Name", "x", function(t) got = t end)
    eq(p.OK.enabled, true)
    eq(p.OK.Text:GetText(), "OK")
    ok(not p.Hint:IsShown())
    p.OK:RunScript("OnClick", "LeftButton")
    eq(got, "x")
  end)
end)
