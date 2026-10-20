local ADDON, ns = ...

-- Alt lockout matrix (Logic/Alts.lua): a movable, closable window with one
-- column per character the add-on has seen (char.seen, ns.RecordSeen) and
-- one row per daily / weekly mount lockout any of them can spend, grouped
-- under Weekly / Daily headers then expansion sub-headers (collapsible,
-- saved in ns.db.global.collapsed under "alts|..."). Each cell: a green check
-- (saved), a dim square (still open: farmable), a grey dash (not for that
-- character's faction) or "?" (no lockout data stored yet: log in once);
-- hovering a cell says which. A character's stored lockouts count as open
-- again once the reset after its last login has passed.
-- Column headers are the characters' names in their class colour (the
-- current one first); right-click one to hide it (ns.db.global.altsHidden),
-- "Show all" brings them back. A row's name click sets the waypoint as the
-- Checklist does (UI.GoTo), hovering it shows the mount tooltip. The window
-- grows with the columns (MIN_W..MAX_W); columns past what fits are left
-- off and the subtitle says how many. Position in ns.db.global.altsWindow.
-- Opened by UI.ToggleAltsWindow: /mtrail alts and the Checklist header's
-- "Alts" button. Redrawn on ns.Refresh only while shown.
-- It is customised like a pop-out (UI/Popouts.lua, UI.AddStyledWindow):
-- right-click the title for the appearance menu (opacity, background,
-- header and text colour, font size, font; "Apply to all pop-outs" and
-- "Reset appearance"; saved under ns.db.global.popouts.alts), drag the
-- corner grip to size it (right-click the grip: fit the columns again;
-- the columns that fit follow the width), and it snaps to a pop-out or the
-- main window when dropped near one. Ctrl-click its x closes every pop-out
-- too.
-- The pure helpers (AltsSections, AltsData, AltsWidth, AltsCellHint,
-- AltsColumnColor) and the widget code are run by tests/ui_build_spec.lua.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local NAME_W = 200 -- the row-name column
local CELL_W = 58 -- one character column
local PAD = 36 -- window insets and the scroll bar
local MIN_W, MAX_W = 380, 1100
local HEIGHT = 440
local MIN_H = 160
local TITLE_HEIGHT = 26
local ROW_HEIGHT = 20
local HEADER_HEIGHT = 22
local SUB_HEADER_HEIGHT = 18
local ICON_SIZE = 16
local READY = "Interface\\RaidFrame\\ReadyCheck-Ready"
local GREY = "|cff9d9d9d"

local function globalDB()
  return ns.db and ns.db.global or nil
end

local function hiddenDB()
  local global = globalDB()
  if not global then return nil end
  if type(global.altsHidden) ~= "table" then global.altsHidden = {} end
  return global.altsHidden
end

local function windowDB()
  local global = globalDB()
  if not global then return nil end
  if type(global.altsWindow) ~= "table" then global.altsWindow = {} end
  return global.altsWindow
end

local function collapsedDB()
  local global = globalDB()
  if not global then return nil end
  if type(global.collapsed) ~= "table" then global.collapsed = {} end
  return global.collapsed
end

-- Pure helpers -------------------------------------------------------------------

-- AceDB's raw character sections ({ ["Name - Realm"] = section }) and this
-- character's key. Without them (a stub database) just this character.
function UI.AltsSections()
  local db = ns.db
  if not db then return {}, nil end
  local current = type(db.keys) == "table" and db.keys.char or nil
  local sv = db.sv
  if type(sv) == "table" and type(sv.char) == "table" then
    if not current then
      for key, section in pairs(sv.char) do
        if rawequal(section, db.char) then current = key end
      end
    end
    return sv.char, current
  end
  current = current or "current"
  return { [current] = db.char }, current
end

-- The matrix at `now` -> rows (Alts.Build), characters (Alts.Characters),
-- hidden count. Mounts are account-wide: one owned / exists lookup for every
-- column, the faction gate per character (Journal.Gate).
function UI.AltsData(now)
  local Game = ns.Game
  now = now or Game.Now()
  local sections, current = UI.AltsSections()
  local chars, hidden = ns.Alts.Characters(sections, now, current, hiddenDB())
  local memo = UI.Memo
  local isOwned, exists = memo(Game.IsOwned), memo(Game.Exists)
  local char = ns.db and ns.db.char
  local rows = ns.Alts.Build({
    characters = chars,
    now = now,
    checklist = UI.ChecklistContext(now),
    gate = function(id, m, faction) return ns.Journal.Gate(id, m, isOwned, exists, faction) end,
    filters = char and type(char.checklistFilters) == "table" and char.checklistFilters or nil,
  })
  return rows, chars, hidden
end

-- How many character columns a window `width` wide holds (at least one).
function UI.AltsFit(width)
  return math.max(1, math.floor(((width or MIN_W) - NAME_W - PAD) / CELL_W))
end

-- Window width for `count` columns and how many of them fit (at least one).
-- maxW defaults to MAX_W (less on a narrow screen).
function UI.AltsWidth(count, maxW)
  maxW = math.max(MIN_W, maxW or MAX_W)
  local fit = UI.AltsFit(maxW)
  local shown = math.min(count, fit)
  local width = math.max(MIN_W, math.min(maxW, NAME_W + PAD + shown * CELL_W))
  return width, shown
end

local CELL_TEXT = {
  done = "%s: saved",
  open = "%s: not saved",
  na = "%s: not available",
  unknown = "%s: no data yet (log in once)",
}

-- A cell's hint title: "<char>: saved" ... by Alts cell state.
function UI.AltsCellHint(charName, state)
  return string.format(L[CELL_TEXT[state] or CELL_TEXT.unknown], charName or "?")
end

-- r, g, b of a class file in RAID_CLASS_COLORS, else white.
function UI.AltsColumnColor(class)
  local colors = type(RAID_CLASS_COLORS) == "table" and RAID_CLASS_COLORS or nil
  local c = colors and class and colors[class]
  if type(c) == "table" and c.r then return c.r, c.g, c.b end
  return 1, 1, 1
end

-- Widgets ----------------------------------------------------------------------------

local w -- the window, built on first open

local function screenMax()
  local sw = UIParent and UIParent.GetWidth and UIParent:GetWidth() or nil
  if type(sw) == "number" and sw > 0 then return math.min(MAX_W, sw - 40) end
  return MAX_W
end

local function savePosition()
  local db = windowDB()
  if not (db and w) then return end
  local point, _, relPoint, x, y = w:GetPoint(1)
  db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end

-- Cell `i` of a row frame (or the column header strip), made on demand.
local function cellFrame(r, i)
  r.Cells = r.Cells or {}
  local c = r.Cells[i]
  if c then return c end
  c = CreateFrame("Button", nil, r)
  c:SetWidth(CELL_W)
  c:SetPoint("TOPLEFT", r, "TOPLEFT", NAME_W + (i - 1) * CELL_W, 0)
  c:SetPoint("BOTTOMLEFT", r, "BOTTOMLEFT", NAME_W + (i - 1) * CELL_W, 0)
  local hl = c:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(c)
  hl:SetColorTexture(1, 1, 1, 0.08)
  local check = c:CreateTexture(nil, "ARTWORK")
  check:SetSize(14, 14)
  check:SetPoint("CENTER", c, "CENTER", 0, 0)
  check:SetTexture(READY)
  c.Check = check
  -- Still open: a dim square with a faint edge.
  local box = CreateFrame("Frame", nil, c)
  box:SetSize(10, 10)
  box:SetPoint("CENTER", c, "CENTER", 0, 0)
  local fill = box:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(box)
  fill:SetColorTexture(1, 1, 1, 0.06)
  UI.FlatBorder(box, 1, 1, 1, 0.35)
  c.Box = box
  local text = c:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  text:SetPoint("CENTER", c, "CENTER", 0, 0)
  c.Text = text
  c:SetScript("OnEnter", function(self)
    if self.char then
      UI.ShowHint(self, UI.AltsCellHint(self.char.name, self.state), self.rowName)
    end
  end)
  c:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  r.Cells[i] = c
  return c
end

local function paintCell(c, state, style)
  c.state = state
  if style then UI.PopoutStyleText(c.Text, style, "GameFontDisableSmall", 0, { 0.6, 0.6, 0.6 }) end
  c.Check:SetShown(state == "done")
  c.Box:SetShown(state == "open")
  if state == "na" then
    c.Text:SetText("-")
  elseif state == "unknown" then
    c.Text:SetText("?")
  else
    c.Text:SetText("")
  end
end

local function toggleHeader(key)
  local store = collapsedDB()
  if not store then return end
  UI.ToggleCollapsed(store, key)
  ns.Refresh()
end

local function onRowClick(self)
  local row = self:GetParent().data
  local e = row and row.entry
  if not e then return end
  if UI.GoTo then
    UI.GoTo(e.id, e.boss)
  elseif ns.Map and ns.Map.SetWaypoint then
    local good, err = pcall(ns.Map.SetWaypoint, e.id, nil, e.boss)
    if not good and ns.Game and ns.Game.ReportError then ns.Game.ReportError(err) end
  end
end

local function onRowEnter(self)
  local row = self:GetParent().data
  local e = row and row.entry
  if not e then return end
  if e.grouped and UI.ShowChecklistGroupTooltip then
    UI.ShowChecklistGroupTooltip(self, e)
  elseif UI.ShowMountTooltip then
    UI.ShowMountTooltip(self, e.id, e.boss)
  end
end

local function onRowLeave()
  if UI.HideMountTooltip then UI.HideMountTooltip() end
end

-- A ScrollBox element: a header (reset or expansion; click collapses) or a
-- lockout row (icon and name, then one cell per shown character).
local function initElement(f, data)
  f.data = data.row
  if not f.Bg then
    local bg = f:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints(f)
    f.Bg = bg
    local name = CreateFrame("Button", nil, f)
    local hl = name:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints(name)
    hl:SetColorTexture(1, 1, 1, 0.06)
    local icon = name:CreateTexture(nil, "ARTWORK")
    icon:SetSize(ICON_SIZE, ICON_SIZE)
    name.Icon = icon
    local text = name:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    text:SetJustifyH("LEFT")
    text:SetWordWrap(false)
    name.Text = text
    f.Name = name
  end
  local name = f.Name
  -- Recycled frames: a header's name spans the row, a lockout's the name column.
  name:ClearAllPoints()
  name:SetPoint("TOPLEFT", f, "TOPLEFT", 0, 0)
  name:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 0, 0)
  if data.header then
    name:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 0, 0)
  else
    name:SetWidth(NAME_W)
  end
  name.Text:ClearAllPoints()
  name.Icon:ClearAllPoints()
  if data.header then
    local sub = (data.depth or 1) >= 2
    f.Bg:SetColorTexture(1, 0.82, 0, sub and 0.04 or 0.1)
    name.Icon:Hide()
    name.Text:SetPoint("LEFT", name, "LEFT", sub and 18 or 6, 0)
    name.Text:SetPoint("RIGHT", name, "RIGHT", -6, 0)
    local style = w and w.style
    if style then
      UI.PopoutStyleText(name.Text, style, sub and "GameFontNormalSmall" or "GameFontNormal", sub and 0 or 1, style.header)
    else
      name.Text:SetFontObject(sub and "GameFontNormalSmall" or "GameFontNormal")
    end
    name.Text:SetText((data.collapsed and "+ " or "- ") .. (data.text or "")
      .. "  " .. GREY .. string.format(L["%d open"], data.open or 0) .. "|r")
    name:SetScript("OnClick", function() toggleHeader(data.key) end)
    name:SetScript("OnEnter", nil)
    name:SetScript("OnLeave", nil)
    for _, c in ipairs(f.Cells or {}) do c:Hide() end
    return
  end
  local row = data.row
  f.Bg:SetColorTexture(1, 1, 1, data.alt and 0.03 or 0)
  local _, iconFile = ns.Game.MountInfo(row.entry.id)
  name.Icon:SetPoint("LEFT", name, "LEFT", 22, 0)
  if iconFile then
    name.Icon:SetTexture(iconFile)
    name.Icon:Show()
  else
    name.Icon:Hide()
  end
  name.Text:SetPoint("LEFT", name.Icon, "RIGHT", 4, 0)
  name.Text:SetPoint("RIGHT", name, "RIGHT", -4, 0)
  if w and w.style then
    UI.PopoutStyleText(name.Text, w.style, "GameFontHighlightSmall")
  else
    name.Text:SetFontObject("GameFontHighlightSmall")
  end
  name.Text:SetText(row.name or "")
  name:SetScript("OnClick", onRowClick)
  name:SetScript("OnEnter", onRowEnter)
  name:SetScript("OnLeave", onRowLeave)
  local chars = w and w.shownChars or {}
  for i, char in ipairs(chars) do
    local c = cellFrame(f, i)
    c.char, c.rowName = char, row.name
    paintCell(c, row.cells[char.key], w and w.style)
    c:Show()
  end
  for i = #chars + 1, #(f.Cells or {}) do f.Cells[i]:Hide() end
end

local function hideMenu(char)
  return {
    { title = char.name },
    { text = string.format(L["Hide %s"], char.name), onClick = function()
      local hidden = hiddenDB()
      if hidden then hidden[char.key] = true end
      ns.Refresh()
    end },
  }
end

-- Column header `i`: the character's name in its class colour.
local function columnFrame(i)
  local c = w.Columns[i]
  if c then return c end
  c = CreateFrame("Button", nil, w.ColumnStrip)
  c:SetWidth(CELL_W)
  c:SetPoint("TOPLEFT", w.ColumnStrip, "TOPLEFT", NAME_W + (i - 1) * CELL_W, 0)
  c:SetPoint("BOTTOMLEFT", w.ColumnStrip, "BOTTOMLEFT", NAME_W + (i - 1) * CELL_W, 0)
  if c.RegisterForClicks then c:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  local hl = c:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(c)
  hl:SetColorTexture(1, 1, 1, 0.08)
  local text = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("LEFT", c, "LEFT", 2, 0)
  text:SetPoint("RIGHT", c, "RIGHT", -2, 0)
  text:SetWordWrap(false)
  c.Text = text
  c:SetScript("OnClick", function(self, button)
    if button == "RightButton" and self.char then UI.ShowMenu(self, hideMenu(self.char), "cursor") end
  end)
  c:SetScript("OnEnter", function(self)
    local char = self.char
    if not char then return end
    local parts = {}
    if char.level then parts[#parts + 1] = string.format(L["Level %d"], char.level) end
    if char.realm then parts[#parts + 1] = char.realm end
    parts[#parts + 1] = L["Right-click: hide this character"]
    UI.ShowHint(self, char.name, table.concat(parts, "\n"))
  end)
  c:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  w.Columns[i] = c
  return c
end

local function build()
  w = CreateFrame("Frame", "MountTrailAltsWindow", UIParent)
  w.key = "alts" -- its style's slot in ns.db.global.popouts (UI.ShowPopoutStyleMenu)
  w.Columns = {}
  w.shownChars = {}
  w.rowHeight, w.headerHeight, w.subHeight = ROW_HEIGHT, HEADER_HEIGHT, SUB_HEADER_HEIGHT
  w:SetSize(MIN_W, HEIGHT)
  w:SetFrameStrata("MEDIUM")
  w:SetMovable(true)
  w:SetClampedToScreen(true)
  w:EnableMouse(true)
  w:Hide()
  if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "MountTrailAltsWindow") end
  local db = windowDB()
  if db and db.width and db.height then
    w:SetSize(math.max(MIN_W, db.width), math.max(MIN_H, db.height))
    w.userSized = true
  elseif db and db.height then
    w:SetHeight(math.max(MIN_H, db.height))
  end
  w:ClearAllPoints()
  if db and db.point then
    w:SetPoint(db.point, UIParent, db.relPoint or db.point, db.x or 0, db.y or 0)
  else
    w:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end

  local fill = w:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(w)
  fill:SetColorTexture(0.06, 0.06, 0.07, 0.92)
  w.Fill = fill
  w.Edge = UI.FlatBorder(w, 1, 1, 1, 0.12)

  -- Title strip: drag to move.
  local strip = CreateFrame("Frame", nil, w)
  strip:SetPoint("TOPLEFT", w, "TOPLEFT", 1, -1)
  strip:SetPoint("TOPRIGHT", w, "TOPRIGHT", -1, -1)
  strip:SetHeight(TITLE_HEIGHT)
  strip:EnableMouse(true)
  strip:RegisterForDrag("LeftButton")
  strip:SetScript("OnDragStart", function() w:StartMoving() end)
  strip:SetScript("OnDragStop", function()
    w:StopMovingOrSizing()
    if w.SetUserPlaced then w:SetUserPlaced(false) end
    -- Snap to a pop-out or the main window, as the pop-outs do.
    local l, t, r, b = w:GetLeft(), w:GetTop(), w:GetRight(), w:GetBottom()
    if l and t and r and b and UI.SnapRect and UI.PopoutSnapTargets then
      local sl, st = UI.SnapRect({ left = l, top = t, right = r, bottom = b }, UI.PopoutSnapTargets({ [w] = true }))
      if sl then
        w:ClearAllPoints()
        w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", sl, st)
      end
    end
    savePosition()
  end)
  strip:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" and UI.ShowPopoutStyleMenu then UI.ShowPopoutStyleMenu(w, self) end
  end)
  strip:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Drag to move"], L["Right-click: appearance"]) end)
  strip:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  local stripBg = strip:CreateTexture(nil, "BACKGROUND")
  stripBg:SetAllPoints(strip)
  stripBg:SetColorTexture(1, 1, 1, 0.05)
  local rule = w:CreateTexture(nil, "BORDER")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, 0)
  rule:SetColorTexture(1, 0.82, 0, 0.3)
  w.Strip = strip

  local close = UI.FlatButton(strip, "x", "plain", 18)
  close:SetWidth(18)
  close:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
  close:SetScript("OnClick", function()
    if type(IsControlKeyDown) == "function" and IsControlKeyDown() and UI.CloseAllPopouts then
      UI.CloseAllPopouts()
    end
    UI.ToggleAltsWindow(false)
  end)
  close:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Close"], L["Ctrl-click: close every pop-out"]) end)
  close:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  w.Close = close

  -- Show all: brings back the hidden characters (shown only when any are).
  local showAll = UI.FlatButton(strip, L["Show all"], "gold", 16)
  showAll:SetPoint("RIGHT", close, "LEFT", -4, 0)
  showAll:SetScript("OnClick", function()
    local global = globalDB()
    if global then global.altsHidden = {} end
    ns.Refresh()
  end)
  showAll:Hide()
  w.ShowAll = showAll

  local title = strip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("LEFT", strip, "LEFT", 8, 0)
  title:SetPoint("RIGHT", showAll, "LEFT", -4, 0)
  title:SetJustifyH("LEFT")
  title:SetText(L["Alt lockouts"])
  w.Title = title

  -- Under the title: the reset timers, then the column headers.
  local resets = w:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  resets:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 8, -5)
  resets:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", -8, -5)
  resets:SetJustifyH("LEFT")
  resets:SetWordWrap(false)
  w.Resets = resets

  local columns = CreateFrame("Frame", nil, w)
  columns:SetPoint("TOPLEFT", resets, "BOTTOMLEFT", -2, -6)
  columns:SetPoint("TOPRIGHT", resets, "BOTTOMRIGHT", 2, -6)
  columns:SetHeight(18)
  w.ColumnStrip = columns

  local list = CreateFrame("Frame", nil, w)
  list:SetPoint("TOPLEFT", columns, "BOTTOMLEFT", 0, -2)
  list:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -6, 6)
  local scrollBox = CreateFrame("Frame", nil, list, "WowScrollBoxList")
  scrollBox:SetPoint("TOPLEFT", list, "TOPLEFT", 0, 0)
  scrollBox:SetPoint("BOTTOMRIGHT", list, "BOTTOMRIGHT", -16, 0)
  local scrollBar = CreateFrame("EventFrame", nil, list, "MinimalScrollBar")
  scrollBar:SetPoint("TOPLEFT", scrollBox, "TOPRIGHT", 4, 0)
  scrollBar:SetPoint("BOTTOMLEFT", scrollBox, "BOTTOMRIGHT", 4, 0)
  local view = CreateScrollBoxListLinearView()
  view:SetElementExtentCalculator(function(_, data)
    if data.header then return (data.depth or 1) >= 2 and w.subHeight or w.headerHeight end
    return w.rowHeight
  end)
  view:SetElementFactory(function(factory) factory("Frame", initElement) end)
  ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)
  w.ScrollBox = scrollBox

  local empty = list:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  empty:SetPoint("CENTER", scrollBox, "CENTER", 0, 0)
  empty:Hide()
  w.Empty = empty

  -- Resize grip: any size (the columns that fit follow the width); right-click
  -- fits the columns again (the height stays).
  UI.SetResizeLimits(w, MIN_W, MIN_H)
  w.Grip = UI.ResizeGrip(w, function(gw, gh)
    w.userSized = true
    local st = windowDB()
    if st then st.width, st.height = math.floor(gw + 0.5), math.floor(gh + 0.5) end
    savePosition()
    UI.RefreshAltsWindow()
  end, function()
    w.userSized = nil
    local st = windowDB()
    if st then st.width = nil end
    UI.RefreshAltsWindow()
  end, L["Right-click: fit the columns"])

  -- The pop-outs' appearance menu repaints it (UI.AddStyledWindow).
  w.Restyle = function(chromeOnly)
    if chromeOnly then
      local style = UI.PopoutStyleOf(w)
      w.Fill:SetColorTexture(style.bg[1], style.bg[2], style.bg[3], style.alpha)
    else
      UI.RefreshAltsWindow()
    end
  end
  w.CloseWindow = function() UI.ToggleAltsWindow(false) end
  if UI.AddStyledWindow then UI.AddStyledWindow(w) end
  return w
end

-- Redraws the window (when shown): columns, width, rows.
function UI.RefreshAltsWindow()
  if not (w and w:IsShown()) then return end
  local Game = ns.Game
  local now = Game.Now()
  local rows, chars, hidden = UI.AltsData(now)
  -- The pop-out style: background, title, and row heights for its font size.
  local style = UI.PopoutStyleOf and UI.PopoutStyleOf(w) or nil
  w.style = style
  if style then
    w.Fill:SetColorTexture(style.bg[1], style.bg[2], style.bg[3], style.alpha)
    UI.PopoutStyleText(w.Title, { font = style.font, size = style.size }, "GameFontNormal", 2, style.header)
    UI.PopoutStyleText(w.Resets, style, "GameFontHighlightSmall")
    local size = style.size or 11
    w.rowHeight = math.max(ROW_HEIGHT, size + 9)
    w.subHeight = math.max(SUB_HEADER_HEIGHT, size + 7)
    w.headerHeight = math.max(HEADER_HEIGHT, size + 11)
    w.ColumnStrip:SetHeight(math.max(18, size + 7))
  end
  local width, fit
  if w.userSized then
    width = w:GetWidth() or MIN_W
    fit = UI.AltsFit(width)
  else
    width, fit = UI.AltsWidth(#chars, screenMax())
    w:SetWidth(width)
  end
  local shown = {}
  for i = 1, fit do shown[i] = chars[i] end
  w.shownChars = shown

  local line = UI.ChecklistSummary(Game.UntilDaily(), Game.UntilWeekly())
  if #chars > fit then
    line = line .. "    " .. GREY .. string.format(L["%d more characters do not fit: hide some"], #chars - fit) .. "|r"
  end
  w.Resets:SetText(line)
  w.ShowAll:SetShown(hidden > 0)

  for i, char in ipairs(shown) do
    local c = columnFrame(i)
    c.char = char
    c.Text:SetText(char.name)
    if style then UI.PopoutStyleText(c.Text, style, "GameFontHighlightSmall") end
    c.Text:SetTextColor(UI.AltsColumnColor(char.class))
    c:Show()
  end
  for i = #shown + 1, #w.Columns do w.Columns[i]:Hide() end

  local untilDaily, untilWeekly = Game.UntilDaily(), Game.UntilWeekly()
  local display = ns.Alts.Rows(rows, {
    collapsed = collapsedDB() or {},
    label = function(reset) return UI.ChecklistHeaderLabel(reset, untilDaily, untilWeekly) end,
  })
  local n = 0
  for _, data in ipairs(display) do
    if data.header then
      n = 0
    else
      n = n + 1
      data.alt = n % 2 == 0
    end
  end
  if ScrollBoxConstants then
    w.ScrollBox:SetDataProvider(CreateDataProvider(display), ScrollBoxConstants.RetainScrollPosition)
  else
    w.ScrollBox:SetDataProvider(CreateDataProvider(display))
  end
  if #chars == 0 then
    w.Empty:SetText(L["No characters yet: log in on each one once."])
  else
    w.Empty:SetText(L["Nothing left to farm on any character."])
  end
  w.Empty:SetShown(#display == 0)
end

-- Opens or closes the window (`show` forces a state) -> shown.
function UI.ToggleAltsWindow(show)
  if show == nil then show = not (w and w:IsShown()) end
  if not show then
    if w then w:Hide() end
    return false
  end
  if not w then build() end
  w:Show()
  if w.Raise then w:Raise() end
  UI.RefreshAltsWindow()
  return true
end

UI.AltsWindow = function() return w end

UI.AddRefreshHook(function() UI.RefreshAltsWindow() end)
