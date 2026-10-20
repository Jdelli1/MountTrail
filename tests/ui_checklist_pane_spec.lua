-- The Checklist tab with the detail pane (UI/ChecklistView.lua +
-- UI/DetailPane.lua): the pane on the right, a plain left-click selects a
-- row and the pane shows its mount; tick boxes and modifier clicks keep
-- their actions. (tests/ui_build_spec.lua covers the tab without the pane.)

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/DetailPane.lua",
  "UI/Tabs.lua", "UI/LockoutHelpers.lua", "UI/ChecklistView.lua", "UI/Popouts.lua" }

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

for _, name in ipairs({ "SetMaxLines", "EnableMouseWheel", "SetAlpha" }) do
  getmetatable(getmetatable(CreateFrame("Frame")).__index).__index[name] =
    getmetatable(getmetatable(CreateFrame("Frame")).__index).__index[name] or function() end
end
do
  local FrameMT = getmetatable(CreateFrame("Frame"))
  FrameMT.SetScrollChild = FrameMT.SetScrollChild or function(self, child) self.scrollChild = child end
  FrameMT.SetVerticalScroll = FrameMT.SetVerticalScroll or function(self, v) self.vscroll = v end
  FrameMT.GetVerticalScroll = FrameMT.GetVerticalScroll or function(self) return self.vscroll or 0 end
end

local function render(box)
  local frames = {}
  for _, data in ipairs(box.provider.rows) do
    box.view.factory(function(kind, init)
      local f = CreateFrame(kind, nil, box)
      init(f, data)
      frames[#frames + 1] = f
    end, data)
  end
  return frames
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
  }
  for k, v in pairs(stubGame) do ns.Game[k] = v end
  return ns
end

local function openChecklist(ns)
  ns.ToggleWindow()
  ns.UI.SelectTab("checklist")
  local contentFrame = ns.UI.frame.Contents.checklist
  local root
  for _, c in ipairs(contentFrame.children) do if c.Detail then root = c end end
  return root
end

describe("Checklist with the detail pane", function()
  it("the pane sits on the right; the header and list stop at its left edge", function()
    local ns = loadUI()
    local root = openChecklist(ns)
    ok(root, "checklist root with a pane")
    local pane = root.Detail
    eq({ pane:GetPoint(1) }, { "TOPRIGHT", root, "TOPRIGHT", 0, 0 })
    local header
    for _, c in ipairs(root.children) do if c.Chips then header = c end end
    local _, rel, relPoint = header:GetPoint(2)
    eq({ rel, relPoint }, { pane, "TOPLEFT" })
    local _, lrel, lrelPoint = header.Checklist:GetPoint(2)
    eq({ lrel, lrelPoint }, { pane, "BOTTOMLEFT" })
  end)

  it("the first entry is selected and shown; a plain click selects another, rows show no pin", function()
    local ns = loadUI()
    local root = openChecklist(ns)
    local header
    for _, c in ipairs(root.children) do if c.Chips then header = c end end
    local box = header.Checklist.ScrollBox
    local mounts = {}
    for _, row in ipairs(box.provider.rows) do
      if not row.header then mounts[#mounts + 1] = row end
    end
    ok(#mounts >= 2, "real data has entries")
    eq(mounts[1].selected, true)
    eq(mounts[1].pin, nil)
    eq(root.Detail.mountID, mounts[1].entry.id)
    local waypoints = 0
    ns.UI.HandleRowClick = function() waypoints = waypoints + 1 end
    local frames = render(box)
    local target
    for _, f in ipairs(frames) do
      if f.entry and f.entry.key == mounts[2].entry.key then target = f end
    end
    target:RunScript("OnClick", "LeftButton")
    eq(waypoints, 0, "no waypoint on a plain click")
    eq(root.Detail.mountID, mounts[2].entry.id)
    local again = {}
    for _, row in ipairs(box.provider.rows) do
      if not row.header and row.selected then again[#again + 1] = row.entry.key end
    end
    eq(again, { mounts[2].entry.key })
    IsShiftKeyDown = function() return true end
    target:RunScript("OnClick", "LeftButton")
    IsShiftKeyDown = nil
    eq(waypoints, 1, "Shift-click still goes through HandleRowClick")
  end)
end)
