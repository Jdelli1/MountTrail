-- Mount detail pane (UI/DetailPane.lua) in a mount list (UI.List): a plain
-- left-click selects a row and the pane shows it (model, name, flavor, the
-- tooltip's lines without hints, buttons); modifier clicks keep their
-- actions; the first row is selected when nothing is.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/DetailPane.lua" }

local probe = CreateFrame("Frame")
local FrameMT = getmetatable(probe)
local RegionMT = getmetatable(FrameMT).__index
local function noop() end
for _, name in ipairs({ "SetTexCoord", "SetJustifyH", "SetWordWrap", "SetDesaturated", "SetTextColor",
  "SetStatusBarTexture", "SetDrawLayer", "SetRotation", "AddMaskTexture", "SetVertexColor", "SetMaxLines",
  "SetFontObject", "SetAutoFocus", "LockHighlight", "UnlockHighlight", "EnableMouseWheel" }) do
  RegionMT[name] = RegionMT[name] or noop
end
function RegionMT:GetStringHeight() return 12 end
function RegionMT:GetStringWidth() return 60 end
function RegionMT:GetWidth() return self.width or 0 end
function RegionMT:GetHeight() return self.height or 0 end
function FrameMT:SetEnabled(on) self.enabled = on end
function FrameMT:SetChecked(on) self.checked = on end
function FrameMT:GetChecked() return self.checked end
function FrameMT:CreateMaskTexture() return self:CreateTexture(nil, "ARTWORK") end
function FrameMT:SetDataProvider(provider) self.provider = provider end
function FrameMT:SetScrollChild(child) self.scrollChild = child end
function FrameMT:SetVerticalScroll(v) self.vscroll = v end
function FrameMT:GetVerticalScroll() return self.vscroll or 0 end
function FrameMT:IsMouseOver() return false end
function CreateScrollBoxListLinearView()
  local view = {}
  function view:SetElementExtentCalculator(fn) self.extent = fn end
  function view:SetElementFactory(fn) self.factory = fn end
  return view
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, bar, view) box.view = view end }
function CreateDataProvider(rows) return { rows = rows } end
GameFontHighlightSmall = { name = "GameFontHighlightSmall" }
function CreateFont(name)
  local font = { name = name }
  function font:SetFontObject(base) self.base = base end
  function font:SetTextColor(r, g, b) self.color = { r, g, b } end
  _G[name] = font
  return font
end
MenuResponse = { Refresh = 2 }
STUB_TEMPLATE_METHODS.WowStyle1FilterDropdownTemplate = {
  SetupMenu = function(self, generator) self.generator = generator end,
  SetDefaultCallback = function(self, fn) self.defaultCallback = fn end,
  SetIsDefaultCallback = function(self, fn) self.isDefaultCallback = fn end,
  ValidateResetState = noop,
}

-- The Mount Journal's preview pieces, recording what they are asked.
local scenes
local function installModelStubs(withTemplate)
  scenes = {}
  STUB_TEMPLATES.WrappedAndUnwrappedModelScene = withTemplate and true or nil
  STUB_TEMPLATES.ModelSceneControlFrameTemplate = withTemplate and true or nil
  STUB_TEMPLATE_METHODS.WrappedAndUnwrappedModelScene = {
    TransitionToModelSceneID = function(self, id) self.sceneID = id; scenes[#scenes + 1] = self end,
    GetActorByTag = function(self, tag)
      self.actor = self.actor or {
        SetModelByCreatureDisplayID = function(a, id) a.displayID = id end,
        SetAnimation = function(a, anim) a.anim = anim end,
        Hide = noop, Show = noop,
      }
      return tag == "unwrapped" and self.actor or nil
    end,
    AttachPlayerToMount = function(self, actor, animID, isSelf, noRider) self.noRider = noRider end,
    PrepareForFanfare = function(self, needs) self.fanfare = needs end,
  }
  C_MountJournal = {
    GetMountInfoExtraByID = function(id)
      if id == 2 then return nil end -- no model
      return 1000 + id, "flavor " .. id, "", false, 0, 7, 0, 0, false
    end,
  }
  GetCVarBool = function() return false end
end

local function loadUI(withTemplate)
  reset_ui_stub()
  installModelStubs(withTemplate ~= false)
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  local game = {
    MountInfo = function(id) return ({ "Alpha", "Beta", "Gamma" })[id] end,
    IsOwned = function(id) return id == 3 end,
    Exists = function() return true end,
    Faction = function() return "Alliance" end,
    MountSourceText = function() return "|cFFFFD200Vendor:|r Someone|n|cFFFFD200Zone:|r Dalaran" end,
    MountDescription = function(id) return "flavor of " .. id end,
    SavedRows = function() return {} end,
    IsQuestDone = function() return false end,
    IsLfgDone = function() return false end,
    Now = function() return 1700000000 end,
    PlayerName = function() return "Tester" end,
  }
  for k, v in pairs(game) do ns.Game[k] = v end
  ns.Data.Mounts = {
    [1] = { name = "Alpha", tab = "misc", section = "shop", coords = { m = 125 } },
    [2] = { name = "Beta", tab = "misc", section = "shop" },
    [3] = { name = "Gamma", tab = "misc", section = "shop" },
  }
  ns.Data.Holidays = {}
  ns.Data.Route = {}
  ns.Data.Spots = {
    [1] = { { npc = 50981, name = "Luk'hok", kind = "drop", daily = true,
      pts = { 550, 67.6, 42.6, 550, 72.8, 53.4, 107, 1, 2 } } },
    [3] = { { npc = 1, name = "Horde Vendor", kind = "vendor", faction = "Horde", pts = { 85, 5, 5 } } },
  }
  ns.Data.SpotsExtra = {}
  ns.Game.MapName = function(m) return ({ [550] = "Nagrand", [107] = "Old Nagrand" })[m] end
  ns.db.global.filters.collected = true
  return ns
end

local function makeList(ns)
  local parent = CreateFrame("Frame", nil, UIParent)
  local list = ns.UI.List(parent, function() return { view = "misc" } end)
  list:Refresh(true)
  return list
end

local function mountRows(list)
  local out = {}
  for _, row in ipairs(list.ScrollBox.provider.rows) do
    if not row.header then out[#out + 1] = row end
  end
  return out
end

describe("detail pane", function()
  it("sits on the list's right; the list and its top strip stop at its left edge", function()
    local ns = loadUI()
    local list = makeList(ns)
    local pane = list.Detail
    ok(pane, "pane built")
    eq(pane.width, ns.UI.DETAIL_WIDTH)
    eq({ pane:GetPoint(1) }, { "TOPRIGHT", list, "TOPRIGHT", 0, 0 })
    local _, rel, relPoint = list.ScrollBox:GetPoint(2)
    eq(rel, pane)
    eq(relPoint, "BOTTOMLEFT")
  end)

  it("selects the first mount when nothing is selected and shows it", function()
    local ns = loadUI()
    local list = makeList(ns)
    local rows = mountRows(list)
    eq(rows[1].id, 1)
    eq(rows[1].selected, true)
    eq(rows[2].selected, false)
    eq(rows[1].pin, nil, "no location icon: the row's clicks stand for it")
    local pane = list.Detail
    eq(pane.mountID, 1)
    eq(pane.Name:GetText(), "Alpha")
    eq(pane.Scene.actor.displayID, 1001, "model by the Mount Journal's display ID")
    eq(pane.Scene.sceneID, 7)
    eq(pane.Scene.noRider, true, "rider hidden while the Mount Journal setting is off")
    eq(pane.Scene.fanfare, false, "no present box")
    eq(pane.Waypoint, nil, "no buttons: the rows' clicks do it")
  end)

  it("a plain left-click selects (nowhere to go: no waypoint); the hover says what clicks do", function()
    local ns = loadUI()
    local list = makeList(ns)
    local waypoints = 0
    ns.Map = { SetWaypoint = function() waypoints = waypoints + 1 end, HasLocation = function() return false end,
      HasSpot = function() return false end }
    local row = CreateFrame("Button")
    local data = mountRows(list)[3]
    ns.UI.InitMountRow(row, data)
    row:RunScript("OnClick", "LeftButton")
    eq(waypoints, 0)
    eq(list.selectedID, 3)
    eq(list.Detail.mountID, 3)
    eq(list.Detail.Name:GetText(), "Gamma")
    ok(list.Detail.Owned:IsShown(), "owned check")
    eq(mountRows(list)[3].selected, true)
    local shown = false
    local old = ns.UI.ShowMountTooltip
    ns.UI.ShowMountTooltip = function() shown = true end
    row:RunScript("OnEnter")
    ns.UI.ShowMountTooltip = old
    eq(shown, false, "the pane replaces the hover tooltip")
    local hint = ns.UI.PaneRowHint(3)
    ok(hint:find("Left-click", 1, true) and not hint:find("Right-click", 1, true), "no location, no achievement: just view")
    ok(not hint:find("Shift-click", 1, true), "nor the map")
    ok(hint:find("Ctrl-click", 1, true) and hint:find("preview", 1, true), hint)
  end)

  it("a plain left-click on an achievement mount only selects it; right-click with nowhere to go opens the achievement", function()
    local ns = loadUI()
    local list = makeList(ns)
    local opened
    ns.Game.OpenAchievement = function(id) opened = id; return true end
    ns.AchievementScan.Lookup = function(id) if id == 2 then return 77, "ready" end return nil, "none" end
    local row = CreateFrame("Button")
    ns.UI.InitMountRow(row, mountRows(list)[2])
    ns.Map.HasLocation = function() return false end
    row:RunScript("OnClick", "LeftButton")
    eq(list.selectedID, 2)
    eq(opened, nil, "left-click: view only")
    row:RunScript("OnClick", "RightButton")
    eq(opened, 77)
    opened = nil
    ns.UI.InitMountRow(row, mountRows(list)[1])
    row:RunScript("OnClick", "LeftButton")
    eq(list.selectedID, 1)
    eq(opened, nil, "other mounts: no achievement")
  end)

  it("Shift-click still opens the map from a row", function()
    local ns = loadUI()
    local list = makeList(ns)
    local opened
    ns.Map = { OpenMap = function(id) opened = id end, HasLocation = function() return true end,
      HasSpot = function() return true end }
    local row = CreateFrame("Button")
    ns.UI.InitMountRow(row, mountRows(list)[1])
    IsShiftKeyDown = function() return true end
    row:RunScript("OnClick", "LeftButton")
    IsShiftKeyDown = nil
    eq(opened, 1)
    eq(list.selectedID, 1, "selection unchanged")
  end)

  it("the selection survives a refresh and moves on when its mount leaves the list", function()
    local ns = loadUI()
    local list = makeList(ns)
    list:Select(2)
    eq(list.Detail.mountID, 2)
    list:Refresh()
    eq(list.Detail.mountID, 2)
    ns.Data.Mounts[2] = nil
    list:Refresh()
    eq(list.Detail.mountID, 1)
  end)

  it("lines are the tooltip's without click hints; flavor first", function()
    local ns = loadUI()
    local c = ns.UI.DetailContent(1)
    eq(c.name, "Alpha")
    eq(c.flavor, "flavor of 1")
    for _, l in ipairs(c.lines) do
      ok(not (l.left or ""):find("Click", 1, true), "no hint: " .. tostring(l.left))
    end
    local tip = ns.UI.TooltipLines(1)
    ok(#tip > #c.lines, "the tooltip keeps its hints")
  end)

  it("a mount without a model shows its large icon; no model template: the icon too", function()
    local ns = loadUI()
    local list = makeList(ns)
    list:Select(2)
    ok(list.Detail.BigIcon:IsShown(), "icon instead")
    ok(not list.Detail.Scene:IsShown())
    local ns2 = loadUI(false)
    local list2 = makeList(ns2)
    eq(list2.Detail.Scene, nil)
    ok(list2.Detail.BigIcon:IsShown())
  end)

  it("row clicks: plain views, right-click plots, Shift opens the map, Ctrl the achievement; the hover lists them", function()
    local ns = loadUI()
    local list = makeList(ns)
    local calls = {}
    ns.Map = { SetWaypoint = function(id) calls[#calls + 1] = "wp" .. id end,
      OpenMap = function(id) calls[#calls + 1] = "map" .. id end,
      HasLocation = function() return true end, HasSpot = function() return true end }
    ns.UI.OpenMountAchievement = function(id) calls[#calls + 1] = "ach" .. id end
    ns.AchievementScan.Lookup = function() return 77, "ready" end
    local row = CreateFrame("Button")
    ns.UI.InitMountRow(row, mountRows(list)[1])
    row:RunScript("OnClick", "LeftButton")
    eq(calls, {}, "a plain click only views")
    row:RunScript("OnClick", "RightButton")
    IsShiftKeyDown = function() return true end
    row:RunScript("OnClick", "LeftButton")
    IsShiftKeyDown = nil
    IsControlKeyDown = function() return true end
    row:RunScript("OnClick", "LeftButton")
    IsControlKeyDown = nil
    eq(calls, { "wp1", "map1", "ach1" })
    eq(list.selectedID, 1, "each click also selects")
    local hint = ns.UI.PaneRowHint(1)
    ok(hint:find("plot the coordinates", 1, true), hint)
    ok(hint:find("show on the map", 1, true), hint)
    ok(hint:find("view the achievement", 1, true), hint)
  end)

  it("opts.detail = false keeps the old full-width list and click", function()
    local ns = loadUI()
    local parent = CreateFrame("Frame", nil, UIParent)
    local list = ns.UI.List(parent, function() return { view = "misc" } end, { detail = false })
    list:Refresh(true)
    eq(list.Detail, nil)
    eq(mountRows(list)[1].onSelect, nil)
  end)

  it("Where to find it: each NPC with its zones and spawn count, no coordinate list; Waypoint plots them all", function()
    local ns = loadUI()
    local spots = ns.UI.DetailSpots(1)
    eq(#spots, 1)
    eq(spots[1].name, "Luk'hok")
    eq(spots[1].daily, true)
    eq(#spots[1].maps, 2)
    eq({ spots[1].maps[1].map, spots[1].maps[1].name, #spots[1].maps[1].points }, { 550, "Nagrand", 2 })
    eq(ns.UI.DetailSpots(3), {}, "the other faction's vendor is left out")
    local list = makeList(ns)
    local pane = list.Detail
    local texts, rights = {}, {}
    for i, fs in ipairs(pane.lineStrings) do
      if fs:IsShown() then
        texts[#texts + 1] = fs:GetText()
        if pane.rightStrings[i]:IsShown() then rights[fs:GetText()] = pane.rightStrings[i]:GetText() end
      end
    end
    local heading, label
    for _, t in ipairs(texts) do
      if t == "Where to find it" then heading = true end
      if t:find("^Luk'hok") then label = t end
    end
    ok(heading, "heading")
    ok(label and label:find("daily", 1, true), tostring(label))
    eq(rights[label], "Nagrand, Old Nagrand \194\183 3 spawn points")
    eq(pane.pointButtons, nil, "no coordinate buttons")
    eq(pane.PlotAll, nil, "no Plot all")
    local went
    ns.UI.GoTo = function(id) went = id end
    local row = CreateFrame("Button")
    ns.UI.InitMountRow(row, mountRows(list)[1])
    row:RunScript("OnClick", "RightButton")
    eq(went, 1, "a row's right-click is the one go-to")
  end)

  it("a row click plots every spawn point when the rare has several (map tab, zone panel)", function()
    local ns = loadUI()
    local plotted, waypoint
    ns.Map.PlotCount = function(id) return id == 1 and 3 or 0 end
    ns.Map.PlotMounts = function(ids, label) plotted = { ids[1], label } end
    ns.Map.SetWaypoint = function(id) waypoint = id end
    ns.UI.HandleRowClick(1, "LeftButton")
    eq(plotted, { 1, "Alpha" })
    eq(waypoint, nil)
    ns.UI.HandleRowClick(2, "LeftButton")
    eq(waypoint, 2)
    eq(ns.UI.ClickHint(1), "Click to plot all 3 spawn points")
    eq(ns.UI.ClickHint(2), "Click to set waypoint")
  end)
end)

describe("detail pane width", function()
  it("drag its left edge: every pane takes the width, saved and clamped; right-click: the default", function()
    local ns = loadUI()
    local a = ns.UI.CreateDetailPane(UIParent)
    local b = ns.UI.CreateDetailPane(UIParent)
    eq(a.width, ns.UI.DETAIL_WIDTH)
    a.right = 900
    STUB_CURSOR[1] = 540
    a.Splitter:RunScript("OnMouseDown", "LeftButton")
    a.Splitter:GetScript("OnUpdate")(a.Splitter, 0.01)
    a.Splitter:RunScript("OnMouseUp", "LeftButton")
    eq({ a.width, b.width }, { 360, 360 }, "both panes")
    eq(ns.db.global.window.paneWidth, 360)
    STUB_CURSOR[1] = 0
    a.Splitter:RunScript("OnMouseDown", "LeftButton")
    a.Splitter:GetScript("OnUpdate")(a.Splitter, 0.01)
    a.Splitter:RunScript("OnMouseUp", "LeftButton")
    eq(ns.db.global.window.paneWidth, ns.UI.PANE_MAX, "no wider than the maximum")
    a.Splitter:RunScript("OnClick", "RightButton")
    eq(b.width, ns.UI.DETAIL_WIDTH)
    eq(ns.UI.CreateDetailPane(UIParent).width, ns.UI.DETAIL_WIDTH, "new panes take the saved width")
  end)

  it("How to get it: AllTheThings' description of the item, else of the NPC behind it", function()
    local ns = loadUI()
    ns.Data.Mounts[1].item, ns.Data.Mounts[1].spell = 900, 132036
    local db = {
      itemID = { [900] = { { parent = { npcID = 50981, description = "Collect ten Skyshards first." } } } },
    }
    ns.Notes.app = { SearchForField = function(field, id) return (db[field] or {})[id] end }
    eq(ns.Notes.Description(1), "Collect ten Skyshards first.", "the dropping NPC's note")
    db.npcID = { [1] = { { description = "Sells it." } } }
    eq(ns.Notes.Description(3), nil, "a Horde vendor's spot only: not this character's")
    ns.Notes.app = false
    eq(ns.Notes.Description(2), nil, "no ATT: nothing")
    eq(ns.Notes.WowheadURL(1), "https://www.wowhead.com/spell=132036")
    ns.Notes.app = { SearchForField = function(field, id) return (db[field] or {})[id] end }
    local list = makeList(ns)
    local texts = {}
    for _, fs in ipairs(list.Detail.lineStrings) do if fs:IsShown() then texts[fs:GetText()] = true end end
    ok(texts["How to get it"] and texts["Collect ten Skyshards first."], "in the pane")
  end)

  it("the Wowhead button opens the mount's page in a box to copy", function()
    local ns = loadUI()
    ns.Data.Mounts[1].spell = 132036
    local list = makeList(ns)
    local shown
    ns.UI.ShowCopyText = function(title, text) shown = text end
    list.Detail.Wowhead:RunScript("OnClick", "LeftButton")
    eq(shown, "https://www.wowhead.com/spell=132036")
  end)
end)
