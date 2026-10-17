local ADDON, ns = ...

-- Mounts whose location is the player's current zone (the zone side panel,
-- UI/ZonePanel.lua). Pure Lua: every map, Encounter Journal and source-text
-- lookup comes in through ctx, so the matching rules are unit-tested.
local Zone = {}
ns.Zone = Zone

-- Enum.UIMapType values (C_Map.GetMapInfo(...).mapType).
local CONTINENT, ZONE, DUNGEON = 2, 3, 4

-- Parent steps followed at most (map trees are a few levels deep).
local MAX_STEPS = 10

-- The zone the player is in, from the player's map: micro / dungeon / orphan
-- floors climb to the first Zone map above them, but never onto a continent
-- (a floor straight under a continent is its own root; a continent stays a
-- continent). When instanceForMap is given and the map is a dungeon floor of
-- a journal instance, the player is inside that instance: the floor itself
-- is the root. mapInfo(id) -> { name=, mapType=, parentMapID= } | nil.
-- -> rootMapID, journalInstanceID|nil; nil for an unknown map.
function Zone.Root(mapID, mapInfo, instanceForMap)
  if not mapID then return nil end
  local info = mapInfo(mapID)
  if type(info) ~= "table" then return nil end
  if info.mapType == DUNGEON and instanceForMap then
    local jid = instanceForMap(mapID)
    if jid and jid ~= 0 then return mapID, jid end
  end
  local current, seen = mapID, { [mapID] = true }
  for _ = 1, MAX_STEPS do
    if type(info.mapType) ~= "number" or info.mapType <= ZONE then return current end
    local parent = info.parentMapID
    if not parent or parent == 0 or seen[parent] then return current end
    local parentInfo = mapInfo(parent)
    if type(parentInfo) ~= "table" or type(parentInfo.mapType) ~= "number"
      or parentInfo.mapType <= CONTINENT then
      return current
    end
    seen[parent] = true
    current, info = parent, parentInfo
  end
  return current
end

-- Fallback name key when ctx.key is missing: UI.GroupKey when loaded, else
-- lower case.
local function defaultKey(name)
  local ui = ns.UI
  if ui and type(ui.GroupKey) == "function" then return ui.GroupKey(name) end
  return string.lower(tostring(name))
end

local function nonEmpty(s)
  return type(s) == "string" and s ~= "" and s or nil
end

-- Mounts the player can still get whose location is the zone of `mapID`
-- (normally C_Map.GetBestMapForUnit("player")); a mount matches when
--   (a) "coords": its coords map is the root (Zone.Root) or a map under it
--       (micro / dungeon floors, sub-zones; a continent root matches only
--       itself),
--   (b) "source": its source text's "Zone:" equals the zone's name (or, in
--       an instance, the instance's), compared by ctx.key,
--   (c) "instance": it belongs to a journal instance whose entrance is in
--       the zone (entrances on the root and on the player's own map; inside
--       an instance: that instance) - its instance sub-group or route
--       instance names the instance, or its coords map is one of the
--       instance's maps.
-- Every mount appears once, with the first rule that matched.
-- ctx: mounts = { [id] = m }, mapInfo(id), and optionally
--   coords(id, m) -> { m= } (default m.coords; the holiday override),
--   sourceZone(id) -> "Zone:" value, subGroup(id, m) -> instance name,
--   routeInstance(id) -> instance name, entrances(mapID) -> { {
--   journalInstanceID=, name= } }, instanceForMap(mapID) -> journal
--   instance, instanceName(journalInstanceID) -> name (EJ_GetInstanceInfo),
--   key(name) -> comparable key (UI.GroupKey), gate(id, m) -> owned boolean
--   or nil to leave the mount out (Zone.Gate; default: kept, not owned),
--   showCollected = true to keep owned mounts.
-- -> list of { id=, m=, owned=, via= "coords"|"source"|"instance" } sorted
-- by name (case-insensitive), then id; zone = { mapID = root, name =,
-- instance = journalInstanceID (inside one) } or nil for an unknown map.
function Zone.MountsFor(mapID, ctx)
  local mapInfo = ctx.mapInfo
  local root, insideInstance = Zone.Root(mapID, mapInfo, ctx.instanceForMap)
  if not root then return {}, nil end
  local rootInfo = mapInfo(root)
  local key = ctx.key or defaultKey

  -- Parent lookups and instance lookups, once per map this call.
  local infoCache, instanceCache = {}, {}
  local function info(id)
    local v = infoCache[id]
    if v == nil then
      v = mapInfo(id)
      if type(v) ~= "table" then v = false end
      infoCache[id] = v
    end
    return v or nil
  end
  local function instanceOf(id)
    if not ctx.instanceForMap then return nil end
    local v = instanceCache[id]
    if v == nil then
      v = ctx.instanceForMap(id)
      if not v or v == 0 then v = false end
      instanceCache[id] = v
    end
    return v or nil
  end

  -- (a) Is `id` the root or a map below it?
  local rootIsZone = type(rootInfo.mapType) == "number" and rootInfo.mapType >= ZONE
  local inZone = {}
  local function underRoot(id)
    if id == root then return true end
    if not rootIsZone then return false end
    local v = inZone[id]
    if v ~= nil then return v end
    local current, steps, found = id, 0, false
    while current and steps < MAX_STEPS do
      local i = info(current)
      if not i or (type(i.mapType) == "number" and i.mapType <= CONTINENT) then break end
      local parent = i.parentMapID
      if parent == root then found = true break end
      if not parent or parent == 0 or parent == current then break end
      current, steps = parent, steps + 1
    end
    inZone[id] = found
    return found
  end

  -- (b) Names the source text's Zone: may carry.
  local zoneName = rootInfo.name
  local names = {}
  local function addName(name)
    name = nonEmpty(name)
    if name then names[key(name)] = true end
  end
  addName(zoneName)

  -- (c) Journal instances of the zone, by ID and by name key.
  local instances, instanceNames = {}, {}
  local function addInstance(jid, fallbackName)
    if not jid or jid == 0 then return end
    instances[jid] = true
    local name = ctx.instanceName and nonEmpty(ctx.instanceName(jid)) or nonEmpty(fallbackName)
    if name then instanceNames[key(name)] = true end
    return name
  end
  if insideInstance then
    local name = addInstance(insideInstance)
    if name then
      zoneName = name
      addName(name)
    end
  elseif rootIsZone and ctx.entrances then
    local maps = { root }
    if mapID ~= root then maps[2] = mapID end
    for _, m in ipairs(maps) do
      local list = ctx.entrances(m)
      if type(list) == "table" then
        for _, entrance in ipairs(list) do
          if type(entrance) == "table" then addInstance(entrance.journalInstanceID, entrance.name) end
        end
      end
    end
  end
  local anyInstance = next(instances) ~= nil

  local function coordsMap(id, m)
    local c
    if ctx.coords then c = ctx.coords(id, m) else c = m.coords end
    return type(c) == "table" and c.m or nil
  end
  local function named(name, set)
    name = nonEmpty(name)
    return name ~= nil and set[key(name)] == true
  end

  local function via(id, m)
    local cm = coordsMap(id, m)
    if cm and underRoot(cm) then return "coords" end
    if ctx.sourceZone and named(ctx.sourceZone(id), names) then return "source" end
    if anyInstance then
      if cm and instanceOf(cm) and instances[instanceOf(cm)] then return "instance" end
      if ctx.subGroup and named(ctx.subGroup(id, m), instanceNames) then return "instance" end
      if ctx.routeInstance and named(ctx.routeInstance(id), instanceNames) then return "instance" end
    end
    return nil
  end

  local out = {}
  for id, m in pairs(ctx.mounts or {}) do
    local reason = via(id, m)
    if reason then
      local owned = false
      if ctx.gate then owned = ctx.gate(id, m) end
      if owned ~= nil and (ctx.showCollected or not owned) then
        out[#out + 1] = { id = id, m = m, owned = owned and true or false, via = reason }
      end
    end
  end
  table.sort(out, function(a, b)
    local na, nb = string.lower(a.m.name or ""), string.lower(b.m.name or "")
    if na ~= nb then return na < nb end
    return a.id < b.id
  end)
  return out, { mapID = root, name = zoneName, instance = insideInstance }
end

-- The Journal's gate (Journal.Gate: known to this client, the player's
-- faction, obtainable or owned) as a ctx.gate: fn(id, m) -> owned or nil.
function Zone.Gate(isOwned, exists, faction)
  return function(id, m)
    return ns.Journal.Gate(id, m, isOwned, exists, faction)
  end
end
