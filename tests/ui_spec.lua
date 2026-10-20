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
    eq(f.template, "PortraitFrameFlatTemplate", "modern flat window")
    eq({ f:GetSize() }, { 900, 560 })
    eq(f.title, "MountTrail")
    eq(f.portraitAsset, 132261)
    ok(f.movable and f.clamped, "movable and clamped")
    -- The navigation column on the left (no tabs), the views right of it.
    ok(f.Nav and f.isFlat, "flat window with a navigation column")
    eq(f.Tabs, nil, "no tab buttons")
    eq({ f.Nav:GetPoint(1) }, { "TOPLEFT", f, "TOPLEFT", 6, -60 }, "under the portrait")
    eq(f.Nav.width, ns.UI.NAV_WIDTH)
    eq({ f.Inset:GetPoint(1) }, { "TOPLEFT", f, "TOPLEFT", 6 + ns.UI.NAV_WIDTH + 4, -34 }, "views right of it, clear of the title bar")
    local labels = {}
    for i = 1, f.Nav.shown do labels[i] = f.Nav.Buttons[i].Text:GetText() end
    eq({ labels[1], labels[2], labels[3] }, { "Home", "Today", "Here" })
    ok(labels[4]:find("^Alts"), labels[4])
    eq({ labels[5], labels[8] }, { "Holidays", "Misc" })
    eq(f.Inset.template, nil, "flat content area, no classic inset")
    eq(f.Inset.Fill:GetParent(), f.Inset, "flat fill drawn on the inset")
    eq(f.Inset.Fill.color, { 0, 0, 0, 0.3 })
    eq(#f.Inset.Edge.edges, 4, "faint 1 px edge")
    eq(next(ns.UI.TemplateFallbacks), nil, "no fallback used")
    eq(ns.UI.CurrentTab(), "journal", "Home by default")
    ok(f.Nav.Buttons[1].selected and f.Nav.Buttons[1].Bar:IsShown(), "Home marked")
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
    for _, key in ipairs({ "journal", "holidays", "achievements", "timewalking", "misc", "checklist", "here" }) do
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
    button("Today"):RunScript("OnClick", "LeftButton")
    eq(views.checklist.builds, 1)
    button("Here"):RunScript("OnClick", "LeftButton")
    eq(views.here.builds, 1)
    local alts = 0
    ns.UI.ToggleAltsWindow = function() alts = alts + 1 end
    button("Alts"):RunScript("OnClick", "LeftButton")
    eq(alts, 1)
    eq(ns.UI.CurrentTab(), "here", "Alts is a window, not a view")
    -- Browse entries are indented under their heading.
    local function leftInset(b)
      for i = 1, b.Text:GetNumPoints() do
        local p, _, _, x = b.Text:GetPoint(i)
        if p == "LEFT" then return x end
      end
    end
    eq(leftInset(button("Holidays")), 18)
    eq(leftInset(button("Today")), 12)
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
    eq(n, 7, "one content frame per view")
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

  it("the retired Route tab's key opens the Checklist tab (F16)", function()
    local ns = loadUI({ window = { tab = "route" } })
    eq(ns.UI.TabKey("route"), "checklist")
    eq(ns.UI.TabKey("misc"), "misc")
    eq(ns.UI.TabKey(nil), "journal")
    ns.ToggleWindow()
    eq(ns.UI.CurrentTab(), "checklist")
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

  it("falls back to the classic window and inset without the modern templates", function()
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
    ok(f.Nav, "the navigation column still there")
    eq(ns.UI.TemplateFallbacks, { PortraitFrameFlatTemplate = "PortraitFrameTemplate" })
    ns.UI.SelectTab("checklist")
    eq(ns.UI.CurrentTab(), "checklist", "views still switch")
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
