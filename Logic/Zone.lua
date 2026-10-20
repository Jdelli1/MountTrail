local ADDON, ns = ...

-- Mounts whose location is the player's current zone (the zone side panel,
-- UI/ZonePanel.lua). Pure Lua: every map, Encounter Journal and source-text
-- lookup comes in through ctx, so the matching rules are unit-tested.
local Zone = {}
ns.Zone = Zone

-- Enum.UIMapType values (C_Map.GetMapInfo(...).mapType).
local CONTINENT, ZONE = 2, 3

-- Parent steps followed at most (map trees are a few levels deep).
local MAX_STEPS = 10

-- Child maps that may hold dungeon entrances (zones and micro maps, not
-- dungeon floors), and the most maps asked for entrances per call.
local ENTRANCE_TYPES = { [ZONE] = true, [5] = true }
local MAX_ENTRANCE_MAPS = 40

-- The zone the player is in, from the player's map: micro / dungeon / orphan
-- floors climb to the first Zone map above them, but never onto a continent
-- (a floor straight under a continent is its own root; a continent stays a
-- continent). When instanceForMap is given and the map is a floor finer than
-- a zone (dungeon, micro, orphan: delves and scenarios are not always
-- dungeon maps) that belongs to a journal instance, the player is inside
-- that instance: the floor itself is the root. Zone and coarser maps are
-- never taken for an instance (the journal ties continents to their world
-- bosses). mapInfo(id) -> { name=, mapType=, parentMapID= } | nil.
-- -> rootMapID, journalInstanceID|nil; nil for an unknown map.
function Zone.Root(mapID, mapInfo, instanceForMap)
  if not mapID then return nil end
  local info = mapInfo(mapID)
  if type(info) ~= "table" then return nil end
  if type(info.mapType) == "number" and info.mapType > ZONE and instanceForMap then
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

-- What the panel shows for `mapID`, as a string: "<root>" or
-- "<root>:<journalInstanceID>" (Zone.Root), or "instance:<name key>" when
-- the map is unknown but ctx.currentInstance names the instance the player
-- is in; nil when nothing is known. Moving between sub-zones of one zone
-- keeps the key, so the panel need not rebuild.
function Zone.Key(mapID, ctx)
  local root, jid = Zone.Root(mapID, ctx.mapInfo, ctx.instanceForMap)
  if root then
    if jid then return root .. ":" .. jid end
    return tostring(root)
  end
  local name = nonEmpty(ctx.currentInstance)
  if name then return "instance:" .. (ctx.key or defaultKey)(name) end
  return nil
end

-- Mounts the player can still get whose location is the zone of `mapID`
-- (normally C_Map.GetBestMapForUnit("player")); a mount matches when
--   (a) "coords": its coords map is the root (Zone.Root) or a map under it
--       (micro / dungeon floors, sub-zones; a continent root matches only
--       itself; inside an instance: any floor of the root's map group),
--   (b) "source": it has no coords and its source text's "Zone:" equals the
--       zone's name (or, in an instance, the instance's), compared by
--       ctx.key, in the zone version of its expansion (ctx.versionOk: TBC
--       and WoD Nagrand, Uldum and its 8.3 assault version, the Midnight
--       Eversong Woods... share a name),
--   (c) "instance": it belongs to a journal instance whose entrance is in
--       the zone (entrances on the root, the player's own map and the
--       root's zone / micro children whose instance's own map,
--       ctx.instanceUiMap, lies in the zone or is unknown: a zone map also
--       shows a neighbour's entrances near its edge; inside an instance:
--       that instance) - its coords map is a floor of the instance (that
--       map or its map group), or it has no coords (inside an instance:
--       with or without) and its instance sub-group or route instance
--       names the instance.
-- A mount's coords decide where it is: a mount with coords never matches by
-- name in a zone its coords are not in.
-- Every mount appears once, with the first rule that matched.
-- ctx: mounts = { [id] = m }, mapInfo(id), and optionally
--   coords(id, m) -> { m= } (default m.coords; the holiday override),
--   sourceZone(id) -> "Zone:" value, subGroup(id, m) -> instance name,
--   routeInstance(id) -> instance name, entrances(mapID) -> { {
--   journalInstanceID=, name= } }, children(mapID) -> { { mapID=,
--   mapType= } } (every descendant), instanceForMap(floor mapID) -> journal
--   instance (Zone.Root; a UI map, never passed to GetInstanceForGameMap),
--   instanceUiMap(journalInstanceID) -> the instance's first floor UI map,
--   mapGroup(mapID) -> map group ID (floors of one instance share it),
--   versionOk(rootMapID, m) -> false when the root is a same-named zone
--   version the mount is not in (Zone.VersionOk),
--   instanceName(journalInstanceID) -> name (EJ_GetInstanceInfo),
--   key(name) -> comparable key (UI.GroupKey), gate(id, m) -> owned boolean
--   or nil to leave the mount out (Zone.Gate; default: kept, not owned),
--   showCollected = true to keep owned mounts, currentInstance = the name
--   of the instance the player is in (GetInstanceInfo) for when the map is
--   unknown (GetBestMapForUnit gives nil in some instances): then only (b)
--   and (c) by that name apply.
-- Nested zones: a Zone-type ancestor of a Zone root (Thaldraszus above
-- Valdrakken, Isle of Dorn above Dornogal) counts for (a) itself, not its
-- other maps; the root and the title stay the inner zone.
-- The gate runs first: excluded mounts are never looked up.
-- -> list of { id=, m=, owned=, via= "coords"|"source"|"instance" } sorted
-- by name (case-insensitive), then id; zone = { mapID = root, name =,
-- instance = journalInstanceID (inside one) } ({ name = } by instance name
-- only) or nil when nothing is known.
function Zone.MountsFor(mapID, ctx)
  local mapInfo = ctx.mapInfo
  local root, insideInstance = Zone.Root(mapID, mapInfo, ctx.instanceForMap)
  local byName = not root and nonEmpty(ctx.currentInstance) or nil
  if not (root or byName) then return {}, nil end
  local rootInfo = root and mapInfo(root) or {}
  local key = ctx.key or defaultKey

  -- Parent lookups, once per map this call.
  local infoCache = {}
  local function info(id)
    local v = infoCache[id]
    if v == nil then
      v = mapInfo(id)
      if type(v) ~= "table" then v = false end
      infoCache[id] = v
    end
    return v or nil
  end
  local function sameGroup(a, b)
    if a == b then return true end
    if not (ctx.mapGroup and a and b) then return false end
    local ga = ctx.mapGroup(a)
    return ga ~= nil and ga == ctx.mapGroup(b)
  end

  -- (a) Is `id` the root, a map below it, or a Zone-type ancestor below the
  -- continent (nested zones)?
  local rootIsZone = type(rootInfo.mapType) == "number" and rootInfo.mapType >= ZONE
  local ancestors = {}
  if root and rootInfo.mapType == ZONE then
    local current, steps = rootInfo.parentMapID, 0
    while current and current ~= 0 and current ~= root and not ancestors[current] and steps < MAX_STEPS do
      local i = info(current)
      if not i or type(i.mapType) ~= "number" or i.mapType <= CONTINENT then break end
      if i.mapType == ZONE then ancestors[current] = true end
      current, steps = i.parentMapID, steps + 1
    end
  end
  local inZone = {}
  local function underRoot(id)
    if not root then return false end
    if id == root or ancestors[id] then return true end
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
  local zoneName = byName or rootInfo.name
  local names = {}
  local function addName(name)
    name = nonEmpty(name)
    if name then names[key(name)] = true end
  end
  addName(zoneName)

  -- (c) Journal instances of the zone, by ID and by name key, and their
  -- first floors.
  local instances, instanceNames, floors = {}, {}, {}
  local function addInstance(jid, fallbackName)
    if not jid or jid == 0 or instances[jid] then return end
    instances[jid] = true
    local floor = ctx.instanceUiMap and ctx.instanceUiMap(jid) or nil
    if floor then floors[#floors + 1] = floor end
    local name = ctx.instanceName and nonEmpty(ctx.instanceName(jid)) or nonEmpty(fallbackName)
    if name then instanceNames[key(name)] = true end
    return name
  end
  -- An entrance listed on the zone's map whose instance lies in another
  -- zone (its first floor sits under a different Zone map): a neighbour's
  -- entrance drawn near the map's edge (Karazhan on the Blasted Lands).
  local function foreign(jid)
    local floor = ctx.instanceUiMap and ctx.instanceUiMap(jid) or nil
    if not floor or underRoot(floor) then return false end
    local current, steps = floor, 0
    while current and steps < MAX_STEPS do
      local i = info(current)
      if not i or type(i.mapType) ~= "number" or i.mapType <= CONTINENT then return false end
      if i.mapType == ZONE then return true end
      current, steps = i.parentMapID, steps + 1
    end
    return false
  end
  if byName then
    instanceNames[key(byName)] = true
  elseif insideInstance then
    local name = addInstance(insideInstance)
    if name then
      zoneName = name
      addName(name)
    end
  elseif rootIsZone and ctx.entrances then
    -- The root, the player's own map, then the root's zone / micro children
    -- (an entrance may sit on a sub-map such as the Caverns of Time), each
    -- once, at most MAX_ENTRANCE_MAPS lookups.
    local maps, listed = {}, {}
    local function addMap(m)
      if m and not listed[m] and #maps < MAX_ENTRANCE_MAPS then
        listed[m] = true
        maps[#maps + 1] = m
      end
    end
    addMap(root)
    addMap(mapID)
    if ctx.children then
      local children = ctx.children(root)
      if type(children) == "table" then
        for _, child in ipairs(children) do
          if type(child) == "table" and ENTRANCE_TYPES[child.mapType] then addMap(child.mapID) end
        end
      end
    end
    for _, m in ipairs(maps) do
      local list = ctx.entrances(m)
      if type(list) == "table" then
        for _, entrance in ipairs(list) do
          if type(entrance) == "table" and entrance.journalInstanceID
            and not foreign(entrance.journalInstanceID) then
            addInstance(entrance.journalInstanceID, entrance.name)
          end
        end
      end
    end
  end
  local anyInstance = next(instances) ~= nil or next(instanceNames) ~= nil

  local function coordsMap(id, m)
    local c
    if ctx.coords then c = ctx.coords(id, m) else c = m.coords end
    return type(c) == "table" and c.m or nil
  end
  local function named(name, set)
    name = nonEmpty(name)
    return name ~= nil and set[key(name)] == true
  end

  local inInstance = insideInstance ~= nil or byName ~= nil
  local function onFloor(cm)
    for _, floor in ipairs(floors) do
      if sameGroup(cm, floor) then return true end
    end
    return false
  end
  local function namesInstance(id, m)
    if ctx.subGroup and named(ctx.subGroup(id, m), instanceNames) then return true end
    if ctx.routeInstance and named(ctx.routeInstance(id), instanceNames) then return true end
    return false
  end
  local function via(id, m)
    local cm = coordsMap(id, m)
    if cm then
      if underRoot(cm) then return "coords" end
      if insideInstance and root and sameGroup(cm, root) then return "coords" end
      if anyInstance and (onFloor(cm) or (inInstance and namesInstance(id, m))) then return "instance" end
      return nil
    end
    if ctx.sourceZone and named(ctx.sourceZone(id), names)
      and not (root and ctx.versionOk and ctx.versionOk(root, m) == false) then
      return "source"
    end
    if anyInstance and namesInstance(id, m) then return "instance" end
    return nil
  end

  local out = {}
  for id, m in pairs(ctx.mounts or {}) do
    -- Gate first: owned / other-faction mounts skip every lookup.
    local owned = false
    if ctx.gate then owned = ctx.gate(id, m) end
    if owned ~= nil and (ctx.showCollected or not owned) then
      local reason = via(id, m)
      if reason then
        out[#out + 1] = { id = id, m = m, owned = owned and true or false, via = reason }
      end
    end
  end
  table.sort(out, function(a, b)
    local na, nb = string.lower(a.m.name or ""), string.lower(b.m.name or "")
    if na ~= nb then return na < nb end
    return a.id < b.id
  end)
  if byName then return out, { name = zoneName } end
  return out, { mapID = root, name = zoneName, instance = insideInstance }
end

-- The journal instance of a floor (a UI map finer than a zone: dungeon,
-- micro, orphan) that is not the player's own: the entrances listed on the
-- maps above it (ctx.entrances), the one whose instance's first floor
-- (ctx.instanceUiMap) is this map or in its map group (ctx.mapGroup).
-- -> journalInstanceID or nil.
function Zone.InstanceForFloor(mapID, ctx)
  if not (mapID and ctx.entrances and ctx.instanceUiMap and ctx.mapInfo) then return nil end
  local group = ctx.mapGroup and ctx.mapGroup(mapID) or nil
  local current, seen = mapID, { [mapID] = true }
  for _ = 1, MAX_STEPS do
    local i = ctx.mapInfo(current)
    local parent = type(i) == "table" and i.parentMapID or nil
    if not parent or parent == 0 or seen[parent] then return nil end
    seen[parent] = true
    local list = ctx.entrances(parent)
    if type(list) == "table" then
      for _, entrance in ipairs(list) do
        local jid = type(entrance) == "table" and entrance.journalInstanceID or nil
        local floor = jid and ctx.instanceUiMap(jid) or nil
        if floor and (floor == mapID or (group ~= nil and ctx.mapGroup(floor) == group)) then return jid end
      end
    end
    local pi = ctx.mapInfo(parent)
    if type(pi) ~= "table" or type(pi.mapType) ~= "number" or pi.mapType <= CONTINENT then return nil end
    current = parent
  end
  return nil
end

-- Whether a mount known only by its source text's zone name belongs in the
-- zone version `rootMapID` (Data.ZoneVersions: zone maps sharing a name ->
-- { g = name group, e = expansion index }). expIndex: the mount's expansion
-- (0 Classic ... ; nil: none). A zone without versions, or a mount without
-- an expansion: true. When a version of the mount's expansion exists, only
-- that one; else any version not newer than the mount (or of unknown
-- expansion).
function Zone.VersionOk(versions, rootMapID, expIndex)
  local v = type(versions) == "table" and versions[rootMapID] or nil
  if type(v) ~= "table" or expIndex == nil then return true end
  for _, other in pairs(versions) do
    if type(other) == "table" and other.g == v.g and other.e == expIndex then
      return v.e == expIndex
    end
  end
  return v.e == nil or v.e <= expIndex
end

-- The Journal's gate (Journal.Gate: known to this client, the player's
-- faction, obtainable or owned) as a ctx.gate: fn(id, m) -> owned or nil.
function Zone.Gate(isOwned, exists, faction)
  return function(id, m)
    return ns.Journal.Gate(id, m, isOwned, exists, faction)
  end
end
