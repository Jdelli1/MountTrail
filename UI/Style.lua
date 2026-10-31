local ADDON, ns = ...

-- The look shared by MountTrail's own windows: the pop-outs (UI/Popouts.lua),
-- the main window (UI/Frame.lua) and the extra windows (the alt lockout
-- matrix, the guide window). A window's style is its own (saved under its
-- key in ns.db.global.popouts), else the shared one ("Apply to all
-- pop-outs", ns.db.global.popoutStyle), over the defaults. Right-click a
-- window's title for its appearance menu (UI.PopoutStyleMenu).

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local function popoutsDB()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.popouts) ~= "table" then global.popouts = {} end
  return global.popouts
end

-- Appearance of a window (right-click its title). Saved per window as
-- { alpha =, bg = { r, g, b }, text = { r, g, b }, size =, font = };
-- missing fields take the defaults (the window's own look). Opacity runs
-- 0.2-1 and the font size 8-24 (whole points): the menu's two sliders.
UI.POPOUT_STYLE = { alpha = 0.92, bg = { 0.06, 0.06, 0.07 }, text = nil, size = nil, font = nil }
local ALPHA_MIN, SIZE_MIN, SIZE_MAX = 0.2, 8, 24
UI.POPOUT_FONTS = {
  { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
  { name = "Arial Narrow", path = "Fonts\\ARIALN.TTF" },
  { name = "Morpheus", path = "Fonts\\MORPHEUS.TTF" },
  { name = "Skurri", path = "Fonts\\SKURRI.TTF" },
}

-- A saved style over the defaults -> a full style table.
function UI.PopoutStyle(saved)
  local d = UI.POPOUT_STYLE
  saved = type(saved) == "table" and saved or {}
  local alpha, size = tonumber(saved.alpha), tonumber(saved.size)
  return {
    alpha = alpha and math.max(ALPHA_MIN, math.min(1, alpha)) or d.alpha,
    bg = type(saved.bg) == "table" and saved.bg or d.bg,
    text = type(saved.text) == "table" and saved.text or d.text,
    header = type(saved.header) == "table" and saved.header or nil,
    size = size and math.max(SIZE_MIN, math.min(SIZE_MAX, math.floor(size + 0.5))) or d.size,
    font = type(saved.font) == "string" and saved.font or d.font,
  }
end

-- The text size a window has until one is chosen: the small font's own (the
-- font object's height), held to the slider's range; 11 when it cannot be
-- read.
function UI.PopoutDefaultSize()
  local fo = _G.GameFontHighlightSmall
  local _, height
  if type(fo) == "table" and type(fo.GetFont) == "function" then _, height = fo:GetFont() end
  height = tonumber(height)
  if not height then return 11 end
  return math.max(SIZE_MIN, math.min(SIZE_MAX, math.floor(height + 0.5)))
end

-- A font string in the window's style: the style's font / size when set
-- (else the given font object) and text colour.
local function styleText(fs, style, fontObject, sizeDelta, color)
  fs:SetFontObject(fontObject)
  if (style.font or style.size) and fs.GetFont and fs.SetFont then
    local path, size, flags = fs:GetFont()
    if style.size then size = style.size + (sizeDelta or 0) end
    path = style.font or path
    if path and size then fs:SetFont(path, size, flags or "") end
  end
  local c = color or style.text
  if c then
    fs:SetTextColor(c[1], c[2], c[3])
  else
    local fo = _G[fontObject]
    if type(fo) == "table" and fo.GetTextColor then fs:SetTextColor(fo:GetTextColor()) end
  end
end

-- The look every window has unless it has its own ("Apply to all pop-outs").
local function sharedStyle()
  local global = ns.db and ns.db.global
  return global and type(global.popoutStyle) == "table" and global.popoutStyle or nil
end

-- The window's own style, else the shared one, over the defaults.
local function styleOf(w)
  local db = popoutsDB()
  local state = db and db[w.key]
  return UI.PopoutStyle(state and state.style or sharedStyle())
end

-- A title or header in a style: its font and size, the Header colour, else
-- `fallback`, else the font's own colour (gold). Never the Text colour:
-- headers and body text are set apart in the appearance menu.
local function headerText(fs, style, fontObject, sizeDelta, fallback)
  styleText(fs, { font = style.font, size = style.size }, fontObject, sizeDelta, style.header or fallback)
end

-- The window's background and title in its style.
local function applyChrome(w, style)
  w.Fill:SetColorTexture(style.bg[1], style.bg[2], style.bg[3], style.alpha)
  headerText(w.Title, style, UI.Font("GameFontNormal"), 2)
end

-- Windows outside this file that take the pop-outs' appearance menu, their
-- shared look ("Apply to all pop-outs") and their snapping (the alt lockout
-- matrix, UI/AltsWindow.lua). Each has `key` (its slot in
-- ns.db.global.popouts, holding only its style) and Restyle(chromeOnly):
-- repaint the background only, or redraw everything in the new style.
local extras = {}

function UI.AddStyledWindow(w)
  extras[#extras + 1] = w
end

-- A window's style (its own, else the shared one, over the defaults), and a
-- font string in a style, for the extra windows.
UI.PopoutStyleOf = function(w) return styleOf(w) end
UI.PopoutStyleText = styleText
UI.PopoutStyleHeader = headerText
UI.PopoutApplyChrome = applyChrome

-- A page's 30 px header in the pop-outs' look (no band, a thin rule under
-- it): a flat Back button when `withBack`, then the title -> back|nil, title.
-- The page's content starts UI.PAGE_TOP down.
UI.PAGE_TOP = -36
function UI.PageHeader(page, withBack)
  local rule = page:CreateTexture(nil, "BORDER")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -30)
  rule:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, -30)
  rule:SetColorTexture(1, 1, 1, 0.1)
  page.Rule = rule
  local back
  if withBack then
    back = UI.FlatButton(page, L["Back"], "plain", 22)
    back:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -4)
    page.Back = back
  end
  local title = page:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalLarge"))
  if back then
    title:SetPoint("LEFT", back, "RIGHT", 12, 0)
  else
    title:SetPoint("LEFT", page, "TOPLEFT", 10, -15)
  end
  page.Title = title
  return back, title
end

-- A flat button for a page's header (Pop out), at its top right.
function UI.PageButton(page, text)
  local b = UI.FlatButton(page, text, "plain", 22)
  b:SetPoint("TOPRIGHT", page, "TOPRIGHT", -4, -4)
  return b
end

-- The extra windows, in the order they were added (UI.AddStyledWindow).
function UI.StyledWindows()
  return extras
end

-- Redraws the pop-outs and the extra windows after a style change.
local function repaintAll(chromeOnly)
  for _, x in ipairs(extras) do
    if x:IsShown() and x.Restyle then x.Restyle(chromeOnly) end
  end
  if chromeOnly then
    for _, win in pairs(UI.PopoutWindows or {}) do
      if win:IsShown() then applyChrome(win, styleOf(win)) end
    end
  else
    UI.RefreshPopouts()
  end
end

-- Saves `change(style)` into window `w`'s style and redraws. chromeOnly: a
-- change of the background only (the opacity slider, many times a second):
-- the windows are repainted without rebuilding their rows.
local function setStyle(w, change, chromeOnly)
  local db = popoutsDB()
  if not db then return end
  db[w.key] = db[w.key] or {}
  local st = db[w.key].style
  if not st then
    st = {}
    for k, v in pairs(sharedStyle() or {}) do st[k] = v end
  end
  change(st)
  db[w.key].style = st
  repaintAll(chromeOnly)
end

-- Blizzard's colour picker for a style colour (presets cover most uses).
local function pickColor(w, field, current)
  local cp = ColorPickerFrame
  if not (cp and cp.SetupColorPickerAndShow) then return end
  local c = current or { 1, 1, 1 }
  local function apply()
    local r, g, b = cp:GetColorRGB()
    setStyle(w, function(st) st[field] = { r, g, b } end)
  end
  cp:SetupColorPickerAndShow({
    r = c[1], g = c[2], b = c[3], hasOpacity = false,
    swatchFunc = apply,
    cancelFunc = function() setStyle(w, function(st) st[field] = current end) end,
  })
end

local BG_PRESETS = {
  { "Dark", { 0.06, 0.06, 0.07 } }, { "Black", { 0, 0, 0 } }, { "Slate", { 0.1, 0.12, 0.16 } },
  { "Bronze", { 0.16, 0.11, 0.05 } }, { "Forest", { 0.05, 0.12, 0.07 } }, { "Wine", { 0.15, 0.05, 0.07 } },
}
local TEXT_PRESETS = {
  { "White", { 1, 1, 1 } }, { "Gold", { 1, 0.82, 0 } }, { "Light grey", { 0.8, 0.8, 0.8 } },
  { "Green", { 0.5, 0.9, 0.5 } }, { "Sky", { 0.55, 0.8, 1 } },
}

local function same(a, b)
  if a == nil or b == nil then return a == b end
  return math.abs(a[1] - b[1]) < 0.01 and math.abs(a[2] - b[2]) < 0.01 and math.abs(a[3] - b[3]) < 0.01
end

-- The appearance menu of a window (right-click its title): opacity and font
-- size are sliders right in it; the colours and the font each open their own
-- flat menu of choices (the current one ticked; Back returns). -> the menu's
-- items function, for UI.ShowMenu or another menu's submenu; `back`
-- (optional, items or a function of them) adds a Back to that menu.
function UI.PopoutStyleMenu(w, back)
  local db = popoutsDB()
  local function current() return styleOf(w) end
  local main
  local function sub(title, choices)
    return function()
      local list = { { title = title } }
      for _, it in ipairs(choices()) do list[#list + 1] = it end
      list[#list + 1] = { separator = true }
      list[#list + 1] = { text = L["Back"], submenu = main }
      return list
    end
  end
  local function choice(text, checked, change)
    return { text = text, checked = checked, keepOpen = true, onClick = function() setStyle(w, change) end }
  end
  main = function()
    local s = current()
    local state = db and db[w.key]
    return {
      { title = L["Appearance"] },
      { text = L["Show completed"], checked = state ~= nil and state.showDone == true, keepOpen = true,
        popoutOnly = true, onClick = function()
          if not state then return end
          state.showDone = not state.showDone or nil
          UI.RefreshPopouts()
        end },
      { separator = true, popoutOnly = true },
      { extra = true },
      { slider = true, text = L["Opacity"], min = math.floor(ALPHA_MIN * 100 + 0.5), max = 100, step = 1,
        value = math.floor(s.alpha * 100 + 0.5), format = "%d%%",
        onChange = function(pct) setStyle(w, function(st) st.alpha = pct / 100 end, true) end },
      { text = L["Background colour"], submenu = sub(L["Background colour"], function()
        local out = {}
        for _, p in ipairs(BG_PRESETS) do
          out[#out + 1] = choice(L[p[1]], same(current().bg, p[2]), function(st) st.bg = p[2] end)
        end
        out[#out + 1] = { text = L["Custom..."], onClick = function() pickColor(w, "bg", current().bg) end }
        return out
      end) },
      { text = L["Header colour"], submenu = sub(L["Header colour"], function()
        local out = { choice(L["Default"], current().header == nil, function(st) st.header = nil end) }
        for _, p in ipairs(TEXT_PRESETS) do
          out[#out + 1] = choice(L[p[1]], same(current().header, p[2]), function(st) st.header = p[2] end)
        end
        out[#out + 1] = { text = L["Custom..."], onClick = function() pickColor(w, "header", current().header) end }
        return out
      end) },
      { text = L["Text colour"], submenu = sub(L["Text colour"], function()
        local out = { choice(L["Default"], current().text == nil, function(st) st.text = nil end) }
        for _, p in ipairs(TEXT_PRESETS) do
          out[#out + 1] = choice(L[p[1]], same(current().text, p[2]), function(st) st.text = p[2] end)
        end
        out[#out + 1] = { text = L["Custom..."], onClick = function() pickColor(w, "text", current().text) end }
        return out
      end) },
      { slider = true, text = L["Font size"], min = SIZE_MIN, max = SIZE_MAX, step = 1,
        value = s.size or UI.PopoutDefaultSize(), format = "%d",
        onChange = function(size) setStyle(w, function(st) st.size = size end) end },
      { text = L["Font"], submenu = sub(L["Font"], function()
        local out = { choice(L["Default"], current().font == nil, function(st) st.font = nil end) }
        for _, f in ipairs(UI.PopoutFonts()) do
          out[#out + 1] = choice(f.name, current().font == f.path, function(st) st.font = f.path end)
        end
        return out
      end) },
      { separator = true },
      { text = L["Apply to all pop-outs"], onClick = function()
        -- This window's look becomes every window's (and new ones').
        local mine = db and db[w.key] and db[w.key].style or sharedStyle()
        if ns.db and ns.db.global then
          ns.db.global.popoutStyle = mine and { alpha = mine.alpha, bg = mine.bg, text = mine.text, header = mine.header,
            size = mine.size, font = mine.font } or nil
        end
        for _, state in pairs(db or {}) do
          if type(state) == "table" then state.style = nil end
        end
        repaintAll()
      end },
      { text = L["Reset appearance"], onClick = function()
        -- Back to the add-on's own look ({}: not the shared one either).
        if db and db[w.key] then db[w.key].style = sharedStyle() and {} or nil end
        repaintAll()
      end },
    }
  end
  -- Show completed is a pop-out's own (the Alts and guide windows list no
  -- lockouts to complete).
  local build = main
  main = function()
    local out = {}
    for _, it in ipairs(build()) do
      if it.extra then
        -- The window's own items (a custom list's sort, UI.PopoutMenuExtra).
        for _, x in ipairs(UI.PopoutMenuExtra and UI.PopoutMenuExtra(w) or {}) do out[#out + 1] = x end
      elseif not it.popoutOnly or (UI.PopoutWindows or {})[w.key] == w then
        out[#out + 1] = it
      end
    end
    if back then
      out[#out + 1] = { separator = true }
      out[#out + 1] = { text = L["Back"], submenu = back }
    end
    return out
  end
  return main
end

function UI.ShowPopoutStyleMenu(w, owner)
  UI.ShowMenu(owner, UI.PopoutStyleMenu(w), "cursor")
end

-- The fonts offered: the game's own, then LibSharedMedia's when another
-- add-on brings it (first 12).
function UI.PopoutFonts()
  local out = {}
  for _, f in ipairs(UI.POPOUT_FONTS) do out[#out + 1] = f end
  local LSM = LibStub and LibStub("LibSharedMedia-3.0", true)
  if LSM and LSM.List and LSM.Fetch then
    local seen = {}
    for _, f in ipairs(out) do seen[string.lower(f.path)] = true end
    local n = 0
    for _, name in ipairs(LSM:List("font") or {}) do
      local path = LSM:Fetch("font", name, true)
      if path and not seen[string.lower(path)] and n < 12 then
        out[#out + 1] = { name = name, path = path }
        seen[string.lower(path)] = true
        n = n + 1
      end
    end
  end
  return out
end
