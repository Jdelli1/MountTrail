-- Fixture for tools/test_verify_data.py
local ADDON, ns = ...
ns.Data = ns.Data or {}

ns.Data.EventGroups = {
  ["Assault: Uldum"] = {
    kind = "assault", zone = "Uldum", maps = { 1527, 249 },
    pois = { [6487] = "Amathet", [6488] = "Aqir" },
  },
  ["Assault: Bad"] = {
    kind = "assault", zone = "Nowhere", maps = { 1527, 9999 },
    pois = { [6490] = "Mantid", [7777] = "Ghost" },
  },
  ["Warfront: Arathi"] = {
    kind = "warfront", zone = "Arathi Highlands", label = "Arathi", maps = { 14 },
    contribution = "Battle for Stromgarde", contributions = { 11, 116, 555 },
  },
}
