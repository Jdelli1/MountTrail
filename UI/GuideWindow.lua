local ADDON, ns = ...

-- The guide window: the guide being followed (UI/Guides.lua), either the
-- current step only (compact: its directions, notes, where its points are
-- and what finishes it) or every step (click one to jump there). Back / Next
-- move through it; right-click the title for the mode, Edit, Export, Reset
-- and Close. Its authors show under the title (credits on hover), and a step
-- with a macro gets Copy macro / Make macro buttons. Its look is set like a
-- pop-out's (the same Appearance menu, UI.AddStyledWindow; slot "guide").
-- Drag its corner grip to any size (saved per view; right-click the grip for
-- the default); the text re-wraps to the width, and the current-step view
-- still grows when a step needs more room than it was given. Its position and mode are saved (ns.db.global.guideWindow).

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local WIDTH = 300 -- the default width
local MIN_W, MIN_H = 200, 110
local PAD = 10
local TITLE_H = 24
local BUTTONS_H = 30
local FULL_H = 340
local LINE_GAP = 4
local STEP_ROW = 20
local MACRO_ROW = 24

local w

local function db()
  local global = ns.db and ns.db.global
  if not global then return {} end
  if type(global.guideWindow) ~= "table" then global.guideWindow = {} end
  return global.guideWindow
end

function UI.GuideWindowCompact()
  return db().full ~= true
end

local function text(parent, font, r, g, b)
  local fs = parent:CreateFontString(nil, "OVERLAY", UI.Font(font))
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(true)
  if r then fs:SetTextColor(r, g, b) end
  return fs
end

-- Links in guide text (Guide.Markup): the game's tooltip on hover,
-- Shift-click puts the link in chat.
local function enableLinks(frame)
  if not frame.SetHyperlinksEnabled then return end
  frame:SetHyperlinksEnabled(true)
  frame:SetScript("OnHyperlinkEnter", function(self, link)
    local point = tonumber(string.match(link or "", "^addon:MountTrail:goto:(%d+)"))
    if point then
      UI.GuidePointTooltip(self, UI.GuideStepPoint(point))
      return
    end
    local mountID = tonumber(string.match(link or "", "^addon:MountTrail:mount:(%d+)"))
    if mountID and UI.ShowMountTooltip then
      UI.ShowMountTooltip(self, mountID)
      return
    end
    local tip = GameTooltip
    if not tip then return end
    tip:SetOwner(self, "ANCHOR_CURSOR")
    if pcall(tip.SetHyperlink, tip, link) then tip:Show() else tip:Hide() end
  end)
  frame:SetScript("OnHyperlinkLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  frame:SetScript("OnHyperlinkClick", function(_, link, text)
    local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false
    local point = tonumber(string.match(link or "", "^addon:MountTrail:goto:(%d+)"))
    if point then
      UI.GuidePointClick(UI.GuideStepPoint(point), shift)
      return
    end
    if not (shift and ns.Game.InsertChatLink) then return end
    -- A mount: its real link for chat (our own link means nothing there).
    local mountID = tonumber(string.match(link or "", "^addon:MountTrail:mount:(%d+)"))
    local m = mountID and ns.Data and ns.Data.Mounts and ns.Data.Mounts[mountID]
    if m then
      text = (m.item and ns.Game.ItemLink(m.item)) or (m.name and ("[" .. m.name .. "]"))
    end
    if text then ns.Game.InsertChatLink(text) end
  end)
end

local function height(fs)
  local h = fs.GetStringHeight and fs:GetStringHeight() or 12
  return math.max(tonumber(h) or 12, 12)
end

-- "Vale of Eternal Blossoms 35.6, 26.0" per point (two at most, then "+ n more").
-- The step's points as links, no coordinates: "Go to: [Alani (north)]
-- [Alani (south)]". Click one for its waypoint, Shift-click for the map;
-- hovering shows the zone and coordinates (UI.GuidePointTooltip).
local function pointName(p)
  return p.label or (ns.Game.MapName and ns.Game.MapName(p.m)) or tostring(p.m)
end

function UI.GuidePlaceText(step)
  local links = {}
  for i, p in ipairs(step and step.gotos or {}) do
    links[#links + 1] = string.format("|cff71d5ff|Haddon:MountTrail:goto:%d|h[%s]|h|r", i,
      (string.gsub(pointName(p), "[|%[%]]", "")))
  end
  if #links == 0 then return "" end
  return L["Go to: "] .. table.concat(links, " ")
end

-- The active step's point `i`, or nil.
function UI.GuideStepPoint(i)
  local entry, n = UI.ActiveGuide()
  local step = entry and entry.guide.steps[n]
  return step and step.gotos[i] or nil
end

-- A point link's tooltip: its name, zone and coordinates, what clicks do.
function UI.GuidePointTooltip(owner, p)
  local tip = GameTooltip
  if not (tip and p) then return end
  tip:SetOwner(owner, "ANCHOR_CURSOR")
  tip:SetText(pointName(p), 1, 1, 1)
  local where = ns.Game.MapName and ns.Game.MapName(p.m)
  tip:AddLine(string.format("%s %.1f, %.1f", where or tostring(p.m), p.x, p.y), 0.7, 0.7, 0.7)
  tip:AddLine(L["Click: set the waypoint. Shift-click: open the map."], 0.45, 0.8, 1)
  tip:Show()
end

-- A point link's click: its waypoint (TomTom), or the map with Shift.
function UI.GuidePointClick(p, shift)
  local map = ns.Map
  if not (p and map) then return end
  if shift and map.OpenZone then
    map.OpenZone(p.m)
  elseif map.SetWaypointAt then
    map.SetWaypointAt(p.m, p.x, p.y, pointName(p))
  end
end

local function showMenu(owner)
  if not UI.ActiveGuide() then return end
  local items
  items = function()
    local entry = UI.ActiveGuide()
    if not entry then return { { title = L["Guide"] } } end
    local compact = UI.GuideWindowCompact()
    local list = { { title = entry.title } }
    -- Change appearance: the pop-outs' whole appearance menu, Back returns here.
    if UI.PopoutStyleMenu then
      list[#list + 1] = { text = L["Change appearance"], submenu = UI.PopoutStyleMenu(w, items) }
    end
    for _, it in ipairs(UI.GuideMenuRest(entry, compact)) do list[#list + 1] = it end
    return list
  end
  UI.ShowMenu(owner, items, "cursor")
end

-- The guide window menu's other items.
function UI.GuideMenuRest(entry, compact)
  return {
    { text = compact and L["Show every step"] or L["Current step only"], onClick = function()
      db().full = compact or nil
      UI.RefreshGuideWindow()
    end },
    { separator = true },
    { text = entry.builtIn and L["Edit a copy..."] or L["Edit..."], onClick = function() UI.EditGuide(entry.id) end },
    { text = L["Export..."], onClick = function() UI.ExportGuide(entry.id) end },
    { text = L["Back to step 1"], onClick = function() UI.ResetGuide(entry.id) end },
    { separator = true },
    { text = L["Close guide"], onClick = function() UI.StopGuide() end },
  }
end

local function build()
  w = CreateFrame("Frame", "MountTrailGuide", UIParent)
  w.key = "guide" -- its style's slot in ns.db.global.popouts (UI.ShowPopoutStyleMenu)
  w:SetSize(db().width or WIDTH, 160)
  UI.SetResizeLimits(w, MIN_W, MIN_H)
  w:SetFrameStrata("MEDIUM")
  w:SetClampedToScreen(true)
  w:SetMovable(true)
  w:EnableMouse(true)
  local saved = db()
  if saved.x and saved.y then
    w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", saved.x, saved.y)
  else
    w:SetPoint("RIGHT", UIParent, "RIGHT", -60, 80)
  end
  local fill = w:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(w)
  fill:SetColorTexture(0.03, 0.03, 0.04, 0.85)
  w.Fill = fill
  UI.FlatBorder(w, 1, 1, 1, 0.12)

  -- Title strip: drag to move, right-click for the menu.
  local strip = CreateFrame("Button", nil, w)
  strip:SetPoint("TOPLEFT", w, "TOPLEFT", 0, 0)
  strip:SetPoint("TOPRIGHT", w, "TOPRIGHT", -24, 0)
  strip:SetHeight(TITLE_H)
  strip:RegisterForDrag("LeftButton")
  if strip.RegisterForClicks then strip:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  strip:SetScript("OnDragStart", function() w:StartMoving() end)
  strip:SetScript("OnDragStop", function()
    w:StopMovingOrSizing()
    if w.GetLeft and w:GetLeft() then
      local s = db()
      s.x, s.y = w:GetLeft(), w:GetTop()
    end
  end)
  strip:SetScript("OnClick", function(self, button) if button == "RightButton" then showMenu(self) end end)
  strip:SetScript("OnEnter", function(self)
    local entry = UI.ActiveGuide()
    UI.ShowHint(self, entry and entry.title or L["Guide"], UI.GuideCreditsText(entry and entry.guide, true))
  end)
  strip:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  local band = strip:CreateTexture(nil, "BACKGROUND")
  band:SetAllPoints(strip)
  band:SetColorTexture(1, 1, 1, 0.05)
  w.Strip = strip

  local title = strip:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
  title:SetPoint("LEFT", strip, "LEFT", PAD, 0)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)
  w.Title = title
  -- The authors, small and grey, on the title's line right after it.
  local byline = strip:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  byline:SetPoint("LEFT", title, "RIGHT", 6, 0)
  byline:SetPoint("RIGHT", strip, "RIGHT", -60, 0)
  byline:SetJustifyH("LEFT")
  byline:SetWordWrap(false)
  w.Byline = byline
  local count = strip:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  count:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
  w.Count = count

  local close = UI.FlatButton(w, "x", "plain", 18)
  close:SetWidth(18)
  close:SetPoint("TOPRIGHT", w, "TOPRIGHT", -3, -3)
  close:SetScript("OnClick", function() UI.StopGuide() end)
  close:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Close guide"], L["Its waypoints come off TomTom; the step is kept."]) end)
  close:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  w.Close = close

  -- Compact body: the current step.
  local body = CreateFrame("Frame", nil, w)
  body:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -(TITLE_H + 6))
  body:SetPoint("TOPRIGHT", w, "TOPRIGHT", -PAD, -(TITLE_H + 6))
  body:SetHeight(1)
  w.Body = body
  enableLinks(body)
  -- A step's macro: copy it, or have it made and put on the cursor.
  local copyMacro = UI.FlatButton(body, L["Copy macro"], "plain", 20)
  copyMacro:SetWidth(110)
  copyMacro:SetScript("OnClick", function()
    local entry, n = UI.ActiveGuide()
    local step = entry and entry.guide.steps[n]
    if step and step.macro then
      UI.ShowGuideCopy(L["Macro"], L["Ctrl+C to copy, then /macro, New, and paste it in."], step.macro)
    end
  end)
  w.CopyMacro = copyMacro
  local makeMacro = UI.FlatButton(body, L["Make macro"], "gold", 20)
  makeMacro:SetWidth(110)
  makeMacro:SetPoint("LEFT", copyMacro, "RIGHT", 6, 0)
  makeMacro:SetScript("OnClick", function()
    local entry, n = UI.ActiveGuide()
    local step = entry and entry.guide.steps[n]
    if step and step.macro then UI.MakeGuideMacro(step.macro) end
  end)
  makeMacro:SetScript("OnEnter", function(self)
    UI.ShowHint(self, L["Make macro"], string.format(L["Writes it into your account macro \"%s\" and puts it on your cursor."], UI.GUIDE_MACRO))
  end)
  makeMacro:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  w.MakeMacro = makeMacro
  w.StepText = text(body, "GameFontHighlight")
  w.Notes = text(body, "GameFontDisableSmall", 0.75, 0.75, 0.75)
  w.Place = text(body, "GameFontHighlightSmall", 0.45, 0.8, 1)
  w.Done = text(body, "GameFontDisableSmall", 0.55, 0.85, 0.55)

  -- Full body: every step, scrolling.
  local scroll = CreateFrame("ScrollFrame", nil, w)
  scroll:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -(TITLE_H + 6))
  scroll:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -PAD, BUTTONS_H + 4)
  if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
  local list = CreateFrame("Frame", nil, scroll)
  list:SetSize(WIDTH - 2 * PAD, 1) -- re-sized with the window (paintFull)
  scroll:SetScrollChild(list)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, (w.listHeight or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * 40)))
  end)
  w.Scroll, w.List, w.Rows = scroll, list, {}

  local back = UI.FlatButton(w, L["Back"], "plain", 22)
  back:SetWidth(80)
  back:SetPoint("BOTTOMLEFT", w, "BOTTOMLEFT", PAD, 6)
  back:SetScript("OnClick", function() UI.GuideGo(-1) end)
  w.Back = back
  local nextButton = UI.FlatButton(w, L["Next"], "gold", 22)
  nextButton:SetWidth(80)
  nextButton:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -(PAD + 12), 6) -- clear of the grip
  -- On the last step it reads Finish and closes the guide.
  nextButton:SetScript("OnClick", function(self)
    if self.finish then UI.FinishGuide() else UI.GuideGo(1) end
  end)
  w.Next = nextButton
  -- Any size: saved per view (the step view's height is a minimum: it still
  -- grows to fit a long step); right-click the grip for the default.
  w.Grip = UI.ResizeGrip(w, function(width, height)
    local s = db()
    s.width = math.floor(width + 0.5)
    if UI.GuideWindowCompact() then s.compactH = math.floor(height + 0.5) else s.fullH = math.floor(height + 0.5) end
    UI.RefreshGuideWindow()
  end, function()
    local s = db()
    s.width, s.compactH, s.fullH = nil, nil, nil
    w:SetWidth(WIDTH)
    UI.RefreshGuideWindow()
  end)
  -- While dragging the grip the text re-wraps live.
  w:SetScript("OnSizeChanged", function()
    if w.sizing then UI.RefreshGuideWindow() end
  end)

  -- The pop-outs' Appearance menu repaints it.
  w.Restyle = function(chromeOnly)
    if chromeOnly then
      local style = UI.PopoutStyleOf(w)
      w.Fill:SetColorTexture(style.bg[1], style.bg[2], style.bg[3], style.alpha)
    else
      UI.RefreshGuideWindow()
    end
  end
  w.CloseWindow = function() UI.StopGuide() end
  if UI.AddStyledWindow then UI.AddStyledWindow(w) end
  w:Hide()
  return w
end

-- The window's style (UI/Popouts.lua), or nil without the pop-outs loaded.
local function style()
  return UI.PopoutStyleOf and UI.PopoutStyleOf(w) or nil
end

-- A font string in the window's style: its font and size, the style's text
-- colour unless `color` keeps the line's own.
local function styled(fs, fontObject, color, sizeDelta)
  local st = style()
  if st and UI.PopoutStyleText then
    UI.PopoutStyleText(fs, st, UI.Font(fontObject), sizeDelta or 0, color)
  elseif color then
    fs:SetTextColor(color[1], color[2], color[3])
  end
end

-- The text width inside the window's padding.
local function innerWidth()
  return math.max(MIN_W, (w and w:GetWidth()) or WIDTH) - 2 * PAD
end

local function stepRow(i)
  local r = w.Rows[i]
  if r then return r end
  r = CreateFrame("Button", nil, w.List)
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(r)
  hl:SetColorTexture(1, 1, 1, 0.06)
  local bar = r:CreateTexture(nil, "BACKGROUND")
  bar:SetAllPoints(r)
  bar:SetColorTexture(1, 0.82, 0, 0.12)
  r.Current = bar
  r.Text = text(r, "GameFontHighlightSmall")
  r.Text:SetPoint("TOPLEFT", r, "TOPLEFT", 4, -3)
  r.Text:SetPoint("TOPRIGHT", r, "TOPRIGHT", -4, -3)
  enableLinks(r)
  r:SetScript("OnClick", function(self) UI.GuideJump(self.step, self.step < (self.current or 1)) end)
  w.Rows[i] = r
  return r
end

local function paintCompact(entry, n, step)
  w.Body:Show()
  w.Scroll:Hide()
  for _, r in ipairs(w.Rows) do r:Hide() end
  local y = 0
  local function place(fs, value)
    fs:ClearAllPoints()
    if not value or value == "" then
      fs:Hide()
      return
    end
    fs:SetPoint("TOPLEFT", w.Body, "TOPLEFT", 0, -y)
    fs:SetWidth(innerWidth())
    fs:SetText(value)
    fs:Show()
    y = y + height(fs) + LINE_GAP
  end
  styled(w.StepText, "GameFontHighlight", nil, 1)
  styled(w.Notes, "GameFontDisableSmall", { 0.75, 0.75, 0.75 }, -1)
  styled(w.Place, "GameFontHighlightSmall", { 0.45, 0.8, 1 }, -1)
  styled(w.Done, "GameFontDisableSmall", { 0.55, 0.85, 0.55 }, -1)
  place(w.StepText, UI.GuideText(step.text))
  place(w.Notes, UI.GuideText(table.concat(step.notes, "\n")))
  place(w.Place, UI.GuidePlaceText(step))
  local done = ns.Guide.DoneText(step)
  place(w.Done, #done > 0 and UI.GuideText(L["Done when: "] .. table.concat(done, ", ")) or L["Press Next when done."])
  w.CopyMacro:SetShown(step.macro ~= nil)
  w.MakeMacro:SetShown(step.macro ~= nil)
  if step.macro then
    w.CopyMacro:ClearAllPoints()
    w.CopyMacro:SetPoint("TOPLEFT", w.Body, "TOPLEFT", 0, -y)
    y = y + MACRO_ROW
  end
  if not w.sizing then w:SetHeight(math.max(w.top + y + BUTTONS_H + 6, db().compactH or 0)) end
end

local function paintFull(entry, n)
  w.Body:Hide()
  w.Scroll:Show()
  local y = 0
  local width = innerWidth()
  w.List:SetWidth(width)
  for i, step in ipairs(entry.guide.steps) do
    local r = stepRow(i)
    r.step, r.current = i, n
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", w.List, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    r.Text:SetWidth(width - 8)
    r.Text:SetText(string.format("%d. %s", i, UI.GuideText(step.text)))
    if i < n then
      styled(r.Text, "GameFontHighlightSmall", { 0.5, 0.5, 0.5 })
    elseif i == n then
      styled(r.Text, "GameFontHighlightSmall", { 1, 0.82, 0 })
    else
      styled(r.Text, "GameFontHighlightSmall")
    end
    r.Current:SetShown(i == n)
    local h = math.max(STEP_ROW, height(r.Text) + 6)
    r:SetHeight(h)
    r:Show()
    y = y + h
  end
  for i = #entry.guide.steps + 1, #w.Rows do w.Rows[i]:Hide() end
  w.List:SetHeight(math.max(y, 1))
  w.listHeight = y
  if not w.sizing then w:SetHeight(db().fullH or FULL_H) end
end

-- Repaints the window for the guide being followed (hides it without one).
function UI.RefreshGuideWindow()
  if not w then return end
  local entry, n = UI.ActiveGuide()
  if not entry then
    w:Hide()
    return
  end
  local steps = entry.guide.steps
  local step = steps[n]
  local st = style()
  if st then
    w.Fill:SetColorTexture(st.bg[1], st.bg[2], st.bg[3], st.alpha)
    if UI.PopoutStyleHeader then UI.PopoutStyleHeader(w.Title, st, UI.Font("GameFontNormal"), 1) end
    styled(w.Byline, "GameFontDisableSmall", { 0.62, 0.62, 0.62 }, -2)
  end
  -- Title, then the authors on the same line: the title keeps its full
  -- width while it fits, giving way (cut short) to at least part of the
  -- authors when the window is narrow.
  local byline = ns.Guide.Byline(entry.guide)
  w.Title:SetWidth(0)
  w.Title:SetText(entry.title)
  w.Byline:SetText(byline or "")
  w.Byline:SetShown(byline ~= nil)
  local room = innerWidth() - 60
  local titleW = tonumber(w.Title.GetStringWidth and w.Title:GetStringWidth()) or room
  local bylineW = byline and (tonumber(w.Byline.GetStringWidth and w.Byline:GetStringWidth()) or 0) or 0
  local keep = byline and math.min(bylineW, math.floor(room * 0.4)) + 6 or 0
  w.Title:SetWidth(math.max(40, math.min(titleW, room - keep)))
  w.top = TITLE_H + 6
  w.Body:ClearAllPoints()
  w.Body:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -w.top)
  w.Body:SetPoint("TOPRIGHT", w, "TOPRIGHT", -PAD, -w.top)
  w.Scroll:SetPoint("TOPLEFT", w, "TOPLEFT", PAD, -w.top)
  w.Count:SetText(string.format(L["%d / %d"], n, #steps))
  w.Back:SetEnabled(n > 1)
  if w.Back.SetAlpha then w.Back:SetAlpha(n > 1 and 1 or 0.4) end
  w.Next.finish = n >= #steps
  UI.FlatButtonSetText(w.Next, w.Next.finish and L["Finish"] or L["Next"])
  w.Next:SetWidth(80)
  if UI.GuideWindowCompact() then paintCompact(entry, n, step) else paintFull(entry, n) end
end

function UI.ShowGuideWindow(show)
  if show then
    if not w then build() end
    w:Show()
    UI.RefreshGuideWindow()
  elseif w then
    w:Hide()
  end
end

-- A guide's menu (its entry under Guides): follow, edit, export, reset, delete.
function UI.ShowGuideMenu(id, owner)
  local entry = UI.GuideById(id)
  if not entry then return end
  local active = UI.ActiveGuide()
  local following = active and active.id == id
  local items = { { title = entry.title } }
  local byline = ns.Guide.Byline(entry.guide)
  if byline then items[#items + 1] = { text = byline, disabled = true } end
  for _, c in ipairs(entry.guide.credits or {}) do items[#items + 1] = { text = c, disabled = true } end
  if #items > 1 then items[#items + 1] = { separator = true } end
  for _, it in ipairs({
    { text = following and L["Close guide"] or L["Follow"], onClick = function()
      if following then UI.StopGuide() else UI.StartGuide(id) end
    end },
    { text = entry.builtIn and L["Edit a copy..."] or L["Edit..."], onClick = function() UI.EditGuide(id) end },
    { text = L["Export..."], onClick = function() UI.ExportGuide(id) end },
    { text = L["Back to step 1"], onClick = function() UI.ResetGuide(id) end },
  }) do items[#items + 1] = it end
  if not entry.builtIn then
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = L["Delete..."], onClick = function()
      UI.AskText(string.format(L["Delete %s?"], entry.title), "", function() UI.DeleteGuide(id) end, {
        match = entry.title, okLabel = L["Delete"], danger = true,
        hint = string.format(L["Type %s to confirm. This can't be undone."], entry.title),
      })
    end }
  end
  UI.ShowMenu(owner, items, "cursor")
end

-- "by A, B" and the credit lines (one per line), or "" without either.
-- withHelp: the window's own hint line after them.
function UI.GuideCreditsText(guide, withHelp)
  local lines = {}
  local byline = guide and ns.Guide.Byline(guide)
  if byline then lines[#lines + 1] = byline end
  for _, c in ipairs(guide and guide.credits or {}) do lines[#lines + 1] = "|cff9d9d9d" .. c .. "|r" end
  if withHelp then lines[#lines + 1] = L["Drag to move. Right-click for options."] end
  return table.concat(lines, "\n")
end

UI.GuideWindow = function() return w end

-- Names arriving from the server (an item or quest a link asked for):
-- repaint once they settle.
local pendingRepaint = false
local loads = CreateFrame("Frame")
loads:RegisterEvent("GET_ITEM_INFO_RECEIVED")
loads:RegisterEvent("QUEST_DATA_LOAD_RESULT")
loads:SetScript("OnEvent", function()
  if not (w and w:IsShown()) or pendingRepaint then return end
  if type(C_Timer) == "table" and type(C_Timer.After) == "function" then
    pendingRepaint = true
    C_Timer.After(0.2, function()
      pendingRepaint = false
      UI.RefreshGuideWindow()
    end)
  else
    UI.RefreshGuideWindow()
  end
end)
