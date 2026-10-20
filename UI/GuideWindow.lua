local ADDON, ns = ...

-- The guide window: the guide being followed (UI/Guides.lua), either the
-- current step only (compact: its directions, notes, where its points are
-- and what finishes it) or every step (click one to jump there). Back / Next
-- move through it; right-click the title for the mode, Edit, Export, Reset
-- and Close. Its position and mode are saved (ns.db.global.guideWindow).

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local WIDTH = 300
local PAD = 10
local TITLE_H = 24
local BUTTONS_H = 30
local FULL_H = 340
local LINE_GAP = 4
local STEP_ROW = 20

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

local function height(fs)
  local h = fs.GetStringHeight and fs:GetStringHeight() or 12
  return math.max(tonumber(h) or 12, 12)
end

-- "Vale of Eternal Blossoms 35.6, 26.0" per point (two at most, then "+ n more").
function UI.GuidePlaceText(step)
  local lines = {}
  for i, p in ipairs(step and step.gotos or {}) do
    if i > 2 then
      lines[#lines + 1] = string.format(L["+ %d more"], #step.gotos - 2)
      break
    end
    local where = ns.Game.MapName and ns.Game.MapName(p.m) or tostring(p.m)
    local label = p.label and (p.label .. ": ") or ""
    lines[#lines + 1] = string.format("%s%s %.1f, %.1f", label, where or "", p.x, p.y)
  end
  return table.concat(lines, "\n")
end

local function showMenu(owner)
  local entry = UI.ActiveGuide()
  if not entry then return end
  local compact = UI.GuideWindowCompact()
  UI.ShowMenu(owner, {
    { title = entry.title },
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
  }, "cursor")
end

local function build()
  w = CreateFrame("Frame", "MountTrailGuide", UIParent)
  w:SetSize(WIDTH, 160)
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
  strip:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Guide"], L["Drag to move. Right-click for options."]) end)
  strip:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  local band = strip:CreateTexture(nil, "BACKGROUND")
  band:SetAllPoints(strip)
  band:SetColorTexture(1, 1, 1, 0.05)
  w.Strip = strip

  local title = strip:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
  title:SetPoint("LEFT", strip, "LEFT", PAD, 0)
  title:SetPoint("RIGHT", strip, "RIGHT", -60, 0)
  title:SetJustifyH("LEFT")
  title:SetWordWrap(false)
  w.Title = title
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
  list:SetSize(WIDTH - 2 * PAD, 1)
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
  nextButton:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -PAD, 6)
  -- On the last step it reads Finish and closes the guide.
  nextButton:SetScript("OnClick", function(self)
    if self.finish then UI.FinishGuide() else UI.GuideGo(1) end
  end)
  w.Next = nextButton
  w:Hide()
  return w
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
    fs:SetWidth(WIDTH - 2 * PAD)
    fs:SetText(value)
    fs:Show()
    y = y + height(fs) + LINE_GAP
  end
  place(w.StepText, step.text)
  place(w.Notes, table.concat(step.notes, "\n"))
  place(w.Place, UI.GuidePlaceText(step))
  local done = ns.Guide.DoneText(step, UI.GuideNames())
  place(w.Done, #done > 0 and (L["Done when: "] .. table.concat(done, ", ")) or L["Press Next when done."])
  w:SetHeight(TITLE_H + 6 + y + BUTTONS_H + 6)
end

local function paintFull(entry, n)
  w.Body:Hide()
  w.Scroll:Show()
  local y = 0
  local width = WIDTH - 2 * PAD
  for i, step in ipairs(entry.guide.steps) do
    local r = stepRow(i)
    r.step, r.current = i, n
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", w.List, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    r.Text:SetWidth(width - 8)
    r.Text:SetText(string.format("%d. %s", i, step.text))
    if i < n then
      r.Text:SetTextColor(0.5, 0.5, 0.5)
    elseif i == n then
      r.Text:SetTextColor(1, 0.82, 0)
    else
      r.Text:SetTextColor(0.9, 0.9, 0.9)
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
  w:SetHeight(FULL_H)
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
  w.Title:SetText(entry.title)
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
  local items = {
    { title = entry.title },
    { text = following and L["Close guide"] or L["Follow"], onClick = function()
      if following then UI.StopGuide() else UI.StartGuide(id) end
    end },
    { text = entry.builtIn and L["Edit a copy..."] or L["Edit..."], onClick = function() UI.EditGuide(id) end },
    { text = L["Export..."], onClick = function() UI.ExportGuide(id) end },
    { text = L["Back to step 1"], onClick = function() UI.ResetGuide(id) end },
  }
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

UI.GuideWindow = function() return w end
