local ADDON, ns = ...

-- Journal tab: a front page in the pop-outs' look. A slim summary strip
-- (title, collected totals over every tab's mounts, a search box, a 4 px
-- bar) over two columns:
--   left   "Expansions": one row per expansion (its tag, its name in its
--          colour, a bar, owned / total and percent; a click opens its mount
--          list, Back returns), then "By source": the same rows for the
--          Journal, Holidays, Achievements, Timewalking and Misc tabs (a
--          click opens that tab);
--   right  "Today": the daily / weekly lockouts and rare spawns left and the
--          player's lists with lockouts open (a click opens them);
--          "Following": the guide being followed, its step and Resume;
--          "Nearby": the first mounts still to get in the player's zone
--          (Zone.MountsFor, worked out again on a new zone or once a minute;
--          a click is the waypoint, the last line opens Current Zone).
-- Every bar takes its completion colour (UI.ProgressColor); a complete row
-- gets a check. Headings are a pop-out's group headers (UI.HeaderColor).
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

-- Layout: margins, the strip, the right column's width, row heights.
local G = {
  left = 12, top = -48, stripH = 36,
  sideW = 230, gap = 20,
  row = 22, heading = 22, sectionGap = 10,
}
UI.HomeLayout = G

local SUMMARY_BAR_H, ROW_BAR_H = 4, 6
local BAR_TEXTURE = "Interface\\Buttons\\WHITE8X8" -- flat fill, tinted below
local GOLD = { 1, 0.82, 0, 1 }
local GREEN = { 0.25, 0.78, 0.35, 1 }
local GREEN_TEXT = "|cff40c040"
local GREY_TEXT = "|cff9d9d9d"
local NEARBY_MAX, TODAY_LISTS_MAX = 5, 3
local NEARBY_TTL = 60 -- seconds the Nearby list is kept for one zone

-- Progress colours (rows and the summary bar): red under 25 %, yellow
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
local currentExp

-- The tabs that list mounts, in tab order; the summary counts all of them
-- and "By source" has a row each.
local SOURCES = {
  { key = "journal", label = "Journal" },
  { key = "holidays", label = "Holidays" },
  { key = "achievements", label = "Achievements" },
  { key = "timewalking", label = "Timewalking" },
  { key = "misc", label = "Misc" },
}
UI.HomeSources = SOURCES

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
-- plus all = the sum over the SOURCES tabs.
function UI.HomeTabCounts(mounts, isOwned, exists, faction)
  local out = { all = { have = 0, total = 0 } }
  for _, src in ipairs(SOURCES) do out[src.key] = { have = 0, total = 0 } end
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

-- A heading, as a pop-out's group header: its text in the header colour
-- over a thin rule of it (repainted with the window's appearance).
local function heading(parent, text)
  local h = CreateFrame("Frame", nil, parent)
  h:SetHeight(G.heading)
  local fs = h:CreateFontString(nil, "OVERLAY", UI.Font("GameFontNormal"))
  fs:SetPoint("LEFT", h, "LEFT", 2, 0)
  fs:SetText(text)
  h.Text = fs
  local rule = h:CreateTexture(nil, "BORDER")
  rule:SetHeight(1)
  rule:SetPoint("BOTTOMLEFT", h, "BOTTOMLEFT", 0, 1)
  rule:SetPoint("BOTTOMRIGHT", h, "BOTTOMRIGHT", 0, 1)
  h.Rule = rule
  return h
end

local function paintHeading(h)
  local c = UI.HeaderColor and UI.HeaderColor({ depth = 1 }) or GOLD
  h.Text:SetTextColor(c[1], c[2], c[3])
  h.Rule:SetColorTexture(c[1], c[2], c[3], 0.35)
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

-- A progress row: [tag] name, a bar, owned / total and percent; a check
-- once complete. withTag: room for an expansion tag before the name.
local function progressRow(parent, i, withTag)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(G.row)
  rowLook(b, i % 2 == 0)
  local nameLeft = 4
  if withTag then
    local tag = UI.ExpansionBadge(b)
    tag:SetPoint("LEFT", b, "LEFT", 4, 0)
    b.Tag = tag
    nameLeft = 4 + 46
  end
  local name = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlight"))
  name:SetPoint("LEFT", b, "LEFT", nameLeft, 0)
  name:SetWidth(withTag and 150 or 190)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  b.Name = name
  local pct = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  pct:SetPoint("RIGHT", b, "RIGHT", -4, 0)
  pct:SetWidth(36)
  pct:SetJustifyH("RIGHT")
  b.Percent = pct
  local count = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
  count:SetPoint("RIGHT", pct, "LEFT", -6, 0)
  count:SetWidth(70)
  count:SetJustifyH("RIGHT")
  b.Count = count
  local check = b:CreateTexture(nil, "OVERLAY")
  check:SetSize(14, 14)
  check:SetPoint("RIGHT", count, "LEFT", -4, 0)
  if UI.AtlasExists(CHECK_ATLAS) then check:SetAtlas(CHECK_ATLAS) else check:SetTexture(CHECK_TEXTURE) end
  check:Hide()
  b.Check = check
  local bar = flatBar(b, ROW_BAR_H)
  bar:SetPoint("LEFT", name, "RIGHT", 8, 0)
  bar:SetPoint("RIGHT", check, "LEFT", -6, 0)
  b.Bar = bar
  return b
end

local function paintProgress(b, have, total)
  b.have, b.total = have, total
  b.Count:SetText(string.format(L["%d / %d"], have, total))
  b.Percent:SetText(string.format(L["%d%%"], UI.HomePercent(have, total)))
  b.Bar:SetMinMaxValues(0, math.max(total, 1))
  b.Bar:SetValue(have)
  b.Bar:SetStatusBarColor(unpack(UI.ProgressColor(have, total)))
  b.Check:SetShown(total > 0 and have >= total)
end

-- A text row of the right column: a label left, a value right.
local function sideRow(parent, i)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(G.row)
  rowLook(b, false)
  local value = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
  value:SetPoint("RIGHT", b, "RIGHT", -4, 0)
  value:SetJustifyH("RIGHT")
  b.Value = value
  local label = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlight"))
  label:SetPoint("LEFT", b, "LEFT", 4, 0)
  label:SetPoint("RIGHT", value, "LEFT", -6, 0)
  label:SetJustifyH("LEFT")
  label:SetWordWrap(false)
  b.Label = label
  b:SetScript("OnClick", function(self) if self.onClick then self.onClick() end end)
  return b
end

-- A Nearby row: the mount's expansion tag and name; a click is the
-- waypoint, the hover its tooltip.
local function nearbyRow(parent)
  local b = CreateFrame("Button", nil, parent)
  b:SetHeight(G.row)
  rowLook(b, false)
  local tag = UI.ExpansionBadge(b)
  tag:SetPoint("LEFT", b, "LEFT", 4, 0)
  b.Tag = tag
  local name = b:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlight"))
  name:SetPoint("LEFT", b, "LEFT", 4 + 46, 0)
  name:SetPoint("RIGHT", b, "RIGHT", -4, 0)
  name:SetJustifyH("LEFT")
  name:SetWordWrap(false)
  b.Name = name
  b:SetScript("OnClick", function(self) if self.mountID and UI.GoTo then UI.GoTo(self.mountID) end end)
  b:SetScript("OnEnter", function(self) if self.mountID then UI.ShowMountTooltip(self, self.mountID) end end)
  b:SetScript("OnLeave", function() UI.HideMountTooltip() end)
  return b
end

-- The right column's parts, placed top to bottom by their contents.
local function place(f, side, y, h)
  f:ClearAllPoints()
  f:SetPoint("TOPLEFT", side, "TOPLEFT", 0, -y)
  f:SetPoint("TOPRIGHT", side, "TOPRIGHT", 0, -y)
  if h then f:SetHeight(h) end
  f:Show()
  return y + (h or f:GetHeight() or G.row)
end

-- Today's rows -> { { label =, value =, open = bool, click = fn } }: the
-- daily / weekly lockouts and rare spawns left (Lockouts on that group),
-- then the player's lists with lockouts open today (at most
-- TODAY_LISTS_MAX; their page).
function UI.HomeToday(built, filters, lists)
  local left = UI.ChecklistLeft and UI.ChecklistLeft(built or {}, filters) or {}
  local out = {}
  for _, g in ipairs(UI.NAV_LOCKOUT_GROUPS or {}) do
    local n = left[g.show] or 0
    out[#out + 1] = { label = L[g.label], value = string.format(L["%d left"], n), open = n > 0,
      click = function() UI.NavClick({ show = g.show }) end }
  end
  local shown = 0
  for _, l in ipairs(lists or {}) do
    if shown >= TODAY_LISTS_MAX then break end
    if l.open > 0 then
      shown = shown + 1
      out[#out + 1] = { label = l.name, value = string.format(L["%d left"], l.open), open = true,
        click = function() UI.NavClick({ source = l.source }) end }
    end
  end
  return out
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
  local y = 0
  -- Today.
  paintHeading(side.TodayHeading)
  y = place(side.TodayHeading, side, y, G.heading)
  local built = UI.ChecklistBuild and UI.ChecklistBuild(Game.Now()) or {}
  local char = ns.db and ns.db.char
  local filters = char and type(char.checklistFilters) == "table" and char.checklistFilters or nil
  local lists = {}
  local store = UI.ListsDB and UI.ListsDB()
  for _, l in ipairs(store and ns.Lists.Sorted(store) or {}) do
    local source = { kind = "list", list = l.id }
    local stats = UI.ListCardStatsFor and UI.ListCardStatsFor(source, built) or { open = 0 }
    lists[#lists + 1] = { name = l.name, open = stats.open, source = source }
  end
  local today = UI.HomeToday(built, filters, lists)
  for i, t in ipairs(today) do
    local b = side.Today[i] or sideRow(side, i)
    side.Today[i] = b
    b.Label:SetText(t.label)
    b.Value:SetText((t.open and GREEN_TEXT or GREY_TEXT) .. t.value .. "|r")
    b.onClick = t.click
    y = place(b, side, y, G.row)
  end
  for i = #today + 1, #side.Today do side.Today[i]:Hide() end
  y = y + G.sectionGap

  -- Following.
  paintHeading(side.FollowHeading)
  y = place(side.FollowHeading, side, y, G.heading)
  local entry, n
  if UI.ActiveGuide then entry, n = UI.ActiveGuide() end
  local f = side.Follow
  if entry then
    local steps = entry.guide.steps
    f.Title:SetText(entry.title)
    local step = steps[n]
    f.Step:SetText(string.format(L["Step %d of %d"], n, #steps)
      .. (step and step.text and ("  " .. GREY_TEXT .. UI.GuideText(step.text) .. "|r") or ""))
    f.Bar:SetMinMaxValues(0, math.max(#steps, 1))
    f.Bar:SetValue(n)
    f.Title:Show()
    f.Step:Show()
    f.Bar:Show()
    f.Resume:Show()
    f.None:Hide()
    y = place(f, side, y, 70)
  else
    f.Title:Hide()
    f.Step:Hide()
    f.Bar:Hide()
    f.Resume:Hide()
    f.None:Show()
    y = place(f, side, y, 34)
  end
  y = y + G.sectionGap

  -- Nearby.
  paintHeading(side.NearbyHeading)
  y = place(side.NearbyHeading, side, y, G.heading)
  local near, zone = UI.HomeNearby(Game.Now())
  for i = 1, NEARBY_MAX do
    local b = side.Nearby[i] or nearbyRow(side)
    side.Nearby[i] = b
    local e = near[i]
    if e then
      b.mountID = e.id
      UI.SetExpansionBadge(b.Tag, e.m and e.m.exp)
      b.Tag:EnableMouse(false)
      b.Name:SetText(Game.MountInfo(e.id) or (e.m and e.m.name) or tostring(e.id))
      y = place(b, side, y, G.row)
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
  place(more, side, y, G.row)
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
      UI.SetExpansionBadge(b.Tag, name)
      b.Tag:EnableMouse(false) -- the row takes the clicks
      local c = UI.EXPANSION_COLORS and UI.EXPANSION_COLORS[name]
      if c then b.Name:SetTextColor(c[1], c[2], c[3]) end
      local have, total = ns.Journal.Counts(mounts, name, isOwned, exists, faction, Game.MountSourceText)
      paintProgress(b, have, total)
    end
  end

  local counts = UI.HomeTabCounts(mounts, isOwned, exists, faction)
  paintHeading(home.SourceHeading)
  for _, b in ipairs(home.Sources) do
    local c = counts[b.key]
    paintProgress(b, c.have, c.total)
  end
  local sumHave, sumTotal = counts.all.have, counts.all.total
  local s = home.Summary
  s.have, s.total = sumHave, sumTotal
  s.Totals:SetText(string.format(L["%d / %d collected  ·  %d%%"], sumHave, sumTotal,
    UI.HomePercent(sumHave, sumTotal)))
  s.Bar:SetMinMaxValues(0, math.max(sumTotal, 1))
  s.Bar:SetValue(sumHave)
  s.Bar:SetStatusBarColor(unpack(UI.ProgressColor(sumHave, sumTotal)))
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

  -- Search box after the title; the first typed letter opens the search page.
  local search = CreateFrame("EditBox", nil, s, "SearchBoxTemplate")
  search:SetAutoFocus(false)
  search:SetSize(220, 20)
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

-- The left column: Expansions and By source, one progress row each.
local function createColumns()
  local main = CreateFrame("Frame", nil, home)
  main:SetPoint("TOPLEFT", home, "TOPLEFT", G.left, G.top)
  main:SetPoint("BOTTOMRIGHT", home, "BOTTOMRIGHT", -(G.left + G.sideW + G.gap), 0)
  home.Main = main
  local y = 0
  local function add(f, h)
    f:SetPoint("TOPLEFT", main, "TOPLEFT", 0, -y)
    f:SetPoint("TOPRIGHT", main, "TOPRIGHT", 0, -y)
    y = y + h
  end
  home.ExpHeading = heading(main, L["Expansions"])
  add(home.ExpHeading, G.heading)
  home.Expansions = {}
  for i, name in ipairs(expansions()) do
    local b = progressRow(main, i, true)
    b.Name:SetText(L[name])
    b.exp = name
    b:SetScript("OnClick", function() showList(name) end)
    add(b, G.row)
    home.Expansions[i] = b
  end
  y = y + G.sectionGap
  home.SourceHeading = heading(main, L["By source"])
  add(home.SourceHeading, G.heading)
  home.Sources = {}
  for i, src in ipairs(SOURCES) do
    local b = progressRow(main, i, false)
    b.key = src.key
    b.Name:SetText(L[src.label])
    b.Name:SetTextColor(GOLD[1], GOLD[2], GOLD[3])
    b:SetScript("OnClick", function() UI.SelectTab(src.key) end)
    add(b, G.row)
    home.Sources[i] = b
  end
  home.mainHeight = y

  -- The right column: Today, Following, Nearby (placed by refreshSide).
  local side = CreateFrame("Frame", nil, home)
  side:SetPoint("TOPRIGHT", home, "TOPRIGHT", -G.left, G.top)
  side:SetPoint("BOTTOMRIGHT", home, "BOTTOMRIGHT", -G.left, 0)
  side:SetWidth(G.sideW)
  home.Side = side
  side.TodayHeading = heading(side, L["Today"])
  side.Today = {}
  side.FollowHeading = heading(side, L["Following"])
  local f = CreateFrame("Frame", nil, side)
  local ft = f:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlight"))
  ft:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
  ft:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  ft:SetJustifyH("LEFT")
  ft:SetWordWrap(false)
  f.Title = ft
  local fs = f:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
  fs:SetPoint("TOPLEFT", ft, "BOTTOMLEFT", 0, -3)
  fs:SetPoint("TOPRIGHT", ft, "BOTTOMRIGHT", 0, -3)
  fs:SetJustifyH("LEFT")
  fs:SetWordWrap(false)
  f.Step = fs
  local fb = flatBar(f, 4)
  fb:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -5)
  fb:SetPoint("TOPRIGHT", fs, "BOTTOMRIGHT", 0, -5)
  fb:SetStatusBarColor(unpack(GOLD))
  f.Bar = fb
  local resume = UI.FlatButton(f, L["Resume guide"], "green", 18)
  resume:SetPoint("TOPLEFT", fb, "BOTTOMLEFT", 0, -6)
  resume:SetScript("OnClick", function() if UI.ShowGuideWindow then UI.ShowGuideWindow(true) end end)
  f.Resume = resume
  local none = f:CreateFontString(nil, "OVERLAY", UI.Font("GameFontDisableSmall"))
  none:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -4)
  none:SetPoint("TOPRIGHT", f, "TOPRIGHT", -4, -4)
  none:SetJustifyH("LEFT")
  none:SetText(L["No guide followed: pick one under Guides."])
  f.None = none
  side.Follow = f
  side.NearbyHeading = heading(side, L["Nearby"])
  side.Nearby = {}
  local more = CreateFrame("Button", nil, side)
  more:SetHeight(G.row)
  local mt = more:CreateFontString(nil, "OVERLAY", UI.Font("GameFontHighlightSmall"))
  mt:SetPoint("LEFT", more, "LEFT", 4, 0)
  mt:SetPoint("RIGHT", more, "RIGHT", -4, 0)
  mt:SetJustifyH("LEFT")
  mt:SetWordWrap(false)
  more.Text = mt
  function more:SetText(text) self.Text:SetText(text) end
  more:SetScript("OnClick", function() UI.SelectTab("here") end)
  side.NearbyMore = more
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
