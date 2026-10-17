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
  it("toc lists Tooltip, List, JournalHome right after Frame", function()
    local fh = assert(io.open(ROOT .. "/AzerothTrail.toc", "r"))
    local lines = {}
    for line in fh:lines() do
      line = line:gsub("\r$", ""):gsub("^%s+", ""):gsub("%s+$", "")
      if line ~= "" and not line:find("^#") then lines[#lines + 1] = line end
    end
    fh:close()
    local frame
    for i, line in ipairs(lines) do if line == "UI\\Frame.lua" then frame = i end end
    ok(frame, "UI\\Frame.lua in toc")
    eq({ lines[frame + 1], lines[frame + 2], lines[frame + 3] },
      { "UI\\Tooltip.lua", "UI\\List.lua", "UI\\JournalHome.lua" })
  end)

  it("loads the UI files and registers the journal view without building it", function()
    local ns = loadUI()
    for _, name in ipairs({ "ShowMountTooltip", "LockoutStatus", "TooltipLines", "List",
      "SourceLine", "MountIcon", "SectionLabel", "ListRows", "PreviewMount", "FilterMenuItems",
      "FilterChecked", "ToggleFilter", "ApplyFilterAction", "FiltersAreDefault", "StyleIcon" }) do
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
      eq(ns.UI.SectionLabel("tradingpost"), "Trading Post")
      eq(ns.UI.SectionLabel("timewalking"), "Timewalking")
      eq(ns.UI.SectionLabel("mystery"), "mystery")
    end)
  end)

  describe("filter menu", function()
    local SOURCES = { "dungeon", "raid", "world", "delve", "treasure", "quest", "activity",
      "reputation", "vendor", "other" }
    local LABELS = { "Dungeon drops", "Raid drops", "World drops / rares", "Delves", "Treasures & caches",
      "Quests", "Zone activities", "Reputation", "Vendors", "Other" }

    it("Journal tab: Collected, a divider, the ten sources, then Check all / Uncheck all", function()
      local ns = loadUI()
      local items = ns.UI.FilterMenuItems("journal", { collected = true, raid = false, quest = false })
      local want = {
        { kind = "checkbox", key = "collected", label = "Collected", checked = true },
        { kind = "divider" },
        { kind = "title", label = "Sources" },
      }
      for i, key in ipairs(SOURCES) do
        want[#want + 1] = { kind = "checkbox", key = key, label = LABELS[i],
          checked = key ~= "raid" and key ~= "quest" }
      end
      want[#want + 1] = { kind = "divider" }
      want[#want + 1] = { kind = "button", action = "checkAll", label = "Check all" }
      want[#want + 1] = { kind = "button", action = "uncheckAll", label = "Uncheck all" }
      eq(items, want)
    end)

    it("other tabs get Collected only; missing keys follow Journal.Select", function()
      local ns = loadUI()
      eq(ns.UI.FilterMenuItems("holiday", {}),
        { { kind = "checkbox", key = "collected", label = "Collected", checked = false } })
      eq(ns.UI.FilterMenuItems("misc", { collected = true })[1].checked, true)
      eq(#ns.UI.FilterMenuItems(nil, nil), 1, "no tab, no filters")
      local journal = ns.UI.FilterMenuItems("journal", {})
      eq(journal[4].checked, true, "a missing source key means shown")
    end)

    it("ToggleFilter flips one key and returns the new state", function()
      local ns = loadUI()
      local f = { collected = false }
      eq(ns.UI.ToggleFilter(f, "collected"), true)
      eq(ns.UI.ToggleFilter(f, "raid"), false, "missing source key was on")
      eq(ns.UI.ToggleFilter(f, "raid"), true)
      eq(f, { collected = true, raid = true })
    end)

    it("Check all / Uncheck all set every source and leave Collected alone", function()
      local ns = loadUI()
      local f = { collected = true, raid = false }
      ns.UI.ApplyFilterAction(f, "uncheckAll", "journal")
      for _, key in ipairs(SOURCES) do eq(f[key], false, key) end
      eq(f.collected, true)
      ns.UI.ApplyFilterAction(f, "checkAll", "journal")
      for _, key in ipairs(SOURCES) do eq(f[key], true, key) end
      eq(f.collected, true)
    end)

    it("reset and the default check cover only what the tab's menu shows", function()
      local ns = loadUI()
      local f = { collected = true, raid = false }
      eq(ns.UI.FiltersAreDefault(f, "journal"), false)
      eq(ns.UI.FiltersAreDefault({ collected = false, raid = false }, "holiday"), true,
        "sources are not in the Holidays menu")
      ns.UI.ApplyFilterAction(f, "reset", "holiday")
      eq(f, { collected = false, raid = false }, "Holidays reset: Collected only")
      ns.UI.ApplyFilterAction(f, "reset", "journal")
      eq(f, ns.Journal.DefaultFilters)
      eq(ns.UI.FiltersAreDefault(f, "journal"), true)
      eq(ns.UI.FiltersAreDefault({}, "journal"), true, "an empty table reads as the defaults")
      ok(f ~= ns.Journal.DefaultFilters, "the saved table is updated, not replaced")
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
    it("shows rate, attempts, Rarity count, lockout and the hint", function()
      local ns = loadUI({
        MountInfo = function(id) if id == 10 then return "Client Name", 1, 2 end end,
        IsQuestDone = function() return true end,
      }, { Mounts = { [10] = { name = "Data Name", chance = 33.4, item = 5555, quest = 111 } } })
      ns.db.global.attempts[10] = 7
      ns.RarityBridge.Attempts = function(item) if item == 5555 then return 42 end end
      eq(ns.UI.TooltipLines(10), {
        "Client Name",
        "~1 in 33 (approx.)",
        "Times farmed: 7",
        "Rarity: 42",
        "Lockout: Saved",
        "Ctrl-click to preview",
      })
    end)

    it("leaves out rate and Rarity when unknown and shows a dash for untracked mounts", function()
      local ns = loadUI(nil, { Mounts = { [20] = { name = "Vendor Mount", item = 1 } } })
      ns.RarityBridge.Attempts = function() return nil end
      eq(ns.UI.TooltipLines(20), {
        "Vendor Mount",
        "Times farmed: 0",
        "Lockout: —",
        "Ctrl-click to preview",
      })
    end)

    it("shows kill statistics instead of the attempt counter for mounts with stats", function()
      local ns = loadUI({ CharKey = function() return "Me-Realm" end },
        { Mounts = { [40] = { name = "Stat Mount", item = 7777, stats = { 1, 2 } } } })
      ns.db.global.attempts[40] = 2
      ns.db.global.stats = { ["Me-Realm"] = { [40] = 3 }, ["Alt-Realm"] = { [40] = 4 } }
      ns.RarityBridge.Attempts = function() return 11 end
      eq(ns.UI.TooltipLines(40), {
        "Stat Mount",
        "Kills: 7 (this character: 3)",
        "Rarity: 11",
        "Lockout: —",
        "Ctrl-click to preview",
      })
      ns.db.global.stats = { ["Me-Realm"] = { [40] = 3 } }
      eq(ns.UI.TooltipLines(40)[2], "Kills: 3", "only this character has data")
    end)

    it("keeps the attempt counter for mounts with stats but no reading yet, and without stats", function()
      local ns = loadUI({ CharKey = function() return "Me-Realm" end }, { Mounts = {
        [40] = { name = "Stat Mount", stats = { 1 } },
        [41] = { name = "Plain Mount" },
      } })
      ns.RarityBridge.Attempts = function() return nil end
      ns.db.global.attempts[40], ns.db.global.attempts[41] = 2, 5
      ns.db.global.stats = { ["Me-Realm"] = { [41] = 9 } } -- stale reading for a mount without stats
      eq(ns.UI.TooltipLines(40)[2], "Times farmed: 2")
      eq(ns.UI.TooltipLines(41)[2], "Times farmed: 5")
      ns.db.global.stats = nil
      eq(ns.UI.TooltipLines(40)[2], "Times farmed: 2", "no stats table at all")
    end)

    it("shows Available and Manual states", function()
      local ns = loadUI(nil, {
        Mounts = { [30] = { name = "A", quest = 1, chance = 100 }, [31] = { name = "M" } },
        Lockouts = { [31] = { manual = true, reset = "weekly" } },
      })
      local a, m = ns.UI.TooltipLines(30), ns.UI.TooltipLines(31)
      eq(a[2], "~1 in 100 (approx.)")
      eq(a[4], "Lockout: Available")
      eq(m[3], "Lockout: Manual")
    end)

    it("paints GameTooltip: title, body lines, hint", function()
      local ns = loadUI(nil, { Mounts = { [20] = { name = "Vendor Mount" } } })
      local calls = {}
      local tip = {}
      function tip:SetOwner(owner, anchor) calls[#calls + 1] = { "SetOwner", owner, anchor } end
      function tip:SetText(text) calls[#calls + 1] = { "SetText", text } end
      function tip:AddLine(text) calls[#calls + 1] = { "AddLine", text } end
      function tip:Show() calls[#calls + 1] = { "Show" } end
      local old = GameTooltip
      GameTooltip = tip
      local owner = {}
      ns.UI.ShowMountTooltip(owner, 20)
      GameTooltip = old
      eq(calls, {
        { "SetOwner", owner, "ANCHOR_RIGHT" },
        { "SetText", "Vendor Mount" },
        { "AddLine", "Times farmed: 0" },
        { "AddLine", "Lockout: —" },
        { "AddLine", "Ctrl-click to preview" },
        { "Show" },
      })
    end)
  end)

  describe("flavor text", function()
    local function paint(ns, id)
      local calls, tip = {}, {}
      function tip:SetOwner() end
      function tip:SetText(text) calls[#calls + 1] = { "SetText", text } end
      function tip:AddLine(text, r, g, b, wrap) calls[#calls + 1] = { "AddLine", text, wrap } end
      function tip:Show() end
      local old = GameTooltip
      GameTooltip = tip
      ns.UI.ShowMountTooltip({}, id)
      GameTooltip = old
      return calls
    end

    it("TooltipFlavor returns the client's mount description", function()
      local ns = loadUI({ MountDescription = function(id) if id == 20 then return "Swift as the wind." end end })
      eq(ns.UI.TooltipFlavor(20), "Swift as the wind.")
      eq(ns.UI.TooltipFlavor(21), nil)
    end)

    it("paints the description wrapped, right under the name", function()
      local ns = loadUI({ MountDescription = function() return "Swift as the wind." end },
        { Mounts = { [20] = { name = "Vendor Mount" } } })
      local calls = paint(ns, 20)
      eq(calls[1], { "SetText", "Vendor Mount" })
      eq(calls[2], { "AddLine", "Swift as the wind.", true })
      eq(calls[3], { "AddLine", "Times farmed: 0", nil })
    end)

    it("shows the mount item's own tooltip, then our lines, when the mount has an item", function()
      local ns = loadUI({ MountDescription = function() return "Swift as the wind." end },
        { Mounts = { [20] = { name = "Vendor Mount", item = 87771 } } })
      local calls, tip = {}, {}
      function tip:SetOwner() end
      function tip:SetItemByID(id) calls[#calls + 1] = { "SetItemByID", id } end
      function tip:SetText(text) calls[#calls + 1] = { "SetText", text } end
      function tip:AddLine(text) calls[#calls + 1] = { "AddLine", text } end
      function tip:Show() calls[#calls + 1] = { "Show" } end
      local old = GameTooltip
      GameTooltip = tip
      ns.UI.ShowMountTooltip({}, 20)
      GameTooltip = old
      eq(calls, {
        { "SetItemByID", 87771 },
        { "AddLine", " " },
        { "AddLine", "Times farmed: 0" },
        { "AddLine", "Lockout: —" },
        { "AddLine", "Ctrl-click to preview" },
        { "Show" },
      })
    end)

    it("adds nothing when there is no description", function()
      local ns = loadUI({ MountDescription = function() return nil end },
        { Mounts = { [20] = { name = "Vendor Mount" } } })
      eq(paint(ns, 20)[2], { "AddLine", "Times farmed: 0", nil })
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

    it("SubGroup: instance for dungeons/raids, zone for world, faction group for reputation", function()
      local ns = loadUI(nil, { Route = ROUTE })
      local texts = {
        [1] = "|cFFFFD200Drop:|r Boss|n|cFFFFD200Zone:|r Stratholme",
        [395] = "Zone: Skywall",
        [4] = "Zone: Feralas",
      }
      local ctx = {
        sourceText = function(id) return texts[id] end,
        mapName = function(mapID)
          if mapID == 317 then return "Stratholme Map" end
          if mapID == 70 then return "Dustwallow" end
        end,
      }
      local SG = ns.UI.SubGroup
      eq({ SG(395, {}, "dungeon", ctx) }, { "Vortex Pinnacle", "Vortex Pinnacle" }, "route step first")
      eq({ SG(515, {}, "raid", ctx) }, { "~other", "Other" }, "a Kill step is no instance")
      eq({ SG(1, { coords = { m = 317 } }, "dungeon", ctx) }, { "Stratholme", "Stratholme" }, "then source Zone:")
      eq({ SG(2, { coords = { m = 317 } }, "raid", ctx) }, { "Stratholme Map", "Stratholme Map" }, "then coords map")
      eq({ SG(3, {}, "dungeon", ctx) }, { "~other", "Other" })
      eq({ SG(4, { coords = { m = 70 } }, "world", ctx) }, { "Feralas", "Feralas" }, "world: Zone: first")
      eq({ SG(5, { coords = { m = 70 } }, "world", ctx) }, { "Dustwallow", "Dustwallow" }, "world: coords map")
      eq({ SG(6, {}, "world", ctx) }, { "~other", "Other" })
      eq({ SG(7, { group = "Netherwing" }, "reputation", ctx) }, { "Netherwing", "Netherwing" })
      eq({ SG(8, { group = "" }, "reputation", ctx) }, { "~other", "Other" })
      eq(SG(9, { group = "x" }, "delve", ctx), nil, "other sections are flat")
      eq(SG(9, { group = "x" }, "brewfest", ctx), nil)
      eq({ SG(1, {}, "dungeon", nil) }, { "~other", "Other" }, "no ctx")
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
        { header = true, depth = 2, section = "dungeon", group = "Blackrock Depths",
          key = "journal|Classic|dungeon|Blackrock Depths", text = "Blackrock Depths", owned = 1, total = 1, collapsed = false },
        { id = 11, m = m[11], owned = true },
        { header = true, depth = 2, section = "dungeon", group = "zul'Aman",
          key = "journal|Classic|dungeon|zul'Aman", text = "zul'Aman", owned = 0, total = 1, collapsed = false },
        { id = 12, m = m[12], owned = false },
        { header = true, depth = 2, section = "dungeon", group = "Zul'Farrak",
          key = "journal|Classic|dungeon|Zul'Farrak", text = "Zul'Farrak", owned = 0, total = 1, collapsed = false },
        { id = 10, m = m[10], owned = false },
        { header = true, depth = 2, section = "dungeon", group = "~other",
          key = "journal|Classic|dungeon|~other", text = "Other", owned = 0, total = 1, collapsed = false },
        { id = 13, m = m[13], owned = false },
        { header = true, depth = 1, section = "world", key = "journal|Classic|world", text = "World drops / rares",
          owned = 0, total = 1, collapsed = false },
        { header = true, depth = 2, section = "world", group = "Feralas",
          key = "journal|Classic|world|Feralas", text = "Feralas", owned = 0, total = 1, collapsed = false },
        { id = 20, m = m[20], owned = false },
        { header = true, depth = 1, section = "delve", key = "journal|Classic|delve", text = "Delves",
          owned = 0, total = 1, collapsed = false },
        { id = 30, m = m[30], owned = false },
      })
    end)

    it("collapsing a section hides its sub-headers and mounts; a sub-group hides its mounts", function()
      local ns = loadUI()
      local selected, _, text = sample()
      local collapsed = { ["journal|Classic|dungeon"] = true, ["journal|Classic|world|Feralas"] = true }
      local rows = ns.UI.ListRows(selected, nil,
        { view = "journal", exp = "Classic", sourceText = text, collapsed = collapsed })
      local keys = {}
      for _, row in ipairs(rows) do
        keys[#keys + 1] = row.header and (row.key .. (row.collapsed and "+" or "-")) or row.id
      end
      eq(keys, { "journal|Classic|dungeon+", "journal|Classic|world-", "journal|Classic|world|Feralas+",
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

    it("HeaderText adds (owned/total) before the badge; HeaderIcon picks the atlas or text", function()
      local ns = loadUI()
      eq(ns.UI.HeaderText({ text = "Raid drops", owned = 2, total = 5 }), "Raid drops  |cff9d9d9d(2/5)|r")
      eq(ns.UI.HeaderText({ text = "Brewfest", owned = 0, total = 1, badge = "Active now" }),
        "Brewfest  |cff9d9d9d(0/1)|r  |cff33ff99Active now|r")
      eq({ ns.UI.HeaderIcon(false) }, { nil, "\226\128\147" }, "no atlas: an en dash when expanded (no U+2212 in the default font)")
      eq({ ns.UI.HeaderIcon(true) }, { nil, "+" })
      STUB_ATLASES["campaign_headericon_open"] = true
      STUB_ATLASES["campaign_headericon_closed"] = true
      eq({ ns.UI.HeaderIcon(false) }, { "campaign_headericon_open", "\226\128\147" })
      eq({ ns.UI.HeaderIcon(true) }, { "campaign_headericon_closed", "+" })
    end)
  end)
end)
