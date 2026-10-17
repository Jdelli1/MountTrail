local ADDON, ns = ...

-- Journal tab: a home grid of expansion cards (logo, owned / total, progress
-- bar); clicking a card opens that expansion's mount list, and Back returns.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local COLS = 4
local CARD_W, CARD_H = 182, 146
local GAP = 10
local LEFT, TOP = 12, -12
local LOGO_W, LOGO_H = 160, 80

local home, listPage, list, title
local cards = {}
local currentExp

local function expansions()
  return (ns.Data and ns.Data.Expansions) or {}
end

local function refreshHome()
  local mounts = (ns.Data and ns.Data.Mounts) or {}
  local Game = ns.Game
  -- Ask the client about each mount at most once for all cards.
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
      card.Count:SetText(string.format(L["%d / %d"], have, total))
      card.Bar:SetMinMaxValues(0, math.max(total, 1))
      card.Bar:SetValue(have)
    end
  end
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
  card:SetSize(CARD_W, CARD_H)
  local col = (i - 1) % COLS
  local row = math.floor((i - 1) / COLS)
  card:SetPoint("TOPLEFT", home, "TOPLEFT", LEFT + col * (CARD_W + GAP), TOP - row * (CARD_H + GAP))

  local bg = card:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints(card)
  bg:SetColorTexture(0, 0, 0, 0.35)

  local highlight = card:CreateTexture(nil, "HIGHLIGHT")
  highlight:SetAllPoints(card)
  highlight:SetColorTexture(1, 1, 1, 0.08)

  local logo = card:CreateTexture(nil, "ARTWORK")
  logo:SetSize(LOGO_W, LOGO_H)
  logo:SetPoint("TOP", card, "TOP", 0, -8)
  card.Logo = logo

  -- Fallback when the client has no logo for this expansion.
  local label = card:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  label:SetPoint("CENTER", logo, "CENTER", 0, 0)
  label:SetWidth(CARD_W - 12)
  label:SetText(L[name])
  card.Name = label

  local bar = CreateFrame("StatusBar", nil, card)
  bar:SetSize(CARD_W - 24, 12)
  bar:SetPoint("BOTTOM", card, "BOTTOM", 0, 12)
  bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  bar:SetStatusBarColor(0.2, 0.75, 0.2)
  bar:SetMinMaxValues(0, 1)
  bar:SetValue(0)
  local barBg = bar:CreateTexture(nil, "BACKGROUND")
  barBg:SetAllPoints(bar)
  barBg:SetColorTexture(0, 0, 0, 0.6)
  card.Bar = bar

  local count = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  count:SetPoint("BOTTOM", bar, "TOP", 0, 6)
  card.Count = count

  card:SetScript("OnClick", function() showList(name) end)
  return card
end

local function build(parent)
  home = CreateFrame("Frame", nil, parent)
  home:SetAllPoints(parent)
  for i, name in ipairs(expansions()) do
    cards[i] = createCard(i, name)
  end

  listPage = CreateFrame("Frame", nil, parent)
  listPage:SetAllPoints(parent)
  listPage:Hide()

  local back = CreateFrame("Button", nil, listPage, "UIPanelButtonTemplate")
  back:SetSize(80, 22)
  back:SetPoint("TOPLEFT", listPage, "TOPLEFT", 4, -4)
  back:SetText(L["Back"])
  back:SetScript("OnClick", showHome)

  title = listPage:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("LEFT", back, "RIGHT", 12, 0)

  local holder = CreateFrame("Frame", nil, listPage)
  holder:SetPoint("TOPLEFT", listPage, "TOPLEFT", 0, -32)
  holder:SetPoint("BOTTOMRIGHT", listPage, "BOTTOMRIGHT", 0, 0)
  list = UI.List(holder, function()
    return { tab = "journal", exp = currentExp, sourceText = ns.Game.MountSourceText }
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
