-- The Journal front page (UI/JournalHome.lua home grid) built under the widget
-- stub: summary strip (title, totals, 4 px bar), 4 x 3 flat tiles that fit
-- the 800 x 560 window, completed-state styling, hover and click.

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
    ExpansionLogo = function(i) if i == 1 then return 123 end end,
    MountSourceText = function() return nil end,
    Now = function() return 1700000000 end,
    PlayerName = function() return "Tester" end,
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

local function tiles(ns, home)
  local out = {}
  for i = 1, #ns.Data.Expansions do out[i] = home.children[i] end
  return out
end

describe("journal home", function()
  it("builds a summary strip and one tile per expansion under the stub", function()
    local ns = loadUI()
    local home = openHome(ns)
    eq(#home.children, #ns.Data.Expansions + 1, "the tiles, then the summary strip")
    local summary = home.Summary
    ok(summary and home.children[#home.children] == summary, "summary strip on the home")
    eq(summary.Title:GetText(), "Mount Collection")
    eq(summary.Title.template, "GameFontNormalLarge")
    eq(summary.Totals.template, "GameFontHighlight")
    eq(summary.Bar.height, 4, "4 px summary bar")
    eq(summary.Bar:GetNumPoints(), 2, "full width: anchored left and right")
    eq(summary.Bar.barColor, ns.UI.ProgressColor(summary.have, summary.total), "its percent's colour")
    for i, tile in ipairs(tiles(ns, home)) do
      eq(tile.kind, "Button", "tile " .. i)
      eq(tile.Bar.height, 3, "slim 3 px tile bar")
      ok(tile.Edge and #tile.Edge.edges == 4, "1 px edge")
      eq(tile.Count.template, "GameFontHighlightSmall")
      eq(tile.Percent.template, "GameFontDisableSmall")
      eq(tile.Count:GetPoint(1), "BOTTOMLEFT", "owned / total on the left")
      eq(tile.Percent:GetPoint(1), "BOTTOMRIGHT", "percent on the right")
    end
  end)

  it("shows the logo, or the expansion name only when there is no logo", function()
    local ns = loadUI()
    local all = tiles(ns, (openHome(ns)))
    eq(all[1].Logo.texture, 123)
    ok(all[1].Logo:IsShown() and not all[1].Name:IsShown(), "logo, no name")
    ok(not all[2].Logo:IsShown() and all[2].Name:IsShown(), "name as the fallback")
    eq(all[2].Name:GetText(), ns.Data.Expansions[2])
  end)

  it("tile counts and percents match their text", function()
    local ns = loadUI()
    local home = openHome(ns)
    local have, total = 0, 0
    for _, tile in ipairs(tiles(ns, home)) do
      local h, t = tile.Count:GetText():match("^(%d+) / (%d+)$")
      ok(h, "tile count text")
      eq(tonumber(h), tile.have)
      eq(tonumber(t), tile.total)
      have, total = have + tile.have, total + tile.total
      eq(tile.Percent:GetText(), ns.UI.HomePercent(tile.have, tile.total) .. "%")
    end
    ok(total > 0 and have > 0 and have < total, "a partial collection")
  end)

  it("summary totals count every tab's mounts; one chip per tab, clicking opens it", function()
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
    eq(#s.Chips, 5)
    for i, chip in ipairs(s.Chips) do
      eq(chip.key, ns.UI.HomeChips[i].key)
      eq({ chip.have, chip.total }, want[chip.key], chip.key)
      eq(chip.Text:GetText(), string.format("|cffffd100%s|r  %d / %d", chip.label, chip.have, chip.total))
    end
    s.Chips[5]:RunScript("OnClick", "LeftButton")
    ok(ns.UI.frame.Contents.misc:IsShown(), "the Misc chip opens the Misc tab")
  end)

  it("percent rounds down and is 0 without mounts", function()
    local ns = loadUI()
    local P = ns.UI.HomePercent
    eq(P(0, 0), 0)
    eq(P(1, 3), 33)
    eq(P(199, 200), 99, "never 100 before the last mount")
    eq(P(5, 5), 100)
  end)

  it("completed expansions: blue bar and the check atlas in the top-right corner", function()
    local ns = loadUI(function() return true end)
    STUB_ATLASES[CHECK_ATLAS] = true -- after loadUI: reset_ui_stub clears atlases
    local home = openHome(ns)
    local seen = 0
    for _, tile in ipairs(tiles(ns, home)) do
      if tile.total > 0 then
        seen = seen + 1
        eq(tile.Bar.barColor, { 0.25, 0.6, 1, 1 }, "blue when complete")
        ok(tile.Check:IsShown(), "check shown")
        eq(tile.Check.atlas, CHECK_ATLAS)
        eq(tile.Check:GetPoint(1), "TOPRIGHT")
      end
    end
    ok(seen > 0, "some expansion has mounts")
    STUB_ATLASES[CHECK_ATLAS] = nil
  end)

  it("incomplete tiles: red / yellow / green by percent and no check; no atlas -> the classic check texture", function()
    local ns = loadUI()
    local home = openHome(ns)
    for _, tile in ipairs(tiles(ns, home)) do
      if tile.have < tile.total then
        eq(tile.Bar.barColor, ns.UI.ProgressColor(tile.have, tile.total), "its percent's colour")
        ok(tile.Bar.barColor[3] ~= 1, "never blue while incomplete")
        ok(not tile.Check:IsShown(), "no check")
      end
    end
    local ns2 = loadUI(function() return true end)
    local tile = tiles(ns2, (openHome(ns2)))[1]
    ok(tile.Check:IsShown())
    eq(tile.Check.atlas, nil, "atlas missing on this client")
    eq(tile.Check.texture, "Interface\\Scenarios\\ScenarioIcon-Check")
  end)

  it("hover brightens the tile and edges it in gold; leave restores", function()
    local ns = loadUI()
    local tile = tiles(ns, (openHome(ns)))[1]
    local base = tile.Bg.color
    tile:RunScript("OnEnter")
    ok(tile.Bg.color[1] > base[1] and tile.Bg.color[4] >= base[4], "brighter fill")
    eq(tile.Edge.edges[1].color, { 1, 0.82, 0, 0.6 }, "gold edge")
    tile:RunScript("OnLeave")
    eq(tile.Bg.color, base)
    eq(tile.Edge.edges[1].color, { 1, 1, 1, 0.1 })
  end)

  it("click opens the expansion list and Back returns home", function()
    local ns = loadUI()
    local home, journal = openHome(ns)
    local tile = tiles(ns, home)[3]
    tile:RunScript("OnClick", "LeftButton")
    local listPage = journal.children[3]
    ok(listPage:IsShown() and not home:IsShown(), "list shown")
    ok(not home.Summary:IsVisible(), "summary hidden with the home")
    local back
    for _, c in ipairs(listPage.children) do
      if c.template == "UIPanelButtonTemplate" then back = c end
    end
    back:RunScript("OnClick", "LeftButton")
    ok(home:IsShown() and not listPage:IsShown(), "Back returns home")
    ok(home.Summary:IsVisible(), "summary back with the home")
  end)

  it("a clicked tile comes back from Back without its hover look", function()
    local ns = loadUI()
    local home, journal = openHome(ns)
    local tile = tiles(ns, home)[3]
    local base = tile.Bg.color
    -- Hover then click: the tile is hidden with the home, no OnLeave arrives.
    tile:RunScript("OnEnter")
    tile:RunScript("OnClick", "LeftButton")
    local back
    for _, c in ipairs(journal.children[3].children) do
      if c.template == "UIPanelButtonTemplate" then back = c end
    end
    back:RunScript("OnClick", "LeftButton")
    eq(tile.Bg.color, base, "plain fill again")
    eq(tile.Edge.edges[1].color, { 1, 1, 1, 0.1 }, "faint edge again")
    -- The client fires OnHide on the tile when the home hides; it resets too.
    tile:RunScript("OnEnter")
    tile:RunScript("OnHide")
    eq(tile.Bg.color, base, "OnHide resets the fill")
    eq(tile.Edge.edges[1].color, { 1, 1, 1, 0.1 }, "OnHide resets the edge")
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
    local back
    for _, c in ipairs(page.children) do
      if c.template == "UIPanelButtonTemplate" then back = c end
    end
    back:RunScript("OnClick", "LeftButton")
    ok(home:IsShown() and not page:IsShown(), "Back returns home")
    eq(list.SearchBox:GetText(), "", "search cleared")
  end)

  it("the 4 x 3 grid and the strip fit the view area of the 900 x 560 window beside the navigation", function()
    local ns = loadUI()
    local G = ns.UI.HomeLayout
    eq(G.cols, 4)
    ok(G.gap >= 10 and G.gap <= 12, "10-12 px gaps")
    -- Window 900 x 560: the navigation column (6 + NAV_WIDTH + 4) on the left,
    -- 6 px right; views from 34 px down to 6 px from the bottom; 4 px inside.
    local contentW = 900 - (6 + ns.UI.NAV_WIDTH + 4) - 6 - 8
    local contentH = 560 - 34 - 6 - 8
    local rows = math.ceil(#ns.Data.Expansions / G.cols)
    eq(rows, 3)
    local right = G.left + G.cols * G.tileW + (G.cols - 1) * G.gap
    local bottom = -G.top + rows * G.tileH + (rows - 1) * G.gap
    ok(right <= contentW - G.left, "fits the width with an even right margin: " .. right)
    ok(bottom <= contentH - 8, "fits the height: " .. bottom)
    ok(-G.top > G.stripH, "grid starts below the summary strip")
    -- Tile positions follow the layout.
    local home = openHome(ns)
    local p, rel, relP, x, y = tiles(ns, home)[6]:GetPoint(1)
    eq({ p, relP, x, y }, { "TOPLEFT", "TOPLEFT", G.left + G.tileW + G.gap, G.top - G.tileH - G.gap })
  end)

  it("tiles fill a resized window (same margins and gaps); never under 80%; unknown size: defaults", function()
    local ns = loadUI()
    local G = ns.UI.HomeLayout
    local dw, dh, ds = ns.UI.HomeTileSize(0, 0, 12)
    eq({ dw, dh }, { G.tileW, G.tileH })
    ok(ds > 0.9 and ds <= 1, "the default tile's logo scale: " .. ds)
    local w, h, s = ns.UI.HomeTileSize(1200, 800, 12)
    eq(w, math.floor((1200 - 2 * G.left - 3 * G.gap) / 4))
    eq(h, math.floor((800 + G.top - 10 - 2 * G.gap) / 3))
    ok(s > 1, "bigger logos")
    local sw, sh = ns.UI.HomeTileSize(300, 200, 12)
    eq({ sw, sh }, { math.floor(G.tileW * 0.8), math.floor(G.tileH * 0.8) })
    local home = openHome(ns)
    home.width, home.height = 1200, 800
    home:RunScript("OnSizeChanged")
    local tile = tiles(ns, home)[6]
    eq({ tile.width, tile.height }, { w, h })
    local p, _, relP, x, y = tile:GetPoint(1)
    eq({ p, relP, x, y }, { "TOPLEFT", "TOPLEFT", G.left + w + G.gap, G.top - h - G.gap })
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
