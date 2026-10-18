-- UI/Options.lua (F9): the AzerothTrail page under Options > AddOns, built
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
  it("toc lists UI\\Options.lua last, after UI\\ZonePanel.lua", function()
    local fh = assert(io.open(ROOT .. "/AzerothTrail.toc", "r"))
    local lines = {}
    for line in fh:lines() do
      line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if line ~= "" and not line:find("^#") then lines[#lines + 1] = line end
    end
    fh:close()
    eq(lines[#lines], "UI\\Options.lua")
    eq(lines[#lines - 1], "UI\\ZonePanel.lua")
  end)

  it("db default: settings.waypoints is the in-game pin", function()
    local ns = loadOptions()
    eq(ns.db.global.settings, { waypoints = "game" })
  end)

  describe("Register", function()
    it("registers a vertical-layout AddOns category with the three controls", function()
      local ns = loadOptions()
      local S = fakeSettings()
      local category = ns.Options.Register(S)
      ok(category, "returns the category")
      eq(category, S.category)
      eq(ns.Options.category, category)
      eq(S.log, {
        { "Category", "AzerothTrail" },
        { "Setting", "AZEROTHTRAIL_WAYPOINTS" },
        { "Dropdown", "AZEROTHTRAIL_WAYPOINTS" },
        { "Setting", "AZEROTHTRAIL_MINIMAP" },
        { "Checkbox", "AZEROTHTRAIL_MINIMAP" },
        { "Setting", "AZEROTHTRAIL_DEBUG" },
        { "Checkbox", "AZEROTHTRAIL_DEBUG" },
        { "AddOnCategory", category },
      })
      local wp, mm, dbg = S.settings.AZEROTHTRAIL_WAYPOINTS, S.settings.AZEROTHTRAIL_MINIMAP, S.settings.AZEROTHTRAIL_DEBUG
      eq({ wp.varType, wp.name, wp.default }, { "string", "Waypoints", "game" })
      eq({ mm.varType, mm.name, mm.default }, { "boolean", "Show minimap button", true })
      eq({ dbg.varType, dbg.name, dbg.default }, { "boolean", "Debug messages", false })
      for _, c in ipairs(S.controls) do
        eq(c.category, category)
        eq(type(c.tooltip), "string", c.setting.variable .. " has a tooltip")
      end
      ok(S.controls[1].tooltip:find("TomTom", 1, true), "the dropdown tooltip carries the TomTom note")
    end)

    it("is skipped (nil, no error) without the Settings API or before ns.db", function()
      local ns = loadOptions()
      eq(ns.Options.Register(nil), nil, "no Settings at all")
      local S = fakeSettings()
      S.RegisterVerticalLayoutCategory = nil
      eq(ns.Options.Register(S), nil, "no vertical layout")
      S = fakeSettings()
      S.CreateControlTextContainer = nil
      eq(ns.Options.Register(S), nil, "no text container")
      eq(#logOf(S, "AddOnCategory"), 0)
      local early = loadOptions({ noInit = true })
      S = fakeSettings()
      eq(early.Options.Register(S), nil, "no ns.db yet")
      eq(S.log, {})
    end)

    it("a Settings call that errors is caught and reported (/azt debug)", function()
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

  describe("waypoints dropdown", function()
    it("reads and writes ns.db.global.settings.waypoints; unknown values are ignored", function()
      local ns = loadOptions()
      local S = fakeSettings()
      ns.Options.Register(S)
      local wp = S.settings.AZEROTHTRAIL_WAYPOINTS
      eq(wp.get(), "game")
      wp.set("tomtom")
      eq(ns.db.global.settings.waypoints, "tomtom")
      eq(wp.get(), "tomtom")
      eq(ns.Map.WaypointMode(), "tomtom", "Map.SetWaypoint follows it")
      wp.set("both")
      eq(ns.db.global.settings.waypoints, "both")
      wp.set("arrow")
      eq(ns.db.global.settings.waypoints, "both", "unknown value ignored")
      ns.db.global.settings.waypoints = "junk"
      eq(wp.get(), "game", "a junk saved value reads as the default")
    end)

    it("offers the three modes; TomTom ones say they fall back when TomTom is not loaded", function()
      local ns = loadOptions()
      local S = fakeSettings()
      ns.Options.Register(S)
      local options = S.controls[1].options
      eq(type(options), "function", "an options generator")
      withGlobals(nil, { AddWaypoint = function() end }, function()
        local data = options()
        eq(#data, 3)
        eq({ data[1].value, data[1].label }, { "game", "In-game map pin" })
        eq({ data[2].value, data[2].label }, { "tomtom", "TomTom arrow" })
        eq({ data[3].value, data[3].label }, { "both", "Both" })
      end)
      withGlobals(nil, nil, function()
        local data = options()
        eq({ data[1].value, data[1].label }, { "game", "In-game map pin" })
        eq({ data[2].value, data[2].label }, { "tomtom", "TomTom arrow (not loaded)" })
        eq({ data[3].value, data[3].label }, { "both", "Both (TomTom not loaded)" })
        ok(data[2].tooltip:find("in-game map pin", 1, true), "tooltip explains the fallback")
        ok(data[3].tooltip:find("in-game map pin", 1, true), "tooltip explains the fallback")
      end)
    end)

    it("WaypointOptions is pure: labels per TomTom state", function()
      local ns = loadOptions()
      local loaded, missing = ns.Options.WaypointOptions(true), ns.Options.WaypointOptions(false)
      eq(loaded[2].label, "TomTom arrow")
      eq(missing[2].label, "TomTom arrow (not loaded)")
      eq(missing[1].label, "In-game map pin")
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
      local mm = S.settings.AZEROTHTRAIL_MINIMAP
      eq(mm.get(), true)
      mm.set(false)
      eq(ns.db.global.minimap.hide, true)
      eq(mm.get(), false)
      mm.set(true)
      eq(ns.db.global.minimap.hide, false)
      eq(calls, { { "Hide", "AzerothTrail" }, { "Show", "AzerothTrail" } })
      DBIcon.Show, DBIcon.Hide = nil, nil
      mm.set(false) -- a LibDBIcon without Show / Hide: the db still changes
      eq(ns.db.global.minimap.hide, true)
    end)
  end)

  describe("debug checkbox", function()
    it("is the same flag as /azt debug", function()
      local ns = loadOptions()
      local S = fakeSettings()
      ns.Options.Register(S)
      local dbg = S.settings.AZEROTHTRAIL_DEBUG
      eq(dbg.get(), false)
      dbg.set(true)
      eq(ns.db.global.debug, true)
      ns.db.global.debug = false
      eq(dbg.get(), false)
    end)

    it("/azt debug tells the open settings page (Settings.NotifyUpdate)", function()
      local ns = loadOptions()
      local S = fakeSettings()
      ns.Options.Register(S)
      withGlobals(S, nil, function()
        run_slash(ns.addon, "azt", "debug")
      end)
      eq(ns.db.global.debug, true)
      eq(logOf(S, "Notify"), { { "Notify", "AZEROTHTRAIL_DEBUG" } })
    end)
  end)

  describe("Open and /azt options", function()
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

    it("/azt options opens the page; help lists it", function()
      local ns = loadOptions()
      local S = fakeSettings()
      withGlobals(S, nil, function()
        ns.Options.Register(S)
        run_slash(ns.addon, "azt", "options")
        run_slash(ns.addon, "azt", " OPTIONS ")
      end)
      eq(logOf(S, "Open"), { { "Open", 77 }, { "Open", 77 } })
      run_slash(ns.addon, "azt", "help")
      ok(table.concat(ns.addon.printed, "\n"):find("/azt options", 1, true), "help mentions /azt options")
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
