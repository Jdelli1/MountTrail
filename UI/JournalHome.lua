local ADDON, ns = ...

-- Journal tab: a front page with a slim summary strip (title, collected
-- totals over every expansion, a 4 px gold bar) above a 4 x 3 grid of flat
-- expansion tiles (logo, a 3 px bar, owned / total and percent); clicking a
-- tile opens that expansion's mount list, and Back returns.
-- Tiles follow the current flat panel style: a dark flat fill with a 1 px
-- subtle edge; hover brightens the fill and turns the edge gold. A completed
-- expansion gets a green bar and a check in its top-right corner.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

-- Layout. The content area of the 800 x 560 window is 780 x 486 (inset 6 px
-- in and 60 px down for the portrait and top tabs, content 4 px inside it).
-- Strip: title and totals in the top 32 px, the bar at 32-36 px. Grid from
-- 48 px down: 12 + 4 x 180 + 3 x 12 = 768 wide (12 px right margin) and
-- 48 + 3 x 134 + 2 x 12 = 474 tall (12 px bottom margin).
local G = {
  cols = 4,
  tileW = 180, tileH = 134,
  gap = 12,
  left = 12, top = -48,
  stripH = 36,
}
UI.HomeLayout = G

local LOGO_W, LOGO_H = 150, 75 -- 2:1, the shape of the client's expansion logos
local LOGO_Y = 15 -- centre of the area above the bar: (30 + 134) / 2 - 134 / 2
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
local cards = {}
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

  local sumHave, sumTotal = 0, 0
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
      sumHave, sumTotal = sumHave + have, sumTotal + total
    end
  end

  local s = home.Summary
  s.have, s.total = sumHave, sumTotal
  s.Totals:SetText(string.format(L["%d / %d collected  ·  %d%%"], sumHave, sumTotal,
    UI.HomePercent(sumHave, sumTotal)))
  s.Bar:SetMinMaxValues(0, math.max(sumTotal, 1))
  s.Bar:SetValue(sumHave)
end

local function showHome()
  currentExp = nil
  listPage:Hide()
  home:Show()
  refreshHome()
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
  card:SetScript("OnLeave", function()
    bg:SetColorTexture(unpack(FILL))
    edge:SetColor(unpack(EDGE))
  end)
  card:SetScript("OnClick", function() showList(name) end)
  return card
end

-- The summary strip: "Mount Journal" left, the totals right, a full-width
-- 4 px gold bar along its bottom edge.
local function createSummary()
  local s = CreateFrame("Frame", nil, home)
  s:SetPoint("TOPLEFT", home, "TOPLEFT", G.left, 0)
  s:SetPoint("TOPRIGHT", home, "TOPRIGHT", -G.left, 0)
  s:SetHeight(G.stripH)

  local heading = s:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  heading:SetPoint("TOPLEFT", s, "TOPLEFT", 0, -8)
  heading:SetText(L["Mount Journal"])
  s.Title = heading

  local totals = s:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  totals:SetPoint("TOPRIGHT", s, "TOPRIGHT", 0, -10)
  s.Totals = totals

  local bar = flatBar(s, SUMMARY_BAR_H)
  bar:SetPoint("BOTTOMLEFT", s, "BOTTOMLEFT", 0, 0)
  bar:SetPoint("BOTTOMRIGHT", s, "BOTTOMRIGHT", 0, 0)
  s.Bar = bar
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
end

local function refresh()
  if not home then return end
  if listPage:IsShown() then
    list:Refresh()
  else
    refreshHome()
  end
end

UI.RegisterView("journal", { Build = build, Refresh = refresh })
