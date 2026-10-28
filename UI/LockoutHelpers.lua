local ADDON, ns = ...

-- Lockout helpers for the Checklist tab (UI\ChecklistView.lua): the
-- per-character lockout state and the hand ticks. The names keep the "Route"
-- prefix of the route planner they came from; Data\Route.lua still names the
-- bosses and instances.
--
--   * UI.RouteContext: lockout state per (mount, route boss) -- game lockouts
--     plus hand ticks.
--   * UI.RouteTickKey / RouteCheck / RouteToggle: hand ticks for lockouts
--     the game can't report.
--   * UI.RouteFlavour, UI.FormatDuration: the Checklist header's lines.
--
-- All of it is pure (no frames) and unit-tested in tests/ui_route_spec.lua.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI


-- Pure helpers -------------------------------------------------------------------

local function memo(fn)
  local cache = {}
  return function(id)
    local v = cache[id]
    if v == nil then
      v = fn(id) and true or false
      cache[id] = v
    end
    return v
  end
end

local function charDB()
  return ns.db and ns.db.char or nil
end

local function ticksStore()
  local char = charDB()
  if not char then return {} end
  char.ticks = char.ticks or {}
  return char.ticks
end

-- Active holidays with a boss to queue for -> { {title=, mounts=} }, sorted by
-- holiday key so the order is stable.
local function holidaySteps()
  local active = ns.Game.ActiveHolidays() or {}
  local holidays = (ns.Data and ns.Data.Holidays) or {}
  local keys = {}
  for key in pairs(active) do
    local h = holidays[key]
    if active[key] and type(h) == "table" and h.stepTitle and type(h.mounts) == "table" and #h.mounts > 0 then
      keys[#keys + 1] = key
    end
  end
  table.sort(keys)
  local steps = {}
  for i, key in ipairs(keys) do
    local h = holidays[key]
    steps[i] = { title = L[h.stepTitle], mounts = h.mounts }
  end
  return steps
end

-- Key of a route boss's hand tick in ns.db.char.ticks: the mountID, or
-- "<mountID>@<routeBoss>" when a per-boss spec (Data.BossLockouts) governs
-- the row, so ticking e.g. a Koralon row does not also tick the same
-- mount's own (Archavon) row.
function UI.RouteTickKey(mountID, routeBoss)
  local per = ns.Data and ns.Data.BossLockouts
  if routeBoss and per and per[routeBoss] then
    return tostring(mountID) .. "@" .. tostring(routeBoss)
  end
  return mountID
end

-- Route.Build context for this character at `now` (epoch seconds, defaults to
-- Game.Now()). stateOf(mountID, routeBoss): "done" when the game reports the
-- governing spec done (the auto path always wins); else "manual-done" while a
-- hand tick (any spec kind: manual specs, or a manual override of an
-- instance / quest / LFG spec) has not expired; else "manual-open" for manual
-- specs and "open" otherwise (untracked mounts too).
function UI.RouteContext(now)
  local Game = ns.Game
  now = now or Game.Now()
  local snap = ns.Lockouts.Snapshot(Game.SavedRows())
  local ticks = ticksStore()
  local function stateOf(mountID, routeBoss)
    local spec = ns.Lockouts.SpecFor(mountID, routeBoss)
    local state = ns.Lockouts.State(spec, snap, Game.IsQuestDone, Game.IsLfgDone)
    if state == "done" then return "done" end
    -- Hand ticks only stand in for lockouts the game can't report (manual
    -- specs). A game-tracked row is done only when the game says so, so a
    -- stray tick never makes this character look locked out.
    if state ~= "manual" then return "open" end
    if ns.Resets.IsTicked(ticks, UI.RouteTickKey(mountID, routeBoss), now) then return "manual-done" end
    return "manual-open"
  end
  return {
    faction = Game.Faction(),
    isOwned = memo(Game.IsOwned),
    isQuestDone = Game.IsQuestDone,
    stateOf = stateOf,
    showCompleted = false,
    holidaySteps = holidaySteps(),
  }
end

-- A lockout spent on some of its difficulties but not all (Lockouts.Progress)
-- -> "Heroic done · Normal, Mythic left", else nil. snap: Lockouts.Snapshot.
function UI.LockoutProgressText(spec, snap)
  local progress = ns.Lockouts.Progress(spec, snap)
  if not progress then return nil end
  local function names(ids)
    local out = {}
    for _, d in ipairs(ids) do out[#out + 1] = ns.Game.DifficultyName(d) or tostring(d) end
    return table.concat(out, ", ")
  end
  return string.format(L["%s done"], names(progress.done)) .. " \194\183 "
    .. string.format(L["%s left"], names(progress.open))
end

-- Whether the player may tick (or untick) a route boss by hand: only bosses
-- with a manual spec (the game can't report them). Game-tracked bosses
-- (instance / quest / LFG) are display-only, "done" belongs to the game, and
-- untracked mounts have nothing to reset.
local function tickable(b)
  local state = b.state
  return state == "manual-open" or state == "manual-done"
end

-- Tick box for a route row -> checked, enabled, auto.
-- Rows with a tickable boss: enabled, checked when every tickable boss is
-- ticked, never tagged "auto" (the tick is the player's). Other kill rows:
-- disabled (the game decides), checked when done, "auto" when Route.Build
-- says so. Travel rows: nil (no box).
function UI.RouteCheck(row)
  if row.kind ~= "kill" then return nil end
  local anyTickable, allTicked = false, true
  for _, b in ipairs(row.bosses or {}) do
    if tickable(b) then
      anyTickable = true
      if b.state ~= "manual-done" then allTicked = false end
    end
  end
  if anyTickable then return allTicked, true, false end
  return row.state == "done", false, row.auto == true
end

-- Click on a tickable row: untick every tickable boss when all are ticked,
-- else tick them all until the next reset of their spec (`reset`, default
-- daily). Ticks are keyed by UI.RouteTickKey. -> true when the row had a
-- tickable boss. Hand ticks never count attempts (Core\Init.lua reads only
-- the game's lockout data).
function UI.RouteToggle(row, store, now, untilDaily, untilWeekly)
  local checked, enabled = UI.RouteCheck(row)
  if not enabled then return false end
  for _, b in ipairs(row.bosses or {}) do
    if tickable(b) then
      local key = UI.RouteTickKey(b.mount, b.boss)
      if checked then
        ns.Resets.Untick(store, key)
      else
        local spec = ns.Lockouts.SpecFor(b.mount, b.boss)
        local kind = (spec and (spec.reset == "weekly" or spec.reset == "daily")) and spec.reset or "daily"
        ns.Resets.Tick(store, key, kind, now, untilDaily, untilWeekly)
      end
    end
  end
  return true
end

-- Opening line: lockouts left, or the Oregon line when none are.
function UI.RouteFlavour(remaining, name)
  if remaining > 0 then
    return string.format(L["You have %d lockouts left. Saddle up?"], remaining)
  end
  return string.format(L["%s has reached Oregon. Nothing left to farm until reset."], name or L["Your party"])
end

-- Seconds -> "2 Days 3 Hr" via SecondsToTime (FrameXML), else "2d 3h 4m".
function UI.FormatDuration(seconds)
  seconds = math.max(0, math.floor(tonumber(seconds) or 0))
  if type(SecondsToTime) == "function" then
    local text = SecondsToTime(seconds, true)
    if type(text) == "string" and text ~= "" then return text end
  end
  local d = math.floor(seconds / 86400)
  local h = math.floor((seconds % 86400) / 3600)
  local m = math.floor((seconds % 3600) / 60)
  if d > 0 then return string.format("%dd %dh %dm", d, h, m) end
  if h > 0 then return string.format("%dh %dm", h, m) end
  return string.format("%dm", m)
end
