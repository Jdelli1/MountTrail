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
    local fh = assert(io.open(ROOT .. "/AzerothTrail.toc", "r"))
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
    eq(f:GetName(), "AzerothTrailFrame")
    eq(f.template, "PortraitFrameFlatTemplate", "modern flat window")
    eq({ f:GetSize() }, { 800, 560 })
    eq(f.title, "AzerothTrail")
    eq(f.portraitAsset, 132261)
    ok(f.movable and f.clamped, "movable and clamped")
    eq(f.numTabs, 6)
    local labels = {}
    for i, tab in ipairs(f.Tabs) do labels[i] = tab:GetText() end
    eq(labels, { "Journal", "Holidays", "Achievements", "Timewalking", "Misc", "Checklist" })
    eq(f.Tabs[1].template, "PanelTopTabButtonTemplate", "modern top tabs")
    ok(f.topTabs and f.isFlat, "flat window with top tabs")
    eq({ f.Tabs[1]:GetPoint(1) }, { "BOTTOMLEFT", f.Inset, "TOPLEFT", 60, 0 }, "tabs sit on the content's top edge")
    eq(f.Inset.template, nil, "flat content area, no classic inset")
    eq(f.Inset.Fill:GetParent(), f.Inset, "flat fill drawn on the inset")
    eq(f.Inset.Fill.color, { 0, 0, 0, 0.3 })
    eq(#f.Inset.Edge.edges, 4, "faint 1 px edge")
    eq(next(ns.UI.TemplateFallbacks), nil, "no fallback used")
    eq(f.selectedTab, 1, "journal by default")
    eq(UISpecialFrames, { "AzerothTrailFrame" })
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
    eq(ns.UI.frame.selectedTab, 6)
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

  it("tab buttons select their tab", function()
    local ns = loadUI()
    local views = {}
    for _, key in ipairs({ "journal", "holidays", "achievements", "timewalking", "misc", "checklist" }) do
      views[key] = countingView()
      ns.UI.RegisterView(key, views[key])
    end
    ns.ToggleWindow()
    ns.UI.frame.Tabs[3]:RunScript("OnClick", "LeftButton")
    eq(ns.UI.frame.selectedTab, 3)
    eq(views.achievements.builds, 1)
    eq(ns.db.global.window.tab, "achievements")
    ns.UI.frame.Tabs[4]:RunScript("OnClick", "LeftButton")
    eq(views.timewalking.builds, 1)
    eq(ns.db.global.window.tab, "timewalking")
    ns.UI.frame.Tabs[5]:RunScript("OnClick", "LeftButton")
    eq(views.misc.builds, 1)
  end)

  it("sizes the six tabs to their text within fixed bounds that fit the window", function()
    local ns = loadUI()
    ns.ToggleWindow()
    local f = ns.UI.frame
    local size = ns.UI.TabSize
    eq(size, { padding = 10, min = 70, max = 116 })
    for i, tab in ipairs(f.Tabs) do
      eq(tab.resized, { padding = 10, minWidth = 70, maxWidth = 116 }, "tab " .. i)
    end
    -- Worst case (every label at the cap): the first tab starts 60 px into
    -- the 6 px inset, tabs are 2 px apart and the last tab's right edge
    -- texture overhangs 8 px; all of it must stay inside the 800 px window.
    local worst = 6 + 60 + #f.Tabs * size.max + (#f.Tabs - 1) * 2 + 8
    ok(worst <= 800, "six tabs fit: " .. worst)
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
    eq(n, 6, "one content frame per tab")
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
    eq(ns.UI.frame.selectedTab, 5)
    eq({ ns.UI.frame:GetPoint(1) }, { "TOPLEFT", UIParent, "TOPLEFT", 100, -50 })
  end)

  it("falls back to journal for an unknown saved tab", function()
    local ns = loadUI({ window = { tab = "bogus" } })
    ns.ToggleWindow()
    eq(ns.UI.frame.selectedTab, 1)
    eq(ns.db.global.window.tab, "journal")
  end)

  it("the retired Route tab's key opens the Checklist tab (F16)", function()
    local ns = loadUI({ window = { tab = "route" } })
    eq(ns.UI.TabKey("route"), "checklist")
    eq(ns.UI.TabKey("misc"), "misc")
    eq(ns.UI.TabKey(nil), "journal")
    ns.ToggleWindow()
    eq(ns.UI.frame.selectedTab, 6)
    eq(ns.db.global.window.tab, "checklist")
    ns.UI.SelectTab("route")
    eq(ns.db.global.window.tab, "checklist", "SelectTab maps it too")
    ok(not pcall(ns.UI.RegisterView, "route", countingView()), "no view registers as route any more")
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

  it("falls back to the classic window, inset and bottom tabs without the modern templates", function()
    local ns = loadUI()
    STUB_TEMPLATES.PortraitFrameFlatTemplate = nil
    STUB_TEMPLATES.PanelTopTabButtonTemplate = nil
    ns.ToggleWindow()
    local f = ns.UI.frame
    ok(f:IsShown(), "window still opens")
    eq(f.template, "PortraitFrameTemplate")
    eq(f.portraitAsset, 132261)
    eq(f.Inset.template, "InsetFrameTemplate")
    eq(f.Inset.Fill, nil, "classic inset draws its own background")
    eq(f.Tabs[1].template, "PanelTabButtonTemplate")
    eq({ f.Tabs[1]:GetPoint(1) }, { "TOPLEFT", f, "BOTTOMLEFT", 11, 2 }, "tabs under the window")
    eq(ns.UI.TemplateFallbacks, {
      PortraitFrameFlatTemplate = "PortraitFrameTemplate",
      PanelTopTabButtonTemplate = "PanelTabButtonTemplate",
    })
    ns.UI.SelectTab("checklist")
    eq(f.selectedTab, 6, "tabs still work")
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

    it("reports a fallback once through /azt debug's error handler", function()
      local ns = loadUI({ debug = true })
      local got = {}
      local old = geterrorhandler
      geterrorhandler = function() return function(msg) got[#got + 1] = msg end end
      ns.UI.Template("NoSuchTemplate", "UIPanelButtonTemplate")
      ns.UI.Template("NoSuchTemplate", "UIPanelButtonTemplate")
      geterrorhandler = old
      eq(got, { "AzerothTrail: template NoSuchTemplate missing, using UIPanelButtonTemplate" })
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

    it("/azt debug lists the fallbacks when turned on", function()
      local ns = loadUI()
      ns.UI.Template("NoSuchTemplate", "UIPanelButtonTemplate")
      ns.UI.Template("AlsoMissing")
      run_slash(ns.addon, "azt", "debug")
      local n = #ns.addon.printed
      eq({ ns.addon.printed[n - 1], ns.addon.printed[n] }, {
        "Template AlsoMissing missing, using none",
        "Template NoSuchTemplate missing, using UIPanelButtonTemplate",
      })
      run_slash(ns.addon, "azt", "debug")
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
      eq(LDB.objects.AzerothTrail, nil, "nothing before login")
      fire_frame_event("PLAYER_LOGIN")
      local obj = LDB.objects.AzerothTrail
      ok(obj, "launcher created")
      eq(obj.type, "launcher")
      eq(obj.icon, 132261)
      eq(DBIcon.registered.AzerothTrail.db, ns.db.global.minimap)
      fire_frame_event("PLAYER_LOGIN") -- a second fire must not re-register
    end)

    it("left-click toggles the window", function()
      local ns = loadUI()
      fire_frame_event("PLAYER_LOGIN")
      local obj = LDB.objects.AzerothTrail
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
      local obj = LDB.objects.AzerothTrail
      local function lines()
        local out = {}
        obj.OnTooltipShow({ AddLine = function(_, text) out[#out + 1] = text end })
        return out
      end
      eq(lines(), { "AzerothTrail", "Left-click: open/close" })
      ns.UI.RouteRemaining = function() return 99 end -- retired: never read
      eq(lines(), { "AzerothTrail", "Left-click: open/close" })
      ns.UI.ChecklistRemaining = function() return 7 end
      eq(lines(), { "AzerothTrail", "Left-click: open/close", "Checklist: 7 lockouts left" })
    end)

    it("sets up immediately when loaded after login", function()
      reset_ui_stub()
      fire_frame_event("PLAYER_LOGIN") -- marks logged in
      local files = toc_lua_files()
      local ns = load_addon(files)
      ns.addon:OnInitialize()
      local chunk = assert(loadfile(ROOT .. "/UI/Frame.lua"))
      chunk("AzerothTrail", ns)
      ok(LDB.objects.AzerothTrail, "launcher created without waiting for PLAYER_LOGIN")
    end)
  end)
end)
