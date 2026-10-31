local ADDON, ns = ...

-- The pure side of a pop-out (split out of UI/Popouts.lua): its saved key
-- and title, its rows (UI.PopoutRows), the mounts "Plot all" plots, the
-- snapping maths (UI.SnapRect, UI.SnapChain), the saved row order
-- (UI.ApplyOrder, UI.MoveKey), the expansion / source groups
-- (UI.PopoutGroups) and the rarity colour of a row's name. No frames here:
-- the windows themselves are UI/Popouts.lua.

local L = ns.L

local UI = ns.UI or {}
ns.UI = UI

local SNAP = 16 -- how close (px) a dropped window must be to snap

-- The saved key of a set: "camp|Legion", "daily|Legion|rares", "daily|all",
-- "zone", "list|3".
function UI.PopoutKey(source)
  if type(source) ~= "table" or not source.kind then return nil end
  if source.kind == "list" then return "list|" .. tostring(source.list) end
  if source.kind == "quick" then return "quick|" .. tostring(source.key) end
  if source.kind == "zone" then return "zone" end
  if source.kind == "zonemounts" then return "zonemounts" end
  if source.all then return source.kind .. "|all" end
  local key = source.kind .. "|" .. tostring(source.exp)
  if source.category then key = key .. "|" .. source.category end
  return key
end

-- The window's title for a set ("Legion rare spawns", "Legion dailies -
-- Rares", a list's name).
function UI.PopoutTitle(source, store)
  if source.kind == "list" then
    local l = store and ns.Lists.Get(store, source.list)
    return l and l.name or L["List"]
  end
  if source.kind == "zone" then return L["Rare Spawns here"] end
  if source.kind == "zonemounts" then
    return string.format(L["Mounts in %s"], source.zoneName or L["this zone"])
  end
  if source.kind == "quick" then
    local q = ns.QuickLists and ns.QuickLists.Get(source.key)
    return q and L[q.name] or L["List"]
  end
  if source.all then
    return L[({ camp = "Rare Spawns", weekly = "Weeklies" })[source.kind] or "Dailies"]
  end
  local exp = L[source.exp or ""] or tostring(source.exp)
  local title
  if source.kind == "camp" then
    title = string.format(L["%s rare spawns"], exp)
  elseif source.kind == "weekly" then
    title = string.format(L["%s weeklies"], exp)
  else
    title = string.format(L["%s dailies"], exp)
  end
  if source.category then title = title .. " \194\183 " .. ns.Checklist.CategoryLabel(source.category) end
  return title
end

local function rareLike(e)
  return e.category == "rares" or e.reset == "camp"
end

-- The name a row shows: the rare's (its spot's NPC) for rare rows, else the
-- entry's (a grouped lockout's boss, else the mount).
local function rowName(e, spots)
  if rareLike(e) then
    return (spots[1] and spots[1].name) or e.boss or e.name or (e.m and e.m.name) or tostring(e.id)
  end
  return e.name or (e.m and e.m.name) or tostring(e.id)
end

-- The rows of a set -> list of { key =, id =, entry =, name =, zone =, done
-- =, camp =, checked = (a rare spawn's last check), spots = Map.Spots, listOnly
-- = (a custom list's mount the Checklist does not track), index = (its place
-- in a custom list) } - open ones first, then by name (a custom list: in its
-- own order) - and how many are left (not done).
-- ctx: { zoneIDs = { [mountID] = true } (kind "zone"), zoneMounts = the
-- zone's mount IDs in the zone panel's order (kind "zonemounts"), campStore =
-- ns.db.char.campChecked, store = the lists store (kind "list"), isOwned =
-- fn(id) }.
function UI.PopoutRows(source, built, ctx)
  ctx = ctx or {}
  local map = ns.Map
  local faction = ns.Game.Faction and ns.Game.Faction() or nil
  local rows, left = {}, 0
  local function add(e, opts)
    local spots = map and map.Spots and map.Spots(e.id, faction) or {}
    local name = (opts and opts.name) or rowName(e, spots)
    local zone = e.zone
    if not zone and spots[1] and ns.Game.MapName then zone = ns.Game.MapName(spots[1].pts[1]) end
    local camp = e.reset == "camp"
    local row = { key = e.key, id = e.id, entry = e, name = name, zone = zone, done = e.done == true,
      camp = camp, spots = spots, listOnly = e.listOnly, index = opts and opts.index }
    if camp and type(ctx.campStore) == "table" then row.checked = ctx.campStore[e.key] end
    if not row.done then left = left + 1 end
    rows[#rows + 1] = row
  end
  local function expOf(e) return e.exp or (e.m and e.m.exp) end
  local kind = source.kind
  if kind == "daily" or kind == "weekly" then
    for _, e in ipairs(built[kind] or {}) do
      if (source.all or expOf(e) == source.exp) and (not source.category or e.category == source.category) then
        add(e)
      end
    end
  elseif kind == "camp" then
    for _, e in ipairs(built.camp or {}) do
      if source.all or expOf(e) == source.exp then add(e) end
    end
  elseif kind == "zone" then
    local ids = ctx.zoneIDs or {}
    for _, reset in ipairs({ "daily", "weekly", "camp" }) do
      for _, e in ipairs(built[reset] or {}) do
        if ids[e.id] and rareLike(e) then add(e) end
      end
    end
  elseif kind == "list" or kind == "quick" or kind == "zonemounts" then
    local ids
    if kind == "zonemounts" then
      ids = ctx.zoneMounts or {}
    elseif kind == "quick" then
      ids = ns.QuickLists and ns.QuickLists.Mounts(source.key) or {}
    else
      local l = ctx.store and ns.Lists.Get(ctx.store, source.list)
      ids = (l and l.mounts) or {}
    end
    -- A mount the Checklist tracks shows its lockout; any other mount of
    -- the list is a plain row (done when collected).
    local byMount = {}
    for _, reset in ipairs({ "daily", "weekly", "camp" }) do
      for _, e in ipairs(built[reset] or {}) do
        for _, id in ipairs(e.mounts or { e.id }) do
          if byMount[id] == nil then byMount[id] = e end
        end
      end
    end
    local mounts = (ns.Data and ns.Data.Mounts) or {}
    for i, id in ipairs(ids) do
      local m = mounts[id]
      local mountName = (ns.Game.MountInfo and ns.Game.MountInfo(id)) or (m and m.name) or tostring(id)
      -- Mounts already known are left out (the Checklist's entries are
      -- not-owned ones already).
      local owned = ctx.isOwned and ctx.isOwned(id) and true or false
      local e = byMount[id]
      if e then
        add(e, { name = mountName, index = i })
      elseif not owned then
        -- A mount the Checklist does not track: a plain row (no box).
        add({ id = id, m = m, key = "list:" .. tostring(id), name = mountName, listOnly = true,
          mounts = { id } }, { name = mountName, index = i })
      end
    end
  end
  table.sort(rows, function(a, b)
    if a.done ~= b.done then return not a.done end
    -- A custom list keeps its own order (the player's: Lists.Move).
    if kind == "list" and a.index and b.index and a.index ~= b.index then return a.index < b.index end
    if a.name ~= b.name then return string.lower(a.name) < string.lower(b.name) end
    return tostring(a.key) < tostring(b.key)
  end)
  return rows, left
end

-- The mounts "Plot all" plots: rows whose box is not ticked (not done,
-- and a rare spawn not marked checked).
function UI.PopoutPlotIDs(rows)
  local ids = {}
  for _, row in ipairs(rows or {}) do
    if not (row.done or (row.camp and row.checked ~= nil)) then ids[#ids + 1] = row.id end
  end
  return ids
end

-- Where a dropped window snaps: rect = { left =, top =, right =, bottom = }
-- (screen units, top > bottom), others = list of such rects (the other
-- open pop-outs, the main window). Edge to edge within `threshold`: under
-- or above another (its left edge too when close), or beside it (its top
-- too when close); the nearest snap wins. -> left, top, or nil.
function UI.SnapRect(rect, others, threshold)
  threshold = threshold or SNAP
  local w, h = rect.right - rect.left, rect.top - rect.bottom
  local best, bestD
  local function try(d, left, top)
    if d <= threshold and (not bestD or d < bestD) then best, bestD = { left, top }, d end
  end
  local function near(a, b) return math.abs(a - b) <= threshold * 2 end
  for _, o in ipairs(others or {}) do
    local overlapX = rect.left < o.right + threshold and rect.right > o.left - threshold
    local overlapY = rect.bottom < o.top + threshold and rect.top > o.bottom - threshold
    if overlapX then
      local left = near(rect.left, o.left) and o.left or rect.left
      try(math.abs(rect.top - o.bottom), left, o.bottom) -- under it
      try(math.abs(rect.bottom - o.top), left, o.top + h) -- above it
    end
    if overlapY then
      local top = near(rect.top, o.top) and o.top or rect.top
      try(math.abs(rect.left - o.right), o.right, top) -- right of it
      try(math.abs(rect.right - o.left), o.left - w, top) -- left of it
    end
  end
  if best then return best[1], best[2] end
  return nil
end

-- The windows that move with `lead` when it is dragged: those snapped under
-- it or to its right (edges within `tolerance`, overlapping), then theirs in
-- turn. rects = { [key] = rect } (UI.SnapRect's rects, `lead` among them).
-- -> sorted list of keys, `lead` not in it.
function UI.SnapChain(lead, rects, tolerance)
  tolerance = tolerance or 2
  local out, seen, queue = {}, { [lead] = true }, { lead }
  while #queue > 0 do
    local cur = rects[table.remove(queue, 1)]
    for k, o in pairs(rects) do
      if not seen[k] and cur then
        local below = math.abs(o.top - cur.bottom) <= tolerance and o.left < cur.right and o.right > cur.left
        local beside = math.abs(o.left - cur.right) <= tolerance and o.bottom < cur.top and o.top > cur.bottom
        if below or beside then
          seen[k] = true
          out[#out + 1] = k
          queue[#queue + 1] = k
        end
      end
    end
  end
  table.sort(out, function(a, b) return tostring(a) < tostring(b) end)
  return out
end

-- Rows in a saved order (Alt-drag): `order` = row keys in the player's order;
-- rows it names come first in that order, the rest after in their own
-- order; done rows stay last either way. -> the rows, re-sorted in place.
function UI.ApplyOrder(rows, order)
  if type(order) ~= "table" or #order == 0 then return rows end
  local rank = {}
  for i, key in ipairs(order) do rank[key] = i end
  local base = {}
  for i, row in ipairs(rows) do base[row] = i end
  table.sort(rows, function(a, b)
    if a.done ~= b.done then return not a.done end
    local ra, rb = rank[a.key], rank[b.key]
    if ra and rb then return ra < rb end
    if ra or rb then return ra ~= nil end
    return base[a] < base[b]
  end)
  return rows
end

-- Rows split by expansion for windows that are not the player's own list
-- -> list of { exp =, rows = { ... }, left = } in expansion order (Data
-- order; unknown last), each group's rows in their given order; one group
-- with exp = nil when the window is a custom list or spans one expansion.
-- The zone's mounts (kind "zonemounts") split by source instead when they
-- span several: { source =, label = (UI.SectionLabel), rows =, left = }.
function UI.PopoutGroups(rows, source, expansions)
  local function expOf(row) return row.entry and (row.entry.exp or (row.entry.m and row.entry.m.exp)) or nil end
  -- The zone's mounts: by source instead (Journal.GroupBySource; Vendors,
  -- Achievements, Dungeon drops, ...), each group labelled.
  if source.kind == "zonemounts" then
    local groups = ns.Journal.GroupBySource(rows, function(row)
      local m = row.entry and row.entry.m
      return m and m.section
    end)
    if #groups > 1 then
      local out = {}
      for i, g in ipairs(groups) do
        local left = 0
        for _, row in ipairs(g.items) do if not row.done then left = left + 1 end end
        out[i] = { source = g.key, label = UI.SectionLabel and UI.SectionLabel(g.key) or g.key, rows = g.items, left = left }
      end
      return out
    end
  end
  -- A custom list groups by expansion only when sorted so (source.byExpansion,
  -- refreshWindow's copy of the source).
  if source.kind ~= "list" or source.byExpansion then
    local seen, n = {}, 0
    for _, row in ipairs(rows) do
      local e = expOf(row) or "?"
      if not seen[e] then seen[e], n = true, n + 1 end
    end
    if n > 1 then
      local rank = {}
      for i, e in ipairs(expansions or (ns.Data and ns.Data.Expansions) or {}) do rank[e] = i end
      local groups, byExp = {}, {}
      for _, row in ipairs(rows) do
        local e = expOf(row) or "?"
        local g = byExp[e]
        if not g then
          g = { exp = expOf(row), rows = {}, left = 0 }
          byExp[e] = g
          groups[#groups + 1] = g
        end
        g.rows[#g.rows + 1] = row
        if not row.done then g.left = g.left + 1 end
      end
      table.sort(groups, function(a, b)
        return (rank[a.exp] or 999) < (rank[b.exp] or 999)
      end)
      return groups
    end
  end
  local left = 0
  for _, row in ipairs(rows) do if not row.done then left = left + 1 end end
  return { { exp = nil, rows = rows, left = left } }
end

-- The order after moving `key` to position `to` among `keys` (the rows as
-- shown) -> new list of keys.
function UI.MoveKey(keys, key, to)
  local out = {}
  for _, k in ipairs(keys) do
    if k ~= key then out[#out + 1] = k end
  end
  to = math.max(1, math.min(to, #out + 1))
  table.insert(out, to, key)
  return out
end

-- The name colour of an open row when "Colour pop-out names by rarity" is on
-- and MountsRarity-2.0 knows the mount (ns.Owners), else nil (the style's).
function UI.PopoutRarityColor(mountID)
  local global = ns.db and ns.db.global
  local settings = global and global.settings
  local owners = ns.Owners
  if not (type(settings) == "table" and settings.rarityColors == true and owners) then return nil end
  local pct = owners.Percent(mountID)
  return pct and owners.Color(pct) or nil
end
