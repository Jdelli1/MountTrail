-- Hand-written data for the live status of event rares (F17): SimpleArmory
-- mount group (Data/Mounts.lua `group`) -> where the game reports that
-- event's state. Every ID is the game's own, checked by
-- `python tools/verify_data.py` (check 4) against the DB2 tables of
-- Retail 12.1.5.70448 (wago.tools):
--   * pois: AreaPOI.db2 ID -> the assault's short name; AreaPOI Name_lang is
--     "Assault: <name>" (6486-6488: Kalimdor, 6489-6491: Pandaria).
--   * contributions: Contribution.db2 IDs whose Name_lang is `contribution`
--     (two rows per warfront, one per faction; which is which is not in the
--     client's data).
--   * maps: UiMap.db2 IDs named `zone`; Uldum and the Vale have two zone
--     maps each (AlternateUiMapGroup 1 / 2), the N'Zoth one first.
-- Which assault a rare belongs to is not in the client's data (the rares'
-- Vignette rows carry no PlayerCondition, the six assault AreaPOIs share one,
-- and Mount.db2 source texts name only the zone), so assault rares get the
-- zone's current assault as information, never "up" / "not up".

local ADDON, ns = ...
ns.Data = ns.Data or {}

ns.Data.EventGroups = {
  ["Assault: Uldum"] = {
    kind = "assault",
    zone = "Uldum",
    maps = { 1527, 249 },
    pois = { [6486] = "N'Zoth", [6487] = "Amathet", [6488] = "Aqir" },
  },
  ["Assault: Vale of Eternal Blossoms"] = {
    kind = "assault",
    zone = "Vale of Eternal Blossoms",
    maps = { 1530, 390 },
    pois = { [6489] = "N'Zoth", [6490] = "Mogu", [6491] = "Mantid" },
  },
  ["Warfront: Arathi"] = {
    kind = "warfront",
    zone = "Arathi Highlands",
    label = "Arathi",
    maps = { 14 },
    contribution = "Battle for Stromgarde",
    contributions = { 11, 116 },
  },
  ["Warfront: Darkshore"] = {
    kind = "warfront",
    zone = "Darkshore",
    label = "Darkshore",
    maps = { 62 },
    contribution = "Battle for Darkshore",
    contributions = { 117, 118 },
  },
}
