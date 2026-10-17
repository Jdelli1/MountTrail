-- Hand-written lockout data: mountID -> how this character's chance at the
-- mount is spent and when it comes back (read by Logic/Lockouts.lua). Shapes:
--   { instance=<GetSavedInstanceInfo return 14>, boss="<GetSavedInstanceEncounterInfo name, enUS>",
--     difficulties={<difficultyID>...}, reset="daily"|"weekly" }  -- done when killed on EVERY listed difficulty
--   { quest=<questID>, reset=... }   { lfg=<LFG dungeonID>, reset="daily" }   { manual=true, reset=... }
--   any spec may add requires={ quest=<questID>, text="<unlock needed>" }
-- Mounts with a Rarity quest flag (Data/Mounts.lua `quest`) and no entry here are
-- treated as { quest=<that quest>, reset="weekly" } (MoP world bosses, Rukhmar).
--
-- Difficulty IDs: 1 Normal dungeon, 2 Heroic dungeon, 23 Mythic dungeon,
-- 3/4 10/25 Normal legacy raid, 5/6 10/25 Heroic legacy raid, 9 40-player,
-- 14 Normal, 15 Heroic, 16 Mythic, 17 LFR.
-- For a mount that drops on "any difficulty" one difficulty is listed (the run the
-- route plans for); several are listed only where each is a separate weekly chance.
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
  [69]  = { manual = true, reset = "daily" },  -- Rivendare's Deathcharger: Stratholme is normal-only, never saved
  [168] = { instance = 532, boss = "Attumen the Huntsman", difficulties = { 3 }, reset = "weekly" }, -- Fiery Warhorse, Karazhan (10-player) -- verify in game
  [183] = { instance = 550, boss = "Kael'thas Sunstrider", difficulties = { 4 }, reset = "weekly" }, -- Ashes of Al'ar, Tempest Keep (25-player) -- verify in game
  [185] = { instance = 556, boss = "Anzu", difficulties = { 2 }, reset = "daily" }, -- Raven Lord, Sethekk Halls -- verify in game
  [213] = { instance = 585, boss = "Kael'thas Sunstrider", difficulties = { 2 }, reset = "daily" }, -- Swift White Hawkstrider, Magisters' Terrace

  -- Wrath of the Lich King ---------------------------------------------------
  [349] = { instance = 249, boss = "Onyxia", difficulties = { 4 }, reset = "weekly" }, -- Onyxian Drake, any size; 25 planned -- verify in game
  [363] = { instance = 631, boss = "The Lich King", difficulties = { 6 }, reset = "weekly" }, -- Invincible, Heroic 25 only
  -- Vault of Archavon: all four bosses drop it; the spec follows Archavon (Rarity's lock boss).
  [286] = { instance = 624, boss = "Archavon the Stone Watcher", difficulties = { 4 }, reset = "weekly" }, -- Grand Black War Mammoth (A) -- verify in game
  [287] = { instance = 624, boss = "Archavon the Stone Watcher", difficulties = { 4 }, reset = "weekly" }, -- Grand Black War Mammoth (H) -- verify in game
  [246] = { instance = 616, boss = "Malygos", difficulties = { 4 }, reset = "weekly" }, -- Azure Drake, any size -- verify in game
  [247] = { instance = 616, boss = "Malygos", difficulties = { 4 }, reset = "weekly" }, -- Blue Drake, any size -- verify in game
  [253] = { instance = 615, boss = "Sartharion", difficulties = { 3 }, reset = "weekly" }, -- Black Drake, 10-player, 3 drakes up
  [250] = { instance = 615, boss = "Sartharion", difficulties = { 4 }, reset = "weekly" }, -- Twilight Drake, 25-player, 3 drakes up
  [264] = { instance = 575, boss = "Skadi the Ruthless", difficulties = { 2 }, reset = "daily" }, -- Blue Proto-Drake, Utgarde Pinnacle heroic
  [304] = { instance = 603, boss = "Yogg-Saron", difficulties = { 14 }, reset = "weekly" }, -- Mimiron's Head, Ulduar (Rarity: difficulty 14) -- verify in game
  [248] = { instance = 595, boss = "Infinite Corruptor", difficulties = { 2 }, reset = "daily" }, -- Bronze Drake, Culling of Stratholme timed heroic -- verify in game

  -- Cataclysm ----------------------------------------------------------------
  [395] = { instance = 657, boss = "Altairus", difficulties = { 2 }, reset = "daily" }, -- Drake of the North Wind, Vortex Pinnacle heroic (normal is never saved)
  [397] = { instance = 725, boss = "Slabhide", difficulties = { 2 }, reset = "daily" }, -- Vitreous Stone Drake, Stonecore heroic (normal is never saved)
  [396] = { instance = 754, boss = "Al'Akir", difficulties = { 4 }, reset = "weekly" }, -- Drake of the South Wind, any size; 25 planned -- verify in game
  -- Firelands: the route runs it on both Normal and Heroic.
  [425] = { instance = 720, boss = "Alysrazor", difficulties = { 4, 6 }, reset = "weekly" }, -- Flametalon of Alysrazor -- verify in game
  [415] = { instance = 720, boss = "Ragnaros", difficulties = { 4, 6 }, reset = "weekly" }, -- Pureblood Fire Hawk -- verify in game
  -- Dragon Soul: one 25 Heroic run covers all three (Handmaiden is heroic only).
  [445] = { instance = 967, boss = "Ultraxion", difficulties = { 6 }, reset = "weekly" }, -- Experiment 12-B -- verify in game
  [442] = { instance = 967, boss = "Madness of Deathwing", difficulties = { 6 }, reset = "weekly" }, -- Blazing Drake -- verify in game
  [444] = { instance = 967, boss = "Madness of Deathwing", difficulties = { 6 }, reset = "weekly" }, -- Life-Binder's Handmaiden, heroic only -- verify in game
  [411] = { instance = 859, boss = "High Priestess Kilnara", difficulties = { 2 }, reset = "daily" }, -- Swift Zulian Panther, Zul'Gurub heroic
  [410] = { instance = 859, boss = "Bloodlord Mandokir", difficulties = { 2 }, reset = "daily" }, -- Armored Razzashi Raptor, Zul'Gurub heroic
  -- Zul'Aman: the bear is the timed-run chest, not a boss; the daily heroic lockout is tracked via the last boss.
  [419] = { instance = 568, boss = "Daakara", difficulties = { 2 }, reset = "daily" }, -- Amani Battle Bear -- verify in game

  -- Mists of Pandaria (world bosses Galleon, Sha of Anger, Oondasta, Nalak use their Rarity quest) --
  [478] = { instance = 1008, boss = "Elegon", difficulties = { 4 }, reset = "weekly" }, -- Astral Cloud Serpent, not LFR; 25 Normal planned -- verify in game
  [531] = { instance = 1098, boss = "Horridon", difficulties = { 4 }, reset = "weekly" }, -- Spawn of Horridon, Normal/Heroic -- verify in game
  [543] = { instance = 1098, boss = "Ji-Kun", difficulties = { 4 }, reset = "weekly" }, -- Clutch of Ji-Kun, Normal/Heroic -- verify in game
  [559] = { instance = 1136, boss = "Garrosh Hellscream", difficulties = { 16 }, reset = "weekly" }, -- Kor'kron Juggernaut, Mythic only

  -- Warlords of Draenor (Rukhmar uses its Rarity quest) ----------------------
  [751] = { instance = 1448, boss = "Archimonde", difficulties = { 16 }, reset = "weekly" }, -- Felsteel Annihilator, Mythic only
  [613] = { instance = 1205, boss = "Blackhand", difficulties = { 16 }, reset = "weekly" }, -- Ironhoof Destroyer, Mythic only

  -- Legion -------------------------------------------------------------------
  [791] = { instance = 1530, boss = "Gul'dan", difficulties = { 14, 15, 16 }, reset = "weekly" }, -- Felblaze Infernal, Normal/Heroic/Mythic
  [633] = { instance = 1530, boss = "Gul'dan", difficulties = { 16 }, reset = "weekly" }, -- Hellfire Infernal, Mythic only
  [899] = { instance = 1676, boss = "Mistress Sassz'ine", difficulties = { 17, 14, 15, 16 }, reset = "weekly" }, -- Abyss Worm
  [971] = { instance = 1712, boss = "Felhounds of Sargeras", difficulties = { 17, 14, 15, 16 }, reset = "weekly" }, -- Antoran Charhound
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
  [1500] = { instance = 2450, boss = "The Nine", difficulties = { 17, 14, 15, 16 }, reset = "weekly" }, -- Sanctum Gloomcharger
  [1471] = { instance = 2450, boss = "Sylvanas Windrunner", difficulties = { 16 }, reset = "weekly" }, -- Vengeance, Mythic only
  [1587] = { instance = 2481, boss = "The Jailer", difficulties = { 16 }, reset = "weekly" }, -- Zereth Overseer, Mythic only

  -- Dragonflight -------------------------------------------------------------
  -- Infinite Timereaver is on the route only via the Quantum Courser drop in Dawn of the Infinites.
  -- (The other Quantum Courser mounts keep the spec of their original source above.)
  [781]  = { instance = 2579, boss = "Chrono-Lord Deios", difficulties = { 23 }, reset = "weekly" }, -- Infinite Timereaver
  [1818] = { instance = 2549, boss = "Fyrakk the Blazing", difficulties = { 16 }, reset = "weekly" }, -- Anu'relos, Mythic only (Rarity: "Fyrakk") -- verify in game

  -- The War Within -----------------------------------------------------------
  [2119] = { instance = 2652, boss = "Void Speaker Eirich", difficulties = { 23 }, reset = "weekly" }, -- Stonevault Mechsuit, Mythic only
  [2204] = { instance = 2651, boss = "The Darkness", difficulties = { 23 }, reset = "weekly" }, -- Wick, Darkflame Cleft Mythic
  [2219] = { instance = 2657, boss = "Queen Ansurek", difficulties = { 17, 14, 15, 16 }, reset = "weekly" }, -- Sureki Skyrazor
  [2223] = { instance = 2657, boss = "Queen Ansurek", difficulties = { 16 }, reset = "weekly" }, -- Ascendant Skyrazor, Mythic only
  [2507] = { instance = 2769, boss = "Chrome King Gallywix", difficulties = { 17, 14, 15, 16 }, reset = "weekly" }, -- Prototype A.S.M.R. -- verify in game
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
