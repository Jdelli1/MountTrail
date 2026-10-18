-- Fixture for tools/test_verify_data.py
local ADDON, ns = ...
ns.Data = ns.Data or {}

ns.Data.Holidays = {
  hallowsend = { title = "Hallow's End", lfg = 285, mounts = { 15 } },
  midsummer = { title = "Midsummer Fire Festival", lfg = 286, mounts = { 21 } },
  brewfest = { title = "Brewfest", lfg = 287, mounts = { 22 } },
  noblegarden = { title = "Noblegarden", mounts = {} },
}
