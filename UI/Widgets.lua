local ADDON, ns = ...

-- The add-on's own widgets, in the window's flat look and not tied to the
-- main window: hints, flat buttons and panels, the menu (with sliders), the
-- expansion badge, the text prompt, splitters and the resize grip. The main
-- window, the pop-outs and the Alts window all build from these.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

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
  local h = CreateFrame("Frame", "MountTrailHint", UIParent)
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
  local title = h:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalSmall"))
  title:SetPoint("TOPLEFT", h, "TOPLEFT", 8, -7)
  title:SetJustifyH("LEFT")
  h.Title = title
  local body = h:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
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
  local label = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
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
local MENU_WIDTH = 190 -- the narrowest a menu gets
local MENU_MAX_WIDTH = 340 -- wider lines wrap
local MENU_TEXT_LEFT, MENU_TEXT_LEFT_BOXED, MENU_TEXT_RIGHT = 9, 24, 22
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
  menuCatcher = CreateFrame("Button", "MountTrailMenuCatcher", UIParent)
  menuCatcher:SetAllPoints(UIParent)
  menuCatcher:SetFrameStrata("FULLSCREEN_DIALOG")
  menuCatcher:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  menuCatcher:SetScript("OnClick", function() UI.HideMenu() end)
  menuCatcher:Hide()
  menu = CreateFrame("Frame", "MountTrailMenu", UIParent)
  menu:SetFrameStrata("FULLSCREEN_DIALOG")
  if menu.SetFrameLevel and menuCatcher.GetFrameLevel then menu:SetFrameLevel(menuCatcher:GetFrameLevel() + 10) end
  menu:SetWidth(MENU_WIDTH)
  menu:SetClampedToScreen(true)
  menu:EnableMouse(true)
  flatPanel(menu)
  menu:Hide()
  menu.items = {}
  tinsert(UISpecialFrames, "MountTrailMenu")
  menu:SetScript("OnHide", function() if menuCatcher then menuCatcher:Hide() end end)
  return menu
end

-- A slider row's readout and slider, made when an item first needs them.
local function sliderParts(it)
  if it.Slider then return it.Slider end
  local value = it:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalSmall"))
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
  local text = it:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
  text:SetJustifyH("LEFT")
  it.Label = text
  local arrow = it:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
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
  -- The menu fits its longest line (MENU_WIDTH .. MENU_MAX_WIDTH); longer
  -- lines wrap onto more rows instead of running past the edge.
  local width = MENU_WIDTH
  for i, data in ipairs(items or {}) do
    local label = data.title or data.text
    if label and label ~= "" and not data.separator then
      local it = menuItem(i)
      it.Label:SetFontObject(data.title and UI.Font("GameFontNormalSmall") or UI.Font("GameFontHighlightSmall"))
      it.Label:SetWidth(0)
      it.Label:SetText(label)
      local w = tonumber(it.Label.GetStringWidth and it.Label:GetStringWidth()) or 0
      local left = data.checked ~= nil and MENU_TEXT_LEFT_BOXED or MENU_TEXT_LEFT
      width = math.max(width, math.ceil(w) + left + MENU_TEXT_RIGHT)
    end
  end
  width = math.min(width, MENU_MAX_WIDTH)
  menu:SetWidth(width)
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
      it.Label:SetWidth(0)
      it.Label:SetText(data.text or "")
      it.Label:SetFontObject("GameFontHighlightSmall")
      it.Value:SetText(sliderText(data, v))
      y = y + MENU_SLIDER
    elseif data.separator then
      it:SetHeight(7)
      it.Label:SetText("")
      y = y + 7
    else
      it.Label:SetFontObject(data.title and UI.Font("GameFontNormalSmall")
        or (data.disabled and UI.Font("GameFontDisableSmall") or UI.Font("GameFontHighlightSmall")))
      local left = boxed and MENU_TEXT_LEFT_BOXED or MENU_TEXT_LEFT
      it.Label:SetWidth(width - left - MENU_TEXT_RIGHT)
      if it.Label.SetWordWrap then it.Label:SetWordWrap(true) end
      it.Label:SetText(data.title or data.text or "")
      local h = tonumber(it.Label.GetStringHeight and it.Label:GetStringHeight()) or 0
      local rowH = math.max(MENU_ITEM, math.ceil(h) + 6)
      it:SetHeight(rowH)
      y = y + rowH
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
  local text = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
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
  prompt = CreateFrame("Frame", "MountTrailPrompt", UIParent)
  prompt:SetSize(280, 104)
  prompt:SetFrameStrata("FULLSCREEN_DIALOG")
  prompt:SetPoint("CENTER", UIParent, "CENTER", 0, 120)
  prompt:EnableMouse(true)
  flatPanel(prompt, 0.97)
  prompt:Hide()
  tinsert(UISpecialFrames, "MountTrailPrompt")
  local title = prompt:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
  title:SetPoint("TOPLEFT", prompt, "TOPLEFT", 12, -12)
  title:SetPoint("TOPRIGHT", prompt, "TOPRIGHT", -12, -12)
  title:SetJustifyH("LEFT")
  prompt.Title = title
  local hint = prompt:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
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
  if edit.SetMaxLetters then edit:SetMaxLetters(200) end
  prompt.Edit = edit
  local function accept()
    if prompt.copy then prompt:Hide() return end
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

-- A box with `text` selected to copy (Ctrl+C); Enter, Esc or Close shut it.
function UI.ShowCopyText(title, text, hint)
  return UI.AskText(title, text, nil, { copy = true, hint = hint, okLabel = L["Close"] })
end

function UI.AskText(title, default, onAccept, opts)
  if not prompt then buildPrompt() end
  opts = opts or {}
  UI.HideMenu()
  prompt.Title:SetText(title or "")
  prompt.onAccept = onAccept
  prompt.copy = opts.copy == true
  prompt.Cancel:SetShown(not prompt.copy)
  -- Names: 40 letters; a copy box or a pasted list (opts.long): no limit.
  if prompt.Edit.SetMaxLetters then prompt.Edit:SetMaxLetters((opts.copy or opts.long) and 0 or 40) end
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

-- Splitters --------------------------------------------------------------------------
-- A drag handle between two side-by-side boxes shares their width (the main
-- window's navigation, list and detail pane); right-click it for the default.

-- `w` held to min..max (whole pixels); junk -> `default`.
function UI.ClampWidth(w, min, max, default)
  w = tonumber(w)
  if not w or w ~= w then return default end
  return math.floor(math.max(min, math.min(max, w)) + 0.5)
end

-- The cursor's x in `region`'s coordinates, or nil.
local function cursorX(region)
  if type(GetCursorPosition) ~= "function" then return nil end
  local x = GetCursorPosition()
  local scale = region.GetEffectiveScale and region:GetEffectiveScale() or 1
  if type(x) ~= "number" or not scale or scale == 0 then return nil end
  return x / scale
end
UI.CursorX = cursorX

-- A vertical drag handle on `parent`: while dragged, widthAt(cursorX) is the
-- new width, apply(w) shows it; done(w) on release (saves); right-click:
-- reset(). The caller anchors it. -> the handle.
function UI.Splitter(parent, widthAt, apply, done, reset)
  local h = CreateFrame("Button", nil, parent)
  h:SetWidth(6)
  h:SetFrameLevel((parent.GetFrameLevel and parent:GetFrameLevel() or 1) + 10)
  if h.RegisterForClicks then h:RegisterForClicks("RightButtonUp") end
  local line = h:CreateTexture(nil, "HIGHLIGHT")
  line:SetPoint("TOP", h, "TOP", 0, 0)
  line:SetPoint("BOTTOM", h, "BOTTOM", 0, 0)
  line:SetWidth(2)
  line:SetColorTexture(1, 0.82, 0, 0.6)
  h:SetScript("OnMouseDown", function(self, button)
    if button ~= "LeftButton" then return end
    self.dragging = true
    self:SetScript("OnUpdate", function()
      local x = cursorX(self)
      if not x then return end
      self.width = widthAt(x)
      apply(self.width)
    end)
  end)
  local function stop(self)
    if not self.dragging then return end
    self.dragging = false
    self:SetScript("OnUpdate", nil)
    if self.width then done(self.width) end
  end
  h:SetScript("OnMouseUp", stop)
  h:SetScript("OnHide", stop)
  h:SetScript("OnClick", function(_, button) if button == "RightButton" and reset then reset() end end)
  h:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Drag to resize"], L["Right-click: default width"]) end)
  h:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  return h
end

-- Resize grip ------------------------------------------------------------------

-- The screen's size (UIParent), each part nil when unknown.
function UI.ScreenSize()
  local w = UIParent.GetWidth and UIParent:GetWidth() or nil
  local h = UIParent.GetHeight and UIParent:GetHeight() or nil
  if type(w) ~= "number" or w <= 0 then w = nil end
  if type(h) ~= "number" or h <= 0 then h = nil end
  return w, h
end

-- Resize limits on `frame` (SetResizeBounds; SetMinResize on older clients).
function UI.SetResizeLimits(frame, minW, minH)
  if frame.SetResizable then frame:SetResizable(true) end
  local maxW, maxH = UI.ScreenSize()
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
