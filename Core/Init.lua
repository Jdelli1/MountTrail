local ADDON, ns = ...

ns.version = "0.1.0"

-- UI hook: re-renders the visible tab. A no-op until UI\Frame.lua (loaded after
-- this file) replaces it; always call it as ns.Refresh() so the replacement is
-- picked up.
ns.Refresh = function() end

local L = ns.L or setmetatable({}, { __index = function(_, key) return key end })

local addon = LibStub("AceAddon-3.0"):NewAddon(ADDON, "AceConsole-3.0", "AceEvent-3.0")
ns.addon = addon

local function copyTable(src)
  local out = {}
  for k, v in pairs(src) do out[k] = type(v) == "table" and copyTable(v) or v end
  return out
end

-- Attempt tracking ------------------------------------------------------------

-- Tracked mounts (every Data.Lockouts key plus every mount with a Rarity quest
-- flag) and the quest / LFG IDs their specs read. Built once, on first use.
local tracked

local function specFor(mountID)
  return ns.Lockouts.SpecFor(mountID)
end

local function tracking()
  if tracked then return tracked end
  local data = ns.Data or {}
  local mounts, quests, lfg = {}, {}, {}
  local seen, seenQuest, seenLfg = {}, {}, {}
  local function add(mountID)
    if not seen[mountID] then seen[mountID] = true; mounts[#mounts + 1] = mountID end
  end
  for mountID in pairs(data.Lockouts or {}) do add(mountID) end
  for mountID, mount in pairs(data.Mounts or {}) do
    if mount.quest then add(mountID) end
  end
  table.sort(mounts)
  for _, mountID in ipairs(mounts) do
    local spec = specFor(mountID)
    if spec and spec.quest and not seenQuest[spec.quest] then
      seenQuest[spec.quest] = true; quests[#quests + 1] = spec.quest
    end
    if spec and spec.lfg and not seenLfg[spec.lfg] then
      seenLfg[spec.lfg] = true; lfg[#lfg + 1] = spec.lfg
    end
  end
  tracked = { mounts = mounts, quests = quests, lfg = lfg }
  return tracked
end

-- Whether this session has received real data from the server. Until then the
-- APIs report "nothing killed / not done", which must not be mistaken for a
-- lockout that reset (and then count a false attempt when the data arrives).
local ready = { instances = false, lfg = false }

-- Current observation { snap=, quests={[id]=true}, lfg={[id]=true} }; only
-- true flags are stored to keep the saved variables small. The saved-instance
-- snapshot is re-read only when `freshInstances` (UPDATE_INSTANCE_INFO);
-- other events reuse prev.snap, so a saved list that is transiently
-- incomplete while they fire can neither drop a kill nor count it later.
local function observe(prev, freshInstances)
  local t = tracking()
  local snap
  if freshInstances or not (prev and prev.snap) then
    snap = ns.Lockouts.Snapshot(ns.Game.SavedRows())
  else
    snap = copyTable(prev.snap)
  end
  local curr = { snap = snap, quests = {}, lfg = {} }
  for _, questID in ipairs(t.quests) do
    if ns.Game.IsQuestDone(questID) then curr.quests[questID] = true end
  end
  if ready.lfg then
    for _, dungeonID in ipairs(t.lfg) do
      if ns.Game.IsLfgDone(dungeonID) then curr.lfg[dungeonID] = true end
    end
  elseif prev then
    curr.lfg = copyTable(prev.lfg or {}) -- keep the last known flags
  else
    -- Nothing known yet: assume done, so the first real reading can only
    -- move done -> open (no count), never a false open -> done.
    for _, dungeonID in ipairs(t.lfg) do curr.lfg[dungeonID] = true end
  end
  return curr
end

-- Compares the last stored observation with a fresh one and counts the new
-- attempts of unowned mounts (Attempts.Newly: one per newly satisfied
-- difficulty group, or per quest / LFG flag going open -> done) on this
-- character's counters (ns.db.global.attemptsByChar). Returns the
-- mountIDs counted (a mount once per attempt). Does nothing until
-- saved-instance data has arrived. freshInstances: true on
-- UPDATE_INSTANCE_INFO (re-read the saved instances), else the last snapshot
-- is kept and only quest / LFG flags are refreshed.
function ns.UpdateAttempts(freshInstances)
  if not (ns.db and ready.instances) then return {} end
  local char, global = ns.db.char, ns.db.global
  local prev = char.last
  local curr = observe(prev, freshInstances)
  local newly = ns.Attempts.Newly(prev, curr, tracking().mounts, specFor,
    function(mountID) return ns.Game.IsOwned(mountID) end)
  if type(global.attemptsByChar) ~= "table" then global.attemptsByChar = {} end
  local charKey = ns.Game.CharKey()
  for _, mountID in ipairs(newly) do
    ns.Attempts.AddForChar(global.attemptsByChar, charKey, mountID)
  end
  char.last = curr
  ns.RecordSeen(char, ns.Game.Now())
  return newly
end

-- Stamps `char` (this character's AceDB section) with who it is and when its
-- stored observation (char.last) stops being true: the daily / weekly reset
-- after `now`. The alt lockout matrix (Logic\Alts.lua) reads every
-- character's section and treats a lockout as fresh once its reset has passed.
function ns.RecordSeen(char, now)
  local Game = ns.Game
  char.seen = {
    name = Game.PlayerName(),
    realm = (GetNormalizedRealmName and GetNormalizedRealmName()) or (GetRealmName and GetRealmName()) or nil,
    class = Game.ClassFile(),
    level = Game.Level(),
    faction = Game.Faction(),
    at = now,
    dailyReset = now + (Game.UntilDaily() or 0),
    weeklyReset = now + (Game.UntilWeekly() or 0),
  }
end

-- Kill statistics -------------------------------------------------------------

-- True when a read was skipped in combat; PLAYER_REGEN_ENABLED does it then.
local statsPending = false

-- Reads this character's kill statistics (Stats.Collect over Game.Statistic)
-- into ns.db.global.stats[charKey]. Not in combat: then it waits for
-- PLAYER_REGEN_ENABLED. -> true when read.
function ns.UpdateStats()
  if not ns.db then return false end
  if ns.Game.InCombat() then
    statsPending = true
    return false
  end
  statsPending = false
  local global = ns.db.global
  if type(global.stats) ~= "table" then global.stats = {} end
  local readings = ns.Stats.Collect(ns.Data and ns.Data.Mounts, ns.Game.Statistic)
  ns.Stats.Merge(global.stats, ns.Game.CharKey(), readings)
  return true
end

-- Lifecycle -------------------------------------------------------------------

-- The route planner is retired for now (F16): the Route tab became the
-- Checklist tab and the route arrow is parked. On `db` (AceDB: .char,
-- .global): the arrow can't come back on (routeMode forced to "list"), the
-- route list's settings go (routeView, showCompleted) and a saved "route"
-- tab opens the Checklist tab.
function ns.RetireRoute(db)
  local char, global = db and db.char, db and db.global
  if type(char) == "table" then
    char.routeMode = "list"
    char.routeView = nil
    char.showCompleted = nil
  end
  local window = type(global) == "table" and global.window or nil
  if type(window) == "table" and window.tab == "route" then window.tab = "checklist" end
end

-- The add-on was called AzerothTrail: its saved variable (AzerothTrailDB,
-- still listed in the .toc) becomes MountTrailDB once, when there is no
-- MountTrailDB yet; the old one is then cleared. WoW reads it from
-- WTF\Account\<account>\SavedVariables\MountTrail.lua, so the old
-- AzerothTrail.lua has to be copied to that name first
-- (tools\link_addon.ps1 does it).
function ns.MigrateOldName()
  if type(MountTrailDB) ~= "table" and type(AzerothTrailDB) == "table" then
    MountTrailDB = AzerothTrailDB
  end
  AzerothTrailDB = nil
end

function addon:OnInitialize()
  -- One saved variable, MountTrailDB: AceDB keeps the per-character section
  -- under .char ("Name - Realm"), so no SavedVariablesPerCharacter is needed.
  -- char.last (the last lockout observation) starts nil.
  ns.MigrateOldName()
  ns.db = LibStub("AceDB-3.0"):New("MountTrailDB", {
    global = {
      -- { collected = bool, [view] = { [section] = false } } (Logic\Journal.lua)
      filters = copyTable(ns.Journal.DefaultFilters),
      -- Attempt counters per character: { [charKey] = { [mountID] = n } }.
      -- `attempts` ({ [mountID] = n }) is the account-wide counter of earlier
      -- versions, kept as a legacy bucket: counted in the tooltip's total only
      -- (Attempts.Summary), never incremented again.
      attempts = {},
      attemptsByChar = {},
      stats = {}, -- kill statistics: { [charKey] = { [mountID] = kills } } (Logic\Stats.lua)
      minimap = { hide = false },
      window = {},
      arrow = {}, -- route arrow frame position (UI\Arrow.lua)
      debug = false, -- /mtrail debug: show caught map / waypoint errors
      achievementMap = {}, -- { build=, ids={[mountID]=achievementID|false} } (Integrations\AchievementScan.lua)
      zonePanel = { open = false }, -- zone side panel shown with the window (UI\ZonePanel.lua)
      -- Options > AddOns > MountTrail (UI\Options.lua): waypoints = "game" | "tomtom" | "both"
      -- (Integrations\Map.lua); showUnobtainable: not-owned unobtainable mounts on Misc (UI\List.lua)
      settings = { waypoints = "game", showUnobtainable = false },
      runWindow = {}, -- tonight's run window position (UI\RunWindow.lua)
      collapsed = {}, -- list headers the player collapsed: { ["<view>|<exp>|<section>[|<sub-group>]"] = true } (UI\List.lua)
    },
    char = {
      ticks = {},
      routeMode = "list", -- the parked route arrow (UI\Arrow.lua): always "list" (ns.RetireRoute)
      checklistHideDone = false, -- Checklist: hide done lockouts
      checklistFilters = {}, -- Checklist Filter menu: { [category] = false } for hidden ones (Logic\Checklist.lua)
      -- Tonight's run (Logic\Run.lua, UI\RunWindow.lua): { stops =, skipped =, started =, expires = } or nil;
      -- runShown: its window is open.
      campChecked = {}, -- Checklist rare spawns with no lockout: { [tick key] = time the player last checked the spawn }
    },
  }, true)
  -- Pre-F15 saved variables kept the Journal's source filters as flat keys.
  ns.Journal.MigrateFilters(ns.db.global.filters)
  ns.RetireRoute(ns.db)
  self:RegisterChatCommand("mtrail", "OnSlash")
  self:RegisterChatCommand("mounttrail", "OnSlash")
  -- The add-on's old name (AzerothTrail): its commands still work.
  self:RegisterChatCommand("azt", "OnSlash")
  self:RegisterChatCommand("azerothtrail", "OnSlash")
end

function addon:OnEnable()
  self:RegisterEvent("PLAYER_ENTERING_WORLD", "OnEnteringWorld")
  self:RegisterEvent("UPDATE_INSTANCE_INFO", "OnLockoutEvent")
  self:RegisterEvent("QUEST_TURNED_IN", "OnLockoutEvent")
  self:RegisterEvent("LFG_UPDATE_RANDOM_INFO", "OnLockoutEvent")
  self:RegisterEvent("NEW_MOUNT_ADDED", "OnLockoutEvent")
  self:RegisterEvent("CALENDAR_UPDATE_EVENT_LIST", "OnCalendarUpdate")
  self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
  -- Kill triggers: ask for fresh saved-instance data so UPDATE_INSTANCE_INFO
  -- (which does the counting) follows promptly. Payloads are not read: Midnight
  -- may hide encounter details.
  self:RegisterEvent("BOSS_KILL", "OnKill")
  self:RegisterEvent("ENCOUNTER_END", "OnKill")
  -- Event rares' live status (F17): assault POIs and warfront contributions
  -- changed; the checklist re-reads them and redraws, throttled
  -- (UI.EventStatusChanged in UI\ChecklistView.lua).
  self:RegisterEvent("AREA_POIS_UPDATED", "OnEventStatus")
  self:RegisterEvent("CONTRIBUTION_COLLECTOR_UPDATE", "OnEventStatus")
end

function addon:OnEnteringWorld()
  ns.Game.RequestLockouts()
  ns.Resets.Prune(ns.db.char.ticks, ns.Game.Now())
  ns.UpdateStats()
  ns.Refresh()
end

function addon:OnLockoutEvent(event)
  if event == "UPDATE_INSTANCE_INFO" then ready.instances = true end
  if event == "LFG_UPDATE_RANDOM_INFO" then ready.lfg = true end
  ns.UpdateAttempts(event == "UPDATE_INSTANCE_INFO")
  if event == "UPDATE_INSTANCE_INFO" then ns.UpdateStats() end
  ns.Refresh()
end

-- Reads the kill statistics a combat-time event had to skip, then refreshes.
function addon:OnCombatEnd()
  if statsPending and ns.UpdateStats() then ns.Refresh() end
end

function addon:OnKill()
  ns.Game.RequestLockouts()
end

function addon:OnCalendarUpdate()
  ns.Game.CalendarChanged()
  ns.Refresh()
end

function addon:OnEventStatus()
  local UI = ns.UI
  if UI and type(UI.EventStatusChanged) == "function" then UI.EventStatusChanged() end
end

-- Slash commands --------------------------------------------------------------

function ns.Dump()
  local rows = ns.Game.SavedRows(true) -- include rows missing an ID, to spot them
  if #rows == 0 then
    addon:Print(L["No saved instances yet (lockout data arrives shortly after login). Try again in a moment."])
    ns.Game.RequestLockouts()
    return
  end
  addon:Print(L["Saved instances (instance ID / difficulty ID):"])
  for _, row in ipairs(rows) do
    local bosses = {}
    for _, boss in ipairs(row.bosses or {}) do
      bosses[#bosses + 1] = string.format("%s (%s)", tostring(boss.name), boss.killed and L["killed"] or L["alive"])
    end
    addon:Print(string.format("%s: %s / %s - %s", tostring(row.name), tostring(row.instance),
      tostring(row.difficulty), table.concat(bosses, ", ")))
  end
end

function addon:OnSlash(input)
  local cmd = string.lower((input or ""):match("^%s*(.-)%s*$"))
  if cmd == "" then
    if ns.ToggleWindow then
      ns.ToggleWindow()
    else
      self:Print(L["The window is not available yet. Type /mtrail help for commands."])
    end
  elseif cmd == "dump" then
    ns.Dump()
  elseif cmd == "zone" then
    if ns.ToggleZonePanel then
      ns.ToggleZonePanel()
    else
      self:Print(L["The window is not available yet. Type /mtrail help for commands."])
    end
  elseif cmd == "rares" then
    if ns.UI and ns.UI.ToggleZonePopout then
      ns.UI.ToggleZonePopout()
    else
      self:Print(L["The window is not available yet. Type /mtrail help for commands."])
    end
  elseif cmd == "run" then
    if ns.UI and ns.UI.ToggleRun then
      ns.UI.ToggleRun()
    else
      self:Print(L["The window is not available yet. Type /mtrail help for commands."])
    end
  elseif cmd == "options" then
    if ns.Options and ns.Options.Open then
      ns.Options.Open()
    else
      self:Print(L["The options page is not available on this client."])
    end
  elseif cmd == "debug" then
    ns.db.global.debug = not ns.db.global.debug
    if ns.Options and ns.Options.Changed then ns.Options.Changed(ns.Options.DEBUG) end
    self:Print(ns.db.global.debug and L["Debug: on (caught map and waypoint errors go to the error handler)"]
      or L["Debug: off"])
    -- Templates the window could not use on this client (UI.Template).
    local fallbacks = ns.UI and ns.UI.TemplateFallbacks
    if ns.db.global.debug and type(fallbacks) == "table" and next(fallbacks) then
      local names = {}
      for preferred in pairs(fallbacks) do names[#names + 1] = preferred end
      table.sort(names)
      for _, preferred in ipairs(names) do
        self:Print(string.format(L["Template %s missing, using %s"], preferred,
          fallbacks[preferred] or L["none"]))
      end
    end
  else
    self:Print(L["Commands:"])
    self:Print(L["/mtrail - show or hide the window"])
    self:Print(L["/mtrail dump - list saved instances (instance ID, difficulty ID, bosses)"])
    self:Print(L["/mtrail zone - show or hide the zone panel (mounts in your current zone)"])
    self:Print(L["/mtrail rares - show or hide the rare spawns of your zone"])
    self:Print(L["/mtrail run - start tonight's farming run (or show / hide the one in progress)"])
    self:Print(L["/mtrail options - open the MountTrail options (Options > AddOns)"])
    self:Print(L["/mtrail debug - show or hide caught map and waypoint errors"])
    self:Print(L["/mtrail help - this list"])
  end
end
