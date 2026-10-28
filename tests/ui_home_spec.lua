-- The Journal front page (UI/JournalHome.lua) built under the widget stub:
-- summary strip (title, totals, search, 4 px bar), the Expansions and By
-- source progress rows, and the Today / Following / Nearby column.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/JournalHome.lua" }

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

local CHECK_ATLAS = "activities-icon-checkmark"

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
  it("a summary strip, then Expansions and By source rows on the left and the Today column on the right", function()
    local ns = loadUI()
    local home = openHome(ns)
    local summary = home.Summary
    eq(summary.Title:GetText(), "Mount Collection")
    eq(summary.Title.template, ns.UI.Font("GameFontNormalLarge"))
    eq(summary.Totals.template, ns.UI.Font("GameFontHighlight"))
    eq(summary.Bar.height, 4, "4 px summary bar")
    eq(summary.Bar:GetNumPoints(), 2, "full width: anchored left and right")
    eq(summary.Bar.barColor, ns.UI.ProgressColor(summary.have, summary.total), "its percent's colour")
    eq(home.ExpHeading.Text:GetText(), "Expansions")
    eq(home.ExpHeading.Text.textColor, { 1, 0.82, 0 }, "a pop-out header: gold by default")
    eq(home.ExpHeading.Rule.color, { 1, 0.82, 0, 0.35 })
    eq(#home.Expansions, #ns.Data.Expansions)
    for i, row in ipairs(home.Expansions) do
      eq(row.kind, "Button", "row " .. i)
      eq(row.Bar.height, 6, "slim bar")
      eq(row.Count.template, ns.UI.Font("GameFontHighlightSmall"))
      eq(row.Percent.template, ns.UI.Font("GameFontDisableSmall"))
      eq(row.Name:GetText(), ns.Data.Expansions[i])
      eq(row.Stripe:IsShown(), i % 2 == 0, "striped every other row")
    end
    eq(home.SourceHeading.Text:GetText(), "By source")
    eq(#home.Sources, 5)
    ok(home.Side and home.Side.TodayHeading:IsShown(), "the right column")
    eq({ home.Side:GetPoint(1) }, { "TOPRIGHT", home, "TOPRIGHT", -12, -48 })
  end)

  it("expansion counts and percents match their text", function()
    local ns = loadUI()
    local home = openHome(ns)
    local have, total = 0, 0
    for _, row in ipairs(home.Expansions) do
      local h, t = row.Count:GetText():match("^(%d+) / (%d+)$")
      ok(h, "count text")
      eq(tonumber(h), row.have)
      eq(tonumber(t), row.total)
      have, total = have + row.have, total + row.total
      eq(row.Percent:GetText(), ns.UI.HomePercent(row.have, row.total) .. "%")
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
    eq(s.Totals:GetText(), string.format("%d / %d collected  ·  %d%%", 3, 7, ns.UI.HomePercent(3, 7)))
    eq(s.Bar.max, 7)
    eq(s.Bar.value, 3)
    local want = {
      journal = { 1, 2 }, holidays = { 1, 1 }, achievements = { 0, 1 }, timewalking = { 0, 1 }, misc = { 1, 2 },
    }
    for i, row in ipairs(home.Sources) do
      eq(row.key, ns.UI.HomeSources[i].key)
      eq({ row.have, row.total }, want[row.key], row.key)
      eq(row.Count:GetText(), string.format("%d / %d", row.have, row.total))
    end
    home.Sources[5]:RunScript("OnClick", "LeftButton")
    ok(ns.UI.frame.Contents.misc:IsShown(), "the Misc row opens the Misc tab")
  end)

  it("percent rounds down and is 0 without mounts", function()
    local ns = loadUI()
    local P = ns.UI.HomePercent
    eq(P(0, 0), 0)
    eq(P(1, 3), 33)
    eq(P(199, 200), 99, "never 100 before the last mount")
    eq(P(5, 5), 100)
  end)

  it("complete rows: blue bar and the check; incomplete: their percent's colour, no check", function()
    local ns = loadUI(function() return true end)
    STUB_ATLASES[CHECK_ATLAS] = true -- after loadUI: reset_ui_stub clears atlases
    local home = openHome(ns)
    local seen = 0
    for _, row in ipairs(home.Expansions) do
      if row.total > 0 then
        seen = seen + 1
        eq(row.Bar.barColor, { 0.25, 0.6, 1, 1 }, "blue when complete")
        ok(row.Check:IsShown(), "check shown")
        eq(row.Check.atlas, CHECK_ATLAS)
      end
    end
    ok(seen > 0, "some expansion has mounts")
    STUB_ATLASES[CHECK_ATLAS] = nil
    local ns2 = loadUI()
    for _, row in ipairs(openHome(ns2).Expansions) do
      if row.have < row.total then
        eq(row.Bar.barColor, ns2.UI.ProgressColor(row.have, row.total))
        ok(not row.Check:IsShown(), "no check")
      end
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

  it("Today: the lockouts left per group and your lists with lockouts open; a click opens them", function()
    local ns = loadUI()
    local built = { daily = {}, weekly = {}, camp = {} }
    ns.UI.ChecklistLeft = function() return { daily = 4, weekly = 0, camp = 2 } end
    local rows = ns.UI.HomeToday(built, nil, {
      { name = "Mine", open = 3, source = { kind = "list", list = 1 } },
      { name = "Done", open = 0, source = { kind = "list", list = 2 } },
    })
    eq(#rows, 4, "three groups and the list with something open")
    eq({ rows[1].label, rows[1].value, rows[1].open }, { "Daily lockouts", "4 left", true })
    eq({ rows[2].value, rows[2].open }, { "0 left", false })
    eq({ rows[4].label, rows[4].value }, { "Mine", "3 left" })
    local clicked
    ns.UI.NavClick = function(e) clicked = e end
    rows[1].click()
    eq(clicked, { show = "daily" })
    rows[4].click()
    eq(clicked.source, { kind = "list", list = 1 })
    -- On the page.
    local home = openHome(ns)
    local today = home.Side.Today
    eq(today[1].Label:GetText(), "Daily lockouts")
    eq(today[1].Value:GetText(), "|cff40c0404 left|r", "green while some are left")
    eq(today[2].Value:GetText(), "|cff9d9d9d0 left|r", "grey when none")
  end)

  it("Following: the guide followed, its step and Resume; else a hint", function()
    local ns = loadUI()
    local home = openHome(ns)
    local f = home.Side.Follow
    ok(f.None:IsShown() and not f.Resume:IsShown(), "no guide: the hint")
    local guide = { title = "Serpent", guide = { steps = { { text = "Fly" }, { text = "Wait" }, { text = "Done" } } } }
    ns.UI.ActiveGuide = function() return guide, 2 end
    ns.UI.GuideText = function(t) return t end
    local opened
    ns.UI.ShowGuideWindow = function(on) opened = on end
    ns.Refresh()
    eq(f.Title:GetText(), "Serpent")
    eq(f.Step:GetText(), "Step 2 of 3  |cff9d9d9dWait|r")
    eq({ f.Bar.max, f.Bar.value }, { 3, 2 })
    ok(f.Resume:IsShown() and not f.None:IsShown())
    f.Resume:RunScript("OnClick", "LeftButton")
    eq(opened, true, "Resume opens the guide window")
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
    ns.Game.MountInfo = function() return nil end
    local home = openHome(ns)
    local side = home.Side
    eq(calls, 1)
    local shown = 0
    for _, b in ipairs(side.Nearby) do if b:IsShown() then shown = shown + 1 end end
    eq(shown, 5, "the first five")
    eq(side.Nearby[1].Name:GetText(), "Mount 1")
    eq(side.Nearby[1].Tag.exp, ns.Data.Expansions[2], "its expansion tag")
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

  it("the rows fit the view area of the 900 x 560 window beside the navigation", function()
    local ns = loadUI()
    local G = ns.UI.HomeLayout
    local home = openHome(ns)
    -- Window 900 x 560: the navigation column (6 + NAV_WIDTH + 4) on the
    -- left, 6 px right; views from 32 px down to 6 px from the bottom; 4 px inside.
    local contentW = 900 - (6 + ns.UI.NAV_WIDTH + 4) - 6 - 8
    local contentH = 560 - 32 - 6 - 8
    ok(-G.top + home.mainHeight <= contentH, "the left column fits the height: " .. (-G.top + home.mainHeight))
    local leftW = contentW - 2 * G.left - G.sideW - G.gap
    ok(leftW >= 46 + 150 + 8 + 60 + 4 + 70 + 6 + 36 + 4, "room for tag, name, bar, count and percent: " .. leftW)
  end)
end)

describe("UI.ProgressColor", function()
  it("red under 25 %, yellow under 75 %, green below complete, blue when complete", function()
    local ns = loadUI()
    local P = ns.UI.ProgressColor
    eq(P(0, 10), { 0.85, 0.22, 0.2, 1 })
    eq(P(2, 10), { 0.85, 0.22, 0.2, 1 }, "20 %")
    eq(P(25, 100), { 1, 0.82, 0, 1 }, "25 %: yellow")
    eq(P(74, 100), { 1, 0.82, 0, 1 })
    eq(P(75, 100), { 0.25, 0.78, 0.35, 1 }, "75 %: green")
    eq(P(99, 100), { 0.25, 0.78, 0.35, 1 })
    eq(P(100, 100), { 0.25, 0.6, 1, 1 }, "complete: blue")
    eq(P(0, 0), { 0.85, 0.22, 0.2, 1 }, "nothing to collect")
  end)
end)
