-- Pure helpers of UI/Tooltip.lua and UI/List.lua (source line, icon, section
-- headers, tooltip lines, lockout status, preview) with stubbed Game and Data.
-- The frame code (List widget, journal home) is built in tests/ui_build_spec.lua.

local UI_FILES = { "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/JournalHome.lua" }

-- Loads the addon plus the UI files; `game` overrides ns.Game functions and
-- `data` replaces ns.Data tables (Mounts, Route, Lockouts, BossLockouts, ...).
local function loadUI(game, data)
  reset_ui_stub()
  local files = toc_lua_files()
  for _, f in ipairs(UI_FILES) do files[#files + 1] = f end
  local ns = load_addon(files)
  ns.addon:OnInitialize()
  local stubGame = {
    MountInfo = function() return nil end,
    IsOwned = function() return false end,
    Exists = function() return true end,
    Faction = function() return "Alliance" end,
    SavedRows = function() return {} end,
    IsQuestDone = function() return false end,
    IsLfgDone = function() return false end,
    ExpansionLogo = function() return nil end,
  }
  for k, v in pairs(game or {}) do stubGame[k] = v end
  for k, v in pairs(stubGame) do ns.Game[k] = v end
  ns.Data.Lockouts, ns.Data.BossLockouts = {}, {}
  ns.Data.Route = {}
  for k, v in pairs(data or {}) do ns.Data[k] = v end
  return ns
end

local ROUTE = {
  {
    title = "Start in ",
    steps = {
      {
        title = "Portal to Uldum",
        steps = {
          { title = "Run Vortex Pinnacle (Dungeon)", bosses = { { mount = 395, boss = "Altairus" } } },
          { title = "Kill Galleon", bosses = { { mount = 515, boss = "Galleon" } } },
        },
      },
      { title = "Run Somewhere Else", bosses = { { mount = 395, boss = "Second" } } },
      { bosses = { { mount = 600, boss = "Untitled" } } },
    },
  },
}

describe("ui journal", function()
  it("toc lists Frame's parts (Widgets, Style, Nav), then Tooltip, List (and SourceText, Search), DetailPane, JournalHome", function()
    local fh = assert(io.open(ROOT .. "/MountTrail.toc", "r"))
    local lines = {}
    for line in fh:lines() do
      line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if line ~= "" and not line:find("^#") then lines[#lines + 1] = line end
    end
    fh:close()
    local frame
    for i, line in ipairs(lines) do if line == "UI\\Frame.lua" then frame = i end end
    ok(frame, "UI\\Frame.lua in toc")
    local got = {}
    for i = 1, 11 do got[i] = lines[frame + i] end
    eq(got, { "UI\\Widgets.lua", "UI\\Style.lua", "UI\\Nav.lua", "UI\\Tooltip.lua", "UI\\List.lua",
      "UI\\ListRows.lua", "UI\\ListFilter.lua", "UI\\SourceText.lua", "UI\\Search.lua",
      "UI\\DetailPane.lua", "UI\\JournalHome.lua" })
  end)

  it("loads the UI files and registers the journal view without building it", function()
    local ns = loadUI()
    for _, name in ipairs({ "ShowMountTooltip", "LockoutStatus", "TooltipLines", "List",
      "SourceLine", "MountIcon", "SectionLabel", "ListRows", "PreviewMount", "FilterMenuItems",
      "FilterChecked", "ToggleFilter", "ApplyFilterAction", "FiltersAreDefault", "FilterLabel",
      "CreateFilterDropdown", "StyleIcon" }) do
      eq(type(ns.UI[name]), "function", name)
    end
    eq(ns.UI.frame, nil, "no window until toggled")
  end)

  describe("SourceLine", function()
    local mounts = {
      [395] = { name = "Drake of the North Wind", group = "Vortex Pinnacle" },
      [515] = { name = "Son of Galleon", group = "Galleon" },
      [600] = { name = "No title", group = "G" },
      [700] = { name = "Group only", group = "Argent Tournament" },
      [800] = { name = "Nothing" },
    }

    it("adds the first route boss and step title without 'Run '", function()
      local ns = loadUI(nil, { Mounts = mounts, Route = ROUTE })
      eq(ns.UI.SourceLine(395), "Vortex Pinnacle · Altairus (Vortex Pinnacle (Dungeon))")
      eq(ns.UI.SourceLine(515), "Galleon · Galleon (Kill Galleon)")
    end)

    it("handles a missing step title, a missing route entry and no group", function()
      local ns = loadUI(nil, { Mounts = mounts, Route = ROUTE })
      eq(ns.UI.SourceLine(600), "G · Untitled")
      eq(ns.UI.SourceLine(700), "Argent Tournament")
      eq(ns.UI.SourceLine(800), "")
      eq(ns.UI.SourceLine(9999), "", "unknown mount")
    end)

    it("uses the route alone when the mount has no group", function()
      local ns = loadUI(nil, { Mounts = { [395] = { name = "x" } }, Route = ROUTE })
      eq(ns.UI.SourceLine(395), "Altairus (Vortex Pinnacle (Dungeon))")
    end)
  end)

  describe("MountIcon", function()
    it("prefers the client icon, then the data file ID, then the icon name", function()
      local ns = loadUI({
        MountInfo = function(id) if id == 1 then return "One", 123456, 99 end end,
      }, { Mounts = {
        [1] = { name = "One", icon = "ignored" },
        [2] = { name = "Two", icon = 654321 },
        [3] = { name = "Three", icon = "ability_mount_ridinghorse" },
        [4] = { name = "Four" },
      } })
      eq(ns.UI.MountIcon(1), 123456)
      eq(ns.UI.MountIcon(2), 654321)
      eq(ns.UI.MountIcon(3), "Interface\\Icons\\ability_mount_ridinghorse")
      eq(ns.UI.MountIcon(4), 134400, "question mark fallback")
    end)
  end)

  describe("row waypoints", function()
    it("HasLocation asks Map.HasLocation (never Resolve), false without it or on an error", function()
      local ns = loadUI()
      ns.Map.Resolve = function() error("Resolve must not run for the pin") end
      ns.Map.HasLocation = function(id) return id == 1 end
      eq(ns.UI.HasLocation(1), true)
      eq(ns.UI.HasLocation(2), false)
      ns.Map.HasLocation = function() return "yes" end
      eq(ns.UI.HasLocation(1), false, "only true counts")
      local reported = {}
      ns.Game.ReportError = function(err) reported[#reported + 1] = tostring(err) end
      ns.Map.HasLocation = function() error("boom") end
      eq(ns.UI.HasLocation(1), false)
      eq(#reported, 1)
      ns.Map = nil
      eq(ns.UI.HasLocation(1), false)
    end)

    it("PinIcon: the map-pin chat atlas when the client has it, else a map icon texture", function()
      local ns = loadUI()
      eq({ ns.UI.PinIcon() }, { nil, "Interface\\Icons\\INV_Misc_Map_01" })
      STUB_ATLASES["Waypoint-MapPin-ChatIcon"] = true
      eq({ ns.UI.PinIcon() }, { "Waypoint-MapPin-ChatIcon", "Interface\\Icons\\INV_Misc_Map_01" })
      STUB_ATLASES["Waypoint-MapPin-ChatIcon"] = nil
    end)
  end)

  describe("ListRows", function()
    it("puts a header before each section run and marks owned rows", function()
      local ns = loadUI(nil, { Holidays = { brewfest = { title = "Brewfest" } } })
      local a = { section = "dungeon" }
      local b = { section = "dungeon" }
      local c = { section = "raid" }
      local d = { section = "brewfest" }
      local rows = ns.UI.ListRows({ { id = 1, m = a }, { id = 2, m = b }, { id = 3, m = c }, { id = 4, m = d } },
        function(id) return id == 2 end)
      eq(rows, {
        { header = true, depth = 1, section = "dungeon", key = "||dungeon", text = "Dungeon drops",
          owned = 1, total = 2, collapsed = false },
        { id = 1, m = a, owned = false },
        { id = 2, m = b, owned = true },
        { header = true, depth = 1, section = "raid", key = "||raid", text = "Raid drops",
          owned = 0, total = 1, collapsed = false },
        { id = 3, m = c, owned = false },
        { header = true, depth = 1, section = "brewfest", key = "||brewfest", text = "Brewfest",
          owned = 0, total = 1, collapsed = false },
        { id = 4, m = d, owned = false },
      })
      eq(ns.UI.ListRows({}), {})
    end)

    it("groups by the entry's refined section when Select gives one", function()
      local ns = loadUI()
      local a = { section = "world" }
      local b = { section = "world" }
      local rows = ns.UI.ListRows({ { id = 1, m = a, section = "world" }, { id = 2, m = b, section = "delve" } })
      eq(rows, {
        { header = true, depth = 1, section = "world", key = "||world", text = "World drops / rares",
          owned = 0, total = 1, collapsed = false },
        { id = 1, m = a, owned = false },
        { header = true, depth = 1, section = "delve", key = "||delve", text = "Delves",
          owned = 0, total = 1, collapsed = false },
        { id = 2, m = b, owned = false },
      })
    end)

    it("labels the ten journal sections", function()
      local ns = loadUI()
      local want = {
        dungeon = "Dungeon drops", raid = "Raid drops", world = "World drops / rares", delve = "Delves",
        treasure = "Treasures & caches", quest = "Quests", activity = "Zone activities",
        reputation = "Reputation", vendor = "Vendors", other = "Other",
      }
      for key, label in pairs(want) do eq(ns.UI.SectionLabel(key), label, key) end
    end)

    it("labels misc sections and falls back to the key", function()
      local ns = loadUI()
      local want = {
        profession = "Professions", shop = "In-game Shop", tradingpost = "Trading Post", pvp = "PvP",
        racial = "Racial", keystone = "Mythic+", promotion = "Promotions", class = "Class",
        bmah = "Black Market", collection = "Collection rewards", other = "Other",
        unobtainable = "Unobtainable",
      }
      for key, label in pairs(want) do eq(ns.UI.SectionLabel(key), label, key) end
      eq(ns.UI.SectionLabel("timewalking"), "Timewalking")
      eq(ns.UI.SectionLabel("mystery"), "mystery")
    end)
  end)

  describe("filter menu", function()
    local SOURCES = { "dungeon", "raid", "world", "delve", "treasure", "quest", "activity",
      "reputation", "vendor", "other" }
    local LABELS = { "Show dungeon drops", "Show raid drops", "Show world drops / rares", "Show delve mounts",
      "Show treasures & caches", "Show quest mounts", "Show zone activity mounts", "Show reputation mounts",
      "Show vendor mounts", "Show other mounts" }
    local MISC = { "profession", "shop", "tradingpost", "pvp", "racial", "keystone", "promotion", "class",
      "bmah", "collection", "other", "unobtainable" }
    local MISC_LABELS = { "Show profession mounts", "Show in-game shop mounts", "Show Trading Post mounts",
      "Show PvP mounts", "Show racial mounts", "Show Mythic+ mounts", "Show promotion mounts",
      "Show class mounts", "Show Black Market mounts", "Show collection rewards",
      "Show other mounts" }
    local EXPS = { "Classic", "Legion" }

    -- The expected menu: Collected, then (with sections) a divider, the
    -- title, one checkbox per section, a divider and Check all / Uncheck all.
    local function menu(collected, title, keys, labels, hidden)
      local want = { { kind = "checkbox", key = "collected", label = "Collected", checked = collected } }
      if #keys == 0 then return want end
      want[#want + 1] = { kind = "divider" }
      want[#want + 1] = { kind = "title", label = title }
      for i, key in ipairs(keys) do
        want[#want + 1] = { kind = "checkbox", key = key, label = labels[i], checked = not (hidden or {})[key] }
      end
      want[#want + 1] = { kind = "divider" }
      want[#want + 1] = { kind = "button", action = "checkAll", label = "Check all" }
      want[#want + 1] = { kind = "button", action = "uncheckAll", label = "Uncheck all" }
      return want
    end

    it("Journal: Collected, the ten sources (Show ...), then Check all / Uncheck all", function()
      local ns = loadUI()
      local items = ns.UI.FilterMenuItems("journal", { collected = true, journal = { raid = false, quest = false } })
      eq(items, menu(true, "Sources", SOURCES, LABELS, { raid = true, quest = true }))
    end)

    it("Misc: the misc categories, Unobtainable last whatever the option", function()
      local ns = loadUI()
      local f = { misc = { shop = false }, journal = { raid = false } }
      local labels = {}
      for i, l in ipairs(MISC_LABELS) do labels[i] = l end
      labels[#labels + 1] = "Show unobtainable mounts"
      eq(ns.UI.FilterMenuItems("misc", f), menu(false, "Categories", MISC, labels, { shop = true }))
      ns.db.global.settings.showUnobtainable = true
      eq(ns.UI.FilterMenuItems("misc", f), menu(false, "Categories", MISC, labels, { shop = true }),
        "the Options setting does not change the menu")
    end)

    it("Holidays: each holiday; Achievements: each expansion and General; Timewalking: Collected only", function()
      local ns = loadUI()
      local holidays = ns.UI.FilterMenuItems("holidays", { holidays = { brewfest = false } })
      eq(holidays[3], { kind = "title", label = "Holidays" })
      local labels = {}
      for _, item in ipairs(holidays) do
        if item.kind == "checkbox" and item.key ~= "collected" then labels[#labels + 1] = item.label end
      end
      eq(labels, { "Show Hallow's End", "Show Brewfest", "Show Love is in the Air", "Show Noblegarden",
        "Show Feast of Winter Veil", "Show Lunar Festival", "Show Midsummer Fire Festival",
        "Show Darkmoon Faire", "Show Anniversary", "Show other mounts" })
      eq(holidays[5].key, "brewfest")
      eq(holidays[5].checked, false)

      eq(ns.UI.FilterMenuItems("achievements", { achievements = { General = false } }, { expansions = EXPS }),
        menu(false, "Expansions", { "Classic", "Legion", "General" },
          { "Show Classic achievements", "Show Legion achievements", "Show General achievements" },
          { General = true }))
      local real = ns.UI.FilterMenuItems("achievements", {})
      eq(#real, #ns.Data.Expansions + 1 + 6, "Data.Expansions by default")

      eq(ns.UI.FilterMenuItems("timewalking", { collected = true, timewalking = { timewalking = false } }),
        { { kind = "checkbox", key = "collected", label = "Collected", checked = true } })
      eq(#ns.UI.FilterMenuItems(nil, nil), 1, "no view, no filters")
      eq(#ns.UI.FilterMenuItems("holiday", {}), 1, "data tab keys: Collected only")
    end)

    it("FilterChecked reads Collected globally and sections per view", function()
      local ns = loadUI()
      local f = { collected = true, misc = { shop = false } }
      eq(ns.UI.FilterChecked(f, "collected", "journal"), true)
      eq(ns.UI.FilterChecked(f, "shop", "misc"), false)
      eq(ns.UI.FilterChecked(f, "shop", "journal"), true)
      eq(ns.UI.FilterChecked(nil, "raid", "journal"), true)
      eq(ns.UI.FilterChecked(nil, "collected", "journal"), false)
    end)

    it("ToggleFilter flips Collected or one section of the view and returns the new state", function()
      local ns = loadUI()
      local f = { collected = false }
      eq(ns.UI.ToggleFilter(f, "collected", "misc"), true)
      eq(ns.UI.ToggleFilter(f, "shop", "misc"), false, "missing section key was on")
      eq(f, { collected = true, misc = { shop = false } })
      eq(ns.UI.ToggleFilter(f, "raid", "journal"), false)
      eq(ns.UI.ToggleFilter(f, "shop", "misc"), true)
      eq(f, { collected = true, journal = { raid = false } }, "only false is stored")
    end)

    it("Check all / Uncheck all set every section of the view and leave the rest alone", function()
      local ns = loadUI()
      local f = { collected = true, journal = { raid = false }, misc = { pvp = false } }
      ns.UI.ApplyFilterAction(f, "uncheckAll", "misc")
      for _, key in ipairs(MISC) do eq(f.misc[key], false, key) end
      eq(f.misc.unobtainable, false, "Unobtainable is in the menu")
      eq(f.collected, true)
      eq(f.journal, { raid = false }, "other views untouched")
      ns.UI.ApplyFilterAction(f, "checkAll", "misc")
      eq(f.misc, nil)
      ns.UI.ApplyFilterAction(f, "uncheckAll", "journal")
      for _, key in ipairs(SOURCES) do eq(f.journal[key], false, key) end
      ns.UI.ApplyFilterAction(f, "checkAll", "journal")
      eq(f, { collected = true })
      ns.UI.ApplyFilterAction(f, "uncheckAll", "timewalking")
      eq(f, { collected = true }, "no sections on Timewalking")
    end)

    it("reset and the default check work per view", function()
      local ns = loadUI()
      local f = { collected = false, journal = { raid = false }, misc = { shop = false } }
      eq(ns.UI.FiltersAreDefault(f, "journal"), false)
      eq(ns.UI.FiltersAreDefault(f, "misc"), false)
      eq(ns.UI.FiltersAreDefault(f, "holidays"), true, "another view's filters do not count")
      eq(ns.UI.FiltersAreDefault(f, "timewalking"), true)
      ns.UI.ApplyFilterAction(f, "reset", "misc")
      eq(f, { collected = false, journal = { raid = false } }, "Misc reset: its sections only")
      eq(ns.UI.FiltersAreDefault(f, "misc"), true)
      f.collected = true
      eq(ns.UI.FiltersAreDefault(f, "timewalking"), false, "Collected counts in every view")
      ns.UI.ApplyFilterAction(f, "reset", "timewalking")
      eq(f, { collected = false, journal = { raid = false } })
      ns.UI.ApplyFilterAction(f, "reset", "journal")
      eq(f, ns.Journal.DefaultFilters)
      ok(f ~= ns.Journal.DefaultFilters, "the saved table is updated, not replaced")
      eq(ns.UI.FiltersAreDefault({}, "journal"), true, "an empty table reads as the defaults")
      -- Unobtainable is always in the Misc menu; a hidden key the menu does
      -- not show does not light the reset arrow.
      eq(ns.UI.FiltersAreDefault({ misc = { unobtainable = false } }, "misc"), false)
      eq(ns.UI.FiltersAreDefault({ misc = { mystery = false } }, "misc"), true, "keys outside the menu do not count")
    end)
  end)

  describe("LockoutStatus", function()
    local mounts = {
      [10] = { name = "Quest mount", quest = 111 },
      [11] = { name = "Instance mount" },
      [12] = { name = "Manual mount" },
      [13] = { name = "Untracked" },
      [14] = { name = "LFG mount" },
    }
    local lockouts = {
      [11] = { instance = 600, boss = "Big Boss", difficulties = { 2 }, reset = "daily" },
      [12] = { manual = true, reset = "daily" },
      [14] = { lfg = 285, reset = "daily" },
    }

    it("maps done/open/manual to saved/available/manual and untracked to nil", function()
      local ns = loadUI({
        IsQuestDone = function(q) return q == 111 end,
        SavedRows = function()
          return { { instance = 600, difficulty = 2, bosses = { { name = "Big Boss", killed = true } } } }
        end,
      }, { Mounts = mounts, Lockouts = lockouts })
      eq(ns.UI.LockoutStatus(10), "saved", "quest flag done")
      eq(ns.UI.LockoutStatus(11), "saved", "boss killed on the tracked difficulty")
      eq(ns.UI.LockoutStatus(12), "manual")
      eq(ns.UI.LockoutStatus(13), nil)
      eq(ns.UI.LockoutStatus(14), "available", "LFG not done")
    end)

    it("is available when nothing is killed", function()
      local ns = loadUI({ IsLfgDone = function(id) return id == 285 end },
        { Mounts = mounts, Lockouts = lockouts })
      eq(ns.UI.LockoutStatus(10), "available")
      eq(ns.UI.LockoutStatus(11), "available")
      eq(ns.UI.LockoutStatus(14), "saved", "LFG done today")
    end)
  end)

  describe("TooltipLines", function()
    local WHITE, GOLD, BLUE, GREY, HINT = { 1, 1, 1 }, { 1, 0.82, 0 }, { 0.4, 0.78, 1 }, { 0.6, 0.6, 0.6 },
      { 0.5, 0.9, 0.5 }
    local function line(left, c, wrap) return { left = left, r = c[1], g = c[2], b = c[3], wrap = wrap } end
    local function double(left, right)
      return { double = true, left = left, right = right, r = GOLD[1], g = GOLD[2], b = GOLD[3],
        rr = WHITE[1], rg = WHITE[2], rb = WHITE[3] }
    end
    local function lefts(lines)
      local out = {}
      for i, l in ipairs(lines) do out[i] = l.right and (l.left .. "=" .. l.right) or l.left end
      return out
    end
    local DS_ROUTE = {
      { title = "Run Dragon Soul (Raid)", bosses = { { mount = 445, boss = "Ultraxion" } } },
      { title = "Kill Galleon (World Boss)", bosses = { { mount = 515, boss = "Galleon" } } },
    }
    local EXPERIMENT = { name = "Experiment 12-B", item = 78919, exp = "Cataclysm", tab = "journal",
      section = "raid", chance = 100, stats = { 6161, 6162 } }

    it("Rarity style: badge, source kind, source lines, odds, attempts, lockout, hint", function()
      local ns = loadUI({
        CharKey = function() return "Me-Realm" end,
        MountSourceText = function() return "|cFFFFD200Drop:|r Ultraxion|n|cFFFFD200Zone:|r Dragon Soul" end,
      }, { Mounts = { [445] = EXPERIMENT }, Route = DS_ROUTE })
      ns.db.global.stats = { ["Me-Realm"] = { [445] = 20 }, ["Alt-Realm"] = { [445] = 10 } }
      ns.db.global.attempts[445] = 99 -- statistics win over our (legacy) counter
      ns.db.global.attemptsByChar = { ["Me-Realm"] = { [445] = 99 } } -- and this character's
      ns.RarityBridge.Attempts = function() return 25 end -- a smaller Rarity count does not lower it
      eq(ns.UI.TooltipLines(445), {
        line("Mount |cffffd100[CATA]|r", WHITE),
        line("Drops from NPC(s)", BLUE),
        line("|cffffd100Drop:|r Ultraxion", WHITE, true),
        line("|cffffd100Zone:|r Dragon Soul", WHITE, true),
        line("1 in 100 chance", WHITE),
        line("Lucky if you obtain in 69 or less", GREY),
        double("Attempts (this character)", "20"),
        double("Total attempts", "30"),
        double("Chance so far", "26.03%"),
        line("Lockout: —", GOLD),
        line("Click to set waypoint", HINT),
      })
    end)

    it("unobtainable mounts: a grey 'No longer obtainable' line right after the source kind", function()
      local ns = loadUI({}, { Mounts = {
        [1] = { name = "Retired drop", tab = "journal", section = "raid", unobtainable = true },
        [2] = { name = "Old season", tab = "misc", section = "unobtainable", unobtainable = true },
        [3] = { name = "Old holiday", tab = "holiday", section = "brewfest", unobtainable = true },
        [4] = { name = "Live drop", tab = "journal", section = "raid" },
      } })
      local l1 = ns.UI.TooltipLines(1)
      eq({ l1[2], l1[3] }, { line("Drops from NPC(s)", BLUE), line("No longer obtainable", GREY) })
      local l2 = ns.UI.TooltipLines(2)
      eq(l2[2], line("No longer obtainable", GREY), "Unobtainable section: no kind line, just the grey one")
      eq(lefts(l2)[3]:find("obtainable"), nil, "once")
      local l3 = ns.UI.TooltipLines(3)
      eq({ l3[2].left, l3[3].left }, { "Holiday event", "No longer obtainable" })
      for _, l in ipairs(ns.UI.TooltipLines(4)) do ok(l.left ~= "No longer obtainable", "obtainable: no line") end
    end)

    it("adds 'Dropped by <boss> in <instance>' unless a source line names the boss", function()
      local texts = {}
      local ns = loadUI({ MountSourceText = function(id) return texts[id] end }, { Mounts = {
        [445] = { name = "Experiment 12-B", tab = "journal", section = "raid" },
        [515] = { name = "Son of Galleon", tab = "journal", section = "world" },
      }, Route = DS_ROUTE })
      local function dropped(id)
        for _, l in ipairs(ns.UI.TooltipLines(id)) do
          if l.left:find("^Dropped by") then return l end
        end
      end
      eq(dropped(445), line("Dropped by Ultraxion in Dragon Soul", WHITE, true), "no source text: the route's instance")
      texts[445] = "Drop: Ultraxion|nZone: Dragon Soul"
      eq(dropped(445), nil, "the Drop line names the boss")
      texts[445] = "Drop: ULTRAXION and friends"
      eq(dropped(445), nil, "case-insensitive")
      texts[445] = "Drop: Someone Else"
      eq(dropped(445).left, "Dropped by Ultraxion in Dragon Soul")
      texts[445] = "Zone: Dragon Soul"
      eq(lefts(ns.UI.TooltipLines(445))[3], "|cffffd100Zone:|r Dragon Soul")
      eq(lefts(ns.UI.TooltipLines(445))[4], "Dropped by Ultraxion in Dragon Soul", "right after the source lines")
      eq(dropped(515).left, "Dropped by Galleon", "no instance, no zone")
      texts[515] = "Zone: Valley of the Four Winds"
      eq(dropped(515).left, "Dropped by Galleon in Valley of the Four Winds", "zone when the route has no instance")
      eq(dropped(9999), nil, "no route entry")
    end)

    it("Attempts without statistics: this character's counter; total = all characters + legacy, or Rarity's if larger", function()
      local ns = loadUI({ CharKey = function() return "Me-Realm" end },
        { Mounts = { [10] = { name = "M", item = 5555, quest = 111 } } })
      ns.db.global.attemptsByChar = { ["Me-Realm"] = { [10] = 2 }, ["Alt-Realm"] = { [10] = 3 } }
      ns.db.global.attempts[10] = 2 -- legacy account-wide counter: total only
      local rarity = 42
      ns.RarityBridge.Attempts = function(item) if item == 5555 then return rarity end end
      eq(lefts(ns.UI.TooltipLines(10)), { "Mount", "Attempts (this character)=2", "Total attempts=42",
        "Lockout: Available", "Click to set waypoint" },
        "no chance: the two Attempts lines only")
      rarity = 3
      eq(lefts(ns.UI.TooltipLines(10))[3], "Total attempts=7")
      rarity = nil
      eq(lefts(ns.UI.TooltipLines(10))[3], "Total attempts=7", "Rarity unreadable")
      ns.db.global.attemptsByChar = {}
      ns.db.global.attempts[10] = nil
      eq(lefts(ns.UI.TooltipLines(10))[2], "Attempts (this character)=0")
      eq(lefts(ns.UI.TooltipLines(10))[3], "Total attempts=0")
    end)

    it("statistics: this character's reading and every character's total; Chance so far uses the total", function()
      local ns = loadUI({ CharKey = function() return "Me-Realm" end }, { Mounts = {
        [40] = { name = "Stat Mount", item = 7777, stats = { 1, 2 }, chance = 20 },
      } })
      local rarity
      ns.RarityBridge.Attempts = function() return rarity end
      ns.db.global.attempts[40] = 2
      ns.db.global.attemptsByChar = { ["Me-Realm"] = { [40] = 2 } }
      ns.db.global.stats = { ["Me-Realm"] = { [40] = 3 } }
      eq(lefts(ns.UI.TooltipLines(40)), { "Mount", "1 in 20 chance", "Lucky if you obtain in 14 or less",
        "Attempts (this character)=3", "Total attempts=3", "Chance so far=14.26%", "Lockout: —",
        "Click to set waypoint" })
      ns.db.global.stats = { ["Me-Realm"] = { [40] = 3 }, ["Alt-Realm"] = { [40] = 4 } }
      eq(lefts(ns.UI.TooltipLines(40))[5], "Total attempts=7")
      eq(lefts(ns.UI.TooltipLines(40))[6], "Chance so far=30.17%", "the total, not this character's")
      ns.db.global.stats = { ["Alt-Realm"] = { [40] = 4 } }
      eq(lefts(ns.UI.TooltipLines(40))[4], "Attempts (this character)=2", "no reading here: own counter")
      eq(lefts(ns.UI.TooltipLines(40))[5], "Total attempts=4")
      ns.db.global.stats = { ["Me-Realm"] = { [41] = 9 } }
      eq(lefts(ns.UI.TooltipLines(40))[5], "Total attempts=4", "no reading yet: counters + legacy")
      ns.db.global.stats = nil
      eq(lefts(ns.UI.TooltipLines(40))[5], "Total attempts=4", "no stats table at all")
      rarity = 11
      eq(lefts(ns.UI.TooltipLines(40))[5], "Total attempts=11", "Rarity's larger count")
    end)

    it("statistics are ignored for mounts without stats (stale readings)", function()
      local ns = loadUI({ CharKey = function() return "Me-Realm" end },
        { Mounts = { [41] = { name = "Plain", quest = 1 } } })
      ns.RarityBridge.Attempts = function() return nil end
      ns.db.global.attempts[41] = 5
      ns.db.global.stats = { ["Me-Realm"] = { [41] = 9 } }
      eq(lefts(ns.UI.TooltipLines(41))[2], "Attempts (this character)=0")
      eq(lefts(ns.UI.TooltipLines(41))[3], "Total attempts=5")
    end)

    it("untracked mounts (no chance, statistics or lockout spec) show no Attempts block", function()
      local ns = loadUI(nil, { Mounts = {
        [20] = { name = "Shop Mount", tab = "misc", section = "shop", item = 1 },
        [21] = { name = "Boss Mount", tab = "journal", section = "world" },
        [22] = { name = "Spec Mount", tab = "journal", section = "world" },
      }, Route = DS_ROUTE, BossLockouts = { Galleon = { quest = 9, reset = "weekly" } },
        Lockouts = { [22] = { manual = true, reset = "weekly" } } })
      ns.Data.Route = { { title = "Kill Galleon", bosses = { { mount = 21, boss = "Galleon" } } } }
      ns.db.global.attempts[20] = 3
      ns.RarityBridge.Attempts = function() return 8 end
      eq(lefts(ns.UI.TooltipLines(20)), { "Mount", "In-game shop", "Lockout: —", "Click to set waypoint" })
      eq(lefts(ns.UI.TooltipLines(21))[4], "Attempts (this character)=0", "route boss with a BossLockouts spec")
      eq(lefts(ns.UI.TooltipLines(21))[5], "Total attempts=0")
      eq(lefts(ns.UI.TooltipLines(22))[3], "Attempts (this character)=0", "own lockout spec")
    end)

    it("a chance with no attempts yet shows 0.00%", function()
      local ns = loadUI(nil, { Mounts = { [30] = { name = "A", chance = 33.4 } } })
      eq(lefts(ns.UI.TooltipLines(30)), { "Mount", "1 in 33 chance", "Lucky if you obtain in 23 or less",
        "Attempts (this character)=0", "Total attempts=0", "Chance so far=0.00%", "Lockout: —", "Click to set waypoint" })
    end)

    it("expansion badges", function()
      local tags = {
        Classic = "CLASSIC", ["The Burning Crusade"] = "TBC", ["Wrath of the Lich King"] = "WOTLK",
        Cataclysm = "CATA", ["Mists of Pandaria"] = "MOP", ["Warlords of Draenor"] = "WOD", Legion = "LEGION",
        ["Battle for Azeroth"] = "BFA", Shadowlands = "SL", Dragonflight = "DF", ["The War Within"] = "TWW",
        Midnight = "MID",
      }
      local ns = loadUI()
      for exp, tag in pairs(tags) do eq(ns.UI.ExpansionTag(exp), tag, exp) end
      eq(ns.UI.ExpansionTag("Unknown"), nil)
      eq(ns.UI.ExpansionTag(nil), nil)
      ns.Data.Mounts = { [1] = { name = "x", exp = "Unknown" }, [2] = { name = "y", exp = "Legion" } }
      eq(ns.UI.TooltipLines(1)[1], line("Mount", WHITE), "unknown expansion: no badge")
      eq(ns.UI.TooltipLines(2)[1].left, "Mount |cffffd100[LEGION]|r")
    end)

    it("SourceKind maps the (refined) source to a kind line; unknown -> nil", function()
      local ns = loadUI()
      local SK = ns.UI.SourceKind
      local cases = {
        { { tab = "journal", section = "dungeon" }, "Drops from NPC(s)" },
        { { tab = "journal", section = "raid" }, "Drops from NPC(s)" },
        { { tab = "journal", section = "world" }, "Drops from NPC(s)" },
        { { tab = "journal", section = "treasure" }, "Found in a treasure / cache" },
        { { tab = "journal", section = "delve" }, "Delve reward" },
        { { tab = "journal", section = "quest" }, "Quest reward" },
        { { tab = "journal", section = "activity" }, "Zone activity reward" },
        { { tab = "journal", section = "reputation" }, "Reputation reward" },
        { { tab = "journal", section = "vendor" }, "Sold by a vendor" },
        { { tab = "journal", section = "other" }, nil },
        { { tab = "misc", section = "achievement" }, "Achievement reward" },
        { { tab = "misc", section = "profession" }, "Crafted by a profession" },
        { { tab = "misc", section = "shop" }, "In-game shop" },
        { { tab = "misc", section = "tradingpost" }, "Trading Post" },
        { { tab = "misc", section = "other" }, nil },
        { { tab = "misc", section = "pvp" }, "PvP reward" },
        { { tab = "misc", section = "racial" }, "Racial mount" },
        { { tab = "misc", section = "keystone" }, "Mythic+ reward" },
        { { tab = "misc", section = "promotion" }, "Promotion" },
        { { tab = "misc", section = "class" }, "Class mount" },
        { { tab = "misc", section = "bmah" }, "Black Market Auction House" },
        { { tab = "misc", section = "collection" }, "Collection reward" },
        { { tab = "misc", section = "limited" }, nil, "no Limited time section any more" },
        { { tab = "misc", section = "unobtainable" }, nil, "Unobtainable: only the grey line (TooltipLines)" },
        -- Unobtainable mounts keep their section's line (TooltipLines adds a grey one).
        { { tab = "misc", section = "pvp", unobtainable = true }, "PvP reward" },
        { { tab = "journal", section = "raid", unobtainable = true }, "Drops from NPC(s)" },
        { { tab = "holiday", section = "brewfest", unobtainable = true }, "Holiday event" },
        { { tab = "holiday", section = "brewfest" }, "Holiday event" },
        { { tab = "holiday", section = "timewalking" }, "Holiday event" },
        { {}, nil },
      }
      for i, c in ipairs(cases) do eq(SK(1, c[1]), c[2], tostring(i)) end
      eq(SK(1, { tab = "journal", section = "world" }, "Delve: Fungal Folly"), "Delve reward", "refined to delve")
      eq(SK(1, { tab = "journal", section = "world" }, function() return "Cache of Treasure" end),
        "Found in a treasure / cache", "refined to treasure")
      eq(SK(1, nil), nil)
    end)

    it("shows Available and Manual lockout states", function()
      local ns = loadUI(nil, {
        Mounts = { [30] = { name = "A", quest = 1 }, [31] = { name = "M" } },
        Lockouts = { [31] = { manual = true, reset = "weekly" } },
      })
      local a, m = lefts(ns.UI.TooltipLines(30)), lefts(ns.UI.TooltipLines(31))
      eq(a[4], "Lockout: Available", "after the two Attempts lines")
      eq(m[4], "Lockout: Manual")
    end)
  end)

  describe("ShowMountTooltip", function()
    -- A recording GameTooltip -> tip, calls.
    local function recordingTip(withItem)
      local calls, tip = {}, {}
      function tip:SetOwner(owner, anchor)
        self.owner = owner
        calls[#calls + 1] = { "SetOwner", owner, anchor }
      end
      function tip:IsOwned(owner) return self.owner == owner end
      function tip:Hide() self.owner = nil end
      if withItem then
        function tip:SetItemByID(id) calls[#calls + 1] = { "SetItemByID", id } end
      end
      function tip:SetText(text, r, g, b) calls[#calls + 1] = { "SetText", text, r, g, b } end
      function tip:AddLine(text, r, g, b, wrap) calls[#calls + 1] = { "AddLine", text, r, g, b, wrap } end
      function tip:AddDoubleLine(left, right, r, g, b, rr, rg, rb)
        calls[#calls + 1] = { "AddDoubleLine", left, right, r, g, b, rr, rg, rb }
      end
      function tip:Show() calls[#calls + 1] = { "Show" } end
      return tip, calls
    end
    local function paint(ns, id, withItem)
      local tip, calls = recordingTip(withItem)
      local old = GameTooltip
      GameTooltip = tip
      ns.UI.ShowMountTooltip("owner", id)
      GameTooltip = old
      return calls
    end

    it("no item: name, wrapped flavor, then the structured lines (double lines as such)", function()
      local ns = loadUI({ MountDescription = function() return "Swift as the wind." end },
        { Mounts = { [20] = { name = "Rare Mount", tab = "journal", section = "world", exp = "Legion",
          chance = 50 } } })
      eq(paint(ns, 20), {
        { "SetOwner", "owner", "ANCHOR_RIGHT" },
        { "SetText", "Rare Mount", 1, 1, 1 },
        { "AddLine", "Swift as the wind.", 0.9, 0.9, 0.9, true },
        { "AddLine", "Mount |cffffd100[LEGION]|r", 1, 1, 1 },
        { "AddLine", "Drops from NPC(s)", 0.4, 0.78, 1 },
        { "AddLine", "1 in 50 chance", 1, 1, 1 },
        { "AddLine", "Lucky if you obtain in 35 or less", 0.6, 0.6, 0.6 },
        { "AddDoubleLine", "Attempts (this character)", "0", 1, 0.82, 0, 1, 1, 1 },
        { "AddDoubleLine", "Total attempts", "0", 1, 0.82, 0, 1, 1, 1 },
        { "AddDoubleLine", "Chance so far", "0.00%", 1, 0.82, 0, 1, 1, 1 },
        { "AddLine", "Lockout: —", 1, 0.82, 0 },
        { "AddLine", "Click to set waypoint", 0.5, 0.9, 0.5 },
        { "Show" },
      })
    end)

    it("no flavor text: nothing between the name and the lines", function()
      local ns = loadUI({ MountDescription = function() return nil end }, { Mounts = { [20] = { name = "Vendor Mount" } } })
      local calls = paint(ns, 20)
      eq(calls[3], { "AddLine", "Mount", 1, 1, 1 })
    end)

    it("item mounts: the item's own tooltip, a spacer, then the lines", function()
      local ns = loadUI({ MountDescription = function() return "Swift as the wind." end },
        { Mounts = { [20] = { name = "Vendor Mount", item = 87771 } } })
      eq(paint(ns, 20, true), {
        { "SetOwner", "owner", "ANCHOR_RIGHT" },
        { "SetItemByID", 87771 },
        { "AddLine", " " },
        { "AddLine", "Mount", 1, 1, 1 },
        { "AddLine", "Lockout: —", 1, 0.82, 0 },
        { "AddLine", "Click to set waypoint", 0.5, 0.9, 0.5 },
        { "Show" },
      })
    end)

    it("a tooltip without AddDoubleLine gets one joined line", function()
      local ns = loadUI(nil, { Mounts = { [20] = { name = "Rare Mount", quest = 1 } } })
      local tip, calls = recordingTip()
      tip.AddDoubleLine = nil
      local old = GameTooltip
      GameTooltip = tip
      ns.UI.ShowMountTooltip("owner", 20)
      GameTooltip = old
      eq(calls[4], { "AddLine", "Attempts (this character)  0", 1, 0.82, 0 })
      eq(calls[5], { "AddLine", "Total attempts  0", 1, 0.82, 0 })
    end)

    it("item data not cached yet: repaints a frame after it loads, one callback per owner and mount", function()
      local ns = loadUI(nil, { Mounts = { [20] = { name = "Rare Mount", item = 87771 },
        [21] = { name = "Other", item = 99 }, [22] = { name = "Third", item = 77 } } })
      local oldItem, oldCItem, oldTip, oldTimer = Item, C_Item, GameTooltip, C_Timer
      local cached, waiting, timers = {}, {}, {}
      C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
      C_Item = { IsItemDataCachedByID = function(id) return cached[id] == true end }
      Item = { CreateFromItemID = function(_, id)
        return { ContinueOnItemLoad = function(_, fn) waiting[#waiting + 1] = { id = id, fn = fn } end }
      end }
      local tip, calls = recordingTip(true)
      GameTooltip = tip
      local function count(name, arg)
        local n = 0
        for _, c in ipairs(calls) do if c[1] == name and (arg == nil or c[2] == arg) then n = n + 1 end end
        return n
      end
      local row = { mountID = 20 }
      ns.UI.ShowMountTooltip(row, 20)
      ns.UI.ShowMountTooltip(row, 20) -- hovered again before the data arrived
      eq(#waiting, 1, "one callback for the same owner and mount")
      eq(waiting[1].id, 87771)
      cached[87771] = true
      waiting[1].fn()
      eq(count("SetItemByID", 87771), 2, "not repainted in the load callback itself")
      eq(#timers, 1)
      eq(timers[1].seconds, 0, "next frame")
      ns.UI.ShowMountTooltip(row, 20) -- hovered again in between: loaded, no new callback
      eq(#waiting, 1)
      timers[1].fn()
      eq(count("SetItemByID", 87771), 4, "repainted once, a frame later")
      eq(count("AddLine", "Click to set waypoint"), 4, "our block painted again")
      eq(#waiting, 1, "cached now: no new callback")

      -- Hidden (or owned by something else) before the data arrives: no repaint.
      ns.UI.ShowMountTooltip(row, 21)
      eq(#waiting, 2)
      ns.UI.HideMountTooltip()
      local before = #calls
      waiting[2].fn()
      timers[2].fn()
      eq(#calls, before, "not repainted after hide")

      -- No C_Timer: repainted directly in the callback.
      C_Timer = nil
      local third = { mountID = 22 }
      ns.UI.ShowMountTooltip(third, 22)
      eq(#waiting, 3)
      waiting[3].fn()
      eq(count("SetItemByID", 77), 2, "repainted at once")

      -- Cached from the start, or no Item mixin / C_Item: no waiting, no error.
      cached[99] = true
      ns.UI.ShowMountTooltip(row, 21)
      eq(#waiting, 3)
      Item = nil
      cached[99] = nil
      ns.UI.ShowMountTooltip({}, 21)
      C_Item = nil
      ns.UI.ShowMountTooltip({}, 21)
      eq(#waiting, 3)
      Item, C_Item, GameTooltip, C_Timer = oldItem, oldCItem, oldTip, oldTimer
    end)

    it("TooltipFlavor returns the client's mount description", function()
      local ns = loadUI({ MountDescription = function(id) if id == 20 then return "Swift as the wind." end end })
      eq(ns.UI.TooltipFlavor(20), "Swift as the wind.")
      eq(ns.UI.TooltipFlavor(21), nil)
    end)
  end)

  describe("PreviewMount", function()
    it("calls DressUpMount with the mount ID", function()
      local ns = loadUI()
      local got
      DressUpMount = function(id) got = id end
      ns.UI.PreviewMount(395)
      DressUpMount = nil
      eq(got, 395)
    end)

    it("falls back to DressUpMountLink with the spell link", function()
      local ns = loadUI(nil, { Mounts = { [395] = { name = "x", spell = 88742 } } })
      local got
      DressUpMountLink = function(link) got = link end
      C_Spell = { GetSpellLink = function(id) return "|Hspell:" .. id .. "|h" end }
      ns.UI.PreviewMount(395)
      DressUpMountLink, C_Spell = nil, nil
      eq(got, "|Hspell:88742|h")
    end)

    it("does nothing when neither exists", function()
      local ns = loadUI()
      ns.UI.PreviewMount(395) -- must not error
    end)
  end)
  describe("collapsible groups", function()
    it("SourceZone reads the first Zone: line without colour codes", function()
      local ns = loadUI()
      local SZ = ns.UI.SourceZone
      eq(SZ("|cFFFFD200Drop:|r Baron Rivendare|n|cFFFFD200Zone: |rStratholme"), "Stratholme")
      eq(SZ("|cFFFFD200Drop:|r Baron Rivendare\n|cFFFFD200Zone:|r  Stratholme  \n|cFFFFD200Zone:|r Elsewhere"),
        "Stratholme", "first Zone line, trimmed, real newlines")
      eq(SZ("Zone: |cff00ff00Icecrown|r"), "Icecrown", "colour inside the value")
      eq(SZ("|cFFFFD200Vendor:|r Someone"), nil)
      eq(SZ("Zone:   "), nil, "empty value")
      eq(SZ("|cnNORMAL_FONT_COLOR:Zone:|r Stratholme"), "Stratholme", "named colour codes")
      eq(SZ("Zone: |A:raceicon-dwarf-male:16:16|aBlackrock Depths"), "Blackrock Depths", "atlas markup")
      eq(SZ("Zone: |Hmapzone:107|hNagrand|h"), "Nagrand", "link markup, link text kept")
      eq(SZ("|cnNORMAL_FONT_COLOR:Drop:|r |Hunit:1|hBoss|h|n|cnNORMAL_FONT_COLOR:Zone:|r |cnWHITE_FONT_COLOR:Icecrown|r"),
        "Icecrown")
      eq(SZ(nil), nil)
      eq(SZ(5), nil)
    end)

    it("InstanceName strips Run and the (Dungeon)/(Raid) suffix, only for instance runs", function()
      local ns = loadUI()
      local IN = ns.UI.InstanceName
      eq(IN("Run Vortex Pinnacle (Dungeon)"), "Vortex Pinnacle")
      eq(IN("Run Throne of the Four Winds (Raid)"), "Throne of the Four Winds")
      eq(IN("Run Magister's Terrace (Midnight Dungeon)"), "Magister's Terrace")
      eq(IN("Run Firelands"), "Firelands")
      eq(IN("Kill Galleon (World Boss)"), nil, "not an instance run")
      eq(IN("Run "), nil)
      eq(IN(nil), nil)
    end)

    it("SubGroup: client instance name first, route last; zone for world; faction group for reputation", function()
      local ns = loadUI(nil, { Route = ROUTE })
      local texts = {
        [1] = "|cFFFFD200Drop:|r Boss|n|cFFFFD200Zone:|r Stratholme",
        [395] = "Zone: Skywall",
        [4] = "Zone: Feralas",
        [10] = "Zone: The Vortex Pinnacle",
      }
      local ctx = {
        sourceText = function(id) return texts[id] end,
        mapName = function(mapID)
          if mapID == 317 then return "Stratholme Map" end
          if mapID == 70 then return "Dustwallow" end
        end,
      }
      local SG = ns.UI.SubGroup
      eq({ SG(395, {}, "dungeon", ctx) }, { "skywall", "Skywall", true }, "client Zone: beats the route")
      eq({ SG(395, { coords = { m = 317 } }, "dungeon", { mapName = ctx.mapName }) },
        { "stratholme map", "Stratholme Map", true }, "coords map name beats the route")
      eq({ SG(395, {}, "dungeon", {}) }, { "vortex pinnacle", "Vortex Pinnacle", false }, "route as the last resort")
      eq({ SG(395, {}, "dungeon", nil) }, { "vortex pinnacle", "Vortex Pinnacle", false }, "no ctx")
      eq({ SG(10, {}, "dungeon", ctx) }, { "vortex pinnacle", "The Vortex Pinnacle", true }, "a leading The is ignored in the key")
      eq({ SG(515, {}, "raid", ctx) }, { "~other", "Other" }, "a Kill step is no instance")
      eq({ SG(1, { coords = { m = 317 } }, "dungeon", ctx) }, { "stratholme", "Stratholme", true }, "Zone: before coords")
      eq({ SG(2, { coords = { m = 317 } }, "raid", ctx) }, { "stratholme map", "Stratholme Map", true })
      eq({ SG(3, {}, "dungeon", ctx) }, { "~other", "Other" })
      eq({ SG(4, { coords = { m = 70 } }, "world", ctx) }, { "feralas", "Feralas", true }, "world: Zone: first")
      eq({ SG(5, { coords = { m = 70 } }, "world", ctx) }, { "dustwallow", "Dustwallow", true }, "world: coords map")
      eq({ SG(395, {}, "world", {}) }, { "~other", "Other" }, "world never uses the route")
      eq({ SG(6, {}, "world", ctx) }, { "~other", "Other" })
      eq({ SG(7, { group = "Netherwing" }, "reputation", ctx) }, { "netherwing", "Netherwing", true })
      eq({ SG(8, { group = "" }, "reputation", ctx) }, { "~other", "Other" })
      for _, generic in ipairs({ "Reputation", "Renown", "Paragon Reputation", "reputation" }) do
        eq({ SG(8, { group = generic }, "reputation", ctx) }, { "~other", "Other" }, "generic group " .. generic)
      end
      eq(SG(9, { group = "x" }, "delve", ctx), nil, "other sections are flat")
      eq(SG(9, { group = "x" }, "brewfest", ctx), nil)
    end)

    it("GroupKey lower-cases, trims and drops a leading The", function()
      local ns = loadUI()
      eq(ns.UI.GroupKey("The Vortex Pinnacle"), "vortex pinnacle")
      eq(ns.UI.GroupKey("  the  Underrot "), "underrot")
      eq(ns.UI.GroupKey("Theramore"), "theramore", "only the word The")
      eq(ns.UI.GroupKey("Throne of the Four Winds"), "throne of the four winds")
    end)

    it("CollapseKey and ToggleCollapsed store only collapsed=true", function()
      local ns = loadUI()
      eq(ns.UI.CollapseKey("journal", "Classic", "dungeon"), "journal|Classic|dungeon")
      eq(ns.UI.CollapseKey("journal", "Classic", "dungeon", "Stratholme"), "journal|Classic|dungeon|Stratholme")
      eq(ns.UI.CollapseKey("misc", nil, "shop"), "misc||shop")
      local store = {}
      eq(ns.UI.ToggleCollapsed(store, "a"), true)
      eq(store, { a = true })
      eq(ns.UI.ToggleCollapsed(store, "a"), false)
      eq(store, {}, "expanded = absent")
    end)

    -- A journal-view selection: dungeon (three instances + one unknown),
    -- world (one zone) and a flat delve section, in Select order.
    local function sample()
      local m = {
        [10] = { name = "A", section = "dungeon" }, [11] = { name = "B", section = "dungeon" },
        [12] = { name = "C", section = "dungeon" }, [13] = { name = "D", section = "dungeon" },
        [20] = { name = "E", section = "world" }, [30] = { name = "F", section = "delve" },
      }
      local texts = { [10] = "Zone: Zul'Farrak", [11] = "Zone: Blackrock Depths", [12] = "Zone: zul'Aman",
        [20] = "Zone: Feralas" }
      local selected = {}
      for _, id in ipairs({ 10, 11, 12, 13, 20, 30 }) do
        selected[#selected + 1] = { id = id, m = m[id], section = m[id].section }
      end
      return selected, m, function(id) return texts[id] end
    end

    it("builds section -> sub-group -> mounts with counts; sub-groups sorted, Other last", function()
      local ns = loadUI()
      local selected, m, text = sample()
      local rows = ns.UI.ListRows(selected, function(id) return id == 11 end,
        { view = "journal", exp = "Classic", sourceText = text, mapName = function() return nil end })
      eq(rows, {
        { header = true, depth = 1, section = "dungeon", key = "journal|Classic|dungeon", text = "Dungeon drops",
          owned = 1, total = 4, collapsed = false },
        { header = true, depth = 2, section = "dungeon", group = "blackrock depths",
          key = "journal|Classic|dungeon|blackrock depths", text = "Blackrock Depths", owned = 1, total = 1, collapsed = false },
        { id = 11, m = m[11], owned = true, depth = 2 },
        { header = true, depth = 2, section = "dungeon", group = "zul'aman",
          key = "journal|Classic|dungeon|zul'aman", text = "zul'Aman", owned = 0, total = 1, collapsed = false },
        { id = 12, m = m[12], owned = false, depth = 2 },
        { header = true, depth = 2, section = "dungeon", group = "zul'farrak",
          key = "journal|Classic|dungeon|zul'farrak", text = "Zul'Farrak", owned = 0, total = 1, collapsed = false },
        { id = 10, m = m[10], owned = false, depth = 2 },
        { header = true, depth = 2, section = "dungeon", group = "~other",
          key = "journal|Classic|dungeon|~other", text = "Other", owned = 0, total = 1, collapsed = false },
        { id = 13, m = m[13], owned = false, depth = 2 },
        { header = true, depth = 1, section = "world", key = "journal|Classic|world", text = "World drops / rares",
          owned = 0, total = 1, collapsed = false },
        { header = true, depth = 2, section = "world", group = "feralas",
          key = "journal|Classic|world|feralas", text = "Feralas", owned = 0, total = 1, collapsed = false },
        { id = 20, m = m[20], owned = false, depth = 2 },
        { header = true, depth = 1, section = "delve", key = "journal|Classic|delve", text = "Delves",
          owned = 0, total = 1, collapsed = false },
        { id = 30, m = m[30], owned = false },
      })
    end)

    it("merges an instance named by the route and by the client, labelled with the client name", function()
      local route = {
        { title = "Run Vortex Pinnacle (Dungeon)", bosses = { { mount = 395, boss = "Altairus" } } },
        { title = "Run Firelands (Raid)", bosses = { { mount = 700, boss = "Ragnaros" } } },
      }
      local ns = loadUI(nil, { Route = route })
      local a = { name = "A", section = "dungeon" }
      local b = { name = "B", section = "dungeon" }
      local c = { name = "C", section = "raid" }
      local texts = { [50] = "|cFFFFD200Zone:|r The Vortex Pinnacle" }
      -- The route-named mount comes first in Select order.
      local rows = ns.UI.ListRows({ { id = 395, m = a, section = "dungeon" }, { id = 50, m = b, section = "dungeon" },
        { id = 700, m = c, section = "raid" } }, nil,
        { view = "journal", exp = "Cataclysm", sourceText = function(id) return texts[id] end })
      eq(rows, {
        { header = true, depth = 1, section = "dungeon", key = "journal|Cataclysm|dungeon", text = "Dungeon drops",
          owned = 0, total = 2, collapsed = false },
        { header = true, depth = 2, section = "dungeon", group = "vortex pinnacle",
          key = "journal|Cataclysm|dungeon|vortex pinnacle", text = "The Vortex Pinnacle", owned = 0, total = 2,
          collapsed = false },
        { id = 395, m = a, owned = false, depth = 2 },
        { id = 50, m = b, owned = false, depth = 2 },
        { header = true, depth = 1, section = "raid", key = "journal|Cataclysm|raid", text = "Raid drops",
          owned = 0, total = 1, collapsed = false },
        { header = true, depth = 2, section = "raid", group = "firelands",
          key = "journal|Cataclysm|raid|firelands", text = "Firelands", owned = 0, total = 1, collapsed = false },
        { id = 700, m = c, owned = false, depth = 2 },
      })
    end)

    it("stays flat when Other is the only sub-group with a shown mount", function()
      local ns = loadUI()
      local a = { name = "A", section = "dungeon" }
      local b = { name = "B", section = "dungeon" }
      local texts = { [1] = "Zone: Stratholme" }
      local selected = { { id = 1, m = a, section = "dungeon" }, { id = 2, m = b, section = "dungeon" } }
      local function owned(id) return id == 1 end
      local rows = ns.UI.ListRows(selected, owned,
        { view = "journal", sourceText = function(id) return texts[id] end, hideOwned = true })
      eq(rows, {
        { header = true, depth = 1, section = "dungeon", key = "journal||dungeon", text = "Dungeon drops",
          owned = 1, total = 2, collapsed = false },
        { id = 2, m = b, owned = false },
      })
      -- Collected on: Stratholme has a shown mount again, so both sub-groups.
      rows = ns.UI.ListRows(selected, owned, { view = "journal", sourceText = function(id) return texts[id] end })
      local labels = {}
      for _, row in ipairs(rows) do if row.header then labels[#labels + 1] = row.text end end
      eq(labels, { "Dungeon drops", "Stratholme", "Other" })
    end)

    it("generic reputation groups are not sub-headers", function()
      local ns = loadUI()
      local function rep(name, group) return { name = name, section = "reputation", group = group } end
      local flat = ns.UI.ListRows({
        { id = 1, m = rep("A", "Reputation"), section = "reputation" },
        { id = 2, m = rep("B", "Renown"), section = "reputation" },
        { id = 3, m = rep("C", "Paragon Reputation"), section = "reputation" },
      }, nil, { view = "journal" })
      eq(#flat, 4, "header + three flat rows")
      eq(flat[2].depth, nil)
      local split = ns.UI.ListRows({
        { id = 1, m = rep("A", "Renown"), section = "reputation" },
        { id = 2, m = rep("B", "Netherwing"), section = "reputation" },
      }, nil, { view = "journal" })
      local got = {}
      for _, row in ipairs(split) do got[#got + 1] = row.header and row.text or row.id end
      eq(got, { "Reputation", "Netherwing", 2, "Other", 1 })
    end)

    it("collapsing a section hides its sub-headers and mounts; a sub-group hides its mounts", function()
      local ns = loadUI()
      local selected, _, text = sample()
      local collapsed = { ["journal|Classic|dungeon"] = true, ["journal|Classic|world|feralas"] = true }
      local rows = ns.UI.ListRows(selected, nil,
        { view = "journal", exp = "Classic", sourceText = text, collapsed = collapsed })
      local keys = {}
      for _, row in ipairs(rows) do
        keys[#keys + 1] = row.header and (row.key .. (row.collapsed and "+" or "-")) or row.id
      end
      eq(keys, { "journal|Classic|dungeon+", "journal|Classic|world-", "journal|Classic|world|feralas+",
        "journal|Classic|delve-", 30 })
      eq(rows[1].total, 4, "a collapsed header still counts its mounts")
    end)

    it("hideOwned drops owned rows but counts them; groups with nothing shown are left out", function()
      local ns = loadUI()
      local selected, _, text = sample()
      local owned = { [11] = true, [20] = true, [10] = true }
      local rows = ns.UI.ListRows(selected, function(id) return owned[id] end,
        { view = "journal", exp = "Classic", sourceText = text, hideOwned = true })
      local got = {}
      for _, row in ipairs(rows) do
        got[#got + 1] = row.header and (row.text .. " " .. row.owned .. "/" .. row.total) or row.id
      end
      eq(got, { "Dungeon drops 2/4", "zul'Aman 0/1", 12, "Other 0/1", 13, "Delves 0/1", 30 })
    end)

    it("a section whose only sub-group is Other stays flat", function()
      local ns = loadUI()
      local a, b = { name = "A", section = "raid" }, { name = "B", section = "raid" }
      local rows = ns.UI.ListRows({ { id = 1, m = a, section = "raid" }, { id = 2, m = b, section = "raid" } }, nil,
        { view = "journal" })
      eq(#rows, 3)
      eq(rows[1].depth, 1)
      eq({ rows[2].id, rows[3].id }, { 1, 2 })
    end)

    it("orders sub-groups independently of input order and badges only top-level headers", function()
      local ns = loadUI()
      local selected, _, text = sample()
      local opts = { view = "journal", sourceText = text,
        headerSuffix = function(s) return s == "dungeon" and "!" or nil end }
      local first = ns.UI.ListRows(selected, nil, opts)
      eq(ns.UI.ListRows(selected, nil, opts), first, "same input, same rows")
      eq(first[1].badge, "!")
      for _, row in ipairs(first) do
        if row.header and row.depth == 2 then eq(row.badge, nil, "no badge on " .. row.text) end
      end
      local function subs(rows)
        local out = {}
        for _, row in ipairs(rows) do if row.depth == 2 then out[#out + 1] = row.key end end
        return out
      end
      -- Same mounts, one section, reversed inside it: same sub-group order.
      local swapped = { selected[4], selected[3], selected[2], selected[1], selected[5], selected[6] }
      eq(subs(ns.UI.ListRows(swapped, nil, opts)), subs(first))
    end)

    it("HeaderText adds (owned/total) before the badge, (n left) on Lockouts; HeaderGlyph is a pop-out's +/-", function()
      local ns = loadUI()
      eq(ns.UI.HeaderText({ text = "Raid drops", owned = 2, total = 5 }), "Raid drops  |cff9d9d9d(2/5)|r")
      eq(ns.UI.HeaderText({ text = "Brewfest", owned = 0, total = 1, badge = "Active now" }),
        "Brewfest  |cff9d9d9d(0/1)|r  |cff33ff99Active now|r")
      eq(ns.UI.HeaderText({ text = "Daily", owned = 2, total = 5, reset = "daily" }), "Daily  |cff9d9d9d(3 left)|r")
      eq(ns.UI.HeaderGlyph(false), "-")
      eq(ns.UI.HeaderGlyph(true), "+")
    end)
  end)

  describe("source text", function()
    it("StripMarkup removes colours, links, textures and atlases; |n breaks lines", function()
      local ns = loadUI()
      local SM = ns.UI.StripMarkup
      eq(SM("|cFFFFD200Drop:|r Ultraxion|n|cFFFFD200Zone: |rDragon Soul"), "Drop: Ultraxion\nZone: Dragon Soul")
      eq(SM("|cnNORMAL_FONT_COLOR:Zone:|r |Hmapzone:107|hNagrand|h"), "Zone: Nagrand")
      eq(SM("Cost: 500|TInterface\\MoneyFrame\\UI-GoldIcon:0|t |A:raceicon-dwarf-male:16:16|aDwarf"), "Cost: 500 Dwarf")
      eq(SM("a\r\nb"), "a\nb", "CRLF")
      eq(SM(nil), nil)
      eq(SM(5), nil)
    end)

    it("DisplayMarkup keeps textures and atlases, sized to the text", function()
      local ns = loadUI()
      local DM = ns.UI.DisplayMarkup
      eq(DM("|cFFFFD200Cost:|r 2000|TINTERFACE\\MONEYFRAME\\UI-GOLDICON.BLP:0|t"),
        "Cost: 2000|TINTERFACE\\MONEYFRAME\\UI-GOLDICON.BLP:0|t")
      eq(DM("5|T463446:16:16:2:0|t"), "5|T463446:0|t", "fileID, size fields rewritten")
      eq(DM("x |A:raceicon-dwarf-male:16:16|a y"), "x |Araceicon-dwarf-male:0:0|a y")
      eq(DM("a|n|Hitem:1|hLink|h"), "a\nLink")
      eq(DM(nil), nil)
    end)

    it("SourcePairs keeps icons in values only with keepIcons", function()
      local ns = loadUI()
      local SP = ns.UI.SourcePairs
      local src = "|cFFFFD200Vendor:|r Mei Francis|n|cFFFFD200Zone:|r Dalaran|n|cFFFFD200Cost:|r 2000|TINTERFACE\\MONEYFRAME\\UI-GOLDICON.BLP:0|t"
      eq(SP(src)[3], { label = "Cost:", value = "2000" }, "stripped by default")
      eq(SP(src, true), {
        { label = "Vendor:", value = "Mei Francis" }, { label = "Zone:", value = "Dalaran" },
        { label = "Cost:", value = "2000|TINTERFACE\\MONEYFRAME\\UI-GOLDICON.BLP:0|t" },
      })
      eq(SP("Cost: |T1357489:14|t 5 |T1357489:14|t", true)[1],
        { label = "Cost:", value = "|T1357489:0|t 5 |T1357489:0|t" }, "value starts and ends with an icon")
      eq(SP("|T1357489:14|tCost: 5", true)[1], { label = "Cost:", value = "5" }, "icon before the label")
      eq(ns.UI.SourceZone("Zone: Dalaran |T1:0|t"), "Dalaran", "zone matching stays stripped")
      eq(ns.UI.SourceZones("|cFFFFD200Drop:|r Huolon|n|cFFFFD200Zone:|r Timeless Isle|n"
        .. "|cFFFFD200Vendor:|r Mistweaver Xia|n|cFFFFD200Location: |rTimeless Isle, Kun-Lai Summit"),
        { "Timeless Isle", "Timeless Isle, Kun-Lai Summit" }, "every Zone: / Location: line")
      eq(ns.UI.SourceZones("|cFFFFD200Vendor:|r Someone"), {})
      eq(ns.UI.SourceZones(nil), {})
    end)

    it("RowDescription keeps icons", function()
      local ns = loadUI(nil, { Mounts = {}, Route = ROUTE })
      ns.AchievementScan.Lookup = function() return nil, "none" end
      eq(ns.UI.RowDescription(1, "Quest: Reward |T463446:16:16|t"), "Quest: Reward |T463446:0|t")
    end)

    it("SourcePairs splits labelled lines and keeps the client's labels", function()
      local ns = loadUI()
      local SP = ns.UI.SourcePairs
      eq(SP("|cFFFFD200Drop:|r Ultraxion|n|cFFFFD200Zone:|r Dragon Soul"), {
        { label = "Drop:", value = "Ultraxion" },
        { label = "Zone:", value = "Dragon Soul" },
      })
      eq(SP("|cFFFFD200Achievement: |rGlory of the Hero|n|cFFFFD200Category: |rDungeons & Raids"), {
        { label = "Achievement:", value = "Glory of the Hero" },
        { label = "Category:", value = "Dungeons & Raids" },
      })
      eq(SP("Achievement: Ahead of the Curve: Ultraxion"),
        { { label = "Achievement:", value = "Ahead of the Curve: Ultraxion" } }, "colon inside the value")
      eq(SP("Promotion\n\n  Zone:   \nBlizzard Store  "), { { value = "Promotion" }, { value = "Blizzard Store" } },
        "unlabelled lines kept, empty lines and empty values dropped")
      eq(SP("This mount can be bought for a while from the shop: soon"),
        { { value = "This mount can be bought for a while from the shop: soon" } }, "a sentence is not a label")
      eq(SP("Butin : Ultraxion"), { { label = "Butin :", value = "Ultraxion" } }, "space before the colon")
      eq(SP("\230\142\137\232\144\189\239\188\154Boss"),
        { { label = "\230\142\137\232\144\189\239\188\154", value = "Boss" } }, "full-width colon")
      eq(SP(nil), {})
      eq(SP(""), {})
    end)

    it("SourcePairs splits several labels on one line", function()
      local ns = loadUI()
      local SP = ns.UI.SourcePairs
      eq(SP("Drop: Ultraxion Zone: Dragon Soul"), {
        { label = "Drop:", value = "Ultraxion" }, { label = "Zone:", value = "Dragon Soul" },
      }, "known labels in plain text")
      eq(SP("|cFFFFD200Drop: |rUltraxion |cFFFFD200Zone: |rDragon Soul"), {
        { label = "Drop:", value = "Ultraxion" }, { label = "Zone:", value = "Dragon Soul" },
      }, "coloured labels")
      eq(SP("|cnNORMAL_FONT_COLOR:Vendor:|r Mei |cnNORMAL_FONT_COLOR:Treasure Hunt:|r Big Chest"), {
        { label = "Vendor:", value = "Mei" }, { label = "Treasure Hunt:", value = "Big Chest" },
      }, "named-colour labels, any label word")
      eq(SP("Vendor: Mei Francis Zone: Dalaran Cost: 200"), {
        { label = "Vendor:", value = "Mei Francis" }, { label = "Zone:", value = "Dalaran" },
        { label = "Cost:", value = "200" },
      })
      eq(SP("Achievement: Ahead of the Curve: Ultraxion"),
        { { label = "Achievement:", value = "Ahead of the Curve: Ultraxion" } }, "unknown words never split")
      eq(SP("Zone: |cff00ff00Icecrown|r"), { { label = "Zone:", value = "Icecrown" } }, "colour inside a value")
      BATTLE_PET_SOURCE_1, ZONE_COLON = "Beute", "Gebiet:"
      local got = SP("Beute: Ultraxion Gebiet: Drachenseele")
      BATTLE_PET_SOURCE_1, ZONE_COLON = nil, nil
      eq(got, { { label = "Beute:", value = "Ultraxion" }, { label = "Gebiet:", value = "Drachenseele" } },
        "the client's own label words")
    end)
  end)

  describe("RowDescription", function()
    local mounts = {
      [445] = { name = "Experiment 12-B", tab = "journal", section = "raid", group = "Raid Drop" },
      [395] = { name = "Drake of the North Wind", tab = "journal", section = "dungeon", group = "Dungeon Drop" },
      [515] = { name = "Son of Galleon", tab = "journal", section = "world", group = "World Boss" },
      [262] = { name = "Red Proto-Drake", tab = "misc", section = "achievement", group = "Achievement" },
      [700] = { name = "Group only", tab = "misc", section = "other", group = "Argent Tournament" },
      [800] = { name = "Nothing", tab = "misc", section = "other" },
    }
    local function load(game)
      local ns = loadUI(game, { Mounts = mounts, Route = ROUTE })
      ns.AchievementScan.Lookup = function() return nil, "none" end
      return ns
    end

    it("Drop with Zone or Location", function()
      local RD = load().UI.RowDescription
      eq(RD(445, "|cFFFFD200Drop:|r Ultraxion|n|cFFFFD200Zone:|r Dragon Soul"), "Drop: Ultraxion · Dragon Soul")
      eq(RD(445, "Drop: Ultraxion\nLocation: Dragon Soul"), "Drop: Ultraxion · Dragon Soul")
      eq(RD(445, "Drop: Ultraxion"), "Drop: Ultraxion")
      eq(RD(445, "Zone: Dragon Soul\nDrop: Ultraxion"), "Drop: Ultraxion · Dragon Soul", "order of lines")
    end)

    it("Achievement from the source text, else the achievement scan's name", function()
      local ns = load({ AchievementName = function(id) if id == 10 then return "Glory of the Hero" end end })
      eq(ns.UI.RowDescription(262, "|cFFFFD200Achievement: |rGlory of the Raider|n|cFFFFD200Category: |rRaids"),
        "Achievement: Glory of the Raider")
      eq(ns.UI.RowDescription(262, nil), "Achievement", "scan knows nothing: the category")
      ns.AchievementScan.Lookup = function(id) if id == 262 then return 10, "ready" end end
      eq(ns.UI.RowDescription(262, nil), "Achievement: Glory of the Hero")
      eq(ns.UI.RowDescription(262, "Category: Raids"), "Achievement: Glory of the Hero",
        "scan name beats a generic line")
    end)

    it("Vendor with zone, Quest alone", function()
      local RD = load().UI.RowDescription
      eq(RD(700, "Vendor: Mei Francis|nZone: Dalaran|nCost: 200"), "Vendor: Mei Francis · Dalaran")
      eq(RD(700, "Vendor: Mei Francis"), "Vendor: Mei Francis")
      eq(RD(700, "Quest: The Wrathgate|nZone: Dragonblight"), "Quest: The Wrathgate")
    end)

    it("another labelled line, with the zone when there is one", function()
      local RD = load().UI.RowDescription
      eq(RD(700, "Treasure: Glimmering Chest|nZone: Hallowfall"), "Treasure: Glimmering Chest · Hallowfall")
      eq(RD(700, "Profession: Engineering"), "Profession: Engineering")
    end)

    it("the route's boss (instance) when the source text names no source", function()
      local RD = load().UI.RowDescription
      eq(RD(395, nil), "Altairus (Vortex Pinnacle)")
      eq(RD(395, "Zone: The Vortex Pinnacle"), "Altairus (Vortex Pinnacle)", "a lone zone is weaker")
      eq(RD(515, nil), "Galleon", "no instance in the step title")
    end)

    it("then a lone zone, an unlabelled line, then the category", function()
      local RD = load().UI.RowDescription
      eq(RD(700, "Zone: Icecrown"), "Zone: Icecrown")
      eq(RD(700, "Promotion"), "Promotion")
      eq(RD(700, nil), "Argent Tournament")
      eq(RD(800, nil), "")
      eq(RD(9999, nil), "", "unknown mount")
    end)

    it("knows the client's localised labels (GlobalStrings)", function()
      BATTLE_PET_SOURCE_1, ZONE_COLON = "Beute", "Gebiet:"
      local RD = load().UI.RowDescription
      local got = RD(445, "Beute: Ultraxion|nGebiet: Drachenseele")
      BATTLE_PET_SOURCE_1, ZONE_COLON = nil, nil
      eq(got, "Beute: Ultraxion · Drachenseele")
    end)

    it("RowSourceText uses the row's description, else SourceLine, plus the tag", function()
      local ns = load()
      eq(ns.UI.RowSourceText({ id = 700, desc = "Drop: X · Y" }), "Drop: X · Y")
      eq(ns.UI.RowSourceText({ id = 700, desc = "Drop: X", tag = "T" }), "Drop: X · |cff33ff99T|r")
      eq(ns.UI.RowSourceText({ id = 700 }), "Argent Tournament")
    end)
  end)
end)
