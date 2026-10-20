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

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

-- Layout. The content area of the 800 x 560 window is 780 x 486 (inset 6 px
-- in and 60 px down for the portrait and top tabs, content 4 px inside it).
-- Strip: title and totals in the top 32 px, the bar at 32-36 px, the tab
-- chips at 42-58 px. Grid from 68 px down: 12 + 4 x 180 + 3 x 12 = 768 wide
-- (12 px right margin) and 68 + 3 x 128 + 2 x 12 = 476 tall (10 px bottom
-- margin).
local G = {
  cols = 4,
  tileW = 180, tileH = 128,
  gap = 12,
  left = 12, top = -68,
  stripH = 36,
  chipsY = -42, chipsH = 16, chipGap = 18,
}
UI.HomeLayout = G

local LOGO_W, LOGO_H = 150, 75 -- 2:1, the shape of the client's expansion logos
local LOGO_Y = 15 -- centre of the area above the bar: (30 + 128) / 2 - 128 / 2
local TILE_BAR_H, SUMMARY_BAR_H = 3, 4
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8" -- flat fill, tinted below
local FILL = { 0.07, 0.07, 0.08, 0.9 }
local FILL_HOVER = { 0.12, 0.12, 0.14, 0.95 }
local EDGE = { 1, 1, 1, 0.1 }
local EDGE_HOVER = { 1, 0.82, 0, 0.6 }
local GOLD = { 1, 0.82, 0, 1 }
local GREEN = { 0.25, 0.78, 0.35, 1 }
local TRACK = { 0, 0, 0, 0.5 }
-- The Great Vault's completed-activity check (Blizzard_WeeklyRewards.xml,
-- CompletedIcon); GreenCheckMarkTemplate's texture where the atlas is missing.
local CHECK_ATLAS = "activities-icon-checkmark"
local CHECK_TEXTURE = "Interface\\Scenarios\\ScenarioIcon-Check"

local home, listPage, list, title
local searchPage, searchList
local searchCache = {} -- Search.Prepare output by mount ID, reset per visit
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
  card.Bar:SetStatusBarColor(unpack(complete and GREEN or GOLD))
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
  for _, chip in ipairs(s.Chips) do
    local c = counts[chip.key]
    chip.have, chip.total = c.have, c.total
    chip.Text:SetText(string.format(L["|cffffd100%s|r  %d / %d"], L[chip.label], c.have, c.total))
    chip:SetWidth(chip.Text:GetStringWidth() + 8)
  end
end

local function showHome()
  currentExp = nil
  listPage:Hide()
  searchPage:Hide()
  home:Show()
  refreshHome()
end

-- Search.Select over every mount through the list gate, with each mount's
-- UI.SearchFields (memoised per visit in searchCache).
local function searchSelect(mounts, query)
  local ctx = { sourceText = query.sourceText, mapName = ns.Game.MapName }
  return ns.Search.Select(mounts, {
    search = query.search,
    cache = searchCache,
    gate = function(id, m)
      return ns.Journal.Gate(id, m, query.isOwned, query.exists, query.faction, query.showUnobtainable)
    end,
    fields = function(id, m) return UI.SearchFields(id, m, ctx) end,
  })
end

-- Opens the search page with `text` in its box (focused, so typing goes on
-- there) and clears the home box.
local function showSearch(text)
  searchCache = {}
  home:Hide()
  listPage:Hide()
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
  local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  label:SetPoint("CENTER", logo, "CENTER", 0, 0)
  label:SetWidth(G.tileW - 16)
  label:SetText(L[name])
  card.Name = label

  -- Bottom area: a slim bar across the tile, owned / total left, percent right.
  local count = card:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  count:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", 10, 9)
  card.Count = count

  local pct = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
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
    local text = chip:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
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

  local heading = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  heading:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -8)
  heading:SetText(L["Mount Collection"])
  s.Title = heading

  local totals = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
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

local function build(parent)
  home = CreateFrame("Frame", nil, parent)
  home:SetAllPoints(parent)
  -- Tiles first, so home.children[i] is expansion i's tile.
  for i, name in ipairs(expansions()) do
    cards[i] = createCard(i, name)
  end
  home.Summary = createSummary()

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

  title = listPage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
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
  local sTitle = searchPage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
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
end

local function refresh()
  if not home then return end
  if searchPage:IsShown() then
    searchList:Refresh()
  elseif listPage:IsShown() then
    list:Refresh()
  else
    refreshHome()
  end
end

UI.RegisterView("journal", { Build = build, Refresh = refresh })
