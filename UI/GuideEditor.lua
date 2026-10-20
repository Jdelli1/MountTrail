local ADDON, ns = ...

-- The guide editor: one window with a large text box for every way a guide
-- comes in or goes out, since a guide is just its text (Logic/Guide.lua):
--   * New guide: a template to fill in.
--   * Import guide: an empty box to paste a shared guide into.
--   * Edit: the player's guide (a built-in one opens as a copy).
--   * Export: the guide's text selected, ready for Ctrl+C.
-- The line under the box checks the text as it is typed: the step count, or
-- the first problem and its line number. Save keeps it (UI.SaveGuide).

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local WIDTH, HEIGHT = 520, 440
local PAD = 12

local e -- the window

local function check()
  local text = e.Edit:GetText() or ""
  local guide, errors = ns.Guide.Parse(text)
  local first = errors and errors[1]
  if first then
    e.Status:SetText(string.format(L["Line %d: %s"], first.line, L[first.msg] or first.msg))
    e.Status:SetTextColor(1, 0.45, 0.35)
  elseif guide then
    e.Status:SetText(string.format(L["%s: %d steps. Looks good."], guide.title, #guide.steps))
    e.Status:SetTextColor(0.55, 0.85, 0.55)
  end
  if e.mode ~= "export" then
    e.Save:SetEnabled(guide ~= nil)
    if e.Save.SetAlpha then e.Save:SetAlpha(guide and 1 or 0.4) end
  end
  return guide, errors
end

local function build()
  e = CreateFrame("Frame", "MountTrailGuideEditor", UIParent)
  e:SetSize(WIDTH, HEIGHT)
  e:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  e:SetFrameStrata("DIALOG")
  e:SetClampedToScreen(true)
  e:SetMovable(true)
  e:EnableMouse(true)
  e:RegisterForDrag("LeftButton")
  e:SetScript("OnDragStart", function(self) self:StartMoving() end)
  e:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
  local fill = e:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(e)
  fill:SetColorTexture(0.05, 0.05, 0.06, 0.97)
  UI.FlatBorder(e, 1, 1, 1, 0.15)
  if UISpecialFrames then tinsert(UISpecialFrames, "MountTrailGuideEditor") end

  local title = e:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
  title:SetPoint("TOPLEFT", e, "TOPLEFT", PAD, -PAD)
  title:SetPoint("TOPRIGHT", e, "TOPRIGHT", -PAD, -PAD)
  title:SetJustifyH("LEFT")
  e.Title = title
  local hint = e:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  hint:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  hint:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", 0, -4)
  hint:SetJustifyH("LEFT")
  hint:SetWordWrap(true)
  e.Hint = hint

  -- The text box: a multi-line edit box scrolling inside a dark field.
  local field = CreateFrame("Frame", nil, e)
  field:SetPoint("TOPLEFT", e, "TOPLEFT", PAD, -58)
  field:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", -PAD, 64)
  local fieldFill = field:CreateTexture(nil, "BACKGROUND")
  fieldFill:SetAllPoints(field)
  fieldFill:SetColorTexture(0, 0, 0, 0.5)
  UI.FlatBorder(field, 1, 1, 1, 0.2)
  local scroll = CreateFrame("ScrollFrame", nil, field)
  scroll:SetPoint("TOPLEFT", field, "TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", field, "BOTTOMRIGHT", -6, 6)
  if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
  local edit = CreateFrame("EditBox", nil, scroll)
  if edit.SetMultiLine then edit:SetMultiLine(true) end
  if edit.SetAutoFocus then edit:SetAutoFocus(false) end
  if edit.SetMaxLetters then edit:SetMaxLetters(0) end
  if edit.SetFontObject then edit:SetFontObject(UI.Font("GameFontHighlightSmall")) end
  edit:SetWidth(WIDTH - 2 * PAD - 14)
  edit:SetHeight(HEIGHT)
  scroll:SetScrollChild(edit)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, (edit:GetHeight() or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * 40)))
  end)
  -- Keep the cursor in view while typing.
  edit:SetScript("OnCursorChanged", function(_, _, y, _, h)
    local top = scroll:GetVerticalScroll() or 0
    local shown = scroll:GetHeight() or 0
    y = -(y or 0)
    if y < top then
      scroll:SetVerticalScroll(y)
    elseif y + (h or 0) > top + shown then
      scroll:SetVerticalScroll(y + (h or 0) - shown)
    end
  end)
  edit:SetScript("OnTextChanged", function() check() end)
  edit:SetScript("OnEscapePressed", function() e:Hide() end)
  -- A click anywhere in the field puts the cursor in the box.
  field:EnableMouse(true)
  field:SetScript("OnMouseDown", function() if edit.SetFocus then edit:SetFocus() end end)
  e.Edit, e.Scroll = edit, scroll

  local status = e:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
  status:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -6)
  status:SetPoint("TOPRIGHT", field, "BOTTOMRIGHT", 0, -6)
  status:SetJustifyH("LEFT")
  e.Status = status

  local save = UI.FlatButton(e, L["Save"], "gold", 22)
  save:SetWidth(90)
  save:SetPoint("BOTTOMRIGHT", e, "BOTTOMRIGHT", -PAD, 10)
  save:SetScript("OnClick", function()
    local text = e.Edit:GetText() or ""
    local id = UI.SaveGuide(text, e.guideID)
    if not id then
      check()
      return
    end
    e:Hide()
    if e.startAfter then UI.StartGuide(id) end
  end)
  e.Save = save
  local cancel = UI.FlatButton(e, L["Cancel"], "plain", 22)
  cancel:SetWidth(90)
  cancel:SetPoint("RIGHT", save, "LEFT", -6, 0)
  cancel:SetScript("OnClick", function() e:Hide() end)
  e.Cancel = cancel
  local selectAll = UI.FlatButton(e, L["Select all"], "plain", 22)
  selectAll:SetWidth(90)
  selectAll:SetPoint("BOTTOMLEFT", e, "BOTTOMLEFT", PAD, 10)
  selectAll:SetScript("OnClick", function()
    if edit.SetFocus then edit:SetFocus() end
    if edit.HighlightText then edit:HighlightText() end
  end)
  e.SelectAll = selectAll
  e:Hide()
end

-- Opens the editor. mode: "new" | "import" | "edit" | "export".
local function open(mode, titleText, hintText, body, guideID, startAfter)
  if not e then build() end
  if UI.HideMenu then UI.HideMenu() end
  e.mode, e.guideID, e.startAfter = mode, guideID, startAfter
  e.Title:SetText(titleText)
  e.Hint:SetText(hintText or "")
  e.Edit:SetText(body or "")
  e.Save:SetShown(mode ~= "export")
  UI.FlatButtonSetText(e.Cancel, mode == "export" and L["Close"] or L["Cancel"])
  e.Cancel:SetWidth(90)
  e:Show()
  if e.Raise then e:Raise() end
  check()
  if e.Edit.SetFocus then e.Edit:SetFocus() end
  if mode == "export" and e.Edit.HighlightText then e.Edit:HighlightText() end
  return e
end

function UI.NewGuide()
  return open("new", L["New guide"],
    L["One keyword per line: #guide, #mount, step, note, goto, quest, item, mount, reach. See the README for the format."],
    ns.Guide.TEMPLATE, nil, true)
end

function UI.ImportGuide()
  return open("import", L["Import a guide"], L["Paste a MountTrail guide (it starts with #guide), then Save."], "", nil, true)
end

-- Edits guide `id` (a built-in guide: a copy, saved as the player's own).
function UI.EditGuide(id)
  local entry = UI.GuideById(id)
  if not entry then return nil end
  if entry.builtIn then
    return open("edit", string.format(L["Edit a copy of %s"], entry.title),
      L["Built-in guides stay as they are: Save keeps this as your own guide."], entry.text, nil, false)
  end
  return open("edit", string.format(L["Edit %s"], entry.title), nil, entry.text, entry.id, false)
end

function UI.ExportGuide(id)
  local entry = UI.GuideById(id)
  if not entry then return nil end
  return open("export", string.format(L["Export %s"], entry.title),
    L["Ctrl+C to copy. Anyone with MountTrail can import it (Guides > + > Import guide)."], entry.text, entry.id, false)
end

UI.GuideEditor = function() return e end
