-- The Journal front page (UI/JournalHome.lua) built under the widget stub:
-- summary strip (title, totals, search, 4 px bar), the Expansions and By
-- source progress rows, and the Today / Following / Nearby column.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/JournalHome.lua", "UI/BrowseView.lua" }

-- Widget methods the home and the list page call that the base stub lacks;
-- the StatusBar ones record what they were given.
local probe = CreateFrame("Frame")
local FrameMT = getmetatable(probe)
local RegionMT = getmetatable(FrameMT).__index
local function noop() end
for _, name in ipairs({ "SetTexCoord", "SetJustifyH", "SetWordWrap", "SetDesaturated", "SetTextColor",
  "SetStatusBarTexture", "SetDrawLayer", "SetRotation", "AddMaskTexture", "SetVertexColor" }) do
  RegionMT[name] = RegionMT[name] or noop
end
function RegionMT:SetStatusBarColor(r, g, b, a) self.barColor = { r, g, b, a } end
function RegionMT:SetMinMaxValues(lo, hi) self.min, self.max = lo, hi end
function RegionMT:SetValue(v) self.value = v end
function RegionMT:SetFontObject(font) self.font = font end
function RegionMT:GetStringWidth() return 60 end
function RegionMT:GetWidth() return self.width or 0 end
function FrameMT:RegisterForClicks(...) self.clickButtons = { ... } end
function FrameMT:IsMouseOver() return true end
for _, name in ipairs({ "SetAutoFocus", "LockHighlight", "UnlockHighlight" }) do
  FrameMT[name] = FrameMT[name] or noop
end
function FrameMT:SetChecked(on) self.checked = on end
function FrameMT:GetChecked() return self.checked end
function FrameMT:SetEnabled(on) self.enabled = on end
function FrameMT:CreateMaskTexture() return self:CreateTexture(nil, "ARTWORK") end
function FrameMT:SetDataProvider(provider) self.provider = provider end
function CreateScrollBoxListLinearView()
  local view = {}
  function view:SetElementExtentCalculator(fn) self.extent = fn end
  function view:SetElementFactory(fn) self.factory = fn end
  return view
end
ScrollUtil = { InitScrollBoxListWithScrollBar = function(box, bar, view) box.view = view end }
function CreateDataProvider(rows) return { rows = rows } end
IsControlKeyDown = function() return false end
GameFontHighlightSmall = { name = "GameFontHighlightSmall" }
function CreateFont(name)
  local font = { name = name }
  function font:SetFontObject(base) self.base = base end
  function font:SetTextColor(r, g, b) self.color = { r, g, b } end
  _G[name] = font
  return font
end
MenuResponse = { Refresh = 2 }
STUB_TEMPLATE_METHODS.WowStyle1FilterDropdownTemplate = {
  SetupMenu = function(self, generator) self.generator = generator end,
  SetDefaultCallback = function(self, fn) self.defaultCallback = fn end,
  SetIsDefaultCallback = function(self, fn) self.isDefaultCallback = fn end,
  ValidateResetState = noop,
}


-- `owned(id)` decides ownership (default: every third mount).
local function loadUI(owned)
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  local stubGame = {
    MountInfo = function() return nil end,
    IsOwned = owned or function(id) return id % 3 == 0 end,
    Exists = function() return true end,
    Faction = function() return "Alliance" end,
    SavedRows = function() return {} end,
    IsQuestDone = function() return false end,
    IsLfgDone = function() return false end,
    MountSourceText = function() return nil end,
    Now = function() return 1700000000 end,
    PlayerName = function() return "Tester" end,
    ActiveHolidays = function() return {} end,
    UntilDaily = function() return 3600 end,
    UntilWeekly = function() return 86400 end,
    PlayerMap = function() return nil end,
  }
  for k, v in pairs(stubGame) do ns.Game[k] = v end
  return ns
end

local function openHome(ns)
  ns.ToggleWindow()
  ns.UI.SelectTab("journal")
  local journal = ns.UI.frame.Contents.journal
  return journal.children[2], journal
end

local function backOf(page) return page.Back end

describe("journal home", function()
  it("a summary card, then Expansions on the left, By source and Nearby on the right", function()
    local ns = loadUI()
    local home = openHome(ns)
    local summary = home.Summary
    eq(summary.Totals:GetText(), string.format("%d / %d", summary.have, summary.total), "the total, large")
    eq(summary.Totals.template, ns.UI.Font("GameFontNormalHuge"))
    eq(summary.Title:GetText(), string.format("mounts collected · %d%%", ns.UI.HomePercent(summary.have, summary.total)))
    eq(summary.Bar.height, 12, "a thick 12 px total bar")
    eq(summary.Bar:GetNumPoints(), 2, "between the total and the search box")
    eq(summary.Bar.barColor, { 1, 0.82, 0, 1 }, "gold")
    eq(home.ExpHeading.Note:GetText(), "collected", "a grey note on the header's right")
    eq(home.ExpHeading.Text:GetText(), "Expansions")
    eq(home.ExpHeading.Text.textColor, { 1, 0.82, 0 }, "a pop-out header: gold by default")
    eq(home.ExpHeading.Rule.color, { 0.15, 0.13, 0.07, 1 }, "a faint rule inside the card")
    ok(home.ExpCard.Fill:IsShown() and home.ExpCard.Edge:IsShown(), "Expansions on a card")
    ok(home.SourceCard.Fill:IsShown(), "By source on a card")
    ok(summary.Card.Edge:IsShown(), "the summary on a card")
    eq(#home.Expansions, #ns.Data.Expansions)
    for i, row in ipairs(home.Expansions) do
      eq(row.kind, "Button", "row " .. i)
      eq(row.Bar.height, 6, "slim bar")
      eq(row.Count.template, ns.UI.Font("GameFontHighlight"), "readable, not the small font")
      eq(row.Percent, nil, "no percent: the count says it")
      eq(row.Name:GetText(), ns.Data.Expansions[i])
      local c = ns.UI.EXPANSION_COLORS[ns.Data.Expansions[i]]
      if c then eq(row.Bar.barColor, { c[1], c[2], c[3], 1 }, "the bar in the expansion's colour") end
      eq(row.Stripe:IsShown(), i % 2 == 0, "striped every other row")
    end
    eq(home.SourceHeading.Text:GetText(), "By source")
    eq(#home.Sources, #ns.Browse.CATEGORIES, "a row per Browse source, not Misc")
    eq(home.Sources[1].Name:GetText(), "Drops")
    ok(home.Side and home.Side.NearbyHeading:IsShown(), "the right column: Nearby")
    eq(home.Side.TodayHeading, nil, "no Today")
    eq(select(2, home.SourceHeading:GetPoint(1)), home.Side, "By source on the right")
    eq(select(2, home.ExpHeading:GetPoint(1)), home.Left, "Expansions on the left")
    eq({ home.Side:GetPoint(1) }, { "TOPRIGHT", home.MainContent, "TOPRIGHT", 0, 0 }, "inside the one scrolling page")
    ok(select(5, home.Side.NearbyHeading:GetPoint(1)) < select(5, home.SourceHeading:GetPoint(1)) - 100,
      "Nearby under By source")
  end)

  it("expansion counts match their text", function()
    local ns = loadUI()
    local home = openHome(ns)
    local have, total = 0, 0
    for _, row in ipairs(home.Expansions) do
      local h, t = row.Count:GetText():match("^(%d+) / (%d+)$")
      ok(h, "count text")
      eq(tonumber(h), row.have)
      eq(tonumber(t), row.total)
      have, total = have + row.have, total + row.total
    end
    ok(total > 0 and have > 0 and have < total, "a partial collection")
  end)

  it("summary totals count every tab's mounts; a By source row per tab, clicking opens it", function()
    local ns = loadUI()
    ns.Data.Mounts = {
      [3] = { name = "J owned", tab = "journal", section = "raid", exp = ns.Data.Expansions[1] },
      [4] = { name = "J", tab = "journal", section = "raid", exp = ns.Data.Expansions[2] },
      [6] = { name = "Holiday owned", tab = "holiday", section = "brewfest" },
      [7] = { name = "Achievement", tab = "misc", section = "achievement" },
      [9] = { name = "Shop owned", tab = "misc", section = "shop" },
      [10] = { name = "Shop", tab = "misc", section = "shop" },
      [11] = { name = "TW", tab = "holiday", section = "timewalking" },
      [13] = { name = "Gone", tab = "misc", section = "other", unobtainable = true },
      [14] = { name = "Horde only", tab = "misc", section = "shop", faction = "Horde" },
    }
    local home = openHome(ns)
    local s = home.Summary
    eq({ s.have, s.total }, { 3, 7 }, "unobtainable unowned and other-faction mounts left out")
    eq(s.Totals:GetText(), "3 / 7")
    eq(s.Title:GetText(), string.format("mounts collected · %d%%", ns.UI.HomePercent(3, 7)))
    eq(s.Bar.max, 7)
    eq(s.Bar.value, 3)
    local want = {
      drops = { 1, 2 }, holidays = { 1, 1 }, achievements = { 0, 1 }, timewalking = { 0, 1 }, shop = { 1, 2 },
    }
    local byKey = {}
    for i, row in ipairs(home.Sources) do
      eq(row.key, ns.Browse.CATEGORIES[i].key)
      eq({ row.have, row.total }, want[row.key] or { 0, 0 }, row.key)
      eq(row.Count:GetText(), string.format("%d / %d", row.have, row.total))
      byKey[row.key] = row
    end
    byKey.shop:RunScript("OnClick", "LeftButton")
    ok(ns.UI.frame.Contents.browse:IsShown(), "In-game Shop opens its Browse page")
    eq(ns.UI.BrowseCategory(), "shop")
    byKey.achievements:RunScript("OnClick", "LeftButton")
    ok(ns.UI.frame.Contents.achievements:IsShown(), "Achievements opens its own view")
    -- Not counting the in-game shop: out of the totals, its row gone.
    ns.UI.SelectTab("journal")
    ns.Journal.SetExcluded({ shop = true })
    ns.Refresh()
    eq({ s.have, s.total }, { 2, 5 }, "the shop's two mounts left out, the owned one too")
    ok(not byKey.shop:IsShown(), "no In-game Shop row")
    ns.Journal.SetExcluded({})
  end)

  it("percent rounds down and is 0 without mounts", function()
    local ns = loadUI()
    local P = ns.UI.HomePercent
    eq(P(0, 0), 0)
    eq(P(1, 3), 33)
    eq(P(199, 200), 99, "never 100 before the last mount")
    eq(P(5, 5), 100)
  end)

  it("a complete row's count turns green; others stay light", function()
    local ns = loadUI(function() return true end)
    local home = openHome(ns)
    local seen = 0
    for _, row in ipairs(home.Expansions) do
      if row.total > 0 then
        seen = seen + 1
        eq(row.Count.textColor, { 0.56, 0.88, 0.56 }, "green when complete")
      end
    end
    ok(seen > 0, "some expansion has mounts")
    local ns2 = loadUI()
    for _, row in ipairs(openHome(ns2).Expansions) do
      if row.have < row.total then eq(row.Count.textColor, { 0.79, 0.75, 0.68 }) end
    end
  end)

  it("click an expansion row: its list; Back returns home", function()
    local ns = loadUI()
    local home, journal = openHome(ns)
    home.Expansions[3]:RunScript("OnClick", "LeftButton")
    local listPage = journal.children[3]
    ok(listPage:IsShown() and not home:IsShown(), "list shown")
    eq(listPage.Title:GetText(), ns.Data.Expansions[3])
    eq(listPage.Back.template, nil, "a flat Back, not the red panel button")
    backOf(listPage):RunScript("OnClick", "LeftButton")
    ok(home:IsShown() and not listPage:IsShown(), "Back returns home")
  end)

  it("Nearby: the first mounts of the zone, kept per zone for a minute; the last line opens Current Zone", function()
    local ns = loadUI()
    local calls = 0
    local zoneList = {}
    for i = 1, 7 do zoneList[i] = { id = i, m = { name = "Mount " .. i, exp = ns.Data.Expansions[2] } } end
    ns.UI.ZoneMounts = function() calls = calls + 1; return zoneList, { name = "Nagrand" } end
    ns.UI.ZoneContext = function() return {} end
    ns.Zone.Key = function() return "107" end
    local now = 1700000000
    ns.Game.Now = function() return now end
    ns.Game.MountInfo = function(id) return nil, 7000 + id end
    local home = openHome(ns)
    local side = home.Side
    eq(calls, 1)
    local shown = 0
    for _, b in ipairs(side.Nearby) do if b:IsShown() then shown = shown + 1 end end
    eq(shown, 5, "the first five")
    eq(side.Nearby[1].Name:GetText(), "Mount 1")
    eq(side.Nearby[1].Icon.texture, 7001, "its icon")
    ok(side.Nearby[1].IconBox:IsShown(), "boxed")
    ok(side.Card.Fill:IsShown(), "Nearby on a card")
    eq(side.NearbyMore.Text:GetText(), "|cff9d9d9d7 in Nagrand: open Current Zone|r")
    ns.Refresh()
    eq(calls, 1, "same zone within a minute: kept")
    now = now + 61
    ns.Refresh()
    eq(calls, 2, "a minute later: again")
    ns.Zone.Key = function() return "108" end
    ns.Refresh()
    eq(calls, 3, "a new zone: again")
    local went
    ns.UI.GoTo = function(id) went = id end
    side.Nearby[2]:RunScript("OnClick", "LeftButton")
    eq(went, 2, "a click is the waypoint")
    side.NearbyMore:RunScript("OnClick", "LeftButton")
    eq(ns.UI.CurrentTab(), "here", "the last line opens Current Zone")
  end)

  it("typing in the home search box opens the search page with grouped results; Back returns", function()
    local ns = loadUI(function() return false end)
    ns.Data.Mounts = {
      [1] = { name = "Swift Zulian Tiger", tab = "journal", section = "dungeon", group = "Zul'Gurub", exp = "Cataclysm" },
      [2] = { name = "Zulian Raptor", tab = "misc", section = "shop" },
      [3] = { name = "Horde Tiger", tab = "misc", section = "shop", faction = "Horde" },
    }
    local home, journal = openHome(ns)
    local box = home.Summary.Search
    ok(box, "search box in the strip")
    box:SetText("tiger")
    box:RunScript("OnTextChanged", false)
    ok(home:IsShown(), "set by code: stays home")
    box:RunScript("OnTextChanged", true)
    local page = journal.children[4]
    ok(page:IsShown() and not home:IsShown(), "search page shown")
    eq(box:GetText(), "", "home box cleared")
    local list = page.List
    eq(list.SearchBox:GetText(), "tiger")
    local rows = list.ScrollBox.provider.rows
    eq(rows[1].header, true)
    eq(rows[1].text, "Mount name")
    eq(rows[2].id, 1, "the other faction's tiger is left out")
    eq(#rows, 2)
    list.SearchBox:SetText("zulgurub")
    list.SearchBox:RunScript("OnTextChanged", true)
    rows = list.ScrollBox.provider.rows
    eq(rows[1].text, "Dungeon / raid")
    eq(rows[2].id, 1)
    backOf(page):RunScript("OnClick", "LeftButton")
    ok(home:IsShown() and not page:IsShown(), "Back returns home")
    eq(list.SearchBox:GetText(), "", "search cleared")
  end)

  it("the rows fit the width of the 900 x 560 window beside the navigation; the column scrolls", function()
    local ns = loadUI()
    local G = ns.UI.HomeLayout
    local home = openHome(ns)
    -- Window 900 x 560: the navigation column (6 + NAV_WIDTH + 4) on the
    -- left, 6 px right; 4 px inside.
    local contentW = 900 - (6 + ns.UI.NAV_WIDTH + 4) - 6 - 8
    eq(home.Main.kind, "ScrollFrame", "the page scrolls")
    eq(home.MainContent.height, home.mainHeight, "its content as tall as the taller column")
    local colW = (contentW - 2 * G.left - G.gap) / 2
    -- The card's insets 10 + 6, name 4 + 128, gap 8, a 60 px bar at least,
    -- gap 8, count 70, 4.
    ok(colW >= 16 + 132 + 8 + 60 + 8 + 70 + 4, "room for name, bar and count in half the page: " .. colW)
    eq(select(4, home.Expansions[1].Name:GetPoint(1)), 4, "no tag column: names start at the row's edge")
  end)
end)

