-- Pure helpers of UI/Tooltip.lua and UI/List.lua (source line, icon, section
-- headers, tooltip lines, lockout status, preview) with stubbed Game and Data.
-- The frame code (List widget, journal home) is compile-checked only.

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
      "SourceLine", "MountIcon", "SectionLabel", "ListRows", "PreviewMount" }) do
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
        { header = true, section = "dungeon", text = "Dungeon drops" },
        { id = 1, m = a, owned = false },
        { id = 2, m = b, owned = true },
        { header = true, section = "raid", text = "Raid drops" },
        { id = 3, m = c, owned = false },
        { header = true, section = "brewfest", text = "Brewfest" },
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
        { header = true, section = "world", text = "World drops / rares" },
        { id = 1, m = a, owned = false },
        { header = true, section = "delve", text = "Delves" },
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
end)
