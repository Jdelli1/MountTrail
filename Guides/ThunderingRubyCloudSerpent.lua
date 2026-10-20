local ADDON, ns = ...

-- Built-in guide (Logic/Guide.lua's format). An example of what a guide
-- looks like: players can edit a copy, or write and share their own.
ns.GuideTexts = ns.GuideTexts or {}
ns.GuideTexts[#ns.GuideTexts + 1] = [[
#guide Thundering Ruby Cloud Serpent
#mount 517
#author MountTrail
#description Alani the Stormborn, a rare cloud serpent circling the Vale of Eternal Blossoms. An example guide: edit a copy to improve it.
step Travel to the Vale of Eternal Blossoms in Pandaria
  goto 390 56.2 42.6 Vale of Eternal Blossoms
  reach 200
step Kill mobs in the Vale until you have ten Skyshards
  note Skyshards are a rare drop from any mob in the Vale; ten combine into a Sky Crystal
step Find Alani: she flies a loop around the Vale
  goto 390 35.6 26 Alani
  goto 390 38.6 64.6 Alani
  goto 390 56.2 42.6 Alani
step Use the Sky Crystal near Alani to break her shield, then kill her
  note She is an elite: bring a friend or a strong character
step Loot her: the mount is a rare drop
  mount 517
]]
