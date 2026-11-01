local ADDON, ns = ...

-- Pop-out checklists: slim movable windows that stay on screen without the
-- main window, any number at once, each showing one set:
--   { kind = "camp", exp = }                 rare spawns with no lockout of an expansion
--   { kind = "daily" | "weekly", exp = [, category = ] }   that reset's lockouts
--                                            of an expansion (one category, e.g. "rares")
--   { kind = "daily" | "weekly" | "camp", all = true }   that whole group, every
--                                            expansion (a Checklist chip's right-click)
--   { kind = "zone" }                        the rares of the zone the player is in
--   { kind = "zonemounts" }                  every mount still to get in the zone the
--                                            player is in (the zone panel's list)
--   { kind = "list", list = id }             a custom list (Logic/Lists.lua)
--   { kind = "quick", key = }                a quick list (Logic/QuickLists.lua)
-- Opened by right-clicking a Checklist header (that set), a custom list's
-- header menu, /mtrail rares (the zone's rares), and /mtrail here or a
-- right-click on the zone panel's title (the zone's mounts; both zone windows
-- follow the player). Rows come from the
-- Checklist (UI.ChecklistBuild), so they match it: a box (a lockout ticked
-- and dimmed when the game says done; a rare spawn's "last checked" box,
-- left-click marks, right-click clears), the name (the rare's for rare
-- rows) and its zone. A click on the row is UI.GoTo: every spawn point of
-- a rare that has several on TomTom, else the waypoint; Shift-click opens
-- the world map there and Ctrl-click previews the mount, as in the lists
-- (UI.RowClickAction). "Plot all" in the
-- title puts the spawn points of every row whose box is not ticked on
-- TomTom at once (Map.PlotMounts). Ctrl-click a window's x to close every
-- pop-out. A custom list's rows are its mounts (ones already known left out);
-- right-click one to take it off the list. Each window can be resized with
-- its corner grip (right-click: fit to its rows again) and snaps to another
-- pop-out or the main window when dropped near one (UI.SnapRect). Alt-drag
-- a row to move it: the order is saved per window (done rows stay last).
-- Windows that are not the player's own list (quick lists, the zone's
-- rares) group their rows under expansion headers when they span several
-- (UI.PopoutGroups); click a group header to collapse it, Shift-click to
-- collapse (or, on a collapsed one, expand) every group of the window
-- (saved per window as ns.db.global.popouts[key].collapsed, UI.ToggleAllCollapsed).
-- Two layouts (the appearance menu, per window): Cards, the default (each
-- group a card, rows with the mount's icon, a second line and the status;
-- layoutRow / placeCard below), and Compact (one line a row).
-- Right-click a window's title for its appearance:
-- opacity and font size (sliders, 20-100 % and 8-24), background and text
-- colour and font (saved per window, UI.PopoutStyle; "Apply to all
-- pop-outs" makes it every window's look, new ones too; "Reset
-- appearance"). Windows snapped together move
-- together: dragging one takes those snapped under it or to its right along
-- (UI.SnapChain), so the top of a stack moves the whole stack.
-- Each row carries a small expansion tag (UI.ExpansionBadge). Each
-- window's position and open
-- state are saved by its set (ns.db.global.popouts) and come back after
-- /reload.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local WIDTH = 280
local TITLE_HEIGHT = 26
local ROW_HEIGHT = 20
local MAX_HEIGHT = 460
local AGE_TICK = 60
local CASCADE = 24
local MIN_W, MIN_H = 200, 70

local function popoutsDB()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.popouts) ~= "table" then global.popouts = {} end
  return global.popouts
end

-- The shared look (UI/Style.lua, loaded before this file in game).
local function styleOf(w) return UI.PopoutStyleOf(w) end
local function styleText(...) return UI.PopoutStyleText(...) end
local function headerText(...) return UI.PopoutStyleHeader(...) end
local function applyChrome(w, style) return UI.PopoutApplyChrome(w, style) end

local function listsDB()
  local global = ns.db and ns.db.global
  if not global then return nil end
  if type(global.lists) ~= "table" then global.lists = {} end
  return global.lists
end
UI.ListsDB = listsDB

-- Widget -----------------------------------------------------------------------

-- Rows, groups, order and snapping maths: UI/PopoutRows.lua.

local function rectOf(f)
  local l, t, r, b = f:GetLeft(), f:GetTop(), f:GetRight(), f:GetBottom()
  if not (l and t and r and b) then return nil end
  return { left = l, top = t, right = r, bottom = b }
end

-- A row's click (the row or its pin): UI.GoTo for its mount and boss.
function UI.PopoutGo(row)
  if row then UI.RowGo(row.id, row.entry and row.entry.boss) end
end

local windows = {} -- key -> window frame
local ticker

local function savePosition(w)
  local db = popoutsDB()
  if not db then return end
  local state = db[w.key] or {}
  local point, _, relPoint, x, y = w:GetPoint(1)
  state.point, state.relPoint, state.x, state.y = point, relPoint, x, y
  db[w.key] = state
end

local function zoneIDs()
  local ids = {}
  if not UI.ZoneMounts then return ids end
  local list = UI.ZoneMounts()
  for _, entry in ipairs(list or {}) do ids[entry.id] = true end
  return ids
end

local function rowFrame(w, i)
  local r = w.rowFrames[i]
  if r then return r end
  r = CreateFrame("Button", nil, w.Content)
  r:SetHeight(ROW_HEIGHT)
  r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  local hl = r:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(r)
  hl:SetColorTexture(1, 1, 1, 0.06)
  local check = CreateFrame("CheckButton", nil, r,
    UI.TemplateChain("MinimalCheckboxTemplate", "SettingsCheckboxTemplate", "UICheckButtonTemplate"))
  check:SetSize(18, 18)
  if check.RegisterForClicks then check:RegisterForClicks("LeftButtonUp", "RightButtonUp") end
  check:SetScript("OnClick", function(_, button)
    local row = r.data
    local char = ns.db and ns.db.char
    if row and row.camp and char then
      if type(char.campChecked) ~= "table" then char.campChecked = {} end
      UI.ChecklistCampClick(row.entry, char.campChecked, ns.Game.Now(), button)
    end
    ns.Refresh()
  end)
  r.Check = check
  local zone = r:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  zone:SetJustifyH("RIGHT")
  zone:SetWordWrap(false)
  r.Zone = zone
  -- The mount's expansion: a small coloured tag (Compact).
  r.Badge = UI.ExpansionBadge(r)
  local name = r:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  r.Name = name
  -- Cards: the mount's icon, a grey second line and the status on the right.
  local icon = r:CreateTexture(nil, "ARTWORK")
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  r.Icon = icon
  local subLine = r:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  subLine:SetJustifyH("LEFT")
  subLine:SetWordWrap(false)
  r.Sub = subLine
  local status = r:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalSmall"))
  status:SetJustifyH("RIGHT")
  status:SetWordWrap(false)
  r.Status = status
  -- The row: left-click as the pin; a custom list's row: right-click menu.
  -- Alt-drag: move the row (the drop line shows where it lands).
  r:RegisterForDrag("LeftButton")
  r:SetScript("OnDragStart", function(self)
    if not (type(IsAltKeyDown) == "function" and IsAltKeyDown()) or not self.data then return end
    w.dragKey = self.data.key
    w.DropLine:Show()
    w:SetScript("OnUpdate", function() UI.PopoutDragUpdate(w) end)
  end)
  r:SetScript("OnDragStop", function()
    if not w.dragKey then return end
    w.justDragged = true
    UI.PopoutDragDrop(w)
  end)
  r:SetScript("OnClick", function(self, button)
    if w.justDragged then
      w.justDragged = nil
      return
    end
    local action = UI.RowClickAction and UI.RowClickAction(button,
      type(IsControlKeyDown) == "function" and IsControlKeyDown() and true or false,
      type(IsShiftKeyDown) == "function" and IsShiftKeyDown() and true or false)
    local data = self.data
    if action == "map" and data then
      if UI.MapAction then UI.MapAction("OpenMap", data.id, data.entry and data.entry.boss) end
    elseif action == "preview" and data then
      if UI.PreviewMount then UI.PreviewMount(data.id) end
    elseif button == "LeftButton" then
      UI.PopoutGo(data)
    elseif button == "RightButton" and w.source.kind == "list" and self.data then
      local data = self.data
      local function edit(fn)
        return function()
          local store = listsDB()
          if store then fn(store) end
          ns.Refresh()
        end
      end
      UI.ShowMenu(self, {
        { title = data.name },
        { text = L["Move up"], onClick = edit(function(store) ns.Lists.Move(store, w.source.list, data.id, -1) end) },
        { text = L["Move down"], onClick = edit(function(store) ns.Lists.Move(store, w.source.list, data.id, 1) end) },
        { separator = true },
        { text = string.format(L["Remove from %s"], UI.PopoutTitle(w.source, listsDB())),
          onClick = edit(function(store) ns.Lists.Remove(store, w.source.list, data.id) end) },
      }, "cursor")
    end
  end)
  r:SetScript("OnEnter", function(self)
    if self.data and UI.ShowMountTooltip then UI.ShowMountTooltip(self, self.data.id) end
  end)
  r:SetScript("OnLeave", function() if UI.HideMountTooltip then UI.HideMountTooltip() end end)
  w.rowFrames[i] = r
  return r
end

-- The expansion group of the row being dragged (nil: none / no groups).
local function dragGroup(w)
  for _, s in ipairs(w.slots or {}) do
    if s.key == w.dragKey then return s.group end
  end
end

-- Where a dragged row would land: the row slot under the cursor.
local function dropIndex(w)
  local top = w.Content:GetTop()
  if not (top and type(GetCursorPosition) == "function") then return nil end
  local _, y = GetCursorPosition()
  local eff = w.Content.GetEffectiveScale and w.Content:GetEffectiveScale() or 1
  local offset = top - y / eff
  local h = w.rowHeight or ROW_HEIGHT
  local slots = w.slots or {}
  local i = 1
  for _, slot in ipairs(slots) do
    if slot.y + h / 2 < offset then i = i + 1 end
  end
  -- A row stays in its expansion's group: the slots of that group only.
  local g = dragGroup(w)
  local lo, hi
  for k, s in ipairs(slots) do
    if g and s.group == g then
      lo = lo or k
      hi = k + 1
    end
  end
  if lo then i = math.max(lo, math.min(hi, i)) end
  return i
end

function UI.PopoutDragUpdate(w)
  local i = dropIndex(w)
  if not i then return end
  local slots = w.slots or {}
  local h = w.rowHeight or ROW_HEIGHT
  -- Above the slot's row, or under the group's last row at its end.
  local g, nxt, prev = dragGroup(w), slots[i], slots[i - 1]
  local y = 0
  if nxt and (g == nil or nxt.group == g) then
    y = nxt.y
  elseif prev then
    y = prev.y + h
  end
  w.DropLine:ClearAllPoints()
  w.DropLine:SetPoint("TOPLEFT", w.Content, "TOPLEFT", 0, -y)
  w.DropLine:SetPoint("TOPRIGHT", w.Content, "TOPRIGHT", 0, -y)
  w.dropAt = i
end

-- Ends an Alt-drag: the row moves to the drop slot; the order is saved.
function UI.PopoutDragDrop(w)
  local key, to = w.dragKey, w.dropAt or dropIndex(w)
  w.dragKey, w.dropAt = nil, nil
  w:SetScript("OnUpdate", nil)
  w.DropLine:Hide()
  if not (key and to) then return end
  local keys = {}
  for _, row in ipairs(w.rows or {}) do
    if not row.done then
      keys[#keys + 1] = row.key
      if row.key == key and #keys < to then to = to - 1 end -- its own slot goes away
    end
  end
  local moved = UI.MoveKey(keys, key, to)
  local store = listsDB()
  if w.source.kind == "list" and store then
    -- A custom list: the mount moves in the list itself, before the row now
    -- after it (the main window's list page shows the same order).
    local idOf = {}
    for _, row in ipairs(w.rows or {}) do idOf[row.key] = row.id end
    local nextKey
    for i, k in ipairs(moved) do if k == key then nextKey = moved[i + 1] end end
    ns.Lists.MoveBefore(store, w.source.list, idOf[key], nextKey and idOf[nextKey] or nil)
    ns.Refresh()
    return
  end
  local db = popoutsDB()
  if db then
    db[w.key] = db[w.key] or {}
    db[w.key].order = moved
  end
  UI.RefreshPopouts()
end

-- Rows follow the window's width (it can be resized).
local function layoutWidth(w)
  local width = math.max(MIN_W, w:GetWidth() or WIDTH)
  w.Content:SetWidth(width - 12)
  for _, r in ipairs(w.rowFrames) do r:SetWidth(width - 24) end
end

-- Expansion group headers in a window, reused between refreshes.
local GROUP_HEIGHT = 18
-- The window's collapsed groups ({ [group key] = true }), created on demand.
local function collapsedOf(w)
  local db = popoutsDB()
  if not db then return {} end
  db[w.key] = db[w.key] or {}
  if type(db[w.key].collapsed) ~= "table" then db[w.key].collapsed = {} end
  return db[w.key].collapsed
end

-- The key a group header collapses under: its source or expansion.
function UI.PopoutGroupKey(g)
  return tostring(g.source or g.exp or "?")
end

local function groupHeader(w, i)
  local h = w.groupFrames[i]
  if h then return h end
  h = CreateFrame("Frame", nil, w.Content)
  h:SetHeight(GROUP_HEIGHT)
  h:EnableMouse(true)
  -- Click: collapse / expand this group; Shift-click: every group at once.
  h:SetScript("OnMouseUp", function(self, button)
    if button ~= "LeftButton" or not self.groupKey then return end
    local store = collapsedOf(w)
    if UI.ShiftDown and UI.ShiftDown() then
      UI.ToggleAllCollapsed(store, w.groupRows, { collapsed = store[self.groupKey] == true })
    else
      UI.ToggleCollapsed(store, self.groupKey)
    end
    UI.RefreshPopouts()
  end)
  h:SetScript("OnEnter", function(self)
    UI.ShowHint(self, L["Click: collapse or expand"], L["Shift-click: all groups at once"])
  end)
  h:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  local text = h:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalSmall"))
  text:SetPoint("LEFT", h, "LEFT", 2, 0)
  h.Text = text
  local rule = h:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 1)
  rule:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 1)
  h.Rule = rule
  w.groupFrames[i] = h
  return h
end


-- Every shown pop-out, extra window and the main window but those in
-- `except` ({ [frame] = true }) -> their rects (UI.SnapRect's `others`).
function UI.PopoutSnapTargets(except)
  except = except or {}
  local out = {}
  local function add(f)
    if f and not except[f] and f:IsShown() then out[#out + 1] = rectOf(f) end
  end
  for _, o in pairs(windows) do add(o) end
  for _, o in ipairs(UI.StyledWindows()) do add(o) end
  if UI.frame then add(UI.frame) end
  return out
end


-- Cards layout (the default; Compact: one line a row): each group a card, a
-- fill a shade lighter than the window with an edge in its expansion's
-- colour (gold without one); rows with the mount's icon, the name over a
-- grey line (UI.PopoutCardLines) and the status on the right. A rare spawn
-- keeps its box, on the right.
local CARD_ROW, CARD_HEADER, CARD_GAP, CARD_INSET = 34, 22, 6, 9
local STATUS_COLORS = { done = { 0.55, 0.88, 0.55 }, open = { 1, 0.82, 0 }, info = { 0.75, 0.75, 0.75 } }
local GOLD = { 1, 0.82, 0 }

local function placeCard(w, i, top, bottom, width, style, color)
  w.cards = w.cards or {}
  local c = w.cards[i]
  if not c then
    c = { Fill = w.Content:CreateTexture(nil, "BACKGROUND"), Edge = w.Content:CreateTexture(nil, "BORDER") }
    w.cards[i] = c
  end
  local bg = style.bg
  for _, t in ipairs({ c.Fill, c.Edge }) do
    t:ClearAllPoints()
    t:SetPoint("TOPLEFT", w.Content, "TOPLEFT", 0, -top)
    t:SetHeight(bottom - top)
    t:Show()
  end
  c.Fill:SetWidth(width)
  c.Fill:SetColorTexture(math.min(1, bg[1] + 0.05), math.min(1, bg[2] + 0.05), math.min(1, bg[3] + 0.05), style.alpha)
  c.Edge:SetWidth(3)
  c.Edge:SetColorTexture(color[1], color[2], color[3], 0.9)
end

-- A row's parts placed for the layout; `right`: the room kept on the right
-- in Cards (the status or the box).
local function layoutRow(r, cards, iconSize, right)
  for _, part in ipairs({ r.Check, r.Badge, r.Name, r.Zone, r.Icon, r.Sub, r.Status }) do part:ClearAllPoints() end
  if cards then
    r.Icon:SetSize(iconSize, iconSize)
    r.Icon:SetPoint("LEFT", r, "LEFT", 0, 0)
    r.Name:SetPoint("BOTTOMLEFT", r.Icon, "RIGHT", 8, 1)
    r.Name:SetPoint("BOTTOMRIGHT", r, "RIGHT", -right, 1)
    r.Sub:SetPoint("TOPLEFT", r.Icon, "RIGHT", 8, -1)
    r.Sub:SetPoint("TOPRIGHT", r, "RIGHT", -right, -1)
    r.Status:SetPoint("RIGHT", r, "RIGHT", -6, 0)
    r.Check:SetPoint("RIGHT", r, "RIGHT", -2, 0)
  else
    r.Check:SetPoint("LEFT", r, "LEFT", 2, 0)
    r.Badge:SetPoint("LEFT", r.Check, "RIGHT", 2, 0)
    r.Zone:SetPoint("RIGHT", r, "RIGHT", -4, 0)
    r.Name:SetPoint("LEFT", r.Badge, "RIGHT", 5, 0)
    r.Name:SetPoint("RIGHT", r.Zone, "LEFT", -6, 0)
  end
  r.Icon:SetShown(cards)
  r.Sub:SetShown(cards)
  r.Zone:SetShown(not cards)
end

local function refreshWindow(w, built)
  if not w:IsShown() then return end
  local char = ns.db and ns.db.char
  local store = listsDB()
  if w.source.kind == "list" and not (store and ns.Lists.Get(store, w.source.list)) then
    UI.ClosePopout(w.key) -- the list was deleted
    return
  end
  -- The zone windows remember the map they show (their zone events compare).
  local follows = w.source.kind == "zone" or w.source.kind == "zonemounts"
  if follows then w.map = ns.Game.PlayerMap() end
  local zoneMounts
  if w.source.kind == "zonemounts" then
    zoneMounts = {}
    local list, zone = {}, nil
    if UI.ZoneMounts then list, zone = UI.ZoneMounts() end
    for _, entry in ipairs(list or {}) do zoneMounts[#zoneMounts + 1] = entry.id end
    w.source.zoneName = zone and zone.name or nil
  end
  local rows, left = UI.PopoutRows(w.source, built, {
    zoneIDs = w.source.kind == "zone" and zoneIDs() or nil,
    zoneMounts = zoneMounts,
    campStore = char and char.campChecked,
    store = store,
    isOwned = ns.Game.IsOwned,
  })
  local db = popoutsDB()
  local state = db and db[w.key]
  -- Show completed (the appearance menu, per window): off leaves done rows out.
  if not (state and state.showDone) then
    local open = {}
    for _, row in ipairs(rows) do if not row.done then open[#open + 1] = row end end
    rows = open
  end
  -- A custom list keeps its own order (Alt-drag moves the mount in the
  -- list); other windows keep theirs per window.
  if w.source.kind ~= "list" then UI.ApplyOrder(rows, state and state.order) end
  local style = styleOf(w)
  applyChrome(w, style)
  local cards = style.layout ~= "compact"
  local size = style.size or 11
  local rowHeight = cards and math.max(CARD_ROW, size * 2 + 12) or math.max(ROW_HEIGHT, size + 9)
  local groupHeight = cards and math.max(CARD_HEADER, size + 11) or math.max(GROUP_HEIGHT, size + 7)
  local inset = cards and CARD_INSET or 0
  w.rowHeight = rowHeight
  w.layout = style.layout
  local groupSource = w.source
  if w.source.kind == "list" and store and ns.Lists.SortOf(store, w.source.list) == "expansion" then
    groupSource = { kind = "list", list = w.source.list, byExpansion = true }
  end
  local groups = UI.PopoutGroups(rows, groupSource)
  -- w.rows in display order (Plot all, Alt-drag); w.slots: where each open
  -- row sits (the drop slots).
  w.rows, w.slots = {}, {}
  w.Title:SetText(UI.PopoutTitle(w.source, store) .. "  |cff9d9d9d(" .. string.format(L["%d left"], left) .. ")|r")
  local width = math.max(MIN_W, w:GetWidth() or WIDTH) - 24
  local y = 0
  local now = ns.Game.Now()
  local n, usedHeaders, usedCards = 0, 0, 0
  local collapsed = collapsedOf(w)
  w.groupRows = {} -- the headers shown, as rows (a Shift-click's UI.ToggleAllCollapsed)
  for gi, g in ipairs(groups) do
    local gkey = UI.PopoutGroupKey(g)
    local hasHeader = g.exp ~= nil or g.label ~= nil or #groups > 1
    local isCollapsed = hasHeader and collapsed[gkey] == true
    local cardTop = y
    local c = (UI.EXPANSION_COLORS and UI.EXPANSION_COLORS[g.exp]) or nil
    if hasHeader then
      w.groupRows[#w.groupRows + 1] = { header = true, key = gkey, collapsed = isCollapsed }
      usedHeaders = usedHeaders + 1
      local h = groupHeader(w, usedHeaders)
      h:ClearAllPoints()
      h:SetPoint("TOPLEFT", w.Content, "TOPLEFT", inset, -y)
      h:SetWidth(width - inset)
      h:SetHeight(groupHeight)
      h.groupKey = gkey
      h.Text:SetText((isCollapsed and "+ " or "- ") .. (g.label or (g.exp and L[g.exp]) or L["Other"])
        .. "  |cff9d9d9d(" .. string.format(L["%d left"], g.left) .. ")|r")
      -- Cards: the header in the Header colour (gold), the card's edge in the
      -- expansion's; Compact: the header itself in the expansion's.
      local hc = c or { 0.8, 0.8, 0.8 }
      headerText(h.Text, style, UI.Font("GameFontNormalSmall"), cards and 1 or 0, (not cards) and hc or nil)
      if cards then
        h.Rule:SetColorTexture(1, 1, 1, 0.08)
      else
        h.Rule:SetColorTexture(hc[1], hc[2], hc[3], 0.35)
      end
      h:Show()
      y = y + groupHeight + 2
    end
    -- A collapsed group shows its header only.
    for _, row in ipairs(isCollapsed and {} or g.rows) do
      n = n + 1
      w.rows[n] = row
      local r = rowFrame(w, n)
      r.data = row
      r:SetHeight(rowHeight)
      r:ClearAllPoints()
      r:SetPoint("TOPLEFT", w.Content, "TOPLEFT", inset, -y)
      r:SetWidth(width - inset - (cards and 4 or 0))
      r:Show()
      UI.SetExpansionBadge(r.Badge, row.entry and (row.entry.exp or (row.entry.m and row.entry.m.exp)))
      local rarity = not row.done and UI.PopoutRarityColor(row.id) or nil
      -- Colour-blind marks: done rows get a tick, rarity colours their share.
      local marks = UI.ColorblindMarks()
      r.Name:SetText(row.name .. ((marks and row.done) and (" " .. UI.MARK_DONE) or "")
        .. (rarity and UI.RarityTag(row.id) or ""))
      styleText(r.Name, style, row.done and UI.Font("GameFontDisableSmall") or UI.Font("GameFontHighlightSmall"), 0,
        row.done and { 0.5, 0.5, 0.5 } or rarity)
      styleText(r.Zone, style, UI.Font("GameFontDisableSmall"), -1, { 0.55, 0.55, 0.55 })
      local zoneText = row.zone or ""
      if row.camp and row.checked then
        zoneText = string.format(L["checked %s ago"], UI.FormatAgo(now - row.checked))
      end
      r.Zone:SetText(zoneText)
      r.Check:SetChecked(row.done or (row.camp and row.checked ~= nil) or false)
      r.Check:SetEnabled(row.camp and true or false)
      local status, statusKind
      if cards then
        local mountName = ns.Game.MountInfo(row.id) or (row.entry and row.entry.m and row.entry.m.name)
        local subText
        subText, status, statusKind = UI.PopoutCardLines(row, zoneText, mountName)
        r.Sub:SetText(subText)
        styleText(r.Sub, style, UI.Font("GameFontDisableSmall"), -1, { 0.6, 0.6, 0.6 })
        r.Icon:SetTexture(select(2, ns.Game.MountInfo(row.id)) or 134400) -- a question mark when unknown
        r.Icon:SetDesaturated(row.done == true)
        r.Status:SetText(status or "")
        styleText(r.Status, style, UI.Font("GameFontNormalSmall"), -1, STATUS_COLORS[statusKind])
        r.Badge:Hide()
      end
      r.Check:SetShown(not cards or row.camp == true)
      r.Status:SetShown(cards and status ~= nil)
      layoutRow(r, cards, rowHeight - 8, row.camp and 24 or (status and 64 or 4))
      if not row.done then w.slots[#w.slots + 1] = { key = row.key, y = y, group = gi } end
      y = y + rowHeight
    end
    if cards then
      usedCards = usedCards + 1
      placeCard(w, usedCards, cardTop, y + 2, width, style, c or GOLD)
      y = y + 2 + CARD_GAP
    end
  end
  for i = usedCards + 1, #(w.cards or {}) do
    w.cards[i].Fill:Hide()
    w.cards[i].Edge:Hide()
  end
  for i = n + 1, #w.rowFrames do w.rowFrames[i]:Hide() end
  for i = usedHeaders + 1, #w.groupFrames do w.groupFrames[i]:Hide() end
  w.Empty:SetShown(#rows == 0)
  if #rows == 0 then y = 30 end
  w.Content:SetHeight(math.max(y, 1))
  w.contentHeight = y
  -- Fit the rows until the player sizes the window; then keep that size.
  if not w.userSized then w:SetHeight(math.min(MAX_HEIGHT, TITLE_HEIGHT + y + 10)) end
end

-- Redraws every open pop-out (one Checklist build for all).
function UI.RefreshPopouts()
  local any = false
  for _, w in pairs(windows) do
    if w:IsShown() then any = true break end
  end
  if not any then return end
  local built = UI.ChecklistBuild(ns.Game.Now())
  for _, w in pairs(windows) do refreshWindow(w, built) end
end

local function openCount()
  local n = 0
  for _, w in pairs(windows) do if w:IsShown() then n = n + 1 end end
  return n
end

local function startTicker()
  if ticker or not (type(C_Timer) == "table" and type(C_Timer.NewTicker) == "function") then return end
  ticker = C_Timer.NewTicker(AGE_TICK, function() UI.RefreshPopouts() end)
end

local function stopTickerIfIdle()
  if openCount() == 0 and ticker then
    if ticker.Cancel then ticker:Cancel() end
    ticker = nil
  end
end

local function build(key, source)
  local w = CreateFrame("Frame", nil, UIParent)
  w.key, w.source = key, source
  w.rowFrames, w.groupFrames = {}, {}
  w:SetSize(WIDTH, 120)
  w:SetFrameStrata("MEDIUM")
  w:SetMovable(true)
  w:SetClampedToScreen(true)
  w:EnableMouse(true)
  w:Hide()
  local db = popoutsDB()
  local state = db and db[key]
  if state and state.width and state.height then
    w:SetSize(math.max(MIN_W, state.width), math.max(MIN_H, state.height))
    w.userSized = true
  end
  w:ClearAllPoints()
  if state and state.point then
    w:SetPoint(state.point, UIParent, state.relPoint or state.point, state.x or 0, state.y or 0)
  else
    local n = openCount()
    w:SetPoint("RIGHT", UIParent, "RIGHT", -60 - n * CASCADE, 60 - n * CASCADE)
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
  strip:SetScript("OnDragStart", function()
    -- The windows snapped under / beside this one come along, pinned to it.
    w.followers = {}
    local lead = rectOf(w)
    if lead then
      local rects = { [key] = lead }
      for k, o in pairs(windows) do
        if o ~= w and o:IsShown() then rects[k] = rectOf(o) end
      end
      for _, k in ipairs(UI.SnapChain(key, rects)) do
        local o, r = windows[k], rects[k]
        local f = { w = o, dx = r.left - lead.left, dy = r.top - lead.top }
        o:ClearAllPoints()
        o:SetPoint("TOPLEFT", w, "TOPLEFT", f.dx, f.dy)
        w.followers[#w.followers + 1] = f
      end
    end
    w:StartMoving()
  end)
  strip:SetScript("OnDragStop", function()
    w:StopMovingOrSizing()
    if w.SetUserPlaced then w:SetUserPlaced(false) end
    local followers = w.followers or {}
    w.followers = nil
    local moving = { [w] = true }
    for _, f in ipairs(followers) do moving[f.w] = true end
    -- Snap to another open pop-out (not one moving with it) or the main window.
    local mine = rectOf(w)
    local left, top = mine and mine.left, mine and mine.top
    if mine then
      local sl, st = UI.SnapRect(mine, UI.PopoutSnapTargets(moving))
      if sl then left, top = sl, st end
      w:ClearAllPoints()
      w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    end
    savePosition(w)
    for _, f in ipairs(followers) do
      if left then
        f.w:ClearAllPoints()
        f.w:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left + f.dx, top + f.dy)
      end
      savePosition(f.w)
    end
  end)
  strip:SetScript("OnMouseUp", function(self, button)
    if button == "RightButton" then UI.ShowPopoutStyleMenu(w, self) end
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

  -- Close: a flat x in the title strip.
  local close = UI.FlatButton(strip, "x", "plain", 18)
  close:SetWidth(18)
  close:SetPoint("RIGHT", strip, "RIGHT", -4, 0)
  close:SetScript("OnClick", function()
    if type(IsControlKeyDown) == "function" and IsControlKeyDown() then
      UI.CloseAllPopouts()
    else
      UI.ClosePopout(key)
    end
  end)
  close:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Close"], L["Ctrl-click: close every pop-out"]) end)
  close:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  w.Close = close

  -- Plot all: every open row's spawn points on TomTom (Map.PlotMounts).
  local plot = UI.FlatButton(strip, L["Plot all"], "green", 16)
  plot:SetPoint("RIGHT", close, "LEFT", -4, 0)
  plot:SetScript("OnClick", function()
    if ns.Map and ns.Map.PlotMounts then
      ns.Map.PlotMounts(UI.PopoutPlotIDs(w.rows), UI.PopoutTitle(w.source, listsDB()))
    end
  end)
  plot:SetScript("OnEnter", function(self) UI.ShowHint(self, L["Plot every unticked row on TomTom"]) end)
  plot:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  w.PlotAll = plot

  local titleText = strip:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
  titleText:SetPoint("LEFT", strip, "LEFT", 8, 0)
  titleText:SetPoint("RIGHT", plot, "LEFT", -4, 0)
  titleText:SetJustifyH("LEFT")
  titleText:SetWordWrap(false)
  w.Title = titleText

  local scroll = CreateFrame("ScrollFrame", nil, w)
  scroll:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 6, -4)
  scroll:SetPoint("BOTTOMRIGHT", w, "BOTTOMRIGHT", -6, 6)
  if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(WIDTH - 12, 1)

  -- Resize grip: any size; right-click fits the rows again.
  UI.SetResizeLimits(w, MIN_W, MIN_H)
  w.Grip = UI.ResizeGrip(w, function(gw, gh)
    w.userSized = true
    local st = popoutsDB()
    if st then
      st[key] = st[key] or {}
      st[key].width, st[key].height = math.floor(gw + 0.5), math.floor(gh + 0.5)
    end
    savePosition(w)
    layoutWidth(w)
  end, function()
    w.userSized = nil
    w:SetWidth(WIDTH)
    local st = popoutsDB()
    if st and st[key] then st[key].width, st[key].height = nil, nil end
    layoutWidth(w)
    UI.RefreshPopouts()
  end, L["Right-click: fit to its rows"])
  w:SetScript("OnSizeChanged", function() layoutWidth(w) end)
  scroll:SetScrollChild(content)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, (w.contentHeight or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * 30)))
  end)
  w.Scroll, w.Content = scroll, content
  -- Where an Alt-dragged row lands.
  local dropLine = content:CreateTexture(nil, "OVERLAY")
  dropLine:SetHeight(2)
  dropLine:SetColorTexture(1, 0.82, 0, 0.9)
  dropLine:Hide()
  w.DropLine = dropLine

  local empty = content:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  empty:SetPoint("TOPLEFT", content, "TOPLEFT", 4, -6)
  empty:SetText(source.kind == "list" and L["Nothing on this list yet."] or L["Nothing left here."])
  empty:Hide()
  w.Empty = empty
  windows[key] = w
  return w
end


-- A custom list window's own items for its title menu (UI.PopoutStyleMenu):
-- its sort, in the order added or by expansion (Lists.SetSort; the list
-- page follows). {} for other windows.
function UI.PopoutMenuExtra(w)
  local store = listsDB()
  if not (w and w.source and w.source.kind == "list" and store and ns.Lists.Get(store, w.source.list)) then return {} end
  local sort = ns.Lists.SortOf(store, w.source.list)
  local function choose(value)
    return function()
      ns.Lists.SetSort(store, w.source.list, value)
      ns.Refresh()
    end
  end
  return {
    { text = L["Sort: order added"], checked = sort == "added", keepOpen = true, onClick = choose("added") },
    { text = L["Sort: by expansion"], checked = sort == "expansion", keepOpen = true, onClick = choose("expansion") },
    { separator = true },
  }
end

-- Opens (or brings back) the pop-out of `source` -> its window.
function UI.OpenPopout(source)
  local key = UI.PopoutKey(source)
  if not key then return nil end
  local w = windows[key] or build(key, source)
  w.source = source
  local db = popoutsDB()
  if db then
    local state = db[key] or {}
    state.open, state.source = true, source
    db[key] = state
  end
  w:Show()
  if w.Raise then w:Raise() end
  startTicker()
  refreshWindow(w, UI.ChecklistBuild(ns.Game.Now()))
  return w
end

function UI.ClosePopout(key)
  local w = windows[key]
  if w then w:Hide() end
  local db = popoutsDB()
  if db and db[key] then db[key].open = false end
  stopTickerIfIdle()
end

-- Closes every open pop-out and extra window (Ctrl-click on any one's x).
function UI.CloseAllPopouts()
  for key, w in pairs(windows) do
    if w:IsShown() then UI.ClosePopout(key) end
  end
  for _, x in ipairs(UI.StyledWindows()) do
    if x:IsShown() and x.CloseWindow then x.CloseWindow() end
  end
end

-- /mtrail here (and the zone panel title's right-click): the mounts of the
-- player's zone, opened or closed.
function UI.ToggleZoneMountsPopout()
  local w = windows.zonemounts
  if w and w:IsShown() then
    UI.ClosePopout("zonemounts")
    return false
  end
  UI.OpenPopout({ kind = "zonemounts" })
  return true
end

-- /mtrail rares: the zone's rares, opened or closed.
function UI.ToggleZonePopout()
  local w = windows.zone
  if w and w:IsShown() then
    UI.ClosePopout("zone")
    return false
  end
  UI.OpenPopout({ kind = "zone" })
  return true
end

UI.PopoutWindows = windows

UI.AddRefreshHook(function() UI.RefreshPopouts() end)

-- Back on screen after /reload when they were open; the zone's window
-- follows the player: the zone panel's events (a new zone, a sub-zone or
-- cave map, a loading screen), redrawn only when the player's map changed.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
for _, event in ipairs({ "ZONE_CHANGED_NEW_AREA", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS",
  "PLAYER_ENTERING_WORLD" }) do
  events:RegisterEvent(event)
end
events:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    local db = popoutsDB()
    for _, state in pairs(db or {}) do
      if type(state) == "table" and state.open and type(state.source) == "table" then
        UI.OpenPopout(state.source)
      end
    end
  else
    local map = ns.Game.PlayerMap()
    for _, key in ipairs({ "zone", "zonemounts" }) do
      local w = windows[key]
      if w and w:IsShown() and map ~= w.map then
        UI.RefreshPopouts()
        return
      end
    end
  end
end)
