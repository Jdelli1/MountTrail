local ADDON, ns = ...

-- Maps achievement mounts (Achievements.IsAchievementMount) to the
-- achievement that rewards them, lazily: nothing is read until the first
-- Lookup / Ensure (hovering an achievement mount, opening the Achievements
-- tab). Then, from the next frame on, every achievement of every category
-- (GetCategoryList -> GetCategoryNumAchievements(cat, true) ->
-- GetAchievementInfo(cat, i), rewardText = 11th return) is read, at most
-- PER_FRAME per frame; those with a reward text or a title some mount's
-- source text names are fed to Achievements.NewMatcher (item name in the
-- reward text, else the source text's "Achievement:" title, else mount
-- name in the reward text), at most MATCH_PER_FRAME per frame (each is
-- checked against every achievement mount). Nothing is read in combat: the
-- scan waits, checking once a second. Only achievement mounts the player's
-- faction can earn are mapped (the client lists only that faction's
-- achievements), and the result is saved per faction:
-- ns.db.global.achievementMap[<"Alliance"|"Horde"|"Neutral">] = { build =
-- "<toc>:<build>:<MATCHER_VERSION>", ids = { [mountID] = achievementID or
-- false } }, reused while the key is the same and it covers every such
-- mount; otherwise it is rebuilt, at most once per session.
--
-- Scan.api holds every client call (specs replace it).

local Achievements = ns.Achievements

local Scan = { state = "idle" } -- "idle" | "running" | "done"
ns.AchievementScan = Scan

Scan.PER_FRAME = 200
Scan.MATCH_PER_FRAME = 25
Scan.COMBAT_RETRY = 1 -- seconds
-- Bumped when matching changes, so saved maps from an older matcher are
-- rebuilt.
Scan.MATCHER_VERSION = "v2"

Scan.api = {
  CategoryList = function()
    return (GetCategoryList and GetCategoryList()) or {}
  end,
  NumAchievements = function(categoryID)
    return (GetCategoryNumAchievements and GetCategoryNumAchievements(categoryID, true)) or 0
  end,
  -- -> id, name, rewardText
  AchievementInfo = function(categoryID, index)
    if not GetAchievementInfo then return nil end
    local id, name, _, _, _, _, _, _, _, _, rewardText = GetAchievementInfo(categoryID, index)
    return id, name, rewardText
  end,
  ItemName = function(itemID)
    local item = C_Item
    return item and item.GetItemNameByID and item.GetItemNameByID(itemID) or nil
  end,
  RequestItem = function(itemID)
    local item = C_Item
    if item and item.RequestLoadItemDataByID then item.RequestLoadItemDataByID(itemID) end
  end,
  InCombat = function()
    return InCombatLockdown ~= nil and InCombatLockdown() == true
  end,
  Faction = function()
    return ns.Game.Faction()
  end,
  Build = function()
    if not GetBuildInfo then return "?" end
    local _, build, _, toc = GetBuildInfo()
    return tostring(toc) .. ":" .. tostring(build)
  end,
  After = function(seconds, fn)
    if C_Timer and C_Timer.After then C_Timer.After(seconds, fn) end
  end,
  SourceText = function(mountID)
    return ns.Game.MountSourceText(mountID)
  end,
  MountName = function(mountID)
    return (ns.Game.MountInfo(mountID))
  end,
  -- The client's own word for "Achievement" (Mount Journal source label).
  SourceLabels = function()
    return { BATTLE_PET_SOURCE_6 }
  end,
}

local listeners = {}
local sessionIds = {} -- faction -> results when there is no ns.db (never in game)

-- The cache key: client build plus matcher version.
local function cacheKey()
  return tostring(Scan.api.Build()) .. ":" .. Scan.MATCHER_VERSION
end

-- IDs of the achievement mounts `faction` can earn, sorted.
local function achievementMounts(faction)
  local out = {}
  for id, m in pairs((ns.Data and ns.Data.Mounts) or {}) do
    if Achievements.IsAchievementMountFor(m, faction) then out[#out + 1] = id end
  end
  table.sort(out)
  return out
end

local function store()
  return ns.db and ns.db.global
end

-- The saved map of `faction` when its key is current, else nil.
local function cachedIds(faction)
  if sessionIds[faction] then return sessionIds[faction] end
  local db = store()
  local map = db and db.achievementMap
  local entry = type(map) == "table" and map[faction] or nil
  if type(entry) == "table" and type(entry.ids) == "table" and entry.build == cacheKey() then
    return entry.ids
  end
  return nil
end

local function covers(ids, faction)
  for _, id in ipairs(achievementMounts(faction)) do
    if ids[id] == nil then return false end
  end
  return true
end

local function finish(ids, faction)
  Scan.state = "done"
  if ids then
    local db = store()
    if db then
      local map = type(db.achievementMap) == "table" and db.achievementMap or {}
      map.build, map.ids = nil, nil -- the first matcher's single map
      map[faction] = { build = cacheKey(), ids = ids }
      db.achievementMap = map
    else
      sessionIds[faction] = ids
    end
  end
  for _, fn in ipairs(listeners) do pcall(fn) end
end

-- Matcher input for every achievement mount of `faction`: item and mount
-- names (read now, so item names that arrived during the scan count) and
-- the source text title.
local function candidates(faction)
  local api, data = Scan.api, (ns.Data and ns.Data.Mounts) or {}
  local labels = api.SourceLabels() or {}
  local out = {}
  for _, id in ipairs(achievementMounts(faction)) do
    local m = data[id]
    local items, names = {}, {}
    items[#items + 1] = m.item and api.ItemName(m.item) or nil
    names[#names + 1] = api.MountName(id)
    names[#names + 1] = m.name
    out[#out + 1] = {
      id = id, items = items, names = names,
      title = Achievements.SourceTitle(api.SourceText(id), labels),
    }
  end
  return out
end

-- Achievement titles named by `faction`'s achievement mounts' source texts
-- (a set).
local function sourceTitles(faction)
  local api, titles = Scan.api, {}
  local labels = api.SourceLabels() or {}
  for _, id in ipairs(achievementMounts(faction)) do
    local title = Achievements.SourceTitle(api.SourceText(id), labels)
    if title then titles[title] = true end
  end
  return titles
end

-- One frame of work: read up to PER_FRAME achievements, keeping those the
-- matcher can use; then (all read) feed up to MATCH_PER_FRAME of them to
-- the matcher. -> true when finished.
local function step(job)
  local api, budget = Scan.api, Scan.PER_FRAME
  if not job.cats then
    job.cats = api.CategoryList() or {}
    job.ci, job.ai, job.read, job.titles = 1, 1, {}, sourceTitles(job.faction)
  end
  while budget > 0 and job.ci <= #job.cats do
    local cat = job.cats[job.ci]
    job.num = job.num or tonumber(api.NumAchievements(cat)) or 0
    if job.ai > job.num then
      job.ci, job.ai, job.num = job.ci + 1, 1, nil
    else
      local id, name, reward = api.AchievementInfo(cat, job.ai)
      if id and ((type(reward) == "string" and reward ~= "") or (name and job.titles[name])) then
        job.read[#job.read + 1] = { id, name, reward }
      end
      job.ai = job.ai + 1
      budget = budget - 1
    end
  end
  if job.ci <= #job.cats then return false end
  if not job.matcher then
    job.matcher, job.fed = Achievements.NewMatcher(candidates(job.faction)), 0
    return #job.read == 0 -- match from the next frame on
  end
  budget = Scan.MATCH_PER_FRAME
  while budget > 0 and job.fed < #job.read do
    job.fed = job.fed + 1
    local a = job.read[job.fed]
    job.matcher:Feed(a[1], a[2], a[3])
    budget = budget - 1
  end
  return job.fed >= #job.read
end

local function schedule(job)
  local function tick()
    if Scan.api.InCombat() then
      Scan.api.After(Scan.COMBAT_RETRY, tick)
      return
    end
    local good, doneOrErr = pcall(step, job)
    if not good then
      if ns.Game and ns.Game.ReportError then ns.Game.ReportError(doneOrErr) end
      finish(nil, job.faction)
    elseif doneOrErr then
      finish(job.matcher:Result(), job.faction)
    else
      Scan.api.After(0, tick)
    end
  end
  Scan.api.After(0, tick)
end

-- Starts the scan unless it ran this session or the saved map is current.
-- -> Scan.state.
function Scan.Ensure()
  if Scan.state ~= "idle" then return Scan.state end
  local faction = Scan.api.Faction()
  local ids = cachedIds(faction)
  if ids and covers(ids, faction) then
    Scan.state = "done"
    return Scan.state
  end
  Scan.state = "running"
  -- Item names load asynchronously: ask now, read when matching.
  local data = (ns.Data and ns.Data.Mounts) or {}
  for _, id in ipairs(achievementMounts(faction)) do
    local item = data[id].item
    if item and not Scan.api.ItemName(item) then Scan.api.RequestItem(item) end
  end
  schedule({ faction = faction })
  return Scan.state
end

-- -> achievementID or nil, and "ready" (known), "pending" (scan running or
-- just started) or "none" (not an achievement mount of the player's
-- faction, or no match). Starts the scan for achievement mounts not in the
-- faction's saved map.
function Scan.Lookup(mountID)
  local m = mountID and ns.Data and ns.Data.Mounts and ns.Data.Mounts[mountID]
  local faction = Scan.api.Faction()
  if not Achievements.IsAchievementMountFor(m, faction) then return nil, "none" end
  local ids = cachedIds(faction)
  if ids and ids[mountID] ~= nil then
    if ids[mountID] then return ids[mountID], "ready" end
    return nil, "none"
  end
  if Scan.Ensure() == "running" then return nil, "pending" end
  return nil, "none"
end

-- fn() runs when a scan finishes (e.g. to repaint an open tooltip).
function Scan.OnDone(fn)
  listeners[#listeners + 1] = fn
end
