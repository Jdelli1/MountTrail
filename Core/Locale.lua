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
L["/azt arrow - switch the route between list and arrow"] = "/azt arrow - switch the route between list and arrow"
L["Route mode: %s"] = "Route mode: %s"
L["/azt debug - show or hide caught map and arrow errors"] = "/azt debug - show or hide caught map and arrow errors"
L["Debug: on (caught map and arrow errors go to the error handler)"] = "Debug: on (caught map and arrow errors go to the error handler)"
L["Debug: off"] = "Debug: off"
L["Template %s missing, using %s"] = "Template %s missing, using %s"
L["none"] = "none"

-- Map button
L["No map location for %s"] = "No map location for %s"

-- Main window and minimap button
L["AzerothTrail"] = "AzerothTrail"
L["Journal"] = "Journal"
L["Holidays"] = "Holidays"
L["Misc"] = "Misc"
L["Route"] = "Route"
L["Coming soon"] = "Coming soon"
L["Left-click: open/close"] = "Left-click: open/close"
L["Route: %d steps left"] = "Route: %d steps left"

-- Journal home and mount list
L["Back"] = "Back"
L["%d / %d"] = "%d / %d"
L["Map"] = "Map"
L["Collected"] = "Collected"
L["Sources"] = "Sources"
L["Filter"] = "Filter"
L["Check all"] = "Check all"
L["Uncheck all"] = "Uncheck all"
L["No mounts match these filters."] = "No mounts match these filters."
L["Dungeon drops"] = "Dungeon drops"
L["Raid drops"] = "Raid drops"
L["World drops / rares"] = "World drops / rares"
L["Delves"] = "Delves"
L["Treasures & caches"] = "Treasures & caches"
L["Quests"] = "Quests"
L["Zone activities"] = "Zone activities"
L["Reputation"] = "Reputation"
L["Vendors"] = "Vendors"
L["Other"] = "Other"
L["Achievements"] = "Achievements"
L["Professions"] = "Professions"
L["Shop"] = "Shop"
L["Trading Post"] = "Trading Post"
L["Timewalking"] = "Timewalking"
L["Anniversary"] = "Anniversary"

-- Mount tooltip
L["~1 in %d (approx.)"] = "~1 in %d (approx.)"
L["Times farmed: %d"] = "Times farmed: %d"
L["Rarity: %d"] = "Rarity: %d"
L["Lockout: %s"] = "Lockout: %s"
L["Saved"] = "Saved"
L["Available"] = "Available"
L["Manual"] = "Manual"
L["—"] = "—"
L["Ctrl-click to preview"] = "Ctrl-click to preview"
L["Shift-right-click to open the achievement"] = "Shift-right-click to open the achievement"
L["Achievement: %s"] = "Achievement: %s"
L["Achievement: looking up..."] = "Achievement: looking up..."
L["(completed)"] = "(completed)"
L["Progress"] = "Progress"
L["+%d more"] = "+%d more"
L["Can't open achievements in combat"] = "Can't open achievements in combat"

-- Holidays and Misc tabs
L["Active now"] = "Active now"
L["Trading Post — this month"] = "Trading Post — this month"

-- Route tab
L["Weekly reset in %s"] = "Weekly reset in %s"
L["Daily reset in %s"] = "Daily reset in %s"
L["Show completed"] = "Show completed"
L["You have %d lockouts left. Saddle up?"] = "You have %d lockouts left. Saddle up?"
L["%s has reached Oregon. Nothing left to farm until reset."] = "%s has reached Oregon. Nothing left to farm until reset."
L["Your party"] = "Your party"
L["auto"] = "auto"
L["Locked"] = "Locked"

-- Route arrow
L["List"] = "List"
L["Arrow"] = "Arrow"
L["Skip"] = "Skip"
L["via: %s"] = "via: %s"
L["%d yd"] = "%d yd"
L["Arrow unavailable here"] = "Arrow unavailable here"
L["Target is on another continent"] = "Target is on another continent"
L["No waypoint for this step"] = "No waypoint for this step"
L["Skip this step for this session"] = "Skip this step for this session"
