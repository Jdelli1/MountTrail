-- UI/Frame.lua under the widget stub: view registry, lazy Build, Refresh
-- dispatch, saved tab and position, Esc registration, minimap launcher.

local function loadUI(global)
  reset_ui_stub()
  local files = toc_lua_files()
  files[#files + 1] = "UI/Frame.lua"
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  for k, v in pairs(global or {}) do ns.db.global[k] = v end
  return ns
end

local function countingView()
  local v = { builds = 0, refreshes = 0 }
  v.Build = function(parent) v.builds = v.builds + 1; v.parent = parent end
  v.Refresh = function() v.refreshes = v.refreshes + 1 end
  return v
end

describe("ui", function()
  it("toc lists UI/Frame.lua right after Core/Init.lua", function()
    local fh = assert(io.open(ROOT .. "/MountTrail.toc", "r"))
    local lines = {}
    for line in fh:lines() do
      line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if line ~= "" and not line:find("^#") then lines[#lines + 1] = line end
    end
    fh:close()
    local init
    for i, line in ipairs(lines) do if line == "Core\\Init.lua" then init = i end end
    ok(init, "Core\\Init.lua in toc")
    eq(lines[init + 1], "UI\\Frame.lua")
  end)

  it("builds the window lazily and exposes the API", function()
    local ns = loadUI()
    eq(ns.UI.frame, nil, "no window before first toggle")
    eq(type(ns.UI.RegisterView), "function")
    eq(type(ns.UI.SelectTab), "function")
    ns.ToggleWindow()
    local f = ns.UI.frame
    ok(f and f:IsShown(), "window shown")
    eq(f:GetName(), "MountTrailFrame")
    eq(f.template, nil, "no Blizzard frame template: the pop-outs' flat look")
    eq({ f:GetSize() }, { 900, 560 })
    eq(f.Title:GetText(), "MountTrail")
    ok(f.Fill and f.Edge and f.Strip and f.CloseButton, "flat fill, edge, title strip and close button")
    eq({ f.Strip:GetPoint(1) }, { "TOPLEFT", f, "TOPLEFT", 1, -1 })
    ok(f.movable and f.clamped, "movable and clamped")
    -- The navigation column on the left (no tabs), the views right of it.
    ok(f.Nav and f.isFlat, "flat window with a navigation column")
    eq(f.Tabs, nil, "no tab buttons")
    eq({ f.Nav:GetPoint(1) }, { "TOPLEFT", f, "TOPLEFT", 6, -32 }, "under the title strip")
    eq(f.Nav.width, ns.UI.NAV_WIDTH)
    eq({ f.Inset:GetPoint(1) }, { "TOPLEFT", f, "TOPLEFT", 6 + ns.UI.NAV_WIDTH + 4, -32 }, "views right of it, under the title strip")
    local labels = {}
    for i = 1, f.Nav.shown do labels[i] = f.Nav.Buttons[i].Text:GetText() end
    eq({ labels[1], labels[2], labels[3] }, { "Home", "Lockouts", "Current Zone" })
    ok(labels[4]:find("^Alts"), labels[4])
    eq({ labels[5], labels[8] }, { "Drops", "Achievements" }, "Browse by source")
    eq(f.Inset.template, nil, "flat content area, no classic inset")
    eq(f.Inset.Fill, nil, "the views sit on the window's own fill, as in a pop-out")
    eq(next(ns.UI.TemplateFallbacks), nil, "no fallback used")
    eq(ns.UI.CurrentTab(), "journal", "Home by default")
    ok(f.Nav.Buttons[1].selected and f.Nav.Buttons[1].Selected:IsShown(), "Home marked")
    eq(f.Nav.Buttons[1].Text.font, ns.UI.Font("GameFontNormal"), "in gold")
    eq(UISpecialFrames, { "MountTrailFrame" })
    ns.ToggleWindow()
    ok(not f:IsShown(), "second toggle hides")
  end)

  it("builds a view the first time its tab is shown and refreshes only the visible tab", function()
    local ns = loadUI()
    local journal, route = countingView(), countingView()
    ns.UI.RegisterView("journal", journal)
    ns.UI.RegisterView("checklist", route)
    ns.Refresh() -- window not built: no-op
    eq(journal.builds, 0)

    ns.ToggleWindow()
    eq(journal.builds, 1)
    eq(journal.refreshes, 1, "refreshed on show")
    eq(route.builds, 0, "route not built while hidden")
    ok(journal.parent and journal.parent:GetParent() == ns.UI.frame.Inset, "Build gets the tab's content frame")

    ns.Refresh()
    eq(journal.refreshes, 2)
    eq(route.refreshes, 0)

    ns.UI.SelectTab("checklist")
    eq(route.builds, 1)
    eq(route.refreshes, 1)
    ok(route.parent:IsShown() and not journal.parent:IsShown(), "only the selected content is shown")
    eq(ns.UI.CurrentTab(), "checklist")
    eq(ns.db.global.window.tab, "checklist")

    ns.Refresh()
    eq(route.refreshes, 2)
    eq(journal.refreshes, 2, "hidden tab not refreshed")

    ns.UI.SelectTab("journal")
    eq(journal.builds, 1, "Build runs once")

    ns.ToggleWindow() -- hide
    ns.Refresh()
    eq(journal.refreshes, 3, "nothing refreshes while closed")
  end)

  it("navigation entries select their view and move the gold mark; Alts opens its window", function()
    local ns = loadUI()
    local views = {}
    for _, key in ipairs({ "journal", "holidays", "achievements", "timewalking", "misc", "checklist", "here", "browse" }) do
      views[key] = countingView()
      ns.UI.RegisterView(key, views[key])
    end
    ns.ToggleWindow()
    local nav = ns.UI.frame.Nav
    local function button(label)
      for i = 1, nav.shown do
        local b = nav.Buttons[i]
        if b.Text:GetText():find("^" .. label) then return b end
      end
    end
    button("Achievements"):RunScript("OnClick", "LeftButton")
    eq(ns.UI.CurrentTab(), "achievements")
    eq(views.achievements.builds, 1)
    eq(ns.db.global.window.tab, "achievements")
    ok(button("Achievements").selected and not button("Home").selected, "the mark follows")
    button("Lockouts"):RunScript("OnClick", "LeftButton")
    eq(views.checklist.builds, 1)
    button("Current Zone"):RunScript("OnClick", "LeftButton")
    eq(views.here.builds, 1)
    local alts = 0
    ns.UI.ToggleAltsWindow = function() alts = alts + 1 end
    button("Alts"):RunScript("OnClick", "LeftButton")
    eq(alts, 1)
    eq(ns.UI.CurrentTab(), "here", "Alts is a window, not a view")
    -- Current Zone: right-click pops the zone's mounts out; both entries explain themselves.
    local popped = 0
    ns.UI.ToggleZoneMountsPopout = function() popped = popped + 1 end
    button("Current Zone"):RunScript("OnClick", "RightButton")
    eq(popped, 1)
    eq(ns.UI.CurrentTab(), "here", "a right-click does not switch the view")
    local hints = {}
    ns.UI.ShowHint = function(_, title, text) hints[#hints + 1] = { title, text } end
    button("Current Zone"):RunScript("OnEnter")
    ok(hints[1][2]:find("Right%-click to pop it out"), hints[1][2])
    button("Lockouts"):RunScript("OnEnter")
    eq(hints[2][1], "Lockouts")
    -- Browse entries are indented under their heading.
    local function leftInset(b)
      for i = 1, b.Text:GetNumPoints() do
        local p, _, _, x = b.Text:GetPoint(i)
        if p == "LEFT" then return x end
      end
    end
    eq(leftInset(button("Holidays")), 18)
    eq(leftInset(button("Lockouts")), 12)
  end)

  it("section headings look like a pop-out's group headers, in the window's header colour", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local nav = ns.UI.frame.Nav
    local h = nav.Headings[1]
    eq(h.Text:GetText(), "- Browse")
    eq(h.Text.textColor, { 1, 0.82, 0 }, "gold by default")
    eq(h.Rule.color, { 1, 0.82, 0, 0.35 }, "a thin rule under it")
    ns.db.global.popouts = { main = { style = { header = { 1, 1, 1 } } } }
    ns.UI.RefreshNav()
    eq(h.Text.textColor, { 1, 1, 1 }, "the appearance menu's header colour")
    eq(h.Rule.color, { 1, 1, 1, 0.35 })
    eq(nav.Edge.width, 1, "a 1 px line on the column's right edge")
  end)

  it("the navigation's text is the font object's size plus the bonus, however often it repaints", function()
    local ns = loadUI()
    -- As in the game: a size set with SetFont survives SetFontObject.
    local probe = CreateFrame("Frame")
    local RegionMT = getmetatable(getmetatable(probe).__index).__index or getmetatable(probe).__index
    local mt = getmetatable(probe:CreateFontString(nil, "OVERLAY", "GameFontHighlight")).__index
    local savedSet, savedGet = mt.SetFont, mt.GetFont
    mt.SetFont = function(self, path, size) self.fontPath, self.fontSize = path, size end
    mt.GetFont = function(self) return self.fontPath or "Fonts\\FRIZQT__.TTF", self.fontSize or 12, "" end
    local fonts = { "GameFontHighlight", "GameFontNormal", "GameFontNormalSmall", "GameFontDisableSmall" }
    for _, name in ipairs(fonts) do
      _G[name] = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
    end
    ns.ToggleWindow()
    for _ = 1, 5 do ns.UI.RefreshNav() end
    local nav = ns.UI.frame.Nav
    eq(nav.Buttons[2].Text.fontSize, 12 + ns.UI.NAV_FONT_BONUS, "no growth")
    eq(nav.Headings[1].Text.fontSize, 12 + ns.UI.NAV_FONT_BONUS)
    for _, name in ipairs(fonts) do _G[name] = nil end
    mt.SetFont, mt.GetFont = savedSet, savedGet
  end)

  it("the left column follows its own size only: Headers and Mount names and text leave it alone", function()
    local ns = loadUI()
    local probe = CreateFrame("Frame")
    local mt = getmetatable(probe:CreateFontString(nil, "OVERLAY", "GameFontHighlight")).__index
    local savedSet = mt.SetFont
    mt.SetFont = function(self, path, size) self.fontPath, self.fontSize = path, size end
    local fonts = { "GameFontHighlight", "GameFontNormal", "GameFontNormalSmall", "GameFontDisableSmall" }
    for _, name in ipairs(fonts) do
      _G[name] = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
    end
    local sizes = { header = 0, body = 0, detail = 0 }
    ns.Options = { TextSize = function(role) return sizes[role] end, NavTextSize = function() return 2 end }
    ns.ToggleWindow()
    local nav = ns.UI.frame.Nav
    local row, heading = nav.Buttons[2], nav.Headings[1]
    local rowH = row.height
    eq({ row.Text.fontSize, heading.Text.fontSize }, { 14, 14 }, "the game's size + the Left column's 2")
    sizes.header, sizes.body = 4, 4
    ns.UI.RefreshNav()
    eq({ row.Text.fontSize, heading.Text.fontSize }, { 14, 14 }, "the other sizes don't move it")
    eq(row.height, rowH, "nor its rows' height")
    ns.Options.NavTextSize = function() return 5 end
    ns.UI.RefreshNav()
    eq(row.Text.fontSize, 17, "the Left column size does")
    for _, name in ipairs(fonts) do _G[name] = nil end
    mt.SetFont = savedSet
  end)

  it("drag the navigation's right edge to resize it (saved, clamped); right-click: the default", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local f = ns.UI.frame
    local nav, split = f.Nav, f.NavSplitter
    ok(split, "a drag handle on the navigation's edge")
    nav.left = 100
    STUB_CURSOR[1] = 300
    split:RunScript("OnMouseDown", "LeftButton")
    split:GetScript("OnUpdate")(split, 0.01)
    eq(nav.width, 200, "follows the cursor")
    local function insetLeft()
      for i = 1, f.Inset:GetNumPoints() do
        local p, _, _, x = f.Inset:GetPoint(i)
        if p == "TOPLEFT" then return x end
      end
    end
    eq(insetLeft(), 6 + 200 + 4, "the views move beside it")
    split:RunScript("OnMouseUp", "LeftButton")
    eq(ns.db.global.window.navWidth, 200, "saved on release")
    STUB_CURSOR[1] = 1000
    split:RunScript("OnMouseDown", "LeftButton")
    split:GetScript("OnUpdate")(split, 0.01)
    split:RunScript("OnMouseUp", "LeftButton")
    eq(ns.db.global.window.navWidth, ns.UI.NAV_MAX, "no wider than the maximum")
    split:RunScript("OnClick", "RightButton")
    eq(ns.db.global.window.navWidth, ns.UI.NAV_WIDTH, "right-click: the default")
    eq(nav.width, ns.UI.NAV_WIDTH)
  end)

  it("the title bar's cogwheel opens the settings menu: sliders and checkboxes that apply at once", function()
    local ns = loadUI()
    local applied = {}
    ns.Options = {
      SCALE_RANGE = { min = 80, max = 150, step = 5 }, TEXT_RANGE = { min = -2, max = 6, step = 1 },
      NAV_TEXT_RANGE = { min = 0, max = 6, step = 1 },
      TEXT_LABELS = { header = "Headers", body = "Mount names and text", detail = "Small notes" },
      TEXT_ORDER = { "header", "body", "detail" }, SCALE_LABEL = "Whole window", NAV_LABEL = "Left column",
      WindowScale = function() return 100 end, TextSize = function() return 0 end, NavTextSize = function() return 2 end,
      Set = function(name, v) applied[#applied + 1] = { name, v } end,
      SetTextSize = function(role, v) applied[#applied + 1] = { role, v } end,
      ResetTextSizes = function() applied[#applied + 1] = { "reset" } end,
      Open = function() applied[#applied + 1] = { "open" } end,
    }
    ns.ToggleWindow()
    local cog = ns.UI.frame.SettingsButton
    ok(cog and cog.Icon.texture == ns.UI.COG_TEXTURE, "a cogwheel")
    ok(cog:GetFrameLevel() >= ns.UI.frame:GetFrameLevel() + 20, "above the window's border art")
    local shown
    ns.UI.ShowMenu = function(owner, items) shown = type(items) == "function" and items() or items end
    cog:RunScript("OnClick", "LeftButton")
    eq(shown[1].title, "Size")
    local order = {}
    for _, it in ipairs(shown) do
      if it.slider then order[#order + 1] = it.text elseif it.title then order[#order + 1] = "# " .. it.title end
    end
    eq({ order[1], order[2], order[3], order[4], order[5], order[6], order[7], order[8] },
      { "# Size", "Whole window", "# Text size", "Left column", "Headers", "Mount names and text", "Small notes", "# Settings" },
      "named by what they size, in the window's order")
    local byText = {}
    for _, it in ipairs(shown) do if it.text then byText[it.text] = it end end
    for text in pairs(byText) do
      ok(not text:find("Count towards the total", 1, true), "the unobtainable count is on the AddOns page only")
    end
    byText["Whole window"].onChange(120)
    byText["Mount names and text"].onChange(3)
    byText["Show unobtainable mounts"].onClick()
    byText["Reset text sizes"].onClick()
    byText["All options..."].onClick()
    eq(applied, { { "windowScale", 120 }, { "body", 3 }, { "showUnobtainable", true }, { "reset" }, { "open" } })
  end)

  it("UI.Font: a sized copy per game font, by its role (gold / white / grey); a change resizes them all", function()
    local ns = loadUI()
    local sizes = { header = 3, body = 0, detail = -1 }
    ns.Options = { TextSize = function(role) return sizes[role] end }
    eq(ns.UI.Font("GameFontNormal"), "GameFontNormal", "no CreateFont: the game font")
    CreateFont = function(name)
      local f = { name = name }
      function f:CopyFontObject(base) self.copied = base end
      function f:SetFont(path, size) self.path, self.size = path, size end
      _G[name] = f
      return f
    end
    for _, name in ipairs({ "GameFontNormal", "GameFontHighlightSmall", "GameFontDisableSmall" }) do
      _G[name] = { GetFont = function() return "Fonts\\FRIZQT__.TTF", 12, "" end }
    end
    eq(ns.UI.Font("GameFontNormal"), "MountTrailGameFontNormal")
    eq(_G.MountTrailGameFontNormal.size, 15, "gold: +3")
    eq(_G[ns.UI.Font("GameFontDisableSmall")].size, 11, "grey: -1")
    eq(ns.UI.Font("SomeOtherFont"), "SomeOtherFont", "not a role's font")
    sizes.header = 6
    ns.UI.ApplyTextSizes()
    eq(_G.MountTrailGameFontNormal.size, 18, "follows the setting")
    sizes.body = 2
    eq(ns.UI.RowHeight(22), 24, "one-line rows grow with the white text")
    sizes.body = -1
    eq(ns.UI.RowHeight(22), 22, "smaller text never shrinks a row")
    eq(ns.UI.HeaderHeight(24), 30)
    CreateFont = nil
    for _, name in ipairs({ "GameFontNormal", "GameFontHighlightSmall", "GameFontDisableSmall",
      "MountTrailGameFontNormal", "MountTrailGameFontDisableSmall" }) do _G[name] = nil end
  end)

  it("UI.NavMove / UI.ApplyNavOrder: one place up or down, never across the favourites' line", function()
    local ns = loadUI()
    local fav = { a = true }
    local isFav = function(k) return fav[k] == true end
    eq(ns.UI.NavMove({ "a", "b", "c" }, "c", -1, isFav), { "a", "c", "b" })
    eq(ns.UI.NavMove({ "a", "b", "c" }, "b", -1, isFav), nil, "a list never goes above a favourite")
    eq(ns.UI.NavMove({ "a", "b", "c" }, "a", 1, isFav), nil, "nor a favourite below the rest")
    eq(ns.UI.NavMove({ "a", "b", "c" }, "c", 1), nil, "at the end")
    eq(ns.UI.NavMove({ "a", "b", "c" }, "a", 1), { "b", "a", "c" }, "no favourites: anywhere")
    local function keys(list) local out = {} for i, e in ipairs(list) do out[i] = e.key end return out end
    eq(keys(ns.UI.ApplyNavOrder({ { key = "x" }, { key = "y" }, { key = "z" } }, { "z", "x" })), { "z", "x", "y" },
      "saved order first, the rest after")
  end)

  it("UI.NavMoveTo / UI.NavDropIndex: Alt-drag lands where dropped, inside its own part", function()
    local ns = loadUI()
    local isFav = function(k) return k == "a" end
    eq(ns.UI.NavMoveTo({ "a", "b", "c", "d" }, "d", 2, isFav), { "a", "d", "b", "c" })
    eq(ns.UI.NavMoveTo({ "a", "b", "c", "d" }, "d", 1, isFav), { "a", "d", "b", "c" }, "clamped below the favourite")
    eq(ns.UI.NavMoveTo({ "a", "b", "c" }, "a", 3, isFav), nil, "a favourite stays among favourites")
    eq(ns.UI.NavMoveTo({ "a", "b", "c" }, "a", 3), { "b", "c", "a" }, "no favourites: anywhere")
    eq(ns.UI.NavMoveTo({ "a", "b" }, "x", 1), nil, "unknown key")
    local rects = { { top = 100, bottom = 80 }, { top = 80, bottom = 60 }, { top = 60, bottom = 40 } }
    eq(ns.UI.NavDropIndex(rects, 95), 1)
    eq(ns.UI.NavDropIndex(rects, 75), 2)
    eq(ns.UI.NavDropIndex(rects, 10), 3, "below the last: the end")
  end)

  it("UI.NavSelected / UI.NavListEntries: a list page marks its list; lists then quick lists", function()
    local ns = loadUI()
    eq(ns.UI.NavSelected("checklist", nil), "checklist")
    eq(ns.UI.NavSelected("journal", { kind = "list", list = 3 }), "list:3")
    eq(ns.UI.NavSelected("journal", { kind = "quick", key = "mythic" }), "quick:mythic")
    local store = { lists = { [1] = { id = 1, name = "B" }, [2] = { id = 2, name = "A" } }, nextId = 3 }
    local entries = ns.UI.NavListEntries(store, { { key = "mythic", name = "Mythic Mounts" } })
    local keys = {}
    for i, e in ipairs(entries) do keys[i] = e.key end
    eq(keys[#keys], "quick:mythic")
    eq(entries[#entries].builtIn, true)
    eq(entries[#entries].source, { kind = "quick", key = "mythic" })
  end)

  it("shows a Coming soon placeholder until a view is registered", function()
    local ns = loadUI()
    ns.ToggleWindow()
    ns.UI.SelectTab("holidays")
    local contents = ns.UI.frame.Contents
    local n = 0
    for key, content in pairs(contents) do
      n = n + 1
      eq(content:GetParent(), ns.UI.frame.Inset, key .. " content in the inset")
    end
    eq(n, 8, "one content frame per view")
    local holidaysContent = contents.holidays
    ok(holidaysContent:IsShown(), "holidays content shown")
    local placeholder = holidaysContent.children[1]
    eq(placeholder.kind, "FontString")
    eq(placeholder:GetText(), "Coming soon")
    ok(placeholder:IsShown(), "placeholder visible")

    local holidays = countingView()
    ns.UI.RegisterView("holidays", holidays) -- late registration, tab on screen
    eq(holidays.builds, 1, "late registration builds the visible tab")
    eq(holidays.parent, holidaysContent)
    ok(not placeholder:IsShown(), "placeholder hidden once the view is built")
  end)

  it("restores the saved tab and position", function()
    local ns = loadUI({ window = { tab = "misc", point = "TOPLEFT", relPoint = "TOPLEFT", x = 100, y = -50 } })
    ns.ToggleWindow()
    eq(ns.UI.CurrentTab(), "misc")
    eq({ ns.UI.frame:GetPoint(1) }, { "TOPLEFT", UIParent, "TOPLEFT", 100, -50 })
  end)

  it("falls back to journal for an unknown saved tab", function()
    local ns = loadUI({ window = { tab = "bogus" } })
    ns.ToggleWindow()
    eq(ns.UI.CurrentTab(), "journal")
    eq(ns.db.global.window.tab, "journal")
  end)

  it("TabKey: a tab's key, else the first tab", function()
    local ns = loadUI()
    eq(ns.UI.TabKey("misc"), "misc")
    eq(ns.UI.TabKey("route"), "journal", "a retired key: the first tab")
    eq(ns.UI.TabKey(nil), "journal")
  end)

  it("saves the position after a title drag", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local f = ns.UI.frame
    f.DragHandle:RunScript("OnDragStart", "LeftButton")
    ok(f.moving, "dragging the title moves the window")
    f:ClearAllPoints()
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 12, 34) -- where the client left it
    f.DragHandle:RunScript("OnDragStop")
    eq(f.userPlaced, false)
    local w = ns.db.global.window
    eq({ w.point, w.relPoint, w.x, w.y }, { "BOTTOMLEFT", "BOTTOMLEFT", 12, 34 })
  end)

  it("takes the pop-outs' appearance: its own style under the key \"main\", the shared one else", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local f = ns.UI.frame
    eq(f.key, "main")
    eq(f.Fill.color, { 0.06, 0.06, 0.07, 0.92 }, "the pop-outs' default fill")
    local listed = false
    for _, w in ipairs(ns.UI.StyledWindows()) do if w == f then listed = true end end
    ok(listed, "restyled with the other windows")
    ns.db.global.popouts = { main = { style = { alpha = 0.5, bg = { 0, 0, 0 } } } }
    f.Restyle()
    eq(f.Fill.color, { 0, 0, 0, 0.5 }, "its own style")
    ns.db.global.popouts = {}
    ns.db.global.popoutStyle = { alpha = 0.8, bg = { 0.1, 0.12, 0.16 } }
    f.Restyle()
    eq(f.Fill.color, { 0.1, 0.12, 0.16, 0.8 }, "the shared style")
    f.CloseButton:RunScript("OnClick")
    ok(not f:IsShown(), "x closes it")
  end)

  describe("Template", function()
    it("returns the preferred template when the client defines it", function()
      local ns = loadUI()
      eq(ns.UI.Template("PanelTopTabButtonTemplate", "PanelTabButtonTemplate"), "PanelTopTabButtonTemplate")
      eq(next(ns.UI.TemplateFallbacks), nil)
    end)

    it("returns the fallback (or nil) for a missing template and records it", function()
      local ns = loadUI()
      eq(ns.UI.Template("NoSuchTemplate", "UIPanelButtonTemplate"), "UIPanelButtonTemplate")
      eq(ns.UI.Template("AlsoMissing"), nil)
      eq(ns.UI.TemplateFallbacks, { NoSuchTemplate = "UIPanelButtonTemplate", AlsoMissing = false })
    end)

    it("reports a fallback once through /mtrail debug's error handler", function()
      local ns = loadUI({ debug = true })
      local got = {}
      local old = geterrorhandler
      geterrorhandler = function() return function(msg) got[#got + 1] = msg end end
      ns.UI.Template("NoSuchTemplate", "UIPanelButtonTemplate")
      ns.UI.Template("NoSuchTemplate", "UIPanelButtonTemplate")
      geterrorhandler = old
      eq(got, { "MountTrail: template NoSuchTemplate missing, using UIPanelButtonTemplate" })
    end)

    it("falls back when C_XMLUtil is missing or errors", function()
      local ns = loadUI()
      local saved = C_XMLUtil
      C_XMLUtil = nil
      eq(ns.UI.Template("PanelTopTabButtonTemplate", "PanelTabButtonTemplate"), "PanelTabButtonTemplate")
      C_XMLUtil = { GetTemplateInfo = function() error("boom") end }
      eq(ns.UI.Template("PortraitFrameFlatTemplate", "PortraitFrameTemplate"), "PortraitFrameTemplate")
      C_XMLUtil = saved
    end)

    it("/mtrail debug lists the fallbacks when turned on", function()
      local ns = loadUI()
      ns.UI.Template("NoSuchTemplate", "UIPanelButtonTemplate")
      ns.UI.Template("AlsoMissing")
      run_slash(ns.addon, "mtrail", "debug")
      local n = #ns.addon.printed
      eq({ ns.addon.printed[n - 1], ns.addon.printed[n] }, {
        "Template AlsoMissing missing, using none",
        "Template NoSuchTemplate missing, using UIPanelButtonTemplate",
      })
      run_slash(ns.addon, "mtrail", "debug")
      eq(ns.addon.printed[#ns.addon.printed], "Debug: off", "nothing listed when turned off")
    end)
  end)

  describe("TemplateChain", function()
    it("returns the first defined template and checks no further", function()
      local ns = loadUI()
      local asked = {}
      local saved = C_XMLUtil.GetTemplateInfo
      C_XMLUtil.GetTemplateInfo = function(name) asked[#asked + 1] = name; return saved(name) end
      eq(ns.UI.TemplateChain("MinimalCheckboxTemplate", "SettingsCheckboxTemplate", "UICheckButtonTemplate"),
        "MinimalCheckboxTemplate")
      C_XMLUtil.GetTemplateInfo = saved
      eq(asked, { "MinimalCheckboxTemplate" }, "lazy: the fallbacks are not looked up")
      eq(next(ns.UI.TemplateFallbacks), nil, "nothing recorded")
    end)

    it("falls through to the next defined template, recording the first name once", function()
      local ns = loadUI()
      STUB_TEMPLATES.MinimalCheckboxTemplate = nil
      STUB_TEMPLATES.SettingsCheckboxTemplate = true
      eq(ns.UI.TemplateChain("MinimalCheckboxTemplate", "SettingsCheckboxTemplate", "UICheckButtonTemplate"),
        "SettingsCheckboxTemplate")
      eq(ns.UI.TemplateFallbacks, { MinimalCheckboxTemplate = "SettingsCheckboxTemplate" })
      STUB_TEMPLATES.SettingsCheckboxTemplate = nil
      eq(ns.UI.TemplateChain("MinimalCheckboxTemplate", "SettingsCheckboxTemplate", "UICheckButtonTemplate"),
        "UICheckButtonTemplate", "the last name is the final fallback")
      eq(ns.UI.TemplateFallbacks, { MinimalCheckboxTemplate = "SettingsCheckboxTemplate" }, "recorded once")
    end)
  end)

  describe("style helpers", function()
    it("AtlasExists asks C_Texture and never errors", function()
      local ns = loadUI()
      STUB_ATLASES["UI-HUD-ActionBar-IconFrame-Mask"] = true
      eq(ns.UI.AtlasExists("UI-HUD-ActionBar-IconFrame-Mask"), true)
      eq(ns.UI.AtlasExists("nope"), false)
      eq(ns.UI.AtlasExists(nil), false)
      local saved = C_Texture
      C_Texture = { GetAtlasInfo = function() error("boom") end }
      eq(ns.UI.AtlasExists("UI-HUD-ActionBar-IconFrame-Mask"), false)
      C_Texture = nil
      eq(ns.UI.AtlasExists("UI-HUD-ActionBar-IconFrame-Mask"), false)
      C_Texture = saved
    end)

    it("FlatBorder draws four 1 px edges and recolours them", function()
      local ns = loadUI()
      local f = CreateFrame("Frame", nil, UIParent)
      local border = ns.UI.FlatBorder(f, 1, 1, 1, 0.1)
      eq(#border.edges, 4)
      eq(#f.children, 4, "edges belong to the frame")
      eq(border.edges[1].height, 1)
      eq(border.edges[3].width, 1)
      eq(border.edges[2].color, { 1, 1, 1, 0.1 })
      border:SetColor(1, 0.82, 0, 0.6)
      for _, edge in ipairs(border.edges) do eq(edge.color, { 1, 0.82, 0, 0.6 }) end
    end)
  end)

  it("rejects unknown view keys", function()
    local ns = loadUI()
    ok(not pcall(ns.UI.RegisterView, "nope", countingView()), "unknown key errors")
  end)

  describe("minimap", function()
    local LDB = LibStub("LibDataBroker-1.1")
    local DBIcon = LibStub("LibDBIcon-1.0")

    it("registers the launcher on PLAYER_LOGIN", function()
      local ns = loadUI()
      eq(LDB.objects.MountTrail, nil, "nothing before login")
      fire_frame_event("PLAYER_LOGIN")
      local obj = LDB.objects.MountTrail
      ok(obj, "launcher created")
      eq(obj.type, "launcher")
      eq(obj.icon, 132261)
      eq(DBIcon.registered.MountTrail.db, ns.db.global.minimap)
      fire_frame_event("PLAYER_LOGIN") -- a second fire must not re-register
    end)

    it("left-click toggles the window", function()
      local ns = loadUI()
      fire_frame_event("PLAYER_LOGIN")
      local obj = LDB.objects.MountTrail
      obj.OnClick(nil, "LeftButton")
      ok(ns.UI.frame:IsShown())
      obj.OnClick(nil, "RightButton")
      ok(ns.UI.frame:IsShown(), "right-click does nothing")
      obj.OnClick(nil, "LeftButton")
      ok(not ns.UI.frame:IsShown())
    end)

    it("tooltip shows the title, the hint and the checklist's lockouts left when known", function()
      local ns = loadUI()
      fire_frame_event("PLAYER_LOGIN")
      local obj = LDB.objects.MountTrail
      local function lines()
        local out = {}
        obj.OnTooltipShow({ AddLine = function(_, text) out[#out + 1] = text end })
        return out
      end
      eq(lines(), { "MountTrail", "Left-click: open/close" })
      ns.UI.RouteRemaining = function() return 99 end -- retired: never read
      eq(lines(), { "MountTrail", "Left-click: open/close" })
      ns.UI.ChecklistRemaining = function() return 7 end
      eq(lines(), { "MountTrail", "Left-click: open/close", "Checklist: 7 lockouts left" })
    end)

    it("sets up immediately when loaded after login", function()
      reset_ui_stub()
      fire_frame_event("PLAYER_LOGIN") -- marks logged in
      local files = toc_lua_files()
      local ns = load_addon(files)
      ns.addon:OnInitialize()
      local chunk = assert(loadfile(ROOT .. "/UI/Frame.lua"))
      chunk("MountTrail", ns)
      ok(LDB.objects.MountTrail, "launcher created without waiting for PLAYER_LOGIN")
    end)
  end)
end)
