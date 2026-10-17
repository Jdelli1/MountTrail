-- Integrations/AchievementScan.lua (lazy mount -> achievement scan, spread
-- over frames, never in combat, cached per client build) with an injected
-- API, plus the Game adapter's achievement calls (AchievementInfo,
-- OpenAchievement) against stubbed globals.

local MOUNTS = {
  [262] = { name = "Red Proto-Drake", item = 44160, tab = "misc", section = "achievement" },
  [263] = { name = "Black Proto-Drake", item = 44164, tab = "misc", section = "achievement" },
  [400] = { name = "Titled Mount", tab = "misc", section = "achievement" },
  [401] = { name = "Lonely Mount", tab = "misc", section = "achievement" },
  [500] = { name = "Shop Mount", item = 1, tab = "misc", section = "shop" },
}

-- MOUNTS plus the two faction Pandaren Kites (Horde 450, Alliance 516).
local KITE_MOUNTS = {
  [450] = { name = "Pandaren Kite", item = 81559, tab = "misc", section = "achievement", faction = "Horde" },
  [516] = { name = "Pandaren Kite", item = 89785, tab = "misc", section = "achievement", faction = "Alliance" },
}
for id, m in pairs(MOUNTS) do KITE_MOUNTS[id] = m end

-- Cache key for the fake client's default build (matcher version v2).
local KEY = "120105:70448:v2"

-- A fake client: three categories, `filler` reward-less achievements in the
-- first, the rewarding ones in the second, and the player's faction's
-- Pandaren Ambassador (Horde 20, Alliance 21, none for Neutral) in the
-- third. Frames run by hand (runFrame).
local function fakeClient(opts)
  opts = opts or {}
  local c = {
    combat = false, build = opts.build or "120105:70448", queue = {}, calls = 0, catCalls = 0,
    faction = opts.faction or "Alliance",
    items = opts.items or { [44160] = "Reins of the Red Proto-Drake" }, requested = {},
    sources = opts.sources or { [400] = "|cFFFFD200Achievement: |rMountacular" },
  }
  local cats = { [1] = {}, [2] = {} }
  for i = 1, opts.filler or 5 do cats[1][i] = { id = 1000 + i, name = "Filler " .. i } end
  cats[2] = {
    { id = 10, name = "Glory of the Hero", reward = "Reward: Reins of the Red Proto-Drake" },
    { id = 11, name = "Glory of the Raider", reward = "Reward: Reins of the Black Proto-Drake" },
    { id = 12, name = "Mountacular" }, -- no reward text: kept for its title
  }
  local kites = {
    Horde = { { id = 20, name = "Pandaren Ambassador", reward = "Reward: Pandaren Kite String" } },
    Alliance = { { id = 21, name = "Pandaren Ambassador", reward = "Reward: Pandaren Kite String" } },
    Neutral = {},
  }
  local function category(cat)
    if cat == 3 then return kites[c.faction] end
    return cats[cat]
  end
  c.api = {
    CategoryList = function() c.catCalls = c.catCalls + 1; return { 1, 2, 3 } end,
    NumAchievements = function(cat) return #category(cat) end,
    AchievementInfo = function(cat, i)
      c.calls = c.calls + 1
      ok(not c.combat, "no achievement reads in combat")
      local a = category(cat)[i]
      return a.id, a.name, a.reward
    end,
    Faction = function() return c.faction end,
    ItemName = function(item) return c.items[item] end,
    RequestItem = function(item) c.requested[#c.requested + 1] = item end,
    InCombat = function() return c.combat end,
    Build = function() return c.build end,
    After = function(seconds, fn) c.queue[#c.queue + 1] = { seconds = seconds, fn = fn } end,
    SourceText = function(id) return c.sources[id] end,
    MountName = function() return nil end,
    SourceLabels = function() return {} end,
  }
  -- Runs the oldest queued callback (one frame / timer); -> its delay or nil.
  function c:runFrame()
    local job = table.remove(self.queue, 1)
    if not job then return nil end
    self.calls = 0
    job.fn()
    return job.seconds
  end
  function c:runAll(limit)
    local frames = 0
    while #self.queue > 0 and frames < (limit or 1000) do
      self:runFrame()
      frames = frames + 1
    end
    return frames
  end
  return c
end

-- savedMap: an achievementMap from an earlier session (shared table).
local function loadScan(client, mounts, savedMap)
  local ns = load_addon(toc_lua_files())
  ns.addon:OnInitialize()
  ns.Data.Mounts = mounts or MOUNTS
  ns.AchievementScan.api = client.api
  if savedMap then ns.db.global.achievementMap = savedMap end
  return ns
end

describe("achievement scan", function()
  it("is listed in the toc after Integrations/Rarity.lua", function()
    local files = toc_lua_files()
    local rarity, scan
    for i, f in ipairs(files) do
      if f == "Integrations/Rarity.lua" then rarity = i end
      if f == "Integrations/AchievementScan.lua" then scan = i end
    end
    ok(rarity and scan, "both in the toc")
    eq(scan, rarity + 1)
  end)

  it("does nothing for mounts that are not achievement mounts", function()
    local client = fakeClient()
    local ns = loadScan(client)
    eq({ ns.AchievementScan.Lookup(500) }, { nil, "none" })
    eq({ ns.AchievementScan.Lookup(99999) }, { nil, "none" })
    eq(#client.queue, 0, "no scan started")
    eq(ns.AchievementScan.state, "idle")
  end)

  it("scans lazily on first lookup, then maps item, mount-name and title matches", function()
    local client = fakeClient()
    local ns = loadScan(client)
    local Scan = ns.AchievementScan
    eq(client.catCalls, 0, "nothing read at load")
    eq({ Scan.Lookup(262) }, { nil, "pending" })
    eq(Scan.state, "running")
    eq(client.catCalls, 0, "work starts on the next frame, not inside the hover")
    client:runAll()
    eq(Scan.state, "done")
    eq({ Scan.Lookup(262) }, { 10, "ready" }, "item name in the reward text")
    eq({ Scan.Lookup(263) }, { 11, "ready" }, "mount name in the reward text")
    eq({ Scan.Lookup(400) }, { 12, "ready" }, "source-text title")
    eq({ Scan.Lookup(401) }, { nil, "none" }, "no match")
    eq(ns.db.global.achievementMap, { Alliance = {
      build = KEY,
      ids = { [262] = 10, [263] = 11, [400] = 12, [401] = false },
    } })
  end)

  it("reads at most PER_FRAME achievements per frame", function()
    local client = fakeClient({ filler = 450 })
    local ns = loadScan(client)
    eq(ns.AchievementScan.PER_FRAME, 200)
    ns.AchievementScan.Ensure()
    local frames = 0
    while #client.queue > 0 do
      client:runFrame()
      ok(client.calls <= 200, "frame read " .. client.calls)
      frames = frames + 1
    end
    ok(frames >= 3, "453 achievements take at least 3 frames, took " .. frames)
    eq(ns.AchievementScan.Lookup(262), 10)
  end)

  it("feeds the matcher at most MATCH_PER_FRAME achievements per frame, only usable ones", function()
    local client = fakeClient({ filler = 450 })
    local ns = loadScan(client)
    eq(ns.AchievementScan.MATCH_PER_FRAME, 25)
    ns.AchievementScan.MATCH_PER_FRAME = 2
    local fed, perFrame = {}, 0
    local real = ns.Achievements.NewMatcher
    ns.Achievements.NewMatcher = function(mounts)
      local m = real(mounts)
      local feed = m.Feed
      function m:Feed(id, ...) fed[#fed + 1] = id; perFrame = perFrame + 1; return feed(self, id, ...) end
      return m
    end
    ns.AchievementScan.Ensure()
    while #client.queue > 0 do
      perFrame = 0
      client:runFrame()
      ok(perFrame <= 2, "fed " .. perFrame)
    end
    eq(fed, { 10, 11, 12, 21 }, "reward-less filler is not fed; Mountacular is kept for its title")
    eq(ns.AchievementScan.Lookup(400), 12)
  end)

  it("Ensure is idempotent while running and after done", function()
    local client = fakeClient()
    local ns = loadScan(client)
    ns.AchievementScan.Ensure()
    ns.AchievementScan.Ensure()
    ns.AchievementScan.Lookup(262)
    eq(#client.queue, 1, "one frame chain")
    client:runAll()
    ns.AchievementScan.Ensure()
    eq(#client.queue, 0)
  end)

  it("never reads in combat: waits, polling once a second, and resumes after", function()
    local client = fakeClient({ filler = 450 })
    local ns = loadScan(client)
    client.combat = true
    ns.AchievementScan.Ensure()
    eq(client:runFrame(), 0)
    eq(client.catCalls, 0, "nothing read in combat")
    eq(client.queue[1].seconds, 1, "retries in a second")
    client:runFrame()
    eq(client.queue[1].seconds, 1)
    client.combat = false
    client:runFrame() -- first chunk
    ok(client.catCalls == 1, "started after combat")
    client.combat = true
    client:runFrame() -- combat mid-scan: pauses
    eq(client.queue[1].seconds, 1)
    client.combat = false
    client:runAll()
    eq(ns.AchievementScan.state, "done")
    eq(ns.AchievementScan.Lookup(262), 10)
  end)

  it("uses the cache for the same build without scanning", function()
    local client = fakeClient()
    local ns = loadScan(client)
    ns.db.global.achievementMap = { Alliance = { build = KEY,
      ids = { [262] = 77, [263] = false, [400] = 78, [401] = false } } }
    eq({ ns.AchievementScan.Lookup(262) }, { 77, "ready" })
    eq({ ns.AchievementScan.Lookup(263) }, { nil, "none" })
    eq(#client.queue, 0, "no scan")
  end)

  it("rescans when the client build changed", function()
    local client = fakeClient({ build = "120105:70500" })
    local ns = loadScan(client)
    ns.db.global.achievementMap = { Alliance = { build = KEY,
      ids = { [262] = 77, [263] = false, [400] = 78, [401] = false } } }
    eq({ ns.AchievementScan.Lookup(262) }, { nil, "pending" })
    client:runAll()
    eq(ns.db.global.achievementMap.Alliance.build, "120105:70500:v2")
    eq(ns.AchievementScan.Lookup(262), 10)
  end)

  it("rebuilds a map saved by the first matcher (no version, not per faction) and drops it", function()
    local client = fakeClient()
    local ns = loadScan(client)
    ns.db.global.achievementMap = { build = "120105:70448",
      ids = { [262] = 77, [263] = false, [400] = 78, [401] = false } }
    eq({ ns.AchievementScan.Lookup(262) }, { nil, "pending" })
    client:runAll()
    eq(ns.AchievementScan.Lookup(262), 10)
    eq(ns.db.global.achievementMap.build, nil, "old top-level keys removed")
    eq(ns.db.global.achievementMap.ids, nil)
    eq(ns.db.global.achievementMap.Alliance.build, KEY)
  end)

  it("keeps one map per faction: a Horde scan does not satisfy an Alliance alt", function()
    local saved = {}
    local horde = fakeClient({ faction = "Horde" })
    local ns = loadScan(horde, KITE_MOUNTS, saved)
    eq({ ns.AchievementScan.Lookup(450) }, { nil, "pending" })
    horde:runAll()
    eq({ ns.AchievementScan.Lookup(450) }, { 20, "ready" }, "Horde kite -> Horde achievement")
    eq({ ns.AchievementScan.Lookup(516) }, { nil, "none" }, "the Alliance kite is not this faction's")
    eq(#horde.queue, 0, "and starts no scan")
    eq(saved.Horde.ids[450], 20)
    eq(saved.Horde.ids[516], nil, "other-faction mounts are not mapped")

    local alliance = fakeClient({ faction = "Alliance" })
    ns = loadScan(alliance, KITE_MOUNTS, saved)
    eq({ ns.AchievementScan.Lookup(516) }, { nil, "pending" }, "the Horde map does not count")
    alliance:runAll()
    eq({ ns.AchievementScan.Lookup(516) }, { 21, "ready" }, "Alliance kite -> Alliance achievement")
    eq(saved.Alliance.ids[450], nil)
    eq(saved.Horde.ids[450], 20, "the Horde map is kept")
  end)

  it("gives Neutral (unchosen Pandaren) its own map without faction mounts", function()
    local saved = {}
    local client = fakeClient({ faction = "Neutral" })
    local ns = loadScan(client, KITE_MOUNTS, saved)
    eq({ ns.AchievementScan.Lookup(450) }, { nil, "none" })
    eq({ ns.AchievementScan.Lookup(262) }, { nil, "pending" })
    client:runAll()
    eq(ns.AchievementScan.Lookup(262), 10)
    ok(saved.Neutral and saved.Neutral.build == KEY, "Neutral entry")
    eq({ saved.Neutral.ids[450], saved.Neutral.ids[516] }, {})
    eq(saved.Alliance, nil)
  end)

  it("rescans once per session when the cache lacks an achievement mount (new data)", function()
    local client = fakeClient()
    local ns = loadScan(client)
    ns.db.global.achievementMap = { Alliance = { build = KEY, ids = { [262] = 77, [263] = false, [400] = 78 } } }
    eq({ ns.AchievementScan.Lookup(401) }, { nil, "pending" })
    client:runAll()
    eq(ns.AchievementScan.Lookup(262), 10, "fresh results")
    ns.AchievementScan.Ensure()
    eq(#client.queue, 0, "only once per session")
  end)

  it("asks the client for item names it does not have yet and reads them when matching", function()
    local client = fakeClient({ items = {}, filler = 450 })
    local ns = loadScan(client)
    ns.AchievementScan.Ensure()
    eq(client.requested, { 44160, 44164 })
    client:runFrame()
    client.items[44160] = "Reins of the Red Proto-Drake" -- arrived while scanning
    client:runAll()
    eq(ns.AchievementScan.Lookup(262), 10)
  end)

  it("calls OnDone listeners once, when the scan finishes", function()
    local client = fakeClient()
    local ns = loadScan(client)
    local n = 0
    ns.AchievementScan.OnDone(function() n = n + 1 end)
    ns.AchievementScan.Ensure()
    eq(n, 0)
    client:runAll()
    eq(n, 1)
    ns.AchievementScan.Ensure()
    eq(n, 1)
  end)

  it("a failing client call ends the scan (done, nothing cached) instead of erroring every frame", function()
    local client = fakeClient()
    local ns = loadScan(client)
    client.api.CategoryList = function() error("boom") end
    ns.AchievementScan.Ensure()
    client:runAll()
    eq(ns.AchievementScan.state, "done")
    eq(ns.db.global.achievementMap, {})
    eq({ ns.AchievementScan.Lookup(262) }, { nil, "none" })
  end)
end)

-- Game adapter ------------------------------------------------------------------

local GLOBALS = { "GetAchievementInfo", "GetAchievementNumCriteria", "GetAchievementCriteriaInfo",
  "ShowAchievementFrameForAchievement", "OpenAchievementFrameToAchievement", "AchievementFrame",
  "AchievementFrame_SelectAchievement", "AchievementFrame_ToggleAchievementFrame", "C_AddOns",
  "LoadAddOn", "ShowUIPanel", "InCombatLockdown" }

local harnessIt = it
local function git(name, fn)
  return harnessIt(name, function()
    local saved = {}
    for _, g in ipairs(GLOBALS) do saved[g] = _G[g] end
    local good, err = pcall(fn)
    for _, g in ipairs(GLOBALS) do _G[g] = saved[g] end
    if not good then error(err, 0) end
  end)
end

describe("game achievements", function()
  local function loadGame() return load_addon({ "Game/API.lua" }).Game end

  git("AchievementInfo reads name, description, state and criteria", function()
    GetAchievementInfo = function(id)
      eq(id, 10)
      return 10, "Glory", 10, true, 1, 2, 3, "Do things.", 0, 123, "Reward: X"
    end
    GetAchievementNumCriteria = function() return 2 end
    GetAchievementCriteriaInfo = function(id, i)
      if i == 1 then return "First", 0, true, 1, 1 end
      return "Second", 0, false, 3, 10
    end
    eq(loadGame().AchievementInfo(10), {
      id = 10, name = "Glory", description = "Do things.", completed = true, numCriteria = 2,
      criteria = {
        { text = "First", completed = true, quantity = 1, required = 1, progressBar = false },
        { text = "Second", completed = false, quantity = 3, required = 10, progressBar = false },
      },
    })
  end)

  git("AchievementInfo marks progress-bar criteria (flags) and keeps quantityString", function()
    GetAchievementInfo = function() return 7, "Rich", 0, false, nil, nil, nil, "Loot gold." end
    GetAchievementNumCriteria = function() return 2 end
    GetAchievementCriteriaInfo = function(_, i)
      if i == 1 then return "Loot gold", 0, false, 1200, 100000, nil, 1, 0, "12g / 1000g" end
      return "Plain", 0, false, 2, 5, nil, 0, 0, "2/5"
    end
    local info = loadGame().AchievementInfo(7)
    eq(info.criteria[1], { text = "Loot gold", completed = false, quantity = 1200, required = 100000,
      progressBar = true, quantityString = "12g / 1000g" })
    eq(info.criteria[2].progressBar, false)
    eq(info.criteria[2].quantityString, "2/5")
  end)

  git("AchievementInfo survives a failing GetAchievementNumCriteria", function()
    GetAchievementInfo = function() return 8, "X", 0, false, nil, nil, nil, "" end
    GetAchievementNumCriteria = function() error("boom") end
    local info = loadGame().AchievementInfo(8)
    eq(info.numCriteria, 0)
    eq(info.criteria, {})
  end)

  git("AchievementInfo reads at most 100 criteria and survives a failing criterion", function()
    GetAchievementInfo = function() return 5, "Many", 0, false, nil, nil, nil, "" end
    GetAchievementNumCriteria = function() return 150 end
    GetAchievementCriteriaInfo = function(_, i)
      if i == 2 then error("bad index") end
      return "C" .. i, 0, false, 0, 1
    end
    local info = loadGame().AchievementInfo(5)
    eq(info.numCriteria, 150)
    eq(#info.criteria, 99, "100 read, the failing one left out")
    eq(info.criteria[2].text, "C3")
  end)

  git("AchievementInfo is nil when unknown or the API is missing", function()
    GetAchievementInfo = nil
    eq(loadGame().AchievementInfo(10), nil)
    GetAchievementInfo = function() return nil end
    eq(loadGame().AchievementInfo(10), nil)
    eq(loadGame().AchievementInfo(nil), nil)
  end)

  git("AchievementName is GetAchievementInfo's name only, guarded", function()
    local criteriaRead = false
    GetAchievementInfo = function(id)
      if id == 10 then return 10, "Glory of the Raider", 25, false end
      if id == 11 then return 11, "" end
      if id == 12 then error("boom") end
    end
    GetAchievementNumCriteria = function() criteriaRead = true; return 3 end
    local G = loadGame()
    eq(G.AchievementName(10), "Glory of the Raider")
    eq(criteriaRead, false, "no criteria reads")
    eq(G.AchievementName(11), nil, "empty name")
    eq(G.AchievementName(12), nil, "error caught")
    eq(G.AchievementName(13), nil, "unknown")
    eq(G.AchievementName(nil), nil)
    GetAchievementInfo = nil
    eq(loadGame().AchievementName(10), nil, "no API")
  end)

  git("InCombat reads InCombatLockdown; false when missing", function()
    InCombatLockdown = function() return true end
    eq(loadGame().InCombat(), true)
    InCombatLockdown = function() return nil end
    eq(loadGame().InCombat(), false)
    InCombatLockdown = nil
    eq(loadGame().InCombat(), false)
  end)

  git("OpenAchievement prefers ShowAchievementFrameForAchievement", function()
    local got
    ShowAchievementFrameForAchievement = function(id) got = id end
    OpenAchievementFrameToAchievement = function() error("not this one") end
    eq(loadGame().OpenAchievement(10), true)
    eq(got, 10)
  end)

  git("OpenAchievement falls back to OpenAchievementFrameToAchievement", function()
    local got
    ShowAchievementFrameForAchievement = nil
    OpenAchievementFrameToAchievement = function(id) got = id end
    eq(loadGame().OpenAchievement(11), true)
    eq(got, 11)
  end)

  git("OpenAchievement loads the achievement UI on demand, shows it and selects", function()
    ShowAchievementFrameForAchievement, OpenAchievementFrameToAchievement = nil, nil
    local log = {}
    C_AddOns = { LoadAddOn = function(name)
      log[#log + 1] = "load " .. name
      AchievementFrame = { IsShown = function() return false end }
      AchievementFrame_ToggleAchievementFrame = function() log[#log + 1] = "toggle" end
      AchievementFrame_SelectAchievement = function(id) log[#log + 1] = "select " .. id end
    end }
    eq(loadGame().OpenAchievement(12), true)
    eq(log, { "load Blizzard_AchievementUI", "toggle", "select 12" })
  end)

  git("OpenAchievement is false (no error) when nothing can open it", function()
    ShowAchievementFrameForAchievement, OpenAchievementFrameToAchievement = nil, nil
    C_AddOns, LoadAddOn, AchievementFrame = nil, nil, nil
    eq(loadGame().OpenAchievement(12), false)
    ShowAchievementFrameForAchievement = function() error("blocked") end
    eq(loadGame().OpenAchievement(12), false)
    eq(loadGame().OpenAchievement(nil), false)
  end)
end)
