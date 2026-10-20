-- UI/Options.lua (F9): the MountTrail page under Options > AddOns, built
-- with the modern Settings API (vertical layout + proxy settings). A fake
-- `Settings` table records what the page registers; the getters / setters
-- are then driven directly.

local function loadOptions(opts)
  opts = opts or {}
  reset_ui_stub()
  local files = toc_lua_files()
  files[#files + 1] = "UI/Options.lua"
  local ns = load_addon(files)
  if not opts.noInit then ns.addon:OnInitialize() end
  return ns
end

-- A fake Settings API (the subset UI/Options.lua uses). Each proxy setting
-- is kept by variable in S.settings with its getter / setter; dropdown and
-- checkbox controls in S.controls (in order); calls in S.log.
local function fakeSettings()
  local S = { log = {}, settings = {}, controls = {}, VarType = { Boolean = "boolean", String = "string", Number = "number" } }
  local function rec(...) S.log[#S.log + 1] = { ... } end
  function S.RegisterVerticalLayoutCategory(name)
    rec("Category", name)
    local category = { name = name }
    function category:GetID() return 77 end
    S.category = category
    return category, { initializers = {} }
  end
  function S.RegisterProxySetting(category, variable, varType, name, default, get, set)
    rec("Setting", variable)
    local setting = { category = category, variable = variable, varType = varType, name = name,
      default = default, get = get, set = set }
    S.settings[variable] = setting
    return setting
  end
  function S.CreateDropdown(category, setting, options, tooltip)
    rec("Dropdown", setting.variable)
    S.controls[#S.controls + 1] = { kind = "dropdown", category = category, setting = setting,
      options = options, tooltip = tooltip }
    return {}
  end
  function S.CreateCheckbox(category, setting, tooltip)
    rec("Checkbox", setting.variable)
    S.controls[#S.controls + 1] = { kind = "checkbox", category = category, setting = setting, tooltip = tooltip }
    return {}
  end
  function S.CreateSliderOptions(min, max, step)
    local o = { min = min, max = max, step = step }
    function o:SetLabelFormatter(where, fn) self.format = fn end
    return o
  end
  function S.CreateSlider(category, setting, options, tooltip)
    rec("Slider", setting.variable)
    S.controls[#S.controls + 1] = { kind = "slider", category = category, setting = setting,
      options = options, tooltip = tooltip }
    return {}
  end
  function S.CreateControlTextContainer()
    local container = { data = {} }
    function container:Add(value, label, tooltip)
      local d = { value = value, label = label, text = label, tooltip = tooltip }
      self.data[#self.data + 1] = d
      return d
    end
    function container:GetData() return self.data end
    return container
  end
  function S.RegisterAddOnCategory(category) rec("AddOnCategory", category) end
  function S.OpenToCategory(id, element) rec("Open", id, element) end
  function S.NotifyUpdate(variable) rec("Notify", variable) end
  return S
end

local function logOf(S, what)
  local out = {}
  for _, e in ipairs(S.log) do if e[1] == what then out[#out + 1] = e end end
  return out
end

-- Runs fn with the global Settings (and TomTom) swapped in, restoring both.
local function withGlobals(settings, tomtom, fn)
  local oldSettings, oldTomTom = Settings, TomTom
  Settings, TomTom = settings, tomtom
  local good, err = pcall(fn)
  Settings, TomTom = oldSettings, oldTomTom
  if not good then error(err, 0) end
end

describe("options", function()
  it("toc lists UI\\Options.lua last, after UI\\MapTab.lua (after UI\\ZonePanel.lua)", function()
    local fh = assert(io.open(ROOT .. "/MountTrail.toc", "r"))
    local lines = {}
    for line in fh:lines() do
      line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if line ~= "" and not line:find("^#") then lines[#lines + 1] = line end
    end
    fh:close()
    eq(lines[#lines], "UI\\Options.lua")
    eq(lines[#lines - 1], "UI\\MapTab.lua")
    eq(lines[#lines - 2], "UI\\ZonePanel.lua")
  end)

  it("db default: unobtainable mounts hidden; no Waypoints setting (TomTom is required)", function()
    local ns = loadOptions()
    eq(ns.db.global.settings, { showUnobtainable = false, rarityColors = false })
  end)

  describe("Register", function()
    it("registers a vertical-layout AddOns category with the four controls", function()
      local ns = loadOptions()
      local S = fakeSettings()
      local category = ns.Options.Register(S)
      ok(category, "returns the category")
      eq(category, S.category)
      eq(ns.Options.category, category)
      eq(S.log, {
        { "Category", "MountTrail" },
        { "Setting", "MOUNTTRAIL_UNOBTAINABLE" },
        { "Checkbox", "MOUNTTRAIL_UNOBTAINABLE" },
        { "Setting", "MOUNTTRAIL_RARITY_COLORS" },
        { "Checkbox", "MOUNTTRAIL_RARITY_COLORS" },
        { "Setting", "MOUNTTRAIL_DIFFICULTY_WARNING" },
        { "Checkbox", "MOUNTTRAIL_DIFFICULTY_WARNING" },
        { "Setting", "MOUNTTRAIL_WINDOW_SCALE" },
        { "Slider", "MOUNTTRAIL_WINDOW_SCALE" },
        { "Setting", "MOUNTTRAIL_TEXT_HEADER" },
        { "Slider", "MOUNTTRAIL_TEXT_HEADER" },
        { "Setting", "MOUNTTRAIL_TEXT_BODY" },
        { "Slider", "MOUNTTRAIL_TEXT_BODY" },
        { "Setting", "MOUNTTRAIL_TEXT_DETAIL" },
        { "Slider", "MOUNTTRAIL_TEXT_DETAIL" },
        { "Setting", "MOUNTTRAIL_NAV_TEXT" },
        { "Slider", "MOUNTTRAIL_NAV_TEXT" },
        { "Setting", "MOUNTTRAIL_SHOW_LISTS" },
        { "Checkbox", "MOUNTTRAIL_SHOW_LISTS" },
        { "Setting", "MOUNTTRAIL_SHOW_QUICK" },
        { "Checkbox", "MOUNTTRAIL_SHOW_QUICK" },
        { "Setting", "MOUNTTRAIL_MINIMAP" },
        { "Checkbox", "MOUNTTRAIL_MINIMAP" },
        { "Setting", "MOUNTTRAIL_DEBUG" },
        { "Checkbox", "MOUNTTRAIL_DEBUG" },
        { "AddOnCategory", category },
      })
      local mm, dbg = S.settings.MOUNTTRAIL_MINIMAP, S.settings.MOUNTTRAIL_DEBUG
      local un = S.settings.MOUNTTRAIL_UNOBTAINABLE
      eq({ un.varType, un.name, un.default }, { "boolean", "Show unobtainable mounts", false })
      eq({ mm.varType, mm.name, mm.default }, { "boolean", "Show minimap button", true })
      eq({ dbg.varType, dbg.name, dbg.default }, { "boolean", "Debug messages", false })
      for _, c in ipairs(S.controls) do
        eq(c.category, category)
        eq(type(c.tooltip), "string", c.setting.variable .. " has a tooltip")
      end
    end)

    it("is skipped (nil, no error) without the Settings API or before ns.db", function()
      local ns = loadOptions()
      eq(ns.Options.Register(nil), nil, "no Settings at all")
      local S = fakeSettings()
      S.RegisterVerticalLayoutCategory = nil
      eq(ns.Options.Register(S), nil, "no vertical layout")
      S = fakeSettings()
      S.CreateCheckbox = nil
      eq(ns.Options.Register(S), nil, "no checkbox")
      eq(#logOf(S, "AddOnCategory"), 0)
      local early = loadOptions({ noInit = true })
      S = fakeSettings()
      eq(early.Options.Register(S), nil, "no ns.db yet")
      eq(S.log, {})
    end)

    it("a Settings call that errors is caught and reported (/mtrail debug)", function()
      local ns = loadOptions()
      local reported = {}
      ns.Game.ReportError = function(err) reported[#reported + 1] = tostring(err) end
      local S = fakeSettings()
      S.CreateCheckbox = function() error("checkbox broke") end
      eq(ns.Options.Register(S), nil)
      eq(#reported, 1)
      ok(reported[1]:find("checkbox broke", 1, true), reported[1])
      eq(#logOf(S, "AddOnCategory"), 0, "no half-built page")
    end)

    it("registers once", function()
      local ns = loadOptions()
      local S = fakeSettings()
      local first = ns.Options.Register(S)
      eq(ns.Options.Register(S), first)
      eq(#logOf(S, "Category"), 1)
    end)
  end)

  it("an old Waypoints setting is dropped on load", function()
    local ns = loadOptions({ noInit = true })
    local AceDB = LibStub("AceDB-3.0")
    local real = AceDB.New
    AceDB.New = function(self, name, defaults)
      local db = real(self, name, defaults)
      db.global.settings.waypoints = "both" -- saved by an earlier version
      return db
    end
    local good, err = pcall(ns.addon.OnInitialize, ns.addon)
    AceDB.New = real
    ok(good, tostring(err))
    eq(ns.db.global.settings.waypoints, nil)
    eq(ns.db.global.settings.showUnobtainable, false)
  end)

  describe("rarity colours checkbox", function()
    it("reads and writes ns.db.global.settings.rarityColors and refreshes", function()
      local ns = loadOptions()
      local refreshed = 0
      ns.Refresh = function() refreshed = refreshed + 1 end
      local S = fakeSettings()
      ns.Options.Register(S)
      local rc = S.settings.MOUNTTRAIL_RARITY_COLORS
      eq({ rc.varType, rc.name, rc.default }, { "boolean", "Colour pop-out names by rarity", false })
      eq(rc.get(), false)
      rc.set(true)
      eq(ns.db.global.settings.rarityColors, true)
      eq(ns.Options.RarityColors(), true)
      eq(refreshed, 1)
      local rcTip
      for _, c in ipairs(S.controls) do if c.setting == rc then rcTip = c.tooltip end end
      ok(rcTip:find("Mount Journal Enhanced", 1, true), "says where the data comes from")
    end)
  end)

  describe("text size sliders", function()
    it("window scale 80-150 % in 5 % steps and navigation text +0 to +6, saved and applied", function()
      local ns = loadOptions()
      local applied, navs = 0, 0
      ns.UI = ns.UI or {}
      ns.UI.ApplyWindowScale = function() applied = applied + 1 end
      ns.UI.RefreshNav = function() navs = navs + 1 end
      local S = fakeSettings()
      ns.Options.Register(S)
      local scale, nav = S.settings.MOUNTTRAIL_WINDOW_SCALE, S.settings.MOUNTTRAIL_NAV_TEXT
      eq({ scale.default, nav.default }, { 100, 2 })
      eq(scale.get(), 100)
      scale.set(123)
      eq(ns.db.global.settings.windowScale, 125, "to the 5 % step")
      eq(applied, 1)
      scale.set(500)
      eq(scale.get(), 150, "no more than 150 %")
      nav.set(9)
      eq(nav.get(), 6)
      eq(navs, 1)
      local slider
      for _, c in ipairs(S.controls) do if c.kind == "slider" and c.setting == scale then slider = c end end
      eq({ slider.options.min, slider.options.max, slider.options.step }, { 80, 150, 5 })
    end)

    it("no sliders (and no such settings) on clients without Settings.CreateSlider", function()
      local ns = loadOptions()
      local S = fakeSettings()
      S.CreateSlider = nil
      ns.Options.Register(S)
      eq(S.settings.MOUNTTRAIL_WINDOW_SCALE, nil)
      eq(ns.Options.WindowScale(), 100)
    end)
  end)

  describe("unobtainable checkbox", function()
    it("reads and writes ns.db.global.settings.showUnobtainable and refreshes the window", function()
      local ns = loadOptions()
      local refreshed = 0
      ns.Refresh = function() refreshed = refreshed + 1 end
      local S = fakeSettings()
      ns.Options.Register(S)
      local un = S.settings.MOUNTTRAIL_UNOBTAINABLE
      eq(un.get(), false)
      un.set(true)
      eq(ns.db.global.settings.showUnobtainable, true)
      eq(un.get(), true)
      eq(refreshed, 1, "the open window updates")
      un.set(false)
      eq(ns.db.global.settings.showUnobtainable, false)
      eq(refreshed, 2)
      ns.db.global.settings.showUnobtainable = "junk"
      eq(un.get(), false, "only true counts as on")
      ok(S.controls[1].tooltip:find("Misc", 1, true), "the tooltip says where they show")
    end)

    it("ShowUnobtainable reads the saved setting (false without a db)", function()
      local ns = loadOptions()
      eq(ns.Options.ShowUnobtainable(), false)
      ns.db.global.settings.showUnobtainable = true
      eq(ns.Options.ShowUnobtainable(), true)
      ns.db.global.settings = nil
      eq(ns.Options.ShowUnobtainable(), false)
      local early = loadOptions({ noInit = true })
      eq(early.Options.ShowUnobtainable(), false)
    end)

    it("ShowUnobtainable delegates to UI.ShowUnobtainable when the list is loaded", function()
      local ns = loadOptions()
      ns.UI = ns.UI or {}
      local answer = true
      ns.UI.ShowUnobtainable = function() return answer end
      eq(ns.Options.ShowUnobtainable(), true, "the list's reader, not the saved false")
      answer = false
      eq(ns.Options.ShowUnobtainable(), false)
    end)
  end)

  describe("minimap checkbox", function()
    it("reads the LibDBIcon db and shows / hides the button", function()
      local ns = loadOptions()
      local DBIcon = LibStub("LibDBIcon-1.0")
      local calls = {}
      DBIcon.Show = function(_, name) calls[#calls + 1] = { "Show", name } end
      DBIcon.Hide = function(_, name) calls[#calls + 1] = { "Hide", name } end
      local S = fakeSettings()
      ns.Options.Register(S)
      local mm = S.settings.MOUNTTRAIL_MINIMAP
      eq(mm.get(), true)
      mm.set(false)
      eq(ns.db.global.minimap.hide, true)
      eq(mm.get(), false)
      mm.set(true)
      eq(ns.db.global.minimap.hide, false)
      eq(calls, { { "Hide", "MountTrail" }, { "Show", "MountTrail" } })
      DBIcon.Show, DBIcon.Hide = nil, nil
      mm.set(false) -- a LibDBIcon without Show / Hide: the db still changes
      eq(ns.db.global.minimap.hide, true)
    end)
  end)

  describe("debug checkbox", function()
    it("is the same flag as /mtrail debug", function()
      local ns = loadOptions()
      local S = fakeSettings()
      ns.Options.Register(S)
      local dbg = S.settings.MOUNTTRAIL_DEBUG
      eq(dbg.get(), false)
      dbg.set(true)
      eq(ns.db.global.debug, true)
      ns.db.global.debug = false
      eq(dbg.get(), false)
    end)

    it("/mtrail debug tells the open settings page (Settings.NotifyUpdate)", function()
      local ns = loadOptions()
      local S = fakeSettings()
      ns.Options.Register(S)
      withGlobals(S, nil, function()
        run_slash(ns.addon, "azt", "debug")
      end)
      eq(ns.db.global.debug, true)
      eq(logOf(S, "Notify"), { { "Notify", "MOUNTTRAIL_DEBUG" } })
    end)
  end)

  describe("Open and /mtrail options", function()
    it("opens the settings panel at the category ID", function()
      local ns = loadOptions()
      local S = fakeSettings()
      ns.Options.Register(S)
      eq(ns.Options.Open(S), true)
      eq(logOf(S, "Open"), { { "Open", 77 } })
    end)

    it("registers the page first when login did not", function()
      local ns = loadOptions()
      local S = fakeSettings()
      eq(ns.Options.Open(S), true)
      eq(#logOf(S, "AddOnCategory"), 1)
      eq(logOf(S, "Open"), { { "Open", 77 } })
    end)

    it("says so when the page could not be registered", function()
      local ns = loadOptions()
      local S = fakeSettings()
      S.RegisterVerticalLayoutCategory = nil
      eq(ns.Options.Open(S), false)
      eq(logOf(S, "Open"), {})
      ok(ns.addon.printed[#ns.addon.printed]:find("not available", 1, true), "prints why")
    end)

    it("/mtrail options opens the page; help lists it", function()
      local ns = loadOptions()
      local S = fakeSettings()
      withGlobals(S, nil, function()
        ns.Options.Register(S)
        run_slash(ns.addon, "azt", "options")
        run_slash(ns.addon, "azt", " OPTIONS ")
      end)
      eq(logOf(S, "Open"), { { "Open", 77 }, { "Open", 77 } })
      run_slash(ns.addon, "azt", "help")
      ok(table.concat(ns.addon.printed, "\n"):find("/mtrail options", 1, true), "help mentions /mtrail options")
    end)
  end)

  describe("PLAYER_LOGIN", function()
    it("registers the page on login, once, with the global Settings", function()
      local S = fakeSettings()
      withGlobals(S, nil, function()
        local ns = loadOptions()
        eq(#logOf(S, "Category"), 0, "nothing before login")
        fire_frame_event("PLAYER_LOGIN")
        eq(#logOf(S, "Category"), 1)
        ok(ns.Options.category, "category kept")
        fire_frame_event("PLAYER_LOGIN")
        eq(#logOf(S, "Category"), 1, "not twice")
      end)
    end)

    it("without the Settings API login does nothing and raises nothing", function()
      withGlobals(nil, nil, function()
        local ns = loadOptions()
        fire_frame_event("PLAYER_LOGIN")
        eq(ns.Options.category, nil)
      end)
    end)
  end)
end)
