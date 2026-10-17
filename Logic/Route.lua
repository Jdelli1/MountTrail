local ADDON, ns = ...

-- Per-character route: filters the SimpleArmory planner tree (ns.Data.Route)
-- for one character and flattens it depth-first into display rows.
-- Pure Lua, no WoW API: the caller passes faction and predicates in ctx.
local Route = {}
ns.Route = Route

local L = ns.L

local CAPITALS = { Horde = "Orgrimmar", Alliance = "Stormwind" }

-- Faction rule for nodes and bosses alike: an `alliance` entry needs an
-- Alliance character, a `horde` entry a Horde one (Neutral drops both).
local function factionOk(entry, faction)
  if entry.alliance and faction ~= "Alliance" then return false end
  if entry.horde and faction ~= "Horde" then return false end
  return true
end

local function capitalTitle(node, faction)
  local cap = CAPITALS[faction] or L["your capital"]
  -- The route's start step ("Start in ") names the capital itself (R14).
  if node.startStep then return string.format(L["Start in %s"], cap) end
  local title = string.format(L["Hearthstone to %s"], cap)
  local own = node.title and string.match(node.title, "^%s*(.-)%s*$") or ""
  if own ~= "" then title = title .. " " .. own end
  return title
end

-- Owned and unobtainable mounts are not worth routing to.
local function wanted(mountID, ctx)
  if ctx.isOwned and ctx.isOwned(mountID) then return false end
  local mounts = ns.Data and ns.Data.Mounts
  local m = mounts and mounts[mountID]
  if m and m.unobtainable then return false end
  return true
end

-- Access gate: the governing spec's `requires` quest must be done.
local function lockInfo(mountID, bossName, ctx)
  local spec = ns.Lockouts and ns.Lockouts.SpecFor and ns.Lockouts.SpecFor(mountID, bossName)
  local req = spec and spec.requires
  if req and not (ctx.isQuestDone and ctx.isQuestDone(req.quest)) then
    return true, req.text
  end
  return false, nil
end

-- src: { {mount=, boss=, note=, ...} } -> surviving row bosses (may be empty).
local function buildBosses(src, ctx)
  local out = {}
  for _, b in ipairs(src or {}) do
    if not b.unavailable and factionOk(b, ctx.faction) and wanted(b.mount, ctx) then
      local locked, lockedText = lockInfo(b.mount, b.boss, ctx)
      out[#out + 1] = {
        mount = b.mount,
        boss = b.boss,
        note = b.note,
        state = (ctx.stateOf and ctx.stateOf(b.mount)) or "open",
        locked = locked,
        lockedText = lockedText,
      }
    end
  end
  return out
end

-- bosses -> state, auto (rule 4).
local function killState(bosses)
  local allDone, anyAuto, anyManual = true, false, false
  for _, b in ipairs(bosses) do
    if b.state == "done" then
      anyAuto = true
    elseif b.state ~= "manual-done" then
      allDone = false
      if b.state == "manual-open" then anyManual = true end
    end
  end
  if allDone then return "done", anyAuto end
  if anyManual then return "manual", false end
  return "open", false
end

-- Builds a kill row, or nil when nothing is left to show.
local function killRow(title, notes, srcBosses, depth, key, ctx)
  local bosses = buildBosses(srcBosses, ctx)
  if #bosses == 0 then return nil end
  local state, auto = killState(bosses)
  if state == "done" and not ctx.showCompleted then return nil end
  return {
    depth = depth, kind = "kill", key = key,
    title = title, notes = notes, bosses = bosses,
    state = state, auto = auto,
  }
end

-- Appends the rows for `node` (and its subtree) to `out`.
local function walk(node, depth, key, ctx, out)
  if node.unavailable or not factionOk(node, ctx.faction) then return end
  local title = node.title or ""
  if node.capital then title = capitalTitle(node, ctx.faction) end

  local rows = {}
  if node.bosses then
    local row = killRow(title, node.notes, node.bosses, depth, key, ctx)
    if row then rows[1] = row end
  end
  local children = {}
  for i, child in ipairs(node.steps or {}) do
    walk(child, depth + 1, key .. "." .. i, ctx, children)
  end

  if not node.bosses then
    -- Travel row: kept only when a descendant survives (rule 5); "done"
    -- when everything under it is done (only seen with showCompleted).
    if #children == 0 then return end
    local allDone = true
    for _, r in ipairs(children) do
      if r.state ~= "done" then allDone = false; break end
    end
    rows[1] = {
      depth = depth, kind = "travel", key = key,
      title = title, notes = node.notes, bosses = {},
      state = allDone and "done" or "open", auto = false,
    }
  end

  for _, r in ipairs(rows) do out[#out + 1] = r end
  for _, r in ipairs(children) do out[#out + 1] = r end
end

-- tree: ns.Data.Route-shaped node list; ctx: see docs in the plan (faction,
-- isOwned, isQuestDone, stateOf, showCompleted, holidaySteps).
-- -> depth-first rows; active holiday steps first at depth 0 (keys "h<i>").
function Route.Build(tree, ctx)
  ctx = ctx or {}
  local out = {}
  for i, step in ipairs(ctx.holidaySteps or {}) do
    local src = {}
    for j, mountID in ipairs(step.mounts or {}) do src[j] = { mount = mountID } end
    local row = killRow(step.title, nil, src, 0, "h" .. i, ctx)
    if row then out[#out + 1] = row end
  end
  for i, node in ipairs(tree or {}) do
    walk(node, 0, tostring(i), ctx, out)
  end
  return out
end
