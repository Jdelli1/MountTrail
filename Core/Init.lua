local ADDON, ns = ...

ns.version = "0.1.0"

-- UI hook: re-renders the window. A no-op until the UI files (Task 12) replace
-- it; always call it as ns.Refresh() so the replacement is picked up.
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
-- true flags are stored to keep the saved variables small.
local function observe(prev)
  local t = tracking()
  local curr = { snap = ns.Lockouts.Snapshot(ns.Game.SavedRows()), quests = {}, lfg = {} }
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

-- Compares the last stored observation with a fresh one and counts one
-- attempt for each unowned mount whose lockout went open -> done. Returns the
-- mountIDs counted. Does nothing until saved-instance data has arrived.
function ns.UpdateAttempts()
  if not (ns.db and ready.instances) then return {} end
  local char, global = ns.db.char, ns.db.global
  local prev = char.last
  local curr = observe(prev)
  local newly = ns.Attempts.Newly(prev, curr, tracking().mounts, specFor,
    function(mountID) return ns.Game.IsOwned(mountID) end)
  for _, mountID in ipairs(newly) do ns.Attempts.Add(global.attempts, mountID) end
  char.last = curr
  return newly
end

-- Lifecycle -------------------------------------------------------------------

function addon:OnInitialize()
  -- One saved variable, AzerothTrailDB: AceDB keeps the per-character section
  -- under .char ("Name - Realm"), so no SavedVariablesPerCharacter is needed.
  -- char.last (the last lockout observation) starts nil.
  ns.db = LibStub("AceDB-3.0"):New("AzerothTrailDB", {
    global = {
      filters = copyTable(ns.Journal.DefaultFilters),
      attempts = {},
      minimap = { hide = false },
      window = {},
    },
    char = {
      ticks = {},
      showCompleted = false,
    },
  }, true)
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
end

function addon:OnEnteringWorld()
  ns.Game.RequestLockouts()
  ns.Resets.Prune(ns.db.char.ticks, ns.Game.Now())
  ns.Refresh()
end

function addon:OnLockoutEvent(event)
  if event == "UPDATE_INSTANCE_INFO" then ready.instances = true end
  if event == "LFG_UPDATE_RANDOM_INFO" then ready.lfg = true end
  ns.UpdateAttempts()
  ns.Refresh()
end

function addon:OnCalendarUpdate()
  ns.Refresh()
end

-- Slash commands --------------------------------------------------------------

function ns.Dump()
  local rows = ns.Game.SavedRows()
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
      self:Print(L["The window is not available yet. Type /azt help for commands."])
    end
  elseif cmd == "dump" then
    ns.Dump()
  else
    self:Print(L["Commands:"])
    self:Print(L["/azt - show or hide the window"])
    self:Print(L["/azt dump - list saved instances (instance ID, difficulty ID, bosses)"])
    self:Print(L["/azt help - this list"])
  end
end
