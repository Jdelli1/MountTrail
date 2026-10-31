-- World map side tab (UI/MapTab.lua): where the tab goes in the column of
-- side tabs, what the panel lists for the viewed map, and the build under a
-- fake Map & Quest Log (QuestMapFrame / WorldMapFrame).

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/ZonePanel.lua", "UI/MapTab.lua" }

-- Widget methods the tab and panel call that the base stub lacks.
local probe = CreateFrame("Frame")
local FrameMT = getmetatable(probe)
local RegionMT = getmetatable(FrameMT).__index
local function noop() end
for _, name in ipairs({ "SetTexCoord", "SetJustifyH", "SetWordWrap", "SetDesaturated", "SetAlpha",
  "AddMaskTexture", "SetVertexColor", "SetTextColor", "SetDrawLayer" }) do
  RegionMT[name] = RegionMT[name] or noop
end
function RegionMT:GetWidth() return self.width or 0 end
function RegionMT:GetHeight() return self.height or 0 end
function RegionMT:GetBottom() return self.bottom end
function FrameMT:CreateMaskTexture() return self:CreateTexture(nil, "ARTWORK") end
function FrameMT:GetChildren()
  local out = {}
  for _, c in ipairs(self.children) do
    if c.kind ~= "Texture" and c.kind ~= "FontString" then out[#out + 1] = c end
  end
  return unpack(out)
end
function CreateScrollBoxListLinearView()
  local view = {}
  function view:SetElementExtentCalculator(fn) self.extent = fn end
  function view:SetElementFactory(fn) self.factory = fn end
  return view
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, bar, view) box.view = view end }
function FrameMT:SetDataProvider(provider) self.provider = provider end
function CreateDataProvider(rows) return { rows = rows } end

local MAPS = {
  [12] = { name = "Kalimdor", mapType = 2 },
  [249] = { name = "Uldum", mapType = 3, parentMapID = 12 },
  [71] = { name = "Tanaris", mapType = 3, parentMapID = 12 },
}

-- A fake side tab: shown, 43 x 55, left edge 10, bottom `bottom`.
local function sideTab(parent, bottom, mode)
  local t = CreateFrame("Frame", nil, parent)
  t.width, t.height, t.left, t.bottom = 43, 55, 10, bottom
  t.displayMode = mode
  function t:SetChecked(on) self.checked = on end
  return t
end

local hooks
local function loadUI(withMap)
  reset_ui_stub()
  hooks = { secure = {}, registry = {} }
  function hooksecurefunc(a, b, c)
    if type(a) == "string" then hooks.secure[a] = b else hooks.secure[b] = c end
  end
  EventRegistry = { RegisterCallback = function(_, event, fn) hooks.registry[event] = fn end }
  QuestMapFrame, WorldMapFrame = nil, nil
  STUB_TEMPLATES.LargeSideTabButtonTemplate = true
  STUB_TEMPLATE_METHODS.LargeSideTabButtonTemplate = {
    SetCustomOnMouseUpHandler = function(self, fn) self.customMouseUpHandler = fn end,
  }
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  local game = {
    MountInfo = function() return nil end,
    IsOwned = function() return false end,
    Exists = function() return true end,
    Faction = function() return "Alliance" end,
    MountSourceText = function() return "" end,
    MapName = function(id) return MAPS[id] and MAPS[id].name end,
    MapInfo = function(id) return MAPS[id] end,
    PlayerMap = function() return 71 end,
    DungeonEntrances = function() return {} end,
    MapChildren = function() return {} end,
    InstanceForMap = function() return nil end,
    JournalInstanceName = function() return nil end,
    CurrentInstanceName = function() return "Somewhere else" end,
  }
  for k, v in pairs(game) do ns.Game[k] = v end
  ns.Data.Mounts = {
    [1] = { name = "Uldum rare", tab = "journal", section = "world", coords = { m = 249 } },
    [2] = { name = "Tanaris rare", tab = "journal", section = "world", coords = { m = 71 } },
  }
  ns.Data.Holidays = {}
  ns.Data.Route = {}
  if withMap then
    local qmf = CreateFrame("Frame", "QuestMapFrame", UIParent)
    qmf.displayMode = 1
    qmf.QuestsTab = sideTab(qmf, 500, 1)
    qmf.EventsTab = sideTab(qmf, 440, 2)
    qmf.MapLegendTab = sideTab(qmf, 380, 3)
    qmf.TabButtons = { qmf.QuestsTab, qmf.EventsTab, qmf.MapLegendTab }
    qmf.ContentsAnchor = CreateFrame("Frame", nil, qmf)
    function qmf:ValidateTabs() end
    local map = CreateFrame("Frame", "WorldMapFrame", UIParent)
    map.mapID = 249
    function map:GetMapID() return self.mapID end
    function map:OnMapChanged() end
  end
  return ns
end

describe("world map tab", function()
  it("MapTabAnchor: under the lowest side tab in the column, never under one hanging from ours", function()
    local ns = loadUI()
    local parent = CreateFrame("Frame")
    local last = sideTab(parent, 380)
    local mine = sideTab(parent, 320)
    local other = sideTab(parent, 320)  -- another add-on's tab
    local hanging = sideTab(parent, 260) -- hangs below ours
    hanging:SetPoint("TOP", mine, "BOTTOM", 0, -3)
    local wide = sideTab(parent, 100)
    wide.width = 300 -- not a side tab
    local hidden = sideTab(parent, 50)
    hidden:Hide()
    local A = ns.UI.MapTabAnchor
    eq(A({ last, mine, other, hanging, wide, hidden }, last, mine, 43, 55), other)
    eq(A({ last, mine }, last, mine, 43, 55), last, "only Blizzard's tabs")
    last.bottom = nil
    eq(A({ last, other }, last, mine, 43, 55), last, "nothing laid out yet")
  end)

  it("MapTabContent lists the viewed zone's mounts; a continent asks for a zone", function()
    local ns = loadUI()
    local rows, title, empty = ns.UI.MapTabContent(249)
    eq(#rows, 1)
    eq(rows[1].id, 1)
    ok(title:find("Uldum", 1, true), title)
    eq(empty, "Nothing left to collect here")
    rows, title, empty = ns.UI.MapTabContent(12)
    eq(#rows, 0)
    ok(title:find("Kalimdor", 1, true), title)
    eq(empty, "Open a zone on the map to see its mounts")
    rows, title, empty = ns.UI.MapTabContent(nil)
    eq(#rows, 0)
    eq(empty, "Open a zone on the map to see its mounts")
  end)

  it("builds nothing without the quest map or the side-tab template", function()
    local ns = loadUI()
    eq(ns.UI.BuildMapTab(), false, "no QuestMapFrame")
    local ns2 = loadUI(true)
    STUB_TEMPLATES.LargeSideTabButtonTemplate = nil
    eq(ns2.UI.BuildMapTab(), false, "no template")
    eq(ns2.UI.mapTab, nil)
  end)

  it("adds a tab under Map Legend; selecting it covers the quest log with the viewed zone's mounts", function()
    local ns = loadUI(true)
    eq(ns.UI.BuildMapTab(), true)
    local tab, panel = ns.UI.mapTab, ns.UI.mapPanel
    eq(tab.template, "LargeSideTabButtonTemplate")
    local point, rel, relPoint = tab:GetPoint(1)
    eq({ point, relPoint }, { "TOP", "BOTTOM" })
    eq(rel, QuestMapFrame.MapLegendTab)
    eq(tab.Icon.texture, 132261)
    ok(not panel:IsShown(), "not selected at first")
    ok(hooks.secure.ValidateTabs and hooks.secure.OnMapChanged, "hooks tab validation and map changes")

    tab.customMouseUpHandler(tab, "LeftButton", true)
    ok(panel:IsShown(), "panel shown")
    eq(ns.db.global.mapTab.selected, true, "saved")
    ok(tab.SelectedTexture == nil or tab.SelectedTexture:IsShown())
    for _, t in ipairs(QuestMapFrame.TabButtons) do eq(t.checked, false, "Blizzard tab unchecked") end
    eq(QuestMapFrame.displayMode, 1, "Blizzard's mode untouched")
    ok(panel.Title:GetText():find("Uldum", 1, true), "viewed map, not the player's")
    eq(#panel.ScrollBox.provider.rows, 1)
    -- The map tab's rows show the mount's icon before the expansion tag.
    local data = panel.ScrollBox.provider.rows[1]
    local row = CreateFrame("Button")
    local savedInfo = ns.Game.MountInfo
    ns.Game.MountInfo = function(id) return "Mount " .. id, 1000 + id end
    panel.ScrollBox.view.factory(function(_, init) init(row, data) end, data)
    ns.Game.MountInfo = savedInfo
    ok(row.Icon and row.Icon:IsShown(), "the mount's icon")
    eq(row.Icon.texture, 1000 + data.id)

    WorldMapFrame.mapID = 71
    hooks.secure.OnMapChanged()
    ok(panel.Title:GetText():find("Tanaris", 1, true), "follows the map")
    eq(panel.ScrollBox.provider.rows[1].id, 2)
  end)

  it("a Blizzard tab click, a mode change or quest details uncover the quest log", function()
    local ns = loadUI(true)
    ns.UI.BuildMapTab()
    local tab, panel = ns.UI.mapTab, ns.UI.mapPanel
    tab.customMouseUpHandler(tab, "LeftButton", true)
    QuestMapFrame.QuestsTab:RunScript("OnMouseUp", "LeftButton", true)
    ok(not panel:IsShown(), "Quests tab click")
    eq(ns.db.global.mapTab.selected, false)
    eq(QuestMapFrame.QuestsTab.checked, true, "Blizzard's current tab checked again")
    eq(QuestMapFrame.EventsTab.checked, false)

    tab.customMouseUpHandler(tab, "LeftButton", true)
    hooks.registry["QuestLog.SetDisplayMode"]()
    ok(not panel:IsShown(), "mode change")

    tab.customMouseUpHandler(tab, "LeftButton", true)
    tab.customMouseUpHandler(tab, "RightButton", true)
    ok(panel:IsShown(), "right-click changes nothing")
  end)

  it("comes back selected when the map opens again", function()
    local ns = loadUI(true)
    ns.db.global.mapTab = { selected = true }
    ns.UI.BuildMapTab()
    ok(ns.UI.mapPanel:IsShown(), "selected from the saved state")
    ns.UI.SelectMapTab(false)
    ns.db.global.mapTab.selected = true
    QuestMapFrame:RunScript("OnShow")
    ok(ns.UI.mapPanel:IsShown(), "OnShow re-applies it")
  end)

  it("MapTabContent groups mounts by source under collapsible headers, with their own keys", function()
    local ns = loadUI()
    ns.UI.ZoneMounts = function()
      return {
        { id = 1, m = { name = "A", section = "vendor" } },
        { id = 2, m = { name = "B", section = "vendor" } },
        { id = 3, m = { name = "C", section = "world" } },
      }, { name = "Eversong Woods" }
    end
    local rows, title = ns.UI.MapTabContent(249)
    local headers = {}
    for _, r in ipairs(rows) do if r.header then headers[#headers + 1] = r.key end end
    eq(#headers, 2, "one header per source")
    ok(headers[1]:find("^maptab|"), headers[1])
    ok(title:find("(3)", 1, true), "the title counts mounts, not rows: " .. title)
    local under, inFirst = 0, false
    for _, r in ipairs(rows) do
      if r.header then inFirst = r.key == headers[1] elseif inFirst then under = under + 1 end
    end
    ns.db.global.collapsed = { [headers[1]] = true }
    local collapsed = ns.UI.MapTabContent(249)
    eq(#collapsed, #rows - under, "a collapsed source hides its mounts")
    eq(ns.UI.ZoneGroupedRows(ns.UI.ZoneMounts(), {})[1].key:find("^zonepanel|") ~= nil, true,
      "the zone panel keeps its own keys")
  end)
end)
