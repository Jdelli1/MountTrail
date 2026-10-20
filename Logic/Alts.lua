local ADDON, ns = ...

-- Alt lockout matrix: which of the player's characters still has each mount
-- lockout open this week / today. Reads every character's AceDB section
-- (char.seen: who it is and when its stored lockouts go stale, written by
-- ns.RecordSeen; char.last: its last lockout observation; char.ticks: its
-- hand ticks) and builds the Checklist (Logic/Checklist.lua) once per
-- character with that character's faction and lockout state.
-- Pure Lua, no WoW API: the caller injects the saved sections, the clock and
-- the Checklist context (UI/AltsWindow.lua builds them).
local Alts = {}
ns.Alts = Alts

local L = ns.L

local RESETS = { "weekly", "daily" } -- the matrix is about the week: weeklies first
local LABELS = { daily = "Daily", weekly = "Weekly" }
local OTHER = "Other"

-- Cell states.
Alts.DONE, Alts.OPEN, Alts.NA, Alts.UNKNOWN = "done", "open", "na", "unknown"

-- "Name - Realm" (AceDB's char key) -> "Name", "Realm".
local function splitKey(key)
  local name, realm = string.match(tostring(key), "^(.-) %- (.+)$")
  return name or tostring(key), realm
end

-- charSections: AceDB's raw ns.db.sv.char ({ ["Name - Realm"] = section }).
-- -> characters, hiddenCount. Only sections with a `seen` table (stamped by
-- ns.RecordSeen) are listed; the keys in `hidden` ({ [key] = true },
-- ns.db.global.altsHidden) are left out and counted. Each character:
-- { key, name, realm, class (class file, e.g. "MAGE"), faction, level, seen,
-- last (nil until a lockout observation was stored), ticks, current (the
-- character logged in), dailyStale / weeklyStale (`now` is past the reset
-- that followed its last observation) }. The current character first, then
-- by name (case-insensitive), realm, key.
function Alts.Characters(charSections, now, currentKey, hidden)
  local list, hiddenCount = {}, 0
  now = tonumber(now) or 0
  for key, section in pairs(type(charSections) == "table" and charSections or {}) do
    local seen = type(section) == "table" and section.seen or nil
    if type(seen) == "table" then
      if type(hidden) == "table" and hidden[key] then
        hiddenCount = hiddenCount + 1
      else
        local keyName, keyRealm = splitKey(key)
        list[#list + 1] = {
          key = key,
          name = seen.name or keyName,
          realm = seen.realm or keyRealm,
          class = seen.class,
          faction = seen.faction,
          level = seen.level,
          seen = seen,
          last = type(section.last) == "table" and section.last or nil,
          ticks = type(section.ticks) == "table" and section.ticks or {},
          current = key == currentKey,
          dailyStale = type(seen.dailyReset) ~= "number" or now >= seen.dailyReset,
          weeklyStale = type(seen.weeklyReset) ~= "number" or now >= seen.weeklyReset,
        }
      end
    end
  end
  table.sort(list, function(a, b)
    if a.current ~= b.current then return a.current end
    local na, nb = string.lower(tostring(a.name)), string.lower(tostring(b.name))
    if na ~= nb then return na < nb end
    local ra, rb = string.lower(tostring(a.realm or "")), string.lower(tostring(b.realm or ""))
    if ra ~= rb then return ra < rb end
    return tostring(a.key) < tostring(b.key)
  end)
  return list, hiddenCount
end

-- Checklist stateOf for character `char` (Alts.Characters) at `now`, from
-- what it stored: Lockouts.State over char.last (snapshot, quest and LFG
-- flags), plus its hand ticks for manual specs (UI.RouteContext's rule: a
-- game-tracked lockout is done only when the game said so). A lockout whose
-- reset has passed since the observation (char.dailyStale / weeklyStale by
-- the spec's reset; no reset counts as daily) is open again; hand ticks
-- expire by themselves (Resets.IsTicked). specFor(id, boss) -> spec
-- (Lockouts.SpecFor), keyOf(id, boss) -> tick key (UI.RouteTickKey).
function Alts.StateOf(char, now, specFor, keyOf)
  local last = char and char.last or {}
  local quests, lfg = last.quests or {}, last.lfg or {}
  local ticks = char and char.ticks or {}
  keyOf = keyOf or function(id) return id end
  return function(mountID, routeBoss)
    local spec = specFor(mountID, routeBoss)
    local state = ns.Lockouts.State(spec, last.snap,
      function(id) return quests[id] == true end,
      function(id) return lfg[id] == true end)
    if state == "done" then
      local stale = char.dailyStale
      if spec and spec.reset == "weekly" then stale = char.weeklyStale end
      return stale and "open" or "done"
    end
    if state ~= "manual" then return "open" end
    if ns.Resets.IsTicked(ticks, keyOf(mountID, routeBoss), now) then return "manual-done" end
    return "manual-open"
  end
end

local function copy(t)
  local out = {}
  for k, v in pairs(t or {}) do out[k] = v end
  return out
end

-- Identity of a matrix row: the lockout an entry spends
-- (Checklist.LockoutKey: one row per kill whichever member a faction's
-- checklist lists first), else the entry's tick key.
local function rowKey(entry, bossLockouts)
  local lockout = ns.Checklist.LockoutKey(entry.spec, entry.boss, bossLockouts)
  return lockout or entry.key
end

-- ctx:
--   characters  Alts.Characters' list (columns)
--   now         epoch seconds
--   checklist   a Checklist.Build context without faction / stateOf / gate
--               (UI.ChecklistContext's other fields: tree, mounts, specFor,
--               holidays, active, expansions, keyOf, bossLockouts, nameOf)
--   gate(id, m, faction) -> owned boolean or nil (Journal.Gate with the
--               account-wide owned / exists lookups and that faction)
--   filters     { [category] = false } (Checklist.Shown), optional
-- -> rows: one per daily / weekly lockout any character's checklist lists
-- (camp entries are not lockouts: left out), { key, name, entry (the first
-- character's entry), reset, exp, expRank, category, cells = { [charKey] =
-- "done" | "open" | "na" (that character's faction has no such lockout) |
-- "unknown" (no observation stored yet) }, open = characters still open }.
-- Sorted by reset (weekly first: the matrix is about the week), expansion
-- order, name (case-insensitive), key.
function Alts.Build(ctx)
  ctx = ctx or {}
  local chars = ctx.characters or {}
  local base = ctx.checklist or {}
  local now = ctx.now or 0
  local specFor = base.specFor or function() return nil end
  local rows, byKey = {}, {}
  for _, char in ipairs(chars) do
    local c = copy(base)
    c.faction = char.faction
    c.stateOf = Alts.StateOf(char, now, specFor, base.keyOf)
    if ctx.gate then
      local faction = char.faction
      c.gate = function(id, m) return ctx.gate(id, m, faction) end
    end
    local built = ns.Checklist.Build(c)
    for _, reset in ipairs(RESETS) do
      for _, e in ipairs(built[reset] or {}) do
        if ns.Checklist.Shown(ctx.filters, e.category) then
          local key = rowKey(e, base.bossLockouts)
          local row = byKey[key]
          if not row then
            row = {
              key = key, name = e.name, entry = e, reset = e.reset, exp = e.exp,
              expRank = e.expRank, category = e.category, cells = {}, open = 0,
            }
            byKey[key] = row
            rows[#rows + 1] = row
          end
          local cell
          if not char.last then
            cell = Alts.UNKNOWN
          else
            cell = e.done and Alts.DONE or Alts.OPEN
          end
          row.cells[char.key] = cell
        end
      end
    end
  end
  -- A character whose checklist does not list a row: not for its faction.
  for _, row in ipairs(rows) do
    local open = 0
    for _, char in ipairs(chars) do
      local cell = row.cells[char.key]
      if cell == nil then row.cells[char.key] = Alts.NA end
      if cell == Alts.OPEN then open = open + 1 end
    end
    row.open = open
  end
  local resetRank = { weekly = 1, daily = 2 }
  table.sort(rows, function(a, b)
    local ra, rb = resetRank[a.reset] or 3, resetRank[b.reset] or 3
    if ra ~= rb then return ra < rb end
    if a.expRank ~= b.expRank then return (a.expRank or math.huge) < (b.expRank or math.huge) end
    local na, nb = string.lower(tostring(a.name)), string.lower(tostring(b.name))
    if na ~= nb then return na < nb end
    return tostring(a.key) < tostring(b.key)
  end)
  return rows
end

-- Alts.Build rows -> display rows: per reset group (weekly, then daily) a
-- header { header = true, depth = 1, key = "alts|<reset>", reset =, text =
-- opts.label(reset) or "Weekly" / "Daily", total = rows, open = rows some
-- character can still do, collapsed = }, then (unless collapsed) per
-- expansion a sub-header { header = true, depth = 2, key =
-- "alts|<reset>|<exp or Other>", exp =, text =, total =, open =, collapsed = }
-- and its rows { row = , depth = 2 } (rows already sorted). opts.collapsed =
-- { [key] = true } (ns.db.global.collapsed).
function Alts.Rows(rows, opts)
  opts = opts or {}
  local collapsed = opts.collapsed or {}
  local out = {}
  for _, reset in ipairs(RESETS) do
    local groups, byExp = {}, {}
    local total, open = 0, 0
    for _, r in ipairs(rows or {}) do
      if r.reset == reset then
        total = total + 1
        if (r.open or 0) > 0 then open = open + 1 end
        local gkey = r.exp or OTHER
        local g = byExp[gkey]
        if not g then
          g = { key = gkey, exp = r.exp, rows = {}, open = 0 }
          byExp[gkey] = g
          groups[#groups + 1] = g
        end
        g.rows[#g.rows + 1] = r
        if (r.open or 0) > 0 then g.open = g.open + 1 end
      end
    end
    if total > 0 then
      local key = "alts|" .. reset
      local isCollapsed = collapsed[key] == true
      out[#out + 1] = {
        header = true, depth = 1, key = key, reset = reset,
        text = opts.label and opts.label(reset) or L[LABELS[reset]],
        total = total, open = open, collapsed = isCollapsed,
      }
      if not isCollapsed then
        for _, g in ipairs(groups) do
          local gkey = key .. "|" .. g.key
          local gCollapsed = collapsed[gkey] == true
          out[#out + 1] = {
            header = true, depth = 2, key = gkey, reset = reset, exp = g.exp,
            text = L[g.key], total = #g.rows, open = g.open, collapsed = gCollapsed,
          }
          if not gCollapsed then
            for _, r in ipairs(g.rows) do out[#out + 1] = { row = r, depth = 2 } end
          end
        end
      end
    end
  end
  return out
end
