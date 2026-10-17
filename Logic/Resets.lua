local ADDON, ns = ...

-- Manual "done" ticks that expire at the next daily/weekly reset.
-- store is a plain table {[key] = expiresAt}, key a mountID (or a route tick
-- key, UI.RouteTickKey); pure Lua, no WoW API.
local Resets = {}
ns.Resets = Resets

function Resets.Expiry(kind, now, untilDaily, untilWeekly)
  if kind == "daily" then return now + untilDaily end
  if kind == "weekly" then return now + untilWeekly end
  error("Resets.Expiry: unknown kind '" .. tostring(kind) .. "' (expected 'daily' or 'weekly')", 2)
end

function Resets.Tick(store, mountID, kind, now, untilDaily, untilWeekly)
  store[mountID] = Resets.Expiry(kind, now, untilDaily, untilWeekly)
end

function Resets.Untick(store, mountID)
  store[mountID] = nil
end

function Resets.IsTicked(store, mountID, now)
  local expires = store[mountID]
  return expires ~= nil and now < expires
end

function Resets.Prune(store, now)
  for id, expires in pairs(store) do
    if expires <= now then store[id] = nil end
  end
end
