-- Pop-out rare tracker (UI/RareTracker.lua): rows from the Checklist's rare
-- entries for one expansion or the current zone, the camp box, waypoint
-- buttons, coordinate buttons, the expansion menu, saved state.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/DetailPane.lua",
  "UI/Tabs.lua", "UI/LockoutHelpers.lua", "UI/ChecklistView.lua", "UI/RareTracker.lua", "UI/ZonePanel.lua" }

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
  for _, name in ipairs({ "SetMaxLines", "EnableMouseWheel", "SetAlpha" }) do
    RegionMT[name] = RegionMT[name] or function() end
  end
  FrameMT.SetScrollChild = FrameMT.SetScrollChild or function(self, child) self.scrollChild = child end
  FrameMT.SetVerticalScroll = FrameMT.SetVerticalScroll or function(self, v) self.vscroll = v end
  FrameMT.GetVerticalScroll = FrameMT.GetVerticalScroll or function(self) return self.vscroll or 0 end
end

local function loadUI()
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  local stubGame = {
    MountInfo = function() return nil end,
    IsOwned = function() return false end,
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
  return ns
end

-- A Checklist.Build-shaped fixture.
local function built()
  local wod = "Warlords of Draenor"
  return {
    daily = {
      { key = "614", id = 614, m = { name = "Mottled Meadowstomper", exp = wod }, exp = wod, category = "rares", done = false },
      { key = "9", id = 9, m = { name = "Raid mount", exp = wod }, exp = wod, category = "raids", done = false },
      { key = "636", id = 636, m = { name = "Swift Breezestrider", exp = wod }, exp = wod, category = "rares", done = true },
    },
    weekly = {},
    camp = {
      { key = "657", id = 657, m = { name = "Garn Nighthowl", exp = wod }, exp = wod, category = "camp", reset = "camp", zone = "Frostfire Ridge", done = false },
      { key = "1", id = 1, m = { name = "Old rare", exp = "Classic" }, exp = "Classic", category = "camp", reset = "camp", done = false },
    },
  }
end

local SPOTS = {
  [614] = { { npc = 50981, name = "Luk'hok", kind = "drop", pts = { 550, 67.6, 42.6, 550, 72.8, 53.4 } } },
  [657] = { { npc = 81001, name = "Nok-Karosh", kind = "drop", pts = { 525, 13.1, 50.4 } } },
}

describe("rare tracker helpers", function()
  it("expansions with rare entries, in expansion order", function()
    local ns = loadUI()
    eq(ns.UI.RareTrackerExpansions(built()), { "Classic", "Warlords of Draenor" })
  end)

  it("rows: the expansion's rares and rare spawns, open first, named after the rare", function()
    local ns = loadUI()
    ns.Data.Spots, ns.Data.SpotsExtra = SPOTS, {}
    local rows, left = ns.UI.RareTrackerRows(built(), "Warlords of Draenor", nil, { ["657"] = 1699990000 })
    local names = {}
    for i, r in ipairs(rows) do names[i] = r.name end
    eq(names, { "Luk'hok", "Nok-Karosh", "Swift Breezestrider" })
    eq(left, 2)
    eq(rows[1].zone, "Nagrand")
    eq(rows[2].zone, "Frostfire Ridge")
    eq(rows[2].camp, true)
    eq(rows[2].checked, 1699990000)
    eq(rows[3].done, true)
  end)

  it("Current zone: only the player's zone's mounts", function()
    local ns = loadUI()
    local rows = ns.UI.RareTrackerRows(built(), "zone", { [657] = true })
    eq(#rows, 1)
    eq(rows[1].id, 657)
    eq(#ns.UI.RareTrackerRows(built(), "zone", nil), 0)
  end)
end)

describe("rare tracker window", function()
  local function open(ns)
    ns.Data.Spots, ns.Data.SpotsExtra = SPOTS, {}
    ns.UI.ChecklistBuild = function() return built() end
    ns.db.global.rareTracker = { exp = "Warlords of Draenor" }
    eq(ns.UI.ToggleRareTracker(), true)
    return ns.UI.rareTracker
  end

  it("opens with the expansion's rares; title counts what is left; saved open", function()
    local ns = loadUI()
    local f = open(ns)
    ok(f:IsShown())
    ok(f.Title:GetText():find("^Warlords of Draenor rare spawns"), f.Title:GetText())
    ok(f.Title:GetText():find("(2 left)", 1, true))
    eq(ns.db.global.rareTracker.open, true)
    eq(#f.rows, 3)
    eq(ns.UI.ToggleRareTracker(), false)
    eq(ns.db.global.rareTracker.open, false)
  end)

  it("-> sets the nearest-spawn waypoint; coordinate buttons for several spawn points", function()
    local ns = loadUI()
    local f = open(ns)
    local calls = {}
    ns.Map.SetWaypoint = function(id) calls[#calls + 1] = "wp" .. id end
    ns.Map.SetWaypointAt = function(m, x, y, name) calls[#calls + 1] = string.format("%d %.1f %.1f %s", m, x, y, name) end
    local first
    for _, c in ipairs(f.Content.children) do
      if c.data and c.data.id == 614 then first = c end
    end
    first.Go:RunScript("OnClick", "RightButton") -- the nearest only
    local buttons = {}
    for _, c in ipairs(f.Content.children) do
      if c.Text and c.m and c:IsShown() then buttons[#buttons + 1] = c end
    end
    eq(#buttons, 2, "Luk'hok's two points; Nok-Karosh has one (the -> button)")
    buttons[2]:RunScript("OnClick", "LeftButton")
    eq(calls, { "wp614", "550 72.8 53.4 Luk'hok" })
  end)

  it("left-click on a rare (row or pin) plots all its spawns; one spot: the waypoint; Plot all", function()
    local ns = loadUI()
    local f = open(ns)
    local plots, waypoints = {}, {}
    ns.Map.PlotMounts = function(ids, label) plots[#plots + 1] = { table.concat(ids, ","), label } end
    ns.Map.SetWaypoint = function(id) waypoints[#waypoints + 1] = id end
    local luk, nok
    for _, c in ipairs(f.Content.children) do
      if c.data and c.data.id == 614 then luk = c end
      if c.data and c.data.id == 657 then nok = c end
    end
    luk:RunScript("OnClick", "LeftButton")
    eq(plots[1], { "614", "Luk'hok" }, "the row")
    luk.Go:RunScript("OnClick", "LeftButton")
    eq(#plots, 2, "the pin")
    nok:RunScript("OnClick", "LeftButton")
    eq(waypoints, { 657 }, "a single spot: the waypoint")
    luk.Go:RunScript("OnClick", "RightButton")
    eq(waypoints, { 657, 614 }, "right-click: the nearest only")
    plots = { plots[1] }
    f.PlotAll:RunScript("OnClick", "LeftButton")
    eq(plots[2][1], "614,657", "open rows only, in list order")
  end)

  it("a rare spawn's box marks it checked; the done daily is ticked and dimmed", function()
    local ns = loadUI()
    local f = open(ns)
    local camp, done
    for _, c in ipairs(f.Content.children) do
      if c.data and c.data.id == 657 then camp = c end
      if c.data and c.data.id == 636 then done = c end
    end
    eq(camp.Check.enabled, true)
    camp.Check:RunScript("OnClick", "LeftButton")
    eq(ns.db.char.campChecked["657"], 1700000000)
    eq(done.Check.checked, true)
    eq(done.Check.enabled, false)
    ok(not done.Go:IsShown(), "no waypoint button on a done row")
  end)

  it("without the menu API the title steps through Current zone and the expansions", function()
    local ns = loadUI()
    local f = open(ns)
    MenuUtil = nil
    f.Strip:RunScript("OnClick", "LeftButton")
    eq(ns.db.global.rareTracker.exp, "zone")
    f.Strip:RunScript("OnClick", "LeftButton")
    eq(ns.db.global.rareTracker.exp, "Classic")
  end)

  it("OpenRareTracker shows the given expansion", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    ns.db.global.rareTracker = { exp = "Midnight" }
    eq(ns.UI.OpenRareTracker("Warlords of Draenor"), true)
    eq(ns.db.global.rareTracker.exp, "Warlords of Draenor")
    ok(ns.UI.rareTracker.Title:GetText():find("^Warlords of Draenor"), ns.UI.rareTracker.Title:GetText())
  end)

  it("comes back after /reload when it was open", function()
    local ns = loadUI()
    ns.UI.ChecklistBuild = function() return built() end
    ns.db.global.rareTracker = { open = true, exp = "Classic" }
    fire_frame_event("PLAYER_LOGIN")
    ok(ns.UI.rareTracker and ns.UI.rareTracker:IsShown(), "reopened")
  end)
end)
