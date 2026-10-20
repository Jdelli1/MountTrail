local ADDON, ns = ...

-- Journal tab: a front page with a slim summary strip (title, collected
-- totals over every tab's mounts, a 4 px gold bar, then one chip per tab with
-- its own owned / total; a chip click opens that tab) above a 4 x 3 grid of flat
-- expansion tiles (logo, a 3 px bar, owned / total and percent); clicking a
-- tile opens that expansion's mount list, and Back returns.
-- Tiles follow the current flat panel style: a dark flat fill with a 1 px
-- subtle edge; hover brightens the fill and turns the edge gold. A completed
-- expansion gets a green bar and a check in its top-right corner.
-- A search box in the strip searches every mount (Logic/Search.lua): typing
-- opens the search page, a list of results grouped by what matched, whose
-- own box takes over the typing; Back returns home.
-- A list (Logic/Lists.lua, Logic/QuickLists.lua; picked in the window's
-- navigation column, UI/Frame.lua) opens here as a page like an
-- expansion's (UI.ShowListPage): its mounts by source, Collected and the
-- detail pane as usual, and a Pop out button. UI.ListCardStatsFor gives the
-- navigation its numbers (owned / total, lockouts open today).

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

-- Layout. The content area of the 800 x 560 window is 780 x 486 (inset 6 px
-- in and 60 px down for the portrait and top tabs, content 4 px inside it).
-- Strip: title and totals in the top 32 px, the bar at 32-36 px, the tab
-- chips at 42-58 px. With the 900 x 560 window and its 156 px navigation
-- column the view area is 726 x 518: the grid from 68 px down is
-- 12 + 4 x 165 + 3 x 12 = 708 wide (12 px right margin) and 68 + 3 x 128 + 2 x 12 = 476 tall.
local G = {
  cols = 4,
  tileW = 165, tileH = 128,
  gap = 12,
  left = 12, top = -68,
  stripH = 36,
  chipsY = -42, chipsH = 16, chipGap = 18,
}
UI.HomeLayout = G

local LOGO_W, LOGO_H = 150, 75 -- 2:1, the shape of the client's expansion logos
local LOGO_BASE = math.min(165 / 180, 128 / 128) -- the default tile's logo scale
local LOGO_Y = 15 -- centre of the area above the bar: (30 + 128) / 2 - 128 / 2
local TILE_BAR_H, SUMMARY_BAR_H = 3, 4
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8" -- flat fill, tinted below
local FILL = { 0.07, 0.07, 0.08, 0.9 }
local FILL_HOVER = { 0.12, 0.12, 0.14, 0.95 }
local EDGE = { 1, 1, 1, 0.1 }
local EDGE_HOVER = { 1, 0.82, 0, 0.6 }
local GOLD = { 1, 0.82, 0, 1 }
local GREEN = { 0.25, 0.78, 0.35, 1 }

-- Progress colours (tiles and the summary bar): red under 25 %, yellow
-- under 75 %, green below complete, blue once complete.
local RED = { 0.85, 0.22, 0.2, 1 }
local BLUE = { 0.25, 0.6, 1, 1 }
UI.PROGRESS_STEPS = { yellow = 25, green = 75 }

-- The bar colour of `have` out of `total` -> { r, g, b, a }; nothing to
-- collect counts as red (0 %).
function UI.ProgressColor(have, total)
  if total and total > 0 and (have or 0) >= total then return BLUE end
  local pct = UI.HomePercent(have, total)
  if pct >= UI.PROGRESS_STEPS.green then return GREEN end
  if pct >= UI.PROGRESS_STEPS.yellow then return GOLD end
  return RED
end
local TRACK = { 0, 0, 0, 0.5 }
-- The Great Vault's completed-activity check (Blizzard_WeeklyRewards.xml,
-- CompletedIcon); GreenCheckMarkTemplate's texture where the atlas is missing.
local CHECK_ATLAS = "activities-icon-checkmark"
local CHECK_TEXTURE = "Interface\\Scenarios\\ScenarioIcon-Check"

local home, listPage, list, title
local searchPage, searchList
local cards = {}
local currentExp

-- The tabs that list mounts, in tab order; the summary counts all of them.
local CHIPS = {
  { key = "journal", label = "Journal" },
  { key = "holidays", label = "Holidays" },
  { key = "achievements", label = "Achievements" },
  { key = "timewalking", label = "Timewalking" },
  { key = "misc", label = "Misc" },
}
UI.HomeChips = CHIPS

local function expansions()
  return (ns.Data and ns.Data.Expansions) or {}
end

-- Whole percent of `have` out of `total`, rounded down (99% until the last
-- mount); 0 when there is nothing to collect.
function UI.HomePercent(have, total)
  if not total or total <= 0 then return 0 end
  return math.floor((have or 0) * 100 / total)
end

-- Owned / total per tab (Journal.ViewOf without options, so an unobtainable
-- mount counts on its own tab) through the list gate (known to the client,
-- this faction, obtainable or owned) -> { [view] = { have =, total = } },
-- plus all = the sum over the CHIPS tabs.
function UI.HomeTabCounts(mounts, isOwned, exists, faction)
  local out = { all = { have = 0, total = 0 } }
  for _, chip in ipairs(CHIPS) do out[chip.key] = { have = 0, total = 0 } end
  for id, m in pairs(mounts or {}) do
    local c = out[ns.Journal.ViewOf(m)]
    if c and c ~= out.all then
      local o = ns.Journal.Gate(id, m, isOwned, exists, faction)
      if o ~= nil then
        c.total, out.all.total = c.total + 1, out.all.total + 1
        if o then c.have, out.all.have = c.have + 1, out.all.have + 1 end
      end
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

local function paintTile(card, have, total)
  card.have, card.total = have, total
  card:ResetLook() -- a tile clicked while hovered gets no OnLeave
  card.Count:SetText(string.format(L["%d / %d"], have, total))
  card.Percent:SetText(string.format(L["%d%%"], UI.HomePercent(have, total)))
  card.Bar:SetMinMaxValues(0, math.max(total, 1))
  card.Bar:SetValue(have)
  local complete = total > 0 and have >= total
  card.Bar:SetStatusBarColor(unpack(UI.ProgressColor(have, total)))
  card.Check:SetShown(complete)
end

local function refreshHome()
  local mounts = (ns.Data and ns.Data.Mounts) or {}
  local Game = ns.Game
  -- Ask the client about each mount at most once for all tiles.
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

  for i, name in ipairs(expansions()) do
    local card = cards[i]
    if card then
      local logo = Game.ExpansionLogo(i)
      if type(logo) == "number" and logo > 0 then
        card.Logo:SetTexture(logo)
        card.Logo:Show()
        card.Name:Hide()
      else
        card.Logo:Hide()
        card.Name:Show()
      end
      local have, total = ns.Journal.Counts(mounts, name, isOwned, exists, faction, Game.MountSourceText)
      paintTile(card, have, total)
    end
  end

  local counts = UI.HomeTabCounts(mounts, isOwned, exists, faction)
  local sumHave, sumTotal = counts.all.have, counts.all.total
  local s = home.Summary
  s.have, s.total = sumHave, sumTotal
  s.Totals:SetText(string.format(L["%d / %d collected  ·  %d%%"], sumHave, sumTotal,
    UI.HomePercent(sumHave, sumTotal)))
  s.Bar:SetMinMaxValues(0, math.max(sumTotal, 1))
  s.Bar:SetValue(sumHave)
  s.Bar:SetStatusBarColor(unpack(UI.ProgressColor(sumHave, sumTotal)))
  for _, chip in ipairs(s.Chips) do
    local c = counts[chip.key]
    chip.have, chip.total = c.have, c.total
    chip.Text:SetText(string.format(L["|cffffd100%s|r  %d / %d"], L[chip.label], c.have, c.total))
    chip:SetWidth(chip.Text:GetStringWidth() + 8)
  end
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

local function createCard(i, name)
  local card = CreateFrame("Button", nil, home)
  card:SetSize(G.tileW, G.tileH)
  local col = (i - 1) % G.cols
  local row = math.floor((i - 1) / G.cols)
  card:SetPoint("TOPLEFT", home, "TOPLEFT", G.left + col * (G.tileW + G.gap), G.top - row * (G.tileH + G.gap))

  -- Flat fill and a 1 px subtle edge; no frame art (it reads as a heavy
  -- border at this size).
  local bg = card:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(card)
  bg:SetColorTexture(unpack(FILL))
  card.Bg = bg

  local edge = UI.FlatBorder(card, unpack(EDGE))
  card.Edge = edge

  -- Logo centred in the space above the bar, in a 2:1 box.
  local logo = card:CreateTexture(nil, "ARTWORK")
  logo:SetSize(LOGO_W, LOGO_H)
  logo:SetPoint("CENTER", card, "CENTER", 0, LOGO_Y)
  card.Logo = logo

  -- Fallback when the client has no logo for this expansion.
  local label = card:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalLarge"))
  label:SetPoint("CENTER", logo, "CENTER", 0, 0)
  label:SetWidth(G.tileW - 16)
  label:SetText(L[name])
  card.Name = label

  -- Bottom area: a slim bar across the tile, owned / total left, percent right.
  local count = card:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
  count:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 9)
  card.Count = count

  local pct = card:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  pct:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 9)
  card.Percent = pct

  local bar = flatBar(card, TILE_BAR_H)
  bar:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 26)
  bar:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 26)
  card.Bar = bar

  -- Completed: a small check in the top-right corner.
  local check = card:CreateTexture(nil, "OVERLAY")
  check:SetSize(18, 18)
  check:SetPoint("TOPRIGHT", card, "TOPRIGHT", -6, -6)
  if UI.AtlasExists(CHECK_ATLAS) then
    check:SetAtlas(CHECK_ATLAS)
  else
    check:SetTexture(CHECK_TEXTURE)
  end
  check:Hide()
  card.Check = check

  card:SetScript("OnEnter", function()
    bg:SetColorTexture(unpack(FILL_HOVER))
    edge:SetColor(unpack(EDGE_HOVER))
  end)
  -- Plain look; also on hide, so a tile clicked while hovered (hidden with
  -- the home, no OnLeave) does not come back from Back still lit.
  function card:ResetLook()
    bg:SetColorTexture(unpack(FILL))
    edge:SetColor(unpack(EDGE))
  end
  card:SetScript("OnLeave", card.ResetLook)
  card:SetScript("OnHide", card.ResetLook)
  card:SetScript("OnClick", function() showList(name) end)
  return card
end

-- One chip per tab under the bar: "<Tab>  owned / total", left to right;
-- hover lights it, a click opens that tab.
local function createChips(s)
  s.Chips = {}
  local prev
  for i, info in ipairs(CHIPS) do
    local chip = CreateFrame("Button", nil, s)
    chip:SetHeight(G.chipsH)
    if prev then
      chip:SetPoint("LEFT", prev, "RIGHT", G.chipGap, 0)
    else
      chip:SetPoint("TOPLEFT", s, "TOPLEFT", -4, G.chipsY)
    end
    chip.key, chip.label = info.key, info.label
    local glow = chip:CreateTexture(nil, "BACKGROUND")
    glow:SetAllPoints(chip)
    glow:SetColorTexture(1, 1, 1, 0.08)
    glow:Hide()
    chip.Glow = glow
    local text = chip:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
    text:SetPoint("LEFT", chip, "LEFT", 4, 0)
    chip.Text = text
    chip:SetScript("OnEnter", function() glow:Show() end)
    chip:SetScript("OnLeave", function() glow:Hide() end)
    chip:SetScript("OnHide", function() glow:Hide() end)
    chip:SetScript("OnClick", function() UI.SelectTab(info.key) end)
    s.Chips[i] = chip
    prev = chip
  end
end

-- The summary strip: "Mount Collection" left, the totals over every tab
-- right, a full-width 4 px gold bar along its bottom edge, the tab chips
-- below it.
local function createSummary()
  local s = CreateFrame("Frame", nil, home)
  s:SetPoint("TOPLEFT", home, "TOPLEFT", G.left, 0)
  s:SetPoint("TOPRIGHT", home, "TOPRIGHT", -G.left, 0)
  s:SetHeight(G.stripH)

  local heading = s:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalLarge"))
  heading:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -8)
  heading:SetText(L["Mount Collection"])
  s.Title = heading

  local totals = s:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlight"))
  totals:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, -10)
  s.Totals = totals

  local bar = flatBar(s, SUMMARY_BAR_H)
  bar:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
  s.Bar = bar
  createChips(s)

  -- Search box after the title; the first typed letter opens the search page.
  local search = CreateFrame("EditBox", nil, s, "SearchBoxTemplate")
  search:SetAutoFocus(false)
  search:SetSize(240, 20)
  search:SetPoint("LEFT", heading, "RIGHT", 24, 0)
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

-- Tile sizes for a home of `width` x `height` (the window can be resized):
-- the grid keeps G.cols columns and fills the space below the strip with
-- the same margins and gaps; never smaller than the
-- defaults' 80%. Unknown size (0) -> the defaults. -> tileW, tileH, logo
-- scale (against the 180 x 128 tile the logo size was drawn for).
function UI.HomeTileSize(width, height, count)
  local rows = math.max(1, math.ceil((count or 12) / G.cols))
  if not (width and width > 0 and height and height > 0) then return G.tileW, G.tileH, LOGO_BASE end
  local w = math.floor((width - 2 * G.left - (G.cols - 1) * G.gap) / G.cols)
  local h = math.floor((height + G.top - 10 - (rows - 1) * G.gap) / rows)
  w = math.max(w, math.floor(G.tileW * 0.8))
  h = math.max(h, math.floor(G.tileH * 0.8))
  return w, h, math.min(w / 180, h / 128)
end

-- Re-lays the tiles for the home's current size.
local function layoutTiles()
  if not home then return end
  local w, h, s = UI.HomeTileSize(home:GetWidth(), home:GetHeight(), #cards)
  home.tileW, home.tileH = w, h
  for i, card in ipairs(cards) do
    local col = (i - 1) % G.cols
    local row = math.floor((i - 1) / G.cols)
    card:SetSize(w, h)
    card:ClearAllPoints()
    card:SetPoint("TOPLEFT", home, "TOPLEFT", G.left + col * (w + G.gap), G.top - row * (h + G.gap))
    local ls = math.min(s, 1.6)
    card.Logo:SetSize(LOGO_W * ls, LOGO_H * ls)
    card.Logo:ClearAllPoints()
    card.Logo:SetPoint("CENTER", card, "CENTER", 0, (30 + h) / 2 - h / 2)
    card.Name:SetWidth(w - 16)
  end
end
UI.HomeLayoutTiles = layoutTiles

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

-- The list page's mounts (UI.List's select): the list's mounts the list gate
-- keeps (owned ones too: Collected decides), grouped by source in
-- Journal.SOURCE_ORDER, then by name; the search box narrows by name.
local function myListSelect(mounts, query)
  local ids = currentList and listMounts(currentList) or {}
  local needle = query.search and string.lower(query.search) or ""
  -- The home page's fuzzy search (tbc, a boss, a zone...).
  local match = UI.SearchMatches and UI.SearchMatches(ids, query.search, query.sourceText) or nil
  local out = {}
  for _, id in ipairs(ids) do
    local m = mounts[id]
    if m and ns.Journal.Gate(id, m, query.isOwned, query.exists, query.faction, true) ~= nil then
      local name = (ns.Game.MountInfo and ns.Game.MountInfo(id)) or m.name or ""
      local hit
      if match then hit = match[id] == true else hit = needle == "" or string.find(string.lower(name), needle, 1, true) end
      if hit then
        out[#out + 1] = { id = id, m = m, section = m.section or "other", name = string.lower(name) }
      end
    end
  end
  table.sort(out, function(a, b)
    local ra, rb = ns.Journal.SourceRank(a.section), ns.Journal.SourceRank(b.section)
    if ra ~= rb then return ra < rb end
    if a.name ~= b.name then return a.name < b.name end
    return a.id < b.id
  end)
  return out
end

-- A page under a flat strip with Back and a title -> page, holder, back, title.
local function pageWithStrip(parent)
  local page = CreateFrame("Frame", nil, parent)
  page:SetAllPoints(parent)
  page:Hide()
  local strip = page:CreateTexture(nil, "BACKGROUND")
  strip:SetPoint("TOPLEFT", page, "TOPLEFT", 0, 0)
  strip:SetPoint("TOPRIGHT", page, "TOPRIGHT", 0, 0)
  strip:SetHeight(30)
  strip:SetColorTexture(1, 1, 1, 0.04)
  local back = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
  back:SetSize(80, 22)
  back:SetPoint("TOPLEFT", page, "TOPLEFT", 4, -4)
  back:SetText(L["Back"])
  local t = page:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalLarge"))
  t:SetPoint("LEFT", back, "RIGHT", 12, 0)
  local holder = CreateFrame("Frame", nil, page)
  holder:SetPoint("TOPLEFT", page, "TOPLEFT", 0, -36)
  holder:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", 0, 0)
  return page, holder, back, t
end

local function build(parent)
  home = CreateFrame("Frame", nil, parent)
  home:SetAllPoints(parent)
  -- Tiles first, so home.children[i] is expansion i's tile.
  for i, name in ipairs(expansions()) do
    cards[i] = createCard(i, name)
  end
  home.Summary = createSummary()
  layoutTiles()
  home:SetScript("OnSizeChanged", layoutTiles)

  listPage = CreateFrame("Frame", nil, parent)
  listPage:SetAllPoints(parent)
  listPage:Hide()

  -- Flat header strip: Back (UIPanelButtonTemplate, which carries the
  -- current red button art since Dragonflight) and the expansion name.
  local strip = listPage:CreateTexture(nil, "BACKGROUND")
  strip:SetPoint("TOPLEFT", listPage, "TOPLEFT", 0, 0)
  strip:SetPoint("TOPRIGHT", listPage, "TOPRIGHT", 0, 0)
  strip:SetHeight(30)
  strip:SetColorTexture(1, 1, 1, 0.04)
  local rule = listPage:CreateTexture(nil, "BORDER")
  rule:SetHeight(1)
  rule:SetPoint("TOPLEFT", strip, "BOTTOMLEFT", 0, 0)
  rule:SetPoint("TOPRIGHT", strip, "BOTTOMRIGHT", 0, 0)
  rule:SetColorTexture(1, 1, 1, 0.1)

  local back = CreateFrame("Button", nil, listPage, "UIPanelButtonTemplate")
  back:SetSize(80, 22)
  back:SetPoint("TOPLEFT", listPage, "TOPLEFT", 4, -4)
  back:SetText(L["Back"])
  back:SetScript("OnClick", showHome)

  title = listPage:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalLarge"))
  title:SetPoint("LEFT", back, "RIGHT", 12, 0)

  local holder = CreateFrame("Frame", nil, listPage)
  holder:SetPoint("TOPLEFT", listPage, "TOPLEFT", 0, -36)
  holder:SetPoint("BOTTOMRIGHT", listPage, "BOTTOMRIGHT", 0, 0)
  list = UI.List(holder, function()
    return { view = "journal", exp = currentExp, sourceText = ns.Game.MountSourceText }
  end)

  searchPage = CreateFrame("Frame", nil, parent)
  searchPage:SetAllPoints(parent)
  searchPage:Hide()
  local sStrip = searchPage:CreateTexture(nil, "BACKGROUND")
  sStrip:SetPoint("TOPLEFT", searchPage, "TOPLEFT", 0, 0)
  sStrip:SetPoint("TOPRIGHT", searchPage, "TOPRIGHT", 0, 0)
  sStrip:SetHeight(30)
  sStrip:SetColorTexture(1, 1, 1, 0.04)
  local sBack = CreateFrame("Button", nil, searchPage, "UIPanelButtonTemplate")
  sBack:SetSize(80, 22)
  sBack:SetPoint("TOPLEFT", searchPage, "TOPLEFT", 4, -4)
  sBack:SetText(L["Back"])
  local sTitle = searchPage:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormalLarge"))
  sTitle:SetPoint("LEFT", sBack, "RIGHT", 12, 0)
  sTitle:SetText(L["Search all mounts"])
  local sHolder = CreateFrame("Frame", nil, searchPage)
  sHolder:SetPoint("TOPLEFT", searchPage, "TOPLEFT", 0, -36)
  sHolder:SetPoint("BOTTOMRIGHT", searchPage, "BOTTOMRIGHT", 0, 0)
  searchList = UI.List(sHolder, function()
    return { view = "search", sourceText = ns.Game.MountSourceText }
  end, { select = searchSelect })
  searchPage.List = searchList
  sBack:SetScript("OnClick", function()
    searchList.SearchBox:SetText("")
    showHome()
  end)

  -- A list's page (a home card's click): its mounts as a list by source.
  local mHolder, mBack
  myListPage, mHolder, mBack, myListTitle = pageWithStrip(parent)
  mBack:SetScript("OnClick", showHome)
  local pop = CreateFrame("Button", nil, myListPage, "UIPanelButtonTemplate")
  pop:SetSize(90, 22)
  pop:SetPoint("TOPRIGHT", myListPage, "TOPRIGHT", -4, -4)
  pop:SetText(L["Pop out"])
  pop:SetScript("OnClick", function() if currentList and UI.OpenPopout then UI.OpenPopout(currentList) end end)
  myListPage.PopOut = pop
  myList = UI.List(mHolder, function()
    local key = currentList and (currentList.kind == "quick" and ("q" .. tostring(currentList.key))
      or tostring(currentList.list)) or ""
    return { view = "mylist", exp = key, sourceText = ns.Game.MountSourceText }
  end, { select = myListSelect })
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
