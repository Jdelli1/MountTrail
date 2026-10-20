local ADDON, ns = ...

-- Pop-out rare tracker: a slim movable window that stays on screen without
-- the main window and lists the rare-spawn mounts of one expansion (or of
-- the zone the player is in) as a little checklist. Each row: a box (the
-- daily kill as the game reports it, ticked and dimmed when done; a rare
-- with no lockout gets the Checklist's "last checked" box, left-click marks,
-- right-click clears), the rare's name, its zone, and a -> button for a
-- waypoint to its spawn point nearest the player (Map.SetWaypoint); a rare
-- with several spawn points lists each as a small coordinate button
-- (Map.SetWaypointAt). Entries come from the Checklist (UI.ChecklistBuild:
-- the daily / weekly "rares" category and the rare spawns with no lockout),
-- so owned mounts and the other faction's are already left out. The title
-- opens a menu to pick the expansion or "Current zone"; the window's
-- position, open state and choice are saved (ns.db.global.rareTracker).
-- Opened by right-clicking a rare header in the Checklist (that expansion,
-- UI.OpenRareTracker) and /azt rares.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local WIDTH = 280
local TITLE_HEIGHT = 26
local ROW_HEIGHT = 20
local POINT_HEIGHT = 15
local MAX_HEIGHT = 460
local ZONE = "zone" -- the "Current zone" choice
local AGE_TICK = 60

local function stateDB()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.rareTracker) ~= "table" then global.rareTracker = {} end
  return global.rareTracker
end

-- Pure helpers -------------------------------------------------------------------

local function isRareEntry(e)
  return e.category == "rares"
end

-- The rare behind an entry: its spot's NPC name (Map.Spots), else the
-- checklist's boss, else the mount's name.
local function rareName(e)
  local map = ns.Map
  local spots = map and map.Spots and map.Spots(e.id, ns.Game.Faction and ns.Game.Faction() or nil) or {}
  return (spots[1] and spots[1].name) or e.boss or (e.m and e.m.name) or tostring(e.id), spots
end

-- Expansions that have rare entries, in Data.Expansions order.
function UI.RareTrackerExpansions(built)
  local have = {}
  for _, list in ipairs({ built.daily or {}, built.weekly or {}, built.camp or {} }) do
    for _, e in ipairs(list) do
      local exp = e.exp or (e.m and e.m.exp)
      if (isRareEntry(e) or list == built.camp) and exp then have[exp] = true end
    end
  end
  local out = {}
  for _, exp in ipairs((ns.Data and ns.Data.Expansions) or {}) do
    if have[exp] then out[#out + 1] = exp end
  end
  return out
end

-- The tracker's rows for `choice` (an expansion name, or "zone" with
-- `zoneIDs` = { [mountID] = true } of the player's zone) -> list of { key =,
-- id =, entry =, name =, zone =, done =, camp =, checked = (camp: the
-- last-checked time or nil), spots = Map.Spots } - open ones first, then by
-- name - and how many are left (not done; camp rows count as left).
function UI.RareTrackerRows(built, choice, zoneIDs, campStore)
  local rows, left = {}, 0
  local function want(e)
    if choice == ZONE then return zoneIDs ~= nil and zoneIDs[e.id] == true end
    return (e.exp or (e.m and e.m.exp)) == choice
  end
  local function add(e, camp)
    if not want(e) then return end
    local name, spots = rareName(e)
    local zone = e.zone
    if not zone and spots[1] and ns.Game.MapName then zone = ns.Game.MapName(spots[1].pts[1]) end
    local row = { key = e.key, id = e.id, entry = e, name = name, zone = zone, done = e.done == true,
      camp = camp, spots = spots }
    if camp and type(campStore) == "table" then row.checked = campStore[e.key] end
    if not row.done then left = left + 1 end
    rows[#rows + 1] = row
  end
  for _, reset in ipairs({ "daily", "weekly" }) do
    for _, e in ipairs(built[reset] or {}) do
      if isRareEntry(e) then add(e, false) end
    end
  end
  for _, e in ipairs(built.camp or {}) do add(e, true) end
  table.sort(rows, function(a, b)
    if a.done ~= b.done then return not a.done end
    if a.name ~= b.name then return string.lower(a.name) < string.lower(b.name) end
    return tostring(a.key) < tostring(b.key)
  end)
  return rows, left
end

-- Widget -----------------------------------------------------------------------

local frame
local rowFrames, pointFrames = {}, {}
local ticker

local function savePosition()
  local db = stateDB()
  if not (db and frame) then return end
  local point, _, relPoint, x, y = frame:GetPoint(1)
  db.point, db.relPoint, db.x, db.y = point, relPoint, x, y
end

local function choice()
  local db = stateDB()
  local c = db and db.exp
  if c then return c end
  local exps = (ns.Data and ns.Data.Expansions) or {}
  return exps[#exps] or ZONE
end

local function setChoice(c)
  local db = stateDB()
  if db then db.exp = c end
  UI.RefreshRareTracker()
end

local function zoneIDs()
  local ids = {}
  if not UI.ZoneMounts then return ids end
  local list = UI.ZoneMounts()
  for _, entry in ipairs(list or {}) do ids[entry.id] = true end
  return ids
end

local function rowFrame(i)
  local r = rowFrames[i]
  if r then return r end
  r = CreateFrame("Button", nil, frame.Content)
  r:SetHeight(ROW_HEIGHT)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(r)
  hl:SetColorTexture(1, 1, 1, 0.06)
  local check = CreateFrame("CheckButton", nil, r,
    UI.TemplateChain("MinimalCheckboxTemplate", "SettingsCheckboxTemplate", "UICheckButtonTemplate"))
  check:SetSize(18, 18)
  check:SetPoint("LEFT", r, "LEFT", 2, 0)
  if check.RegisterForClicks then check:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  check:SetScript("OnClick", function(self, button)
    local row = r.data
    local char = ns.db and ns.db.char
    if row and row.camp and char then
      if type(char.campChecked) ~= "table" then char.campChecked = {} end
      UI.ChecklistCampClick(row.entry, char.campChecked, ns.Game.Now(), button)
    end
    ns.Refresh()
  end)
  r.Check = check
  local go = CreateFrame("Button", nil, r)
  go:SetSize(18, 18)
  go:SetPoint("RIGHT", r, "RIGHT", -2, 0)
  local goIcon = go:CreateTexture(nil, "ARTWORK")
  goIcon:SetAllPoints(go)
  local atlas, texture = UI.PinIcon()
  if atlas then goIcon:SetAtlas(atlas) else goIcon:SetTexture(texture) end
  go.Icon = goIcon
  local goHl = go:CreateTexture(nil, "HIGHLIGHT")
  goHl:SetAllPoints(go)
  goHl:SetColorTexture(1, 1, 1, 0.15)
  go:SetScript("OnClick", function()
    if r.data and ns.Map then ns.Map.SetWaypoint(r.data.id) end
  end)
  r.Go = go
  local zone = r:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  zone:SetPoint("RIGHT", go, "LEFT", -4, 0)
  zone:SetJustifyH("RIGHT")
  zone:SetWordWrap(false)
  r.Zone = zone
  local name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  name:SetPoint("LEFT", check, "RIGHT", 2, 0)
  name:SetPoint("RIGHT", zone, "LEFT", -6, 0)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  r.Name = name
  -- The row itself: left-click waypoint, hover the mount tooltip.
  r:SetScript("OnClick", function(self, button)
    if button == "LeftButton" and self.data and ns.Map then ns.Map.SetWaypoint(self.data.id) end
  end)
  r:SetScript("OnEnter", function(self)
    if self.data and UI.ShowMountTooltip then UI.ShowMountTooltip(self, self.data.id) end
  end)
  r:SetScript("OnLeave", function() if UI.HideMountTooltip then UI.HideMountTooltip() end end)
  rowFrames[i] = r
  return r
end

local function pointFrame(i)
  local b = pointFrames[i]
  if b then return b end
  b = CreateFrame("Button", nil, frame.Content)
  b:SetHeight(POINT_HEIGHT)
  local text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("LEFT", b, "LEFT", 3, 0)
  b.Text = text
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(b)
  bg:SetColorTexture(1, 0.82, 0, 0.12)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(b)
  hl:SetColorTexture(1, 0.82, 0, 0.25)
  b:SetScript("OnClick", function(self)
    if ns.Map and ns.Map.SetWaypointAt then ns.Map.SetWaypointAt(self.m, self.x, self.y, self.npc) end
  end)
  pointFrames[i] = b
  return b
end

local function title(left)
  local c = choice()
  local label = c == ZONE and L["Current zone"] or L[c]
  return string.format(L["%s rare spawns"], label) .. "  |cff9d9d9d(" .. string.format(L["%d left"], left) .. ")|r"
end

function UI.RefreshRareTracker()
  if not (frame and frame:IsShown()) then return end
  local c = choice()
  local built = UI.ChecklistBuild(ns.Game.Now())
  local char = ns.db and ns.db.char
  local rows, left = UI.RareTrackerRows(built, c, c == ZONE and zoneIDs() or nil, char and char.campChecked)
  frame.rows = rows
  frame.Title:SetText(title(left))
  local width = WIDTH - 24
  local y, used = 0, 0
  for i, row in ipairs(rows) do
    local r = rowFrame(i)
    r.data = row
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", frame.Content, "TOPLEFT", 0, -y)
    r:SetWidth(width)
    r:Show()
    r.Name:SetText(row.name)
    r.Name:SetFontObject(row.done and "GameFontDisableSmall" or "GameFontHighlightSmall")
    local zoneText = row.zone or ""
    if row.camp and row.checked then
      zoneText = string.format(L["checked %s ago"], UI.FormatAgo(ns.Game.Now() - row.checked))
    end
    r.Zone:SetText(zoneText)
    r.Check:SetChecked(row.done or (row.camp and row.checked ~= nil) or false)
    r.Check:SetEnabled(row.camp and true or false)
    r.Go:SetShown(not row.done)
    y = y + ROW_HEIGHT
    -- Several spawn points: each as a coordinate button under the row.
    local points = {}
    for _, spot in ipairs(row.spots or {}) do
      local pts = spot.pts
      for k = 1, #pts - 2, 3 do points[#points + 1] = { pts[k], pts[k + 1], pts[k + 2], spot.name } end
    end
    if #points > 1 and not row.done then
      local x = 22
      for _, p in ipairs(points) do
        used = used + 1
        local b = pointFrame(used)
        b.m, b.x, b.y, b.npc = p[1], p[2], p[3], p[4] or row.name
        b.Text:SetText(string.format("%.1f, %.1f", p[2], p[3]))
        local w = (b.Text.GetStringWidth and b.Text:GetStringWidth() or 56) + 6
        if x + w > width then
          x = 22
          y = y + POINT_HEIGHT + 2
        end
        b:SetWidth(w)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", frame.Content, "TOPLEFT", x, -y)
        b:Show()
        x = x + w + 4
      end
      y = y + POINT_HEIGHT + 4
    end
  end
  for i = #rows + 1, #rowFrames do rowFrames[i]:Hide() end
  for i = used + 1, #pointFrames do pointFrames[i]:Hide() end
  frame.Empty:SetShown(#rows == 0)
  if #rows == 0 then y = 30 end
  frame.Content:SetHeight(math.max(y, 1))
  frame.contentHeight = y
  frame:SetHeight(math.min(MAX_HEIGHT, TITLE_HEIGHT + y + 10))
end

local function openMenu(owner)
  local exps = UI.RareTrackerExpansions(UI.ChecklistBuild(ns.Game.Now()))
  local menu = MenuUtil
  if menu and type(menu.CreateContextMenu) == "function" then
    menu.CreateContextMenu(owner, function(_, root)
      root:CreateTitle(L["Show rare spawns of"])
      local function radio(label, value)
        root:CreateRadio(label, function() return choice() == value end, function() setChoice(value) end, value)
      end
      radio(L["Current zone"], ZONE)
      for _, exp in ipairs(exps) do radio(L[exp], exp) end
    end)
    return
  end
  -- No menu API: step through the choices.
  local choices = { ZONE }
  for _, exp in ipairs(exps) do choices[#choices + 1] = exp end
  local now = choice()
  for i, c in ipairs(choices) do
    if c == now then
      setChoice(choices[i % #choices + 1])
      return
    end
  end
  setChoice(choices[1])
end

local function build()
  frame = CreateFrame("Frame", "AzerothTrailRareTracker", UIParent)
  frame:SetSize(WIDTH, 120)
  frame:SetFrameStrata("MEDIUM")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:Hide()
  local db = stateDB()
  frame:ClearAllPoints()
  if db and db.point then
    frame:SetPoint(db.point, UIParent, db.relPoint or db.point, db.x or 0, db.y or 0)
  else
    frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 60)
  end

  local fill = frame:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(frame)
  fill:SetColorTexture(0.06, 0.06, 0.07, 0.92)
  frame.Edge = UI.FlatBorder(frame, 1, 1, 1, 0.12)

  -- Title strip: drag to move; click the title for the expansion menu.
  local strip = CreateFrame("Button", nil, frame)
  strip:SetPoint("TOPLEFT", frame, "TOPLEFT", 1, -1)
  strip:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -1, -1)
  strip:SetHeight(TITLE_HEIGHT)
  strip:RegisterForDrag("LeftButton")
  strip:RegisterForClicks("LeftButtonUp")
  strip:SetScript("OnDragStart", function() frame:StartMoving() end)
  strip:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
    if frame.SetUserPlaced then frame:SetUserPlaced(false) end
    savePosition()
  end)
  strip:SetScript("OnClick", function(self) openMenu(self) end)
  strip:SetScript("OnEnter", function(self)
    if not GameTooltip then return end
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText(L["Click to choose the expansion; drag to move"], 0.5, 0.9, 0.5)
    GameTooltip:Show()
  end)
  strip:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
  local stripBg = strip:CreateTexture(nil, "BACKGROUND")
  stripBg:SetAllPoints(strip)
  stripBg:SetColorTexture(1, 1, 1, 0.05)
  local rule = frame:CreateTexture(nil, "BORDER")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, 0)
  rule:SetColorTexture(1, 0.82, 0, 0.3)
  frame.Strip = strip

  local close = CreateFrame("Button", nil, strip, "UIPanelCloseButton")
  close:SetSize(22, 22)
  close:SetPoint("RIGHT", strip, "RIGHT", -2, 0)
  close:SetScript("OnClick", function() UI.ToggleRareTracker(false) end)
  frame.Close = close

  -- A small down arrow: the title opens a menu.
  local arrow = strip:CreateTexture(nil, "ARTWORK")
  arrow:SetSize(12, 12)
  arrow:SetPoint("RIGHT", close, "LEFT", -2, 0)
  if UI.AtlasExists("common-dropdown-icon-down") then
    arrow:SetAtlas("common-dropdown-icon-down")
  else
    arrow:SetTexture("Interface\\ChatFrame\\ChatFrameExpandArrow")
  end
  frame.Arrow = arrow

  local titleText = strip:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  titleText:SetPoint("LEFT", strip, "LEFT", 8, 0)
  titleText:SetPoint("RIGHT", arrow, "LEFT", -4, 0)
  titleText:SetJustifyH("LEFT")
  titleText:SetWordWrap(false)
  frame.Title = titleText

  local scroll = CreateFrame("ScrollFrame", nil, frame)
  scroll:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 6, -4)
  scroll:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -6, 6)
  if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(WIDTH - 12, 1)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, (frame.contentHeight or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * 30)))
  end)
  frame.Scroll, frame.Content = scroll, content

  local empty = content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  empty:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -6)
  empty:SetText(L["No rare-spawn mounts left here."])
  empty:Hide()
  frame.Empty = empty

  frame:SetScript("OnShow", function()
    UI.RefreshRareTracker()
    if not ticker and type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function" then
      ticker = C_Timer.NewTicker(AGE_TICK, function() UI.RefreshRareTracker() end)
    end
  end)
  frame:SetScript("OnHide", function()
    if ticker and ticker.Cancel then ticker:Cancel() end
    ticker = nil
  end)
  UI.rareTracker = frame
  return frame
end

-- Shows (true), hides (false) or flips (nil) the tracker; saved.
function UI.ToggleRareTracker(show)
  if not frame then build() end
  if show == nil then show = not frame:IsShown() end
  local db = stateDB()
  if db then db.open = show and true or false end
  frame:SetShown(show and true or false)
  if show then UI.RefreshRareTracker() end
  return show and true or false
end

-- Shows the tracker on `exp` (an expansion name, or "zone").
function UI.OpenRareTracker(exp)
  local db = stateDB()
  if db and exp then db.exp = exp end
  return UI.ToggleRareTracker(true)
end

UI.AddRefreshHook(function() UI.RefreshRareTracker() end)

-- Back on screen after /reload when it was open; follows the player's zone
-- in "Current zone" mode.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("ZONE_CHANGED_NEW_AREA")
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local db = stateDB()
    if db and db.open then UI.ToggleRareTracker(true) end
  elseif choice() == ZONE then
    UI.RefreshRareTracker()
  end
end)
