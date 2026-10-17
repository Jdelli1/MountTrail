local ADDON, ns = ...

-- Kill statistics for mounts that carry Rarity statistic IDs (Data.Mounts
-- `stats`). The game keeps these per character and retroactively, so for
-- such mounts they replace our own attempt counter in the tooltip's
-- Attempts line (UI.TooltipLines). Pure Lua, no WoW API: callers pass a
-- statistic reader (Game.Statistic) in.
--
-- Saved as ns.db.global.stats = { [charKey] = { [mountID] = kills } }.

local Stats = {}
ns.Stats = Stats

-- Sum of `statistic(id)` over a mount's statistic IDs (e.g. one per
-- difficulty). -> number, or nil (unread) unless every ID gave a number, so
-- a partial sum never replaces a full one.
function Stats.Read(ids, statistic)
  if type(ids) ~= "table" or #ids == 0 then return nil end
  local total = 0
  for _, id in ipairs(ids) do
    local n = statistic(id)
    if type(n) ~= "number" then return nil end
    total = total + n
  end
  return total
end

-- { [mountID] = kills } for every mount with statistics that gave a reading.
function Stats.Collect(mounts, statistic)
  local out = {}
  for mountID, m in pairs(mounts or {}) do
    if type(m) == "table" and m.stats then
      local n = Stats.Read(m.stats, statistic)
      if n then out[mountID] = n end
    end
  end
  return out
end

-- Writes `readings` into store[charKey]; mounts not read this time keep
-- their earlier value. Kill statistics only increase, so a reading below the
-- stored one is ignored: that covers "--" (0) read before the client's
-- statistics load. Tradeoff: a character deleted and recreated with the same
-- name and realm keeps the old character's (higher) count. -> store[charKey].
function Stats.Merge(store, charKey, readings)
  local mine = store[charKey]
  if type(mine) ~= "table" then
    mine = {}
    store[charKey] = mine
  end
  for mountID, n in pairs(readings or {}) do
    local old = mine[mountID]
    if type(old) ~= "number" or n > old then mine[mountID] = n end
  end
  return mine
end

-- -> total over every character, this character's count, and how many
-- characters have a reading. total / mine are nil when there is no reading
-- (no character / not this one).
function Stats.Totals(store, mountID, charKey)
  if type(store) ~= "table" then return nil, nil, 0 end
  local total, mine, chars = nil, nil, 0
  for key, counts in pairs(store) do
    local n = type(counts) == "table" and counts[mountID] or nil
    if type(n) == "number" then
      total, chars = (total or 0) + n, chars + 1
      if key == charKey then mine = n end
    end
  end
  return total, mine, chars
end
