local ADDON, ns = ...

-- Daily / weekly lockout checklist (the Checklist tab): every
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

-- Stable text of a difficulties list (nested lists too): { {3,4}, 5 } -> "{3,4},5".
local function listText(list)
  if type(list) ~= "table" then return tostring(list) end
  local parts = {}
  for i, v in ipairs(list) do
    parts[i] = type(v) == "table" and ("{" .. listText(v) .. "}") or tostring(v)
  end
  return table.concat(parts, ",")
end

-- Identity of the lockout a spec spends, so entries sharing one kill become
-- one checklist entry: "boss:<route boss>" when a per-boss spec
-- (Data.BossLockouts, `bossLockouts`) governs the route boss, else the
-- instance spec's signature (instance, boss, difficulties, reset), else
-- "quest:<id>" / "lfg:<id>". Manual specs (hand ticks per mount) and
-- anything else -> nil: never grouped.
function Checklist.LockoutKey(spec, routeBoss, bossLockouts)
  if type(spec) ~= "table" or spec.manual or spec.camp then return nil end
  if routeBoss and type(bossLockouts) == "table" and bossLockouts[routeBoss] then
    return "boss:" .. tostring(routeBoss)
  end
  if spec.instance then
    return "instance:" .. tostring(spec.instance) .. "|" .. tostring(spec.boss)
      .. "|" .. listText(spec.difficulties) .. "|" .. tostring(spec.reset)
  end
  if spec.quest then return "quest:" .. tostring(spec.quest) end
  if spec.lfg then return "lfg:" .. tostring(spec.lfg) end
  return nil
end

local function rankOf(list)
  local rank = {}
  for i, key in ipairs(list or {}) do rank[key] = i end
  return rank
end

-- Lockout categories, in display order (F14): the third checklist level.
local CATEGORIES = { "raids", "dungeons", "worldbosses", "rares", "holidays", "other" }
local CATEGORY_LABELS = {
  raids = "Raids", dungeons = "Dungeons", worldbosses = "World bosses",
  rares = "Rares", holidays = "Holidays", other = "Other",
}
local CATEGORY_RANK = rankOf(CATEGORIES)
Checklist.CATEGORIES = CATEGORIES

-- Rare Spawns with no lockout (camp specs, Lockouts.IsCamp): their own
-- top-level group after Daily and Weekly, and their own filter key.
local CAMP = "camp"
Checklist.CAMP = CAMP
-- The Filter menu's keys: the lockout categories, then the camp group.
Checklist.FILTERS = { "raids", "dungeons", "worldbosses", "rares", "holidays", "other", CAMP }

-- Localised label of a category key ("raids" -> "Raids").
function Checklist.CategoryLabel(key)
  return L[CATEGORY_LABELS[key] or CATEGORY_LABELS.other]
end

-- Raid difficulty IDs (legacy 10/25 normal / heroic, 40-player, flexible,
-- Normal / Heroic / Mythic / LFR, Timewalking raid).
local RAID_DIFFICULTIES = {
  [3] = true, [4] = true, [5] = true, [6] = true, [7] = true, [9] = true,
  [14] = true, [15] = true, [16] = true, [17] = true, [33] = true,
}

local function anyRaidDifficulty(list)
  if type(list) ~= "table" then return RAID_DIFFICULTIES[list] == true end
  for _, d in ipairs(list) do
    if anyRaidDifficulty(d) then return true end
  end
  return false
end

-- Category of a lockout: an LFG flag or a holiday mount (`holiday` key, or
-- a holiday-tab mount) -> "holidays"; a spec's own `category` (one of
-- Checklist.CATEGORIES) next; an instance spec -> "raids" when any
-- difficulty is a raid one, else "dungeons"; anything else from the mount's
-- journal section (raid / dungeon) or SimpleArmory group ("World Boss" ->
-- "worldbosses", a rare-spawn group -> "rares", Lockouts.IsRareGroup);
-- else "other".
function Checklist.Category(spec, m, holiday)
  m = type(m) == "table" and m or {}
  spec = type(spec) == "table" and spec or {}
  if holiday or spec.lfg or m.tab == "holiday" then return "holidays" end
  -- A spec's own category (e.g. a covenant rare SimpleArmory files under a vendor).
  if spec.category and CATEGORY_RANK[spec.category] then return spec.category end
  if spec.instance then
    return anyRaidDifficulty(spec.difficulties) and "raids" or "dungeons"
  end
  if m.section == "raid" then return "raids" end
  if m.section == "dungeon" then return "dungeons" end
  if m.group == "World Boss" then return "worldbosses" end
  local Lockouts = ns.Lockouts
  if Lockouts and Lockouts.IsRareGroup and Lockouts.IsRareGroup(m.group) then return "rares" end
  return "other"
end

-- Whether `filters` ({ [category] = false }, only hidden ones stored:
-- ns.db.char.checklistFilters) shows `category` (nil counts as "other").
function Checklist.Shown(filters, category)
  if type(filters) ~= "table" then return true end
  return filters[category or "other"] ~= false
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
--   bossLockouts Data.BossLockouts (route boss -> spec), for lockout identity
-- Members: one per route (mount, boss) pair whose spec exists (first in
-- depth-first order per key; route nodes / bosses that are unavailable or for
-- the other faction are skipped), then every mount with a spec the route
-- does not name at all (boss nil). Holiday mounts only while their holiday is
-- active. Owned mounts and mounts the gate excludes are left out.
-- Members spending the same lockout (Checklist.LockoutKey: e.g. every
-- Vault of Archavon watcher's rows) are ONE entry: one kill, one state, one row.
-- Camp specs (rare spawns with no kill flag, Lockouts.IsCamp) go to a third
-- list, `camp`: entries with state = reset = category = "camp", done = false,
-- zone = the spec's zone, never grouped, sorted by expansion, zone (none
-- last), name.
-- -> { daily = { entry }, weekly = { entry }, camp = { entry } }; entry = { id= (first member),
-- m=, boss=, title= (route node), holiday= (key), key= (first member's tick
-- key), spec=, reset=, state=, done=, auto= (done by the game), locked=,
-- lockedText=, name=, exp= (the spec's `exp`, else the first member's;
-- nil when unknown), expRank=, category= (Checklist.Category of the spec and
-- the first member), mounts= { member ids, data order }, names= { their
-- display names }, grouped= (#mounts > 1) }. A grouped entry's name is its
-- boss (route boss, else the spec's boss, else the holiday's title, else the
-- first mount's name). A spec without a reset files under daily (as hand
-- ticks default to daily). Sorted: not done first, then expansion order (the
-- spec's `exp` when it has one, e.g. a per-boss spec, else the first
-- member's), then name (case-insensitive), id, route order.
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

  local out = { daily = {}, weekly = {}, camp = {} }
  local seen, order = {}, 0
  local groups = {} -- Checklist.LockoutKey -> entry

  local function add(id, boss, title)
    local m = mounts[id]
    if not m then return end
    local spec = specFor(id, boss)
    -- No spec, or repeatable content with no lockout (e.g. Stratholme, run
    -- as often as you like): nothing to do "today", so not on the checklist.
    if not spec or spec.repeatable then return end
    local key = keyOf(id, boss)
    if seen[key] then return end
    local holiday = holidayOf(id, m)
    if holiday and not active[holiday] then return end
    local owned = false
    if ctx.gate then owned = ctx.gate(id, m) end
    if owned == nil or owned then return end
    seen[key] = true
    local name = (ctx.nameOf and ctx.nameOf(id, m)) or m.name or tostring(id)
    if spec.camp then
      -- A rare spawn with no kill flag and no reset: never done, never
      -- grouped, listed until the mount is owned (the gate above).
      order = order + 1
      local exp = spec.exp or m.exp
      local camp = out.camp
      camp[#camp + 1] = {
        id = id, m = m, boss = boss, title = title, key = key, spec = spec,
        reset = CAMP, state = CAMP, done = false, auto = false, locked = false,
        name = name, order = order, exp = exp, expRank = rank[exp] or unknownRank,
        category = CAMP, zone = spec.zone, mounts = { id }, names = { name }, grouped = false,
      }
      return
    end
    -- Another member of a lockout already listed: one kill, one entry.
    local lockout = Checklist.LockoutKey(spec, boss, ctx.bossLockouts)
    local group = lockout and groups[lockout]
    if group then
      group.mounts[#group.mounts + 1] = id
      group.names[#group.names + 1] = name
      return
    end
    order = order + 1
    local state = stateOf(id, boss) or "open"
    local req = spec.requires
    local locked = (req and not (ctx.isQuestDone and ctx.isQuestDone(req.quest))) and true or false
    local reset = spec.reset == "weekly" and "weekly" or "daily"
    local list = out[reset]
    -- The lockout's expansion: a per-boss spec's own `exp`, else the mount's.
    local exp = spec.exp or m.exp
    local entry = {
      id = id, m = m, boss = boss, title = title, holiday = holiday, key = key,
      spec = spec, reset = reset, state = state,
      done = state == "done" or state == "manual-done",
      auto = state == "done",
      locked = locked, lockedText = locked and req.text or nil,
      name = name, order = order,
      exp = exp, expRank = rank[exp] or unknownRank,
      category = Checklist.Category(spec, m, holiday),
      mounts = { id }, names = { name }, grouped = false,
    }
    list[#list + 1] = entry
    if lockout then groups[lockout] = entry end
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

  -- A lockout that drops several mounts is named after its boss.
  for _, reset in ipairs(RESETS) do
    for _, e in ipairs(out[reset]) do
      if #e.mounts > 1 then
        e.grouped = true
        local boss = (e.boss ~= "" and e.boss) or e.spec.boss
        local h = e.holiday and ctx.holidays and ctx.holidays[e.holiday]
        e.name = boss or (h and h.title and L[h.title]) or e.name
      end
    end
  end

  local function before(a, b)
    if a.done ~= b.done then return not a.done end
    if a.expRank ~= b.expRank then return a.expRank < b.expRank end
    local na, nb = string.lower(a.name), string.lower(b.name)
    if na ~= nb then return na < nb end
    if a.id ~= b.id then return a.id < b.id end
    return a.order < b.order
  end
  for _, reset in ipairs(RESETS) do table.sort(out[reset], before) end
  -- Camp entries: expansion order, then zone (none last), then name.
  table.sort(out.camp, function(a, b)
    if a.expRank ~= b.expRank then return a.expRank < b.expRank end
    if (a.zone == nil) ~= (b.zone == nil) then return b.zone == nil end
    if a.zone and a.zone ~= b.zone then return string.lower(a.zone) < string.lower(b.zone) end
    return before(a, b)
  end)
  return out
end

-- Checklist.Build output -> ScrollBox rows, three collapsible levels above
-- the entries: reset -> expansion -> category (F14).
--   Per non-empty reset group (daily, then weekly) a header { header = true,
--   depth = 1, key = "checklist|<reset>", reset =, text = opts.label(reset)
--   (default "Daily" / "Weekly"), owned = done count, total =, collapsed = }
--   (owned / total as UI.HeaderText reads them).
--   Unless collapsed, one expansion sub-header per expansion with an entry
--   still to do (F4's sub-header rows): { header = true, depth = 2, key =
--   "checklist|<reset>|<exp>", reset =, exp =, text = the expansion, owned =,
--   total =, collapsed = }, in expansion order (entry.expRank: Data.Expansions
--   order, unknown ones after by name, entries without an expansion last as
--   "Other"). A group whose only expansion is "Other" has no expansion level:
--   its categories hang under the reset header.
--   Unless collapsed, one category header per category with an entry still
--   to do: { header = true, depth = parent depth + 1, key =
--   "checklist|<reset>|<exp or Other>|<category>", reset =, exp =, category =,
--   text = Checklist.CategoryLabel, owned =, total =, collapsed = }, in
--   Checklist.CATEGORIES order. A lone category still gets its header, except
--   a lone "other": those entries hang under the parent header.
--   Unless collapsed, its entries still to do as { id=, m=, entry=, done=,
--   depth = the parent header's depth (nil right under a reset header) }
--   (entries already sorted).
-- Done entries are never listed: they disappear on their own, while every
-- header counts them. opts.collapsed = { [key] = true }; opts.filters =
-- { [category] = false } (ns.db.char.checklistFilters, Checklist.Shown):
-- hidden categories' entries are left out of the rows and of every count.
-- opts.status(entry) -> text or nil (F17, event rares' live status): each
-- entry row carries its text as `status`, and a header (any level) carries
-- it too when every entry still to do under it has the same text.
local OTHER = "Other"

-- The status text every open entry of `entries` shares, else nil.
local function sharedStatus(entries, statusOf)
  if not statusOf then return nil end
  local text
  for _, e in ipairs(entries) do
    if not e.done then
      local s = statusOf(e)
      if s == nil or (text ~= nil and s ~= text) then return nil end
      text = s
    end
  end
  return text
end

local function expGroups(list)
  local groups, byKey = {}, {}
  for _, e in ipairs(list) do
    local exp = e.exp
    local gkey = exp or OTHER
    local group = byKey[gkey]
    if not group then
      group = { key = gkey, exp = exp, rank = e.expRank or math.huge, entries = {}, done = 0, open = 0 }
      byKey[gkey] = group
      groups[#groups + 1] = group
    end
    group.entries[#group.entries + 1] = e
    if e.done then group.done = group.done + 1 else group.open = group.open + 1 end
  end
  table.sort(groups, function(a, b)
    if (a.exp == nil) ~= (b.exp == nil) then return b.exp == nil end
    if a.rank ~= b.rank then return a.rank < b.rank end
    return string.lower(a.key) < string.lower(b.key)
  end)
  return groups
end

-- Entries -> category groups in Checklist.CATEGORIES order (an unknown or
-- missing category counts as "other").
local function categoryGroups(entries)
  local groups, byKey = {}, {}
  for _, e in ipairs(entries) do
    local key = CATEGORY_RANK[e.category] and e.category or "other"
    local group = byKey[key]
    if not group then
      group = { key = key, entries = {}, done = 0, open = 0 }
      byKey[key] = group
      groups[#groups + 1] = group
    end
    group.entries[#group.entries + 1] = e
    if e.done then group.done = group.done + 1 else group.open = group.open + 1 end
  end
  table.sort(groups, function(a, b) return CATEGORY_RANK[a.key] < CATEGORY_RANK[b.key] end)
  return groups
end

-- Groups with an entry still to do (the others get no header).
local function withOpen(groups)
  local shown = {}
  for _, group in ipairs(groups) do
    if group.open > 0 then shown[#shown + 1] = group end
  end
  return shown
end

-- Camp entries (Checklist.Build's `camp` list, entries already sorted) ->
-- zone groups in entry order: { { key = zone or "Other", zone =, entries = } }.
local function zoneGroups(entries)
  local groups, byKey = {}, {}
  for _, e in ipairs(entries) do
    local gkey = e.zone or OTHER
    local group = byKey[gkey]
    if not group then
      group = { key = gkey, zone = e.zone, entries = {} }
      byKey[gkey] = group
      groups[#groups + 1] = group
    end
    group.entries[#group.entries + 1] = e
  end
  return groups
end

-- The "Rare Spawns (no lockout)" group (camp specs) after Daily and Weekly:
-- a header { header = true, depth = 1, key = "checklist|camp", camp = true,
-- text = opts.label("camp") or "Rare Spawns (no lockout)", left = mounts
-- left, collapsed = }, then per expansion { depth = 2, key =
-- "checklist|camp|<exp or Other>", exp =, left = } and per zone (the source
-- text's Zone, none = "Other") { depth = 3, key = "checklist|camp|<exp>|<zone>",
-- zone =, left = }, then its entries { id=, m=, entry=, done = false, camp =
-- true, depth = 3 }. No done/total (nothing here is ever done: `left` counts
-- the mounts still to get). Hidden by filters.camp = false.
local function addCamp(rows, built, collapsed, filters, opts)
  local list = (built and built.camp) or {}
  if #list == 0 or not Checklist.Shown(filters, CAMP) then return end
  local key = "checklist|" .. CAMP
  local isCollapsed = collapsed[key] == true
  rows[#rows + 1] = {
    header = true, depth = 1, key = key, reset = CAMP, camp = true,
    text = opts.label and opts.label(CAMP) or L["Rare Spawns (no lockout)"],
    left = #list, collapsed = isCollapsed,
  }
  if isCollapsed then return end
  for _, group in ipairs(expGroups(list)) do
    local gkey = key .. "|" .. group.key
    local gCollapsed = collapsed[gkey] == true
    rows[#rows + 1] = {
      header = true, depth = 2, key = gkey, reset = CAMP, camp = true, exp = group.exp,
      text = L[group.key], left = #group.entries, collapsed = gCollapsed,
    }
    if not gCollapsed then
      for _, zone in ipairs(zoneGroups(group.entries)) do
        local zkey = gkey .. "|" .. zone.key
        local zCollapsed = collapsed[zkey] == true
        rows[#rows + 1] = {
          header = true, depth = 3, key = zkey, reset = CAMP, camp = true, exp = group.exp,
          zone = zone.zone, text = zone.zone or L[OTHER], left = #zone.entries, collapsed = zCollapsed,
        }
        if not zCollapsed then
          for _, e in ipairs(zone.entries) do
            rows[#rows + 1] = { id = e.id, m = e.m, entry = e, done = false, camp = true, depth = 3 }
          end
        end
      end
    end
  end
end

function Checklist.Rows(built, opts)
  opts = opts or {}
  local collapsed = opts.collapsed or {}
  local filters = opts.filters
  local statusOf = type(opts.status) == "function" and opts.status or nil
  local rows = {}
  local function addEntries(entries, depth)
    for _, e in ipairs(entries) do
      if not e.done then
        rows[#rows + 1] = { id = e.id, m = e.m, entry = e, done = e.done, depth = depth,
          status = statusOf and statusOf(e) or nil }
      end
    end
  end
  -- The category level under the header at `depth` keyed `key`.
  local function addCategories(entries, depth, key, reset, exp)
    local shown = withOpen(categoryGroups(entries))
    if #shown == 1 and shown[1].key == "other" then
      addEntries(shown[1].entries, depth > 1 and depth or nil)
      return
    end
    for _, group in ipairs(shown) do
      local ckey = key .. "|" .. group.key
      local cCollapsed = collapsed[ckey] == true
      rows[#rows + 1] = {
        header = true, depth = depth + 1, key = ckey, reset = reset, exp = exp, category = group.key,
        text = Checklist.CategoryLabel(group.key), owned = group.done, total = #group.entries,
        collapsed = cCollapsed, status = sharedStatus(group.entries, statusOf),
      }
      if not cCollapsed then addEntries(group.entries, depth + 1) end
    end
  end
  for _, reset in ipairs(RESETS) do
    local list = {}
    for _, e in ipairs((built and built[reset]) or {}) do
      if Checklist.Shown(filters, e.category) then list[#list + 1] = e end
    end
    if #list > 0 then
      local done = 0
      for _, e in ipairs(list) do if e.done then done = done + 1 end end
      local key = "checklist|" .. reset
      local isCollapsed = collapsed[key] == true
      rows[#rows + 1] = {
        header = true, depth = 1, key = key, reset = reset,
        text = opts.label and opts.label(reset) or L[LABELS[reset]],
        owned = done, total = #list, collapsed = isCollapsed, status = sharedStatus(list, statusOf),
      }
      if not isCollapsed then
        local shown = withOpen(expGroups(list))
        if #shown == 1 and shown[1].exp == nil then
          addCategories(shown[1].entries, 1, key .. "|" .. OTHER, reset, nil)
        else
          for _, group in ipairs(shown) do
            local gkey = key .. "|" .. group.key
            local gCollapsed = collapsed[gkey] == true
            rows[#rows + 1] = {
              header = true, depth = 2, key = gkey, reset = reset, exp = group.exp,
              text = L[group.key], owned = group.done, total = #group.entries,
              collapsed = gCollapsed, status = sharedStatus(group.entries, statusOf),
            }
            if not gCollapsed then addCategories(group.entries, 2, gkey, reset, group.exp) end
          end
        end
      end
    end
  end
  addCamp(rows, built, collapsed, filters, opts)
  return rows
end

-- Mounts left in the camp group (rare spawns with no lockout) of a
-- Checklist.Build output, 0 when `filters` hides it.
function Checklist.CampLeft(built, filters)
  if not Checklist.Shown(filters, CAMP) then return 0 end
  return #((built and built.camp) or {})
end

-- Entries of a Checklist.Build output not done yet, in the categories
-- `filters` shows (Checklist.Shown; nil = all).
function Checklist.Remaining(built, filters)
  local n = 0
  for _, reset in ipairs(RESETS) do
    for _, e in ipairs((built and built[reset]) or {}) do
      if not e.done and Checklist.Shown(filters, e.category) then n = n + 1 end
    end
  end
  return n
end
