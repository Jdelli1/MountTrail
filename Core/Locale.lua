local ADDON, ns = ...

-- Missing keys fall back to the key itself, so English strings are the keys.
ns.L = setmetatable({}, {
  __index = function(_, key) return key end,
})

local L = ns.L

-- Route
L["Hearthstone to %s"] = "Hearthstone to %s"
L["your capital"] = "your capital"
L["Start in %s"] = "Start in %s"
