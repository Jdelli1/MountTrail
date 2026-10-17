-- Logic/Achievements.lua: pure helpers for the achievement hover and
-- Shift+right-click (F2): which mounts are achievement mounts, the
-- "Achievement: <name>" part of a Mount Journal source text, the
-- reward-text matcher and the tooltip criteria lines.

local function loadLogic()
  return load_addon({ "Core/Locale.lua", "Logic/Achievements.lua" })
end

describe("achievements logic", function()
  it("is listed in the toc after Logic/Attempts.lua", function()
    local files = toc_lua_files()
    local at, ach
    for i, f in ipairs(files) do
      if f == "Logic/Attempts.lua" then at = i end
      if f == "Logic/Achievements.lua" then ach = i end
    end
    ok(at and ach, "both in the toc")
    eq(ach, at + 1)
  end)

  describe("IsAchievementMount", function()
    it("takes misc mounts in the achievement section only", function()
      local A = loadLogic().Achievements
      eq(A.IsAchievementMount({ tab = "misc", section = "achievement" }), true)
      eq(A.IsAchievementMount({ tab = "misc", section = "shop" }), false)
      eq(A.IsAchievementMount({ tab = "journal", section = "achievement" }), false)
      eq(A.IsAchievementMount(nil), false)
    end)
  end)

  describe("SourceTitle", function()
    local A = loadLogic().Achievements
    it("reads the name after the Achievement label, colour codes stripped", function()
      eq(A.SourceTitle("|cFFFFD200Achievement: |rGlory of the Raider"), "Glory of the Raider")
    end)
    it("stops at the next |n line", function()
      eq(A.SourceTitle("|cFFFFD200Achievement: |rGlory of the Hero|n|cFFFFD200Category: |rDungeons & Raids"),
        "Glory of the Hero")
    end)
    it("finds the label on a later line and trims spaces", function()
      eq(A.SourceTitle("|cFFFFD200Drop: |rSomething|n|cFFFFD200Achievement:|r  Mountacular  "), "Mountacular")
    end)
    it("takes extra (localized) labels", function()
      eq(A.SourceTitle("|cFFFFD200Erfolg: |rRuhm des Schlachtzüglers", { "Erfolg" }), "Ruhm des Schlachtzüglers")
    end)
    it("returns nil without a label or text", function()
      eq(A.SourceTitle("|cFFFFD200Vendor: |rSomeone"), nil)
      eq(A.SourceTitle(nil), nil)
      eq(A.SourceTitle("|cFFFFD200Achievement: |r"), nil)
    end)
  end)

  describe("ContainsName", function()
    local A = loadLogic().Achievements
    it("finds a whole name, plain (no patterns)", function()
      eq(A.ContainsName("Reward: Reins of the Red Proto-Drake", "Reins of the Red Proto-Drake"), true)
      eq(A.ContainsName("Reward: Reins of the Red Proto-Drake", "Red Proto-Drake"), true)
      eq(A.ContainsName("Reward: 100% (more)", "100% (more)"), true)
    end)
    it("does not match inside a longer word", function()
      eq(A.ContainsName("Reward: Red Drakeling", "Red Drake"), false)
      eq(A.ContainsName("Reward: Darkred Drake", "red Drake"), false)
      eq(A.ContainsName("Reward: Red Drakeling, Red Drake", "Red Drake"), true, "a later whole match counts")
    end)
    it("is false for empty or missing input", function()
      eq(A.ContainsName(nil, "x"), false)
      eq(A.ContainsName("x", nil), false)
      eq(A.ContainsName("x", ""), false)
    end)
  end)

  describe("Matcher", function()
    local A = loadLogic().Achievements
    local MOUNTS = {
      { id = 262, items = { "Reins of the Red Proto-Drake" }, names = { "Red Proto-Drake" }, title = "Glory of the Hero" },
      { id = 263, items = {}, names = { "Black Proto-Drake" } },
      { id = 400, items = {}, names = {}, title = "Mountacular" },
      { id = 500, items = { "Reins of Nothing" }, names = { "Nothing" } },
    }

    it("maps by item name in the reward text", function()
      local m = A.NewMatcher(MOUNTS)
      m:Feed(10, "Something", "Reward: Reins of the Red Proto-Drake")
      eq(m:Result()[262], 10)
    end)

    it("falls back to the mount name, then the source title; unmatched mounts are false", function()
      local m = A.NewMatcher(MOUNTS)
      m:Feed(11, "Glory of the Raider", "Reward: Reins of the Black Proto-Drake")
      m:Feed(12, "Mountacular", "")
      eq(m:Result(), { [262] = false, [263] = 11, [400] = 12, [500] = false })
    end)

    it("prefers item name over source title over mount name, whatever the feed order", function()
      local m = A.NewMatcher(MOUNTS)
      m:Feed(1, "Glory of the Hero", nil)                          -- title
      m:Feed(2, "Other", "Reward: Red Proto-Drake")                 -- mount name
      m:Feed(3, "Third", "Reward: Reins of the Red Proto-Drake")    -- item name
      m:Feed(4, "Fourth", "Reward: Reins of the Red Proto-Drake")   -- later item match loses
      eq(m:Result()[262], 3)
      local m2 = A.NewMatcher(MOUNTS)
      m2:Feed(2, "Other", "Reward: Red Proto-Drake")
      m2:Feed(1, "Glory of the Hero", nil)
      eq(m2:Result()[262], 1, "an exact source-title match beats a mount-name match elsewhere")
      local m3 = A.NewMatcher(MOUNTS)
      m3:Feed(1, "Glory of the Hero", nil)
      m3:Feed(2, "Other", "Reward: Red Proto-Drake")
      eq(m3:Result()[262], 1, "either order")
    end)

    describe("a name inside a longer candidate name (Crimson vs Heavenly Crimson Cloud Serpent)", function()
      local SERPENTS = {
        { id = 472, items = {}, names = { "Crimson Cloud Serpent" } },
        { id = 474, items = {}, names = { "Heavenly Crimson Cloud Serpent" } },
      }
      it("the longer name takes the reward, the shorter one is skipped", function()
        local m = A.NewMatcher(SERPENTS)
        m:Feed(100, "Heavenly", "Reward: Heavenly Crimson Cloud Serpent")
        eq(m:Result(), { [472] = false, [474] = 100 })
        m:Feed(101, "Crimson", "Reward: Crimson Cloud Serpent")
        eq(m:Result(), { [472] = 101, [474] = 100 })
      end)
      it("in either feed order", function()
        local m = A.NewMatcher(SERPENTS)
        m:Feed(101, "Crimson", "Reward: Crimson Cloud Serpent")
        m:Feed(100, "Heavenly", "Reward: Heavenly Crimson Cloud Serpent")
        eq(m:Result(), { [472] = 101, [474] = 100 })
      end)
      it("also when the longer mount already matched by item name", function()
        local m = A.NewMatcher({
          { id = 472, items = {}, names = { "Crimson Cloud Serpent" } },
          { id = 474, items = { "Reins of the Heavenly Crimson Cloud Serpent" }, names = { "Heavenly Crimson Cloud Serpent" } },
        })
        m:Feed(100, "Heavenly", "Reward: Reins of the Heavenly Crimson Cloud Serpent")
        eq(m:Result(), { [472] = false, [474] = 100 })
      end)
      it("does not suppress two mounts with the same name", function()
        local m = A.NewMatcher({
          { id = 450, items = {}, names = { "Pandaren Kite" } },
          { id = 516, items = {}, names = { "Pandaren Kite" } },
        })
        m:Feed(20, "Pandaren Ambassador", "Reward: Pandaren Kite String")
        eq(m:Result(), { [450] = 20, [516] = 20 })
      end)
    end)

    it("ignores missing ids and blank names", function()
      local m = A.NewMatcher({ { id = 1, items = { "" }, names = { nil }, title = "" } })
      m:Feed(nil, "x", "Reward: x")
      m:Feed(5, "", "")
      eq(m:Result(), { [1] = false })
    end)

    it("does not match a name that is only part of a longer word", function()
      local m = A.NewMatcher({ { id = 1, items = {}, names = { "Red Drake" } } })
      m:Feed(7, "a", "Reward: Red Drakeling")
      eq(m:Result()[1], false)
    end)
  end)

  describe("TooltipLines", function()
    local A = loadLogic().Achievements
    local GOLD, GREEN, GREY, WHITE = { 1, 0.82, 0 }, { 0.25, 1, 0.25 }, { 0.6, 0.6, 0.6 }, { 1, 1, 1 }
    local function texts(lines)
      local out = {}
      for i, l in ipairs(lines) do out[i] = l.text end
      return out
    end
    local function color(l) return { l.r, l.g, l.b } end

    it("shows the name, wrapped description and criteria coloured by state", function()
      local lines = A.TooltipLines({
        name = "Glory of the Hero", description = "Complete the heroic dungeon feats.", completed = false,
        numCriteria = 3,
        criteria = {
          { text = "Make Quick Werk of Him", completed = true, quantity = 1, required = 1 },
          { text = "Kill 50 trash", completed = false, quantity = 12, required = 50 },
          { text = "Done counter", completed = true, quantity = 50, required = 50 },
        },
      })
      eq(texts(lines), {
        "Achievement: Glory of the Hero",
        "Complete the heroic dungeon feats.",
        "  Make Quick Werk of Him",
        "  Kill 50 trash (12/50)",
        "  Done counter",
      })
      eq(color(lines[1]), GOLD)
      eq(color(lines[2]), WHITE)
      eq(lines[2].wrap, true)
      eq(color(lines[3]), GREEN)
      eq(color(lines[4]), GREY)
      eq(color(lines[5]), GREEN)
    end)

    it("colours the name green with (completed) when earned", function()
      local lines = A.TooltipLines({ name = "Mountacular", completed = true, numCriteria = 0, criteria = {} })
      eq(texts(lines), { "Achievement: Mountacular (completed)" })
      eq(color(lines[1]), GREEN)
    end)

    it("shows at most 8 criteria, then +N more (counting criteria not fetched)", function()
      local criteria = {}
      for i = 1, 10 do criteria[i] = { text = "C" .. i, completed = i % 2 == 0, quantity = 0, required = 1 } end
      local lines = A.TooltipLines({ name = "Big", description = "", numCriteria = 12, criteria = criteria })
      eq(#lines, 1 + 8 + 1, "name, 8 criteria, more line (empty description left out)")
      eq(lines[9].text, "  C8")
      eq(lines[10].text, "+4 more")
      eq(color(lines[10]), GREY)
    end)

    it("takes a custom max", function()
      local criteria = {}
      for i = 1, 3 do criteria[i] = { text = "C" .. i, completed = false } end
      eq(texts(A.TooltipLines({ name = "X", numCriteria = 3, criteria = criteria }, 2)),
        { "Achievement: X", "  C1", "  C2", "+1 more" })
    end)

    it("shows a nameless counted criterion as Progress; nameless single steps count in +N more", function()
      local lines = A.TooltipLines({ name = "Collect", numCriteria = 2, criteria = {
        { text = "", completed = false, quantity = 120, required = 300 },
        { text = "", completed = false, quantity = 0, required = 1 },
      } })
      eq(texts(lines), { "Achievement: Collect", "  Progress (120/300)", "+1 more" })
    end)

    it("shows quantityString for progress-bar criteria (money, big counters)", function()
      local lines = A.TooltipLines({ name = "Rich", numCriteria = 3, criteria = {
        { text = "Loot gold", completed = false, quantity = 1200, required = 100000,
          progressBar = true, quantityString = "12|TInterface\\MoneyFrame\\UI-GoldIcon:0|t / 1000|TInterface\\MoneyFrame\\UI-GoldIcon:0|t" },
        { text = "", completed = true, quantity = 300, required = 300, progressBar = true, quantityString = "300 / 300" },
        { text = "Bar without string", completed = false, quantity = 2, required = 5, progressBar = true },
      } })
      eq(texts(lines), {
        "Achievement: Rich",
        "  Loot gold: 12|TInterface\\MoneyFrame\\UI-GoldIcon:0|t / 1000|TInterface\\MoneyFrame\\UI-GoldIcon:0|t",
        "  Progress: 300 / 300",
        "  Bar without string (2/5)",
      })
      eq(color(lines[3]), GREEN)
    end)

    it("returns {} without info", function()
      eq(A.TooltipLines(nil), {})
      eq(A.TooltipLines({}), {})
    end)
  end)
end)
