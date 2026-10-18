local ADDON, ns = ...

-- Daily / weekly lockout checklist (the Route tab's Checklist view): every
-- lockout this character can still spend on a mount, grouped by reset.
-- Pure Lua, no WoW API: the caller injects the route tree, spec / state
-- lookups and the gate (UI/ChecklistView.lua builds the context).
local Checklist = {}
ns.Checklist = Checklist

local L = ns.L

local RESETS = { "daily", "weekly" }
local LABELS = { daily = "Daily", weekly = "Weekly" }

-- Route faction rule (Logic/Route.lua): an `alliance` entry needs an
-- Alliance character, a `horde` entry a Horde one.
local function factionOk(entry, faction)
  if entry.alliance and faction ~= "Alliance" then return false end
  if entry.horde and faction ~= "Horde" then return false end
  return true
end

-- Every mount the route tree names anywhere (any faction, unavailable nodes
-- too): those mounts are the route's to list or to leave out.
local function routedMounts(tree)
  local seen = {}
  local function walk(node)
    for _, b in ipairs(node.bosses or {}) do
      if b.mount then seen[b.mount] = true end
    end
    for _, child in ipairs(node.steps or {}) do walk(child) end
  end
  for _, node in ipairs(tree or {}) do walk(node) end
  return seen
end

-- mountID -> holiday key, from each holiday's `mounts` list and from
-- holiday-tab mounts whose section is a known holiday.
local function holidayLookup(holidays)
  local byMount = {}
  for key, h in pairs(holidays or {}) do
    if type(h) == "table" then
      for _, id in ipairs(h.mounts or {}) do byMount[id] = key end
    end
  end
  return function(id, m)
    if byMount[id] then return byMount[id] end
    if m and m.tab == "holiday" and m.section and holidays and holidays[m.section] then
      return m.section
    end
    return nil
  end
end

local function rankOf(list)
  local rank = {}
  for i, key in ipairs(list or {}) do rank[key] = i end
  return rank
end

-- ctx (all optional):
--   tree       ns.Data.Route-shaped node list (bosses = { {mount=, boss=} }, steps)
--   mounts     { [id] = m } (ns.Data.Mounts)
--   specFor(id, boss) -> lockout spec or nil (Lockouts.SpecFor)
--   stateOf(id, boss) -> "done" | "manual-done" | "manual-open" | "open"
--              (UI.RouteContext's; boss is nil for mounts outside the route)
--   gate(id, m) -> owned boolean, or nil to leave the mount out
--              (Journal.Gate: client knows it, faction, obtainable); default kept, not owned
--   faction    the player's faction, for the route's alliance / horde flags
--   holidays   ns.Data.Holidays; active = { [holidayKey] = true }
--   expansions ns.Data.Expansions (sort order; unknown / missing after them)
--   keyOf(id, boss) -> tick key (UI.RouteTickKey); entries sharing a key are
--              one lockout (default: the mountID, one entry per mount)
--   isQuestDone(questID) -> bool, for a spec's `requires` unlock
--   nameOf(id, m) -> display name (default m.name)
-- Entries: one per route (mount, boss) pair whose spec exists (first in
-- depth-first order per key; route nodes / bosses that are unavailable or for
-- the other faction are skipped), then every mount with a spec the route
-- does not name at all (boss nil). Holiday mounts only while their holiday is
-- active. Owned mounts and mounts the gate excludes are left out.
-- -> { daily = { entry }, weekly = { entry } }; entry = { id=, m=, boss=,
-- title= (route node), holiday= (key), key=, spec=, reset=, state=, done=,
-- auto= (done by the game), locked=, lockedText=, name= }. A spec without a
-- reset files under daily (as hand ticks default to daily). Sorted: not done
-- first, then expansion order, then name (case-insensitive), id, route order.
function Checklist.Build(ctx)
  ctx = ctx or {}
  local mounts = ctx.mounts or {}
  local specFor = ctx.specFor or function() return nil end
  local stateOf = ctx.stateOf or function() return "open" end
  local keyOf = ctx.keyOf or function(id) return id end
  local active = ctx.active or {}
  local holidayOf = holidayLookup(ctx.holidays)
  local rank = rankOf(ctx.expansions)
  local unknownRank = #(ctx.expansions or {}) + 1

  local out = { daily = {}, weekly = {} }
  local seen, order = {}, 0

  local function add(id, boss, title)
    local m = mounts[id]
    if not m then return end
    local spec = specFor(id, boss)
    if not spec then return end
    local key = keyOf(id, boss)
    if seen[key] then return end
    local holiday = holidayOf(id, m)
    if holiday and not active[holiday] then return end
    local owned = false
    if ctx.gate then owned = ctx.gate(id, m) end
    if owned == nil or owned then return end
    seen[key] = true
    order = order + 1
    local state = stateOf(id, boss) or "open"
    local req = spec.requires
    local locked = (req and not (ctx.isQuestDone and ctx.isQuestDone(req.quest))) and true or false
    local reset = spec.reset == "weekly" and "weekly" or "daily"
    local name = (ctx.nameOf and ctx.nameOf(id, m)) or m.name or tostring(id)
    local list = out[reset]
    list[#list + 1] = {
      id = id, m = m, boss = boss, title = title, holiday = holiday, key = key,
      spec = spec, reset = reset, state = state,
      done = state == "done" or state == "manual-done",
      auto = state == "done",
      locked = locked, lockedText = locked and req.text or nil,
      name = name, order = order,
      expRank = rank[m.exp] or unknownRank,
    }
  end

  local function walk(node)
    if node.unavailable or not factionOk(node, ctx.faction) then return end
    for _, b in ipairs(node.bosses or {}) do
      if b.mount and not b.unavailable and factionOk(b, ctx.faction) then
        add(b.mount, b.boss, node.title)
      end
    end
    for _, child in ipairs(node.steps or {}) do walk(child) end
  end
  for _, node in ipairs(ctx.tree or {}) do walk(node) end

  local routed = routedMounts(ctx.tree)
  local extra = {}
  for id in pairs(mounts) do
    if not routed[id] then extra[#extra + 1] = id end
  end
  table.sort(extra)
  for _, id in ipairs(extra) do add(id, nil, nil) end

  local function before(a, b)
    if a.done ~= b.done then return not a.done end
    if a.expRank ~= b.expRank then return a.expRank < b.expRank end
    local na, nb = string.lower(a.name), string.lower(b.name)
    if na ~= nb then return na < nb end
    if a.id ~= b.id then return a.id < b.id end
    return a.order < b.order
  end
  for _, reset in ipairs(RESETS) do table.sort(out[reset], before) end
  return out
end

-- Checklist.Build output -> ScrollBox rows: per non-empty reset group (daily,
-- then weekly) a header { header = true, depth = 1, key = "checklist|<reset>",
-- reset =, text = opts.label(reset) (default "Daily" / "Weekly"), owned =
-- done count, total =, collapsed = } (owned / total as UI.HeaderText reads
-- them), then unless collapsed its entries still to do as { id=, m=, entry=,
-- done= } (entries already sorted). Done entries are never listed: they
-- disappear on their own, while the header counts span the whole group.
-- opts.collapsed = { [key] = true }.
function Checklist.Rows(built, opts)
  opts = opts or {}
  local collapsed = opts.collapsed or {}
  local rows = {}
  for _, reset in ipairs(RESETS) do
    local list = (built and built[reset]) or {}
    if #list > 0 then
      local done = 0
      for _, e in ipairs(list) do if e.done then done = done + 1 end end
      local key = "checklist|" .. reset
      local isCollapsed = collapsed[key] == true
      rows[#rows + 1] = {
        header = true, depth = 1, key = key, reset = reset,
        text = opts.label and opts.label(reset) or L[LABELS[reset]],
        owned = done, total = #list, collapsed = isCollapsed,
      }
      if not isCollapsed then
        for _, e in ipairs(list) do
          if not e.done then
            rows[#rows + 1] = { id = e.id, m = e.m, entry = e, done = e.done }
          end
        end
      end
    end
  end
  return rows
end

-- Entries of a Checklist.Build output not done yet.
function Checklist.Remaining(built)
  local n = 0
  for _, reset in ipairs(RESETS) do
    for _, e in ipairs((built and built[reset]) or {}) do
      if not e.done then n = n + 1 end
    end
  end
  return n
end
