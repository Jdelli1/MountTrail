-- Logic/Search.lua: front-page search over every mount (pure).

describe("search", function()
  local function load()
    return load_addon({ "Core/Locale.lua", "Logic/Search.lua" }).Search
  end

  local MOUNTS = {
    [1] = { name = "Invincible" },
    [2] = { name = "Volcanic Stone Drake" },
    [3] = { name = "Drake of the North Wind" },
    [4] = { name = "Ashes of Al'ar" },
    [5] = { name = "Plagued Proto-Drake" },
    [6] = { name = "Swift Zulian Tiger" },
  }
  local FIELDS = {
    [1] = { boss = { "The Lich King" }, instance = { "Icecrown Citadel" }, expansion = { "Wrath of the Lich King" } },
    [2] = { achievement = { "Glory of the Cataclysm Raider" }, expansion = { "Cataclysm" } },
    [3] = { boss = { "Altairus" }, instance = { "The Vortex Pinnacle" }, expansion = { "Cataclysm" } },
    [4] = { boss = { "Kael'thas Sunstrider" }, instance = { "Tempest Keep" }, expansion = { "The Burning Crusade" } },
    [5] = { achievement = { "Glory of the Raider (10 player)" }, expansion = { "Wrath of the Lich King" } },
    [6] = { boss = { "High Priest Thekal" }, instance = { "Zul'Gurub" }, zone = { "Northern Stranglethorn" } },
  }
  local function run(S, text, gate)
    return S.Select(MOUNTS, {
      search = text,
      gate = gate,
      fields = function(id, m)
        local f = { name = m.name }
        for k, v in pairs(FIELDS[id]) do f[k] = v end
        return f
      end,
    })
  end
  local function ids(hits)
    local out = {}
    for i, h in ipairs(hits) do out[i] = h.id end
    return out
  end

  it("splits words, lower case, apostrophes dropped", function()
    local S = load()
    eq(S.Words("Ashes of Al'ar, Kael’thas!"), { "ashes", "of", "alar", "kaelthas" })
    eq(S.Words(nil), {})
  end)

  it("edit distance counts a neighbour swap as one edit and stops past max", function()
    local S = load()
    eq(S.Distance("glroy", "glory", 2), 1)
    eq(S.Distance("raidr", "raider", 2), 1)
    eq(S.Distance("flirty", "glory", 2), 3, "beyond max")
    eq(S.Distance("abc", "abcdefg", 1), 2, "length gap alone exceeds max")
  end)

  it("an empty or blank query finds nothing", function()
    local S = load()
    eq(run(S, ""), {})
    eq(run(S, "   "), {})
    eq(run(S, "t"), {}, "one letter is too short")
  end)

  it("matches mount names exactly, by prefix, inside a word and with typos", function()
    local S = load()
    eq(ids(run(S, "invincible")), { 1 })
    eq(ids(run(S, "invin")), { 1 })
    eq(ids(run(S, "invincable")), { 1 }, "one typo")
    eq(run(S, "invin")[1].section, "search_name")
  end)

  it("matches bosses, dungeons, zones and achievements, grouped by what matched", function()
    local S = load()
    local hits = run(S, "altairus")
    eq(ids(hits), { 3 })
    eq(hits[1].section, "search_boss")
    eq(run(S, "vortex pinnacle")[1].section, "search_instance")
    eq(run(S, "stranglethorn")[1].section, "search_zone")
    eq(run(S, "kaelthas")[1].id, 4, "apostrophes do not matter")
  end)

  it("abbreviations: icc, cata, tk, bc", function()
    local S = load()
    eq(ids(run(S, "icc")), { 1 })
    eq(ids(run(S, "tk")), { 4 })
    eq(ids(run(S, "bc")), { 4 })
    local cata = ids(run(S, "cata"))
    table.sort(cata)
    eq(cata, { 2, 3 })
  end)

  it("several words: any order, filler words ignored, the best match first", function()
    local S = load()
    local hits = run(S, "glory of the raider cata")
    eq(hits[1].id, 2)
    eq(hits[1].section, "search_achievement")
    eq(run(S, "cata raider glory")[1].id, 2, "word order does not matter")
  end)

  it("a badly mistyped word is carried by the others (two thirds must match)", function()
    local S = load()
    local hits = run(S, "flirty of the raider cata")
    eq(hits[1].id, 2, "raider + cata")
    for _, h in ipairs(hits) do
      ok(h.id ~= 3, "Drake of the North Wind matches cata only")
    end
    eq(S.Needed(1), 1)
    eq(S.Needed(2), 2)
    eq(S.Needed(3), 2)
    eq(S.Needed(4), 3)
  end)

  it("two words both have to match", function()
    local S = load()
    eq(ids(run(S, "drake altairus")), { 3 })
  end)

  it("a mount the gate excludes is left out", function()
    local S = load()
    eq(run(S, "invincible", function(id) if id ~= 1 then return false end end), {})
  end)

  it("reuses prepared fields from the cache", function()
    local S = load()
    local calls = 0
    local cache = {}
    local q = { search = "drake", cache = cache, fields = function(_, m) calls = calls + 1; return { name = m.name } end }
    S.Select(MOUNTS, q)
    local first = calls
    q.search = "tiger"
    S.Select(MOUNTS, q)
    eq(calls, first, "no second build")
  end)
end)
