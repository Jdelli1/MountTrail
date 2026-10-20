local ADDON, ns = ...

-- Built-in guide (the format: docs/GUIDES.md). It doubles as the example of
-- every feature a guide can use: authors and credits, highlighting, links
-- with tooltips, several points per step, a macro, and done lines. Players
-- can edit a copy, or write and share their own.
ns.GuideTexts = ns.GuideTexts or {}
ns.GuideTexts[#ns.GuideTexts + 1] = [[
#guide Thundering Ruby Cloud Serpent
#mount 517
#author MountTrail
#credit Alani's spawn points from AllTheThings
#credit An example guide: edit a copy to improve it
#description Alani the Stormborn, a rare elite cloud serpent circling the Vale of Eternal Blossoms, drops [mount:517].

-- 1. Getting there: moves on by itself once you are in the Vale.
step Travel to the **Vale of Eternal Blossoms** in Pandaria
  note Any flying mount works; the Vale sits in the middle of Pandaria
  goto 390 56.2 42.6 Vale of Eternal Blossoms
  reach 200

-- 2. The shards: moves on once ten Skyshards are in your bags.
step Kill mobs in the Vale until you have **ten** [item:86547]
  note Skyshards are a **rare** drop from any mob in the Vale
  note Ten of them combine into a [item:86546]
  item 86547 10

-- 3. Finding her: three points on TomTom, the arrow picks the closest.
step Find **Alani**: she flies a loop around the Vale
  note Use the macro to check whether she is near
  goto 390 35.6 26 Alani (north)
  goto 390 38.6 64.6 Alani (south)
  goto 390 56.2 42.6 Alani (east)
  macro /tar Alani

-- 4. The fight.
step Use the [item:86546] near Alani to break her shield, then kill her
  note She is an **elite**: bring a friend or a strong character
  macro /tar Alani

-- 5. The prize: moves on (and finishes) once the mount is yours.
step Loot her: [mount:517] drops every time
  note In a group, make sure the loot goes to you (Master Looter)
  mount 517
]]
