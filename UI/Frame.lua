local ADDON, ns = ...

-- Main window, tabs and minimap button. Loads after Core\Init.lua, so ns.db
-- does not exist yet: the window is built on the first ToggleWindow and the
-- minimap button on PLAYER_LOGIN (after AceDB's OnInitialize).

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local ICON = 132261 -- same as ## IconTexture in the .toc
local WIDTH, HEIGHT = 800, 560

-- Style helpers ------------------------------------------------------------------
-- The window follows Blizzard's current flat panel style (Professions, Delves,
-- the modern Collections). Every template newer than the classic ones goes
-- through UI.Template, so a client without it gets the classic look instead
-- of a broken window.

-- preferred -> fallback for each template the client did not define (shown
-- by `/azt debug`).
UI.TemplateFallbacks = UI.TemplateFallbacks or {}

local function templateExists(name)
  local util = C_XMLUtil
  if type(name) ~= "string" or type(util) ~= "table" or type(util.GetTemplateInfo) ~= "function" then
    return false
  end
  local good, info = pcall(util.GetTemplateInfo, name)
  return good and info ~= nil
end

-- `preferred` when the client defines that XML template
-- (C_XMLUtil.GetTemplateInfo), else `fallback` (may be nil). A fallback is
-- recorded in UI.TemplateFallbacks and reported once through
-- Game.ReportError (visible with /azt debug).
function UI.Template(preferred, fallback)
  if templateExists(preferred) then return preferred end
  if UI.TemplateFallbacks[preferred] == nil then
    UI.TemplateFallbacks[preferred] = fallback or false
    local game = ns.Game
    if game and type(game.ReportError) == "function" then
      game.ReportError(string.format("template %s missing, using %s", tostring(preferred),
        tostring(fallback or "none")))
    end
  end
  return fallback
end

-- True when the client knows the texture atlas `name` (C_Texture.GetAtlasInfo).
function UI.AtlasExists(name)
  local tex = C_Texture
  if type(name) ~= "string" or type(tex) ~= "table" or type(tex.GetAtlasInfo) ~= "function" then
    return false
  end
  local good, info = pcall(tex.GetAtlasInfo, name)
  return good and info ~= nil
end

-- A 1 px flat border around `frame` (four edge textures on `layer`, default
-- BORDER) -> border; border:SetColor(r, g, b, a) recolours it (hover tints).
function UI.FlatBorder(frame, r, g, b, a, layer)
  local border = { edges = {} }
  local function edge(p1, p2, horizontal)
    local t = frame:CreateTexture(nil, layer or "BORDER")
    t:SetPoint(p1, frame, p1, 0, 0)
    t:SetPoint(p2, frame, p2, 0, 0)
    if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    border.edges[#border.edges + 1] = t
    return t
  end
  edge("TOPLEFT", "TOPRIGHT", true)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  edge("TOPLEFT", "BOTTOMLEFT", false)
  edge("TOPRIGHT", "BOTTOMRIGHT", false)
  function border:SetColor(cr, cg, cb, ca)
    for _, t in ipairs(self.edges) do t:SetColorTexture(cr, cg, cb, ca) end
  end
  border:SetColor(r or 1, g or 1, b or 1, a or 0.1)
  return border
end

-- Tab order is fixed; views plug in by key (Tasks 13/14).
local TABS = {
  { key = "journal", label = "Journal" },
  { key = "holidays", label = "Holidays" },
  { key = "misc", label = "Misc" },
  { key = "route", label = "Route" },
}
local TAB_INDEX = {}
for i, tab in ipairs(TABS) do TAB_INDEX[tab.key] = i end

local views = {}    -- key -> { Build = fn(parent), Refresh = fn() }
local built = {}    -- key -> true once view.Build ran
local contents = {} -- key -> content frame
local placeholders = {} -- key -> "Coming soon" FontString
local current      -- selected tab key

local function windowDB()
  if not ns.db then return nil end
  ns.db.global.window = ns.db.global.window or {}
  return ns.db.global.window
end

local function validKey(key)
  return key and TAB_INDEX[key] and key or TABS[1].key
end

-- Builds the selected tab's view the first time it is on screen, then
-- refreshes it. Tabs with no view keep their placeholder.
local function showCurrent()
  local frame = UI.frame
  if not (frame and frame:IsShown()) then return end
  local view = views[current]
  if not view then return end
  if not built[current] then
    built[current] = true
    if placeholders[current] then placeholders[current]:Hide() end
    if view.Build then view.Build(contents[current]) end
  end
  if view.Refresh then view.Refresh() end
end

-- Registers a tab view. key: "journal", "holidays", "misc" or "route".
function UI.RegisterView(key, view)
  assert(TAB_INDEX[key], "AzerothTrail: unknown view key " .. tostring(key))
  assert(type(view) == "table", "AzerothTrail: view must be a table")
  views[key] = view
  if UI.frame and key == current then showCurrent() end
end

local function savePosition(frame)
  local db = windowDB()
  if not db then return end
  local point, _, relPoint, x, y = frame:GetPoint(1)
  db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end

local function restorePosition(frame)
  local db = windowDB()
  frame:ClearAllPoints()
  if db and db.point then
    frame:SetPoint(db.point, UIParent, db.relPoint or db.point, db.x or 0, db.y or 0)
  else
    frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  end
end

local function setPortrait(frame)
  if frame.SetPortraitToAsset then -- PortraitFrameMixin (Retail)
    frame:SetPortraitToAsset(ICON)
  elseif frame.portrait and SetPortraitToTexture then -- older templates
    SetPortraitToTexture(frame.portrait, ICON)
  elseif frame.PortraitContainer and frame.PortraitContainer.portrait then
    frame.PortraitContainer.portrait:SetTexture(ICON)
  end
end

local function setTitle(frame, text)
  if frame.SetTitle then
    frame:SetTitle(text)
  elseif frame.TitleText then
    frame.TitleText:SetText(text)
  end
end

function UI.SelectTab(key)
  key = validKey(key)
  current = key
  local db = windowDB()
  if db then db.tab = key end
  local frame = UI.frame
  if not frame then return end
  for _, tab in ipairs(TABS) do
    contents[tab.key]:SetShown(tab.key == key)
  end
  PanelTemplates_SetTab(frame, TAB_INDEX[key])
  showCurrent()
end

local TITLE_HEIGHT = 24 -- title bar of the portrait frame
local PORTRAIT_RIGHT = 60 -- the portrait covers the top-left corner up to here
local CONTENT_TOP = -60 -- content starts below the portrait

local function createWindow()
  local frameTemplate = UI.Template("PortraitFrameFlatTemplate", "PortraitFrameTemplate")
  local flat = frameTemplate == "PortraitFrameFlatTemplate"
  local frame = CreateFrame("Frame", "AzerothTrailFrame", UIParent, frameTemplate)
  UI.frame = frame
  frame.isFlat = flat
  frame:Hide()
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  setTitle(frame, L["AzerothTrail"])
  setPortrait(frame)
  restorePosition(frame)

  -- Drag handle over the title bar (right of the portrait, left of the close
  -- button). We save the position ourselves, so opt out of the layout cache.
  local drag = CreateFrame("Frame", nil, frame)
  drag:SetPoint("TOPLEFT", frame, "TOPLEFT", PORTRAIT_RIGHT, 0)
  drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, 0)
  drag:SetHeight(TITLE_HEIGHT)
  drag:EnableMouse(true)
  drag:RegisterForDrag("LeftButton")
  drag:SetScript("OnDragStart", function() frame:StartMoving() end)
  drag:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    frame:SetUserPlaced(false)
    savePosition(frame)
  end)
  frame.DragHandle = drag

  -- Content area below the portrait; one content frame per tab inside it.
  -- Flat window: a plain frame over a slightly darker flat fill with a 1 px
  -- edge (the modern inset look). Classic fallback: the classic inset.
  local inset
  if flat then
    inset = CreateFrame("Frame", nil, frame)
    -- The fill and edge belong to the window, so the inset's children stay
    -- the four tab contents.
    local fill = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    fill:SetPoint("TOPLEFT", inset, "TOPLEFT", 0, 0)
    fill:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", 0, 0)
    fill:SetColorTexture(0, 0, 0, 0.3)
    frame.InsetFill = fill
  else
    inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
  end
  inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, CONTENT_TOP)
  inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
  frame.Inset = inset

  -- Tabs: modern top tabs between the title bar and the content (right of
  -- the portrait); classic bottom tabs when the client lacks the template.
  local tabTemplate = UI.Template("PanelTopTabButtonTemplate", "PanelTabButtonTemplate")
  local topTabs = tabTemplate == "PanelTopTabButtonTemplate"
  frame.topTabs = topTabs

  frame.Tabs = {}
  for i, tab in ipairs(TABS) do
    local content = CreateFrame("Frame", nil, inset)
    content:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    content:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
    content:Hide()
    contents[tab.key] = content

    local placeholder = content:CreateFontString(nil, "OVERLAY", "GameFontDisableLarge")
    placeholder:SetPoint("CENTER", content, "CENTER", 0, 0)
    placeholder:SetText(L["Coming soon"])
    placeholders[tab.key] = placeholder

    -- PanelTemplates_* find tabs as <frameName>Tab<i> (or frame.Tabs[i]).
    local button = CreateFrame("Button", "AzerothTrailFrameTab" .. i, frame, tabTemplate)
    button:SetID(i)
    button:SetText(L[tab.label])
    if i == 1 then
      if topTabs then
        button:SetPoint("BOTTOMLEFT", inset, "TOPLEFT", PORTRAIT_RIGHT, 0)
      else
        button:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 11, 2)
      end
    elseif topTabs then
      button:SetPoint("LEFT", frame.Tabs[i - 1], "RIGHT", 2, 0)
    else
      button:SetPoint("TOPLEFT", frame.Tabs[i - 1], "TOPRIGHT", 3, 0)
    end
    if PanelTemplates_TabResize then PanelTemplates_TabResize(button, 0) end
    button:SetScript("OnClick", function()
      if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
      end
      UI.SelectTab(tab.key)
    end)
    frame.Tabs[i] = button
  end
  PanelTemplates_SetNumTabs(frame, #TABS)

  frame:HookScript("OnShow", showCurrent)

  -- Esc closes the window.
  tinsert(UISpecialFrames, frame:GetName())

  local db = windowDB()
  UI.SelectTab(db and db.tab)
  return frame
end

function ns.ToggleWindow()
  local frame = UI.frame or createWindow()
  if frame:IsShown() then
    frame:Hide()
  else
    frame:Show()
  end
end

-- Refresh hooks: functions run on every ns.Refresh(), before the window check,
-- so UI that lives outside the main window (the route arrow, UI\Arrow.lua)
-- stays current while the window is closed. Hooks must not raise errors.
local refreshHooks = {}

function UI.AddRefreshHook(fn)
  assert(type(fn) == "function", "AzerothTrail: refresh hook must be a function")
  refreshHooks[#refreshHooks + 1] = fn
end

-- Runs the refresh hooks, then re-renders the visible tab (nothing more while
-- the window is closed).
ns.Refresh = function()
  for _, fn in ipairs(refreshHooks) do fn() end
  local frame = UI.frame
  if not (frame and frame:IsShown()) then return end
  local view = views[current]
  if view and built[current] and view.Refresh then view.Refresh() end
end

-- Minimap button ----------------------------------------------------------------

local minimapReady = false

local function setupMinimap()
  if minimapReady or not ns.db then return end
  minimapReady = true
  local LDB = LibStub("LibDataBroker-1.1", true)
  local DBIcon = LibStub("LibDBIcon-1.0", true)
  if not LDB then return end
  local launcher = LDB:NewDataObject(ADDON, {
    type = "launcher",
    text = L["AzerothTrail"],
    icon = ICON,
    OnClick = function(_, button)
      if button == "LeftButton" then ns.ToggleWindow() end
    end,
    OnTooltipShow = function(tooltip)
      tooltip:AddLine(L["AzerothTrail"])
      tooltip:AddLine(L["Left-click: open/close"], 1, 1, 1)
      if type(UI.RouteRemaining) == "function" then
        local left = UI.RouteRemaining()
        if type(left) == "number" then
          tooltip:AddLine(string.format(L["Route: %d steps left"], left), 1, 1, 1)
        end
      end
    end,
  })
  UI.launcher = launcher
  if launcher and DBIcon then
    ns.db.global.minimap = ns.db.global.minimap or { hide = false }
    DBIcon:Register(ADDON, launcher, ns.db.global.minimap)
  end
end

if IsLoggedIn() then
  setupMinimap()
else
  local loginFrame = CreateFrame("Frame")
  loginFrame:RegisterEvent("PLAYER_LOGIN")
  loginFrame:SetScript("OnEvent", function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    setupMinimap()
  end)
end
