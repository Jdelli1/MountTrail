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
-- was replaced by `used` (nil: nothing), for /azt debug.
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

-- Hints ----------------------------------------------------------------------------
-- A small hint in the window's own look (instead of the game tooltip): a
-- flat dark panel, slightly see-through, a faint 1 px edge and a thin gold
-- rule on top, a gold title line and an optional grey line under it, in the
-- small font. Follows the owner's scale (the window's size grip). anchor:
-- "cursor" (beside the mouse, for wide rows such as headers), "right", or
-- "above" (default).
local HINT_WIDTH = 260
local hintFrame

local function buildHint()
  local h = CreateFrame("Frame", "AzerothTrailHint", UIParent)
  h:SetFrameStrata("TOOLTIP")
  h:Hide()
  local fill = h:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(h)
  fill:SetColorTexture(0.05, 0.05, 0.06, 0.85)
  h.Fill = fill
  h.Edge = UI.FlatBorder(h, 1, 1, 1, 0.12)
  local rule = h:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", h, "TOPLEFT", 1, -1)
  rule:SetPoint("TOPRIGHT", h, "TOPRIGHT", -1, -1)
  rule:SetColorTexture(1, 0.82, 0, 0.35)
  local title = h:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  title:SetPoint("TOPLEFT", h, "TOPLEFT", 8, -7)
  title:SetJustifyH("LEFT")
  h.Title = title
  local body = h:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  body:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -3)
  body:SetJustifyH("LEFT")
  body:SetWordWrap(true)
  h.Body = body
  return h
end

local function measure(fs)
  local w = fs.GetStringWidth and fs:GetStringWidth() or 0
  local hgt = fs.GetStringHeight and fs:GetStringHeight() or 12
  return tonumber(w) or 0, math.max(tonumber(hgt) or 12, 10)
end

function UI.ShowHint(owner, title, text, anchor)
  if not owner then return end
  hintFrame = hintFrame or buildHint()
  local h = hintFrame
  h.owner = owner
  h.Title:SetText(title or "")
  h.Title:SetWidth(0)
  local tw, th = measure(h.Title)
  local width, height = tw, th
  if text and text ~= "" then
    h.Body:SetWidth(HINT_WIDTH - 16)
    h.Body:SetText(text)
    h.Body:Show()
    local bw, bh = measure(h.Body)
    width = math.max(width, math.min(bw, HINT_WIDTH - 16))
    height = height + 3 + bh
  else
    h.Body:Hide()
  end
  h:SetSize(math.min(HINT_WIDTH, width + 16), height + 14)
  -- The owner's scale (the main window can be scaled with its grip).
  local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
  local ownerScale = owner.GetEffectiveScale and owner:GetEffectiveScale() or parentScale
  if h.SetScale then h:SetScale(ownerScale / parentScale) end
  h:ClearAllPoints()
  if anchor == "cursor" and type(GetCursorPosition) == "function" then
    local x, y = GetCursorPosition()
    local eff = h.GetEffectiveScale and h:GetEffectiveScale() or 1
    h:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / eff + 12, y / eff + 10)
  elseif anchor == "right" then
    h:SetPoint("LEFT", owner, "RIGHT", 6, 0)
  else
    h:SetPoint("BOTTOM", owner, "TOP", 0, 4)
  end
  h:Show()
end

-- Hides the hint (only when `owner` still owns it, when given).
function UI.HideHint(owner)
  if hintFrame and (owner == nil or hintFrame.owner == owner) then
    hintFrame:Hide()
    hintFrame.owner = nil
  end
end

-- Flat widgets ---------------------------------------------------------------------
-- The window's own look for buttons, menus and the name prompt (no Blizzard
-- dropdown menus or dialog art): dark flat panels, a faint edge, a thin
-- gold rule, small fonts.

local FLAT_STYLES = {
  gold = { 1, 0.82, 0, 0.18 },
  green = { 0.25, 0.78, 0.35, 0.25 },
  plain = { 1, 1, 1, 0.07 },
}

-- A flat text button: tinted fill, lighter on hover, small font; width
-- follows the text (UI.FlatButtonSetText). style: "gold" | "green" | "plain".
function UI.FlatButton(parent, text, style, height)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(height or 18)
  local fill = b:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(b)
  fill:SetColorTexture(unpack(FLAT_STYLES[style] or FLAT_STYLES.plain))
  b.Fill = fill
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(b)
  hl:SetColorTexture(1, 1, 1, 0.12)
  local label = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  label:SetPoint("CENTER", b, "CENTER", 0, 0)
  b.Text = label
  UI.FlatButtonSetText(b, text)
  return b
end

function UI.FlatButtonSetText(b, text)
  b.Text:SetText(text or "")
  local w = b.Text.GetStringWidth and b.Text:GetStringWidth() or 40
  b:SetWidth((tonumber(w) or 40) + 14)
end

-- Panel look shared by the menu and the prompt.
local function flatPanel(f, alpha)
  local fill = f:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(f)
  fill:SetColorTexture(0.05, 0.05, 0.06, alpha or 0.95)
  f.Fill = fill
  f.Edge = UI.FlatBorder(f, 1, 1, 1, 0.12)
  local rule = f:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", f, "TOPLEFT", 1, -1)
  rule:SetPoint("TOPRIGHT", f, "TOPRIGHT", -1, -1)
  rule:SetColorTexture(1, 0.82, 0, 0.35)
end

-- Menu: UI.ShowMenu(owner, items[, anchor]) with items (a list, or a
-- function returning one)
--   { title = "Text" }                                 a gold heading
--   { text =, onClick = fn, checked = bool|nil, disabled = bool, keepOpen = bool }
--   { text =, submenu = items }                        opens another menu in its place (">")
--   { slider = true, text =, min =, max =, step =, value =, format =, onChange = fn }
--                                                      a label, the value and a slider (drag, or the
--                                                      wheel); format: "%d%%" or fn(value) -> text
--   { separator = true }
-- A checked / unchecked item shows a small square box (filled gold when
-- checked). A click runs onClick and closes the menu (keepOpen: stays open
-- and repaints). A click anywhere else, Escape, or the owner hiding closes
-- it. A slider reports each change to onChange (not what painting sets) and
-- the rest of the menu repaints, so ticks follow. anchor: "cursor" or below
-- the owner (default). The menu is placed once, when it opens: a keepOpen
-- click or a sub-menu repaints it where it stands.
local MENU_WIDTH = 190
local MENU_ITEM = 18
local MENU_SLIDER = 36
local menu, menuCatcher
local showMenu

-- `value` held to min..max and snapped to the step (whole numbers when none).
function UI.SnapSliderValue(value, min, max, step)
  step = (tonumber(step) or 0) > 0 and step or 1
  value = min + math.floor((value - min) / step + 0.5) * step
  return math.max(min, math.min(max, value))
end

local function sliderText(data, value)
  local fmt = data.format
  if type(fmt) == "function" then return fmt(value) end
  if type(fmt) == "string" then return string.format(fmt, value) end
  return tostring(value)
end

local function buildMenu()
  menuCatcher = CreateFrame("Button", "AzerothTrailMenuCatcher", UIParent)
  menuCatcher:SetAllPoints(UIParent)
  menuCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
  menuCatcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  menuCatcher:SetScript("OnClick", function() UI.HideMenu() end)
  menuCatcher:Hide()
  menu = CreateFrame("Frame", "AzerothTrailMenu", UIParent)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  if menu.SetFrameLevel and menuCatcher.GetFrameLevel then menu:SetFrameLevel(menuCatcher:GetFrameLevel() + 10) end
  menu:SetWidth(MENU_WIDTH)
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  flatPanel(menu)
  menu:Hide()
  menu.items = {}
  tinsert(UISpecialFrames, "AzerothTrailMenu")
  menu:SetScript("OnHide", function() if menuCatcher then menuCatcher:Hide() end end)
  return menu
end

-- A slider row's readout and slider, made when an item first needs them.
local function sliderParts(it)
  if it.Slider then return it.Slider end
  local value = it:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  value:SetPoint("TOPRIGHT", it, "TOPRIGHT", -9, -4)
  value:SetJustifyH("RIGHT")
  it.Value = value
  local s = CreateFrame("Slider", nil, it)
  s:SetOrientation("HORIZONTAL")
  s:SetHeight(14)
  s:SetPoint("TOPLEFT", it, "TOPLEFT", 9, -19)
  s:SetPoint("TOPRIGHT", it, "TOPRIGHT", -9, -19)
  s:EnableMouse(true)
  s:EnableMouseWheel(true)
  s:SetObeyStepOnDrag(true)
  local track = s:CreateTexture(nil, "BACKGROUND")
  track:SetHeight(4)
  track:SetPoint("LEFT", s, "LEFT", 0, 0)
  track:SetPoint("RIGHT", s, "RIGHT", 0, 0)
  track:SetColorTexture(1, 1, 1, 0.15)
  s:SetThumbTexture("Interface\\Buttons\\WHITE8X8")
  local thumb = s:GetThumbTexture()
  thumb:SetSize(8, 14)
  thumb:SetColorTexture(1, 0.82, 0, 0.9)
  -- A change the player makes (drag, wheel): the readout and onChange, then
  -- the rest of the menu repaints (a tick that depends on it). What painting
  -- sets is remembered first, so it is not taken for a change.
  s:SetScript("OnValueChanged", function(self, v)
    local data = self.data
    if not data then return end
    v = UI.SnapSliderValue(v, data.min, data.max, data.step)
    if v == self.last then return end
    self.last = v
    data.value = v -- a list that is not rebuilt repaints with it, not the old value
    it.Value:SetText(sliderText(data, v))
    if data.onChange then data.onChange(v) end
    if menu.lastItems then showMenu(menu.owner, menu.lastItems, menu.anchor, true) end
  end)
  s:SetScript("OnMouseWheel", function(self, delta)
    local data = self.data
    if not data then return end
    local step = (tonumber(data.step) or 0) > 0 and data.step or 1
    self:SetValue(UI.SnapSliderValue(self:GetValue() + delta * step, data.min, data.max, data.step))
  end)
  it.Slider = s
  return s
end

local function menuItem(i)
  local it = menu.items[i]
  if it then return it end
  it = CreateFrame("Button", nil, menu)
  it:SetHeight(MENU_ITEM)
  local hl = it:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(it)
  hl:SetColorTexture(1, 0.82, 0, 0.15)
  it.Highlight = hl
  local box = it:CreateTexture(nil, "ARTWORK")
  box:SetSize(10, 10)
  box:SetPoint("LEFT", it, "LEFT", 8, 0)
  it.Box = box
  local boxEdge = UI.FlatBorder(it, 1, 1, 1, 0.35)
  -- The box's own edge: re-anchor the four edges around the box.
  for k, t in ipairs(boxEdge.edges) do
    t:ClearAllPoints()
    if k == 1 then t:SetPoint("TOPLEFT", box, "TOPLEFT"); t:SetPoint("TOPRIGHT", box, "TOPRIGHT")
    elseif k == 2 then t:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT"); t:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT")
    elseif k == 3 then t:SetPoint("TOPLEFT", box, "TOPLEFT"); t:SetPoint("BOTTOMLEFT", box, "BOTTOMLEFT")
    else t:SetPoint("TOPRIGHT", box, "TOPRIGHT"); t:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT") end
  end
  it.BoxEdge = boxEdge
  local text = it:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetJustifyH("LEFT")
  it.Label = text
  local arrow = it:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  arrow:SetPoint("RIGHT", it, "RIGHT", -8, 0)
  arrow:SetText(">")
  it.Arrow = arrow
  local rule = it:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("LEFT", it, "LEFT", 6, 0)
  rule:SetPoint("RIGHT", it, "RIGHT", -6, 0)
  rule:SetColorTexture(1, 1, 1, 0.12)
  it.Rule = rule
  it:SetScript("OnClick", function(self)
    local data = self.data
    if not data or data.title or data.separator or data.disabled or data.slider then return end
    if data.submenu then
      showMenu(menu.owner, data.submenu, menu.anchor, true)
      return
    end
    if data.onClick then data.onClick(data) end
    if data.keepOpen and menu.lastItems then
      showMenu(menu.owner, menu.lastItems, menu.anchor, true)
    else
      UI.HideMenu()
    end
  end)
  menu.items[i] = it
  return it
end

-- inPlace: a repaint of the open menu (a keepOpen click, a sub-menu, a
-- slider): its place and scale stay as they are.
function showMenu(owner, items, anchor, inPlace)
  if not menu then buildMenu() end
  inPlace = inPlace and menu:IsShown()
  menu.owner, menu.lastItems, menu.anchor = owner, items, anchor
  -- items may be a function that builds the list (a keepOpen click
  -- repaints from it, so ticks follow the click).
  if type(items) == "function" then items = items() end
  local y = 6
  for i, data in ipairs(items or {}) do
    local it = menuItem(i)
    it.data = data
    it:ClearAllPoints()
    it:SetPoint("TOPLEFT", menu, "TOPLEFT", 1, -y)
    it:SetPoint("TOPRIGHT", menu, "TOPRIGHT", -1, -y)
    it.Label:ClearAllPoints()
    local boxed = data.checked ~= nil
    it.Box:SetShown(boxed)
    for _, t in ipairs(it.BoxEdge.edges) do t:SetShown(boxed) end
    if data.slider then
      it.Label:SetPoint("TOPLEFT", it, "TOPLEFT", 9, -4)
    elseif boxed then
      it.Box:SetColorTexture(1, 0.82, 0, data.checked and 0.9 or 0)
      it.Label:SetPoint("LEFT", it.Box, "RIGHT", 6, 0)
    else
      it.Label:SetPoint("LEFT", it, "LEFT", 9, 0)
    end
    it.Rule:SetShown(data.separator == true)
    it.Arrow:SetShown(data.submenu ~= nil)
    it.Highlight:SetShown(not (data.title or data.separator or data.disabled or data.slider))
    if it.Slider then
      it.Slider:SetShown(data.slider == true)
      it.Value:SetShown(data.slider == true)
    end
    if data.slider then
      local s = sliderParts(it)
      local v = UI.SnapSliderValue(tonumber(data.value) or data.min, data.min, data.max, data.step)
      -- The range is only set when it differs: a repaint while dragging
      -- must not touch the slider being dragged.
      local range = data.min .. ":" .. data.max .. ":" .. tostring(data.step)
      s.data = nil -- while painting: whatever the slider says is not a change
      if s.range ~= range then
        s.range = range
        s:SetMinMaxValues(data.min, data.max)
        s:SetValueStep(tonumber(data.step) or 1)
      end
      s.last = v
      if s:GetValue() ~= v then s:SetValue(v) end
      s.data = data
      it:SetHeight(MENU_SLIDER)
      it.Label:SetText(data.text or "")
      it.Label:SetFontObject("GameFontHighlightSmall")
      it.Value:SetText(sliderText(data, v))
      y = y + MENU_SLIDER
    elseif data.separator then
      it:SetHeight(7)
      it.Label:SetText("")
      y = y + 7
    else
      it:SetHeight(MENU_ITEM)
      it.Label:SetText(data.title or data.text or "")
      it.Label:SetFontObject(data.title and "GameFontNormalSmall"
        or (data.disabled and "GameFontDisableSmall" or "GameFontHighlightSmall"))
      y = y + MENU_ITEM
    end
    it:Show()
  end
  for i = #(items or {}) + 1, #menu.items do menu.items[i]:Hide() end
  menu:SetHeight(y + 5)
  if not inPlace then
    -- Placed when it opens only: reading the pointer again on a repaint put
    -- the menu's corner under the row just clicked, so it crept down.
    local parentScale = UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
    local ownerScale = owner and owner.GetEffectiveScale and owner:GetEffectiveScale() or parentScale
    if menu.SetScale then menu:SetScale(ownerScale / parentScale) end
    menu:ClearAllPoints()
    if anchor == "cursor" and type(GetCursorPosition) == "function" then
      local x, cy = GetCursorPosition()
      local eff = menu.GetEffectiveScale and menu:GetEffectiveScale() or 1
      menu:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / eff + 4, cy / eff - 4)
    elseif owner then
      menu:SetPoint("TOPLEFT", owner, "BOTTOMLEFT", 0, -2)
    else
      menu:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
  end
  menuCatcher:Show()
  menu:Show()
  if UI.HideHint then UI.HideHint() end
  return menu
end

function UI.ShowMenu(owner, items, anchor)
  return showMenu(owner, items, anchor, false)
end

function UI.HideMenu()
  if menu then menu:Hide() end
  if menuCatcher then menuCatcher:Hide() end
end

-- Expansion badge: a small coloured tag with the expansion's short name
-- (UI.ExpansionTag: "WOD", "SL" ...), hidden for mounts without one.
local EXPANSION_COLORS = {
  ["Classic"] = { 0.85, 0.7, 0.35 }, ["The Burning Crusade"] = { 0.4, 0.8, 0.25 },
  ["Wrath of the Lich King"] = { 0.45, 0.75, 1 }, ["Cataclysm"] = { 0.95, 0.45, 0.15 },
  ["Mists of Pandaria"] = { 0.2, 0.8, 0.6 }, ["Warlords of Draenor"] = { 0.75, 0.35, 0.2 },
  ["Legion"] = { 0.45, 0.95, 0.2 }, ["Battle for Azeroth"] = { 0.3, 0.5, 0.95 },
  ["Shadowlands"] = { 0.6, 0.65, 0.8 }, ["Dragonflight"] = { 0.95, 0.3, 0.3 },
  ["The War Within"] = { 0.9, 0.65, 0.3 }, ["Midnight"] = { 0.7, 0.45, 0.95 },
}
UI.EXPANSION_COLORS = EXPANSION_COLORS

function UI.ExpansionBadge(parent)
  local b = CreateFrame("Frame", nil, parent)
  b:SetSize(30, 12)
  local fill = b:CreateTexture(nil, "ARTWORK")
  fill:SetAllPoints(b)
  b.Fill = fill
  local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("CENTER", b, "CENTER", 0, 0)
  if text.SetFont and text.GetFont then
    local font, _, flags = text:GetFont()
    if font then text:SetFont(font, 8, flags) end
  end
  b.Text = text
  return b
end

-- Paints a badge for `exp` (hidden when it has no tag).
function UI.SetExpansionBadge(b, exp)
  local tag = UI.ExpansionTag and UI.ExpansionTag(exp) or nil
  if not tag then
    b:Hide()
    b:SetWidth(1)
    return
  end
  local c = EXPANSION_COLORS[exp] or { 0.6, 0.6, 0.6 }
  b.Fill:SetColorTexture(c[1], c[2], c[3], 0.35)
  b.Text:SetText(tag)
  b.Text:SetTextColor(math.min(1, c[1] + 0.35), math.min(1, c[2] + 0.35), math.min(1, c[3] + 0.35))
  b:SetWidth((b.Text.GetStringWidth and b.Text:GetStringWidth() or 24) + 6)
  b.exp = exp
  b:SetScript("OnEnter", function(self) UI.ShowHint(self, L[exp]) end)
  b:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  if b.EnableMouse then b:EnableMouse(true) end
  b:Show()
end

-- Name prompt: UI.AskText(title, default, onAccept[, opts]) - a small flat
-- dialog with a text box, OK and Cancel; Enter accepts, Escape cancels.
-- onAccept gets the trimmed text (not called for an empty one). opts:
--   match = text the box must hold (trimmed, any case) before OK works
--           (OK greyed out until then; the typed-name check before a delete),
--   okLabel = the OK button's text, danger = true for a red OK button,
--   hint = a small grey line under the title.
local prompt

-- Whether the box's text is what opts.match asks for (trimmed, any case).
function UI.PromptMatches(text, match)
  if match == nil then return true end
  local t = string.lower(string.match(text or "", "^%s*(.-)%s*$"))
  return t ~= "" and t == string.lower(string.match(match, "^%s*(.-)%s*$"))
end

local function paintOK()
  local good = UI.PromptMatches(prompt.Edit:GetText(), prompt.match)
  prompt.OK:SetEnabled(good)
  if prompt.OK.SetAlpha then prompt.OK:SetAlpha(good and 1 or 0.4) end
end

local function buildPrompt()
  prompt = CreateFrame("Frame", "AzerothTrailPrompt", UIParent)
  prompt:SetSize(280, 104)
  prompt:SetFrameStrata("FULLSCREEN_DIALOG")
  prompt:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  prompt:EnableMouse(true)
  flatPanel(prompt, 0.97)
  prompt:Hide()
  tinsert(UISpecialFrames, "AzerothTrailPrompt")
  local title = prompt:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", prompt, "TOPLEFT", 12, -12)
  title:SetPoint("TOPRIGHT", prompt, "TOPRIGHT", -12, -12)
  title:SetJustifyH("LEFT")
  prompt.Title = title
  local hint = prompt:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  hint:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -4)
  hint:SetJustifyH("LEFT")
  hint:Hide()
  prompt.Hint = hint
  local boxFrame = CreateFrame("Frame", nil, prompt)
  boxFrame:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -10)
  boxFrame:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -10)
  prompt.Box = boxFrame
  boxFrame:SetHeight(24)
  local boxFill = boxFrame:CreateTexture(nil, "BACKGROUND")
  boxFill:SetAllPoints(boxFrame)
  boxFill:SetColorTexture(0, 0, 0, 0.5)
  UI.FlatBorder(boxFrame, 1, 1, 1, 0.2)
  local edit = CreateFrame("EditBox", nil, boxFrame)
  edit:SetPoint("TOPLEFT", boxFrame, "TOPLEFT", 6, 0)
  edit:SetPoint("BOTTOMRIGHT", boxFrame, "BOTTOMRIGHT", -6, 0)
  if edit.SetFontObject then edit:SetFontObject("GameFontHighlight") end
  if edit.SetAutoFocus then edit:SetAutoFocus(false) end
  if edit.SetMaxLetters then edit:SetMaxLetters(40) end
  prompt.Edit = edit
  local function accept()
    local text = string.match(edit:GetText() or "", "^%s*(.-)%s*$")
    if not UI.PromptMatches(text, prompt.match) then return end
    local fn = prompt.onAccept
    prompt:Hide()
    if fn and text ~= "" then fn(text) end
  end
  edit:SetScript("OnEnterPressed", accept)
  edit:SetScript("OnTextChanged", function() paintOK() end)
  edit:SetScript("OnEscapePressed", function() prompt:Hide() end)
  local ok = UI.FlatButton(prompt, L["OK"], "gold", 20)
  ok:SetWidth(70)
  ok:SetPoint("BOTTOMRIGHT", prompt, "BOTTOMRIGHT", -12, 10)
  ok:SetScript("OnClick", accept)
  prompt.OK = ok
  local cancel = UI.FlatButton(prompt, L["Cancel"], "plain", 20)
  cancel:SetWidth(70)
  cancel:SetPoint("RIGHT", ok, "LEFT", -6, 0)
  cancel:SetScript("OnClick", function() prompt:Hide() end)
  prompt.Cancel = cancel
  return prompt
end

function UI.AskText(title, default, onAccept, opts)
  if not prompt then buildPrompt() end
  opts = opts or {}
  UI.HideMenu()
  prompt.Title:SetText(title or "")
  prompt.onAccept = onAccept
  prompt.match = opts.match
  prompt.Hint:SetText(opts.hint or "")
  prompt.Hint:SetShown(opts.hint ~= nil)
  -- The box sits under the hint when there is one.
  prompt.Box:ClearAllPoints()
  local above = opts.hint and prompt.Hint or prompt.Title
  prompt.Box:SetPoint("TOPLEFT", above, "BOTTOMLEFT", 0, opts.hint and -6 or -10)
  prompt.Box:SetPoint("TOPRIGHT", above, "BOTTOMRIGHT", 0, opts.hint and -6 or -10)
  prompt:SetHeight(opts.hint and 120 or 104)
  UI.FlatButtonSetText(prompt.OK, opts.okLabel or L["OK"])
  prompt.OK:SetWidth(70)
  prompt.OK.Fill:SetColorTexture(unpack(opts.danger and { 0.85, 0.2, 0.15, 0.45 } or { 1, 0.82, 0, 0.18 }))
  prompt.Edit:SetText(default or "")
  paintOK()
  prompt:Show()
  if prompt.Edit.SetFocus then prompt.Edit:SetFocus() end
  if prompt.Edit.HighlightText then prompt.Edit:HighlightText() end
  return prompt
end

-- Tab order is fixed; views plug in by key. A saved key of an older
-- version's tab maps to its successor (UI.LEGACY_TABS: the retired Route tab
-- -> Checklist); any other unknown key falls back to the first tab.
local TABS = {
  { key = "journal", label = "Journal" },
  { key = "holidays", label = "Holidays" },
  { key = "achievements", label = "Achievements" },
  { key = "timewalking", label = "Timewalking" },
  { key = "misc", label = "Misc" },
  { key = "checklist", label = "Checklist" },
}

UI.LEGACY_TABS = { route = "checklist" }

-- Tab widths for PanelTemplates_TabResize: each tab fits its text plus 10 px
-- of extra padding (on top of the template's 20 px sides), at least 70 px so
-- Misc is not stubby, at most 116 px so a long translation
-- truncates instead of pushing the row past the window: 6 x 116 + gaps
-- stays inside the 800 px window from the 60 px portrait offset.
UI.TabSize = { padding = 10, min = 70, max = 116 }
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

-- Registers a tab view. key: "journal", "holidays", "achievements",
-- "timewalking", "misc" or "checklist".
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

-- Window size ------------------------------------------------------------------
-- A grip in the bottom-right corner resizes the window freely (any width and
-- height within UI.MIN_SIZE and the screen); the lists, the detail pane and
-- the front page's tiles follow. Right-click the grip: the default size.
-- Saved in ns.db.global.window.width / height. (The old scale setting of
-- earlier versions is dropped: the window is drawn at 100%.)
UI.WINDOW_SIZE = { WIDTH, HEIGHT }
UI.MIN_SIZE = { 700, 480 }

-- A saved size clamped to UI.MIN_SIZE and `maxW` x `maxH` (the screen);
-- junk -> the default size.
function UI.ClampSize(w, h, maxW, maxH)
  if type(w) ~= "number" or type(h) ~= "number" or w ~= w or h ~= h then return WIDTH, HEIGHT end
  w = math.max(UI.MIN_SIZE[1], math.min(maxW or w, w))
  h = math.max(UI.MIN_SIZE[2], math.min(maxH or h, h))
  return math.floor(w + 0.5), math.floor(h + 0.5)
end

local function screenSize()
  local w = UIParent.GetWidth and UIParent:GetWidth() or nil
  local h = UIParent.GetHeight and UIParent:GetHeight() or nil
  if type(w) ~= "number" or w <= 0 then w = nil end
  if type(h) ~= "number" or h <= 0 then h = nil end
  return w, h
end

-- Resize limits on `frame` (SetResizeBounds; SetMinResize on older clients).
function UI.SetResizeLimits(frame, minW, minH)
  if frame.SetResizable then frame:SetResizable(true) end
  local maxW, maxH = screenSize()
  if frame.SetResizeBounds then
    frame:SetResizeBounds(minW, minH, maxW or 4000, maxH or 3000)
  elseif frame.SetMinResize then
    frame:SetMinResize(minW, minH)
  end
end

local GRIP_SIZE = 14 -- in the corner, clear of the lists' scroll bars
local GRIP = "Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-"

-- A corner grip that resizes `frame` (StartSizing); onDone(w, h) after a
-- drag, onReset() on right-click; `hint` for the hover.
function UI.ResizeGrip(frame, onDone, onReset, hint)
  local grip = CreateFrame("Button", nil, frame)
  grip:SetSize(GRIP_SIZE, GRIP_SIZE)
  grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -1, 1)
  grip:SetFrameLevel(frame:GetFrameLevel() + 20)
  grip:SetNormalTexture(GRIP .. "Up")
  grip:SetHighlightTexture(GRIP .. "Highlight")
  grip:SetPushedTexture(GRIP .. "Down")
  grip:RegisterForClicks("RightButtonUp")
  grip:SetScript("OnMouseDown", function(_, button)
    if button ~= "LeftButton" or not frame.StartSizing then return end
    frame.sizing = true
    frame:StartSizing("BOTTOMRIGHT")
  end)
  local function stop()
    if not frame.sizing then return end
    frame.sizing = nil
    frame:StopMovingOrSizing()
    if frame.SetUserPlaced then frame:SetUserPlaced(false) end
    if onDone then onDone(frame:GetWidth(), frame:GetHeight()) end
  end
  grip:SetScript("OnMouseUp", stop)
  grip:SetScript("OnHide", stop)
  grip:SetScript("OnClick", function(_, button)
    if button == "RightButton" and onReset then onReset() end
  end)
  grip:SetScript("OnEnter", function(self)
    UI.ShowHint(self, L["Drag to resize"], hint or L["Right-click: default size"], "right")
  end)
  grip:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  return grip
end

-- Sets the window's size (clamped), keeping its top-left corner on screen
-- where it is, and saves size and position.
function UI.SetWindowSize(frame, w, h)
  local maxW, maxH = screenSize()
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

local function restorePosition(frame)
  local db = windowDB()
  frame:SetScale(1)
  if db then db.scale = nil end
  local maxW, maxH = screenSize()
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
local TITLE_BUTTONS_RIGHT = 52 -- close button + one 20 px title-bar button

-- Window hooks: fn(frame) runs once the main window is built (right away
-- when it already is), for UI that docks to it (UI/ZonePanel.lua). A hook
-- that errors is reported (Game.ReportError) and never breaks the window.
local windowHooks = {}

local function runWindowHook(fn, frame)
  local good, err = pcall(fn, frame)
  if not good and ns.Game and ns.Game.ReportError then ns.Game.ReportError(err) end
end

function UI.AddWindowHook(fn)
  assert(type(fn) == "function", "AzerothTrail: window hook must be a function")
  windowHooks[#windowHooks + 1] = fn
  if UI.frame then runWindowHook(fn, UI.frame) end
end

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
  inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, CONTENT_TOP)
  inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
  frame.Inset = inset

  -- Tabs: modern top tabs between the title bar and the content (right of
  -- the portrait); classic bottom tabs when the client lacks the template.
  local tabTemplate = UI.Template("PanelTopTabButtonTemplate", "PanelTabButtonTemplate")
  local topTabs = tabTemplate == "PanelTopTabButtonTemplate"
  frame.topTabs = topTabs

  frame.Tabs = {}
  frame.Contents = contents
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
    if PanelTemplates_TabResize then
      local size = UI.TabSize
      PanelTemplates_TabResize(button, size.padding, nil, size.min, size.max)
    end
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

  for _, fn in ipairs(windowHooks) do runWindowHook(fn, frame) end

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
-- so UI that lives outside the main window (the parked route arrow, UI\Arrow.lua)
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
