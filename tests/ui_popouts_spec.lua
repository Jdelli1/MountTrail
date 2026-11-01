-- Pop-out checklists (UI/Popouts.lua): expansion groups, appearance,
-- snapped stacks; custom lists in the detail pane and the Checklist, and the
-- flat widgets (UI.ShowMenu / UI.AskText).

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/DetailPane.lua",
  "UI/Tabs.lua", "UI/LockoutHelpers.lua", "UI/ChecklistView.lua", "UI/AltsWindow.lua", "UI/Popouts.lua",
  "UI/ZonePanel.lua" }

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
-- Fonts: a font object resets the font; SetFont / GetFont / the text
-- colour are recorded (pop-out appearance).
function RegionMT:SetFontObject(font) self.font = font; self.fontPath, self.fontSize = nil, nil end
function RegionMT:GetFont() return self.fontPath or "Fonts\\FRIZQT__.TTF", self.fontSize or 10, "" end
function RegionMT:SetFont(path, size) self.fontPath, self.fontSize = path, size end
function RegionMT:SetTextColor(r, g, b) self.textColor = { r, g, b } end
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
-- Slider (the menu's sliders): range, step and value recorded; SetValue clamps
-- and fires OnValueChanged on a change, as the client does.
function FrameMT:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function FrameMT:GetMinMaxValues() return self.min, self.max end
function FrameMT:SetValueStep(step) self.step = step end
function FrameMT:GetValueStep() return self.step or 1 end
function FrameMT:SetObeyStepOnDrag(on) self.obeyStep = on end
function FrameMT:SetOrientation(o) self.orientation = o end
function FrameMT:SetValue(v)
  if self.min and self.max then v = math.max(self.min, math.min(self.max, v)) end
  if v == self.value then return end
  self.value = v
  if self.scripts.OnValueChanged then self.scripts.OnValueChanged(self, v) end
end
function FrameMT:GetValue() return self.value or 0 end
function FrameMT:SetThumbTexture(asset)
  self.thumb = self:CreateTexture(nil, "OVERLAY")
  self.thumb.texture = asset
end
function FrameMT:GetThumbTexture() return self.thumb end

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
  -- Start with no lists (OnInitialize gives the example Mythic Mounts list).
  ns.db.global.lists = {}
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
    local menu = _G.MountTrailMenu
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

  it("Compact: each row shows its expansion's tag", function()
    local ns = loadUI()
    setup(ns)
    ns.db.global.popoutStyle = { layout = "compact" }
    local w = ns.UI.OpenPopout({ kind = "camp", exp = WOD })
    local row
    for _, c in ipairs(w.Content.children) do if c.data and c.data.id == 657 then row = c end end
    eq(w.layout, "compact")
    ok(row.Badge:IsShown())
    eq(row.Badge.Text:GetText(), "WOD")
    eq(row.Badge.exp, WOD)
    ok(not row.Icon:IsShown() and row.Zone:IsShown(), "one line: no icon, the zone on the right")
  end)

  it("Cards (the default): the mount's icon, a second line, the status; each group a card", function()
    local ns = loadUI()
    setup(ns)
    local savedInfo = ns.Game.MountInfo
    ns.Game.MountInfo = function(id) return "Mount " .. id, 5000 + id end
    local w = ns.UI.OpenPopout({ kind = "camp", exp = WOD })
    eq(w.layout, "cards")
    local row
    for _, c in ipairs(w.Content.children) do if c.data and c.data.id == 657 then row = c end end
    ok(row.Icon:IsShown(), "the icon")
    eq(row.Icon.texture, 5657)
    ok(not row.Badge:IsShown(), "no expansion tag")
    ok(row.Sub:IsShown() and not row.Zone:IsShown(), "the place on the second line")
    ok(row.Check:IsShown(), "a rare spawn keeps its box")
    ok(w.rowHeight >= 34, "two lines tall")
    ok(w.cards and w.cards[1] and w.cards[1].Fill:IsShown(), "the group's card")
    -- The appearance menu switches the window to Compact and back.
    local items = ns.UI.PopoutStyleMenu(w)()
    local function item(text) for _, it in ipairs(items) do if it.text == text then return it end end end
    ok(item("Cards").checked and not item("Compact").checked)
    item("Compact").onClick()
    eq(w.layout, "compact")
    ok(not w.cards[1].Fill:IsShown(), "no cards in Compact")
    items = ns.UI.PopoutStyleMenu(w)()
    item("Cards").onClick()
    eq(w.layout, "cards")
    ns.Game.MountInfo = savedInfo
  end)

  it("PopoutCardLines: the second line and the status of a card row", function()
    local ns = loadUI()
    local CL = ns.UI.PopoutCardLines
    eq({ CL({ name = "Luk'hok", camp = true, entry = {} }, "Nagrand", "Great Greytusk") },
      { "Great Greytusk · Nagrand" }, "a rare: the mount under its name, no status (its box)")
    eq({ CL({ name = "Invincible", entry = { boss = "The Lich King" } }, "Icecrown Citadel", "Invincible") },
      { "The Lich King · Icecrown Citadel", "Open", "open" })
    eq({ CL({ name = "Invincible", done = true, entry = {} }, nil, "Invincible") }, { "", "Done", "done" })
    eq({ CL({ name = "X", listOnly = true, entry = { m = { chance = 100 } } }, "Zone", "X") },
      { "Zone", "1 in 100", "info" }, "a plain list mount: its drop chance")
    eq({ CL({ name = "X", listOnly = true, entry = {} }, "", "X") }, { "" })
  end)

  it("groups rows by expansion on ready-made sets, never on the player's own lists", function()
    local ns = loadUI()
    local U = ns.UI
    local rows = {
      { key = "a", entry = { exp = WOD } }, { key = "b", entry = { m = { exp = "Classic" } }, done = true },
      { key = "c", entry = {} }, { key = "d", entry = { exp = WOD } },
    }
    local g = U.PopoutGroups(rows, { kind = "quick", key = "mythic" })
    eq(#g, 3)
    eq({ g[1].exp, g[2].exp }, { "Classic", WOD }, "expansion order")
    eq(g[3].exp, nil, "no expansion last")
    eq({ #g[1].rows, g[1].left, #g[2].rows, g[2].left }, { 1, 0, 2, 2 })
    eq({ g[2].rows[1].key, g[2].rows[2].key }, { "a", "d" }, "the given order within a group")
    local one = U.PopoutGroups(rows, { kind = "list", list = 1 })
    eq(#one, 1)
    eq(one[1].exp, nil)
    eq({ #one[1].rows, one[1].left }, { 4, 3 })
    eq(#U.PopoutGroups({ rows[1], rows[4] }, { kind = "zone" }), 1, "one expansion: no groups")
  end)

  it("a quick list shows expansion headers; the player's own list keeps its rows as they are", function()
    local ns = loadUI()
    setup(ns)
    ns.QuickLists.Mounts = function() return { 614, 1 } end
    local q = ns.UI.OpenPopout({ kind = "quick", key = "mythic" })
    local heads = {}
    for _, h in ipairs(q.groupFrames) do if h:IsShown() then heads[#heads + 1] = h.Text:GetText() end end
    eq(#heads, 2)
    ok(heads[1]:find("^%- Classic"), heads[1])
    ok(heads[2]:find("^%- " .. WOD), heads[2])
    eq({ q.rows[1].id, q.rows[2].id }, { 1, 614 })
    local store = ns.UI.ListsDB()
    local id = ns.Lists.Create(store, "Mine")
    ns.Lists.Add(store, id, 614)
    ns.Lists.Add(store, id, 1)
    local l = ns.UI.OpenPopout({ kind = "list", list = id })
    for _, h in ipairs(l.groupFrames) do ok(not h:IsShown(), "no headers on a custom list") end
    eq(#l.rows, 2)
    eq({ l.rows[1].id, l.rows[2].id }, { 614, 1 }, "in the order added, expansions mixed")
    -- By expansion (the title menu): headers, the list's order inside.
    local items = ns.UI.PopoutMenuExtra(l)
    eq({ items[1].text, items[1].checked, items[2].text, items[2].checked },
      { "Sort: order added", true, "Sort: by expansion", false })
    items[2].onClick()
    eq(ns.Lists.SortOf(store, id), "expansion")
    local shown = {}
    for _, h in ipairs(l.groupFrames) do if h:IsShown() then shown[#shown + 1] = h.Text:GetText() end end
    eq(#shown, 2, "a header per expansion")
    ok(shown[1]:find("^%- Classic"), shown[1])
    eq(ns.UI.PopoutMenuExtra(q), {}, "a quick list has no sort")
    -- Move down (a row's right-click) changes the list itself.
    ns.Lists.SetSort(store, id, "added")
    ns.Lists.Move(store, id, 614, 1)
    ns.Refresh()
    eq({ l.rows[1].id, l.rows[2].id }, { 1, 614 }, "the list's new order")
    -- Alt-drag: the list itself changes, not a window order.
    l.dragKey, l.dropAt = l.rows[2].key, 1
    l.SetScript = l.SetScript or function() end
    ns.UI.PopoutDragDrop(l)
    eq(store.lists[id].mounts, { 614, 1 }, "dragged to the top of the list")
    eq((ns.db.global.popouts[l.key] or {}).order, nil, "no per-window order for a custom list")
  end)

  it("Alt-drag keeps a row inside its expansion group; moving down lands at the line", function()
    local ns = loadUI()
    setup(ns)
    ns.db.global.popoutStyle = { layout = "compact" } -- one-line rows: 20 px apart
    ns.QuickLists.Mounts = function() return { 1, 614, 9 } end
    local w = ns.UI.OpenPopout({ kind = "quick", key = "mythic" })
    local function ids()
      local out = {}
      for i, r in ipairs(w.rows) do out[i] = r.id end
      return out
    end
    local start = ids()
    eq(start[1], 1, "Classic first")
    local x, y = start[2], start[3] -- the two WOD rows
    local function rowOf(id)
      for _, c in ipairs(w.Content.children) do if c.data and c.data.id == id and c:IsShown() then return c end end
    end
    IsAltKeyDown = function() return true end
    w.Content.top = 500
    -- The first WOD row dragged past the end: lands after the other one.
    rowOf(x):RunScript("OnDragStart")
    STUB_CURSOR[1], STUB_CURSOR[2] = 50, 300
    w:RunScript("OnUpdate")
    eq(w.dropAt, 4)
    local _, _, _, _, lineY = w.DropLine:GetPoint(1)
    eq(lineY, -100, "under the group's last row")
    rowOf(x):RunScript("OnDragStop")
    eq(ids(), { 1, y, x }, "moved down one")
    -- Dragged to the very top: stays in its group (its first row).
    rowOf(x):RunScript("OnDragStart")
    STUB_CURSOR[1], STUB_CURSOR[2] = 50, 500
    w:RunScript("OnUpdate")
    eq(w.dropAt, 2, "the group's first slot")
    rowOf(x):RunScript("OnDragStop")
    eq(ids(), { 1, x, y })
    IsAltKeyDown = nil
    STUB_CURSOR[1], STUB_CURSOR[2] = 0, 0
  end)

  it("appearance: right-click the title; saved per window; Apply to all; Reset", function()
    local ns = loadUI()
    setup(ns)
    local a = ns.UI.OpenPopout({ kind = "camp", exp = WOD })
    local b = ns.UI.OpenPopout({ kind = "daily", exp = WOD })
    local menu
    -- Every click comes with the pointer lower and further right than the one
    -- before (it is over the row just clicked).
    local function nudge() STUB_CURSOR[1], STUB_CURSOR[2] = STUB_CURSOR[1] + 15, STUB_CURSOR[2] - 20 end
    local function click(text)
      for _, it in ipairs(menu.items) do
        if it:IsShown() and it.data and not it.data.slider and it.data.text == text then
          nudge()
          it:RunScript("OnClick", "LeftButton")
          return it
        end
      end
      error("no menu item " .. text)
    end
    local function sliderRow(label)
      for _, it in ipairs(menu.items) do
        if it:IsShown() and it.data and it.data.slider and it.data.text == label then return it end
      end
      error("no slider " .. label)
    end
    local function pos() local p, _, rp, x, y = menu:GetPoint(1); return { p, rp, x, y } end
    STUB_CURSOR[1], STUB_CURSOR[2] = 600, 700
    a.Strip:RunScript("OnMouseUp", "RightButton")
    menu = _G.MountTrailMenu
    ok(menu:IsShown(), "the flat menu")
    local opened = pos()
    eq(opened, { "TOPLEFT", "BOTTOMLEFT", 604, 696 }, "opens at the pointer")
    eq(menu.items[1].data.title, "Appearance")
    -- Opacity: a slider (20-100 %), no steps to pick from.
    local op = sliderRow("Opacity")
    eq({ op.Slider.min, op.Slider.max, op.Slider.step, op.Slider.value }, { 20, 100, 1, 92 })
    eq(op.Value:GetText(), "92%")
    ok(not (ns.db.global.popouts["camp|" .. WOD] or {}).style, "opening the menu changes nothing")
    op.Slider:SetValue(60)
    ok(menu:IsShown(), "stays open")
    local st = ns.db.global.popouts["camp|" .. WOD].style
    eq(st.alpha, 0.6)
    eq(op.Value:GetText(), "60%")
    eq(a.Fill.color[4], 0.6, "the window follows live")
    eq(b.Fill.color[4], 0.92, "the other window keeps its look")
    op.Slider:SetValue(5)
    eq(st.alpha, 0.2, "no lower than 20%")
    op.Slider:SetValue(60)
    local bgItem
    for _, it in ipairs(menu.items) do if it:IsShown() and it.data.text == "Background colour" then bgItem = it end end
    ok(bgItem.Arrow:IsShown(), "a sub-menu item shows its arrow")
    click("Background colour")
    ok(menu:IsShown(), "the sub-menu replaces it")
    eq(menu.items[1].data.title, "Background colour")
    click("Forest")
    eq(st.bg, { 0.05, 0.12, 0.07 })
    click("Back")
    click("Text colour")
    click("Gold")
    eq(st.text, { 1, 0.82, 0 })
    click("Back")
    click("Header colour")
    click("Sky")
    eq(st.header, { 0.55, 0.8, 1 })
    eq(a.Title.textColor, { 0.55, 0.8, 1 }, "the title: the header colour, not the text colour")
    click("Back")
    -- Opacity shows what was set when the menu is painted again.
    eq(sliderRow("Opacity").Slider.value, 60)
    -- Font size: a number (8-24), the window's own default until one is set.
    local fs = sliderRow("Font size")
    eq({ fs.Slider.min, fs.Slider.max, fs.Slider.step, fs.Slider.value }, { 8, 24, 1, 11 })
    eq(fs.Value:GetText(), "11")
    eq(st.size, nil)
    for _, it in ipairs(menu.items) do ok(not (it.data and it.data.text == "Default size"), "no Default size item") end
    fs.Slider:SetValue(14)
    eq(st.size, 14)
    eq(fs.Value:GetText(), "14")
    ok(a.rowHeight > 20, "taller rows for bigger text")
    fs.Slider:SetValue(30)
    eq(st.size, 24, "no bigger than 24")
    fs.Slider:SetValue(7)
    eq(st.size, 8, "no smaller than 8")
    fs.Slider:SetValue(14)
    eq(st.size, 14)
    click("Font")
    click("Morpheus")
    eq(st.font, "Fonts\\MORPHEUS.TTF")
    local row
    for _, c in ipairs(a.Content.children) do if c.data and c.data.id == 657 then row = c end end
    eq({ row.Name.fontPath, row.Name.fontSize }, { "Fonts\\MORPHEUS.TTF", 14 })
    eq(row.Name.textColor, { 1, 0.82, 0 })
    ok(menu:IsShown(), "still open after all those clicks")
    eq(pos(), opened, "and where it opened: a click does not move the menu")
    click("Back")
    eq(pos(), opened, "Back neither")
    click("Apply to all pop-outs")
    ok(not menu:IsShown(), "closed")
    eq(ns.db.global.popoutStyle.alpha, 0.6)
    eq(ns.db.global.popouts["camp|" .. WOD].style, nil, "the shared look now")
    eq(b.Fill.color[4], 0.6, "every window")
    local c = ns.UI.OpenPopout({ kind = "weekly", exp = WOD })
    eq(c.Fill.color[4], 0.6, "a new window too")
    b.Strip:RunScript("OnMouseUp", "RightButton")
    click("Reset appearance")
    eq(b.Fill.color[4], 0.92, "back to the add-on's look")
    eq(a.Fill.color[4], 0.6, "the others keep the shared look")
    ok(ns.UI.PopoutFonts()[1].path:find("FRIZQT"), "the game's fonts first")
    eq(ns.UI.PopoutStyle({ alpha = 5 }).alpha, 1, "opacity clamped")
    STUB_CURSOR[1], STUB_CURSOR[2] = 0, 0
  end)

  it("style: opacity 0.2-1 and font size 8-24 whole points, as saved", function()
    local ns = loadUI()
    local style = ns.UI.PopoutStyle
    eq(style({ alpha = 0.05 }).alpha, 0.2)
    eq(style({ alpha = 0.55 }).alpha, 0.55)
    eq(style({}).alpha, 0.92, "the default")
    eq(style({}).size, nil, "no size chosen")
    eq(style({ size = 3 }).size, 8)
    eq(style({ size = 99 }).size, 24)
    eq(style({ size = 13.4 }).size, 13, "whole points")
    eq(style({ size = 10 }).size, 10, "an old preset size still holds")
  end)

  it("style: the default font size is the small font's own, within 8-24", function()
    local ns = loadUI()
    eq(ns.UI.PopoutDefaultSize(), 11, "no font object to ask: 11")
    local saved = _G.GameFontHighlightSmall
    _G.GameFontHighlightSmall = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12.4, "" end }
    eq(ns.UI.PopoutDefaultSize(), 12)
    _G.GameFontHighlightSmall = { GetFont = function() return "x", 40, "" end }
    eq(ns.UI.PopoutDefaultSize(), 24)
    _G.GameFontHighlightSmall = saved
  end)

  it("snapped windows move together: the top one takes the stack, a middle one those below", function()
    local ns = loadUI()
    local chain = ns.UI.SnapChain
    local rects = {
      a = { left = 100, top = 600, right = 380, bottom = 500 },
      b = { left = 100, top = 500, right = 380, bottom = 400 },
      c = { left = 100, top = 400, right = 380, bottom = 300 },
      d = { left = 380, top = 600, right = 660, bottom = 500 }, -- right of a
      e = { left = 900, top = 600, right = 1180, bottom = 450 }, -- apart
    }
    eq(chain("a", rects), { "b", "c", "d" })
    eq(chain("b", rects), { "c" })
    eq(chain("c", rects), {})
    eq(chain("e", rects), {})

    setup(ns)
    local top = ns.UI.OpenPopout({ kind = "camp", exp = WOD })
    local mid = ns.UI.OpenPopout({ kind = "daily", exp = WOD })
    local low = ns.UI.OpenPopout({ kind = "weekly", exp = WOD })
    local function place(w, r) w.left, w.top, w.right, w.bottom = r.left, r.top, r.right, r.bottom end
    place(top, rects.a)
    place(mid, rects.b)
    place(low, rects.c)
    local function anchor(w)
      local p, rel, rp, x, y = w:GetPoint(1)
      return { p, rp, x, y }, rel
    end
    mid.Strip:RunScript("OnDragStart")
    local pt, rel = anchor(low)
    eq(pt, { "TOPLEFT", "TOPLEFT", 0, -100 }, "pinned to the one dragged")
    ok(rel == mid)
    ok(select(2, top:GetPoint(1)) ~= mid, "the one above stays")
    place(mid, { left = 1000, top = 300, right = 1280, bottom = 200 })
    mid.Strip:RunScript("OnDragStop")
    pt, rel = anchor(mid)
    eq(pt, { "TOPLEFT", "BOTTOMLEFT", 1000, 300 })
    ok(rel == UIParent)
    pt, rel = anchor(low)
    eq(pt, { "TOPLEFT", "BOTTOMLEFT", 1000, 200 }, "came along")
    ok(rel == UIParent)
    local saved = ns.db.global.popouts["weekly|" .. WOD]
    eq({ saved.point, saved.relPoint, saved.x, saved.y }, { "TOPLEFT", "BOTTOMLEFT", 1000, 200 })
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
    ok(menu.items[1].Band:IsShown() and menu.items[1].Accent:IsShown(), "a title sits on a card band")
    ok(not menu.items[2].Band:IsShown(), "items do not")
    menu.items[2]:RunScript("OnClick", "LeftButton")
    eq(clicked, 1)
    ok(menu:IsShown(), "keepOpen")
    menu.items[4]:RunScript("OnClick", "LeftButton")
    eq(clicked, 1, "disabled does nothing")
    _G.MountTrailMenuCatcher:RunScript("OnClick", "LeftButton")
    ok(not menu:IsShown(), "a click elsewhere closes")
  end)

  it("menu: a click repaints in place; a sub-menu opens where the menu is; it never follows the pointer", function()
    local ns = loadUI()
    local owner = CreateFrame("Button", nil, UIParent)
    local state = false
    local main
    local function sub()
      return { { title = "Sub" }, { text = "Back", submenu = main } }
    end
    main = function()
      return {
        { title = "Main" },
        { text = "Loop", checked = state, keepOpen = true, onClick = function() state = not state end },
        { text = "More", submenu = sub },
      }
    end
    local function pos(m) local p, _, rp, x, y = m:GetPoint(1); return { p, rp, x, y } end
    STUB_CURSOR[1], STUB_CURSOR[2] = 400, 700
    local menu = ns.UI.ShowMenu(owner, main, "cursor")
    local first = pos(menu)
    eq(first, { "TOPLEFT", "BOTTOMLEFT", 404, 696 })
    ok(menu.clamped, "kept on screen")
    -- Each click is made with the pointer lower and to the right of the
    -- menu's corner; the menu used to jump to it every time.
    STUB_CURSOR[1], STUB_CURSOR[2] = 460, 650
    menu.items[2]:RunScript("OnClick", "LeftButton")
    eq(state, true)
    eq(pos(menu), first, "a keepOpen click stays put")
    STUB_CURSOR[1], STUB_CURSOR[2] = 470, 620
    menu.items[3]:RunScript("OnClick", "LeftButton")
    eq(menu.items[1].data.title, "Sub")
    eq(pos(menu), first, "the sub-menu opens in the same place")
    STUB_CURSOR[1], STUB_CURSOR[2] = 480, 600
    menu.items[2]:RunScript("OnClick", "LeftButton")
    eq(menu.items[1].data.title, "Main")
    eq(pos(menu), first, "Back too")
    -- Closed and opened again: at the pointer once more (and scaled to its owner).
    ns.UI.HideMenu()
    STUB_CURSOR[1], STUB_CURSOR[2] = 120, 340
    ns.UI.ShowMenu(owner, main, "cursor")
    eq(pos(menu), { "TOPLEFT", "BOTTOMLEFT", 124, 336 }, "a new open is placed afresh")
    -- Below its owner, the other anchor, also stays through a repaint.
    ns.UI.HideMenu()
    ns.UI.ShowMenu(owner, main)
    local below = pos(menu)
    eq(below, { "TOPLEFT", "BOTTOMLEFT", 0, -2 })
    menu.items[2]:RunScript("OnClick", "LeftButton")
    eq(pos(menu), below)
    STUB_CURSOR[1], STUB_CURSOR[2] = 0, 0
  end)

  it("menu: a slider row has a range, step and value; dragging reports, painting does not", function()
    local ns = loadUI()
    local owner = CreateFrame("Button", nil, UIParent)
    local value, got, ticks = 60, {}, 0
    local function items()
      return {
        { title = "Look" },
        { slider = true, text = "Opacity", min = 20, max = 100, step = 1, value = value, format = "%d%%",
          onChange = function(v) value = v; got[#got + 1] = v end },
        { text = "Tick", checked = value > 60, keepOpen = true, onClick = function() ticks = ticks + 1 end },
      }
    end
    local menu = ns.UI.ShowMenu(owner, items)
    local row = menu.items[2]
    local s = row.Slider
    ok(s:IsShown(), "a slider")
    eq({ s.min, s.max, s.step, s.value, s.obeyStep, s.orientation }, { 20, 100, 1, 60, true, "HORIZONTAL" })
    eq(row.Label:GetText(), "Opacity")
    eq(row.Value:GetText(), "60%")
    ok(not row.Highlight:IsShown(), "no hover highlight on a slider row")
    ok(row:GetHeight() > 18, "taller than a text row")
    eq(got, {}, "painting does not report a change")
    s:SetValue(75)
    eq(got, { 75 })
    eq(row.Value:GetText(), "75%", "the readout follows")
    eq(menu.items[3].data.checked, true, "the rest repaints (no jump back to 60)")
    eq(s.value, 75)
    s:RunScript("OnMouseWheel", 1)
    eq(value, 76, "wheel: one step up")
    s:RunScript("OnMouseWheel", -1)
    s:RunScript("OnMouseWheel", -1)
    eq(value, 74, "and down")
    s:SetValue(75.4)
    eq(value, 75, "whole steps")
    s:SetValue(75)
    eq(#got, 5, "the same value reports nothing")
    -- A click on the row's label or a tick elsewhere does not close or report.
    row:RunScript("OnClick", "LeftButton")
    ok(menu:IsShown(), "a click on the row itself does nothing")
    menu.items[3]:RunScript("OnClick", "LeftButton")
    eq(ticks, 1)
    eq(#got, 5)
    eq(s.value, 75)
    -- The row's frames serve other menus: no slider there.
    ns.UI.ShowMenu(owner, { { title = "x" }, { text = "plain" } })
    ok(not menu.items[2].Slider:IsShown(), "a plain row hides it")
    eq(menu.items[2]:GetHeight(), 18)
    -- A menu given as a plain list (not rebuilt on a repaint): the slider keeps what was dragged to.
    ns.UI.ShowMenu(owner, { { slider = true, min = 0, max = 10, step = 1, value = 3, onChange = function() end } })
    menu.items[1].Slider:SetValue(7)
    eq(menu.items[1].Slider.value, 7, "no jump back to the value it was opened with")
    eq(menu.items[1].Value:GetText(), "7")
    -- A value out of range is held to it; the step snaps it.
    ns.UI.ShowMenu(owner, { { slider = true, min = 8, max = 24, step = 1, value = 99, onChange = function() end } })
    eq(menu.items[1].Slider.value, 24)
    eq(menu.items[1].Value:GetText(), "24", "no format: the number")
    eq(ns.UI.SnapSliderValue(10.4, 8, 24, 1), 10)
    eq(ns.UI.SnapSliderValue(10.5, 8, 24, 1), 11)
    eq(ns.UI.SnapSliderValue(3, 8, 24, 1), 8)
    eq(ns.UI.SnapSliderValue(30, 8, 24, 1), 24)
    eq(ns.UI.SnapSliderValue(5, 0, 10, nil), 5, "no step given: whole")
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
    local menu = _G.MountTrailMenu
    eq(menu.items[2].data.text, "Loop")
    eq(menu.items[2].data.checked, false)
    menu.items[2]:RunScript("OnClick", "LeftButton")
    eq(ns.Lists.Has(store, id, 614), true)
    ok(menu:IsShown(), "stays open")
    eq(menu.items[2].data.checked, true, "repainted")
    local newItem
    for _, it in ipairs(menu.items) do if it:IsShown() and it.data.text == "New list..." then newItem = it end end
    newItem:RunScript("OnClick", "LeftButton")
    local p = _G.MountTrailPrompt
    ok(p:IsShown(), "asks for a name")
    p.Edit:SetText("Tanaan")
    p.Edit:RunScript("OnEnterPressed")
    local sorted = ns.Lists.Sorted(store)
    eq(#sorted, 2)
    eq(sorted[2].name, "Tanaan")
    eq(ns.Lists.Get(store, sorted[2].id).mounts, { 614 })
  end)

  it("Checklist chips: right-click Daily / Weekly / Rare Spawns pops the whole group out", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local store = ns.UI.ListsDB()
    local id = ns.Lists.Create(store, "Loop")
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    local root
    for _, c in ipairs(ns.UI.frame.Contents.checklist.children) do if c.Detail then root = c end end
    local header
    for _, c in ipairs(root.children) do if c.Chips then header = c end end
    local chip = {}
    for _, c in ipairs(header.Chips) do chip[c.key] = c end
    eq(chip.daily.clickButtons, { "LeftButtonUp", "RightButtonUp" })
    chip.daily:RunScript("OnClick", "RightButton")
    eq(ns.db.char.checklistShow, nil, "a right-click does not switch the list")
    local W = ns.UI.PopoutWindows
    local daily = W["daily|all"]
    ok(daily and daily:IsShown(), "every daily, one window")
    ok(daily.Title:GetText():find("^Dailies"), daily.Title:GetText())
    eq(#daily.rows, 2, "every expansion's dailies still to do")
    ns.db.global.popouts["daily|all"].showDone = true
    ns.UI.RefreshPopouts()
    eq(#daily.rows, 3, "with Show completed: the done one too")
    chip.weekly:RunScript("OnClick", "RightButton")
    ok(W["weekly|all"]:IsShown())
    ok(W["weekly|all"].Title:GetText():find("^Weeklies"))
    chip.camp:RunScript("OnClick", "RightButton")
    local camp = W["camp|all"]
    ok(camp.Title:GetText():find("^Rare Spawns"), camp.Title:GetText())
    eq(#camp.rows, 2, "rare spawns of every expansion")
    eq(ns.db.global.popouts["camp|all"].source, { kind = "camp", all = true }, "saved: back after /reload")
    eq(chip.lists, nil, "no Lists chip: the lists live in the navigation")
    -- A left-click still switches the list.
    chip.weekly:RunScript("OnClick", "LeftButton")
    eq(ns.db.char.checklistShow, "weekly")
  end)

  it("deleting a list asks for its name; Delete only works once it is typed", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local store = ns.UI.ListsDB()
    local id = ns.Lists.Create(store, "WoD loop")
    ns.ToggleWindow()
    -- The list's menu (the navigation's right-click on it).
    ns.UI.ShowCustomListMenu(id, CreateFrame("Frame", nil, UIParent))
    local menu = _G.MountTrailMenu
    local del
    for _, it in ipairs(menu.items) do if it:IsShown() and it.data.text == "Delete..." then del = it end end
    del:RunScript("OnClick", "LeftButton")
    local p = _G.MountTrailPrompt
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

describe("zone window and the alt lockouts window", function()
  it("the zone's rares follow the player: zone, sub-zone and loading-screen events, only on a new map", function()
    local ns = loadUI()
    local builds = 0
    ns.UI.ChecklistBuild = function() builds = builds + 1; return built() end
    local map = 550
    ns.Game.PlayerMap = function() return map end
    local zoneIDs = { [550] = { { id = 614 } }, [525] = { { id = 657 } } }
    ns.UI.ZoneMounts = function() return zoneIDs[map] or {} end
    local w = ns.UI.OpenPopout({ kind = "zone" })
    eq(w.map, 550)
    local function shown() local out = {} for i, r in ipairs(w.rows) do out[i] = r.id end return out end
    eq(shown(), { 614 })
    local before = builds
    fire_frame_event("ZONE_CHANGED")
    eq(builds, before, "same map: no redraw")
    map = 525
    fire_frame_event("ZONE_CHANGED_INDOORS")
    eq(shown(), { 657 }, "a new map: redrawn")
    map = 550
    fire_frame_event("PLAYER_ENTERING_WORLD")
    eq(shown(), { 614 })
    -- Closed, the player moves on, reopened, back again: still follows.
    ns.UI.ClosePopout("zone")
    map = 525
    fire_frame_event("ZONE_CHANGED_NEW_AREA")
    ns.UI.OpenPopout({ kind = "zone" })
    eq(shown(), { 657 })
    map = 550
    fire_frame_event("ZONE_CHANGED_NEW_AREA")
    eq(shown(), { 614 }, "back to the first zone")
  end)

  it("the alt lockouts window takes the pop-out appearance menu, Apply to all, snapping and a resize grip", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    ns.UI.ToggleAltsWindow(true)
    local alts = ns.UI.AltsWindow()
    ok(alts:IsShown(), "opened")
    eq(alts.Fill.color[4], 0.92, "the pop-outs' default look")
    -- Right-click the title: the same Appearance menu.
    alts.Strip:RunScript("OnMouseUp", "RightButton")
    local menu = _G.MountTrailMenu
    ok(menu:IsShown())
    eq(menu.items[1].data.title, "Appearance")
    local op
    for _, it in ipairs(menu.items) do
      if it:IsShown() and it.data and it.data.slider and it.data.text == "Opacity" then op = it end
    end
    op.Slider:SetValue(50)
    eq(ns.db.global.popouts.alts.style.alpha, 0.5, "saved under popouts.alts")
    eq(alts.Fill.color[4], 0.5, "repainted live")
    -- A bigger font: taller rows.
    ns.db.global.popouts.alts.style.size = 20
    alts.Restyle(false)
    eq(alts.rowHeight, 29)
    eq(alts.Title.fontSize, 22, "the title two points up, as the pop-outs'")
    -- Apply to all from a pop-out: the alts window takes that look too.
    local camp = ns.UI.OpenPopout({ kind = "camp", exp = WOD })
    ns.db.global.popouts["camp|" .. WOD].style = { alpha = 0.3 }
    camp.Strip:RunScript("OnMouseUp", "RightButton")
    for _, it in ipairs(menu.items) do
      if it:IsShown() and it.data and it.data.text == "Apply to all pop-outs" then it:RunScript("OnClick", "LeftButton") end
    end
    eq(ns.db.global.popoutStyle.alpha, 0.3)
    eq(ns.db.global.popouts.alts.style, nil)
    eq(alts.Fill.color[4], 0.3, "follows the shared look")
    -- Dropped near the pop-out: snaps under it.
    camp.left, camp.top, camp.right, camp.bottom = 100, 600, 380, 400
    alts.left, alts.top, alts.right, alts.bottom = 108, 392, 488, 0
    alts.Strip:RunScript("OnDragStart")
    alts.Strip:RunScript("OnDragStop")
    eq({ alts:GetPoint(1) }, { "TOPLEFT", UIParent, "BOTTOMLEFT", 100, 400 })
    -- Resize grip: the width is kept and decides the columns.
    alts.Grip:RunScript("OnMouseDown", "LeftButton")
    alts.width, alts.height = 500, 300
    alts.Grip:RunScript("OnMouseUp", "LeftButton")
    eq({ ns.db.global.altsWindow.width, ns.db.global.altsWindow.height }, { 500, 300 })
    eq(ns.UI.AltsFit(500), 4)
    alts.Grip:RunScript("OnClick", "RightButton")
    eq(ns.db.global.altsWindow.width, nil, "fits the columns again")
    eq(ns.db.global.altsWindow.height, 300, "the height stays")
    -- Ctrl-click a pop-out's x closes the alts window too.
    IsControlKeyDown = function() return true end
    camp.Close:RunScript("OnClick", "LeftButton")
    IsControlKeyDown = nil
    ok(not alts:IsShown() and not camp:IsShown(), "both closed")
  end)
end)

describe("the zone's mounts pop-out", function()
  it("lists every mount still to get in the player's zone, follows the map, opens from /mtrail here", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local map = 550
    ns.Game.PlayerMap = function() return map end
    local zones = {
      [550] = { { id = 614 }, { id = 7 }, { id = 4242 } }, -- 7 is owned (loadUI's IsOwned)
      [525] = { { id = 657 } },
    }
    local names_ = { [550] = "Nagrand", [525] = "Frostfire Ridge" }
    ns.UI.ZoneMounts = function() return zones[map] or {}, { name = names_[map] } end
    ns.Data.Mounts[4242] = { name = "Plain Vendor Mount", exp = WOD }
    run_slash(ns.addon, "mtrail", "here")
    local w = ns.UI.PopoutWindows.zonemounts
    ok(w and w:IsShown(), "opened")
    ok(w.Title:GetText():find("^Mounts in Nagrand"), w.Title:GetText())
    local function ids() local out = {} for i, r in ipairs(w.rows) do out[i] = r.id end table.sort(out) return out end
    eq(ids(), { 614, 4242 }, "the tracked lockout and a plain mount; owned ones left out")
    for _, r in ipairs(w.rows) do
      if r.id == 614 then eq(r.entry.reset, "daily", "the Checklist's entry when it tracks the mount") end
      if r.id == 4242 then eq(r.listOnly, true, "a plain row otherwise") end
    end
    map = 525
    fire_frame_event("ZONE_CHANGED_NEW_AREA")
    eq(ids(), { 657 })
    ok(w.Title:GetText():find("^Mounts in Frostfire Ridge"), w.Title:GetText())
    run_slash(ns.addon, "mtrail", "here")
    ok(not w:IsShown(), "the slash toggles it")
  end)

  it("pop-out rows: Shift-click opens the map, Ctrl-click previews, a plain click goes there", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local got = {}
    ns.UI.MapAction = function(method, id, boss) got[#got + 1] = { method, id, boss } end
    ns.UI.PreviewMount = function(id) got[#got + 1] = { "preview", id } end
    ns.UI.RowGo = function(id, boss) got[#got + 1] = { "go", id, boss } end
    local w = ns.UI.OpenPopout({ kind = "weekly", exp = WOD })
    local r = w.rowFrames[1]
    eq(r.data.id, 10)
    IsShiftKeyDown = function() return true end
    r:RunScript("OnClick", "LeftButton")
    IsShiftKeyDown = nil
    IsControlKeyDown = function() return true end
    r:RunScript("OnClick", "LeftButton")
    IsControlKeyDown = nil
    r:RunScript("OnClick", "LeftButton")
    eq(got, { { "OpenMap", 10, "Boss" }, { "preview", 10 }, { "go", 10, "Boss" } })
  end)

  it("/mtrail zone (and /mtrail here) toggles the zone's mounts pop-out, not the side panel", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    ns.Game.PlayerMap = function() return 550 end
    ns.UI.ZoneMounts = function() return { { id = 614 } }, { name = "Nagrand" } end
    run_slash(ns.addon, "mtrail", "zone")
    ok(ns.UI.PopoutWindows.zonemounts:IsShown(), "pop-out opened")
    ok(not (ns.UI.frame and ns.UI.frame:IsShown()), "main window stays closed")
    ok(not (ns.UI.zonePanel and ns.UI.zonePanel:IsShown()), "side panel stays closed")
    run_slash(ns.addon, "mtrail", "zone")
    ok(not ns.UI.PopoutWindows.zonemounts:IsShown(), "and closed again")
    run_slash(ns.addon, "mtrail", "here")
    ok(ns.UI.PopoutWindows.zonemounts:IsShown(), "here still works")
    run_slash(ns.addon, "mtrail", "help")
    local found = false
    for _, line in ipairs(ns.addon.printed or {}) do if line:find("^/mtrail zone") then found = true end end
    ok(found, "help lists /mtrail zone")
  end)

  it("right-clicking the zone panel's title pops the zone's mounts out", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    ns.Game.PlayerMap = function() return 550 end
    ns.UI.ZoneMounts = function() return { { id = 614 } }, { name = "Nagrand" } end
    ns.ToggleWindow()
    ns.UI.SetZonePanelOpen(true)
    local hit = ns.UI.zonePanel.TitleHit
    ok(hit, "the title takes a right-click")
    hit:RunScript("OnClick", "RightButton")
    ok(ns.UI.PopoutWindows.zonemounts:IsShown())
  end)
end)

describe("the zone's mounts pop-out, by source", function()
  it("groups its rows under source headers when the zone has several", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    ns.Game.PlayerMap = function() return 550 end
    ns.Data.Mounts[4242] = { name = "Vendor Mount", exp = WOD, section = "vendor" }
    ns.Data.Mounts[4343] = { name = "Achievement Mount", exp = WOD, section = "achievement" }
    ns.UI.ZoneMounts = function() return { { id = 4343 }, { id = 4242 } }, { name = "Nagrand" } end
    local groups = ns.UI.PopoutGroups({
      { id = 4242, entry = { m = ns.Data.Mounts[4242] } },
      { id = 4343, entry = { m = ns.Data.Mounts[4343] }, done = false },
    }, { kind = "zonemounts" })
    eq(#groups, 2)
    eq({ groups[1].label, groups[2].label }, { "Vendors", "Achievements" })
    local w = ns.UI.OpenPopout({ kind = "zonemounts" })
    local shown = {}
    for _, h in ipairs(w.groupFrames) do if h:IsShown() then shown[#shown + 1] = h.Text:GetText() end end
    ok(shown[1]:find("^%- Vendors"), shown[1])
    ok(shown[2]:find("^%- Achievements"), shown[2])
  end)
end)

describe("pop-out group headers", function()
  it("click collapses a group (saved per window); Shift-click collapses or expands them all", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local w = ns.UI.OpenPopout({ kind = "camp", all = true })
    local function shownHeads()
      local out = {}
      for _, h in ipairs(w.groupFrames) do if h:IsShown() then out[#out + 1] = h end end
      return out
    end
    local heads = shownHeads()
    eq(#heads, 2, "two expansions")
    eq(#w.rows, 2)
    heads[1]:RunScript("OnMouseUp", "LeftButton")
    eq(ns.db.global.popouts["camp|all"].collapsed[heads[1].groupKey], true)
    eq(#w.rows, 1, "its rows hidden")
    ok(shownHeads()[1].Text:GetText():find("^%+ "), "a collapsed header shows +")
    IsShiftKeyDown = function() return true end
    shownHeads()[2]:RunScript("OnMouseUp", "LeftButton")
    eq(#w.rows, 0, "every group collapsed")
    shownHeads()[1]:RunScript("OnMouseUp", "LeftButton")
    IsShiftKeyDown = nil
    eq(#w.rows, 2, "a collapsed header's Shift-click expands them all")
    eq(ns.db.global.popouts["camp|all"].collapsed, {})
  end)
end)

describe("lists in the navigation column", function()
  -- The journal home too, from here on.
  UI_FILES[#UI_FILES + 1] = "UI/JournalHome.lua"
  UI_FILES[#UI_FILES + 1] = "UI/BrowseView.lua"

  local function home(ns)
    ns.ToggleWindow()
    ns.UI.SelectTab("journal")
    return ns.UI.frame.Contents.journal.children[2], ns.UI.frame.Contents.journal
  end

  it("UI.ListCardStats: owned / total, and the open lockouts of its mounts still to get (each once)", function()
    local ns = loadUI()
    local e = { id = 614, mounts = { 614, 615 }, done = false }
    local built = { daily = { e, { id = 636, done = true } }, weekly = {} }
    local stats = ns.UI.ListCardStats({ 614, 615, 636, 7 }, function(id) return id == 7 end, built)
    eq(stats, { have = 1, total = 4, open = 1 })
  end)

  local function navButton(ns, label)
    local nav = ns.UI.frame.Nav
    for i = 1, nav.shown do
      local b = nav.Buttons[i]
      if b.Text:GetText():find(label, 1, true) then return b end
    end
  end

  it("the navigation lists the built-in lists and your own; a click opens the list page; deleting it goes home", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local h = home(ns)
    local nav = ns.UI.frame.Nav
    ok(nav.Empty:IsShown(), "no lists yet: the hint")
    ok(navButton(ns, "Weekly lockouts"), "the quick list")
    local store = ns.UI.ListsDB()
    local id = ns.Lists.Create(store, "Loop")
    ns.Lists.Add(store, id, 614)
    ns.Lists.Add(store, id, 7) -- owned (loadUI's IsOwned)
    ns.Data.Mounts[614].section = "world"
    ns.Data.Mounts[7] = { name = "Owned One", exp = WOD, tab = "journal", section = "vendor" }
    ns.Refresh()
    ok(not nav.Empty:IsShown())
    local b = navButton(ns, "Loop")
    ok(b, "the list's entry")
    ok(b.Badge:GetText():find("1", 1, true), "its open lockout: " .. tostring(b.Badge:GetText()))
    eq(navButton(ns, "Weekly lockouts").Text:GetText(), "Weekly lockouts", "no mark in the name (the star is a button)")
    ok(navButton(ns, "Weekly lockouts").Star:IsShown(), "a favourite star on each list")
    b:RunScript("OnClick", "LeftButton")
    local journal = ns.UI.frame.Contents.journal
    local page
    for _, c in ipairs(journal.children) do if c.List and c.PopOut then page = c end end
    ok(page and page:IsShown() and not h:IsShown(), "the list page")
    eq(page.Title:GetText(), "Loop")
    ok(navButton(ns, "Loop").selected and not navButton(ns, "Home").selected, "its entry marked")
    eq(ns.UI.ListCardStatsFor({ kind = "list", list = id }, built()), { have = 1, total = 2, open = 1 })
    -- The list's own order, no headers; Collected on: the owned mount too.
    local function ids()
      local out = {}
      for _, r in ipairs(page.List.ScrollBox.provider.rows) do
        ok(not r.header, "in the order added: no headers")
        out[#out + 1] = r.id
      end
      return out
    end
    ns.db.global.filters.collected = true
    page.List:Refresh()
    eq(ids(), store.lists[id].mounts, "the order the mounts were added")
    ns.Lists.Move(store, id, store.lists[id].mounts[2], -1)
    page.List:Refresh()
    eq(ids(), store.lists[id].mounts, "moved: the list's new order")
    -- By expansion: a header per expansion, the list's order inside.
    ns.Lists.SetSort(store, id, "expansion")
    page.List:Refresh()
    local have, total = 0, 0
    for _, r in ipairs(page.List.ScrollBox.provider.rows) do
      if r.header then
        eq(r.depth, 1)
        have, total = have + (r.owned or 0), total + (r.total or 0)
      end
    end
    eq({ have, total }, { 1, 2 }, "by expansion, owned counted")
    ns.Lists.SetSort(store, id, "added")
    ns.db.global.filters.collected = false
    page.PopOut:RunScript("OnClick", "LeftButton")
    ok(ns.UI.PopoutWindows["list|" .. id]:IsShown())
    -- Home leaves the page.
    navButton(ns, "Home"):RunScript("OnClick", "LeftButton")
    ok(h:IsShown() and not page:IsShown(), "home again")
    -- Deleted while open: home.
    navButton(ns, "Loop"):RunScript("OnClick", "LeftButton")
    ns.Lists.Delete(store, id)
    ns.Refresh()
    ok(h:IsShown() and not page:IsShown(), "home after the delete")
    eq(navButton(ns, "Loop"), nil, "its entry gone")
  end)

  it("one Lists section: the built-in lists first, tagged auto, then your own; it collapses (saved)", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local store = ns.UI.ListsDB()
    ns.Lists.Create(store, "Loop")
    home(ns)
    local nav = ns.UI.frame.Nav
    local function heading(text)
      for _, h in ipairs(nav.Headings) do
        if h:IsShown() and (h.Text:GetText():gsub("^[%+%-] ", "")) == text then return h end
      end
    end
    local lists = heading("Lists")
    ok(lists, "one Lists heading")
    eq(heading("Quick lists"), nil, "no Quick lists heading")
    eq(heading("My lists"), nil, "no My lists heading")
    eq(lists.key, ns.UI.NAV_LISTS_KEY)
    ok(nav.AddList:IsShown(), "its +")
    local function index(label)
      for i = 1, nav.shown do if nav.Buttons[i].Text:GetText() == label then return i end end
    end
    ok(index("Weekly lockouts") < index("Loop"), "built-in lists first")
    ok(navButton(ns, "Weekly lockouts").Tag:IsShown(), "a built-in list is tagged auto")
    eq(navButton(ns, "Weekly lockouts").Tag:GetText(), "auto")
    ok(not navButton(ns, "Loop").Tag:IsShown(), "your own is not")
    lists:RunScript("OnClick", "LeftButton")
    eq(ns.db.global.collapsed[ns.UI.NAV_LISTS_KEY], true)
    eq(navButton(ns, "Loop"), nil, "collapsed: your lists hidden")
    eq(navButton(ns, "Weekly lockouts"), nil, "and the built-in ones")
    eq(heading("Lists").Text:GetText(), "+ Lists")
    heading("Lists"):RunScript("OnClick", "LeftButton")
    ok(navButton(ns, "Loop") and navButton(ns, "Weekly lockouts"), "expanded again")
    eq(ns.db.global.collapsed[ns.UI.NAV_LISTS_KEY], nil)
    eq(heading("Browse").key, ns.UI.NAV_BROWSE_KEY, "Browse collapses too")
    heading("Browse"):RunScript("OnClick", "LeftButton")
    eq(navButton(ns, "Drops"), nil, "Browse collapsed")
    heading("Browse"):RunScript("OnClick", "LeftButton")
    ok(navButton(ns, "Drops"), "and back")
  end)

  it("Built-in lists hold Daily / Weekly lockouts and Rare Spawns: a click opens Lockouts on that group", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    home(ns)
    local daily = navButton(ns, "Daily lockouts")
    ok(daily and navButton(ns, "Weekly lockouts") and navButton(ns, "Rare Spawns"), "the three groups")
    eq(daily.Badge:GetText(), "2 left", "what is left")
    daily:RunScript("OnClick", "LeftButton")
    eq(ns.UI.CurrentTab(), "checklist")
    eq(ns.db.char.checklistShow, "daily")
    ok(navButton(ns, "Daily lockouts").selected and not navButton(ns, "Lockouts").selected, "the group marked")
    navButton(ns, "Lockouts"):RunScript("OnClick", "LeftButton")
    eq(ns.db.char.checklistShow, "all", "Lockouts shows everything")
    ok(navButton(ns, "Lockouts").selected)
    -- Right-click pops the group out.
    ns.UI.ShowMenu = function(_, items) for _, it in ipairs(items) do if it.onClick then it.onClick() end end end
    navButton(ns, "Weekly lockouts"):RunScript("OnClick", "RightButton")
    ok(ns.UI.PopoutWindows["weekly|all"]:IsShown())
  end)

  it("the star favourites a list: pinned to the top of its section, saved; again unpins", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local store = ns.UI.ListsDB()
    ns.Lists.Create(store, "Alpha")
    ns.Lists.Create(store, "Beta")
    home(ns)
    local nav = ns.UI.frame.Nav
    local function order(names)
      local out = {}
      for i = 1, nav.shown do
        local t = nav.Buttons[i].Text:GetText()
        for _, n in ipairs(names) do if t == n then out[#out + 1] = t end end
      end
      return out
    end
    eq(order({ "Alpha", "Beta" }), { "Alpha", "Beta" })
    local beta = navButton(ns, "Beta")
    eq(beta.Star.favorite, false)
    beta.Star:RunScript("OnClick", "LeftButton")
    eq(order({ "Alpha", "Beta" }), { "Beta", "Alpha" }, "pinned to the top")
    ok(navButton(ns, "Beta").Star.favorite, "a filled star")
    eq(navButton(ns, "Beta").Star.Icon.atlas, ns.UI.STAR_ON)
    ok(next(ns.db.global.navFavorites), "saved")
    navButton(ns, "Weekly lockouts").Star:RunScript("OnClick", "LeftButton")
    eq(order({ "Daily lockouts", "Weekly lockouts" }), { "Weekly lockouts", "Daily lockouts" }, "quick lists too")
    navButton(ns, "Beta").Star:RunScript("OnClick", "LeftButton")
    eq(order({ "Alpha", "Beta" }), { "Alpha", "Beta" }, "unpinned")
    ok(not navButton(ns, "Lockouts").Star:IsShown(), "views have no star")
  end)

  it("Alt-drag reorders lists, quick lists and Browse; favourites stay on top; right-click pops out", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local store = ns.UI.ListsDB()
    ns.Lists.Create(store, "Alpha")
    ns.Lists.Create(store, "Beta")
    ns.Lists.Create(store, "Gamma")
    home(ns)
    local nav = ns.UI.frame.Nav
    local function order(names)
      local out = {}
      for i = 1, nav.shown do
        local t = nav.Buttons[i].Text:GetText()
        for _, n in ipairs(names) do if t == n then out[#out + 1] = t end end
      end
      return out
    end
    -- Lay the buttons out 20 px apart, top to bottom.
    local function layout()
      for i = 1, nav.shown do
        local b = nav.Buttons[i]
        b.top, b.bottom = 1000 - i * 20, 1000 - i * 20 - 20
      end
    end
    local function drag(label, onto)
      layout()
      local b, target = navButton(ns, label), navButton(ns, onto)
      IsAltKeyDown = function() return true end
      b:RunScript("OnDragStart", "LeftButton")
      IsAltKeyDown = nil
      STUB_CURSOR[2] = target.top - 2
      b:RunScript("OnDragStop")
      return b
    end
    local b = drag("Gamma", "Alpha")
    eq(order({ "Alpha", "Beta", "Gamma" }), { "Gamma", "Alpha", "Beta" })
    ok(b.justDragged, "the drop's click is swallowed")
    b:RunScript("OnMouseDown", "LeftButton")
    eq(b.justDragged, nil, "the next press clicks again")
    navButton(ns, "Alpha").Star:RunScript("OnClick", "LeftButton")
    drag("Beta", "Alpha")
    eq(order({ "Alpha", "Beta", "Gamma" }), { "Alpha", "Beta", "Gamma" }, "cannot pass the favourite")
    drag("Rare Spawns", "Daily lockouts")
    eq(order({ "Daily lockouts", "Rare Spawns" }), { "Rare Spawns", "Daily lockouts" }, "quick lists")
    drag("PvP", "Drops")
    eq(order({ "Drops", "PvP" }), { "PvP", "Drops" }, "Browse")
    ok(ns.db.global.navOrder.browse and ns.db.global.navOrder.lists, "saved")
    local without = navButton(ns, "Beta")
    IsAltKeyDown = function() return false end
    without:RunScript("OnDragStart", "LeftButton")
    IsAltKeyDown = nil
    ok(not without.dragging, "no Alt: no drag")
    local popped, menu
    ns.UI.OpenPopout = function(src) popped = src end
    ns.UI.ShowMenu = function() menu = true end
    navButton(ns, "Rare Spawns"):RunScript("OnClick", "RightButton")
    ok(popped and popped.kind, "right-click pops out")
    eq(menu, nil, "no menu")
  end)

  it("Options can hide your lists and the built-in lists from the navigation", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    ns.Lists.Create(ns.UI.ListsDB(), "Loop")
    home(ns)
    ns.db.global.settings.navHideLists = true
    ns.UI.RefreshNav()
    eq(navButton(ns, "Loop"), nil, "your lists hidden")
    ok(not ns.UI.frame.Nav.AddList:IsShown(), "and the +")
    ok(navButton(ns, "Weekly lockouts"), "the built-in lists still there")
    ns.db.global.settings.navHideQuick = true
    ns.UI.RefreshNav()
    eq(navButton(ns, "Weekly lockouts"), nil, "built-in lists hidden")
    ok(navButton(ns, "Drops"), "Browse stays")
  end)

  it("right-click a list entry pops it out, Shift-right-click opens its menu; + starts a list", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local store = ns.UI.ListsDB()
    local id = ns.Lists.Create(store, "Loop")
    home(ns)
    local menuFor, popped
    ns.UI.ShowCustomListMenu = function(listID) menuFor = listID end
    ns.UI.OpenPopout = function(src) popped = src end
    navButton(ns, "Loop"):RunScript("OnClick", "RightButton")
    eq(menuFor, nil)
    eq(popped and popped.list, id, "right-click pops it out")
    IsShiftKeyDown = function() return true end
    navButton(ns, "Loop"):RunScript("OnClick", "RightButton")
    IsShiftKeyDown = nil
    eq(menuFor, id, "Shift-right-click: rename / delete")
    local asked = 0
    ns.UI.NewListPrompt = function() asked = asked + 1 end
    local items
    ns.UI.ShowMenu = function(_, list) items = list end
    ns.UI.frame.Nav.AddList:RunScript("OnClick", "LeftButton")
    local by = {}
    for _, it in ipairs(items or {}) do if it.text then by[it.text] = it end end
    ok(by["Import list..."], "+ also imports")
    by["New list..."].onClick()
    eq(asked, 1)
  end)
end)

describe("Browse in the navigation column", function()
  it("Drops opens a browse page by expansion; Achievements opens its own view; the choice is saved", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    ns.ToggleWindow()
    local nav = ns.UI.frame.Nav
    local function button(label)
      for i = 1, nav.shown do
        local b = nav.Buttons[i]
        if b.Text:GetText() == label then return b end
      end
    end
    button("Drops"):RunScript("OnClick", "LeftButton")
    eq(ns.UI.CurrentTab(), "browse")
    local page = ns.UI.frame.Contents.browse.children[2]
    eq(page.Title:GetText(), "Drops")
    local rows = page.List.ScrollBox.provider.rows
    ok(#rows > 0 and rows[1].header, "headers")
    ok(button("Drops").selected, "Drops marked")
    -- The home page's fuzzy search: "tbc" keeps the Burning Crusade's drops.
    page.List.searchText = "tbc"
    page.List:Refresh()
    local exps, mounts = {}, 0
    for _, r in ipairs(page.List.ScrollBox.provider.rows) do
      if r.header and (r.depth or 1) == 1 then exps[#exps + 1] = r.text end
      if not r.header then mounts = mounts + 1 end
    end
    eq(exps, { "The Burning Crusade" }, "tbc: only TBC drops")
    page.List.searchText = ""
    page.List:Refresh()
    button("Professions"):RunScript("OnClick", "LeftButton")
    eq(page.Title:GetText(), "Professions")
    eq(ns.db.global.window.browse, "professions")
    ok(button("Professions").selected and not button("Drops").selected)
    button("Achievements"):RunScript("OnClick", "LeftButton")
    eq(ns.UI.CurrentTab(), "achievements", "its own view")
    ok(button("Achievements").selected)
  end)
end)

describe("refresh cost", function()
  it("one Checklist build per ns.Refresh, fresh again after it", function()
    local ns = loadUI()
    local calls = 0
    local old = ns.Checklist.Build
    ns.Checklist.Build = function(...) calls = calls + 1 return old(...) end
    ns.ToggleWindow()
    ns.UI.SelectTab("checklist")
    calls = 0
    ns.Refresh()
    eq(calls, 1, "view and navigation share it")
    ns.UI.ChecklistBuild(ns.Game.Now())
    eq(calls, 2, "outside a refresh: built anew")
  end)

  it("game events in one frame refresh once (ns.RefreshSoon)", function()
    local ns = loadUI()
    local timers, n = {}, 0
    C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
    local old = ns.Refresh
    ns.Refresh = function() n = n + 1 end
    ns.RefreshSoon()
    ns.RefreshSoon()
    ns.RefreshSoon()
    eq(#timers, 1)
    timers[1]()
    eq(n, 1)
    ns.RefreshSoon()
    eq(#timers, 2, "a later burst schedules again")
    C_Timer = nil
    ns.Refresh = old
  end)

  it("the search pages share one cache, dropped when the window closes", function()
    local ns = loadUI()
    ns.ToggleWindow()
    ns.UI.SearchMatches({ 1, 2 }, "alpha")
    ok(next(ns.UI.SearchCache()), "filled")
    ns.ToggleWindow()
    eq(next(ns.UI.SearchCache()), nil, "closed: emptied")
  end)
end)

describe("example lists", function()
  it("Mythic Mounts arrives once in My lists, as the player's own list", function()
    local ns = load_addon({ "Core/Locale.lua", "Data/Mounts.lua", "Data/Lockouts.lua", "Logic/Lists.lua", "Logic/QuickLists.lua" })
    local global, store = {}, {}
    local made = ns.QuickLists.SeedExamples(global, store)
    eq(#made, 1)
    local l = ns.Lists.Get(store, made[1])
    eq(l.name, "Mythic Mounts")
    eq(l.mounts, ns.QuickLists.Mounts("mythic"), "the mythic dungeon mounts")
    ok(#l.mounts > 0)
    ns.Lists.Delete(store, made[1])
    eq(#ns.QuickLists.SeedExamples(global, store), 0, "deleted: not given again")
    local other = {}
    local store2 = { lists = { [1] = { name = "Mythic Mounts", mounts = {} } }, nextID = 2 }
    eq(#ns.QuickLists.SeedExamples(other, store2), 0, "a list by that name already: left alone")
    eq(#ns.QuickLists.LISTS, 0, "no longer a quick list")
    ok(ns.QuickLists.Get("mythic"), "still found by key (old pop-outs)")
  end)
end)

describe("Show completed", function()
  it("Lockouts' Filter menu has Show completed; reset turns it off", function()
    local ns = loadUI()
    local items = ns.UI.ChecklistFilterItems({})
    eq(items[1].label, "Show completed")
    eq(items[1].checked, false)
    eq(items[2].kind, "divider")
    ns.UI.SetChecklistShowDone(true)
    eq(ns.db.global.settings.checklistShowDone, true)
    eq(ns.UI.ChecklistFilterItems({})[1].checked, true)
    local filters = {}
    ns.UI.ApplyChecklistFilterAction(filters, "uncheckAll")
    eq(ns.UI.ChecklistShowDone(), true, "Uncheck all is about categories only")
  end)

  it("a pop-out's menu toggles its done rows", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    ns.UI.OpenPopout({ kind = "daily", all = true })
    local w = ns.UI.PopoutWindows["daily|all"]
    eq(#w.rows, 2)
    local items
    ns.UI.ShowMenu = function(_, list) items = type(list) == "function" and list() or list end
    ns.UI.ShowPopoutStyleMenu(w, w)
    local item
    for _, it in ipairs(items) do if it.text == "Show completed" then item = it end end
    eq(item.checked, false)
    item.onClick()
    eq(#w.rows, 3)
    eq(ns.db.global.popouts["daily|all"].showDone, true)
  end)
end)

describe("adding and removing a mount from your lists", function()
  it("the pane's button counts your lists; on a list's page Move up / down and Remove come first", function()
    local ns = loadUI()
    local store = ns.UI.ListsDB()
    local id = ns.Lists.Create(store, "Loop")
    local pane = ns.UI.CreateDetailPane(UIParent)
    pane:SetMount(614)
    eq(pane.AddList.Text:GetText(), "+ List")
    ns.Lists.Add(store, id, 614)
    pane:Refresh()
    eq(pane.AddList.Text:GetText(), "Lists (1)")
    local items
    ns.UI.ShowMenu = function(_, list) items = type(list) == "function" and list() or list end
    ns.UI.CurrentListPage = function() return { kind = "list", list = id } end
    ns.Lists.Add(store, id, 1)
    ns.UI.ShowListMenu(pane.AddList, 614)
    eq({ items[2].text, items[3].text, items[4].text }, { "Move up", "Move down", "Remove from Loop" },
      "on its list's page: move it, or take it off")
    items[3].onClick()
    eq(store.lists[id].mounts, { 1, 614 }, "moved down")
    items[2].onClick()
    eq(store.lists[id].mounts, { 614, 1 }, "and up again")
    items[4].onClick()
    eq(ns.Lists.Has(store, id, 614), false)
    ns.UI.ShowListMenu(pane.AddList, 614)
    eq(items[2].text, "Loop", "not on it: just the lists to tick")
    eq(items[2].checked, false)
  end)
end)

describe("the Appearance menu on other windows", function()
  it("Show completed is a pop-out's own; other styled windows get the rest", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    local items
    ns.UI.ShowMenu = function(_, list) items = type(list) == "function" and list() or list end
    local other = CreateFrame("Frame", nil, UIParent)
    other.key = "guide"
    ns.UI.ShowPopoutStyleMenu(other, other)
    local texts = {}
    for _, it in ipairs(items) do if it.text then texts[it.text] = true end end
    ok(not texts["Show completed"], "not on the guide window")
    ok(texts["Background colour"] and texts["Reset appearance"], "the rest is there")
    ns.UI.OpenPopout({ kind = "daily", all = true })
    ns.UI.ShowPopoutStyleMenu(ns.UI.PopoutWindows["daily|all"], other)
    local found
    for _, it in ipairs(items) do if it.text == "Show completed" then found = true end end
    ok(found, "still on a pop-out")
  end)
end)

describe("header and text colours stay apart", function()
  local RED, BLUE = { 1, 0, 0 }, { 0, 0, 1 }
  local function same(a, b) return a and b and a[1] == b[1] and a[2] == b[2] and a[3] == b[3] end

  it("a pop-out: Text colours the rows only, Header the title and group headers only", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    ns.db.global.popoutStyle = { text = RED }
    ns.UI.OpenPopout({ kind = "daily", all = true })
    local w = ns.UI.PopoutWindows["daily|all"]
    ok(same(w.rowFrames[1].Name.textColor, RED), "the rows take the Text colour")
    ok(not same(w.Title.textColor, RED), "the title does not")
    local h = w.groupFrames[1]
    ok(not h or not same(h.Text.textColor, RED), "nor a group header")
    ns.db.global.popoutStyle = { text = RED, header = BLUE }
    ns.UI.RefreshPopouts()
    ok(same(w.Title.textColor, BLUE), "Header colours the title")
    ok(not h or same(h.Text.textColor, BLUE), "and a group header")
    ok(same(w.rowFrames[1].Name.textColor, RED), "the rows keep the Text colour")
  end)

  it("the shared helper never gives a header the Text colour", function()
    local ns = loadUI()
    local fs = UIParent:CreateFontString()
    ns.UI.PopoutStyleHeader(fs, ns.UI.PopoutStyle({ text = RED }), "GameFontNormal", 0)
    ok(not same(fs.textColor, RED), "Default header: the font's own colour, not Text")
    ns.UI.PopoutStyleHeader(fs, ns.UI.PopoutStyle({ text = RED }), "GameFontNormal", 0, { 0.5, 0.5, 0.5 })
    ok(same(fs.textColor, { 0.5, 0.5, 0.5 }), "or the header's own fallback")
    ns.UI.PopoutStyleHeader(fs, ns.UI.PopoutStyle({ text = RED, header = BLUE }), "GameFontNormal", 0)
    ok(same(fs.textColor, BLUE))
  end)
end)

describe("menus fit their text", function()
  it("a long line widens the menu; one past the cap wraps onto more rows", function()
    local ns = loadUI()
    local oldW, oldH = RegionMT.GetStringWidth, RegionMT.GetStringHeight
    RegionMT.GetStringWidth = function(self) return #(self.text or "") * 6 end
    RegionMT.GetStringHeight = function(self)
      local w = self.width and self.width > 0 and self.width or math.huge
      return math.ceil((#(self.text or "") * 6) / w) * 12
    end
    local owner = CreateFrame("Button", nil, UIParent)
    local menu = ns.UI.ShowMenu(owner, { { title = "Short" }, { text = "Go" } })
    eq(menu.width, 190, "short items: the usual width")
    menu = ns.UI.ShowMenu(owner, { { title = "T" }, { text = string.rep("x", 40), disabled = true } })
    eq(menu.width, 240 + 9 + 22, "fits the longest line")
    menu = ns.UI.ShowMenu(owner, { { title = "T" }, { text = string.rep("x", 100), disabled = true } })
    eq(menu.width, 340, "no wider than the cap")
    ok(menu.items[2].height > 18, "the long line wraps onto more rows")
    RegionMT.GetStringWidth, RegionMT.GetStringHeight = oldW, oldH
  end)
end)
