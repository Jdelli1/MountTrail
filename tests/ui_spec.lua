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
    eq(f.template, "PortraitFrameTemplate")
    eq({ f:GetSize() }, { 800, 560 })
    eq(f.title, "AzerothTrail")
    eq(f.portraitAsset, 132261)
    ok(f.movable and f.clamped, "movable and clamped")
    eq(f.numTabs, 4)
    eq(f.Tabs[4]:GetText(), "Route")
    eq(f.Tabs[1].template, "PanelTabButtonTemplate")
    eq(f.selectedTab, 1, "journal by default")
    eq(UISpecialFrames, { "AzerothTrailFrame" })
    ns.ToggleWindow()
    ok(not f:IsShown(), "second toggle hides")
  end)

  it("builds a view the first time its tab is shown and refreshes only the visible tab", function()
    local ns = loadUI()
    local journal, route = countingView(), countingView()
    ns.UI.RegisterView("journal", journal)
    ns.UI.RegisterView("route", route)
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

    ns.UI.SelectTab("route")
    eq(route.builds, 1)
    eq(route.refreshes, 1)
    ok(route.parent:IsShown() and not journal.parent:IsShown(), "only the selected content is shown")
    eq(ns.UI.frame.selectedTab, 4)
    eq(ns.db.global.window.tab, "route")

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
    local misc = countingView()
    ns.UI.RegisterView("misc", misc)
    ns.ToggleWindow()
    ns.UI.frame.Tabs[3]:RunScript("OnClick", "LeftButton")
    eq(ns.UI.frame.selectedTab, 3)
    eq(misc.builds, 1)
  end)

  it("shows a Coming soon placeholder until a view is registered", function()
    local ns = loadUI()
    ns.ToggleWindow()
    ns.UI.SelectTab("holidays")
    local contents = ns.UI.frame.Inset.children
    eq(#contents, 4, "one content frame per tab")
    local holidaysContent = contents[2]
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
    eq(ns.UI.frame.selectedTab, 3)
    eq({ ns.UI.frame:GetPoint(1) }, { "TOPLEFT", UIParent, "TOPLEFT", 100, -50 })
  end)

  it("falls back to journal for an unknown saved tab", function()
    local ns = loadUI({ window = { tab = "bogus" } })
    ns.ToggleWindow()
    eq(ns.UI.frame.selectedTab, 1)
    eq(ns.db.global.window.tab, "journal")
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

    it("tooltip shows the title, the hint and route steps when known", function()
      local ns = loadUI()
      fire_frame_event("PLAYER_LOGIN")
      local obj = LDB.objects.AzerothTrail
      local function lines()
        local out = {}
        obj.OnTooltipShow({ AddLine = function(_, text) out[#out + 1] = text end })
        return out
      end
      eq(lines(), { "AzerothTrail", "Left-click: open/close" })
      ns.UI.RouteRemaining = function() return 7 end
      eq(lines(), { "AzerothTrail", "Left-click: open/close", "Route: 7 steps left" })
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
