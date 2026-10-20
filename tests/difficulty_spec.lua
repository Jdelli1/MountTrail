-- Wrong-difficulty warning: Lockouts.WrongDifficulty (Logic/Lockouts.lua) and
-- the warning itself (UI/DifficultyCheck.lua).

describe("Lockouts.WrongDifficulty", function()
  it("a mount of this instance that does not drop on this difficulty", function()
    local ns = load_addon({ "Core/Locale.lua", "Logic/Lockouts.lua" })
    local L = ns.Lockouts
    local specs = {
      [1] = { instance = 603, difficulties = { 4 } }, -- 25 Normal only
      [2] = { instance = 603, difficulties = { { 3, 4, 5, 6 } } }, -- any size or difficulty
      [3] = { instance = 999, difficulties = { 16 } }, -- another instance
      [4] = { quest = 5 }, -- no instance
      [5] = { instance = 603, difficulties = { 5, 6 } }, -- Heroic only
    }
    local function specFor(id) return specs[id] end
    eq(L.DropDifficulties(specs[2]), { [3] = true, [4] = true, [5] = true, [6] = true })
    local wrong = L.WrongDifficulty({ 1, 2, 3, 4, 5 }, 603, 3, specFor) -- 10 Normal
    local ids = {}
    for _, w in ipairs(wrong) do ids[#ids + 1] = w.id end
    eq(ids, { 1, 5 })
    eq(wrong[1].wanted, { 4 })
    eq(wrong[2].wanted, { 5, 6 })
    eq(L.WrongDifficulty({ 1 }, 603, 4, specFor), {}, "the right difficulty: nothing")
    eq(L.WrongDifficulty({ 1 }, nil, nil, specFor), {}, "outside instances: nothing")
  end)
end)

describe("the warning", function()
  local function loadUI()
    reset_ui_stub()
    local files = toc_lua_files()
    for _, f in ipairs({ "UI/Frame.lua", "UI/DifficultyCheck.lua", "UI/Options.lua" }) do files[#files + 1] = f end
    local ns = load_addon(files)
    ns.addon:OnInitialize()
    ns.Game.IsOwned = function(id) return id == 7 end
    ns.Game.MountInfo = function(id) return ({ [1] = "Invincible", [7] = "Owned one" })[id] end
    ns.Game.DifficultyName = function(d) return ({ [3] = "10 Player", [4] = "25 Player", [5] = "10 Player (Heroic)",
      [6] = "25 Player (Heroic)" })[d] end
    ns.Lockouts.SpecFor = function(id)
      return ({ [1] = { instance = 631, difficulties = { 6 } }, [7] = { instance = 631, difficulties = { 6 } } })[id]
    end
    local shown, said = {}, {}
    ns.Game.ScreenWarning = function(text) shown[#shown + 1] = text return true end
    ns.addon.Print = function(_, msg) said[#said + 1] = msg end
    local pop = CreateFrame("Frame", nil, UIParent)
    pop.rows = { { id = 1 }, { id = 7 } }
    ns.UI.PopoutWindows = { ["weekly|all"] = pop }
    return ns, shown, said, pop
  end

  it("warns once on entering on the wrong difficulty; owned mounts and closed pop-outs don't count", function()
    local ns, shown, said, pop = loadUI()
    ns.Game.CurrentInstance = function() return 631, 4 end
    ns.UI.CheckDifficulty()
    eq(shown, { "Wrong difficulty for Invincible: you are on 25 Player, it drops on 25 Player (Heroic)." })
    eq(said, shown, "and in chat")
    ns.UI.CheckDifficulty()
    eq(#shown, 1, "once per instance and difficulty")
    ns.Game.CurrentInstance = function() return 631, 6 end
    ns.UI.CheckDifficulty()
    eq(#shown, 1, "the right difficulty: quiet")
    ns.Game.CurrentInstance = function() return nil end
    ns.UI.CheckDifficulty()
    pop:Hide()
    ns.Game.CurrentInstance = function() return 631, 4 end
    ns.UI.CheckDifficulty()
    eq(#shown, 1, "no open pop-out: nothing")
  end)

  it("can be switched off", function()
    local ns, shown = loadUI()
    ns.Options.Set("difficultyWarning", false)
    eq(ns.db.global.settings.difficultyWarnOff, true)
    ns.Game.CurrentInstance = function() return 631, 4 end
    ns.UI.CheckDifficulty()
    eq(#shown, 0)
    ns.Options.Set("difficultyWarning", true)
    ns.UI.CheckDifficulty()
    eq(#shown, 1)
  end)
end)
