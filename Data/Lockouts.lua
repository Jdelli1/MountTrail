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
--   { camp=true, zone="<Zone>" }: a rare spawn with no known kill flag and no
--     reset (long-respawn rares: owner ruling). No reset, no tick, never "done",
--     no attempts: the checklist lists it under "Rare Spawns (no lockout)" by
--     expansion and zone until the mount is owned, with a box recording when
--     the player last checked the spawn. `zone` is a Zone / Location of the
--     mount's Mount.db2 SourceText (tools/verify_data.py check 7); omitted when
--     the source text names none.
--   repeatable=true: no lockout at all (run as often as you like): a route
--   step, never a daily / weekly checklist entry
-- Mounts with a Rarity quest flag (Data/Mounts.lua `quest`) and no entry here are
-- treated as { quest=<that quest>, reset=Lockouts.QuestReset(mount) }: "daily" for a
-- SimpleArmory group "Rare Spawn" (or ending in " Rare Spawn", or a BfA zone-rare group
-- starting "Warfront: " / "Assault: "), else "weekly" (MoP
-- world bosses, Rukhmar: group "World Boss"). An entry here always wins.
--
-- Difficulty IDs: 1 Normal dungeon, 2 Heroic dungeon, 23 Mythic dungeon,
-- 3/4 10/25 Normal legacy raid, 5/6 10/25 Heroic legacy raid, 9 40-player,
-- 14 Normal, 15 Heroic, 16 Mythic, 17 LFR. Old raids the game now saves as
-- size-free Normal / Heroic (Firelands): a 3 / 4 entry is also met by a 14
-- kill, a 5 / 6 entry by a 15 kill (Lockouts.LEGACY_AS).
-- LFR (17) is not tracked in v1 (Ruling R10): LFR kills are not expected to show up
-- in the saved-instance list, so a spec listing 17 could never complete.
--
-- Boss names match the saved-instance list when either contains the other,
-- case-insensitively (Logic/Lockouts.lua): "Harlan Sweete" matches "Lord Harlan
-- Sweete", "High Tinker Mekkatorque" matches "Mekkatorque".
--
-- Boss encounter names and difficulties partly derived from Rarity
-- (https://github.com/WowRarity/Rarity, DB/Mounts/*.lua `lockBossName`,
-- `instanceDifficulties`, `lockDungeonId`), GPL-2.0.
-- Entries marked `-- verify in game` are unconfirmed: check them with `/mtrail dump`
-- (docs/BETA_TESTING.md lists what to check in game).

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
  -- Bronze Drake: "Infinite Corruptor" (the timed heroic's bonus boss) is neither a JournalEncounter nor a
  -- DungeonEncounter of The Culling of Stratholme (map 595) in the game's tables (tools/verify_data.py,
  -- build 12.1.5.70448: only Meathook, Salramm, Chrono-Lord Epoch, Mal'Ganis), so the saved-instance
  -- list can never name it: hand tick, no auto tick. Mount.db2 SourceText: "Drop: Infinite Corruptor".
  [248] = { manual = true, reset = "daily" }, -- Bronze Drake, Culling of Stratholme timed heroic -- verify in game

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
  -- Tanaan Jungle: Mount.db2 SourceText "Drop: Vengeance, Deathtalon, Terrorfist,
  -- Doomroller; Zone: Tanaan Jungle" for all three. Four rares, each its own daily
  -- kill (Rarity: questId { 39287, 39288, 39289, 39290 }, one per rare); the
  -- generated `quest` keeps only Deathtalon's 39287, which would tick (and merge)
  -- all three on one kill of four. One row per mount, ticked by hand.
  [611] = { manual = true, reset = "daily" }, -- Tundra Icehoof: four Tanaan rares, no single kill flag -- hand tick
  [622] = { manual = true, reset = "daily" }, -- Armored Razorback: four Tanaan rares, no single kill flag -- hand tick
  [643] = { manual = true, reset = "daily" }, -- Warsong Direfang: four Tanaan rares, no single kill flag -- hand tick
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
  -- Tomb Stalker: JournalEncounter 2172 "Dazar, The First King" links (DungeonEncounterID) to DungeonEncounter
  -- 2143 "King Dazar" on map 1762 (tools/verify_data.py, build 12.1.5.70448); "Dazar" is contained in both and
  -- in no other King's Rest boss name.
  [1040] = { instance = 1762, boss = "Dazar", difficulties = { 23 }, reset = "weekly" }, -- Tomb Stalker, King's Rest Mythic -- verify in game
  [1053] = { instance = 1841, boss = "Unbound Abomination", difficulties = { 23 }, reset = "weekly" }, -- Underrot Crawg, Underrot Mythic
  [1252] = { instance = 2097, boss = "HK-8 Aerial Oppression Unit", difficulties = { 23 }, reset = "weekly" }, -- Mechagon Peacekeeper, Mythic
  [1227] = { instance = 2097, boss = "King Mechagon", difficulties = { 23 }, reset = "weekly" }, -- Aerial Unit R-21/X, Mythic hard mode
  [1293] = { instance = 2217, boss = "N'Zoth the Corruptor", difficulties = { 16 }, reset = "weekly" }, -- Ny'alotha Allseer, Mythic only

  -- Shadowlands --------------------------------------------------------------
  -- Covenant rares SimpleArmory files under a covenant vendor group: Mount.db2
  -- SourceText names the rare ("Drop: <rare>; Covenant: ...; Zone: ..."), so their
  -- Rarity kill flag resets daily like every rare spawn, under Rares
  -- (tools/verify_data.py check 7, rare-quest-not-daily).
  [1310] = { quest = 59612, reset = "daily", category = "rares" }, -- Horrid Dredwing: Drop: Harika the Horrid, Revendreth
  [1370] = { quest = 58784, reset = "daily", category = "rares" }, -- Armored Bonehoof Tauralus: Drop: Sabriel the Bonecleaver, Maldraxxus
  [1393] = { quest = 61632, reset = "daily", category = "rares" }, -- Wild Glimmerfur Prowler: Drop: Valfir the Unrelenting, Ardenweald
  [1406] = { instance = 2286, boss = "Nalthor the Rimebinder", difficulties = { 23 }, reset = "weekly" }, -- Marrowfang, Necrotic Wake Mythic
  [1481] = { instance = 2441, boss = "So'leah", difficulties = { 23 }, reset = "weekly" }, -- Cartel Master's Gearglider; Heroic is repeatable (not saved), Mythic is the lockout
  [1500] = { instance = 2450, boss = "The Nine", difficulties = { 14, 15, 16 }, reset = "weekly" }, -- LFR untracked; Sanctum Gloomcharger
  [1471] = { instance = 2450, boss = "Sylvanas Windrunner", difficulties = { 16 }, reset = "weekly" }, -- Vengeance, Mythic only
  [1587] = { instance = 2481, boss = "The Jailer", difficulties = { 16 }, reset = "weekly" }, -- Zereth Overseer, Mythic only

  -- Dragonflight -------------------------------------------------------------
  -- Infinite Timereaver drops from any Timewalking boss (no lockout); "daily" is a pacing choice.
  [781]  = { manual = true, reset = "daily", repeatable = true }, -- Infinite Timereaver: any Timewalking dungeon boss, no lockout (repeatable)
  [1818] = { instance = 2549, boss = "Fyrakk the Blazing", difficulties = { 16 }, reset = "weekly" }, -- Anu'relos, Mythic only (Rarity: "Fyrakk") -- verify in game

  -- The War Within -----------------------------------------------------------
  -- No Stonevault Mechsuit (2119) spec: Mount.db2 SourceText "Quest: Repurposed, Restored" and it is not in
  -- Void Speaker Eirich's journal loot (tools/verify_data.py, build 12.1.5.70448): a quest reward, no lockout.
  [2204] = { instance = 2651, boss = "The Darkness", difficulties = { 23 }, reset = "weekly" }, -- Wick, Darkflame Cleft Mythic
  [2219] = { instance = 2657, boss = "Queen Ansurek", difficulties = { 14, 15, 16 }, reset = "weekly" }, -- LFR untracked; Sureki Skyrazor
  [2223] = { instance = 2657, boss = "Queen Ansurek", difficulties = { 16 }, reset = "weekly" }, -- Ascendant Skyrazor, Mythic only
  [2507] = { instance = 2769, boss = "Chrome King Gallywix", difficulties = { 14, 15, 16 }, reset = "weekly" }, -- LFR untracked; Prototype A.S.M.R. -- verify in game
  [2487] = { instance = 2769, boss = "Chrome King Gallywix", difficulties = { 16 }, reset = "weekly" }, -- The Big G, Mythic only (Rarity: "Gallywix") -- verify in game
  [2569] = { instance = 2810, boss = "Dimensius, the All-Devouring", difficulties = { 16 }, reset = "weekly" }, -- Unbound Star-Eater, Mythic only -- verify in game

  -- Midnight: instance = JournalInstance MapID, boss = DungeonEncounter name,
  -- loot from JournalEncounterItem (DB2 build 12.1.5.70448). Difficulty from
  -- the Mount.db2 source text "(Mythic)" (dungeons 23, raids 16).
  -- Lucent Hawkstrider: JournalInstance 1300 Magisters' Terrace (MapID 2811), DungeonEncounter 3074 "Degentrius", item 260231 -- difficulty: verify in game
  [2817] = { instance = 2811, boss = "Degentrius", difficulties = { 23 }, reset = "weekly" },
  -- Spectral Hawkstrider: JournalInstance 1299 Windrunner Spire (MapID 2805), DungeonEncounter 3059 "Restless Heart" (journal: The Restless Heart), item 262914 -- difficulty: verify in game
  [2805] = { instance = 2805, boss = "Restless Heart", difficulties = { 23 }, reset = "weekly" },
  -- Ashes of Belo'ren: JournalInstance 1308 March on Quel'Danas (MapID 2913, LfgDungeons TypeID 2 raid), DungeonEncounter 3183 "Midnight Falls", item 246590 -- difficulty: verify in game
  [2607] = { instance = 2913, boss = "Midnight Falls", difficulties = { 16 }, reset = "weekly" },
  [2950] = { manual = true, reset = "weekly" }, -- Luminous Sporeglider, Sporefall: Rotmire kills on 4 separate weeks (multi-week mechanic: hand ticks) -- verify in game
  -- The Writhing Brood: JournalInstance 1322 Altar of Fangs (MapID 2993), DungeonEncounter 3458 "Zul'jan", item 276804 -- difficulty: verify in game (its source text names no difficulty)
  [3058] = { instance = 2993, boss = "Zul'jan", difficulties = { 23 }, reset = "weekly" },
  -- Primeval Skyfriend: JournalInstance 1320 The Venomous Abyss (MapID 3004, LfgDungeons TypeID 2 raid, 14/15/16), DungeonEncounter 3492 "Ula'tek", item 275658 -- difficulty: verify in game
  [3030] = { instance = 3004, boss = "Ula'tek", difficulties = { 16 }, reset = "weekly" },

  -- Rare Spawns with no known kill flag (camp specs) ------------------------
  -- Mount.db2 SourceText "Drop: <creature>" (tools/verify_data.py check 7, build
  -- 12.1.5.70448), not Encounter Journal loot, no Rarity quest: no daily lockout
  -- (owner: long-respawn rares). zone = the source text's Zone / Location.
  -- Wrath of the Lich King
  [265] = { camp = true, zone = "The Storm Peaks" }, -- Time-Lost Proto-Drake: Drop: Time-Lost Proto-Drake
  -- Cataclysm
  [393] = { camp = true, zone = "Deepholm" }, -- Phosphorescent Stone Drake: Drop: Aeonaxx
  [400] = { camp = true, zone = "Feralas" }, -- Grey Riding Camel: Drop: Dormus the Camel-Hoarder
  [420] = { camp = true, zone = "Vashj'ir" }, -- Subdued Seahorse: Drop: Poseidus
  -- Mists of Pandaria
  [517] = { camp = true, zone = "Vale of Eternal Blossoms" }, -- Thundering Ruby Cloud Serpent: Drop: Alani
  [534] = { camp = true, zone = "Dread Wastes, Kun-Lai Summit, Townlong Steppes, Valley of the Four Winds" }, -- Amber Primordial Direhorn: Drop: Zandalari Warbringer
  [535] = { camp = true, zone = "Dread Wastes, Krasarang Wilds, Kun-Lai Summit, Townlong Steppes, Valley of the Four Winds" }, -- Slate Primordial Direhorn: Drop: Zandalari Warbringer
  [536] = { camp = true, zone = "Dread Wastes, Kun-Lai Summit, Townlong Steppes, Valley of the Four Winds" }, -- Jade Primordial Direhorn: Drop: Zandalari Warbringer
  [561] = { camp = true, zone = "Timeless Isle" }, -- Thundering Onyx Cloud Serpent: Drop: Huolon
  -- Warlords of Draenor
  [612] = { camp = true, zone = "Nagrand" }, -- Bloodhoof Bull: Drop: Nakk the Thunderer
  [614] = { camp = true, zone = "Nagrand" }, -- Mottled Meadowstomper: Drop: Luk'hok
  [627] = { camp = true, zone = "Frostfire Ridge" }, -- Great Greytusk: Drop: Gorok
  [630] = { camp = true, zone = "Talador" }, -- Sapphire Riverbeast: Drop: Silthide
  [636] = { camp = true, zone = "Shadowmoon Valley" }, -- Swift Breezestrider: Drop: Pathrunner
  [655] = { camp = true, zone = "Gorgrond" }, -- Sunhide Gronnling: Drop: Poundfist
  [657] = { camp = true, zone = "Frostfire Ridge" }, -- Garn Nighthowl: Drop: Nok-Karosh
  -- Battle for Azeroth
  [1057] = { camp = true, zone = "Stormsong Valley" }, -- Nazjatar Blood Serpent: Drop: Adherent of the Abyss
  [1201] = { camp = true, zone = "Darkshore" }, -- Frightened Kodo: Drop: Frightened Kodo
  [1258] = { camp = true }, -- Fabious: Drop: Fabious (the source text names no zone)
  [1311] = { camp = true, zone = "Vale of Eternal Blossoms" }, -- Ivory Cloud Serpent: Drop: Ivory Cloud Serpent
  -- Shadowlands
  [803]  = { camp = true, zone = "Korthia" }, -- Mastercraft Gravewing: Drop: Stygian Stonecrusher
  [1306] = { camp = true, zone = "Ardenweald" }, -- Swift Gloomhoof: Drop: Night Mare
  [1307] = { camp = true, zone = "Bastion" }, -- Sundancer: Drop: Sundancer
  [1362] = { camp = true, zone = "Ardenweald" }, -- Spinemaw Gladechewer: Drop: Gormtamer Tizo
  [1415] = { camp = true, zone = "Ardenweald" }, -- Arboreal Gulper: Drop: Humon'gozz
  [1434] = { camp = true, zone = "Zereth Mortis" }, -- Deepstar Aurelid: Drop: Hirukon
  [1449] = { camp = true, zone = "Korthia" }, -- Lord of the Corpseflies: Drop: Fleshwing
  [1487] = { camp = true, zone = "Korthia" }, -- Summer Wilderling: Drop: Escaped Wilderling
  [1493] = { camp = true, zone = "Korthia" }, -- Forsworn Aquilon: Drop: Wild Worldcracker
  [1502] = { camp = true, zone = "The Maw" }, -- Fallen Charger: Drop: Fallen Charger
  [1584] = { camp = true }, -- Colossal Plaguespew Mawrat: Drop: Rhuv, Gorger of Ruin (no zone in the source text) -- verify in game
  -- Dragonflight
  [1553] = { camp = true, zone = "The Azure Span" }, -- Liberated Slyvern: Drop: Breezebiter
  -- The War Within
  [2176] = { camp = true, zone = "Isle of Dorn" }, -- Alunira: Drop: Alunira
  [2601] = { camp = true, zone = "K'aresh" }, -- Pearlescent Krolusk: Drop: Urmag
  [2603] = { camp = true, zone = "K'aresh" }, -- Sthaarbs's Last Lunch: Drop: Sthaarbs
  -- Midnight
  [2749] = { camp = true, zone = "Harandar" }, -- Echo of Aln'sharan: Drop: Aln'Sharan
  [3031] = { camp = true }, -- Hexflame Reaver: Drop: Ral'kala (SimpleArmory "Prey Drop"; no zone in the source text) -- verify in game
  -- Not here (tools/verify_allow.json "rares"): Fathom Dweller (Kosumoth, a
  -- world-quest boss), Netherlord's Accursed Wrathsteed (warlock Class Hall),
  -- Mail Muncher (Horrific Visions) and the Visions Revisited mounts: instanced
  -- or summoned, not world rares.

  -- Holiday bosses (Ruling R3): the daily LFG reward marks the day's kill ---
  [219]  = { lfg = 285, reset = "daily" }, -- Headless Horseman's Mount
  [2623] = { lfg = 285, reset = "daily" }, -- The Headless Horseman's Ghoulish Charger
  [202]  = { lfg = 287, reset = "daily" }, -- Swift Brewfest Ram
  [226]  = { lfg = 287, reset = "daily" }, -- Great Brewfest Kodo
  [2640] = { lfg = 287, reset = "daily" }, -- Brewfest Bomber (overrides Rarity quest 91894)
  [352]  = { lfg = 288, reset = "daily" }, -- X-45 Heartbreaker
  [2328] = { lfg = 288, reset = "daily" }, -- Love Witch's Sweeper
  [2492] = { lfg = 288, reset = "daily" }, -- Spring Butterfly
  [3036] = { lfg = 286, reset = "daily" }, -- Sun Festival's Painted Roc: Ahune (LfgDungeons 286, tools/verify_data.py) -- verify in game
}

-- Per-route-row overrides (Ruling R12): route boss name exactly as in
-- Data/Route.lua bosses[].boss -> spec, for rows whose mount's own spec above
-- describes a different source. Each name must belong to a single route node.
ns.Data.BossLockouts = {
  -- Vault of Archavon: the other three watchers (Archavon is the mount spec itself).
  ["Koralon"] = { instance = 624, boss = "Koralon the Flame Watcher", difficulties = { 3, 4 }, reset = "weekly", exp = "Wrath of the Lich King" }, -- verify in game
  ["Emalon"]  = { instance = 624, boss = "Emalon the Storm Watcher", difficulties = { 3, 4 }, reset = "weekly", exp = "Wrath of the Lich King" }, -- verify in game
  ["Toravon"] = { instance = 624, boss = "Toravon the Ice Watcher", difficulties = { 3, 4 }, reset = "weekly", exp = "Wrath of the Lich King" }, -- verify in game
}
