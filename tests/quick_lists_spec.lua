-- Logic/QuickLists.lua: ready-made lists worked out from the data.

describe("QuickLists", function()
  it("Mythic Mounts: dungeon mounts whose lockout includes Mythic (23), real data", function()
    local ns = load_addon(toc_lua_files())
    local ids = ns.QuickLists.Mounts("mythic")
    local names = {}
    for _, id in ipairs(ids) do names[#names + 1] = ns.Data.Mounts[id].name end
    local want = { "Midnight", "Smoldering Ember Wyrm", "Sharkbait", "Tomb Stalker", "Underrot Crawg",
      "Mechagon Peacekeeper", "Aerial Unit R-21/X", "Marrowfang", "Cartel Master's Gearglider", "Wick",
      "Lucent Hawkstrider", "Spectral Hawkstrider", "The Writhing Brood" }
    local have = {}
    for _, n in ipairs(names) do have[n] = true end
    for _, n in ipairs(want) do ok(have[n], n .. " on the list") end
    eq(#ids, #want, table.concat(names, ", "))
    ok(not have["Drake of the North Wind"], "Normal / Heroic drops are not")
    ok(not have["Invincible"], "raid Mythic (16) is not")
  end)

  it("sorted by expansion, then name; unknown list -> {}", function()
    local ns = load_addon({ "Core/Locale.lua", "Logic/QuickLists.lua" })
    local data = {
      Expansions = { "Legion", "Battle for Azeroth" },
      Mounts = { [1] = { name = "Zeta", exp = "Battle for Azeroth" }, [2] = { name = "Alpha", exp = "Battle for Azeroth" },
        [3] = { name = "Old", exp = "Legion" }, [4] = { name = "Heroic", exp = "Legion" } },
      Lockouts = { [1] = { instance = 1, difficulties = { 23 } }, [2] = { instance = 2, difficulties = { { 2, 23 } } },
        [3] = { instance = 3, difficulties = 23 }, [4] = { instance = 4, difficulties = { 2 } } },
    }
    eq(ns.QuickLists.Mounts("mythic", data), { 3, 2, 1 })
    eq(ns.QuickLists.Mounts("nope", data), {})
    eq(ns.QuickLists.Get("mythic").name, "Mythic Mounts")
  end)
end)
