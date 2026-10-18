local ADDON, ns = ...

-- Live status of event rares (F17): the N'Zoth assault running in Uldum / the
-- Vale of Eternal Blossoms and the state of the Arathi / Darkshore warfronts,
-- for the checklist rows whose mount is in one of Data/Events.lua's groups.
-- Pure Lua, no WoW API: the caller (UI/ChecklistView.lua) injects the game
-- lookups (Game.AreaPOIsForMap, Game.AreaPOISecondsLeft,
-- Game.ContributionsForMap) and a duration formatter.
--
-- Only what the game reports is shown: which assault is up in the zone (an
-- assault rare can't be tied to its assault from the client's data, so rows
-- never claim a rare is up), and each warfront contribution's state as the
-- game names it (no claim about which rares a phase spawns). Anything the
-- game does not report reads "Status unknown — click to load".
local Events = {}
ns.Events = Events

local L = ns.L or setmetatable({}, { __index = function(_, k) return k end })

local UNKNOWN = "Status unknown — click to load"

-- Enum.ContributionState (GarrisonConstantsDocumentation): None 0,
-- Building 1, Active 2, UnderAttack 3, Destroyed 4. The game's own state
-- name (GetContributionAppearance(...).stateName) wins; these stand in when
-- it gives none.
local STATE_NAMES = { [1] = "Building", [2] = "Active", [3] = "Under attack", [4] = "Destroyed" }
local BUILDING = 1

-- The event group of mount data `m` (its SimpleArmory `group`) -> key, def;
-- nil when it has none.
function Events.GroupOf(m, groups)
  if type(m) ~= "table" or type(groups) ~= "table" or m.group == nil then return nil end
  local def = groups[m.group]
  if type(def) ~= "table" then return nil end
  return m.group, def
end

-- An assault group's status from `poiIDs` (the AreaPOI IDs its maps report,
-- nil when unknown) and secondsLeft(poiID) (may be nil) -> { kind =
-- "assault", known = true, poi =, name = def.pois[poi], seconds = (positive
-- or nil) } or { kind = "assault", known = false }. Two assault POIs at once
-- (a rotation in progress): the lowest ID.
function Events.AssaultStatus(def, poiIDs, secondsLeft)
  local found
  for _, id in ipairs(type(poiIDs) == "table" and poiIDs or {}) do
    if type(id) == "number" and def.pois[id] and (found == nil or id < found) then found = id end
  end
  if not found then return { kind = "assault", known = false } end
  local seconds = type(secondsLeft) == "function" and secondsLeft(found) or nil
  if type(seconds) ~= "number" or seconds <= 0 then seconds = nil end
  return { kind = "assault", known = true, poi = found, name = def.pois[found], seconds = seconds }
end

local function isOurs(def, id)
  for _, mine in ipairs(def.contributions or {}) do
    if mine == id then return true end
  end
  return false
end

-- A warfront group's status from `contributions` (Game.ContributionsForMap
-- rows of its maps: { id=, state=, stateName=, percent= (0..1), seconds=,
-- useTime= }, nil when unknown) -> { kind = "warfront", known = true, parts
-- = { { id=, state=, stateName=, percent= (whole %, contributing only) |
-- seconds= (when the game's appearance uses time left) } } } or { kind =
-- "warfront", known = false }. Rows that are not def.contributions, or in
-- state None, are left out.
function Events.WarfrontStatus(def, contributions)
  local parts = {}
  for _, c in ipairs(type(contributions) == "table" and contributions or {}) do
    if type(c) == "table" and type(c.id) == "number" and isOurs(def, c.id)
      and type(c.state) == "number" and STATE_NAMES[c.state] then
      local part = { id = c.id, state = c.state,
        stateName = (type(c.stateName) == "string" and c.stateName ~= "") and c.stateName or L[STATE_NAMES[c.state]] }
      if c.useTime and type(c.seconds) == "number" and c.seconds > 0 then
        part.seconds = c.seconds
      elseif c.state == BUILDING and type(c.percent) == "number" then
        part.percent = math.floor(c.percent * 100 + 0.5)
      end
      parts[#parts + 1] = part
    end
  end
  if #parts == 0 then return { kind = "warfront", known = false } end
  return { kind = "warfront", known = true, parts = parts }
end

-- True for the "status unknown" line (the row's click then opens the map).
function Events.IsUnknown(text)
  return text == L[UNKNOWN]
end

-- The UiMap the game needs open to report `def`'s status: its first map.
function Events.ZoneMap(def)
  return type(def) == "table" and type(def.maps) == "table" and def.maps[1] or nil
end

-- The checklist line of a group's status; formatDuration(seconds) -> text.
function Events.StatusText(def, status, formatDuration)
  if type(status) ~= "table" or not status.known then return L[UNKNOWN] end
  if status.kind == "assault" then
    if status.seconds then
      return string.format(L["%s: %s assault — %s left"], L[def.zone], L[status.name], formatDuration(status.seconds))
    end
    return string.format(L["%s: %s assault"], L[def.zone], L[status.name])
  end
  local parts = {}
  for i, p in ipairs(status.parts) do
    local text = p.stateName
    if p.seconds then
      text = string.format(L["%s — %s left"], text, formatDuration(p.seconds))
    elseif p.percent then
      text = string.format("%s (%d%%)", text, p.percent)
    end
    parts[i] = text
  end
  return string.format(L["%s warfront: %s"], L[def.label or def.zone], table.concat(parts, " / "))
end

-- Calls fn(...) under pcall -> its first result, nil on an error.
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local good, result = pcall(fn, ...)
  if good then return result end
  return nil
end

-- Every group's line: { [group key] = text }. lookups: poisForMap(uiMapID)
-- -> AreaPOI IDs | nil, poiInfo(uiMapID, poiID) -> table | nil (optional),
-- secondsLeft(poiID) -> number | nil,
-- contributionsForMap(uiMapID) -> rows | nil, formatDuration(seconds). Each
-- of a group's maps is asked; a lookup that errors counts as unknown.
function Events.Statuses(groups, lookups)
  local out = {}
  for key, def in pairs(type(groups) == "table" and groups or {}) do
    local status
    if def.kind == "assault" then
      local ids, any = {}, false
      for _, map in ipairs(def.maps or {}) do
        local list = try(lookups.poisForMap, map)
        if type(list) == "table" then
          any = true
          for _, id in ipairs(list) do
            -- With poiInfo (GetAreaPOIInfo), one of our POIs counts only
            -- when the game also has its info on this map.
            if not (lookups.poiInfo and def.pois[id]) or try(lookups.poiInfo, map, id) ~= nil then
              ids[#ids + 1] = id
            end
          end
        end
      end
      status = Events.AssaultStatus(def, any and ids or nil, function(id) return try(lookups.secondsLeft, id) end)
    elseif def.kind == "warfront" then
      local rows, any = {}, false
      for _, map in ipairs(def.maps or {}) do
        local list = try(lookups.contributionsForMap, map)
        if type(list) == "table" then
          any = true
          for _, c in ipairs(list) do rows[#rows + 1] = c end
        end
      end
      status = Events.WarfrontStatus(def, any and rows or nil)
    end
    out[key] = Events.StatusText(def, status, lookups.formatDuration)
  end
  return out
end
