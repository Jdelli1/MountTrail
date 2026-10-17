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

-- Slash commands and /azt dump
L["No saved instances yet (lockout data arrives shortly after login). Try again in a moment."] = "No saved instances yet (lockout data arrives shortly after login). Try again in a moment."
L["Saved instances (instance ID / difficulty ID):"] = "Saved instances (instance ID / difficulty ID):"
L["killed"] = "killed"
L["alive"] = "alive"
L["The window is not available yet. Type /azt help for commands."] = "The window is not available yet. Type /azt help for commands."
L["Commands:"] = "Commands:"
L["/azt - show or hide the window"] = "/azt - show or hide the window"
L["/azt dump - list saved instances (instance ID, difficulty ID, bosses)"] = "/azt dump - list saved instances (instance ID, difficulty ID, bosses)"
L["/azt help - this list"] = "/azt help - this list"
