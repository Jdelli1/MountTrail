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
    local pane = list.Detail
    eq(pane.mountID, 1)
    eq(pane.Name:GetText(), "Alpha")
    eq(pane.Scene.actor.displayID, 1001, "model by the Mount Journal's display ID")
    eq(pane.Scene.sceneID, 7)
    eq(pane.Scene.noRider, true, "rider hidden while the Mount Journal setting is off")
    eq(pane.Scene.fanfare, false, "no present box")
    eq(pane.Waypoint.enabled, true, "has a location")
    eq(pane.Achievement.enabled, false)
  end)

  it("a plain left-click selects (no waypoint); rows show no tooltip", function()
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

  it("buttons: waypoint and map through Map, achievement through the achievement opener", function()
    local ns = loadUI()
    local list = makeList(ns)
    local calls = {}
    ns.Map = { SetWaypoint = function(id) calls[#calls + 1] = "wp" .. id end,
      OpenMap = function(id) calls[#calls + 1] = "map" .. id end,
      HasLocation = function() return true end, HasSpot = function() return true end }
    ns.UI.OpenMountAchievement = function(id) calls[#calls + 1] = "ach" .. id end
    list.Detail.Waypoint:RunScript("OnClick")
    list.Detail.MapButton:RunScript("OnClick")
    list.Detail.Achievement:RunScript("OnClick")
    eq(calls, { "wp1", "map1", "ach1" })
  end)

  it("opts.detail = false keeps the old full-width list and click", function()
    local ns = loadUI()
    local parent = CreateFrame("Frame", nil, UIParent)
    local list = ns.UI.List(parent, function() return { view = "misc" } end, { detail = false })
    list:Refresh(true)
    eq(list.Detail, nil)
    eq(mountRows(list)[1].onSelect, nil)
  end)
end)
