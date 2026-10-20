local ADDON, ns = ...

-- Main window and minimap button: text sizes, style helpers, the views
-- (tabs), the window's size, scale and position, the settings menu and the
-- refresh. The shared widgets live in UI/Widgets.lua, the navigation column
-- in UI/Nav.lua (both load right after this file). Loads after Core\Init.lua,
-- so ns.db does not exist yet: the window is built on the first ToggleWindow
-- and the minimap button on PLAYER_LOGIN (after AceDB's OnInitialize).

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local ICON = 132261 -- same as ## IconTexture in the .toc
local WIDTH, HEIGHT = 900, 560

-- Text sizes ----------------------------------------------------------------------
-- Every game font the add-on draws text with belongs to a role: headers
-- (the gold titles and headers), body (the white text: mount names, rows)
-- and details (the grey second lines: sources, zones, counts). UI.Font(name)
-- hands out the add-on's own copy of the game font (MountTrail<name>, made
-- with CreateFont on first use) sized by its role: the game's size plus
-- UI.TextSize(role) points (Options' text size sliders). Font strings set to
-- a font object follow it, so UI.ApplyTextSizes resizes all the text at
-- once. Without CreateFont (or the game font) the game font itself is used.

UI.FONT_ROLES = {
  GameFontNormal = "header", GameFontNormalSmall = "header", GameFontNormalLarge = "header",
  GameFontHighlight = "body", GameFontHighlightSmall = "body", GameFontGreen = "body",
  GameFontDisable = "detail", GameFontDisableSmall = "detail", GameFontDisableLarge = "detail",
}
UI.TEXT_ROLES = { "header", "body", "detail" }

local fonts = {} -- MountTrail<name> -> { base =, role =, object = }

-- Points added to a role's fonts (Options: settings.text<Role>, -2..+6).
function UI.TextSize(role)
  local options = ns.Options
  if options and options.TextSize then return options.TextSize(role) end
  return 0
end

local function sizeFont(f)
  local base = _G[f.base]
  if type(base) ~= "table" or type(base.GetFont) ~= "function" then return end
  local path, size, flags = base:GetFont()
  if path and size then f.object:SetFont(path, math.max(6, size + UI.TextSize(f.role)), flags or "") end
end

-- The font object to use for game font `name`: the add-on's sized copy, or
-- `name` itself (not a role's font, no CreateFont, no such game font).
function UI.Font(name)
  local role = UI.FONT_ROLES[name]
  if not role or type(CreateFont) ~= "function" then return name end
  local mine = "MountTrail" .. name
  if not fonts[mine] then
    local base = _G[name]
    if type(base) ~= "table" then return name end
    local good, object = pcall(CreateFont, mine)
    if not (good and object) then return name end
    if object.CopyFontObject then object:CopyFontObject(base) end
    fonts[mine] = { base = name, role = role, object = object }
    sizeFont(fonts[mine])
  end
  return mine
end

-- Taller rows for larger text: a mount row (gold name over a grey line)
-- grows by both sizes' extra points, a header by the gold one's (smaller
-- text never shrinks a row).
local function grow(role) return math.max(0, UI.TextSize(role)) end

function UI.RowHeight(base)
  return base + grow("header") + grow("detail")
end

function UI.HeaderHeight(base)
  return base + grow("header")
end

-- Resizes every copy for the current settings (the text follows), then
-- redraws (row heights follow the sizes).
function UI.ApplyTextSizes()
  for _, f in pairs(fonts) do sizeFont(f) end
  if ns.Refresh then ns.Refresh() end
end

-- Style helpers ------------------------------------------------------------------
-- The window follows Blizzard's current flat panel style (Professions, Delves,
-- the modern Collections). Every template newer than the classic ones goes
-- through UI.Template, so a client without it gets the classic look instead
-- of a broken window.

-- preferred -> fallback for each template the client did not define (shown
-- by `/mtrail debug`).
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
-- Game.ReportError (visible with /mtrail debug).
function UI.Template(preferred, fallback)
  if templateExists(preferred) then return preferred end
  UI.RecordFallback(preferred, fallback)
  return fallback
end

-- The first template of `...` the client defines, checked in order and only
-- as far as needed; the last name is the final fallback and is returned
-- without a check. When the first name is not used, that is recorded once in
-- UI.TemplateFallbacks (first -> the name used) and reported like
-- UI.Template.
function UI.TemplateChain(...)
  local n = select("#", ...)
  local first = (...)
  local chosen
  for i = 1, n do
    local name = select(i, ...)
    if i == n or templateExists(name) then
      chosen = name
      break
    end
  end
  if chosen ~= first then UI.RecordFallback(first, chosen) end
  return chosen
end

-- Records (once) that `missing` (a template, or a method a template lacks)
-- was replaced by `used` (nil: nothing), for /mtrail debug.
function UI.RecordFallback(missing, used)
  if UI.TemplateFallbacks[missing] ~= nil then return end
  UI.TemplateFallbacks[missing] = used or false
  local game = ns.Game
  if game and type(game.ReportError) == "function" then
    game.ReportError(string.format("template %s missing, using %s", tostring(missing), tostring(used or "none")))
  end
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

-- The views, by key (each a content frame; views plug in with
-- UI.RegisterView). The navigation column on the left (UI.NAV) selects them:
-- Home (the journal's front page), Lockouts (the checklist), Current Zone
-- (the zone's mounts; right-click pops them out), the Alts window, Browse
-- (by source, Logic/Browse.lua: a browse page per category, or Holidays /
-- Achievements / Timewalking's own views), then My lists and the quick lists, one entry each (a list opens as
-- a page of the journal view, UI.ShowListPage). A saved key of an older
-- version's tab maps to its successor (UI.LEGACY_TABS: the retired Route tab
-- -> Checklist); any other unknown key falls back to the first view.
local TABS = {
  { key = "journal", label = "Home" },
  { key = "holidays", label = "Holidays" },
  { key = "achievements", label = "Achievements" },
  { key = "timewalking", label = "Timewalking" },
  { key = "misc", label = "Misc" },
  { key = "checklist", label = "Lockouts" },
  { key = "here", label = "Current Zone" },
  { key = "browse", label = "Browse" },
}

UI.LEGACY_TABS = { route = "checklist" }

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

-- The saved window state (ns.db.global.window), or nil before ns.db exists.
function UI.WindowDB()
  return windowDB()
end

-- A tab key to select: `key` when it is a tab, its successor when it is a
-- retired tab's key, else the first tab.
function UI.TabKey(key)
  key = UI.LEGACY_TABS[key] or key
  return key and TAB_INDEX[key] and key or TABS[1].key
end
local validKey = UI.TabKey

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

-- Registers a view. key: "journal", "holidays", "achievements",
-- "timewalking", "misc" (no navigation entry: Browse splits it by source),
-- "checklist", "here" or "browse".
function UI.RegisterView(key, view)
  assert(TAB_INDEX[key], "MountTrail: unknown view key " .. tostring(key))
  assert(type(view) == "table", "MountTrail: view must be a table")
  views[key] = view
  if UI.frame and key == current then showCurrent() end
end

local function savePosition(frame)
  local db = windowDB()
  if not db then return end
  local point, _, relPoint, x, y = frame:GetPoint(1)
  db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end

-- Window size ------------------------------------------------------------------
-- A grip in the bottom-right corner resizes the window freely (any width and
-- height within UI.MIN_SIZE and the screen); the lists, the detail pane and
-- the front page's tiles follow. Right-click the grip: the default size.
-- Saved in ns.db.global.window.width / height. (The old scale setting of
-- earlier versions is dropped: the window is drawn at 100%.)
UI.WINDOW_SIZE = { WIDTH, HEIGHT }
UI.MIN_SIZE = { 820, 480 }

-- A saved size clamped to UI.MIN_SIZE and `maxW` x `maxH` (the screen);
-- junk -> the default size.
function UI.ClampSize(w, h, maxW, maxH)
  if type(w) ~= "number" or type(h) ~= "number" or w ~= w or h ~= h then return WIDTH, HEIGHT end
  w = math.max(UI.MIN_SIZE[1], math.min(maxW or w, w))
  h = math.max(UI.MIN_SIZE[2], math.min(maxH or h, h))
  return math.floor(w + 0.5), math.floor(h + 0.5)
end

-- The window's three boxes (navigation, list, detail pane) share its width
-- through drag handles (UI.Splitter): the navigation's right edge and the
-- detail pane's left edge. Widths are saved in ns.db.global.window
-- (navWidth, paneWidth); right-click a handle for the default.
UI.NAV_MIN, UI.NAV_MAX = 120, 280
UI.PANE_MIN, UI.PANE_MAX = 220, 460

-- Sets the window's size (clamped), keeping its top-left corner on screen
-- where it is, and saves size and position.
function UI.SetWindowSize(frame, w, h)
  local maxW, maxH = UI.ScreenSize()
  w, h = UI.ClampSize(w, h, maxW, maxH)
  local left, top = frame:GetLeft(), frame:GetTop()
  frame:SetSize(w, h)
  if left and top then
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
  end
  local db = windowDB()
  if db then db.width, db.height = w, h end
  savePosition(frame)
end

local function createSizeGrip(frame)
  UI.SetResizeLimits(frame, UI.MIN_SIZE[1], UI.MIN_SIZE[2])
  local grip = UI.ResizeGrip(frame, function(w, h)
    UI.SetWindowSize(frame, w, h)
  end, function()
    UI.SetWindowSize(frame, WIDTH, HEIGHT)
  end)
  frame.SizeGrip = grip
  return grip
end

-- The window's scale: Options' "Window scale" (80-150 %, default 100).
function UI.WindowScale()
  local options = ns.Options
  local pct = options and options.WindowScale and options.WindowScale() or 100
  return pct / 100
end

-- Applies the scale setting to the window (when built).
function UI.ApplyWindowScale()
  if UI.frame then UI.frame:SetScale(UI.WindowScale()) end
end

local function restorePosition(frame)
  local db = windowDB()
  frame:SetScale(UI.WindowScale())
  if db then db.scale = nil end
  local maxW, maxH = UI.ScreenSize()
  frame:SetSize(UI.ClampSize(db and db.width or WIDTH, db and db.height or HEIGHT, maxW, maxH))
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

-- The view on screen (its key).
function UI.CurrentTab()
  return current
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
  showCurrent()
  if UI.RefreshNav then UI.RefreshNav() end
end

-- Settings menu -----------------------------------------------------------------------
-- The title bar's cogwheel: the settings at hand in a flat menu (UI.ShowMenu):
-- the window scale and the text sizes as sliders, the options' checkboxes,
-- and "All options..." for the AddOns page (UI/Options.lua). Each change
-- applies at once.

UI.COG_ATLAS = "QuestLog-icon-setting"
UI.COG_TEXTURE = "Interface\\Buttons\\UI-OptionsButton"

-- Title-bar buttons sit above the window template's border and title art
-- (Retail draws its NineSlice on a high frame level): the close button's
-- level, else a margin above the window's.
function UI.RaiseTitleButton(button, frame)
  if not (button.SetFrameLevel and frame.GetFrameLevel) then return end
  local level = frame:GetFrameLevel() + 20
  local close = frame.CloseButton
  if close and close.GetFrameLevel and close:GetFrameLevel() > level then level = close:GetFrameLevel() end
  button:SetFrameLevel(level)
end

-- The menu's items (rebuilt on each repaint) -> UI.ShowMenu items.
function UI.SettingsMenuItems()
  local O = ns.Options
  if not O then return { { title = L["Settings"] } } end
  local global = ns.db and ns.db.global
  local saved = global and type(global.settings) == "table" and global.settings or {}
  local function check(text, on, flip)
    return { text = text, checked = on, keepOpen = true, onClick = flip }
  end
  local items = {
    { title = L["Settings"] },
    { slider = true, text = L["Window scale"], min = O.SCALE_RANGE.min, max = O.SCALE_RANGE.max,
      step = O.SCALE_RANGE.step, value = O.WindowScale(), format = "%d%%",
      onChange = function(v) O.Set("windowScale", v) end },
  }
  for _, role in ipairs(UI.TEXT_ROLES) do
    items[#items + 1] = { slider = true, text = L[O.TEXT_LABELS[role]], min = O.TEXT_RANGE.min,
      max = O.TEXT_RANGE.max, step = 1, value = O.TextSize(role), format = "%+d",
      onChange = function(v) O.SetTextSize(role, v) end }
  end
  items[#items + 1] = { slider = true, text = L["Navigation text size"], min = O.NAV_TEXT_RANGE.min,
    max = O.NAV_TEXT_RANGE.max, step = 1, value = O.NavTextSize(), format = "+%d",
    onChange = function(v) O.Set("navTextSize", v) end }
  items[#items + 1] = { separator = true }
  items[#items + 1] = check(L["Show unobtainable mounts"], saved.showUnobtainable == true,
    function() O.Set("showUnobtainable", not (saved.showUnobtainable == true)) end)
  items[#items + 1] = check(L["Colour pop-out names by rarity"], saved.rarityColors == true,
    function() O.Set("rarityColors", not (saved.rarityColors == true)) end)
  items[#items + 1] = check(L["Warn about the wrong difficulty"], saved.difficultyWarnOff ~= true,
    function() O.Set("difficultyWarning", saved.difficultyWarnOff == true) end)
  items[#items + 1] = check(L["Show My lists"], saved.navHideLists ~= true,
    function() O.Set("showLists", saved.navHideLists == true) end)
  items[#items + 1] = check(L["Show Quick lists"], saved.navHideQuick ~= true,
    function() O.Set("showQuick", saved.navHideQuick == true) end)
  items[#items + 1] = check(L["Show minimap button"], not (global and global.minimap and global.minimap.hide),
    function() O.Set("minimap", global and global.minimap and global.minimap.hide == true) end)
  items[#items + 1] = { separator = true }
  items[#items + 1] = { text = L["Reset text sizes"], onClick = function() O.ResetTextSizes() end }
  items[#items + 1] = { text = L["All options..."], onClick = function() O.Open() end }
  return items
end

function UI.ShowSettingsMenu(owner)
  if UI.ShowMenu then UI.ShowMenu(owner, UI.SettingsMenuItems, "cursor") end
end

-- Window hooks: fn(frame) runs once the main window is built (right away
-- when it already is), for UI that docks to it (UI/ZonePanel.lua). A hook
-- that errors is reported (Game.ReportError) and never breaks the window.
local windowHooks = {}

local function runWindowHook(fn, frame)
  local good, err = pcall(fn, frame)
  if not good and ns.Game and ns.Game.ReportError then ns.Game.ReportError(err) end
end

function UI.AddWindowHook(fn)
  assert(type(fn) == "function", "MountTrail: window hook must be a function")
  windowHooks[#windowHooks + 1] = fn
  if UI.frame then runWindowHook(fn, UI.frame) end
end

-- Window -----------------------------------------------------------------------

local TITLE_HEIGHT = 24 -- title bar of the portrait frame
local PORTRAIT_RIGHT = 60 -- the portrait covers the top-left corner up to here
local VIEW_TOP = -34 -- the view area starts clear of the title bar and its border (right of the portrait)
local TITLE_BUTTONS_RIGHT = 74 -- close button + two 20 px title-bar buttons (zone panel, settings)
UI.VIEW_TOP = VIEW_TOP -- UI.SetNavWidth moves the views beside the navigation column

local function createWindow()
  local frameTemplate = UI.Template("PortraitFrameFlatTemplate", "PortraitFrameTemplate")
  local flat = frameTemplate == "PortraitFrameFlatTemplate"
  local frame = CreateFrame("Frame", "MountTrailFrame", UIParent, frameTemplate)
  UI.frame = frame
  frame.isFlat = flat
  frame:Hide()
  frame:SetSize(WIDTH, HEIGHT)
  frame:SetToplevel(true)
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  setTitle(frame, L["MountTrail"])
  setPortrait(frame)
  restorePosition(frame)

  -- Drag handle over the title bar (right of the portrait, left of the close
  -- button and the title-bar buttons such as the zone panel toggle). We save
  -- the position ourselves, so opt out of the layout cache.
  local drag = CreateFrame("Frame", nil, frame)
  drag:SetPoint("TOPLEFT", frame, "TOPLEFT", PORTRAIT_RIGHT, 0)
  drag:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -TITLE_BUTTONS_RIGHT, 0)
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
  createSizeGrip(frame)

  -- Content area below the portrait; one content frame per tab inside it
  -- (frame.Contents[key]). Flat window: a plain frame with a slightly darker
  -- flat fill and a faint 1 px edge (the modern inset look). Classic
  -- fallback: the classic inset.
  local inset
  if flat then
    inset = CreateFrame("Frame", nil, frame)
    local fill = inset:CreateTexture(nil, "BACKGROUND")
    fill:SetAllPoints(inset)
    fill:SetColorTexture(0, 0, 0, 0.3)
    inset.Fill = fill
    inset.Edge = UI.FlatBorder(inset, 1, 1, 1, 0.08)
  else
    inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
  end
  -- The navigation column on the left, the views right of it.
  local nav = UI.CreateNav(frame)
  frame.Nav = nav
  inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 6 + UI.NavWidth() + 4, VIEW_TOP)
  inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
  frame.Inset = inset

  -- The navigation's right edge: drag to share the width with the views.
  local split = UI.Splitter(frame, function(x)
    return x - (nav:GetLeft() or 0)
  end, function(w) UI.SetNavWidth(w) end, function(w) UI.SetNavWidth(w, true) end, function()
    UI.SetNavWidth(UI.NAV_WIDTH, true)
  end)
  split:SetPoint("TOPLEFT", nav, "TOPRIGHT", -1, 0)
  split:SetPoint("BOTTOMLEFT", nav, "BOTTOMRIGHT", -1, 0)
  frame.NavSplitter = split

  frame.Contents = contents
  for _, tab in ipairs(TABS) do
    local content = CreateFrame("Frame", nil, inset)
    content:SetPoint("TOPLEFT", inset, "TOPLEFT", 4, -4)
    content:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -4, 4)
    content:Hide()
    contents[tab.key] = content

    local placeholder = content:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableLarge"))
    placeholder:SetPoint("CENTER", content, "CENTER", 0, 0)
    placeholder:SetText(L["Coming soon"])
    placeholders[tab.key] = placeholder
  end

  frame:HookScript("OnShow", showCurrent)
  -- Closed: let the search's prepared fields go.
  frame:HookScript("OnHide", function() if UI.ClearSearchCache then UI.ClearSearchCache() end end)

  -- Esc closes the window.
  tinsert(UISpecialFrames, frame:GetName())

  for _, fn in ipairs(windowHooks) do runWindowHook(fn, frame) end

  -- Settings: a cogwheel in the title bar, left of the zone panel's button.
  local cog = CreateFrame("Button", nil, frame)
  cog:SetSize(20, 20)
  if frame.ZoneButton then
    cog:SetPoint("RIGHT", frame.ZoneButton, "LEFT", -2, 0)
  elseif frame.CloseButton then
    cog:SetPoint("RIGHT", frame.CloseButton, "LEFT", -24, 0)
  else
    cog:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -52, -2)
  end
  local gear = cog:CreateTexture(nil, "ARTWORK")
  gear:SetAllPoints(cog)
  if UI.AtlasExists(UI.COG_ATLAS) then gear:SetAtlas(UI.COG_ATLAS) else gear:SetTexture(UI.COG_TEXTURE) end
  cog.Icon = gear
  UI.RaiseTitleButton(cog, frame)
  local hl = cog:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(cog)
  hl:SetColorTexture(1, 1, 1, 0.15)
  cog:SetScript("OnClick", function(self) UI.ShowSettingsMenu(self) end)
  cog:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Settings"], L["Text sizes, window scale and options"]) end)
  cog:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  frame.SettingsButton = cog

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
-- so UI that lives outside the main window (pop-outs, the zone panel, the Alts window)
-- stays current while the window is closed. Hooks must not raise errors.
local refreshHooks = {}

function UI.AddRefreshHook(fn)
  assert(type(fn) == "function", "MountTrail: refresh hook must be a function")
  refreshHooks[#refreshHooks + 1] = fn
end

-- Runs the refresh hooks, then re-renders the visible tab (nothing more while
-- the window is closed).
-- The views, the navigation and the pop-outs share one Checklist build
-- (UI.ChecklistBuild) while it runs.
ns.Refresh = function()
  UI.refreshing = true
  local good, err = pcall(function()
    for _, fn in ipairs(refreshHooks) do fn() end
    local frame = UI.frame
    if not (frame and frame:IsShown()) then return end
    local view = views[current]
    if view and built[current] and view.Refresh then view.Refresh() end
    UI.RefreshNav()
  end)
  UI.refreshing = false
  if UI.ForgetChecklistBuild then UI.ForgetChecklistBuild() end
  if not good then error(err, 0) end
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
    text = L["MountTrail"],
    icon = ICON,
    OnClick = function(_, button)
      if button == "LeftButton" then ns.ToggleWindow() end
    end,
    OnTooltipShow = function(tooltip)
      tooltip:AddLine(L["MountTrail"])
      tooltip:AddLine(L["Left-click: open/close"], 1, 1, 1)
      if type(UI.ChecklistRemaining) == "function" then
        local left = UI.ChecklistRemaining()
        if type(left) == "number" then
          tooltip:AddLine(string.format(L["Checklist: %d lockouts left"], left), 1, 1, 1)
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
