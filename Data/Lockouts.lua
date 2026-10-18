-- Hand-written lockout data: mountID -> how this character's chance at the
-- mount is spent and when it comes back (read by Logic/Lockouts.lua). Shapes:
--   { instance=<GetSavedInstanceInfo return 14>, boss="<GetSavedInstanceEncounterInfo name, enUS>",
--     difficulties={ <entry>... }, reset="daily"|"weekly" }
--     Each entry is a difficulty ID or a table of IDs (Ruling R9). A table is one
--     lockout group, satisfied by a kill on ANY of its IDs (difficulties that share
--     one lockout); a plain ID is a group of one. The spec is done when EVERY group
--     is satisfied: { {3,4,5,6} } = one kill on any size/difficulty; { 3, 4 } = a
--     10-player kill AND a 25-player kill (separate lockouts).
--   { quest=<questID>, reset=... }   { lfg=<LFG dungeonID>, reset="daily" }   { manual=true, reset=... }
--   any spec may add requires={ quest=<questID>, text="<unlock needed>" }
--   repeatable=true: no lockout at all (run as often as you like): a route
--   step, never a daily / weekly checklist entry
-- Mounts with a Rarity quest flag (Data/Mounts.lua `quest`) and no entry here are
-- treated as { quest=<that quest>, reset="weekly" } (MoP world bosses, Rukhmar).
--
-- Difficulty IDs: 1 Normal dungeon, 2 Heroic dungeon, 23 Mythic dungeon,
-- 3/4 10/25 Normal legacy raid, 5/6 10/25 Heroic legacy raid, 9 40-player,
-- 14 Normal, 15 Heroic, 16 Mythic, 17 LFR.
-- LFR (17) is not tracked in v1 (Ruling R10): LFR kills are not expected to show up
-- in the saved-instance list, so a spec listing 17 could never complete.
--
-- Boss encounter names and difficulties partly derived from Rarity
-- (https://github.com/WowRarity/Rarity, DB/Mounts/*.lua `lockBossName`,
-- `instanceDifficulties`, `lockDungeonId`), GPL-2.0.
-- Entries marked `-- verify in game` are unconfirmed: check them with `/azt dump`
-- (docs/ingame-checklist.md).

local ADDON, ns = ...
ns.Data = ns.Data or {}

ns.Data.Lockouts = {
  -- Classic / The Burning Crusade -------------------------------------------
  [117] = { manual = true, reset = "weekly" }, -- Blue Qiraji Battle Tank: Ahn'Qiraj trash, no saved encounter
  [118] = { manual = true, reset = "weekly" }, -- Red Qiraji Battle Tank: Ahn'Qiraj trash
  [119] = { manual = true, reset = "weekly" }, -- Yellow Qiraji Battle Tank: Ahn'Qiraj trash
  [120] = { manual = true, reset = "weekly" }, -- Green Qiraji Battle Tank: Ahn'Qiraj trash
  [69]  = { manual = true, reset = "daily", repeatable = true },  -- Rivendare's Deathcharger: Stratholme is normal-only and has no lockout (repeatable: a route step, not a checklist entry)
  [168] = { instance = 532, boss = "Attumen the Huntsman", difficulties = { 3 }, reset = "weekly" }, -- Fiery Warhorse, Karazhan (10-player) -- verify in game
  [183] = { instance = 550, boss = "Kael'thas Sunstrider", difficulties = { 4 }, reset = "weekly" }, -- Ashes of Al'ar, Tempest Keep (25-player) -- verify in game
  [185] = { instance = 556, boss = "Anzu", difficulties = { 2 }, reset = "daily" }, -- Raven Lord, Sethekk Halls -- verify in game
  [213] = { instance = 585, boss = "Kael'thas Sunstrider", difficulties = { 2 }, reset = "daily" }, -- Swift White Hawkstrider, Magisters' Terrace

  -- Wrath of the Lich King ---------------------------------------------------
  [349] = { instance = 249, boss = "Onyxia", difficulties = { 3, 4 }, reset = "weekly" }, -- Onyxian Drake, 10 and 25 are separate lockouts -- verify in game
  [363] = { instance = 631, boss = "The Lich King", difficulties = { 6 }, reset = "weekly" }, -- Invincible, Heroic 25 only
  -- Vault of Archavon: all four bosses drop it; the spec follows Archavon (Rarity's lock boss),
  -- Koralon/Emalon/Toravon rows use BossLockouts below.
  [286] = { instance = 624, boss = "Archavon the Stone Watcher", difficulties = { 3, 4 }, reset = "weekly" }, -- Grand Black War Mammoth (A), 10 and 25 separate -- verify in game
  [287] = { instance = 624, boss = "Archavon the Stone Watcher", difficulties = { 3, 4 }, reset = "weekly" }, -- Grand Black War Mammoth (H), 10 and 25 separate -- verify in game
  [246] = { instance = 616, boss = "Malygos", difficulties = { 3, 4 }, reset = "weekly" }, -- Azure Drake, 10 and 25 are separate lockouts -- verify in game
  [247] = { instance = 616, boss = "Malygos", difficulties = { 3, 4 }, reset = "weekly" }, -- Blue Drake, 10 and 25 are separate lockouts -- verify in game
  [253] = { instance = 615, boss = "Sartharion", difficulties = { 3 }, reset = "weekly" }, -- Black Drake, 10-player, 3 drakes up
  [250] = { instance = 615, boss = "Sartharion", difficulties = { 4 }, reset = "weekly" }, -- Twilight Drake, 25-player, 3 drakes up
  [264] = { instance = 575, boss = "Skadi the Ruthless", difficulties = { 2 }, reset = "daily" }, -- Blue Proto-Drake, Utgarde Pinnacle heroic
  [304] = { instance = 603, boss = "Yogg-Saron", difficulties = { 14 }, reset = "weekly" }, -- Mimiron's Head, Ulduar (Rarity: difficulty 14) -- verify in game
  [248] = { instance = 595, boss = "Infinite Corruptor", difficulties = { 2 }, reset = "daily" }, -- Bronze Drake, Culling of Stratholme timed heroic -- verify in game

  -- Cataclysm ----------------------------------------------------------------
  [395] = { instance = 657, boss = "Altairus", difficulties = { 2 }, reset = "daily" }, -- Drake of the North Wind, Vortex Pinnacle heroic (normal is never saved)
  [397] = { instance = 725, boss = "Slabhide", difficulties = { 2 }, reset = "daily" }, -- Vitreous Stone Drake, Stonecore heroic (normal is never saved)
  -- Cataclysm and Mists raids: all sizes and difficulties share one lockout (Ruling R11).
  [396] = { instance = 754, boss = "Al'Akir", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }, -- Drake of the South Wind, any size or difficulty -- verify in game
  [425] = { instance = 720, boss = "Alysrazor", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }, -- Flametalon of Alysrazor -- verify in game
  [415] = { instance = 720, boss = "Ragnaros", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }, -- Pureblood Fire Hawk -- verify in game
  -- Dragon Soul: one heroic run covers all three (Handmaiden is heroic only).
  [445] = { instance = 967, boss = "Ultraxion", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }, -- Experiment 12-B -- verify in game
  [442] = { instance = 967, boss = "Madness of Deathwing", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }, -- Blazing Drake -- verify in game
  [444] = { instance = 967, boss = "Madness of Deathwing", difficulties = { { 5, 6 } }, reset = "weekly" }, -- Life-Binder's Handmaiden, heroic only -- verify in game
  [411] = { instance = 859, boss = "High Priestess Kilnara", difficulties = { 2 }, reset = "daily" }, -- Swift Zulian Panther, Zul'Gurub heroic
  [410] = { instance = 859, boss = "Bloodlord Mandokir", difficulties = { 2 }, reset = "daily" }, -- Armored Razzashi Raptor, Zul'Gurub heroic
  -- Zul'Aman: the bear is the timed-run chest, not a boss; the daily heroic lockout is tracked via the last boss.
  [419] = { instance = 568, boss = "Daakara", difficulties = { 2 }, reset = "daily" }, -- Amani Battle Bear -- verify in game

  -- Mists of Pandaria (world bosses Galleon, Sha of Anger, Oondasta, Nalak use their Rarity quest) --
  [478] = { instance = 1008, boss = "Elegon", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }, -- Astral Cloud Serpent, any size or difficulty -- verify in game
  [531] = { instance = 1098, boss = "Horridon", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }, -- Spawn of Horridon, Normal/Heroic -- verify in game
  [543] = { instance = 1098, boss = "Ji-Kun", difficulties = { { 3, 4, 5, 6 } }, reset = "weekly" }, -- Clutch of Ji-Kun, Normal/Heroic -- verify in game
  [559] = { instance = 1136, boss = "Garrosh Hellscream", difficulties = { 16 }, reset = "weekly" }, -- Kor'kron Juggernaut, Mythic only

  -- Warlords of Draenor (Rukhmar uses its Rarity quest) ----------------------
  [751] = { instance = 1448, boss = "Archimonde", difficulties = { 16 }, reset = "weekly" }, -- Felsteel Annihilator, Mythic only
  [613] = { instance = 1205, boss = "Blackhand", difficulties = { 16 }, reset = "weekly" }, -- Ironhoof Destroyer, Mythic only

  -- Legion -------------------------------------------------------------------
  [791] = { instance = 1530, boss = "Gul'dan", difficulties = { 14, 15, 16 }, reset = "weekly" }, -- Felblaze Infernal, Normal/Heroic/Mythic
  [633] = { instance = 1530, boss = "Gul'dan", difficulties = { 16 }, reset = "weekly" }, -- Hellfire Infernal, Mythic only
  [899] = { instance = 1676, boss = "Mistress Sassz'ine", difficulties = { 14, 15, 16 }, reset = "weekly" }, -- LFR untracked; Abyss Worm
  [971] = { instance = 1712, boss = "Felhounds of Sargeras", difficulties = { 14, 15, 16 }, reset = "weekly" }, -- LFR untracked; Antoran Charhound
  [954] = { instance = 1712, boss = "Argus the Unmaker", difficulties = { 16 }, reset = "weekly" }, -- Shackled Ur'zul, Mythic only
  -- Return to Karazhan, Mythic only
  [875] = { instance = 1651, boss = "Attumen the Huntsman", difficulties = { 23 }, reset = "weekly" }, -- Midnight
  [883] = { instance = 1651, boss = "Nightbane", difficulties = { 23 }, reset = "weekly" }, -- Smoldering Ember Wyrm (timed reward)

  -- Battle for Azeroth -------------------------------------------------------
  -- G.M.O.D.: Mekkatorque on Normal/Heroic/Mythic; on LFR it drops from Jaina instead (not tracked).
  [1217] = { instance = 2070, boss = "High Tinker Mekkatorque", difficulties = { 14, 15, 16 }, reset = "weekly" }, -- G.M.O.D.
  [1219] = { instance = 2070, boss = "Lady Jaina Proudmoore", difficulties = { 16 }, reset = "weekly" }, -- Glacial Tidestorm, Mythic only -- verify in game
  [995]  = { instance = 1754, boss = "Harlan Sweete", difficulties = { 23 }, reset = "weekly" }, -- Sharkbait, Freehold Mythic
  [1040] = { instance = 1762, boss = "Dazar, The First King", difficulties = { 23 }, reset = "weekly" }, -- Tomb Stalker, King's Rest Mythic
  [1053] = { instance = 1841, boss = "Unbound Abomination", difficulties = { 23 }, reset = "weekly" }, -- Underrot Crawg, Underrot Mythic
  [1252] = { instance = 2097, boss = "HK-8 Aerial Oppression Unit", difficulties = { 23 }, reset = "weekly" }, -- Mechagon Peacekeeper, Mythic
  [1227] = { instance = 2097, boss = "King Mechagon", difficulties = { 23 }, reset = "weekly" }, -- Aerial Unit R-21/X, Mythic hard mode
  [1293] = { instance = 2217, boss = "N'Zoth the Corruptor", difficulties = { 16 }, reset = "weekly" }, -- Ny'alotha Allseer, Mythic only

  -- Shadowlands --------------------------------------------------------------
  [1406] = { instance = 2286, boss = "Nalthor the Rimebinder", difficulties = { 23 }, reset = "weekly" }, -- Marrowfang, Necrotic Wake Mythic
  [1481] = { instance = 2441, boss = "So'leah", difficulties = { 23 }, reset = "weekly" }, -- Cartel Master's Gearglider; Heroic is repeatable (not saved), Mythic is the lockout
  [1500] = { instance = 2450, boss = "The Nine", difficulties = { 14, 15, 16 }, reset = "weekly" }, -- LFR untracked; Sanctum Gloomcharger
  [1471] = { instance = 2450, boss = "Sylvanas Windrunner", difficulties = { 16 }, reset = "weekly" }, -- Vengeance, Mythic only
  [1587] = { instance = 2481, boss = "The Jailer", difficulties = { 16 }, reset = "weekly" }, -- Zereth Overseer, Mythic only

  -- Dragonflight -------------------------------------------------------------
  -- Infinite Timereaver drops from any Timewalking boss (no lockout); "daily" is a pacing choice.
  -- Its Dawn of the Infinites route row uses BossLockouts["Chrono-Lord Deios"].
  [781]  = { manual = true, reset = "daily", repeatable = true }, -- Infinite Timereaver: any Timewalking dungeon boss, no lockout (repeatable)
  [1818] = { instance = 2549, boss = "Fyrakk the Blazing", difficulties = { 16 }, reset = "weekly" }, -- Anu'relos, Mythic only (Rarity: "Fyrakk") -- verify in game

  -- The War Within -----------------------------------------------------------
  [2119] = { instance = 2652, boss = "Void Speaker Eirich", difficulties = { 23 }, reset = "weekly" }, -- Stonevault Mechsuit, Mythic only
  [2204] = { instance = 2651, boss = "The Darkness", difficulties = { 23 }, reset = "weekly" }, -- Wick, Darkflame Cleft Mythic
  [2219] = { instance = 2657, boss = "Queen Ansurek", difficulties = { 14, 15, 16 }, reset = "weekly" }, -- LFR untracked; Sureki Skyrazor
  [2223] = { instance = 2657, boss = "Queen Ansurek", difficulties = { 16 }, reset = "weekly" }, -- Ascendant Skyrazor, Mythic only
  [2507] = { instance = 2769, boss = "Chrome King Gallywix", difficulties = { 14, 15, 16 }, reset = "weekly" }, -- LFR untracked; Prototype A.S.M.R. -- verify in game
  [2487] = { instance = 2769, boss = "Chrome King Gallywix", difficulties = { 16 }, reset = "weekly" }, -- The Big G, Mythic only (Rarity: "Gallywix") -- verify in game
  [2569] = { instance = 2810, boss = "Dimensius, the All-Devouring", difficulties = { 16 }, reset = "weekly" }, -- Unbound Star-Eater, Mythic only -- verify in game

  -- Midnight: instance IDs not known yet -> manual ticks. Replace with instance
  -- specs once `/azt dump` shows them (see docs/ingame-checklist.md).
  [2817] = { manual = true, reset = "weekly" }, -- Lucent Hawkstrider, Magisters' Terrace (Midnight) Mythic, Degentrius -- verify in game
  [2805] = { manual = true, reset = "weekly" }, -- Spectral Hawkstrider, Windrunner Spire Mythic, The Restless Heart -- verify in game
  [2607] = { manual = true, reset = "weekly" }, -- Ashes of Belo'ren, March on Quel'Danas Mythic, Midnight Falls -- verify in game
  [2950] = { manual = true, reset = "weekly" }, -- Luminous Sporeglider, Sporefall: Rotmire kills on 4 separate weeks -- verify in game
  [3058] = { manual = true, reset = "weekly" }, -- The Writhing Brood, Altar of Fangs Mythic, Zul'jan -- verify in game
  [3030] = { manual = true, reset = "weekly" }, -- Primeval Skyfriend, The Venomous Abyss Mythic, Ula'tek -- verify in game

  -- Holiday bosses (Ruling R3): the daily LFG reward marks the day's kill ---
  [219]  = { lfg = 285, reset = "daily" }, -- Headless Horseman's Mount
  [2623] = { lfg = 285, reset = "daily" }, -- The Headless Horseman's Ghoulish Charger
  [202]  = { lfg = 287, reset = "daily" }, -- Swift Brewfest Ram
  [226]  = { lfg = 287, reset = "daily" }, -- Great Brewfest Kodo
  [2640] = { lfg = 287, reset = "daily" }, -- Brewfest Bomber (overrides Rarity quest 91894)
  [352]  = { lfg = 288, reset = "daily" }, -- X-45 Heartbreaker
  [2328] = { lfg = 288, reset = "daily" }, -- Love Witch's Sweeper
  [2492] = { lfg = 288, reset = "daily" }, -- Spring Butterfly
}

-- Per-route-row overrides (Ruling R12): route boss name exactly as in
-- Data/Route.lua bosses[].boss -> spec, for rows whose mount's own spec above
-- describes a different source. Each name must belong to a single route node.
ns.Data.BossLockouts = {
  -- Dawn of the Infinites, Mythic: Chrono-Lord Deios can drop a Quantum Courser
  -- item that teaches an older dungeon mount (all rows of that node).
  ["Chrono-Lord Deios"] = { instance = 2579, boss = "Chrono-Lord Deios", difficulties = { 23 }, reset = "weekly" },
  -- Vault of Archavon: the other three watchers (Archavon is the mount spec itself).
  ["Koralon"] = { instance = 624, boss = "Koralon the Flame Watcher", difficulties = { 3, 4 }, reset = "weekly" }, -- verify in game
  ["Emalon"]  = { instance = 624, boss = "Emalon the Storm Watcher", difficulties = { 3, 4 }, reset = "weekly" }, -- verify in game
  ["Toravon"] = { instance = 624, boss = "Toravon the Ice Watcher", difficulties = { 3, 4 }, reset = "weekly" }, -- verify in game
}
