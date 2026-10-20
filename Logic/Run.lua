local ADDON, ns = ...

-- Tonight's farming run: this character's open lockouts (the Checklist's
-- daily and weekly entries) in an order worth riding, and the run's
-- progress as the player works through it (UI/RunWindow.lua).
-- Pure Lua, no WoW API: places come in from Map.Locate, "open" from the
-- caller's predicate.
local Run = {}
ns.Run = Run

local UNKNOWN = "?"

-- Group of a stop: its continent's uiMap when known, else its world
-- continent, else UNKNOWN (no place at all).
local function groupKey(place)
  if type(place) ~= "table" then return UNKNOWN end
  if place.area then return "a" .. tostring(place.area) end
  if place.continent then return "c" .. tostring(place.continent) end
  return UNKNOWN
end

local function hasXY(place)
  return type(place) == "table" and place.continent ~= nil
    and type(place.x) == "number" and type(place.y) == "number"
end

local function dist2(a, b)
  if a.continent ~= b.continent then return math.huge end
  return (a.x - b.x) ^ 2 + (a.y - b.y) ^ 2
end

-- Nearest-neighbour walk over `stops` (all with x / y) from `from` (a place,
-- or nil: start at the stop farthest from the group's centre, an end of the
-- group rather than its middle). Ties keep input order.
local function walk(stops, from)
  local left = {}
  for i, s in ipairs(stops) do left[i] = s end
  if #left == 0 then return {} end
  if not from then
    local cx, cy = 0, 0
    for _, s in ipairs(left) do cx, cy = cx + s.place.x, cy + s.place.y end
    cx, cy = cx / #left, cy / #left
    local centre = { continent = left[1].place.continent, x = cx, y = cy }
    local far, farD = 1, -1
    for i, s in ipairs(left) do
      local d = dist2(s.place, centre)
      if d ~= math.huge and d > farD then far, farD = i, d end
    end
    from = left[far].place
  end
  local out = {}
  while #left > 0 do
    local best, bestD = 1, math.huge
    for i, s in ipairs(left) do
      local d = dist2(from, s.place)
      if d < bestD then best, bestD = i, d end
    end
    local s = table.remove(left, best)
    out[#out + 1] = s
    from = s.place
  end
  return out
end

-- stops: { { key =, place = Map.Locate result or nil, ... } } in checklist
-- order; here: the player's world position ({ continent =, x =, y = }) or nil.
-- -> the same stops in riding order: grouped by continent, the player's own
-- continent first, then the others by how many stops they hold (most first;
-- ties by name), stops with no known place last. Within a continent: stops
-- with a world position by nearest neighbour (from the player on their own
-- continent), then those known only by zone, in input order.
function Run.Plan(stops, here)
  local groups, byKey = {}, {}
  for i, s in ipairs(stops or {}) do
    local key = groupKey(s.place)
    local g = byKey[key]
    if not g then
      g = { key = key, name = type(s.place) == "table" and s.place.areaName or nil,
        first = i, xy = {}, zoneOnly = {}, mine = false }
      byKey[key] = g
      groups[#groups + 1] = g
    end
    if hasXY(s.place) then
      g.xy[#g.xy + 1] = s
      if here and s.place.continent == here.continent then g.mine = true end
    else
      g.zoneOnly[#g.zoneOnly + 1] = s
    end
  end
  table.sort(groups, function(a, b)
    if (a.key == UNKNOWN) ~= (b.key == UNKNOWN) then return b.key == UNKNOWN end
    if a.mine ~= b.mine then return a.mine end
    local na, nb = #a.xy + #a.zoneOnly, #b.xy + #b.zoneOnly
    if na ~= nb then return na > nb end
    local la, lb = string.lower(a.name or ""), string.lower(b.name or "")
    if la ~= lb then return la < lb end
    return a.first < b.first
  end)
  local out = {}
  for _, g in ipairs(groups) do
    for _, s in ipairs(walk(g.xy, g.mine and here or nil)) do out[#out + 1] = s end
    for _, s in ipairs(g.zoneOnly) do out[#out + 1] = s end
  end
  return out
end

-- A new run over `stops` (Run.Plan's order; each { key =, ... } is stored
-- as is) started at `now`, ending at `expires` (the next daily reset).
function Run.New(stops, now, expires)
  return { stops = stops or {}, skipped = {}, started = now, expires = expires }
end

function Run.Expired(run, now)
  return type(run) ~= "table" or type(run.stops) ~= "table"
    or (run.expires ~= nil and now >= run.expires)
end

-- Whether stop `s` is still to do: not skipped and isOpen(key).
local function todo(run, s, isOpen)
  return not (run.skipped and run.skipped[s.key]) and isOpen(s.key)
end

-- The stop to ride to: the first one still to do -> stop, its index; nil
-- when the run is over.
function Run.Current(run, isOpen)
  for i, s in ipairs(run.stops or {}) do
    if todo(run, s, isOpen) then return s, i end
  end
  return nil
end

-- Up to `n` stops still to do after the current one.
function Run.Upcoming(run, isOpen, n)
  local out, seenCurrent = {}, false
  for _, s in ipairs(run.stops or {}) do
    if todo(run, s, isOpen) then
      if seenCurrent then
        out[#out + 1] = s
        if #out >= n then break end
      else
        seenCurrent = true
      end
    end
  end
  return out
end

-- -> stops behind the player (done or skipped), total stops.
function Run.Progress(run, isOpen)
  local total, behind = #(run.stops or {}), 0
  for _, s in ipairs(run.stops or {}) do
    if not todo(run, s, isOpen) then behind = behind + 1 end
  end
  return behind, total
end

-- Skips the current stop (it stays open on the checklist) -> the new current.
function Run.Skip(run, isOpen)
  local s = Run.Current(run, isOpen)
  if s then
    run.skipped = run.skipped or {}
    run.skipped[s.key] = true
  end
  return Run.Current(run, isOpen)
end

-- How many stops were skipped and are still open (worth a second pass).
function Run.SkippedOpen(run, isOpen)
  local n = 0
  for _, s in ipairs(run.stops or {}) do
    if run.skipped and run.skipped[s.key] and isOpen(s.key) then n = n + 1 end
  end
  return n
end

-- Puts the skipped stops back on the run.
function Run.Unskip(run)
  run.skipped = {}
end
