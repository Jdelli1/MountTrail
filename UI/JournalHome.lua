local ADDON, ns = ...

-- Journal tab: a front page in the Blend A look, every part a card (a fill
-- a shade lighter than the window, a 1 px border, a 3 px coloured edge;
-- newCard / placeCard). A summary card (the collected total over every
-- tab's mounts in large gold figures, "mounts collected · 58%" under it, a
-- 12 px gold bar, a search box) over two columns in one scrolling page:
--   left   "Expansions": one row per expansion (its name and its bar in its
--          colour, owned / total; a click opens its mount list, Back
--          returns);
--   right  "By source": the same rows for the Browse categories (a click
--          opens that page; bars bronze), then "Nearby": the first mounts
--          still to get in the player's zone, each with its icon (boxed in
--          its rarity's colour), its source and its drop chance
--          (Zone.MountsFor, worked out again on a new zone or once a minute;
--          a click is the waypoint, the last line opens Current Zone).
-- A complete row's count turns green. Headings are in the header colour
-- (UI.HeaderColor), "collected" on their right.
-- The search box searches every mount (Logic/Search.lua): typing opens the
-- search page, a list of results grouped by what matched, whose own box
-- takes over the typing; Back returns home.
-- A list (Logic/Lists.lua, Logic/QuickLists.lua; picked in the window's
-- navigation column, UI/Frame.lua) opens here as a page like an
-- expansion's (UI.ShowListPage): its mounts by source, Collected and the
-- detail pane as usual, and a Pop out button. UI.ListCardStatsFor gives the
-- navigation its numbers (owned / total, lockouts open today).

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

-- Layout: margins, the strip, the gap between the two columns, row heights.
local G = {
  left = 12, top = -66, stripH = 56,
  gap = 12,
  row = 22, heading = 24, sectionGap = 10, nearRow = 36,
  cardIn = 10, cardPad = 6, -- rows' inset from a card's left (past its edge) and right
}
UI.HomeLayout = G

local SUMMARY_BAR_H, ROW_BAR_H = 12, 6
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8" -- flat fill, tinted below
local GOLD = { 1, 0.82, 0, 1 }
local DONE = { 0.56, 0.88, 0.56 } -- a complete row's count
local GREY_TEXT = "|cff9d9d9d"
local NEARBY_MAX = 5
local NEARBY_TTL = 60 -- seconds the Nearby list is kept for one zone
-- The cards' edges: gold for the collection, bronze for the sources, green
-- for what is near.
local EDGE_SOURCES = { 0.56, 0.48, 0.29 }
local EDGE_NEARBY = { 0.36, 0.89, 0.36 }
local NO_RARITY = { 0.35, 0.32, 0.26 }

local TRACK = { 0, 0, 0, 0.5 }

local home, listPage, list, title
local searchPage, searchList
local currentExp

local function expansions()
  return (ns.Data and ns.Data.Expansions) or {}
end

-- Whole percent of `have` out of `total`, rounded down (99% until the last
-- mount); 0 when there is nothing to collect.
function UI.HomePercent(have, total)
  if not total or total <= 0 then return 0 end
  return math.floor((have or 0) * 100 / total)
end

-- Owned / total per source, the Browse categories (Logic/Browse.lua: a
-- category with its own view, Achievements / Holidays / Timewalking, by
-- Journal.ViewOf), through the list gate (known to the client, this faction,
-- obtainable or owned) and the counted sections only (Journal.IsExcluded)
-- -> { [category key] = { have =,
-- total = } }, plus all = every mount the gate keeps. sourceText as
-- Journal.SectionOf (refines delves and caches).
function UI.HomeSourceCounts(mounts, isOwned, exists, faction, sourceText)
  local out = { all = { have = 0, total = 0 } }
  for _, c in ipairs(ns.Browse.CATEGORIES) do out[c.key] = { have = 0, total = 0 } end
  for id, m in pairs(mounts or {}) do
    local o = ns.Journal.Gate(id, m, isOwned, exists, faction, ns.Journal.countUnobtainable)
    -- A section the player does not count (Options) stays listed but is
    -- left out of these numbers.
    if o ~= nil and not ns.Journal.IsExcluded(m) then
      local key = ns.Browse.CategoryOf(id, m, sourceText) or ns.Journal.ViewOf(m)
      local c = out[key] or out.other
      c.total, out.all.total = c.total + 1, out.all.total + 1
      if o then c.have, out.all.have = c.have + 1, out.all.have + 1 end
    end
  end
  return out
end

-- A flat StatusBar (gold) on a dark track; the caller anchors it.
local function flatBar(parent, height)
  local bar = CreateFrame("StatusBar", nil, parent)
  bar:SetHeight(height)
  bar:SetStatusBarTexture(BAR_TEXTURE)
  bar:SetStatusBarColor(unpack(GOLD))
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  local track = bar:CreateTexture(nil, "BACKGROUND")
  track:SetAllPoints(bar)
  track:SetColorTexture(unpack(TRACK))
  bar.Track = track
  return bar
end

-- A card behind a run of rows: textures on `parent` (so under its rows),
-- placed by placeCard.
local function newCard(parent)
  local c = {}
  for _, k in ipairs({ "Fill", "Top", "Bottom", "Right" }) do c[k] = parent:CreateTexture(nil, "BACKGROUND") end
  c.Edge = parent:CreateTexture(nil, "BORDER")
  return c
end

-- Places card `c` on `parent` from `top` to `bottom` (px down from its
-- top), full width, its left edge in `color`.
local function placeCard(c, parent, top, bottom, color)
  local h, line = math.max(1, bottom - top), UI.THEME.cardEdge
  for _, t in ipairs({ c.Fill, c.Edge, c.Top, c.Bottom, c.Right }) do
    t:ClearAllPoints()
    t:Show()
  end
  c.Fill:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -top)
  c.Fill:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -top)
  c.Fill:SetHeight(h)
  c.Fill:SetColorTexture(1, 1, 1, 0.035)
  c.Edge:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -top)
  c.Edge:SetSize(3, h)
  c.Edge:SetColorTexture(color[1], color[2], color[3], 0.9)
  c.Top:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -top)
  c.Top:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -top)
  c.Top:SetHeight(1)
  c.Bottom:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, -(bottom - 1))
  c.Bottom:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -(bottom - 1))
  c.Bottom:SetHeight(1)
  c.Right:SetPoint("TOPRIGHT", parent, "TOPRIGHT", 0, -top)
  c.Right:SetSize(1, h)
  for _, t in ipairs({ c.Top, c.Bottom, c.Right }) do t:SetColorTexture(line[1], line[2], line[3], 1) end
end

-- A card's header: its text in the header colour over a faint rule, a grey
-- `note` on its right ("collected").
local function heading(parent, text, note)
  local h = CreateFrame("Frame", nil, parent)
  h:SetHeight(G.heading)
  local fs = h:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
  fs:SetPoint("LEFT", h, "LEFT", 2, 0)
  fs:SetText(text)
  h.Text = fs
  local right = h:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  right:SetPoint("RIGHT", h, "RIGHT", -4, 0)
  right:SetText(note or "")
  h.Note = right
  local rule = h:CreateTexture(nil, "BORDER")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 1)
  rule:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 1)
  h.Rule = rule
  return h
end

local function paintHeading(h)
  local c = UI.HeaderColor and UI.HeaderColor({ depth = 1 }) or GOLD
  local r = UI.THEME.cardRule
  h.Text:SetTextColor(c[1], c[2], c[3])
  h.Rule:SetColorTexture(r[1], r[2], r[3], 1)
end

-- A hover band and, every other row, a faint stripe (the lists' look).
local function rowLook(b, alt)
  local stripe = b:CreateTexture(nil, "BACKGROUND")
  stripe:SetAllPoints(b)
  stripe:SetColorTexture(1, 1, 1, 0.025)
  stripe:SetShown(alt)
  b.Stripe = stripe
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints(b)
  hl:SetColorTexture(1, 1, 1, 0.07)
end

-- A progress row: the name, a bar, owned / total (as the design: no
-- percent; a complete row's count turns green).
local function progressRow(parent, i)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(G.row)
  rowLook(b, i % 2 == 0)
  local name = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlight"))
  name:SetPoint("LEFT", b, "LEFT", 4, 0)
  name:SetWidth(128)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  b.Name = name
  local count = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlight"))
  count:SetPoint("RIGHT", b, "RIGHT", -4, 0)
  count:SetWidth(70)
  count:SetJustifyH("RIGHT")
  b.Count = count
  local bar = flatBar(b, ROW_BAR_H)
  bar:SetPoint("LEFT", name, "RIGHT", 8, 0)
  bar:SetPoint("RIGHT", count, "LEFT", -8, 0)
  b.Bar = bar
  return b
end

-- A row's numbers, its bar in `color` (an expansion's, the sources'
-- bronze).
local function paintProgress(b, have, total, color)
  b.have, b.total = have, total
  b.Count:SetText(string.format(L["%d / %d"], have, total))
  local done = total > 0 and have >= total
  if done then b.Count:SetTextColor(DONE[1], DONE[2], DONE[3]) else b.Count:SetTextColor(0.79, 0.75, 0.68) end
  b.Bar:SetMinMaxValues(0, math.max(total, 1))
  b.Bar:SetValue(have)
  b.Bar:SetStatusBarColor(color[1], color[2], color[3], 1)
end

-- A Nearby row: the mount's icon (boxed in its rarity's colour), its name
-- over its source, its drop chance as a badge; a click is the waypoint, the
-- hover its tooltip.
local function nearbyRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(G.nearRow)
  rowLook(b, false)
  local box = CreateFrame("Frame", nil, b)
  box:SetSize(G.nearRow - 8, G.nearRow - 8)
  box:SetPoint("LEFT", b, "LEFT", 2, 0)
  box.Edge = UI.FlatBorder(box, 1, 1, 1, 0.3)
  b.IconBox = box
  local icon = box:CreateTexture(nil, "ARTWORK")
  icon:SetPoint("TOPLEFT", box, "TOPLEFT", 1, -1)
  icon:SetPoint("BOTTOMRIGHT", box, "BOTTOMRIGHT", -1, 1)
  icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
  b.Icon = icon
  local badge = UI.Badge(b)
  badge:SetPoint("RIGHT", b, "RIGHT", -4, 0)
  b.Chance = badge
  local name = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlight"))
  name:SetPoint("BOTTOMLEFT", box, "RIGHT", 8, 1)
  name:SetPoint("RIGHT", badge, "LEFT", -6, 0)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  b.Name = name
  local sub = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  sub:SetPoint("TOPLEFT", box, "RIGHT", 8, -1)
  sub:SetPoint("RIGHT", badge, "LEFT", -6, 0)
  sub:SetJustifyH("LEFT")
  sub:SetWordWrap(false)
  b.Sub = sub
  b:SetScript("OnClick", function(self) if self.mountID and UI.GoTo then UI.GoTo(self.mountID) end end)
  b:SetScript("OnEnter", function(self) if self.mountID then UI.ShowMountTooltip(self, self.mountID) end end)
  b:SetScript("OnLeave", function() UI.HideMountTooltip() end)
  return b
end

-- The right column's parts, placed top to bottom by their contents, inside
-- their card.
local function place(f, side, y, h)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", side, "TOPLEFT", G.cardIn, -y)
  f:SetPoint("TOPRIGHT", side, "TOPRIGHT", -G.cardPad, -y)
  if h then f:SetHeight(h) end
  f:Show()
  return y + (h or f:GetHeight() or G.row)
end

-- The Nearby list, kept per zone (Zone.Key) for NEARBY_TTL seconds.
local nearby = { key = nil, at = nil, list = {}, zone = nil }

function UI.HomeNearby(now)
  local Game = ns.Game
  local good, ctx = pcall(UI.ZoneContext)
  if not good or not ctx then return {}, nil end
  local mapID = Game.PlayerMap()
  local okKey, key = pcall(ns.Zone.Key, mapID, ctx)
  if not okKey then key = nil end
  if nearby.key == key and nearby.at and now and now - nearby.at < NEARBY_TTL then
    return nearby.list, nearby.zone
  end
  local found, zone = UI.ZoneMounts(mapID, ctx)
  nearby.key, nearby.at, nearby.list, nearby.zone = key, now, found or {}, zone
  return nearby.list, zone
end

function UI.ForgetHomeNearby()
  nearby.key, nearby.at, nearby.list, nearby.zone = nil, nil, {}, nil
end

local function refreshSide()
  local side = home.Side
  local Game = ns.Game
  local top = home.nearbyTop or 0
  local y = top + 2
  -- Nearby: a card of the zone's first mounts.
  paintHeading(side.NearbyHeading)
  y = place(side.NearbyHeading, side, y, G.heading) + 2
  local near, zone = UI.HomeNearby(Game.Now())
  for i = 1, NEARBY_MAX do
    local b = side.Nearby[i] or nearbyRow(side)
    side.Nearby[i] = b
    local e = near[i]
    if e then
      b.mountID = e.id
      local name, icon = Game.MountInfo(e.id)
      b.Name:SetText(name or (e.m and e.m.name) or tostring(e.id))
      b.Icon:SetTexture(icon or 134400) -- a question mark when unknown
      local rarity = UI.ListRarityColor and UI.ListRarityColor(e.id) or nil
      if rarity then b.Name:SetTextColor(rarity[1], rarity[2], rarity[3]) else b.Name:SetTextColor(1, 1, 1) end
      local edge = rarity or NO_RARITY
      b.IconBox.Edge:SetColor(edge[1], edge[2], edge[3], 1)
      b.Sub:SetText(UI.SourceLine and UI.SourceLine(e.id) or "")
      local chance = e.m and tonumber(e.m.chance)
      UI.SetBadge(b.Chance, chance and chance > 1 and string.format(L["1 in %d"], chance) or nil, "grey")
      y = place(b, side, y, G.nearRow)
    else
      b.mountID = nil
      b:Hide()
    end
  end
  local more = side.NearbyMore
  if #near == 0 then
    more:SetText(GREY_TEXT .. L["Nothing left to collect here"] .. "|r")
  else
    more:SetText(GREY_TEXT .. string.format(L["%d in %s: open Current Zone"], #near,
      zone and zone.name or L["this zone"]) .. "|r")
  end
  y = place(more, side, y, G.row) + 4
  placeCard(side.Card, side, top, y, EDGE_NEARBY)
  home.rightHeight = y
  home.FitPage()
end

local function refreshHome()
  local mounts = (ns.Data and ns.Data.Mounts) or {}
  local Game = ns.Game
  -- Ask the client about each mount at most once for all rows.
  local owned, known = {}, {}
  local function isOwned(id)
    if owned[id] == nil then owned[id] = Game.IsOwned(id) and true or false end
    return owned[id]
  end
  local function exists(id)
    if known[id] == nil then known[id] = Game.Exists(id) and true or false end
    return known[id]
  end
  local faction = Game.Faction()

  paintHeading(home.ExpHeading)
  for i, name in ipairs(expansions()) do
    local b = home.Expansions[i]
    if b then
      local c = (UI.EXPANSION_COLORS and UI.EXPANSION_COLORS[name]) or GOLD
      b.Name:SetTextColor(c[1], c[2], c[3])
      local have, total = ns.Journal.Counts(mounts, name, isOwned, exists, faction, Game.MountSourceText)
      paintProgress(b, have, total, c)
    end
  end

  local sourceText = UI.MemoText and UI.MemoText(Game.MountSourceText) or Game.MountSourceText
  local counts = UI.HomeSourceCounts(mounts, isOwned, exists, faction, sourceText)
  paintHeading(home.SourceHeading)
  for _, b in ipairs(home.Sources) do
    local c = counts[b.key] or { have = 0, total = 0 }
    paintProgress(b, c.have, c.total, EDGE_SOURCES)
  end
  home.LayoutMain()
  local sumHave, sumTotal = counts.all.have, counts.all.total
  local s = home.Summary
  s.have, s.total = sumHave, sumTotal
  s.Totals:SetText(string.format(L["%d / %d"], sumHave, sumTotal))
  s.Title:SetText(string.format(L["mounts collected · %d%%"], UI.HomePercent(sumHave, sumTotal)))
  s.Bar:SetMinMaxValues(0, math.max(sumTotal, 1))
  s.Bar:SetValue(sumHave)
  s.Bar:SetStatusBarColor(GOLD[1], GOLD[2], GOLD[3], 1)
  local good, err = pcall(refreshSide)
  if not good and Game.ReportError then Game.ReportError(err) end
end

local myListPage, myList, myListTitle
local currentList -- the list page's source: { kind = "list", list = id } | { kind = "quick", key = }

local function showHome()
  currentExp = nil
  currentList = nil
  listPage:Hide()
  searchPage:Hide()
  myListPage:Hide()
  home:Show()
  refreshHome()
end

-- Search.Select over every mount through the list gate, with each mount's
-- UI.SearchFields (memoised in the shared UI.SearchCache, reset per visit).
local function searchSelect(mounts, query)
  local ctx = { sourceText = query.sourceText, mapName = ns.Game.MapName }
  return ns.Search.Select(mounts, {
    search = query.search,
    cache = UI.SearchCache(),
    gate = function(id, m)
      return ns.Journal.Gate(id, m, query.isOwned, query.exists, query.faction, query.showUnobtainable)
    end,
    fields = function(id, m) return UI.SearchFields(id, m, ctx) end,
  })
end

-- Opens the search page with `text` in its box (focused, so typing goes on
-- there) and clears the home box.
local function showSearch(text)
  UI.ClearSearchCache()
  home:Hide()
  listPage:Hide()
  myListPage:Hide()
  searchPage:Show()
  local box = searchList.SearchBox
  box:SetText(text)
  if type(box.SetFocus) == "function" then box:SetFocus() end
  if type(box.SetCursorPosition) == "function" then box:SetCursorPosition(#text) end
  home.Summary.Search:SetText("")
  searchList.searchText = text -- whether or not SetText fired OnTextChanged
  searchList:Refresh(true)
end

local function showList(name)
  currentExp = name
  title:SetText(L[name])
  home:Hide()
  listPage:Show()
  list:Refresh(true)
end

-- The summary strip: "Mount Collection" and the search box left, the totals
-- over every tab right, a full-width 4 px bar along its bottom edge.
local function createSummary()
  local s = CreateFrame("Frame", nil, home)
  s:SetPoint("TOPLEFT", home, "TOPLEFT", G.left, 0)
  s:SetPoint("TOPRIGHT", home, "TOPRIGHT", -G.left, 0)
  s:SetHeight(G.stripH)
  -- A card, its edge gold.
  s.Card = newCard(s)
  placeCard(s.Card, s, 0, G.stripH, GOLD)

  -- The total in large gold figures, "mounts collected · 58%" under it.
  local totals = s:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalHuge"))
  totals:SetPoint("TOPLEFT", s, "TOPLEFT", G.cardIn + 2, -8)
  s.Totals = totals
  local titleText = s:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisable"))
  titleText:SetPoint("TOPLEFT", totals, "BOTTOMLEFT", 0, -3)
  s.Title = titleText

  -- Search box on the right; the first typed letter opens the search page.
  local search = CreateFrame("EditBox", nil, s, "SearchBoxTemplate")
  search:SetAutoFocus(false)
  search:SetSize(200, 20)
  search:SetPoint("RIGHT", s, "RIGHT", -12, 0)

  -- The gold bar between them.
  local bar = flatBar(s, SUMMARY_BAR_H)
  bar:SetPoint("LEFT", s, "LEFT", 190, 0)
  bar:SetPoint("RIGHT", search, "LEFT", -18, 0)
  s.Bar = bar
  -- A short one-line hint (a long one wrapped onto two lines); the tooltip
  -- says what else it finds.
  local hint = search.Instructions
  if hint and hint.SetText then
    hint:SetText(L["Search all mounts"])
    if hint.SetWordWrap then hint:SetWordWrap(false) end
    if hint.SetMaxLines then hint:SetMaxLines(1) end
  end
  search:HookScript("OnEnter", function(self)
    UI.ShowHint(self, L["Search all mounts"],
      L["Mount, boss or rare, dungeon or raid, zone, achievement or expansion. Typos and short names (icc, cata, bfa) work."])
  end)
  search:HookScript("OnLeave", function(self) UI.HideHint(self) end)
  search:HookScript("OnTextChanged", function(self, userInput)
    local text = self:GetText() or ""
    if userInput and string.find(text, "%S") then showSearch(text) end
  end)
  s.Search = search
  return s
end

-- The page under the summary: two columns in one scrolling frame, as the
-- design. Left: Expansions. Right: By source (the Browse categories, the
-- navigation's order; a category the player does not count is left out),
-- then Nearby (placed by refreshSide, under By source).
local function createColumns()
  local main = CreateFrame("ScrollFrame", nil, home)
  main:SetPoint("TOPLEFT", home, "TOPLEFT", G.left, G.top)
  main:SetPoint("BOTTOMRIGHT", home, "BOTTOMRIGHT", -G.left, 0)
  local content = CreateFrame("Frame", nil, main)
  content:SetSize(1, 1)
  main:SetScrollChild(content)
  if main.EnableMouseWheel then main:EnableMouseWheel(true) end
  main:SetScript("OnMouseWheel", function(self, delta)
    local max = math.max(0, (home.mainHeight or 0) - (self:GetHeight() or 0))
    self:SetVerticalScroll(math.min(max, math.max(0, (self:GetVerticalScroll() or 0) - delta * 30)))
  end)
  local left = CreateFrame("Frame", nil, content)
  left:SetPoint("TOPLEFT", content, "TOPLEFT", 0, 0)
  local right = CreateFrame("Frame", nil, content)
  right:SetPoint("TOPRIGHT", content, "TOPRIGHT", 0, 0)
  -- Each column half the page, less the gap between them.
  main:SetScript("OnSizeChanged", function(self, w)
    w = w or self:GetWidth() or 1
    content:SetWidth(w)
    local half = math.max(1, (w - G.gap) / 2)
    left:SetWidth(half)
    right:SetWidth(half)
  end)
  home.Main, home.MainContent = main, content
  home.Left, home.Side = left, right

  home.ExpCard, home.SourceCard = newCard(left), newCard(right)
  home.ExpHeading = heading(left, L["Expansions"], L["collected"])
  home.Expansions = {}
  for i, name in ipairs(expansions()) do
    local b = progressRow(left, i)
    b.Name:SetText(L[name])
    b.exp = name
    b:SetScript("OnClick", function() showList(name) end)
    home.Expansions[i] = b
  end
  home.SourceHeading = heading(right, L["By source"], L["collected"])
  home.Sources = {}
  for i, c in ipairs(ns.Browse.CATEGORIES) do
    local b = progressRow(right, i)
    b.key, b.category = c.key, c
    b.Name:SetText(L[c.label])
    b:SetScript("OnClick", function()
      if c.view then UI.SelectTab(c.view) elseif UI.ShowBrowse then UI.ShowBrowse(c.key) end
    end)
    home.Sources[i] = b
  end

  -- The page's height: the taller column (Nearby counted once placed).
  function home.FitPage()
    local h = math.max(home.leftHeight or 0, home.rightHeight or 0)
    home.mainHeight = h
    content:SetHeight(math.max(h, 1))
    left:SetHeight(math.max(home.leftHeight or 0, 1))
    right:SetHeight(math.max(home.rightHeight or 0, 1))
  end

  -- Places the rows top to bottom inside their cards (a source left out
  -- takes no room), striping the shown ones afresh.
  function home.LayoutMain()
    local y
    local function add(col, f, h)
      f:ClearAllPoints()
      f:SetPoint("TOPLEFT", col, "TOPLEFT", G.cardIn, -y)
      f:SetPoint("TOPRIGHT", col, "TOPRIGHT", -G.cardPad, -y)
      f:Show()
      y = y + h
    end
    y = 2
    add(left, home.ExpHeading, G.heading)
    y = y + 2
    for _, b in ipairs(home.Expansions) do add(left, b, G.row) end
    y = y + 4
    placeCard(home.ExpCard, left, 0, y, GOLD)
    home.leftHeight = y
    y = 2
    add(right, home.SourceHeading, G.heading)
    y = y + 2
    local n = 0
    for _, b in ipairs(home.Sources) do
      if ns.Browse.Shown(b.category) then
        n = n + 1
        b.Stripe:SetShown(n % 2 == 0)
        add(right, b, G.row)
      else
        b:Hide()
      end
    end
    y = y + 4
    placeCard(home.SourceCard, right, 0, y, EDGE_SOURCES)
    home.nearbyTop = y + G.sectionGap
    home.rightHeight = math.max(home.rightHeight or 0, y)
    home.FitPage()
  end

  -- Nearby, under By source (placed by refreshSide).
  local side = right
  side.Card = newCard(side)
  side.NearbyHeading = heading(side, L["Nearby"])
  side.Nearby = {}
  local more = CreateFrame("Button", nil, side)
  more:SetHeight(G.row)
  local mt = more:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlight"))
  mt:SetPoint("LEFT", more, "LEFT", 4, 0)
  mt:SetPoint("RIGHT", more, "RIGHT", -4, 0)
  mt:SetJustifyH("LEFT")
  mt:SetWordWrap(false)
  more.Text = mt
  function more:SetText(text) self.Text:SetText(text) end
  more:SetScript("OnClick", function() UI.SelectTab("here") end)
  side.NearbyMore = more
  home.LayoutMain()
end

-- Lists column ----------------------------------------------------------------------


-- A list's card numbers: `ids` its mounts; isOwned(id); built a
-- Checklist.Build output -> { have = owned, total = #ids, open = the daily /
-- weekly lockouts of its mounts still to get that are not done yet (a
-- lockout shared by several of its mounts counts once) }.
function UI.ListCardStats(ids, isOwned, built)
  local byMount = {}
  for _, reset in ipairs({ "daily", "weekly" }) do
    for _, e in ipairs((built and built[reset]) or {}) do
      for _, id in ipairs(e.mounts or { e.id }) do
        if byMount[id] == nil then byMount[id] = e end
      end
    end
  end
  local have, open, seen = 0, 0, {}
  for _, id in ipairs(ids or {}) do
    if isOwned(id) then
      have = have + 1
    else
      local e = byMount[id]
      if e and not e.done and not seen[e] then
        seen[e] = true
        open = open + 1
      end
    end
  end
  return { have = have, total = #(ids or {}), open = open }
end

-- The mounts of a list source ({ kind = "list", list = id } or
-- { kind = "quick", key = }) -> ids, name.
local function listMounts(source)
  if source.kind == "quick" then
    local q = ns.QuickLists and ns.QuickLists.Get(source.key)
    return ns.QuickLists and ns.QuickLists.Mounts(source.key) or {}, q and L[q.name] or L["List"]
  end
  local store = UI.ListsDB and UI.ListsDB()
  local l = store and ns.Lists.Get(store, source.list)
  return (l and l.mounts) or {}, l and l.name or L["List"]
end

local function showMyList(source)
  currentList = source
  local _, name = listMounts(source)
  myListTitle:SetText(name)
  home:Hide()
  listPage:Hide()
  searchPage:Hide()
  myListPage:Show()
  myList:Refresh(true)
end

-- How the list page shows its list: a custom list's own sort
-- (Lists.SortOf: "added", "expansion"); a quick list keeps its order.
local function listSort(source)
  if not (source and source.kind == "list") then return "added" end
  local store = UI.ListsDB and UI.ListsDB()
  return store and ns.Lists.SortOf(store, source.list) or "added"
end

-- The list page's mounts (UI.List's select): the list's mounts the list gate
-- keeps (owned ones too: Collected decides), in the list's order (moved by
-- the player), or by expansion (each expansion a section, the list's order
-- inside) when the list is sorted so; the search box narrows by name.
local function myListSelect(mounts, query)
  local ids = currentList and listMounts(currentList) or {}
  local needle = query.search and string.lower(query.search) or ""
  -- The home page's fuzzy search (tbc, a boss, a zone...).
  local match = UI.SearchMatches and UI.SearchMatches(ids, query.search, query.sourceText) or nil
  local byExp = listSort(currentList) == "expansion"
  local out = {}
  for _, o in ipairs(ns.Lists.Ordered(ids, mounts, byExp and "expansion" or "added", expansions())) do
    local id = o.id
    local m = mounts[id]
    if m and ns.Journal.Gate(id, m, query.isOwned, query.exists, query.faction, true) ~= nil then
      local name = (ns.Game.MountInfo and ns.Game.MountInfo(id)) or m.name or ""
      local hit
      if match then hit = match[id] == true else hit = needle == "" or string.find(string.lower(name), needle, 1, true) end
      if hit then
        out[#out + 1] = { id = id, m = m, section = byExp and (m.exp or "Other") or "list" }
      end
    end
  end
  return out
end

-- A page under a flat header (UI.PageHeader) with Back and a title -> page,
-- holder, back, title.
local function pageWithStrip(parent)
  local page = CreateFrame("Frame", nil, parent)
  page:SetAllPoints(parent)
  page:Hide()
  local back, t = UI.PageHeader(page, true)
  local holder = CreateFrame("Frame", nil, page)
  holder:SetPoint("TOPLEFT", page, "TOPLEFT", 0, UI.PAGE_TOP)
  holder:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
  return page, holder, back, t
end

local function build(parent)
  home = CreateFrame("Frame", nil, parent)
  home:SetAllPoints(parent)
  home.Summary = createSummary()
  createColumns()

  -- An expansion's page: Back and the expansion's name over its list.
  local holder, back
  listPage, holder, back, title = pageWithStrip(parent)
  back:SetScript("OnClick", showHome)
  list = UI.List(holder, function()
    return { view = "journal", exp = currentExp, sourceText = ns.Game.MountSourceText }
  end)

  -- The search page.
  local sHolder, sBack, sTitle
  searchPage, sHolder, sBack, sTitle = pageWithStrip(parent)
  sTitle:SetText(L["Search all mounts"])
  searchList = UI.List(sHolder, function()
    return { view = "search", sourceText = ns.Game.MountSourceText }
  end, { select = searchSelect })
  searchPage.List = searchList
  sBack:SetScript("OnClick", function()
    searchList.SearchBox:SetText("")
    showHome()
  end)

  -- A list's page (the navigation's lists): its mounts as a list by source.
  local mHolder, mBack
  myListPage, mHolder, mBack, myListTitle = pageWithStrip(parent)
  mBack:SetScript("OnClick", showHome)
  local pop = UI.PageButton(myListPage, L["Pop out"])
  pop:SetScript("OnClick", function() if currentList and UI.OpenPopout then UI.OpenPopout(currentList) end end)
  myListPage.PopOut = pop
  myList = UI.List(mHolder, function()
    local key = currentList and (currentList.kind == "quick" and ("q" .. tostring(currentList.key))
      or tostring(currentList.list)) or ""
    return { view = "mylist", exp = key, sourceText = ns.Game.MountSourceText,
      bare = listSort(currentList) ~= "expansion" }
  end, {
    select = myListSelect,
    -- A custom list's sort, after the Filter menu's choices.
    menu = {
      items = function()
        if not (currentList and currentList.kind == "list") then return {} end
        local sort = listSort(currentList)
        return {
          { kind = "title", label = L["Sort"] },
          { kind = "radio", key = "sort:added", label = L["Order added"], checked = sort == "added" },
          { kind = "radio", key = "sort:expansion", label = L["By expansion"], checked = sort == "expansion" },
        }
      end,
      onChange = function(kind, value)
        if kind ~= "radio" or not (currentList and currentList.kind == "list") then return false end
        local store = UI.ListsDB and UI.ListsDB()
        if store then ns.Lists.SetSort(store, currentList.list, value == "sort:expansion" and "expansion" or "added") end
        return true
      end,
    },
  })
  myListPage.List = myList
  myListPage.Title = myListTitle
end

local function refresh()
  if not home then return end
  if myListPage:IsShown() then
    -- A deleted list: back home.
    if currentList and currentList.kind == "list" then
      local store = UI.ListsDB and UI.ListsDB()
      if not (store and ns.Lists.Get(store, currentList.list)) then
        showHome()
        return
      end
    end
    local _, name = listMounts(currentList)
    myListTitle:SetText(name)
    myList:Refresh()
  elseif searchPage:IsShown() then
    searchList:Refresh()
  elseif listPage:IsShown() then
    list:Refresh()
  else
    refreshHome()
  end
end

-- The navigation column's hooks (UI/Frame.lua): a list's page, the front
-- page, the list on screen, and a list's numbers.
function UI.ShowListPage(source)
  if myListPage and source then showMyList(source) end
end

function UI.ShowJournalHome()
  if home then showHome() end
end

function UI.CurrentListPage()
  if myListPage and myListPage:IsShown() then return currentList end
  return nil
end

-- UI.ListCardStats for a list source; `built` a Checklist.Build output
-- (default: built now).
function UI.ListCardStatsFor(source, built)
  local ids = listMounts(source)
  built = built or (UI.ChecklistBuild and UI.ChecklistBuild(ns.Game.Now())) or {}
  return UI.ListCardStats(ids, function(id) return ns.Game.IsOwned(id) end, built)
end

UI.RegisterView("journal", { Build = build, Refresh = refresh })
