-- Browse by source (Logic/Browse.lua): categories, where each mount goes,
-- and a page's mounts grouped by expansion.

local function load()
  local ns = load_addon({ "Core/Locale.lua", "Data/Mounts.lua", "Data/Holidays.lua", "Logic/Journal.lua",
    "Logic/Browse.lua" })
  return ns
end

describe("Browse", function()
  it("every mount goes to exactly one place: a browse category or Holidays / Achievements / Timewalking", function()
    local ns = load()
    local B, J = ns.Browse, ns.Journal
    local counts, viewed = {}, 0
    for id, m in pairs(ns.Data.Mounts) do
      local c = B.CategoryOf(id, m, nil)
      local view = J.ViewOf(m)
      if c then
        ok(B.Get(c) and not B.Get(c).view, "mount " .. id .. " in a browse page: " .. tostring(c))
        counts[c] = (counts[c] or 0) + 1
      else
        ok(view == "holidays" or view == "achievements" or view == "timewalking", "mount " .. id .. ": " .. tostring(view))
        viewed = viewed + 1
      end
    end
    for _, key in ipairs({ "drops", "vendors", "quests", "professions", "shop", "pvp", "keystone", "other" }) do
      ok((counts[key] or 0) > 0, key .. " has mounts")
    end
    ok(viewed > 0)
  end)

  it("the categories keep their order; Holidays, Achievements, Timewalking have their own views", function()
    local B = load().Browse
    local keys = {}
    for i, c in ipairs(B.CATEGORIES) do keys[i] = c.key end
    eq(keys, { "drops", "vendors", "quests", "achievements", "professions", "shop", "pvp", "keystone",
      "holidays", "timewalking", "other" })
    eq({ B.Get("holidays").view, B.Get("achievements").view, B.Get("timewalking").view },
      { "holidays", "achievements", "timewalking" })
  end)

  it("Select: the category's mounts the gate keeps, by expansion order then name; search narrows", function()
    local ns = load_addon({ "Core/Locale.lua", "Logic/Journal.lua", "Logic/Browse.lua" })
    local mounts = {
      [1] = { name = "Zed", tab = "journal", section = "raid", exp = "Legion" },
      [2] = { name = "Amber", tab = "journal", section = "dungeon", exp = "Legion" },
      [3] = { name = "Old", tab = "journal", section = "world", exp = "Classic" },
      [4] = { name = "Shop", tab = "misc", section = "shop", exp = "Legion" },
      [5] = { name = "Horde Only", tab = "journal", section = "raid", exp = "Legion", faction = "Horde" },
    }
    local q = { isOwned = function() return false end, exists = function() return true end, faction = "Alliance" }
    local rows = ns.Browse.Select("drops", mounts, q, { "Classic", "Legion" })
    local ids, secs = {}, {}
    for i, r in ipairs(rows) do ids[i], secs[i] = r.id, r.section end
    eq(ids, { 3, 2, 1 }, "other faction left out; Classic first, then by name")
    eq(secs, { "Classic", "Legion", "Legion" }, "grouped by expansion")
    q.search = "am"
    eq(#ns.Browse.Select("drops", mounts, q, { "Classic", "Legion" }), 1)
  end)
end)
