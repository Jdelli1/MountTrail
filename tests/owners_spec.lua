-- How many characters own a mount (Integrations/MountsRarity.lua over the
-- MountsRarity-2.0 library when another add-on loaded it), its tooltip line,
-- and the pop-out rows' rarity colour (Options "Colour pop-out names by rarity").

local function load()
  return load_addon({ "Core/Locale.lua", "Integrations/MountsRarity.lua" })
end

local LIB = { GetRarityByID = function(self, id) return ({ [1] = 0.28, [2] = 5, [3] = 15, [4] = 42, [5] = 80 })[id] end }

describe("ns.Owners", function()
  it("reads the library's percentage; nil without it, for an unknown mount, or on an error", function()
    local O = load().Owners
    eq(O.Available(), false, "the test stub has no MountsRarity-2.0")
    eq(O.Percent(1), nil)
    O.lib = LIB
    ok(O.Available())
    eq(O.Percent(1), 0.28)
    eq(O.Percent(99), nil, "untracked")
    eq(O.Percent(nil), nil)
    O.lib = { GetRarityByID = function() error("broken") end }
    eq(O.Percent(1), nil, "an error is nil")
  end)

  it("tiers like Mount Journal Enhanced: <2 legendary, <10 epic, <20 rare, <50 uncommon, else common", function()
    local O = load().Owners
    eq({ O.Quality(0.28), O.Quality(5), O.Quality(15), O.Quality(42), O.Quality(80) }, { 5, 4, 3, 2, 1 })
    eq(O.Color(0.28), { 1, 0.5, 0 }, "legendary orange without C_Item")
    eq(O.Text(0.28), "0.28%")
    eq(O.Text(42.345), "42.3%")
  end)
end)

describe("rarity in the tooltip and the pop-outs", function()
  local function loadUI()
    reset_ui_stub()
    local files = toc_lua_files()
    for _, f in ipairs({ "UI/Frame.lua", "UI/Tooltip.lua", "UI/List.lua", "UI/LockoutHelpers.lua",
      "UI/ChecklistView.lua", "UI/Popouts.lua" }) do files[#files + 1] = f end
    local ns = load_addon(files)
    ns.addon:OnInitialize()
    for k, v in pairs({
      MountInfo = function() return nil end, IsOwned = function() return false end,
      Exists = function() return true end, Faction = function() return "Alliance" end,
      SavedRows = function() return {} end, IsQuestDone = function() return false end,
      IsLfgDone = function() return false end, MountSourceText = function() return nil end,
      ActiveHolidays = function() return {} end, Now = function() return 1700000000 end,
      UntilDaily = function() return 3600 end, UntilWeekly = function() return 86400 end,
      PlayerName = function() return "Tester" end, CharKey = function() return "Tester-Realm" end,
    }) do ns.Game[k] = v end
    ns.Data.Mounts = { [1] = { name = "Rare One", exp = "Legion", tab = "journal", section = "vendor" } }
    return ns
  end

  it("the tooltip says how many characters own it, in its quality colour; nothing without the library", function()
    local ns = loadUI()
    local function rarityLine()
      for _, l in ipairs(ns.UI.TooltipLines(1)) do if l.left == "Rarity" then return l end end
    end
    eq(rarityLine(), nil, "no library: no line")
    ns.Owners.lib = LIB
    local l = rarityLine()
    eq({ l.double, l.right, l.rr, l.rg, l.rb }, { true, "0.28% of characters", 1, 0.5, 0 })
  end)

  it("pop-out rows take the rarity colour only with the option on", function()
    local ns = loadUI()
    ns.Owners.lib = LIB
    eq(ns.UI.PopoutRarityColor(1), nil, "off by default")
    ns.db.global.settings.rarityColors = true
    eq(ns.UI.PopoutRarityColor(1), { 1, 0.5, 0 })
    eq(ns.UI.PopoutRarityColor(99), nil, "unknown mount: the style's colour")
    ns.Owners.lib = false
    eq(ns.UI.PopoutRarityColor(1), nil, "no library")
  end)
end)
