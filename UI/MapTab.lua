local ADDON, ns = ...

-- World map side tab: an MountTrail tab in the Map & Quest Log's column of
-- side tabs (with Quests, Events and Map Legend; LargeSideTabButtonTemplate,
-- our icon in a round mask). Selecting it covers the quest log with
-- "Mounts in <zone>" for the map being viewed (not the player's map): the
-- zone panel's list (UI.ZoneContext / ZoneMounts / ZoneRows, rows from
-- UI.InitMountRow: click for a waypoint, Shift map, Ctrl preview, tooltip).
-- Maps coarser than a zone (world, continent) say to open a zone.
-- Taint: Blizzard's tables and fields are only read, never written. The
-- panel is an opaque cover over the quest log, so Blizzard's own display
-- mode is never changed; clicking any of Blizzard's tabs (or Blizzard
-- switching mode, or opening a quest's details) uncovers it again. Our tab
-- sits under the lowest side tab in the column (other add-ons add tabs
-- there too), never under one that hangs below ours. The choice is saved in
-- ns.db.global.mapTab.selected, so the tab comes back selected.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local ICON = 132261 -- same as ## IconTexture in the .toc
local TAB_GAP = 3
local ICON_SIZE = 26
local HEADER = 34
local ZONE_TYPE = 3 -- Enum.UIMapType.Zone: coarser maps list nothing
local MAX_HOPS = 12 -- anchor-chain steps followed when looking for a cycle

local tab, panel
local hookedTabs = {}

local function report(err)
  if ns.Game and ns.Game.ReportError then ns.Game.ReportError(err) end
end

local function stateDB()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.mapTab) ~= "table" then global.mapTab = {} end
  return global.mapTab
end

-- Whether `frame` hangs (through its first anchor, step by step) from
-- `target`.
local function hangsFrom(frame, target)
  local current = frame
  for _ = 1, MAX_HOPS do
    if type(current.GetPoint) ~= "function" then return false end
    local _, rel = current:GetPoint(1)
    if rel == nil then return false end
    if rel == target then return true end
    current = rel
  end
  return false
end

-- Side tab to put ours under: among `frames` (the quest map's children),
-- the shown ones shaped like a side tab (about `width` x `height`) whose left
-- edge lines up with `first` (Blizzard's last tab) and that sit lower, not
-- ours and not hanging from ours, the lowest. -> that frame, else `first`
-- (also when nothing is laid out yet).
function UI.MapTabAnchor(frames, first, self, width, height)
  local best, bestBottom = first, first and first:GetBottom() or nil
  local left = first and first:GetLeft() or nil
  if not (bestBottom and left) then return first end
  for _, f in ipairs(frames or {}) do
    if f ~= self and f ~= first and f.IsShown and f:IsShown() then
      local w, h = f:GetWidth(), f:GetHeight()
      local fl, fb = f:GetLeft(), f:GetBottom()
      if w and h and fl and fb
        and math.abs(w - width) <= 2 and math.abs(h - height) <= 2
        and math.abs(fl - left) <= 2
        and fb < bestBottom
        and not hangsFrom(f, self) then
        best, bestBottom = f, fb
      end
    end
  end
  return best
end

-- The map the world map shows, else the player's.
local function viewedMap()
  local map = WorldMapFrame
  if map and type(map.GetMapID) == "function" then
    local good, id = pcall(map.GetMapID, map)
    if good and type(id) == "number" then return id end
  end
  return ns.Game.PlayerMap()
end

-- What the panel lists for `mapID` -> rows, title, empty text.
-- ctx (default UI.ZoneContext()) has no current instance: the world map
-- may show any map, wherever the player stands.
function UI.MapTabContent(mapID, ctx)
  local info = mapID and ns.Game.MapInfo(mapID) or nil
  if not info then
    return {}, L["MountTrail"], L["Open a zone on the map to see its mounts"]
  end
  if type(info.mapType) == "number" and info.mapType < ZONE_TYPE then
    return {}, string.format(L["Mounts in %s"], info.name or "?"), L["Open a zone on the map to see its mounts"]
  end
  ctx = ctx or UI.ZoneContext()
  ctx.currentInstance = nil
  local list, zone = UI.ZoneMounts(mapID, ctx)
  local rows = UI.ZoneRows(list)
  return rows, UI.ZoneTitle(zone or { name = info.name }, #rows), L["Nothing left to collect here"]
end

local function refreshPanel()
  if not (panel and panel:IsVisible()) then return end
  local good, rows, title, emptyText = pcall(UI.MapTabContent, viewedMap())
  if not good then
    report(rows)
    rows, title, emptyText = {}, L["MountTrail"], ""
  end
  panel.Title:SetText(title)
  panel.ScrollBox:SetDataProvider(CreateDataProvider(rows))
  panel.Empty:SetText(emptyText)
  panel.Empty:SetShown(#rows == 0)
end
UI.RefreshMapTab = refreshPanel

local function paintTab(selected)
  if not tab then return end
  tab.Icon:SetDesaturated(not selected)
  tab.Icon:SetAlpha(selected and 1 or 0.75)
  if tab.SelectedTexture then tab.SelectedTexture:SetShown(selected) end
end

-- Blizzard's tabs show the quest log's own mode again (read only).
local function paintBlizzardTabs(ours)
  local qmf = QuestMapFrame
  for _, t in ipairs((qmf and qmf.TabButtons) or {}) do
    if type(t.SetChecked) == "function" then
      t:SetChecked((not ours) and t.displayMode == qmf.displayMode)
    end
  end
end

-- Selects (true) or leaves (false) our tab.
function UI.SelectMapTab(on)
  on = on and true or false
  local db = stateDB()
  if db then db.selected = on end
  if not panel then return end
  local was = panel:IsShown()
  panel:SetShown(on)
  paintTab(on)
  -- Blizzard's tabs are repainted only when the cover comes or goes.
  if on ~= was then paintBlizzardTabs(on) end
  if on then refreshPanel() end
end

local function placeTab()
  local qmf = QuestMapFrame
  if not (tab and qmf and qmf.QuestsTab) then return end
  -- Blizzard's last tab is the floor (also when nothing is laid out yet).
  local last = qmf.MapLegendTab or qmf.QuestsTab
  local below = UI.MapTabAnchor({ qmf:GetChildren() }, last, tab, tab:GetWidth(), tab:GetHeight())
  tab:ClearAllPoints()
  tab:SetPoint("TOP", below, "BOTTOM", 0, -TAB_GAP)
end

-- Leave our tab when one of the quest log's tabs is clicked.
local function hookTabs()
  local qmf = QuestMapFrame
  for _, t in ipairs((qmf and qmf.TabButtons) or {}) do
    if not hookedTabs[t] and type(t.HookScript) == "function" then
      hookedTabs[t] = true
      t:HookScript("OnMouseUp", function(_, button, upInside)
        if button == "LeftButton" and upInside and panel and panel:IsShown() then
          UI.SelectMapTab(false)
        end
      end)
    end
  end
end

local function buildPanel(qmf)
  local anchor = qmf.ContentsAnchor or qmf
  local p = CreateFrame("Frame", "MountTrailMapPanel", qmf)
  p:SetPoint("TOPLEFT", anchor, "TOPLEFT", 0, 0)
  p:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -22, 0)
  p:SetFrameLevel(qmf:GetFrameLevel() + 50)
  p:EnableMouse(true)
  if p.EnableMouseWheel then p:EnableMouseWheel(true) end
  p:Hide()

  -- Opaque, so the quest log underneath does not show through.
  local fill = p:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(p)
  fill:SetColorTexture(0.06, 0.06, 0.07, 1)
  p.Fill = fill
  p.Edge = UI.FlatBorder(p, 1, 1, 1, 0.1)

  local strip = p:CreateTexture(nil, "BORDER")
  strip:SetPoint("TOPLEFT", p, "TOPLEFT", 1, -1)
  strip:SetPoint("TOPRIGHT", p, "TOPRIGHT", -1, -1)
  strip:SetHeight(HEADER)
  strip:SetColorTexture(1, 1, 1, 0.04)
  local rule = p:CreateTexture(nil, "BORDER")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, 0)
  rule:SetColorTexture(1, 0.82, 0, 0.25)

  local title = p:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
  title:SetPoint("LEFT", strip, "LEFT", 10, 0)
  title:SetPoint("RIGHT", strip, "RIGHT", -10, 0)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)
  p.Title = title

  local scrollBox = CreateFrame("Frame", nil, p, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", rule, "BOTTOMLEFT", 0, -2)
  scrollBox:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -16, 4)
  p.ScrollBox = scrollBox
  local scrollBar = CreateFrame("EventFrame", nil, p, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
  p.ScrollBar = scrollBar
  local view = CreateScrollBoxListLinearView()
  view:SetElementExtentCalculator(function() return UI.RowHeight(UI.MOUNT_ROW_HEIGHT) end)
  view:SetElementFactory(function(factory) factory("Button", UI.InitMountRow) end)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)

  local empty = p:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisable"))
  empty:SetPoint("LEFT", scrollBox, "LEFT", 12, 0)
  empty:SetPoint("RIGHT", scrollBox, "RIGHT", -12, 0)
  empty:Hide()
  p.Empty = empty
  return p
end

local function buildTab(qmf)
  local t = CreateFrame("Frame", "MountTrailMapTab", qmf, "LargeSideTabButtonTemplate")
  t.tooltipText = L["MountTrail: mounts on this map"]
  local icon = t.Icon or t:CreateTexture(nil, "ARTWORK")
  t.Icon = icon
  icon:ClearAllPoints()
  icon:SetPoint("CENTER", t, "CENTER", -2, 0)
  icon:SetSize(ICON_SIZE, ICON_SIZE)
  icon:SetTexture(ICON)
  if type(t.CreateMaskTexture) == "function" then
    local mask = t:CreateMaskTexture()
    mask:SetAllPoints(icon)
    mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    icon:AddMaskTexture(mask)
  end
  local function onUp(_, button, upInside)
    if button == "LeftButton" and upInside ~= false then UI.SelectMapTab(true) end
  end
  if type(t.SetCustomOnMouseUpHandler) == "function" then
    t:SetCustomOnMouseUpHandler(onUp)
  else
    t:SetScript("OnMouseUp", onUp)
  end
  return t
end

-- Builds the tab and panel once the quest map exists (-> true when built).
function UI.BuildMapTab()
  if tab then return true end
  local qmf = QuestMapFrame
  if not (qmf and qmf.QuestsTab) then return false end
  if not UI.Template("LargeSideTabButtonTemplate", nil) then return false end
  local good, err = pcall(function()
    tab = buildTab(qmf)
    panel = buildPanel(qmf)
  end)
  if not good then
    report(err)
    tab, panel = nil, nil
    return false
  end
  UI.mapTab, UI.mapPanel = tab, panel
  placeTab()
  hookTabs()
  if type(hooksecurefunc) == "function" then
    if type(qmf.ValidateTabs) == "function" then
      hooksecurefunc(qmf, "ValidateTabs", function() placeTab(); hookTabs() end)
    end
    local map = WorldMapFrame
    if map and type(map.OnMapChanged) == "function" then
      hooksecurefunc(map, "OnMapChanged", refreshPanel)
    end
    if type(QuestMapFrame_ShowQuestDetails) == "function" then
      hooksecurefunc("QuestMapFrame_ShowQuestDetails", function()
        if panel:IsShown() then UI.SelectMapTab(false) end
      end)
    end
  end
  local registry = EventRegistry
  if registry and type(registry.RegisterCallback) == "function" then
    registry:RegisterCallback("QuestLog.SetDisplayMode", function()
      if panel:IsShown() then UI.SelectMapTab(false) end
    end, tab)
  end
  qmf:HookScript("OnShow", function()
    placeTab()
    hookTabs()
    local db = stateDB()
    UI.SelectMapTab(db ~= nil and db.selected == true)
  end)
  local db = stateDB()
  UI.SelectMapTab(db ~= nil and db.selected == true)
  return true
end

UI.AddRefreshHook(function() refreshPanel() end)

local loader = CreateFrame("Frame")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self)
  if UI.BuildMapTab() then
    self:UnregisterEvent("PLAYER_LOGIN")
    self:UnregisterEvent("ADDON_LOADED")
  end
end)
