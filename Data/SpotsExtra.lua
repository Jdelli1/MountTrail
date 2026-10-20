-- Hand-kept spots: where to find the NPC behind a mount when Data/Spots.lua
-- (generated from AllTheThings) has nothing, or has it incomplete. Same shape
-- as Data.Spots; entries here are added to the generated ones (Map.Spots).
--   [mountID] = { { name = "NPC name", kind = "drop" | "vendor", faction =
--     "Alliance" | "Horde" (optional), quest = daily kill quest (optional),
--     pts = { uiMapID, x, y, uiMapID, x, y, ... } } },  -- x / y in percent
-- Coordinates checked in game by the owner. Never copy them from sites whose
-- terms forbid it.

local ADDON, ns = ...
ns.Data = ns.Data or {}

ns.Data.SpotsExtra = {
}
