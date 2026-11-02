local ADDON, ns = ...

-- The navigation column on the main window's left: its fixed entries, the
-- Browse section and the lists, favourites, the player's order (Alt-drag),
-- collapsible headings and badges. UI/Frame.lua builds the window and calls
-- UI.CreateNav; the views it selects are UI/Frame.lua's (UI.SelectTab).

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

-- Entries ----------------------------------------------------------------------

-- The navigation column's fixed entries, top to bottom: views (key), an
-- action (Alts: its own window), section headings. Badges come from
-- UI.NavBadge. The lists follow under "Lists" (UI.NavListEntries): the
-- built-in ones first, then the player's own.
UI.NAV = {
  { key = "journal", label = "Home" },
  { key = "checklist", label = "Lockouts" },
  { key = "here", label = "Current Zone" },
  { action = "alts", label = "Alts" },
}

-- The Browse section's entries (Logic/Browse.lua, by source): a category
-- with its own view is that view's entry (key = the view), the others open
-- a browse page (key "browse:<category>").
function UI.NavBrowseEntries(categories)
  local out = {}
  for _, c in ipairs(categories or {}) do
    if c.view then
      out[#out + 1] = { key = c.view, label = c.label }
    else
      out[#out + 1] = { key = "browse:" .. c.key, label = c.label, category = c.key }
    end
  end
  return out
end
UI.NAV_WIDTH = 176
-- The collapse keys of the My lists and Quick lists sections.
UI.NAV_LISTS_KEY = "nav|lists"
UI.NAV_BROWSE_KEY = "nav|browse"
-- A list entry's favourite star (the Auction House's: filled / hollow). A
-- favourite (ns.db.global.navFavorites[entry key]) is pinned to the top of
-- its section.
UI.STAR_ON, UI.STAR_OFF = "auctionhouse-icon-favorite", "auctionhouse-icon-favorite-off"

local function favorites()
  local global = ns.db and ns.db.global
  if not global then return {} end
  if type(global.navFavorites) ~= "table" then global.navFavorites = {} end
  return global.navFavorites
end

function UI.IsNavFavorite(key)
  return favorites()[key] == true
end

function UI.ToggleNavFavorite(key)
  local store = favorites()
  store[key] = (not store[key]) or nil
  if UI.RefreshNav then UI.RefreshNav() end
end

-- The player's order of each section (ns.db.global.navOrder[section] =
-- { entry keys }): "lists", "quick", "browse".
local function navOrders()
  local global = ns.db and ns.db.global
  if not global then return {} end
  if type(global.navOrder) ~= "table" then global.navOrder = {} end
  return global.navOrder
end

-- `entries` in the saved `order` (keys it names first, in that order; the
-- rest after in their own order, e.g. a new list at the end).
function UI.ApplyNavOrder(entries, order)
  if type(order) ~= "table" or #order == 0 then return entries end
  local rank = {}
  for i, key in ipairs(order) do rank[key] = i end
  local named, rest = {}, {}
  for _, e in ipairs(entries) do
    if rank[e.key] then named[#named + 1] = e else rest[#rest + 1] = e end
  end
  table.sort(named, function(a, b) return rank[a.key] < rank[b.key] end)
  for _, e in ipairs(rest) do named[#named + 1] = e end
  return named
end

local shownSections = {} -- section -> its entries' keys as last shown (the moves' baseline)

-- `keys` with `key` moved to position `to` (1..#keys), held inside its own
-- part (the favourites, or the rest; isFavorite nil: anywhere) -> the new
-- keys, or nil when nothing changes.
function UI.NavMoveTo(keys, key, to, isFavorite)
  local from
  for i, k in ipairs(keys) do if k == key then from = i end end
  if not from then return nil end
  local lo, hi = 1, #keys
  if isFavorite then
    local mine = isFavorite(key) == true
    lo, hi = nil, nil
    for i, k in ipairs(keys) do
      if (isFavorite(k) == true) == mine then
        lo = lo or i
        hi = i
      end
    end
  end
  to = math.max(lo, math.min(hi, to))
  if to == from then return nil end
  local out = {}
  for _, k in ipairs(keys) do if k ~= key then out[#out + 1] = k end end
  table.insert(out, to, key)
  return out
end

-- Where a dragged entry lands among a section's rows (`rects` = { { top =,
-- bottom = } } top to bottom, screen coordinates) for the cursor at `y`: the
-- first row whose middle is below the cursor, else the last -> index.
function UI.NavDropIndex(rects, y)
  for i, r in ipairs(rects) do
    if y > (r.top + r.bottom) / 2 then return i end
  end
  return #rects
end

-- Whether a part of Lists is shown (Options: "Show your lists" / "Show
-- built-in lists"): "lists" the player's own, "quick" the built-in ones.
function UI.NavSectionShown(section)
  local global = ns.db and ns.db.global
  local saved = global and type(global.settings) == "table" and global.settings or {}
  if section == "lists" then return saved.navHideLists ~= true end
  if section == "quick" then return saved.navHideQuick ~= true end
  return true
end

-- `entries` with the favourites first (each part keeps its order).
function UI.FavoritesFirst(entries, isFavorite)
  local fav, rest = {}, {}
  for _, e in ipairs(entries) do
    if isFavorite(e.key) then fav[#fav + 1] = e else rest[#rest + 1] = e end
  end
  for _, e in ipairs(rest) do fav[#fav + 1] = e end
  return fav
end

-- Navigation column -----------------------------------------------------------------

-- The navigation column's width (saved; UI.NAV_WIDTH by default).
function UI.NavWidth()
  local db = UI.WindowDB()
  return UI.ClampWidth(db and db.navWidth, UI.NAV_MIN, UI.NAV_MAX, UI.NAV_WIDTH)
end

local NAV_ROW, NAV_HEADING = 24, 26
-- Points added to the navigation's fonts (the game's small fonts read tiny
-- at high resolutions with a small UI scale): Options' "Navigation text
-- size" (default 2).
UI.NAV_FONT_BONUS = 2

function UI.NavFontBonus()
  local options = ns.Options
  if options and options.NavTextSize then return options.NavTextSize() end
  return UI.NAV_FONT_BONUS
end

-- `fs` in game font `name` (its colour), the game's own size plus the
-- "Left column" setting (UI.NavFontBonus) only: the column follows that
-- slider alone, not the Headers / Mount names ones (UI.Font's copies). The
-- size comes from the game font itself, never from `fs`: a font string keeps
-- a size set with SetFont through SetFontObject, so reading it back would
-- grow the text on every repaint.
local function navFont(fs, name)
  fs:SetFontObject(name)
  local fo = _G[name]
  if not (fs.SetFont and type(fo) == "table" and type(fo.GetFont) == "function") then return end
  local path, size, flags = fo:GetFont()
  if path and size then fs:SetFont(path, size + UI.NavFontBonus(), flags or "") end
end
local NAV_GOLD = { 1, 0.82, 0 }

-- The main window's header colour (its appearance, UI/Style.lua), else gold:
-- the section headings and their rules, as a pop-out's group headers.
local function headerColor()
  local style = UI.frame and UI.PopoutStyleOf and UI.PopoutStyleOf(UI.frame)
  return style and style.header or NAV_GOLD
end

-- The entries under "Lists": each custom list ({ list = id }), then each
-- quick list ({ quick = key, builtIn = true }) -> { { key = "list:<id>" |
-- "quick:<key>", label =, source = (UI.OpenPopout / UI.ShowListPage source),
-- builtIn = } }.
-- The lockout groups among the quick lists: each opens Lockouts on that
-- group (ns.db.char.checklistShow) and pops out as the whole group.
UI.NAV_LOCKOUT_GROUPS = {
  { show = "daily", label = "Daily lockouts" },
  { show = "weekly", label = "Weekly lockouts" },
  { show = "camp", label = "Rare Spawns" },
}

function UI.NavListEntries(store, quick)
  local out = {}
  for _, l in ipairs(store and ns.Lists.Sorted(store) or {}) do
    out[#out + 1] = { key = "list:" .. tostring(l.id), label = l.name, source = { kind = "list", list = l.id } }
  end
  for _, g in ipairs(UI.NAV_LOCKOUT_GROUPS) do
    out[#out + 1] = { key = "lockouts:" .. g.show, label = L[g.label], show = g.show,
      source = { kind = g.show, all = true }, builtIn = true }
  end
  for _, q in ipairs(quick or {}) do
    out[#out + 1] = { key = "quick:" .. tostring(q.key), label = L[q.name],
      source = { kind = "quick", key = q.key }, builtIn = true }
  end
  return out
end

-- The entry that shows as selected: the list page's list when the journal
-- view shows one (UI.CurrentListPage), the browse page's category, else the
-- view's key.
function UI.NavSelected(view, listSource, browseCategory, checklistShow)
  if view == "browse" and browseCategory then return "browse:" .. tostring(browseCategory) end
  if view == "checklist" and (checklistShow == "daily" or checklistShow == "weekly" or checklistShow == "camp") then
    return "lockouts:" .. checklistShow
  end
  if view == "journal" and listSource then
    if listSource.kind == "quick" then return "quick:" .. tostring(listSource.key) end
    return "list:" .. tostring(listSource.list)
  end
  return view
end

-- A badge for an entry (right-aligned, grey or green), as the pop-outs
-- count: Lockouts or one of its groups -> "<n> left", a list -> its
-- lockouts open today, "<n> left" (green). (Here has none:
-- working out the zone's mounts on every refresh costs too much.) nil: none. Errors are swallowed (nil).
-- built() -> the Checklist.Build output to count from (one per repaint).
function UI.NavBadge(entry, built)
  local good, text, green = pcall(function()
    if entry.key == "checklist" and built then
      local char = ns.db and ns.db.char
      local filters = char and type(char.checklistFilters) == "table" and char.checklistFilters or nil
      local n = ns.Checklist.Remaining(built(), filters)
      return n > 0 and string.format(L["%d left"], n) or nil
    end
    if entry.show and built and UI.ChecklistLeft then
      local char = ns.db and ns.db.char
      local filters = char and type(char.checklistFilters) == "table" and char.checklistFilters or nil
      local n = UI.ChecklistLeft(built(), filters)[entry.show] or 0
      return n > 0 and string.format(L["%d left"], n) or nil
    end
    if entry.source and UI.ListCardStatsFor and built then
      local stats = UI.ListCardStatsFor(entry.source, built())
      if stats and stats.open > 0 then
        -- Green says "open today"; the colour-blind marks say it in words.
        local fmt = (UI.ColorblindMarks and UI.ColorblindMarks()) and L["%d open"] or L["%d left"]
        return string.format(fmt, stats.open), true
      end
    end
    return nil
  end)
  if good then return text, green end
  return nil
end

local nav

local function navButton(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(NAV_ROW)
  b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  -- The entry you are on: a gold-tinted band (its name turns gold too).
  local sel = b:CreateTexture(nil, "BACKGROUND")
  sel:SetAllPoints(b)
  sel:SetColorTexture(1, 0.82, 0, 0.12)
  sel:Hide()
  b.Selected = sel
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(b)
  hl:SetColorTexture(1, 1, 1, 0.06)
  -- A list's favourite star (right edge), the badge left of it.
  local star = CreateFrame("Button", nil, b)
  star:SetSize(14, 14)
  star:SetPoint("RIGHT", b, "RIGHT", -6, 0)
  local starIcon = star:CreateTexture(nil, "ARTWORK")
  starIcon:SetAllPoints(star)
  star.Icon = starIcon
  star:SetScript("OnClick", function(self)
    local e = self:GetParent().entry
    if e then UI.ToggleNavFavorite(e.key) end
  end)
  star:SetScript("OnEnter", function(self)
    local e = self:GetParent().entry
    UI.ShowHint(self, e and UI.IsNavFavorite(e.key) and L["Unpin from the top"] or L["Favourite: pin to the top"])
  end)
  star:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  b.Star = star
  local badge = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  badge:SetPoint("RIGHT", b, "RIGHT", -8, 0)
  b.Badge = badge
  -- The count sits on a small dark box, shown while it has text.
  local box = b:CreateTexture(nil, "BORDER")
  box:SetPoint("TOPLEFT", badge, "TOPLEFT", -5, 3)
  box:SetPoint("BOTTOMRIGHT", badge, "BOTTOMRIGHT", 5, -3)
  box:SetColorTexture(1, 1, 1, 0.07)
  box:Hide()
  b.BadgeBox = box
  local text = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlight"))
  text:SetPoint("LEFT", b, "LEFT", 12, 0)
  text:SetPoint("RIGHT", badge, "LEFT", -4, 0)
  text:SetJustifyH("LEFT")
  text:SetWordWrap(false)
  b.Text = text
  b:SetScript("OnClick", function(self, button)
    local e = self.entry
    if not e then return end
    if button == "RightButton" then
      if e.key == "here" then
        if UI.ToggleZoneMountsPopout then UI.ToggleZoneMountsPopout() end
        return
      end
      -- Right-click pops a list out; Shift-right-click: a custom list's
      -- rename / delete menu.
      local shift = type(IsShiftKeyDown) == "function" and IsShiftKeyDown()
      if shift and e.source and e.source.kind == "list" and UI.ShowCustomListMenu then
        UI.ShowCustomListMenu(e.source.list, self)
      elseif e.source and UI.OpenPopout then
        UI.OpenPopout(e.source)
      end
      return
    end
    if self.justDragged then
      self.justDragged = nil
      return
    end
    if PlaySound and SOUNDKIT and SOUNDKIT.IG_CHARACTER_INFO_TAB then PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB) end
    UI.NavClick(e)
  end)
  -- Alt-drag: reorder the entry's section (a gold line shows where it lands).
  -- A new press clears the drag's click guard (the drop may not click).
  b:SetScript("OnMouseDown", function(self) if not self.dragging then self.justDragged = nil end end)
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnDragStart", function(self)
    local e = self.entry
    if not (e and e.section and type(IsAltKeyDown) == "function" and IsAltKeyDown()) then return end
    UI.NavDragStart(self)
  end)
  b:SetScript("OnDragStop", function(self) UI.NavDragStop(self) end)
  b:SetScript("OnEnter", function(self)
    local e = self.entry
    local reorder = e and e.section and ("\n" .. L["Alt-drag to reorder."]) or ""
    if e and e.source then
      UI.ShowHint(self, e.label, (e.source.kind == "list" and L["Click: open. Right-click: pop out. Shift-right-click: share, rename or delete"]
        or L["Click: open. Right-click: pop out"]) .. reorder)
    elseif e and e.section then
      UI.ShowHint(self, L[e.label] or e.label, L["Alt-drag to reorder."])
    elseif e and e.action == "alts" then
      UI.ShowHint(self, L["Alt lockouts"], L["Opens its own window"])
    elseif e and e.key == "here" then
      UI.ShowHint(self, L["Current Zone"], L["Every mount you can still get in the zone you are in. Right-click to pop it out: a small window that follows you."])
    elseif e and e.key == "checklist" then
      UI.ShowHint(self, L["Lockouts"], L["Your daily and weekly mount lockouts and rare spawns on this character."])
    end
  end)
  b:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  return b
end

-- Alt-drag ------------------------------------------------------------------------

local sectionButtons = {} -- section -> its rows (buttons) as last shown

local function dragTarget(b)
  local e = b.entry
  local rows = e and sectionButtons[e.section] or {}
  local rects = {}
  for i, r in ipairs(rows) do
    local top, bottom = r:GetTop(), r:GetBottom()
    if not (top and bottom) then return nil, rows end
    rects[i] = { top = top, bottom = bottom }
  end
  if type(GetCursorPosition) ~= "function" then return nil, rows end
  local _, y = GetCursorPosition()
  local scale = b.GetEffectiveScale and b:GetEffectiveScale() or 1
  if type(y) ~= "number" or #rects == 0 then return nil, rows end
  return UI.NavDropIndex(rects, y / scale), rows
end

-- Starts an Alt-drag of nav button `b`: the drop line follows the cursor.
function UI.NavDragStart(b)
  b.dragging = true
  local line = nav and nav.DropLine
  b:SetScript("OnUpdate", function(self)
    local i, rows = dragTarget(self)
    if not (line and i and rows[i]) then return end
    line:ClearAllPoints()
    local above = rows[i]
    line:SetPoint("BOTTOMLEFT", above, "TOPLEFT", 4, -1)
    line:SetPoint("BOTTOMRIGHT", above, "TOPRIGHT", -4, -1)
    line:Show()
  end)
end

-- Ends an Alt-drag: the entry moves where the line was (inside its part:
-- favourites stay above the rest) and the section's order is saved.
function UI.NavDragStop(b)
  if not b.dragging then return end
  b.dragging = nil
  b.justDragged = true
  b:SetScript("OnUpdate", nil)
  if nav and nav.DropLine then nav.DropLine:Hide() end
  local e = b.entry
  local i = dragTarget(b)
  if not (e and i) then return end
  local fav = e.section ~= "browse" and UI.IsNavFavorite or nil
  local moved = UI.NavMoveTo(shownSections[e.section] or {}, e.key, i, fav)
  if moved then
    navOrders()[e.section] = moved
    UI.RefreshNav()
  end
end

-- An entry's click: a view (Home also leaves a list or expansion page), the
-- Alts window, or a list's page.
function UI.NavClick(e)
  if e.action == "alts" then
    if UI.ToggleAltsWindow then UI.ToggleAltsWindow() end
    return
  end
  if e.category then
    if UI.ShowBrowse then UI.ShowBrowse(e.category) end
    return
  end
  -- Lockouts (all) or one of its groups (the quick lists' Daily / Weekly /
  -- Rare Spawns).
  if e.show or e.key == "checklist" then
    local char = ns.db and ns.db.char
    if char then char.checklistShow = e.show or "all" end
    if UI.CurrentTab() == "checklist" then
      ns.Refresh()
    else
      UI.SelectTab("checklist")
    end
    return
  end
  if e.source then
    UI.SelectTab("journal")
    if UI.ShowListPage then UI.ShowListPage(e.source) end
    if UI.RefreshNav then UI.RefreshNav() end
    return
  end
  if e.key == "journal" and UI.CurrentTab() == "journal" and UI.ShowJournalHome then UI.ShowJournalHome() end
  UI.SelectTab(e.key)
end

-- The navigation's collapsed sections ({ ["nav|lists"] = true, ... }), kept
-- with the lists' collapsed headers (ns.db.global.collapsed).
local function navCollapsed()
  local global = ns.db and ns.db.global
  if not global then return {} end
  if type(global.collapsed) ~= "table" then global.collapsed = {} end
  return global.collapsed
end

-- A section heading, as a pop-out's group header: "- Browse" in the header
-- colour over a thin rule of it; a collapsible one (`key`) flips on click
-- ("+" while collapsed).
local function navHeading(parent)
  local h = CreateFrame("Button", nil, parent)
  h:SetHeight(NAV_HEADING)
  local text = h:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalSmall"))
  text:SetJustifyH("LEFT")
  text:SetPoint("LEFT", h, "LEFT", 10, 0)
  h.Text = text
  local rule = h:CreateTexture(nil, "ARTWORK")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 8, 2)
  rule:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", -8, 2)
  h.Rule = rule
  h:SetScript("OnClick", function(self)
    if not self.key then return end
    local store = navCollapsed()
    store[self.key] = (not store[self.key]) or nil
    UI.RefreshNav()
  end)
  h:SetScript("OnEnter", function(self)
    if self.key then UI.ShowHint(self, L["Click: collapse or expand"]) end
  end)
  h:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  return h
end

-- Paints heading `h`: its text in the header colour (a collapsible one,
-- `key`, after its "- " / "+ "), and its rule.
local function paintHeading(h, text, key)
  h.key = key
  local collapsed = key ~= nil and navCollapsed()[key] == true
  h.collapsed = key ~= nil and collapsed or nil
  navFont(h.Text, "GameFontNormalSmall")
  local c = headerColor()
  h.Text:SetTextColor(c[1], c[2], c[3])
  -- Section labels in capitals, as the design's small gold caps.
  text = string.upper(text)
  h.Text:SetText(key and ((collapsed and "+ " or "- ") .. text) or text)
  h.Rule:SetColorTexture(c[1], c[2], c[3], 0.35)
  h:EnableMouse(key ~= nil)
end

-- Builds the column on the window's left, under the title strip (UI/Frame.lua's
-- window calls it once) -> the column.
function UI.CreateNav(frame)
  local n = CreateFrame("Frame", nil, frame)
  n:SetPoint("TOPLEFT", frame, "TOPLEFT", 6, UI.VIEW_TOP) -- under the title strip
  n:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 6, 6)
  n:SetWidth(UI.NavWidth())
  -- A faint shade and a 1 px line on its right edge set it off from the views.
  local fill = n:CreateTexture(nil, "BACKGROUND")
  fill:SetAllPoints(n)
  fill:SetColorTexture(1, 1, 1, 0.02)
  n.Fill = fill
  local edge = n:CreateTexture(nil, "BORDER")
  edge:SetWidth(1)
  edge:SetPoint("TOPRIGHT", n, "TOPRIGHT", 0, 0)
  edge:SetPoint("BOTTOMRIGHT", n, "BOTTOMRIGHT", 0, 0)
  edge:SetColorTexture(1, 1, 1, 0.08)
  n.Edge = edge

  local scroll = CreateFrame("ScrollFrame", nil, n)
  scroll:SetPoint("TOPLEFT", n, "TOPLEFT", 1, -4)
  scroll:SetPoint("BOTTOMRIGHT", n, "BOTTOMRIGHT", -1, 4)
  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(UI.NavWidth() - 2, 1)
  scroll:SetScrollChild(content)
  if scroll.EnableMouseWheel then scroll:EnableMouseWheel(true) end
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, (n.contentHeight or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * 30)))
  end)
  n.Scroll, n.Content = scroll, content
  n.Buttons, n.Headings = {}, {}
  -- Where an Alt-dragged entry lands.
  local dropLine = content:CreateTexture(nil, "OVERLAY")
  dropLine:SetHeight(2)
  dropLine:SetColorTexture(1, 0.82, 0, 0.9)
  dropLine:Hide()
  n.DropLine = dropLine

  local add = UI.FlatButton(content, "+", "gold", 16)
  add:SetWidth(20)
  add:SetScript("OnClick", function(self)
    UI.ShowMenu(self, {
      { title = L["My lists"] },
      { text = L["New list..."], onClick = function() if UI.NewListPrompt then UI.NewListPrompt() end end },
      { text = L["Import list..."], onClick = function() if UI.ImportListPrompt then UI.ImportListPrompt() end end },
    }, "cursor")
  end)
  add:SetScript("OnEnter", function(self)
    UI.ShowHint(self, L["New or imported list"], L["Or + List on any mount to start one with it"])
  end)
  add:SetScript("OnLeave", function(self) UI.HideHint(self) end)
  n.AddList = add

  local empty = content:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  empty:SetJustifyH("LEFT")
  empty:SetWidth(UI.NavWidth() - 24)
  empty:SetText(L["No lists yet: + here, or + List on any mount."])
  n.Empty = empty
  nav = n
  return n
end

-- Sets the navigation column's width (clamped) and moves the views beside
-- it; `save`: keep it (ns.db.global.window.navWidth).
function UI.SetNavWidth(w, save)
  w = UI.ClampWidth(w, UI.NAV_MIN, UI.NAV_MAX, UI.NAV_WIDTH)
  local frame = UI.frame
  if not (frame and nav) then return w end
  nav:SetWidth(w)
  nav.Content:SetWidth(w - 2)
  nav.Empty:SetWidth(w - 24)
  if frame.Inset then frame.Inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 6 + w + 4, UI.VIEW_TOP) end
  if save then
    local db = UI.WindowDB()
    if db then db.navWidth = w end
  end
  return w
end

-- Repaints the column: the fixed entries, then My lists (and the quick
-- lists), each with its badge; the selected entry is gold on a faint band.
function UI.RefreshNav()
  if not nav then return end
  local listPage = UI.CurrentListPage and UI.CurrentListPage() or nil
  local char = ns.db and ns.db.char
  local selected = UI.NavSelected(UI.CurrentTab(), listPage, UI.BrowseCategory and UI.BrowseCategory() or nil,
    char and char.checklistShow)
  local cache
  local function built()
    cache = cache or (UI.ChecklistBuild and UI.ChecklistBuild(ns.Game.Now())) or {}
    return cache
  end
  local y, nb, nh = 0, 0, 0
  for k in pairs(sectionButtons) do sectionButtons[k] = nil end
  -- -> whether the section is collapsed (only for a collapsible `key`).
  -- withAdd: true for Lists' +, or the + button to place.
  local function heading(text, withAdd, key)
    nh = nh + 1
    local h = nav.Headings[nh] or navHeading(nav.Content)
    nav.Headings[nh] = h
    paintHeading(h, text, key)
    h:ClearAllPoints()
    h:SetPoint("TOPLEFT", nav.Content, "TOPLEFT", 0, -y)
    h:SetPoint("RIGHT", nav.Content, "RIGHT", withAdd and -30 or 0, 0)
    h:Show()
    if withAdd then
      local add = withAdd == true and nav.AddList or withAdd
      add:ClearAllPoints()
      add:SetPoint("TOPRIGHT", nav.Content, "TOPRIGHT", -6, -(y + 4))
      add:Show()
    end
    y = y + NAV_HEADING
    return key ~= nil and navCollapsed()[key] == true
  end
  local function entry(e, indent)
    nb = nb + 1
    local b = nav.Buttons[nb] or navButton(nav.Content)
    nav.Buttons[nb] = b
    b.entry = e
    b:ClearAllPoints()
    b:SetPoint("TOPLEFT", nav.Content, "TOPLEFT", 0, -y)
    b:SetPoint("RIGHT", nav.Content, "RIGHT", 0, 0)
    b.Text:SetPoint("LEFT", b, "LEFT", indent and 18 or 12, 0)
    local label = L[e.label] or e.label
    -- A quick list: the game's favourite star (the font has no star glyph).
    -- A list: its favourite star (filled when pinned), the badge beside it.
    local isList = e.source ~= nil
    b.Star:SetShown(isList)
    b.Badge:ClearAllPoints()
    if isList then
      b.Star.favorite = UI.IsNavFavorite(e.key)
      b.Star.Icon:SetAtlas(b.Star.favorite and UI.STAR_ON or UI.STAR_OFF)
      b.Star.Icon:SetAlpha(b.Star.favorite and 1 or 0.5)
      -- Clear of the star: the count's box reaches 5 px past its text.
      b.Badge:SetPoint("RIGHT", b.Star, "LEFT", -12, 0)
    else
      b.Badge:SetPoint("RIGHT", b, "RIGHT", -8, 0)
    end
    b.Text:SetText(label)
    b.Text:SetPoint("RIGHT", b.Badge, "LEFT", -10, 0) -- clear of the count's box
    local badge, green = UI.NavBadge(e, built)
    b.Badge:SetText(badge and ((green and "|cff40c040" or "") .. badge .. (green and "|r" or "")) or "")
    b.BadgeBox:SetShown(badge ~= nil and badge ~= "")
    local on = (e.key ~= nil and e.key == selected)
    b.Selected:SetShown(on)
    navFont(b.Text, on and "GameFontNormal" or "GameFontHighlight")
    navFont(b.Badge, "GameFontDisableSmall")
    b.selected = on
    if e.section then
      sectionButtons[e.section] = sectionButtons[e.section] or {}
      local list = sectionButtons[e.section]
      list[#list + 1] = b
    end
    -- Taller with the "Left column" size only.
    local rowH = NAV_ROW + math.max(0, UI.NavFontBonus() - 2)
    b:SetHeight(rowH)
    b:Show()
    y = y + rowH
  end
  for _, e in ipairs(UI.NAV) do entry(e, false) end
  y = y + 4
  local browse = UI.ApplyNavOrder(UI.NavBrowseEntries(ns.Browse and ns.Browse.CATEGORIES), navOrders().browse)
  local function record(section, list)
    local keys = {}
    for i, e in ipairs(list) do
      keys[i] = e.key
      e.section = section
    end
    shownSections[section] = keys
  end
  record("browse", browse)
  if not heading(L["Browse"], false, UI.NAV_BROWSE_KEY) then
    for _, e in ipairs(browse) do entry(e, true) end
  end
  -- Lists (with +), one collapsible section: the built-in lists first (each
  -- always first), then the player's own.
  y = y + 4
  local store = UI.ListsDB and UI.ListsDB()
  local lists = UI.NavListEntries(store, ns.QuickLists and ns.QuickLists.LISTS)
  local mine, quick = {}, {}
  for _, e in ipairs(lists) do
    if e.builtIn then quick[#quick + 1] = e else mine[#mine + 1] = e end
  end
  mine = UI.FavoritesFirst(UI.ApplyNavOrder(mine, navOrders().lists), UI.IsNavFavorite)
  quick = UI.FavoritesFirst(UI.ApplyNavOrder(quick, navOrders().quick), UI.IsNavFavorite)
  record("lists", mine)
  record("quick", quick)
  local showMine = UI.NavSectionShown("lists")
  local showQuick = #quick > 0 and UI.NavSectionShown("quick")
  local collapsed = (showMine or showQuick) and heading(L["Lists"], showMine, UI.NAV_LISTS_KEY)
  if not showMine then nav.AddList:Hide() end
  nav.Empty:SetShown(showMine and #mine == 0 and not collapsed)
  if (showMine or showQuick) and not collapsed then
    if showQuick then
      for _, e in ipairs(quick) do entry(e, true) end
    end
    if showMine and #mine == 0 then
      nav.Empty:ClearAllPoints()
      nav.Empty:SetPoint("TOPLEFT", nav.Content, "TOPLEFT", 12, -(y + 2))
      y = y + 30
    end
    if showMine then
      for _, e in ipairs(mine) do entry(e, true) end
    end
  end
  for i = nb + 1, #nav.Buttons do nav.Buttons[i]:Hide() end
  for i = nh + 1, #nav.Headings do nav.Headings[i]:Hide() end
  nav.contentHeight = y
  nav.Content:SetHeight(math.max(y, 1))
  nav.shown = nb
end
